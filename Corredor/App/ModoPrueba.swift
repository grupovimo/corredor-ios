import Foundation

/// Los recorridos de XCUITest (PruebasUI/, en GitHub): la app arranca con `-ModoPruebaUI YES
/// -CorredorApi http://127.0.0.1:8787 -CorredorToken prueba` contra la API grabada, ya adentro, sin el
/// recorrido, sin consejos y sin pedir permiso de avisos (el sistema no deja concederlo de antemano).
/// Sólo existe en Debug: lo que sube a TestFlight (Release) nunca entra en este modo.
enum ModoPrueba {
    static var activo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "ModoPruebaUI")
        #else
        false
        #endif
    }

    /// El token de la sesión de prueba (la API grabada no lo valida).
    static var token: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CorredorToken")
        #else
        nil
        #endif
    }
}
