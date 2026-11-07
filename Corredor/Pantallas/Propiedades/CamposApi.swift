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
        do {
            return try await pedir(metodo, ruta, cuerpo: try Api.codificador.encode(cuerpo), envio: envio)
        } catch let e as ErrorApi where !e.campos.isEmpty {
            throw ErrorConCampos(error: e, campos: e.campos)
        }
    }

    /// `conCampos` que decodifica la respuesta.
    func conCampos<T: Decodable, C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C, envio: String? = nil, como: T.Type) async throws -> T {
        let d = try await conCampos(metodo, ruta, cuerpo, envio: envio)
        do { return try Api.decodificador.decode(T.self, from: d) } catch { throw ErrorApi.desconocido }
    }
}
