import AuthenticationServices
import Foundation
import UIKit

/// Ingreso con Apple y Google por Clerk, la identidad compartida de Grupo Vimo, sin el SDK: se habla
/// con la Frontend API en modo nativo (`_is_native=1`), con el token del cliente de Clerk en
/// `Authorization`. Es el mismo flujo que la web (apps/web/src/lib/clerk.ts) y que Caigo:
///
/// - Apple: la hoja nativa de Sign in with Apple da el identity token y se canjea con
///   `strategy=oauth_token_apple` (si la persona es nueva en Clerk, el intento queda «transferable» y
///   se pasa a `sign_ups` con `transfer=true`).
/// - Google: `oauth_google` con `redirect_url = ar.com.corredor.app://callback`, abierto con
///   ASWebAuthenticationSession; la vuelta trae `rotating_token_nonce`.
///
/// En los dos casos se pide el JWT de la sesión de Clerk, se cierra esa sesión (Corredor sigue con
/// la propia) y el JWT va a `POST /v1/auth/clerk`, que lo verifica y devuelve la sesión.
/// La clave publicable (de la que sale la Frontend API) la da la API en /v1/auth/proveedores.
final class Clerk {
    struct ErrorClerk: Error { var codigo: String }

    static let versionFapi = "2025-11-10"
    static let esquema = "ar.com.corredor.app"
    static let vuelta = "ar.com.corredor.app://callback"

    let fapi: URL
    private let http: URLSession

    init?(publicable: String?, http: URLSession = .shared) {
        guard let f = Clerk.fapiDe(publicable) else { return nil }
        fapi = f
        self.http = http
    }

    /// La Frontend API sale de la clave publicable: pk_<entorno>_<base64("host$")>.
    static func fapiDe(_ publicable: String?) -> URL? {
        guard let p = publicable else { return nil }
        let partes = p.split(separator: "_", maxSplits: 2).map(String.init)
        guard partes.count == 3, partes[0] == "pk", partes[1] == "live" || partes[1] == "test" else { return nil }
        var b = partes[2].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let datos = Data(base64Encoded: b), var host = String(data: datos, encoding: .utf8) else { return nil }
        if host.hasSuffix("$") { host.removeLast() }
        let valido = host.range(of: "^[a-z0-9.-]+\\.[a-z]{2,}$", options: [.regularExpression, .caseInsensitive]) != nil
        return valido ? URL(string: "https://\(host)") : nil
    }

    fileprivate struct Verificacion: Decodable {
        var status: String?
        var external_verification_redirect_url: String?
    }
    fileprivate struct Factor: Decodable {
        var strategy: String?
        var email_address_id: String?
    }
    fileprivate struct Recurso: Decodable {
        var id: String?
        var status: String?
        var created_session_id: String?
        var first_factor_verification: Verificacion?
        var supported_first_factors: [Factor]?
    }
    fileprivate struct ErrorFapi: Decodable { var code: String? }
    fileprivate struct Respuesta: Decodable {
        var response: Recurso?
        var jwt: String?
        var errors: [ErrorFapi]?
    }

    fileprivate func pedir(_ ruta: String, _ metodo: String = "GET", cuerpo: [String: String]? = nil,
                       cliente: String? = nil, query: [URLQueryItem] = []) async throws -> (Respuesta, String) {
        var c = URLComponents(url: fapi.appendingPathComponent("v1" + ruta), resolvingAgainstBaseURL: false)!
        c.queryItems = query + [URLQueryItem(name: "_is_native", value: "1"),
                                URLQueryItem(name: "__clerk_api_version", value: Clerk.versionFapi)]
        var r = URLRequest(url: c.url!)
        r.httpMethod = metodo
        if let cliente, !cliente.isEmpty { r.setValue(cliente, forHTTPHeaderField: "Authorization") }
        if metodo == "POST" {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(Clerk.formulario(cuerpo ?? [:]).utf8)
        }
        let (datos, resp) = try await http.data(for: r)
        let respuesta = (try? JSONDecoder().decode(Respuesta.self, from: datos)) ?? Respuesta()
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            throw ErrorClerk(codigo: respuesta.errors?.first?.code ?? "clerk_no_responde")
        }
        // Clerk rota el token del cliente: vale el último que mandó.
        let nuevo = h.value(forHTTPHeaderField: "authorization") ?? ""
        return (respuesta, nuevo.isEmpty ? (cliente ?? "") : nuevo)
    }

    static func formulario(_ d: [String: String]) -> String {
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-._~")
        return d.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: permitidos) ?? "")" }
            .joined(separator: "&")
    }

    /// Con el intento ya creado: si quedó «transferable» (persona nueva en Clerk) lo pasa a alta, pide
    /// el JWT de la sesión y la cierra.
    fileprivate func terminar(_ r: Respuesta, cliente: String) async throws -> String {
        var resp = r
        var cliente = cliente
        var sesion = resp.response?.created_session_id ?? ""
        if sesion.isEmpty, resp.response?.first_factor_verification?.status == "transferable" {
            (resp, cliente) = try await pedir("/client/sign_ups", "POST", cuerpo: ["transfer": "true"], cliente: cliente)
            sesion = resp.response?.created_session_id ?? ""
        }
        guard sesion.range(of: "^sess_[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw ErrorClerk(codigo: "cancelado")
        }
        let (t, clienteT) = try await pedir("/client/sessions/\(sesion)/tokens", "POST", cliente: cliente)
        guard let jwt = t.jwt, !jwt.isEmpty else { throw ErrorClerk(codigo: "clerk_no_responde") }
        _ = try? await pedir("/client/sessions/\(sesion)/remove", "POST", cliente: clienteT)
        return jwt
    }

    /// Apple: el identity token de la hoja nativa → JWT de sesión de Clerk.
    func conApple(tokenApple: String) async throws -> String {
        let (r, cliente) = try await pedir("/client/sign_ins", "POST", cuerpo: ["strategy": "oauth_token_apple", "token": tokenApple])
        return try await terminar(r, cliente: cliente)
    }

    /// Google: abre la hoja web del sistema y devuelve el JWT de sesión de Clerk.
    @MainActor
    func conGoogle() async throws -> String {
        let (r, cliente) = try await pedir("/client/sign_ins", "POST", cuerpo: ["strategy": "oauth_google", "redirect_url": Clerk.vuelta])
        guard let s = r.response?.first_factor_verification?.external_verification_redirect_url, let url = URL(string: s),
              let intento = r.response?.id, intento.range(of: "^sia_[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw ErrorClerk(codigo: "clerk_no_responde")
        }
        let vuelta = try await HojaWeb().abrir(url)
        let nonce = URLComponents(url: vuelta, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "rotating_token_nonce" }?.value
        let q = (nonce?.isEmpty == false) ? [URLQueryItem(name: "rotating_token_nonce", value: nonce)] : []
        do {
            let (r2, c2) = try await pedir("/client/sign_ins/\(intento)", cliente: cliente, query: q)
            return try await terminar(r2, cliente: c2)
        } catch let e as ErrorClerk where e.codigo == "external_account_not_found" {
            // Alguien nuevo vuelve sin nonce: va directo al alta.
            let (r3, c3) = try await pedir("/client/sign_ups", "POST", cuerpo: ["transfer": "true"], cliente: cliente)
            return try await terminar(r3, cliente: c3)
        }
    }
}

extension Clerk {
    /// Un ingreso con código por mail a medio hacer: el intento (o el alta, si la persona es nueva) y
    /// el token del cliente de Clerk.
    struct IntentoMail {
        fileprivate var id: String
        fileprivate var alta: Bool
        fileprivate var cliente: String
    }

    /// Mail: manda el código de 6 números. Si la persona no existe en Clerk, arranca el alta.
    func pedirCodigo(email: String) async throws -> IntentoMail {
        do {
            let (r, cliente) = try await pedir("/client/sign_ins", "POST", cuerpo: ["identifier": email])
            guard let id = r.response?.id,
                  let mail = r.response?.supported_first_factors?.first(where: { $0.strategy == "email_code" })?.email_address_id else {
                throw ErrorClerk(codigo: "sin_codigo")
            }
            let (_, c2) = try await pedir("/client/sign_ins/\(id)/prepare_first_factor", "POST",
                                          cuerpo: ["strategy": "email_code", "email_address_id": mail], cliente: cliente)
            return IntentoMail(id: id, alta: false, cliente: c2)
        } catch let e as ErrorClerk where e.codigo == "form_identifier_not_found" {
            let (r, cliente) = try await pedir("/client/sign_ups", "POST", cuerpo: ["email_address": email])
            guard let id = r.response?.id else { throw ErrorClerk(codigo: "clerk_no_responde") }
            let (_, c2) = try await pedir("/client/sign_ups/\(id)/prepare_verification", "POST",
                                          cuerpo: ["strategy": "email_code"], cliente: cliente)
            return IntentoMail(id: id, alta: true, cliente: c2)
        }
    }

    /// El código que llegó por mail → JWT de sesión de Clerk.
    func conCodigo(_ i: IntentoMail, codigo: String) async throws -> String {
        let ruta = i.alta ? "/client/sign_ups/\(i.id)/attempt_verification" : "/client/sign_ins/\(i.id)/attempt_first_factor"
        let (r, cliente) = try await pedir(ruta, "POST", cuerpo: ["strategy": "email_code", "code": codigo], cliente: i.cliente)
        return try await terminar(r, cliente: cliente)
    }
}

/// La hoja web del sistema para el ida y vuelta con Google.
@MainActor
final class HojaWeb: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var sesion: ASWebAuthenticationSession?

    func abrir(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: Clerk.esquema) { vuelta, error in
                if let vuelta {
                    cont.resume(returning: vuelta)
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: Clerk.ErrorClerk(codigo: "cancelado"))
                } else {
                    cont.resume(throwing: error ?? Clerk.ErrorClerk(codigo: "clerk_no_responde"))
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            sesion = s
            if !s.start() { cont.resume(throwing: Clerk.ErrorClerk(codigo: "clerk_no_responde")) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Ventana.principal() ?? ASPresentationAnchor() }
    }
}

/// La hoja nativa de Sign in with Apple: devuelve el identity token (JWT de Apple).
@MainActor
final class HojaApple: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var cont: CheckedContinuation<String, Error>?
    private var controlador: ASAuthorizationController?

    func pedirToken() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            cont = c
            let pedido = ASAuthorizationAppleIDProvider().createRequest()
            pedido.requestedScopes = [.fullName, .email]
            let ctl = ASAuthorizationController(authorizationRequests: [pedido])
            ctl.delegate = self
            ctl.presentationContextProvider = self
            controlador = ctl
            ctl.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let token = (authorization.credential as? ASAuthorizationAppleIDCredential)?.identityToken
            .flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let token { cont?.resume(returning: token) } else { cont?.resume(throwing: Clerk.ErrorClerk(codigo: "clerk_no_responde")) }
            cont = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            if let e = error as? ASAuthorizationError, e.code == .canceled {
                cont?.resume(throwing: Clerk.ErrorClerk(codigo: "cancelado"))
            } else {
                cont?.resume(throwing: error)
            }
            cont = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Ventana.principal() ?? ASPresentationAnchor() }
    }
}

enum Ventana {
    @MainActor
    static func principal() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }
}
