import Foundation

/// El ingreso con mail completo, como la web (web/src/lib/clerk.ts, «Con mail»): según la cuenta,
/// contraseña o código por mail; alguien nuevo se da de alta con el código (y la contraseña, si la
/// instancia la pide); y recuperar el acceso (código `reset_password_email_code`, contraseña nueva y
/// cierre de las otras sesiones). Habla con la Frontend API de Clerk en modo nativo, igual que
/// `Clerk` (Nucleo/Clerk.swift), que tiene sus pedidos `fileprivate`: por eso el pedido va de nuevo
/// acá (con PATCH, que hace falta para la contraseña del alta).
final class ClerkMail {
    /// El paso que sigue en la pantalla.
    enum Paso: Equatable {
        case clave
        case codigo(alta: Bool)
        case claveNueva(alta: Bool)
        case listo(token: String)
    }

    let fapi: URL
    private let http: URLSession
    private var cliente = ""
    private var id = ""
    private(set) var alta = false

    init?(publicable: String?, http: URLSession = .shared) {
        guard let f = Clerk.fapiDe(publicable) else { return nil }
        fapi = f
        self.http = http
    }

    /// Con la clave publicable del Info.plist (la misma que usa `Estado` para Apple y Google).
    static func configurado() -> ClerkMail? {
        ClerkMail(publicable: Bundle.main.object(forInfoDictionaryKey: "ClerkPublicable") as? String)
    }

    private struct Factor: Decodable {
        var strategy: String?
        var email_address_id: String?
    }
    private struct Recurso: Decodable {
        var id: String?
        var status: String?
        var created_session_id: String?
        var supported_first_factors: [Factor]?
        var missing_fields: [String]?
    }
    private struct ErrorFapi: Decodable { var code: String? }
    private struct Respuesta: Decodable {
        var response: Recurso?
        var jwt: String?
        var errors: [ErrorFapi]?
    }

    private func pedir(_ ruta: String, _ metodo: String = "GET", cuerpo: [String: String]? = nil, conCliente: Bool = true) async throws -> Respuesta {
        var c = URLComponents(url: fapi.appendingPathComponent("v1" + ruta), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "_is_native", value: "1"), URLQueryItem(name: "__clerk_api_version", value: Clerk.versionFapi)]
        var r = URLRequest(url: c.url!)
        r.httpMethod = metodo
        if conCliente, !cliente.isEmpty { r.setValue(cliente, forHTTPHeaderField: "Authorization") }
        if let cuerpo {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(Clerk.formulario(cuerpo).utf8)
        }
        let datos: Data
        let resp: URLResponse
        do {
            (datos, resp) = try await http.data(for: r)
        } catch {
            throw Clerk.ErrorClerk(codigo: "sin_conexion")
        }
        let respuesta = (try? JSONDecoder().decode(Respuesta.self, from: datos)) ?? Respuesta()
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            throw Clerk.ErrorClerk(codigo: respuesta.errors?.first?.code ?? "clerk_no_responde")
        }
        // Clerk rota el token del cliente: vale el último que mandó.
        if let nuevo = h.value(forHTTPHeaderField: "authorization"), !nuevo.isEmpty { cliente = nuevo }
        return respuesta
    }

    /// El JWT de la sesión de Clerk; la sesión de Clerk se cierra (Corredor sigue con la propia).
    private func sesionDe(_ sesion: String?) async throws -> String {
        guard let sesion, sesion.range(of: "^sess_[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw Clerk.ErrorClerk(codigo: "cancelado")
        }
        let t = try await pedir("/client/sessions/\(sesion)/tokens", "POST", cuerpo: [:])
        guard let jwt = t.jwt, !jwt.isEmpty else { throw Clerk.ErrorClerk(codigo: "clerk_no_responde") }
        _ = try? await pedir("/client/sessions/\(sesion)/remove", "POST", cuerpo: [:])
        return jwt
    }

    /// Arranca con el mail: si tiene cuenta, ingreso (contraseña o código); si no, alta con código.
    func empezar(email: String) async throws -> Paso {
        cliente = ""
        do {
            let r = try await pedir("/client/sign_ins", "POST", cuerpo: ["identifier": email], conCliente: false)
            id = r.response?.id ?? ""
            alta = false
            let factores = r.response?.supported_first_factors ?? []
            if factores.contains(where: { $0.strategy == "password" }) { return .clave }
            guard let mail = factores.first(where: { $0.strategy == "email_code" })?.email_address_id else {
                throw Clerk.ErrorClerk(codigo: "sin_mail")
            }
            _ = try await pedir("/client/sign_ins/\(id)/prepare_first_factor", "POST", cuerpo: ["strategy": "email_code", "email_address_id": mail])
            return .codigo(alta: false)
        } catch let e as Clerk.ErrorClerk where e.codigo == "form_identifier_not_found" {
            // Alta: el mail, y verificarlo con un código.
            cliente = ""
            let a = try await pedir("/client/sign_ups", "POST", cuerpo: ["email_address": email], conCliente: false)
            id = a.response?.id ?? ""
            alta = true
            _ = try await pedir("/client/sign_ups/\(id)/prepare_verification", "POST", cuerpo: ["strategy": "email_code"])
            return .codigo(alta: true)
        }
    }

    /// Con la contraseña de la cuenta.
    func entrarConClave(_ clave: String) async throws -> Paso {
        let r = try await pedir("/client/sign_ins/\(id)/attempt_first_factor", "POST", cuerpo: ["strategy": "password", "password": clave])
        return .listo(token: try await sesionDe(r.response?.created_session_id))
    }

    /// El código que llegó por mail (ingreso, alta o recuperar).
    func confirmarCodigo(_ codigo: String, recuperar: Bool = false) async throws -> Paso {
        let ruta = alta ? "/client/sign_ups/\(id)/attempt_verification" : "/client/sign_ins/\(id)/attempt_first_factor"
        let solo = codigo.filter(\.isNumber)
        let r = try await pedir(ruta, "POST", cuerpo: ["strategy": recuperar ? "reset_password_email_code" : "email_code", "code": solo])
        if r.response?.status == "needs_new_password" { return .claveNueva(alta: false) }
        // La instancia pide contraseña para el alta.
        if alta, r.response?.status == "missing_requirements", r.response?.missing_fields?.contains("password") == true {
            return .claveNueva(alta: true)
        }
        return .listo(token: try await sesionDe(r.response?.created_session_id))
    }

    /// La contraseña nueva: al recuperar (cierra las otras sesiones de Clerk) o la que pide el alta.
    func guardarClave(_ clave: String) async throws -> Paso {
        let r: Respuesta
        if alta {
            r = try await pedir("/client/sign_ups/\(id)", "PATCH", cuerpo: ["password": clave])
        } else {
            r = try await pedir("/client/sign_ins/\(id)/reset_password", "POST", cuerpo: ["password": clave, "sign_out_of_other_sessions": "true"])
        }
        return .listo(token: try await sesionDe(r.response?.created_session_id))
    }

    /// Recuperar: arranca el ingreso con el mail y pide el código para la contraseña nueva. `false`
    /// si el mail no tiene cuenta o no usa contraseña (la pantalla dice lo mismo: no se revela quién
    /// está registrado).
    func pedirRecuperar(email: String) async throws -> Bool {
        cliente = ""
        alta = false
        let r: Respuesta
        do {
            r = try await pedir("/client/sign_ins", "POST", cuerpo: ["identifier": email], conCliente: false)
        } catch let e as Clerk.ErrorClerk where e.codigo == "form_identifier_not_found" {
            return false
        }
        id = r.response?.id ?? ""
        guard let mail = r.response?.supported_first_factors?.first(where: { $0.strategy == "reset_password_email_code" })?.email_address_id else {
            return false
        }
        _ = try await pedir("/client/sign_ins/\(id)/prepare_first_factor", "POST",
                            cuerpo: ["strategy": "reset_password_email_code", "email_address_id": mail])
        return true
    }

    // MARK: Requisitos y mensajes (los mismos de la web)

    private static let comunes: Set<String> = [
        "1234567890", "12345678910", "qwertyuiop", "contraseña", "contrasena", "password12", "password123", "argentina1",
        "0123456789", "1111111111", "abcdefghij", "corredor123", "inmobiliaria", "iloveyou12", "boca123456", "river12345",
    ]

    /// Los requisitos de la contraseña nueva que se tildan solos (2c).
    static func requisitos(_ clave: String) -> (largo: Bool, comun: Bool) {
        (clave.count >= 10, !clave.isEmpty && !esComun(clave))
    }

    private static func esComun(_ c: String) -> Bool {
        let x = c.lowercased()
        if comunes.contains(x) { return true }
        if x.count > 1, let p = x.first, x.allSatisfy({ $0 == p }) { return true }
        return x.hasPrefix("0123456789") || x.hasPrefix("1234567890") || x.hasPrefix("9876543210")
    }

    /// El error de Clerk como lo lee la persona.
    static func mensaje(_ codigo: String) -> String {
        let m: [String: String] = [
            "form_password_incorrect": "La contraseña no es esa. Probá de nuevo o recuperala.",
            "form_code_incorrect": "El código no es ese. Revisalo y probá de nuevo.",
            "verification_expired": "El código venció. Pedí uno nuevo.",
            "form_password_pwned": "Esa contraseña apareció en filtraciones. Elegí otra.",
            "form_password_length_too_short": "La contraseña es muy corta.",
            "form_password_validation_failed": "La contraseña no cumple los requisitos.",
            "form_param_format_invalid": "Revisá el mail: no parece válido.",
            "form_identifier_exists": "Ese mail ya tiene cuenta. Ingresá.",
            "too_many_requests": "Hubo demasiados intentos. Probá de nuevo en unos minutos.",
            "strategy_for_user_invalid": "Esa cuenta entra con Google o Apple: usá ese botón.",
            "sin_mail": "Esa cuenta entra con Google o Apple: usá ese botón.",
            "sin_conexion": "No pudimos conectar. Probá de nuevo.",
        ]
        return m[codigo] ?? "No pudimos completar el ingreso. Probá de nuevo."
    }
}
