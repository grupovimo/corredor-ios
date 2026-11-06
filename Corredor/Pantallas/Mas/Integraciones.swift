import AuthenticationServices
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// 43 Integraciones: WhatsApp, Mercado Libre, los feeds de Zonaprop y Argenprop, los avisos push y
/// Corredor en tu IA. Cada una dice su estado, qué hace y cómo se conecta (tocándola). Conectar y
/// desconectar es del dueño; el resto ve el estado.
struct Integraciones: View {
    @Environment(Estado.self) private var estado
    @State private var numero: Numero?
    @State private var ml: CuentaML?
    @State private var erroresML = 0
    @State private var feeds: [Feed] = []
    @State private var push = (activos: 0, total: 0)
    @State private var ia = false
    @State private var cargado = false
    @State private var abierta: Clave?

    /// `GET /v1/whatsapp/numero` (whatsapp.Numero).
    struct Numero: Codable { var conectado: Bool?; var numeroId: String?; var telefono: String?; var conectadoEn: Date?; var verificacion: String?; var estado: String? }
    /// `GET /v1/mercadolibre`.
    struct CuentaML: Codable { var disponible: Bool?; var conectada: Bool?; var apodo: String?; var reautorizar: Bool?; var preguntasSinResponder: Int? }
    /// `GET /v1/inmobiliaria/feeds`: un feed por portal, con la URL (lleva la clave) y la última lectura.
    struct Feed: Codable, Identifiable { var portal: String; var url: String; var leidoEn: Date?; var avisos: Int?; var id: String { portal } }

    enum Clave: String, Identifiable { case whatsapp, mercadolibre, zonaprop, argenprop, push; var id: String { rawValue } }

    /// Qué hace cada una y cómo se conecta (los textos de la web).
    static let queHace: [Clave: (titulo: String, texto: String, pasos: [String])] = [
        .whatsapp: ("WhatsApp Business",
                    "Las consultas de tu número entran a la Bandeja, cada una con su dueño, y se contestan desde Corredor. Fuera de las 24 horas sólo salen plantillas aprobadas por Meta.",
                    ["En Meta Business, creá la app y sumá WhatsApp con tu número.",
                     "Creá un usuario del sistema con permiso sobre la cuenta y generá su token permanente.",
                     "Pegá acá el identificador del número y el token: los probamos con Meta antes de guardarlos."]),
        .mercadolibre: ("Mercado Libre",
                        "Publicás desde la ficha de cada propiedad y las preguntas llegan a la Bandeja para contestarlas desde Corredor. Si una publicación falla, te decimos qué le falta.",
                        ["Tocá «Conectar»: vas a Mercado Libre.", "Entrá con la cuenta de la inmobiliaria y autorizá a Corredor.", "Volvés acá con la cuenta conectada."]),
        .zonaprop: ("Zonaprop",
                    "Zonaprop lee tu feed varias veces por día: publica las propiedades que elegiste difundir ahí y saca las que ya no están. Las consultas llegan por mail y a la Bandeja.",
                    ["Copiá la URL de tu feed.", "En tu cuenta de Zonaprop, andá a «Integraciones» y pegala como feed XML.", "Cuando la lea por primera vez, acá dice «Activo»."]),
        .argenprop: ("Argenprop",
                     "Argenprop lee tu feed y publica las propiedades que elegiste difundir ahí. Lo que cambiás en Corredor se actualiza solo en la próxima lectura.",
                     ["Copiá la URL de tu feed.", "En tu cuenta de Argenprop, pegala donde pide la URL del feed.", "Cuando la lea por primera vez, acá dice «Activo»."]),
        .push: ("Avisos push",
                "Cada persona los activa en su celular o su compu: una consulta nueva, una visita que está por empezar, un cobro vencido. Cada uno elige cuáles quiere.",
                ["Entrá a tu perfil desde el dispositivo donde querés recibirlos.", "Tocá «Activar avisos» y aceptá el permiso del navegador."]),
    ]

    /// El estado de una fila: un texto con su tono o un botón.
    enum EstadoFila { case texto(String, Tono), boton(String), nada }

    struct Fila: Identifiable { var clave: Clave; var nombre: String; var logo: String?; var icono: String; var detalle: String; var estado: EstadoFila; var id: String { clave.rawValue } }

    private func feed(_ p: String) -> Feed? { feeds.first { $0.portal == p } }

    var filas: [Fila] {
        var f: [Fila] = []
        let n = numero
        f.append(Fila(clave: .whatsapp, nombre: "WhatsApp", logo: "LogoWhatsApp", icono: "message",
                      detalle: n?.conectado == true ? "\(n?.telefono ?? "Número conectado") · \(Formato.cantidad(push.total, "persona", "personas"))"
                          : "Las consultas entran a la Bandeja y respondés desde Corredor",
                      estado: n?.conectado == true ? .texto("Conectado", .verde) : .boton("Conectar")))
        let detalleML: String
        let estadoML: EstadoFila
        if ml?.conectada != true {
            detalleML = ml?.disponible == false ? "Todavía no está habilitado en Corredor" : "Publicá y contestá preguntas desde Corredor"
            estadoML = ml?.disponible == false ? .texto("Sin habilitar", .neutro) : .boton("Conectar")
        } else {
            let preguntas = ml?.preguntasSinResponder ?? 0
            if ml?.reautorizar == true { detalleML = "Mercado Libre pide volver a conectar" }
            else if erroresML > 0 { detalleML = Formato.cantidad(erroresML, "publicación con error", "publicaciones con error") }
            else { detalleML = "\(ml?.apodo?.nonEmpty ?? "Cuenta conectada")\(preguntas > 0 ? " · \(Formato.cantidad(preguntas, "pregunta", "preguntas")) sin responder" : "")" }
            estadoML = ml?.reautorizar == true || erroresML > 0 ? .texto("Revisar", .oro) : .texto("Conectado", .verde)
        }
        f.append(Fila(clave: .mercadolibre, nombre: "Mercado Libre", logo: nil, icono: "storefront", detalle: detalleML, estado: estadoML))
        for (clave, nombre) in [(Clave.zonaprop, "Zonaprop"), (Clave.argenprop, "Argenprop")] {
            let x = feed(clave.rawValue)
            let leido = x?.leidoEn
            f.append(Fila(clave: clave, nombre: "\(nombre) · feed", logo: nil, icono: "dot.radiowaves.up.forward",
                          detalle: leido.map { "leído \(Relativa.de($0)) · \(Formato.cantidad(x?.avisos ?? 0, "aviso", "avisos"))" } ?? "Pegá la URL del feed en tu cuenta de \(nombre)",
                          estado: leido != nil ? .texto("Activo", .verde) : estado.esDuenio ? .boton("Conectar") : .nada))
        }
        f.append(Fila(clave: .push, nombre: "Avisos push", logo: nil, icono: "bell.badge",
                      detalle: "\(push.activos) de \(Formato.cantidad(push.total, "persona", "personas")) los activaron", estado: .nada))
        return f
    }

    var body: some View {
        Group {
            if cargado { lista } else { EsqueletoFilas(filas: 6).padding(16).frame(maxHeight: .infinity, alignment: .top).background(FondoApp()) }
        }
        .pantallaApilada("Integraciones")
        .task(id: estado.version) { await cargar() }
        .sheet(item: $abierta) { c in
            HojaIntegracion(clave: c, fila: filas.first { $0.clave == c }, numero: numero, ml: ml, erroresML: erroresML, feed: feed(c.rawValue),
                            alCambiar: { await cargar() })
        }
    }

    private var lista: some View {
        List {
            Section {
                Text(Formato.sinViudas("Cada una dice su estado y qué hace. Tocala para ver cómo se conecta.")).estilo(.footnote).foregroundStyle(C.texto2)
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(filas) { f in
                    Button { abierta = f.clave } label: { fila(f) }.buttonStyle(.plain)
                }
                Button { estado.abrir(ASeccion(clave: "ia")) } label: {
                    fila(Fila(clave: .push, nombre: "Corredor en tu IA", logo: "Simbolo", icono: "sparkles", detalle: "Tu asistente lee tu cartera y arma borradores",
                              estado: .texto(ia ? "Habilitada" : "Apagada", ia ? .verde : .neutro)))
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .refreshable { await cargar() }
    }

    private func fila(_ f: Fila) -> some View {
        HStack(spacing: 12) {
            if let l = f.logo {
                Image(l).resizable().scaledToFit().frame(width: 28, height: 28)
            } else {
                Image(systemName: f.icono).font(.system(size: 20)).foregroundStyle(C.okTinta).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(f.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                Text(f.detalle).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
            switch f.estado {
            case .texto(let t, let tono):
                Text(t).font(Estilo.chip.font).foregroundStyle(tono.tinta).padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
            case .boton(let t):
                Text(t).font(Estilo.footnoteFuerte.font).foregroundStyle(C.sobreAccion).padding(.horizontal, 12).frame(height: 30).background(C.accion, in: Capsule())
            case .nada:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
    }

    private func cargar() async {
        let api = estado.api
        numero = try? await api.get("/v1/whatsapp/numero")
        ml = try? await api.get("/v1/mercadolibre")
        let errores: [JSONLibre] = (try? await api.get("/v1/publicaciones", query: [.init(name: "portal", value: "mercadolibre"), .init(name: "estado", value: "error"), .init(name: "limite", value: "50")])) ?? []
        erroresML = errores.count
        // Sólo el dueño: la URL lleva la clave.
        if estado.esDuenio { feeds = (try? await api.get("/v1/inmobiliaria/feeds")) ?? [] }
        let equipo: [Miembro] = (try? await api.get("/v1/equipo")) ?? []
        push = (equipo.filter { $0.avisosPush == true }.count, equipo.count)
        struct IA: Decodable { var habilitado: Bool? }
        let a: IA? = try? await api.get("/v1/ia/ajustes")
        ia = a?.habilitado ?? false
        cargado = true
    }
}

// MARK: - La hoja de cada integración

/// Qué hace, cómo se conecta y los botones de cada integración (la `Hoja` de la web).
struct HojaIntegracion: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var clave: Integraciones.Clave
    var fila: Integraciones.Fila?
    var numero: Integraciones.Numero?
    var ml: Integraciones.CuentaML?
    var erroresML: Int
    var feed: Integraciones.Feed?
    var alCambiar: () async -> Void
    @State private var ocupado = false
    @State private var verificacion: String?
    @State private var confirmar: Confirmacion?

    private var que: (titulo: String, texto: String, pasos: [String]) { Integraciones.queHace[clave] ?? ("", "", []) }
    private var duenio: Bool { estado.esDuenio }
    private var conectada: Bool { (clave == .whatsapp && numero?.conectado == true) || (clave == .mercadolibre && ml?.conectada == true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let d = fila?.detalle { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                    Text(Formato.sinViudas(que.texto)).estilo(.subhead).foregroundStyle(C.texto)
                }
                if !conectada {
                    Section {
                        ForEach(Array(que.pasos.enumerated()), id: \.offset) { n, p in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(n + 1)").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.sobreAccion)
                                    .frame(width: 22, height: 22).background(C.accion, in: Circle())
                                Text(Formato.sinViudas(p)).estilo(.subhead).foregroundStyle(C.texto)
                            }
                        }
                    }
                }
                if let f = feed {
                    Section {
                        HStack {
                            Text(f.url).font(.footnote.monospaced()).foregroundStyle(C.texto).lineLimit(3)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = f.url
                                estado.avisar("URL copiada. Pegala en el portal.")
                            } label: { Label("Copiar", systemImage: "doc.on.doc") }.buttonStyle(.borderless)
                        }
                    } footer: { Text("La URL lleva una clave: no la publiques. Si se filtró, generá otra y volvé a pegarla en los portales.") }
                }
                if clave == .whatsapp, numero?.conectado != true, duenio {
                    FormWhatsApp { n in
                        verificacion = n.verificacion
                        estado.avisar("WhatsApp conectado")
                        await alCambiar()
                    }
                }
                if let v = verificacion {
                    Section {
                        Text("Token de verificación del webhook (se muestra una sola vez):").estilo(.footnote).foregroundStyle(C.texto2)
                        Text(v).font(.footnote.monospaced()).textSelection(.enabled)
                        Button { UIPasteboard.general.string = v; estado.avisar("Copiado") } label: { Label("Copiar", systemImage: "doc.on.doc") }
                    }
                }
                if !duenio, clave != .push {
                    Section { Label("La conecta el dueño o la dueña de la inmobiliaria.", systemImage: "lock").estilo(.footnote).foregroundStyle(C.texto2) }
                }
                Section { botones }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle(que.titulo).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .confirmacion($confirmar)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var botones: some View {
        if clave == .whatsapp, duenio, numero?.conectado == true {
            Button("Desconectar", role: .destructive) {
                confirmar = Confirmacion(titulo: "¿Desconectás WhatsApp?",
                                         texto: "Las consultas dejan de entrar a la Bandeja. Para volver, hay que pegar el token de nuevo.",
                                         boton: "Desconectar") { Task { await hacer("DELETE", "/v1/whatsapp/numero", "WhatsApp desconectado") } }
            }
        } else if clave == .mercadolibre, duenio, ml?.disponible != false {
            if ml?.conectada == true {
                if erroresML > 0 { Button("Ver la publicación") { cerrar(); estado.abrir(ASeccion(clave: "difusion")) } }
                if ml?.reautorizar == true {
                    Button("Volver a conectar") { Task { await conectarML() } }.disabled(ocupado)
                } else {
                    Button("Desconectar", role: .destructive) {
                        confirmar = Confirmacion(titulo: "¿Desconectás Mercado Libre?",
                                                 texto: "Tus avisos quedan en Mercado Libre pero sin sincronizar, y las preguntas dejan de llegar. Para volver, autorizás de nuevo.",
                                                 boton: "Desconectar") { Task { await hacer("DELETE", "/v1/mercadolibre", "Mercado Libre desconectado") } }
                    }
                }
            } else {
                Button { Task { await conectarML() } } label: { Label("Conectar", systemImage: "arrow.up.right.square") }.disabled(ocupado)
            }
        } else if feed != nil, duenio {
            Button { Task { await hacer("POST", "/v1/inmobiliaria/clave-feed", "Clave nueva: volvé a pegar la URL en los portales") } } label: {
                if ocupado { ProgressView() } else { Text("Generar otra clave") }
            }
            .disabled(ocupado)
        } else if clave == .push {
            Button("Ir a mi perfil") { cerrar(); estado.abrir(APerfil()) }
        }
    }

    private func hacer(_ metodo: String, _ ruta: String, _ ok: String) async {
        ocupado = true
        defer { ocupado = false }
        do {
            try await estado.api.hacer(metodo, ruta)
            estado.avisar(ok)
            await alCambiar()
            cerrar()
        } catch { estado.avisar(error) }
    }

    /// Conectar (o volver a conectar) Mercado Libre: su hoja de autorización y, a la vuelta, el canje del código.
    private func conectarML() async {
        struct L: Decodable { var url: String }
        ocupado = true
        defer { ocupado = false }
        let l: L
        do { l = try await estado.api.enviar("POST", "/v1/mercadolibre/conectar", [String: String]()) } catch { return estado.avisar(error) }
        guard let u = URL(string: l.url) else { return estado.avisar("No se pudo abrir Mercado Libre.", ok: false) }
        let vuelta: URL
        do { vuelta = try await HojaWeb().abrir(u) } catch {
            if (error as? Clerk.ErrorClerk)?.codigo != "cancelado" { estado.avisar("Mercado Libre no autorizó la conexión. Probá conectar de nuevo desde el panel.", ok: false) }
            return
        }
        let q = URLComponents(url: vuelta, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if q.first(where: { $0.name == "error" })?.value?.nonEmpty != nil {
            return estado.avisar("Mercado Libre no autorizó la conexión. Probá conectar de nuevo desde el panel.", ok: false)
        }
        guard let code = q.first(where: { $0.name == "code" })?.value?.nonEmpty, let st = q.first(where: { $0.name == "state" })?.value?.nonEmpty else {
            return estado.avisar("Faltan datos de Mercado Libre en el link. Probá conectar de nuevo desde el panel.", ok: false)
        }
        struct Cuerpo: Encodable { var codigo: String; var estado: String }
        do {
            let r: Integraciones.CuentaML = try await estado.api.enviar("POST", "/v1/mercadolibre/vuelta", Cuerpo(codigo: code, estado: st))
            estado.avisar("Listo: conectaste la cuenta\(r.apodo?.nonEmpty.map { " \($0)" } ?? "") de Mercado Libre.")
            await alCambiar()
            cerrar()
        } catch { estado.avisar(error) }
    }
}

// MARK: - Conectar el número de WhatsApp

/// Los datos del número de Meta (el identificador, la cuenta, el token y el secreto de la app), con el
/// error de cada campo. Al conectar la API los prueba con Meta («Probando con Meta…»).
struct FormWhatsApp: View {
    @Environment(Estado.self) private var estado
    var alConectar: (Integraciones.Numero) async -> Void
    @State private var numeroId = ""
    @State private var cuentaId = ""
    @State private var token = ""
    @State private var secreto = ""
    @State private var enviando = false
    @State private var campos: [String: String] = [:]

    var body: some View {
        Section {
            campo("Identificador del número de teléfono", $numeroId, "numeroId", teclado: .numberPad)
            campo("Identificador de la cuenta de WhatsApp Business", $cuentaId, "cuentaId", teclado: .numberPad, ayuda: "Para ver tus plantillas aprobadas.")
            VStack(alignment: .leading, spacing: 4) {
                SecureField("Token permanente", text: $token).textContentType(.password)
                ErrorDeCampo(texto: campos["token"])
            }
            VStack(alignment: .leading, spacing: 4) {
                SecureField("Clave secreta de la app (opcional)", text: $secreto)
                Text("Si usás una app de Meta propia.").estilo(.footnote).foregroundStyle(C.texto3)
                ErrorDeCampo(texto: campos["appSecreto"])
            }
            Button { Task { await conectar() } } label: {
                if enviando { HStack { ProgressView(); Text("Probando con Meta…") } } else { Text("Conectar").bold() }
            }
            .disabled(enviando || numeroId.isEmpty || token.isEmpty)
        } footer: { Text("Lo sacás de Meta for Developers › tu app › WhatsApp › Configuración de la API.") }
    }

    private func campo(_ t: String, _ v: Binding<String>, _ k: String, teclado: UIKeyboardType, ayuda: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(t, text: v).keyboardType(teclado).font(.body.monospaced())
            if let ayuda { Text(ayuda).estilo(.footnote).foregroundStyle(C.texto3) }
            ErrorDeCampo(texto: campos[k])
        }
    }

    private func conectar() async {
        enviando = true
        defer { enviando = false }
        campos = [:]
        struct C: Encodable { var numeroId: String; var cuentaId: String; var token: String; var appSecreto: String }
        do {
            let d = try await estado.api.pedirConCampos("PUT", "/v1/whatsapp/numero", C(numeroId: numeroId.trimmingCharacters(in: .whitespaces), cuentaId: cuentaId.trimmingCharacters(in: .whitespaces),
                                                                                    token: token.trimmingCharacters(in: .whitespaces), appSecreto: secreto.trimmingCharacters(in: .whitespaces)))
            let n = try Api.decodificador.decode(Integraciones.Numero.self, from: d)
            await alConectar(n)
            estado.version += 1
        } catch { campos = estado.camposDe(error) }
    }
}

/// El alta del número desde otra pantalla (los primeros pasos, MIRA): la misma hoja de Integraciones.
struct ConectarWhatsApp: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var verificacion: String?

    var body: some View {
        NavigationStack {
            Form {
                if let v = verificacion {
                    Section {
                        Label("WhatsApp conectado", systemImage: "checkmark.circle.fill").foregroundStyle(C.okTinta)
                        Text("Token de verificación del webhook (se muestra una sola vez):").estilo(.footnote).foregroundStyle(C.texto2)
                        Text(v).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                } else {
                    FormWhatsApp { n in
                        estado.sugerir("WhatsApp conectado", "Respuestas", ASeccion(clave: "respuestas"))
                        if let v = n.verificacion?.nonEmpty { verificacion = v } else { cerrar() }
                    }
                }
            }
            .navigationTitle("Conectar WhatsApp").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(verificacion == nil ? "Cancelar" : "Listo") { cerrar() } } }
        }
    }
}
