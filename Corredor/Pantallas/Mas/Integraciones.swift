import AuthenticationServices
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Integraciones: el número de WhatsApp, Mercado Libre (conectar con su hoja) y los feeds de portales.
struct Integraciones: View {
    @Environment(Estado.self) private var estado
    @State private var conectarWA = false
    @State private var numero: JSONLibre?
    @State private var ml: CuentaML?
    @State private var feeds: [Feed] = []

    /// `GET /v1/mercadolibre`.
    struct CuentaML: Codable { var disponible: Bool?; var conectada: Bool?; var apodo: String?; var reautorizar: Bool?; var preguntasSinResponder: Int? }
    /// `GET /v1/inmobiliaria/feeds`: un feed por portal, con la URL (lleva la clave) y la última lectura.
    struct Feed: Codable, Identifiable { var portal: String; var url: String; var leidoEn: Date?; var avisos: Int?; var id: String { portal } }

    var body: some View {
        List {
            Section(header: Text("WhatsApp"), footer: Text("Las consultas llegan a Mensajes y podés responder desde la app.")) {
                if let n = numero, n["conectado"] == .bool(true) || n["telefono"]?.texto != nil {
                    LabeledContent("Número", value: n["telefono"]?.texto ?? n["numeroId"]?.texto ?? "Conectado")
                    LabeledContent("Estado", value: n["estado"]?.texto?.capitalized ?? "Conectado")
                } else {
                    Text("Todavía no conectaste tu número.").foregroundStyle(C.texto2)
                    Button("Conectar WhatsApp") { conectarWA = true }
                }
            }
            Section(header: Text("Mercado Libre"), footer: Text("Publicás desde la ficha y respondés las preguntas en Mensajes.")) {
                if let m = ml, m.conectada == true {
                    LabeledContent("Cuenta", value: m.apodo?.nonEmpty ?? "Conectada")
                    if m.reautorizar == true {
                        Text("Mercado Libre pide volver a conectar la cuenta.").foregroundStyle(C.avisoTinta)
                        Button("Volver a conectar") { Task { await conectarML() } }
                    }
                    Button("Desconectar", role: .destructive) { Task { await desconectarML() } }
                } else if ml?.disponible == false {
                    Text("Todavía no está habilitado en Corredor.").foregroundStyle(C.texto2)
                } else {
                    Button("Conectar Mercado Libre") { Task { await conectarML() } }
                }
            }
            if !feeds.isEmpty {
                Section(header: Text("Portales"), footer: Text("Zonaprop y Argenprop leen tu cartera desde estos links. La URL lleva una clave: no la publiques.")) {
                    ForEach(feeds) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PublicacionPortal.nombres[f.portal] ?? f.portal.capitalized)
                                Text(f.leidoEn.map { "Activo · leído \(Formato.hace($0))\(f.avisos.map { " · \(Formato.cantidad($0, "aviso", "avisos"))" } ?? "")" } ?? "Todavía no lo leyó")
                                    .estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            Button { UIPasteboard.general.string = f.url; estado.avisar("Link copiado") } label: { Image(systemName: "doc.on.doc") }
                                .accessibilityLabel("Copiar el link")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Integraciones")
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $conectarWA) { ConectarWhatsApp() }
    }

    private func cargar() async {
        numero = try? await estado.api.get("/v1/whatsapp/numero")
        ml = try? await estado.api.get("/v1/mercadolibre")
        // Sólo el dueño: la URL lleva la clave.
        if estado.esDuenio { feeds = (try? await estado.api.get("/v1/inmobiliaria/feeds")) ?? [] }
    }

    private func desconectarML() async {
        do {
            try await estado.api.hacer("DELETE", "/v1/mercadolibre")
            estado.avisar("Desconectaste Mercado Libre")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func conectarML() async {
        struct L: Decodable { var url: String }
        let l: L
        do { l = try await estado.api.enviar("POST", "/v1/mercadolibre/conectar", [String: String]()) } catch { return estado.avisar(error) }
        guard let u = URL(string: l.url) else { return estado.avisar("No se pudo abrir Mercado Libre.", ok: false) }
        if let vuelta = try? await HojaWeb().abrir(u), let c = URLComponents(url: vuelta, resolvingAgainstBaseURL: false) {
            struct Cuerpo: Encodable { var codigo: String; var estado: String }
            if let code = c.queryItems?.first(where: { $0.name == "code" })?.value {
                do {
                    let r: CuentaML = try await estado.api.enviar("POST", "/v1/mercadolibre/vuelta", Cuerpo(codigo: code, estado: c.queryItems?.first { $0.name == "state" }?.value ?? ""))
                    estado.avisar("Listo: conectaste la cuenta \(r.apodo ?? "de Mercado Libre")")
                } catch { estado.avisar(error) }
            }
        }
        await cargar()
    }
}

// MARK: - Conectar el número de WhatsApp

/// Conectar el número de WhatsApp (Meta) desde el celular: el identificador del número, la cuenta, el
/// token y el secreto de la app; después, la verificación.
struct ConectarWhatsApp: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var numeroId = ""
    @State private var cuentaId = ""
    @State private var token = ""
    @State private var secreto = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Lo sacás de Meta for Developers › tu app › WhatsApp › Configuración de la API.")) {
                    TextField("Identificador del número de teléfono", text: $numeroId).keyboardType(.numberPad)
                    TextField("Identificador de la cuenta de WhatsApp Business", text: $cuentaId).keyboardType(.numberPad)
                    SecureField("Token de acceso permanente", text: $token)
                    SecureField("Clave secreta de la app (opcional)", text: $secreto)
                }
            }
            .navigationTitle("Conectar WhatsApp").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Conectar") { Task { await conectar() } }.disabled(numeroId.isEmpty || token.isEmpty || guardando) }
            }
        }
    }

    private func conectar() async {
        guardando = true
        defer { guardando = false }
        struct C: Encodable { var numeroId: String; var cuentaId: String?; var token: String; var appSecreto: String? }
        do {
            try await estado.api.hacer("PUT", "/v1/whatsapp/numero", C(numeroId: numeroId, cuentaId: cuentaId.nonEmpty, token: token, appSecreto: secreto.nonEmpty))
            try? await estado.api.hacer("POST", "/v1/whatsapp/numero/verificacion")
            estado.sugerir("WhatsApp conectado", "Respuestas", ASeccion(clave: "respuestas"))
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
