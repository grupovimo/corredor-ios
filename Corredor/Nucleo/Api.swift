import Foundation

/// Un error de la API (application/problem+json) o de la red, con lo que hay que decirle a la persona.
struct ErrorApi: Error, Equatable {
    var estado: Int
    var codigo: String
    var titulo: String
    var detalle: String
    /// Ingreso con contraseña: intentos que quedan antes de pausarlo.
    var restantes: Int?
    /// Segundos para volver a probar (429).
    var reintentarEn: Int?

    var sinConexion: Bool { codigo == "sin_conexion" }
    var sinSesion: Bool { estado == 401 && codigo == "sin_sesion" }

    static let sinRed = ErrorApi(estado: 0, codigo: "sin_conexion", titulo: "Sin conexión",
                                 detalle: "No hay internet. Revisá la conexión y probá de nuevo.")
    static let desconocido = ErrorApi(estado: 0, codigo: "interno", titulo: "Algo salió mal",
                                      detalle: "Probá de nuevo en un rato.")
}

/// El cliente de la API de Corredor (crm-inmobiliaria, rama corredor, api/). Va directo contra
/// api.corredor.com.ar con la sesión propia en `Authorization: Bearer`.
final class Api: @unchecked Sendable {
    let base: URL
    var token: String?
    /// Se llama cuando la API dice que la sesión ya no vale (401 sin_sesion): la app vuelve al ingreso.
    var alPerderSesion: (@MainActor () -> Void)?
    private let http: URLSession

    init(base: URL, token: String? = nil, http: URLSession = .shared) {
        self.base = base
        self.token = token
        self.http = http
    }

    /// La API de la configuración (Info.plist, CORREDOR_API). En Debug se puede pisar con el argumento
    /// `-CorredorApi http://127.0.0.1:4000` (el simulador contra la API local).
    static func urlConfigurada() -> URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "CorredorApi"), let u = URL(string: s) { return u }
        #endif
        let s = Bundle.main.object(forInfoDictionaryKey: "CorredorApi") as? String ?? ""
        return URL(string: s.isEmpty ? "https://api.corredor.com.ar" : s)!
    }

    /// La web de Corredor (para los links públicos: fichas, recibos, la web de la inmobiliaria).
    static func web() -> URL {
        let s = Bundle.main.object(forInfoDictionaryKey: "CorredorWeb") as? String ?? ""
        return URL(string: s.isEmpty ? "https://corredor.com.ar" : s)!
    }

    static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let f = Fecha.iso(s) { return f }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "fecha \(s)")
        }
        return d
    }()

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private struct Problema: Decodable {
        var status: Int?
        var code: String?
        var title: String?
        var detail: String?
        var restantes: Int?
    }

    func pedir(_ metodo: String, _ ruta: String, query: [URLQueryItem] = [], cuerpo: Data? = nil, envio: String? = nil) async throws -> Data {
        var c = URLComponents(url: base.appendingPathComponent(ruta), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!, timeoutInterval: 20)
        r.httpMethod = metodo
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        // Idempotencia: la misma Idempotency-Key no aplica dos veces la escritura.
        if let envio { r.setValue(envio, forHTTPHeaderField: "Idempotency-Key") }
        if let cuerpo {
            r.httpBody = cuerpo
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let datos: Data
        let resp: URLResponse
        do {
            (datos, resp) = try await http.data(for: r)
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            throw ErrorApi.sinRed
        }
        guard let h = resp as? HTTPURLResponse else { throw ErrorApi.desconocido }
        if (200..<300).contains(h.statusCode) { return datos }
        let p = (try? JSONDecoder().decode(Problema.self, from: datos)) ?? Problema()
        let e = ErrorApi(estado: h.statusCode, codigo: p.code ?? "interno", titulo: p.title ?? "Algo salió mal",
                         detalle: p.detail ?? "Probá de nuevo en un rato.", restantes: p.restantes,
                         reintentarEn: h.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        if e.sinSesion, token != nil, let alPerderSesion {
            await alPerderSesion()
        }
        throw e
    }

    func get<T: Decodable>(_ ruta: String, query: [URLQueryItem] = []) async throws -> T {
        try decodificar(await pedir("GET", ruta, query: query))
    }

    func enviar<T: Decodable, C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C) async throws -> T {
        try decodificar(await pedir(metodo, ruta, cuerpo: Api.codificador.encode(cuerpo)))
    }

    /// Un pedido sin respuesta (204).
    func hacer<C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C) async throws {
        _ = try await pedir(metodo, ruta, cuerpo: Api.codificador.encode(cuerpo))
    }

    func hacer(_ metodo: String, _ ruta: String) async throws {
        _ = try await pedir(metodo, ruta)
    }

    private func decodificar<T: Decodable>(_ d: Data) throws -> T {
        do {
            return try Api.decodificador.decode(T.self, from: d)
        } catch {
            #if DEBUG
            print("Api: no pude leer \(T.self): \(error)")
            #endif
            throw ErrorApi.desconocido
        }
    }
}

/// Lo último que se trajo de cada lista, para verlo sin conexión (handoff 5a: «Ves lo guardado hoy,
/// 14:20»). Un archivo por clave en Caches, con la fecha en que se guardó.
enum Guardado {
    private static var carpeta: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("guardado")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private static func archivo(_ clave: String) -> URL {
        carpeta.appendingPathComponent(clave.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? clave)
    }

    static func guardar<T: Encodable>(_ valor: T, clave: String) {
        guard let d = try? Api.codificador.encode(valor) else { return }
        try? d.write(to: archivo(clave), options: .atomic)
    }

    static func leer<T: Decodable>(_ tipo: T.Type, clave: String) -> (T, Date)? {
        let u = archivo(clave)
        guard let d = try? Data(contentsOf: u), let v = try? Api.decodificador.decode(T.self, from: d) else { return nil }
        let f = (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate] as? Date) ?? Date()
        return (v, f)
    }

    /// Al cerrar sesión o cambiar de inmobiliaria no queda nada de la anterior.
    static func borrarTodo() {
        try? FileManager.default.removeItem(at: carpeta)
    }
}

/// Un archivo subido (POST /v1/archivos?uso=foto|documento|audio|adjunto|marca).
struct Archivo: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String?
    var tipo: String?
    var bytes: Int?
    var url: String?
}

extension Api {
    /// Sube un archivo (multipart, campo `archivo`).
    func subir(_ datos: Data, nombre: String, tipo: String, uso: String) async throws -> Archivo {
        let limite = "corredor-\(UUID().uuidString)"
        var cuerpo = Data()
        cuerpo.append("--\(limite)\r\nContent-Disposition: form-data; name=\"archivo\"; filename=\"\(nombre)\"\r\nContent-Type: \(tipo)\r\n\r\n".data(using: .utf8)!)
        cuerpo.append(datos)
        cuerpo.append("\r\n--\(limite)--\r\n".data(using: .utf8)!)
        var c = URLComponents(url: base.appendingPathComponent("/v1/archivos"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "uso", value: uso)]
        var r = URLRequest(url: c.url!, timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(limite)", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.httpBody = cuerpo
        let (d, resp): (Data, URLResponse)
        do { (d, resp) = try await URLSession.shared.data(for: r) } catch { throw ErrorApi.sinRed }
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            struct P: Decodable { var detail: String?; var title: String? }
            let p = try? JSONDecoder().decode(P.self, from: d)
            throw ErrorApi(estado: (resp as? HTTPURLResponse)?.statusCode ?? 0, codigo: "archivo", titulo: p?.title ?? "No se subió",
                           detalle: p?.detail ?? "No se pudo subir el archivo.")
        }
        return try Api.decodificador.decode(Archivo.self, from: d)
    }
}
