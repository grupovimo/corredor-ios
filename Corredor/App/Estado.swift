import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// La sesión como la devuelve la API (`GET /v1/auth/sesion`, `PUT /v1/auth/inmobiliaria`).
struct Sesion: Codable, Equatable {
    struct Usuario: Codable, Equatable {
        var id: String
        var email: String
        var nombre: String
        var apellido: String
        var foto: String?
        var tourVisto: Bool?

        var completo: String { [nombre, apellido].filter { !$0.isEmpty }.joined(separator: " ").isEmpty ? email : [nombre, apellido].filter { !$0.isEmpty }.joined(separator: " ") }
    }
    struct Membresia: Codable, Equatable, Identifiable, Hashable {
        var inmobiliariaId: String
        var slug: String
        var nombre: String
        var rol: String
        var id: String { inmobiliariaId }
    }
    var usuario: Usuario
    var inmobiliariaId: String?
    var rol: String?
    var inmobiliarias: [Membresia]
}

/// Lo que devuelve `POST /v1/auth/clerk`: el token y la sesión.
struct Ingreso: Decodable {
    var token: String
    var usuario: Sesion.Usuario
    var inmobiliariaId: String?
    var rol: String?
    var inmobiliarias: [Sesion.Membresia]

    var sesion: Sesion { Sesion(usuario: usuario, inmobiliariaId: inmobiliariaId, rol: rol, inmobiliarias: inmobiliarias) }
}

/// El aviso de abajo (handoff · «Deshacer en vez de confirmar»): 5 s, con «Deshacer» si se puede.
struct Aviso: Identifiable, Equatable {
    let id = UUID()
    var texto: String
    var ok = true
    var deshacer: (() -> Void)?
    /// La sugerencia del paso siguiente («Publicar», «Cargar contrato»): su texto y qué hace.
    var accion: (String, () -> Void)?

    static func == (a: Aviso, b: Aviso) -> Bool { a.id == b.id }
}

/// El estado de la app: la sesión (token en el Keychain), la inmobiliaria y el rol, la pestaña y la
/// navegación, el aviso con «Deshacer» y la cola sin conexión. Lo comparten todas las pantallas.
@Observable
@MainActor
final class Estado {
    enum Fase: Equatable {
        case arrancando
        /// 1A–1B: bienvenida e ingreso con Apple o Google.
        case afuera
        /// 1C: trabaja en más de una inmobiliaria (o en ninguna todavía).
        case eligiendo
        case adentro
    }

    var fase: Fase = .arrancando
    let api: Api
    var sesion: Sesion?
    var aviso: Aviso?
    /// Pantalla bloqueada con Face ID (1D) hasta que la persona se identifique.
    var bloqueada = false
    /// La pestaña elegida y lo apilado en cada una.
    var pestana: Pestana = .inicio
    var pilas: [Pestana: NavigationPath] = [:]
    /// MIRA se abre a pantalla completa desde el botón del centro.
    var miraAbierta = false
    /// Se sube después de cada cambio para que las listas se vuelvan a pedir.
    var version = 0
    /// Insignias de la barra (mensajes sin leer, avisos).
    var sinLeer = 0
    var avisosPendientes = 0
    /// El recorrido de la primera vez (también se vuelve a ver desde «Más»).
    var mostrarRecorrido = false
    /// Conectado al stream de cambios (App/Vivo.swift); sin él, el chat vuelve a consultar cada tanto.
    var enVivo = false
    @ObservationIgnored var recargaVivo: Task<Void, Never>?
    let cola: Cola
    private(set) var tokenPush: String?
    private var avisoTarea: Task<Void, Never>?

    var conFaceID: Bool {
        get { UserDefaults.standard.bool(forKey: "faceID") }
        set { UserDefaults.standard.set(newValue, forKey: "faceID") }
    }

    init(api: Api? = nil) {
        let a = api ?? Api(base: Api.urlConfigurada(), token: Llavero.leer("token"))
        self.api = a
        cola = Cola(api: a)
        a.alPerderSesion = { [weak self] in self?.sesionPerdida() }
        cola.alSubir = { [weak self] in self?.version += 1 }
    }

    var usuario: Sesion.Usuario? { sesion?.usuario }
    var inmobiliaria: Sesion.Membresia? { sesion?.inmobiliarias.first { $0.inmobiliariaId == sesion?.inmobiliariaId } }
    var rol: String { sesion?.rol ?? "lector" }
    var esDuenio: Bool { rol == "duenio" }
    /// Agente o dueño: puede cargar y cambiar cosas (el lector sólo mira).
    var escribe: Bool { rol != "lector" }

    // MARK: Arranque

    func arrancar() async {
        guard api.token != nil else {
            fase = .afuera
            return
        }
        do {
            try await cargarSesion()
            if conFaceID { bloqueada = true }
            entrarSegunInmobiliaria()
        } catch let e as ErrorApi where e.sinConexion {
            // Sin señal se entra igual con lo guardado (E4: «Sin conexión»).
            sesion = Guardado.leer(Sesion.self, clave: "sesion")?.0
            if conFaceID { bloqueada = true }
            fase = sesion?.inmobiliariaId == nil ? .afuera : .adentro
        } catch {
            olvidarSesion()
            fase = .afuera
        }
    }

    private func cargarSesion() async throws {
        let s: Sesion = try await api.get("/v1/auth/sesion")
        sesion = s
        Guardado.guardar(s, clave: "sesion")
        SesionCompartida.guardar(token: api.token, api: api.base)
    }

    private func entrarSegunInmobiliaria() {
        guard let s = sesion else { fase = .afuera; return }
        if let t = invitacionPendiente, s.inmobiliariaId == nil {
            // Recién entra y lo invitaron: mientras se acepta, la pantalla de elegir.
            fase = .eligiendo
            Task { await aceptarInvitacion(t) }
        } else if s.inmobiliariaId == nil || (s.inmobiliarias.count > 1 && !UserDefaults.standard.bool(forKey: "eligio-\(s.usuario.id)")) {
            fase = .eligiendo
        } else {
            fase = .adentro
            Spotlight.indexarSecciones(duenio: esDuenio)
            Task { await despuesDeEntrar() }
        }
    }

    private func despuesDeEntrar() async {
        if let t = invitacionPendiente { await aceptarInvitacion(t) }
        await pedirPermisoPush()
        cola.subir()
    }

    // MARK: Ingreso (1B)

    func ingresarConApple() async throws {
        guard let clerk = Clerk(publicable: Bundle.main.object(forInfoDictionaryKey: "ClerkPublicable") as? String) else {
            throw Clerk.ErrorClerk(codigo: "sin_clave")
        }
        let tokenApple = try await HojaApple().pedirToken()
        try await canjear(try await clerk.conApple(tokenApple: tokenApple))
    }

    func ingresarConGoogle() async throws {
        guard let clerk = Clerk(publicable: Bundle.main.object(forInfoDictionaryKey: "ClerkPublicable") as? String) else {
            throw Clerk.ErrorClerk(codigo: "sin_clave")
        }
        try await canjear(try await clerk.conGoogle())
    }

    /// 1B «Entrar con mail»: manda el código.
    func pedirCodigo(email: String) async throws -> Clerk.IntentoMail {
        guard let clerk = Clerk(publicable: Bundle.main.object(forInfoDictionaryKey: "ClerkPublicable") as? String) else {
            throw Clerk.ErrorClerk(codigo: "sin_clave")
        }
        return try await clerk.pedirCodigo(email: email)
    }

    func ingresarConCodigo(_ i: Clerk.IntentoMail, codigo: String) async throws {
        guard let clerk = Clerk(publicable: Bundle.main.object(forInfoDictionaryKey: "ClerkPublicable") as? String) else {
            throw Clerk.ErrorClerk(codigo: "sin_clave")
        }
        try await canjear(try await clerk.conCodigo(i, codigo: codigo))
    }

    private func canjear(_ jwt: String) async throws {
        struct Cuerpo: Encodable { var token: String }
        let i: Ingreso = try await api.enviar("POST", "/v1/auth/clerk", Cuerpo(token: jwt))
        Llavero.guardar(i.token, cuenta: "token")
        api.token = i.token
        Guardado.borrarTodo()
        sesion = i.sesion
        Guardado.guardar(i.sesion, clave: "sesion")
        SesionCompartida.guardar(token: i.token, api: api.base)
        entrarSegunInmobiliaria()
    }

    /// Una invitación pendiente de aceptar (el link llegó antes de entrar).
    var invitacionPendiente: String? {
        get { UserDefaults.standard.string(forKey: "invitacion") }
        set { UserDefaults.standard.set(newValue, forKey: "invitacion") }
    }

    /// Acepta la invitación del link y entra a esa inmobiliaria. Sin sesión, la guarda para después.
    func aceptarInvitacion(_ token: String) async {
        guard api.token != nil, fase != .afuera else {
            invitacionPendiente = token
            avisar("Entrá con tu cuenta y te sumamos a la inmobiliaria.")
            return
        }
        struct C: Encodable { var token: String }
        do {
            let antes = Set(sesion?.inmobiliarias.map(\.id) ?? [])
            try await api.hacer("POST", "/v1/invitaciones/aceptar", C(token: token))
            invitacionPendiente = nil
            try await cargarSesion()
            if let nueva = sesion?.inmobiliarias.first(where: { !antes.contains($0.id) }) {
                try await elegir(nueva)
                avisar("Ya estás en \(nueva.nombre) como \(ElegirInmobiliaria.rol(nueva.rol).lowercased())")
            }
        } catch { avisar(error) }
    }

    /// 1C: elegir (o cambiar) la inmobiliaria.
    func elegir(_ m: Sesion.Membresia) async throws {
        struct Cuerpo: Encodable { var inmobiliariaId: String }
        let s: Sesion = try await api.enviar("PUT", "/v1/auth/inmobiliaria", Cuerpo(inmobiliariaId: m.inmobiliariaId))
        if s.inmobiliariaId != sesion?.inmobiliariaId { Guardado.borrarTodo(); pilas = [:] }
        sesion = s
        Guardado.guardar(s, clave: "sesion")
        UserDefaults.standard.set(true, forKey: "eligio-\(s.usuario.id)")
        fase = .adentro
        Spotlight.indexarSecciones(duenio: esDuenio)
        version += 1
        Task { await despuesDeEntrar() }
    }

    /// Crear la primera inmobiliaria desde la app (la cuenta nueva sin ninguna).
    func crearInmobiliaria(nombre: String) async throws {
        struct Cuerpo: Encodable { var nombre: String }
        struct Creada: Decodable { var id: String }
        let c: Creada = try await api.enviar("POST", "/v1/inmobiliarias", Cuerpo(nombre: nombre))
        try await cargarSesion()
        if let m = sesion?.inmobiliarias.first(where: { $0.inmobiliariaId == c.id }) {
            try await elegir(m)
        }
    }

    func salir() async {
        if let t = tokenPush { try? await api.hacer("DELETE", "/v1/push/dispositivos/\(t)") }
        try? await api.hacer("POST", "/v1/auth/salir")
        olvidarSesion()
        fase = .afuera
    }

    private func sesionPerdida() {
        olvidarSesion()
        fase = .afuera
        avisar("Tu sesión venció. Entrá de nuevo.", ok: false)
    }

    private func olvidarSesion() {
        Llavero.borrar("token")
        api.token = nil
        sesion = nil
        pilas = [:]
        Guardado.borrarTodo()
        cola.vaciar()
        SesionCompartida.guardar(token: nil, api: api.base)
    }

    // MARK: Navegación

    func pila(_ p: Pestana) -> Binding<NavigationPath> {
        Binding(get: { self.pilas[p] ?? NavigationPath() }, set: { self.pilas[p] = $0 })
    }

    /// Ir a una pestaña y apilar un destino (desde cualquier pantalla, un push o un widget).
    func ir(_ r: Ruta) {
        if r.pestana == .mira {
            miraAbierta = true
            if let d = r.destino { Self.apilar(d, en: &pilas[.inicio, default: NavigationPath()]); pestana = .inicio }
            return
        }
        pestana = r.pestana
        if let d = r.destino {
            var p = NavigationPath()
            Self.apilar(d, en: &p)
            pilas[r.pestana] = p
        }
    }

    func abrir(_ destino: AnyHashable, en p: Pestana? = nil) {
        Self.apilar(destino, en: &pilas[p ?? pestana, default: NavigationPath()])
    }

    /// Apila el destino con su tipo real. Agregado como `AnyHashable`, `NavigationPath` lo guarda como
    /// `AnyHashable` y SwiftUI no encuentra su `navigationDestination` (muestra el triángulo amarillo).
    /// `base` se abre como `any Hashable` y `append` recibe, p. ej., un `AFichaPropiedad`.
    static func apilar(_ d: AnyHashable, en path: inout NavigationPath) {
        let valor: any Hashable = d.base as? any Hashable ?? d
        path.append(valor)
    }

    // MARK: Avisos

    /// El aviso de abajo. Con `deshacer`, 5 s para arrepentirse (handoff · Comportamiento).
    func avisar(_ texto: String, ok: Bool = true, deshacer: (() -> Void)? = nil) {
        aviso = Aviso(texto: texto, ok: ok, deshacer: deshacer)
        avisoTarea?.cancel()
        let id = aviso?.id
        avisoTarea = Task {
            try? await Task.sleep(for: .seconds(deshacer == nil ? 3 : 5))
            if !Task.isCancelled, aviso?.id == id { aviso = nil }
        }
    }

    /// El paso siguiente, en el momento justo: después de cargar, captar, cerrar o cobrar, el aviso de
    /// abajo propone lo que suele venir después y lleva ahí en un toque (dura 6 s).
    func sugerir(_ texto: String, _ boton: String, _ destino: AnyHashable) {
        sugerir(texto, boton) { [weak self] in self?.abrir(destino) }
    }

    func sugerir(_ texto: String, _ boton: String, hacer: @escaping () -> Void) {
        aviso = Aviso(texto: texto, ok: true, accion: (boton, hacer))
        avisoTarea?.cancel()
        let id = aviso?.id
        avisoTarea = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, aviso?.id == id { aviso = nil }
        }
    }

    /// El error de un pedido, dicho en palabras.
    func avisar(_ e: Error) {
        if let e = e as? ErrorApi { avisar(e.detalle.isEmpty ? e.titulo : e.detalle, ok: false) } else { avisar("Algo salió mal. Probá de nuevo.", ok: false) }
    }

    // MARK: Face ID (1D)

    func desbloquear() async {
        let c = LAContext()
        c.localizedFallbackTitle = "Usar el código"
        if (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Entrar a Corredor")) == true {
            bloqueada = false
        }
    }

    // MARK: Push

    private func pedirPermisoPush() async {
        let c = UNUserNotificationCenter.current()
        let ajustes = await c.notificationSettings()
        switch ajustes.authorizationStatus {
        case .notDetermined:
            if (try? await c.requestAuthorization(options: [.alert, .badge, .sound])) == true {
                UIApplication.shared.registerForRemoteNotifications()
            }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    /// El token de APNs, registrado en la API para que mande los avisos al iPhone.
    func registrarTokenPush(_ hex: String) async {
        tokenPush = hex
        struct Cuerpo: Encodable {
            var token: String
            var plataforma = "ios"
            #if DEBUG
            var entorno = "sandbox"
            #else
            var entorno = "produccion"
            #endif
        }
        try? await api.hacer("POST", "/v1/push/dispositivos", Cuerpo(token: hex))
    }
}

/// La cola sin conexión (handoff · «Sin conexión»): lo que se carga sin señal queda guardado en disco
/// con su estado visible («2 cambios en cola») y se sube solo cuando vuelve la red. Cada cambio va
/// con su Idempotency-Key, así la API no lo duplica si se reintenta.
@Observable
@MainActor
final class Cola {
    struct Cambio: Codable, Identifiable, Equatable {
        var id = UUID()
        var metodo: String
        var ruta: String
        var cuerpo: Data?
        /// Lo que se le muestra a la persona: «Alta de Gorriti 4820», «Cobro de Lucía Méndez».
        var etiqueta: String
        var creado = Date()
        var intentos = 0
        var error: String?
    }

    private(set) var cambios: [Cambio] = []
    private(set) var subiendo = false
    var alSubir: (() -> Void)?
    private let api: Api
    private static let clave = "cola"

    init(api: Api) {
        self.api = api
        cambios = Guardado.leer([Cambio].self, clave: Cola.clave)?.0 ?? []
    }

    /// Manda el cambio ya; si no hay señal, queda en la cola y devuelve `false`.
    @discardableResult
    func enviar<C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C?, etiqueta: String) async throws -> Bool {
        let d = try cuerpo.map { try Api.codificador.encode($0) }
        var c = Cambio(metodo: metodo, ruta: ruta, cuerpo: d, etiqueta: etiqueta)
        do {
            _ = try await api.pedir(metodo, ruta, cuerpo: d, envio: c.id.uuidString)
            return true
        } catch let e as ErrorApi where e.sinConexion {
            c.intentos = 1
            cambios.append(c)
            guardar()
            return false
        }
    }

    func subir() {
        guard !subiendo, !cambios.isEmpty else { return }
        subiendo = true
        Task {
            defer { subiendo = false }
            for c in cambios {
                do {
                    _ = try await api.pedir(c.metodo, c.ruta, cuerpo: c.cuerpo, envio: c.id.uuidString)
                    cambios.removeAll { $0.id == c.id }
                    alSubir?()
                } catch let e as ErrorApi where e.sinConexion {
                    break
                } catch let e as ErrorApi {
                    // La API lo rechazó (no es la señal): queda con el motivo para que se vea y se corrija.
                    if let i = cambios.firstIndex(where: { $0.id == c.id }) {
                        cambios[i].intentos += 1
                        cambios[i].error = e.detalle
                    }
                } catch {}
            }
            guardar()
        }
    }

    func descartar(_ c: Cambio) {
        cambios.removeAll { $0.id == c.id }
        guardar()
    }

    func vaciar() {
        cambios = []
        guardar()
    }

    private func guardar() { Guardado.guardar(cambios, clave: Cola.clave) }
}
