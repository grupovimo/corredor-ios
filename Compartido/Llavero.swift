import Foundation
import Security

/// La sesión de Corredor en el Keychain del iPhone: sólo este aparato (no viaja en las copias de
/// iCloud) y accesible después del primer desbloqueo, para que el push en segundo plano la pueda usar.
enum Llavero {
    static let servicio = "ar.com.corredor.app.sesion"

    private static func base(_ cuenta: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servicio,
                                kSecAttrAccount as String: cuenta]
        // El grupo compartido con los widgets y la Live Activity (CorredorGrupoLlavero en el Info.plist).
        if let g = SesionCompartida.grupo { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    static func guardar(_ valor: String, cuenta: String) {
        borrar(cuenta)
        var q = base(cuenta)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecValueData as String] = Data(valor.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func leer(_ cuenta: String) -> String? {
        var q = base(cuenta)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func borrar(_ cuenta: String) {
        SecItemDelete(base(cuenta) as CFDictionary)
    }
}
