import AppIntents
import PhotosUI
import SwiftUI
import TipKit
import UserNotifications

// MARK: - Modelos (formas de la API)

/// GET /v1/perfil (equipo.Miembro): lo de la persona que no viene de Clerk.
struct DatosPerfil: Codable, Equatable {
    var usuarioId: String?
    var email: String?
    var nombre: String?
    var apellido: String?
    var foto: String?
    var telefono: String?
    var whatsapp: String?
    var rol: String?
}

/// GET/PUT /v1/perfil/web (equipo.EnLaWeb): cómo aparece en la web de la inmobiliaria.
struct EnLaWebPerfil: Codable, Equatable {
    var fotoId: String?
    var enWeb = false
    var presentacion: String?
}

/// GET/PUT /v1/perfil/firma (equipo.Firma): la firma en mensajes, por inmobiliaria.
struct FirmaPerfil: Codable, Equatable {
    var texto: String?
    var activa = false
    var sugerida = ""
}

/// GET /v1/auth/sesiones (cuentas.SesionAbierta).
struct SesionAbiertaPerfil: Decodable, Identifiable, Equatable {
    var id: String
    var actual: Bool
    var agente: String?
    var ip: String?
    var creadaEn: Date
    var vistoEn: Date?

    /// «Este iPhone», «Chrome en Mac»… desde el navegador (o la app) que anotó la sesión.
    var dispositivo: (titulo: String, icono: String) {
        let ua = agente ?? ""
        func tiene(_ p: String) -> Bool { ua.range(of: p, options: .regularExpression) != nil }
        // La app manda «Corredor/… CFNetwork/… Darwin/…»: es un iPhone.
        let app = tiene("CFNetwork|Darwin|Corredor")
        let cel = app || tiene("iPhone|Android.*Mobile|Mobile")
        let equipo = tiene("iPhone") || (app && !tiene("iPad")) ? "iPhone" : tiene("iPad") ? "iPad" : tiene("Android") ? "Android"
            : tiene("Mac OS X") ? "Mac" : tiene("Windows") ? "Windows" : tiene("Linux") ? "Linux" : ""
        let nav = tiene("Edg/") ? "Edge" : tiene("Chrome/") ? "Chrome" : tiene("Firefox/") ? "Firefox" : tiene("Safari/") ? "Safari" : ""
        let titulo: String
        if actual {
            titulo = cel && !equipo.isEmpty ? "Este \(equipo)" : "Este navegador"
        } else if !nav.isEmpty && !equipo.isEmpty {
            titulo = "\(nav) en \(equipo)"
        } else if app {
            titulo = "Corredor en iPhone"
        } else {
            titulo = equipo.nonEmpty ?? nav.nonEmpty ?? "Otro dispositivo"
        }
        return (titulo, cel ? "iphone" : "laptopcomputer")
    }
}

/// Cómo están los avisos en este iPhone.
enum EstadoPushDispositivo { case activo, inactivo, bloqueado }

// MARK: - Mi perfil

/// Mi perfil (07 · 6C, como /perfil de la web): la foto, el rol, los datos de contacto que van en la
/// web y las fichas, la firma, «En la web», los avisos (los de este iPhone, con la prueba), el
/// recorrido, las sesiones abiertas, las inmobiliarias (cambiar, crear otra, aceptar una invitación),
/// Face ID, la apariencia, salir y borrar la cuenta.
struct MiPerfil: View {
    @Environment(Estado.self) private var estado
    @AppStorage("tema") private var tema = "sistema"
    @State private var faceID = false
    @State private var perfil: DatosPerfil?
    @State private var web = EnLaWebPerfil()
    @State private var firma: FirmaPerfil?
    @State private var avisosActivos: Int?
    @State private var error: ErrorApi?
    @State private var cargado = false
    @State private var editando = false
    @State private var editandoWeb = false
    @State private var editandoFirma = false
    @State private var borrando = false
    @State private var push: EstadoPushDispositivo?
    @State private var foto: PhotosPickerItem?
    @State private var subiendo = false
    @State private var urlFoto: URL?

    private var nombre: String {
        let n = [perfil?.nombre, perfil?.apellido].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return n.nonEmpty ?? perfil?.email ?? estado.usuario?.completo ?? ""
    }
    private var esLector: Bool { estado.rol == "lector" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !cargado, let error {
                    EstadoError(que: "tu perfil", error: error) { Task { await cargar() } }
                } else if !cargado {
                    EsqueletoFilas(filas: 6)
                } else {
                    cabeza
                    tusDatos
                    avisosDispositivo
                    recorrido
                    ListaSesiones()
                    inmobiliarias
                    ajustes
                    salir
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .background(FondoApp())
        .pantallaApilada("Mi perfil")
        .onAppear { faceID = estado.conFaceID }
        .task(id: estado.version) { await cargar() }
        .onChange(of: foto) { _, i in if let i { subirFoto(i) } }
        .sheet(isPresented: $editando) {
            HojaDatosContacto(perfil: perfil) { p in perfil = p }.hojaTLW([.medium, .large])
        }
        .sheet(isPresented: $editandoWeb) {
            HojaEnLaWeb(web: $web).hojaTLW([.medium, .large])
        }
        .sheet(isPresented: $editandoFirma) {
            if let f = firma { HojaFirmaMensajes(firma: f) { firma = $0 }.hojaTLW([.medium, .large]) }
        }
        .sheet(isPresented: $borrando) { BorrarCuenta().presentationDetents([.medium]) }
    }

    // MARK: Partes

    private var cabeza: some View {
        HStack(spacing: 14) {
            if esLector {
                circuloFoto
            } else {
                PhotosPicker(selection: $foto, matching: .images) {
                    circuloFoto.overlay(alignment: .bottomTrailing) {
                        Image(systemName: subiendo ? "arrow.triangle.2.circlepath" : "camera.fill").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(C.sobreAccion).frame(width: 26, height: 26).background(C.accion, in: Circle())
                            .overlay(Circle().stroke(C.fondo, lineWidth: 2))
                    }
                }
                .disabled(subiendo)
                .accessibilityLabel(web.fotoId == nil ? "Subir tu foto" : "Cambiar tu foto")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre).font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font).foregroundStyle(C.texto)
                Text("\(ElegirInmobiliaria.rol(estado.rol)) en \(estado.inmobiliaria?.nombre ?? "")").estilo(.texto14).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
        }
    }

    private var circuloFoto: some View {
        Group {
            if let u = urlFoto ?? (perfil?.foto ?? estado.usuario?.foto).flatMap(URL.init(string:)) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
            } else {
                Text(Formato.iniciales(nombre)).font(Estilo(tamano: 24, peso: .bold, relativo: .title2).font)
                    .foregroundStyle(C.oro).frame(maxWidth: .infinity, maxHeight: .infinity).background(C.verde700)
            }
        }
        .frame(width: 72, height: 72).clipShape(Circle())
    }

    private var tusDatos: some View {
        VStack(spacing: 0) {
            fila("Celular", perfil?.telefono?.nonEmpty ?? "Agregalo") { editando = true }
            linea
            fila("WhatsApp", perfil?.whatsapp?.nonEmpty ?? perfil?.telefono?.nonEmpty ?? "Agregalo") { editando = true }
            linea
            fila("Mail", perfil?.email ?? estado.usuario?.email ?? "", nil)
            if let f = firma {
                linea
                fila("Firma en mensajes", f.activa ? (f.texto?.nonEmpty ?? "Sin firma") : "Sin firma", apagado: !f.activa) { editandoFirma = true }
            }
            if !esLector {
                linea
                fila("En la web", web.enWeb ? (web.presentacion?.nonEmpty ?? "Aparecés en Nosotros") : "No aparecés", verde: web.enWeb) { editandoWeb = true }
            }
            linea
            fila("Avisos", avisosActivos.map { $0 == 1 ? "1 activo" : "\($0) activos" } ?? "Configurar", verde: true) { estado.abrir(AConfigAvisos()) }
        }
        .tarjeta()
    }

    @ViewBuilder
    private var avisosDispositivo: some View {
        if let push {
            HStack(spacing: 12) {
                Image(systemName: push == .activo ? "bell.badge.fill" : "bell.slash").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avisos en este dispositivo").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(push == .activo ? "Te llegan aunque Corredor esté cerrado." : push == .bloqueado ? "Están bloqueados en este dispositivo." : "Para que no se te escape una consulta.")
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 4)
                switch push {
                case .bloqueado:
                    Button("Ver cómo") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u, options: [:], completionHandler: nil) } }
                        .buttonStyle(BotonSecundario()).fixedSize()
                case .inactivo:
                    Button("Activar") { Task { await activarPush() } }.buttonStyle(BotonSecundario()).fixedSize()
                case .activo:
                    Menu {
                        Button("Probar") { Task { await probarPush() } }
                        Button("Apagar", role: .destructive) { Task { await apagarPush() } }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Probar o apagar los avisos")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 64)
            .tarjeta()
        }
    }

    private var recorrido: some View {
        HStack(spacing: 12) {
            Image(systemName: "map").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recorrido del panel").estilo(.filaLista).foregroundStyle(C.texto)
                Text("Dónde está cada cosa, en 5 pasos.").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 4)
            Button("Verlo") { estado.mostrarRecorrido = true }.buttonStyle(BotonSecundario()).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 64)
        .tarjeta()
    }

    private var inmobiliarias: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INMOBILIARIAS").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(estado.sesion?.inmobiliarias ?? []) { m in
                    filaInmobiliaria(m)
                    linea
                }
                filaIcono("plus", "Crear otra inmobiliaria") { estado.abrir(ASeccion(clave: "empezar")) }
                linea
                filaIcono("envelope.open", "Aceptar una invitación") { estado.abrir(ASeccion(clave: "invitaciones")) }
            }
            .tarjeta()
        }
    }

    private func filaInmobiliaria(_ m: Sesion.Membresia) -> some View {
        Button {
            guard m.id != estado.sesion?.inmobiliariaId else { return }
            Task {
                do {
                    try await estado.elegir(m)
                    estado.avisar("Estás en \(m.nombre) como \(ElegirInmobiliaria.rol(m.rol).lowercased())")
                } catch { estado.avisar(error) }
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(m.nombre.prefix(1))).font(Estilo.headline.font).foregroundStyle(C.texto)
                    .frame(width: 36, height: 36).background(C.hundida, in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.nombre).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                    Text("\(ElegirInmobiliaria.rol(m.rol)) · \(m.slug).\(FormCrearInmobiliaria.dominio)").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer()
                if m.id == estado.sesion?.inmobiliariaId { Image(systemName: "checkmark").foregroundStyle(C.accion) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
    }

    private var ajustes: some View {
        VStack(alignment: .leading, spacing: 12) {
            TipView(ConsejoSiri()).tipBackground(C.superficie)
            ShortcutsLink().shortcutsLinkStyle(.automaticOutline).frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                Toggle(isOn: $faceID) {
                    Label { Text("Desbloquear con Face ID").estilo(.body16) } icon: { Image(systemName: "faceid").foregroundStyle(C.accion) }
                }
                .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 14).frame(minHeight: 54)
                .onChange(of: faceID) { _, n in estado.conFaceID = n }
                linea
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                    Text("Apariencia").estilo(.body16).foregroundStyle(C.texto)
                    Spacer()
                    Picker("Apariencia", selection: $tema) {
                        Text("Como el iPhone").tag("sistema"); Text("Claro").tag("claro"); Text("Oscuro").tag("oscuro")
                    }
                    .pickerStyle(.menu).tint(C.texto2)
                }
                .padding(.horizontal, 14).frame(minHeight: 50)
                ForEach(Self.accesos, id: \.1) { icono, texto, destino in
                    linea
                    filaIcono(icono, texto) { estado.abrir(destino) }
                }
            }
            .tarjeta()
        }
    }

    private var salir: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                Button("Salir") { Task { await estado.salir() } }
                    .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.accion)
                    .frame(maxWidth: .infinity, minHeight: 50)
                linea
                Button("Borrar mi cuenta") { borrando = true }
                    .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.error)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .tarjeta()
            Text(Formato.sinViudas("Al borrar tu cuenta se eliminan tus datos personales. Las operaciones y contratos quedan en la inmobiliaria."))
                .estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text("Corredor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
        }
    }

    private static let accesos: [(String, String, AnyHashable)] = [
        ("person.2", "Contactos", AContactos()), ("rectangle.split.3x1", "Operaciones", AOperaciones()),
        ("doc.text", "Contratos y cobranzas", ACobranzas()), ("checklist", "Inventarios", ASeccion(clave: "inventarios")),
        ("flag", "Objetivo del mes", ASeccion(clave: "objetivos")), ("bell", "Avisos", AAvisos()),
        ("gearshape", "Configuración, consorcios e informes", ASeccion(clave: "mas")),
    ]

    private var linea: some View { Rectangle().fill(C.linea).frame(height: 0.5) }

    /// Una fila «clave · valor ›» de la lista del perfil (6C).
    private func fila(_ clave: String, _ valor: String, verde: Bool = false, apagado: Bool = false, _ hacer: (() -> Void)?) -> some View {
        Button { hacer?() } label: {
            HStack(spacing: 12) {
                Text(clave).estilo(.body16).foregroundStyle(C.texto)
                Spacer(minLength: 8)
                Text(valor).estilo(.texto14).foregroundStyle(verde ? C.ok : apagado ? C.texto3 : C.texto2).lineLimit(1)
                if hacer != nil { Chevron() }
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .disabled(hacer == nil)
    }

    private func filaIcono(_ icono: String, _ texto: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                Text(texto).estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
    }

    // MARK: Datos

    private func cargar() async {
        do {
            let p: DatosPerfil = try await estado.api.get("/v1/perfil")
            perfil = p
            error = nil
        } catch let e as ErrorApi {
            error = e
            if perfil == nil { return }
        } catch { return }
        // Lo demás, cada cosa por su lado: si falla, la fila sale con lo que hay (como la web).
        struct Prefs: Decodable { struct Tipo: Decodable { var push: Bool?; var mail: Bool? }; var tipos: [Tipo]? }
        if let pr: Prefs = try? await estado.api.get("/v1/avisos/preferencias") {
            avisosActivos = (pr.tipos ?? []).filter { $0.push == true || $0.mail == true }.count
        }
        if let w: EnLaWebPerfil = try? await estado.api.get("/v1/perfil/web") {
            web = w
            if let id = w.fotoId, let a: Archivo = try? await estado.api.get("/v1/archivos/\(id)") { urlFoto = a.url.flatMap(URL.init(string:)) }
        }
        firma = (try? await estado.api.get("/v1/perfil/firma")) ?? FirmaPerfil()
        await mirarPush()
        cargado = true
    }

    private func mirarPush() async {
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch s {
        case .denied: push = .bloqueado
        case .authorized, .provisional, .ephemeral: push = estado.pushApagado ? .inactivo : .activo
        default: push = .inactivo
        }
    }

    private func activarPush() async {
        let c = UNUserNotificationCenter.current()
        if await c.notificationSettings().authorizationStatus == .denied {
            await mirarPush()
            return
        }
        await estado.prenderPush()
        await mirarPush()
    }

    private func apagarPush() async {
        do {
            try await estado.apagarPush()
            push = .inactivo
            estado.avisar("Este dispositivo ya no recibe avisos") {
                Task { await activarPush() }
            }
        } catch {
            estado.avisar("No se guardó", ok: false)
        }
    }

    private func probarPush() async {
        do {
            try await estado.api.hacer("POST", "/v1/push/prueba")
            estado.avisar("Mandamos uno de prueba")
        } catch {
            estado.avisar("No salió la prueba", ok: false)
        }
    }

    /// La foto nueva: se sube (uso foto: pública y con sus tamaños) y queda al toque, con «Deshacer».
    private func subirFoto(_ i: PhotosPickerItem) {
        let antes = web
        let urlAntes = urlFoto
        Task {
            subiendo = true
            defer { subiendo = false; foto = nil }
            do {
                guard let d = try await i.loadTransferable(type: Data.self), let img = UIImage(data: d) else {
                    estado.avisar("Elegí una foto (JPG, PNG o WebP).", ok: false)
                    return
                }
                let a = try await estado.api.subir(img.achicada(1200).jpegData(compressionQuality: 0.85) ?? d, nombre: "foto.jpg", tipo: "image/jpeg", uso: "foto")
                var w = web
                w.fotoId = a.id
                try await estado.api.hacer("PUT", "/v1/perfil/web", w)
                web = w
                urlFoto = a.url.flatMap(URL.init(string:))
                Haptico.exito()
                estado.avisar("Listo: tu foto nueva") {
                    Task {
                        do {
                            try await estado.api.hacer("PUT", "/v1/perfil/web", antes)
                            web = antes
                            urlFoto = urlAntes
                        } catch { estado.avisar("No se guardó", ok: false) }
                    }
                }
            } catch {
                estado.avisar(error)
            }
        }
    }
}

// MARK: - Hojas

/// «Tus datos de contacto»: el celular y el WhatsApp (van en tu ficha de la web y en lo que mandás).
struct HojaDatosContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var perfil: DatosPerfil?
    var alGuardar: (DatosPerfil) -> Void
    @State private var telefono = ""
    @State private var whatsapp = ""
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tus datos de contacto").estilo(.titulo).foregroundStyle(C.texto)
            Text("Van en tu ficha de la web y en lo que mandás a los clientes.").estilo(.subhead).foregroundStyle(C.texto2)
            Etiquetado("Celular") { TextField("", text: $telefono).keyboardType(.phonePad).textContentType(.telephoneNumber).campoCorredor() }
            Etiquetado("WhatsApp (opcional)") {
                TextField("", text: $whatsapp).keyboardType(.phonePad).textContentType(.telephoneNumber).campoCorredor()
                Text("Si es otro número que el celular.").estilo(.footnote).foregroundStyle(C.texto3)
            }
            if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button(guardando ? "Guardando…" : "Guardar") { guardar() }.buttonStyle(BotonPrincipal()).disabled(guardando)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear {
            telefono = perfil?.telefono ?? ""
            whatsapp = perfil?.whatsapp ?? ""
        }
    }

    private func guardar() {
        struct C: Encodable { var telefono: String; var whatsapp: String }
        let t = telefono.trimmingCharacters(in: .whitespaces), w = whatsapp.trimmingCharacters(in: .whitespaces)
        if t.count > 40 || w.count > 40 { error = "El teléfono es demasiado largo."; return }
        guardando = true
        error = nil
        Task {
            defer { guardando = false }
            do {
                try await estado.api.hacer("PATCH", "/v1/perfil", C(telefono: t, whatsapp: w))
                var p = perfil ?? DatosPerfil()
                p.telefono = t.nonEmpty
                p.whatsapp = w.nonEmpty
                alGuardar(p)
                cerrar()
            } catch let e as ErrorApi {
                error = e.detalle.isEmpty ? e.titulo : e.detalle
            } catch {
                self.error = "No se guardó"
            }
        }
    }
}

/// «Tu lugar en la web»: aparecer en «Nosotros» de la web de la inmobiliaria y cómo se presenta.
struct HojaEnLaWeb: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @Binding var web: EnLaWebPerfil
    @State private var enWeb = false
    @State private var presentacion = ""
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tu lugar en la web").estilo(.titulo).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Tu nombre, tu foto y cómo te presentás, en «Nosotros» de la web de la inmobiliaria.")).estilo(.subhead).foregroundStyle(C.texto2)
            Toggle(isOn: $enWeb) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aparecer en Nosotros").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(Formato.sinViudas("Ni tu mail ni tu teléfono: sólo nombre, foto y rol.")).estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            .tint(C.ok)
            Etiquetado("Cómo te presentás (opcional)") {
                TextField("", text: $presentacion).campoCorredor()
                    .onChange(of: presentacion) { _, n in if n.count > 60 { presentacion = String(n.prefix(60)) } }
                Text("Por ejemplo: «Palermo y Belgrano» o «Corredora · Mat.\u{00a0}7215».").estilo(.footnote).foregroundStyle(C.texto3)
            }
            if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button(guardando ? "Guardando…" : "Guardar") { guardar() }.buttonStyle(BotonPrincipal()).disabled(guardando)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear {
            enWeb = web.enWeb
            presentacion = web.presentacion ?? ""
        }
    }

    private func guardar() {
        let antes = web
        var nuevo = web
        nuevo.enWeb = enWeb
        nuevo.presentacion = presentacion.trimmingCharacters(in: .whitespaces).nonEmpty
        guardando = true
        error = nil
        Task {
            defer { guardando = false }
            do {
                try await estado.api.hacer("PUT", "/v1/perfil/web", nuevo)
                web = nuevo
                cerrar()
                let enlace = $web
                estado.avisar(nuevo.enWeb ? "Listo: aparecés en Nosotros" : "Listo: ya no aparecés en la web") {
                    Task {
                        do {
                            try await estado.api.hacer("PUT", "/v1/perfil/web", antes)
                            enlace.wrappedValue = antes
                        } catch { estado.avisar("No se guardó", ok: false) }
                    }
                }
            } catch let e as ErrorApi {
                error = e.detalle.isEmpty ? e.titulo : e.detalle
            } catch {
                self.error = "No se guardó"
            }
        }
    }
}

/// «Firma en mensajes»: el renglón que va al pie de los WhatsApp y los mails que se mandan desde
/// Corredor. Si no hay, propone la sugerida y la activa; sin texto no queda activa.
struct HojaFirmaMensajes: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var firma: FirmaPerfil
    var alGuardar: (FirmaPerfil) -> Void
    @State private var activa = false
    @State private var texto = ""
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Firma en mensajes").estilo(.titulo).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Va al pie de los WhatsApp y los mails que mandás desde Corredor.")).estilo(.subhead).foregroundStyle(C.texto2)
            Toggle(isOn: $activa) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firmar mis mensajes").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(Formato.sinViudas("Dos renglones abajo de lo que escribís, sólo en esta inmobiliaria.")).estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            .tint(C.ok)
            Etiquetado("Firma") {
                TextField("", text: $texto).campoCorredor()
                    .onChange(of: texto) { _, n in if n.count > 120 { texto = String(n.prefix(120)) } }
                if !firma.sugerida.isEmpty {
                    Text("Por ejemplo: «\(firma.sugerida)».").estilo(.footnote).foregroundStyle(C.texto3)
                }
            }
            if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button(guardando ? "Guardando…" : "Guardar") { guardar() }.buttonStyle(BotonPrincipal()).disabled(guardando)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear {
            activa = firma.texto?.nonEmpty != nil ? firma.activa : true
            texto = firma.texto ?? firma.sugerida
        }
    }

    private func guardar() {
        struct Cuerpo: Encodable { var texto: String?; var activa: Bool }
        let antes = firma
        let t = texto.trimmingCharacters(in: .whitespaces).nonEmpty
        let nuevo = FirmaPerfil(texto: t, activa: activa && t != nil, sugerida: firma.sugerida)
        guardando = true
        error = nil
        Task {
            defer { guardando = false }
            do {
                try await estado.api.hacer("PUT", "/v1/perfil/firma", Cuerpo(texto: nuevo.texto, activa: nuevo.activa))
                alGuardar(nuevo)
                cerrar()
                let volver = alGuardar
                estado.avisar(nuevo.activa ? "Listo: tus mensajes van firmados" : "Listo: tus mensajes van sin firma") {
                    Task {
                        do {
                            try await estado.api.hacer("PUT", "/v1/perfil/firma", Cuerpo(texto: antes.texto, activa: antes.activa))
                            volver(antes)
                        } catch { estado.avisar("No se guardó", ok: false) }
                    }
                }
            } catch let e as ErrorApi {
                error = e.detalle.isEmpty ? e.titulo : e.detalle
            } catch {
                self.error = "No se guardó"
            }
        }
    }
}

// MARK: - Sesiones abiertas

/// «Sesiones abiertas» con nombre legible («Este iPhone», «Chrome en Mac»), «ahora / hace…» y
/// «Cerrar» al toque (vuelve si falla).
struct ListaSesiones: View {
    @Environment(Estado.self) private var estado
    @State private var sesiones: [SesionAbiertaPerfil] = []
    @State private var cerradas: Set<String> = []

    var body: some View {
        let lista = sesiones.filter { !cerradas.contains($0.id) }
        Group {
            if !lista.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sesiones abiertas").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(lista.enumerated()), id: \.element.id) { i, s in
                            fila(s)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                }
            }
        }
        .task(id: estado.version) {
            if let l: [SesionAbiertaPerfil] = try? await estado.api.get("/v1/auth/sesiones") { sesiones = l }
        }
    }

    private func fila(_ s: SesionAbiertaPerfil) -> some View {
        let d = s.dispositivo
        return HStack(spacing: 12) {
            Image(systemName: d.icono).font(.system(size: 20)).foregroundStyle(s.actual ? C.accion : C.texto2)
                .frame(width: 40, height: 40).background(s.actual ? C.okFondo : C.hundida, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(d.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                Text(s.actual ? "ahora" : Formato.hace(s.vistoEn ?? s.creadaEn)).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 4)
            if !s.actual {
                Button("Cerrar") { cerrar(s, titulo: d.titulo) }
                    .font(Estilo.subheadFuerte.font).foregroundStyle(C.error).frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 60)
    }

    private func cerrar(_ s: SesionAbiertaPerfil, titulo: String) {
        cerradas.insert(s.id)
        Task {
            do {
                try await estado.api.hacer("DELETE", "/v1/auth/sesiones/\(s.id)")
                estado.avisar("Cerramos la sesión de \(titulo)")
            } catch let e as ErrorApi where e.estado == 404 {
                estado.avisar("Cerramos la sesión de \(titulo)")
            } catch {
                cerradas.remove(s.id)
                estado.avisar("No se guardó", ok: false)
            }
        }
    }
}
