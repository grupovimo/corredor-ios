import ActivityKit
import Foundation

/// Lo que muestran los widgets (14A, 14E): la próxima visita, lo sin responder y los cobros de hoy.
/// El widget lo pide a la API con la sesión compartida del Keychain (sin App Group: no hace falta
/// tocar los perfiles de firma) y guarda lo último para mostrarlo sin señal.
struct Hoy: Codable {
    struct Visita: Codable {
        var id: String
        var donde: String
        var con: String?
        var empieza: Date
    }
    struct Mensaje: Codable {
        var id: String
        var quien: String
        var canal: String
        var cuando: Date?
    }
    var visita: Visita?
    var sinResponder: Int
    var mensajes: [Mensaje]
    var cobrosHoy: Int
    var actualizado: Date

    static let vacio = Hoy(visita: nil, sinResponder: 0, mensajes: [], cobrosHoy: 0, actualizado: .distantPast)

    private static var archivo: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("hoy.json")
    }

    static func leer() -> Hoy {
        guard let u = archivo, let d = try? Data(contentsOf: u) else { return .vacio }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Hoy.self, from: d)) ?? .vacio
    }

    func guardar() {
        guard let u = Hoy.archivo else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(self).write(to: u, options: .atomic)
    }
}

extension Hoy {
    /// Lo pide a la API (la próxima visita de hoy y lo sin responder) con el token compartido.
    static func traer() async -> Hoy {
        guard let token = Llavero.leer("token"),
              let base = (Bundle.main.object(forInfoDictionaryKey: "CorredorApi") as? String).flatMap(URL.init(string:)) else { return leer() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let x = f.date(from: s) { return x }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s) ?? Date.distantPast
        }
        func get<T: Decodable>(_ ruta: String, _ q: String = "") async -> T? {
            var r = URLRequest(url: URL(string: base.absoluteString + ruta + q)!, timeoutInterval: 15)
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try? dec.decode(T.self, from: d)
        }
        struct Cita: Decodable { var id: String; var empiezaEn: Date; var propiedadTitulo: String?; var lugar: String?; var titulo: String?; var contactoNombre: String?; var estado: String? }
        struct Panel: Decodable { var agendaHoy: [Cita]? }
        struct Conv: Decodable { var id: String; var contactoNombre: String?; var nombre: String?; var noLeidos: Int?; var ultimoMensajeEn: Date? }
        guard let p: Panel = await get("/v1/panel") else { return leer() }
        let convs: [Conv] = await get("/v1/whatsapp/conversaciones", "?noLeidas=si&limite=20") ?? []
        let v = (p.agendaHoy ?? []).filter { $0.empiezaEn.addingTimeInterval(3600) > Date() && $0.estado != "cancelada" }.sorted { $0.empiezaEn < $1.empiezaEn }.first
        let h = Hoy(visita: v.map { Visita(id: $0.id, donde: $0.propiedadTitulo ?? $0.lugar ?? $0.titulo ?? "Visita", con: $0.contactoNombre, empieza: $0.empiezaEn) },
                    sinResponder: convs.reduce(0) { $0 + ($1.noLeidos ?? 0) },
                    mensajes: convs.prefix(3).map { Mensaje(id: $0.id, quien: $0.contactoNombre ?? $0.nombre ?? "Sin nombre", canal: "wa", cuando: $0.ultimoMensajeEn) },
                    cobrosHoy: 0, actualizado: Date())
        h.guardar()
        return h
    }
}

/// La Live Activity de la próxima visita (14A, 14D): dónde, con quién y cuánto falta.
struct VisitaActividad: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var empieza: Date
        var estado: String
    }
    var citaId: String
    var donde: String
    var con: String?
}
