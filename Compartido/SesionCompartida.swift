import Foundation

/// La sesión compartida entre la app, los widgets y la Live Activity: el token va en el grupo del
/// Keychain (CorredorGrupoLlavero) y la URL de la API en UserDefaults del grupo de la app.
enum SesionCompartida {
    /// El grupo del Keychain compartido (del Info.plist, con el prefijo del equipo ya resuelto).
    static var grupo: String? {
        let g = Bundle.main.object(forInfoDictionaryKey: "CorredorGrupoLlavero") as? String
        return (g?.isEmpty ?? true) || g!.hasPrefix("$(") ? nil : g
    }

    static func guardar(token: String?, api: URL) {
        if let token { Llavero.guardar(token, cuenta: "token") }
        UserDefaults.standard.set(api.absoluteString, forKey: "api")
    }

    static var token: String? { Llavero.leer("token") }
}
