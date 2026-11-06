import Foundation

/// Un 400 de la API con los errores por campo (`issues: [{path, message}]` del problem+json): las
/// hojas los muestran debajo de cada campo, como la web.
struct ErrorConCampos: Error {
    var error: ErrorApi
    /// Ruta → mensaje («direccion» → «Poné la dirección.»).
    var campos: [String: String]
}

extension Api {
    /// Como `enviar`/`hacer`, pero si la API rechaza los datos tira `ErrorConCampos` con cada campo.
    /// Los demás errores (sin red, 402, 409…) salen como `ErrorApi`, igual que siempre.
    func conCampos<C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C, envio: String? = nil) async throws -> Data {
        var c = URLComponents(url: base.appendingPathComponent(ruta.components(separatedBy: "?").first ?? ruta), resolvingAgainstBaseURL: false)!
        if let q = ruta.components(separatedBy: "?").dropFirst().first { c.query = q }
        var r = URLRequest(url: c.url!, timeoutInterval: 20)
        r.httpMethod = metodo
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let envio { r.setValue(envio, forHTTPHeaderField: "Idempotency-Key") }
        r.httpBody = try Api.codificador.encode(cuerpo)
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
        let p = (try? JSONDecoder().decode(ProblemaApi.self, from: datos)) ?? ProblemaApi()
        let e = ErrorApi(estado: h.statusCode, codigo: p.code ?? "interno", titulo: p.title ?? "Algo salió mal", detalle: p.detail ?? "Probá de nuevo en un rato.")
        if e.sinSesion, let alPerderSesion { await alPerderSesion() }
        let campos = Dictionary((p.issues ?? []).compactMap { c -> (String, String)? in
            guard let r = c.path, let m = c.message else { return nil }
            return (r, m)
        }, uniquingKeysWith: { a, _ in a })
        if !campos.isEmpty { throw ErrorConCampos(error: e, campos: campos) }
        throw e
    }

    /// `conCampos` que decodifica la respuesta.
    func conCampos<T: Decodable, C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C, envio: String? = nil, como: T.Type) async throws -> T {
        let d = try await conCampos(metodo, ruta, cuerpo, envio: envio)
        do { return try Api.decodificador.decode(T.self, from: d) } catch { throw ErrorApi.desconocido }
    }
}
