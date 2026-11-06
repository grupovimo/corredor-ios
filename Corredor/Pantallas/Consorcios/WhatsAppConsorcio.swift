import Foundation

/// Mandar un WhatsApp desde el número de la inmobiliaria, como `mandarWhatsApp` de la web
/// (lib/server/contratos.ts): con el número conectado abre (o retoma) la conversación y manda el
/// texto; fuera de la ventana de 24 h, la plantilla aprobada que sirva, con los datos en orden. Sin el
/// número conectado o sin plantilla, devuelve el wa.me para abrir desde el teléfono.
enum ConsorcioWhatsApp {
    enum Envio { case porCorredor, waMe(URL) }

    struct Numero: Decodable { var conectado: Bool? }
    struct Conversacion: Decodable { var id: String; var enVentana: Bool? }
    struct Plantilla: Decodable { var nombre: String; var idioma: String; var categoria: String?; var parametros: Int? }
    struct Contacto: Decodable { var nombre: String?; var telefono: String? }

    /// Para qué es: elige la plantilla fuera de 24 h (los mismos patrones que la web).
    static let patrones: [String: String] = [
        "recordatorio": "recordatorio_(pago|cobro|alquiler)|cobr|pago|vencim|alquiler",
        "expensas": "expensa|liquidaci|consorci|recib"
    ]

    static func conectado(_ api: Api) async -> Bool {
        do {
            let n: Numero = try await api.get("/v1/whatsapp/numero")
            return n.conectado == true
        } catch { return false }
    }

    static func waMe(_ telefono: String?, _ texto: String) -> URL? {
        let n = (telefono ?? "").filter(\.isNumber)
        var c = URLComponents(string: "https://wa.me/\(n)")
        if !texto.isEmpty { c?.queryItems = [URLQueryItem(name: "text", value: texto)] }
        return c?.url
    }

    /// Manda el texto a un contacto. `conectado`: si ya se sabe (en un envío masivo se pregunta una vez).
    static func mandar(_ api: Api, contactoId: String, texto: String, para: String, parametros: [String], conectado: Bool? = nil) async throws -> Envio {
        let c: Contacto = try await api.get("/v1/contactos/\(contactoId)")
        guard let tel = c.telefono?.nonEmpty else {
            throw ErrorApi(estado: 422, codigo: "sin_telefono", titulo: "Sin teléfono", detalle: "\(c.nombre ?? "El contacto") no tiene teléfono cargado.")
        }
        let hay: Bool
        if let conectado { hay = conectado } else { hay = await Self.conectado(api) }
        guard hay else { return .waMe(waMe(tel, texto) ?? URL(string: "https://wa.me")!) }
        struct AbrirC: Encodable { var contactoId: String }
        let conv: Conversacion = try await api.enviar("POST", "/v1/whatsapp/conversaciones", AbrirC(contactoId: contactoId))
        if conv.enVentana == true {
            struct M: Encodable { var texto: String }
            try await api.hacer("POST", "/v1/whatsapp/conversaciones/\(conv.id)/mensajes", M(texto: texto))
            return .porCorredor
        }
        let plantillas: [Plantilla] = (try? await api.get("/v1/whatsapp/plantillas")) ?? []
        let re = patrones[para] ?? patrones["recordatorio"]!
        let sirve: (Plantilla) -> Bool = { $0.nombre.range(of: re, options: .regularExpression) != nil }
        guard let p = plantillas.first(where: { ($0.categoria ?? "").uppercased() == "UTILITY" && sirve($0) }) ?? plantillas.first(where: sirve) else {
            return .waMe(waMe(tel, texto) ?? URL(string: "https://wa.me")!)
        }
        let n = p.parametros ?? 0
        let ps = (0..<n).map { $0 < parametros.count ? parametros[$0] : "" }
        struct DP: Encodable { var nombre: String; var idioma: String; var parametros: [String] }
        struct E: Encodable { var contactoId: String; var plantilla: DP }
        try await api.hacer("POST", "/v1/whatsapp/plantillas/enviar", E(contactoId: contactoId, plantilla: DP(nombre: p.nombre, idioma: p.idioma, parametros: ps)))
        return .porCorredor
    }

    /// Lo que salió por WhatsApp de un período.
    struct EnvioPeriodo { var enviadas = 0; var sinTelefono: [String] = []; var sinWhatsApp = false; var fallidas: [String] = [] }

    /// Manda por WhatsApp la liquidación del período a cada propietario con teléfono, con un link nuevo
    /// al recibo (como `liquidacionesPorWhatsApp` de la web). Sin el número conectado no sale nada.
    static func liquidaciones(_ api: Api, consorcio: String, periodo: String) async throws -> EnvioPeriodo {
        let ficha: PeriodoAPI = try await api.get("/v1/consorcios/\(consorcio)/periodos/\(periodo)")
        var out = EnvioPeriodo()
        let hay = await conectado(api)
        for l in ficha.liquidaciones ?? [] {
            guard let pid = l.propietarioId, l.telefono?.nonEmpty != nil else {
                out.sinTelefono.append(l.unidad)
                continue
            }
            guard hay else { out.sinWhatsApp = true; continue }
            do {
                let link: LinkConsorcio = try await api.enviar("POST", "/v1/consorcios/\(consorcio)/liquidaciones/\(l.id)/link", [String: String]())
                let mes = Cons.nombreMes(l.periodo)
                let total = Formato.plata(l.total.rounded())
                let nombre = (l.propietario ?? "").split(separator: " ").first.map(String.init) ?? "Hola"
                let texto = "Hola \(nombre), ya está la liquidación de expensas de \(mes) de la unidad \(l.unidad): \(total). El detalle, los comprobantes y cómo pagar: \(link.url)"
                let r = try await mandar(api, contactoId: pid, texto: texto, para: "expensas", parametros: [nombre, mes, l.unidad, total, link.url], conectado: true)
                if case .porCorredor = r { out.enviadas += 1 } else { out.fallidas.append(l.unidad) }
            } catch {
                out.fallidas.append(l.unidad)
            }
        }
        return out
    }
}
