import UIKit
import UserNotifications

/// El delegado de la app para APNs: registra el token (`POST /v1/push/dispositivos`), muestra los
/// avisos con la app abierta, abre la pantalla exacta al tocarlos (`ruta` del payload) y resuelve las
/// acciones del aviso expandido (14B) y la respuesta escrita desde el aviso (14C).
final class Delegado: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var estado: Estado?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 14B–14C: un WhatsApp o una pregunta de ML se responden sin abrir la app; un cobro se registra
        // pidiendo desbloquear el iPhone.
        let responder = UNTextInputNotificationAction(identifier: "responder", title: "Responder", options: [.authenticationRequired],
                                                      textInputButtonTitle: "Enviar", textInputPlaceholder: "Escribí tu respuesta")
        let ver = UNNotificationAction(identifier: "ver", title: "Abrir", options: [.foreground])
        let llamar = UNNotificationAction(identifier: "llamar", title: "Llamar", options: [.foreground])
        let cobrar = UNNotificationAction(identifier: "cobrar", title: "Registrar cobro", options: [.authenticationRequired, .foreground])
        let confirmar = UNNotificationAction(identifier: "confirmar", title: "Confirmar visita", options: [.authenticationRequired])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "mensaje", actions: [responder, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "consulta", actions: [responder, llamar, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "cobro", actions: [cobrar, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "visita", actions: [confirmar, ver], intentIdentifiers: []),
        ])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await self.estado?.registrarTokenPush(hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs: \(error.localizedDescription)")
        #endif
    }

    // Con la app abierta, el aviso se ve igual (banner, sonido y lista) y las listas se refrescan.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await MainActor.run { self.estado?.version += 1 }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let ruta = (info["ruta"] as? String).flatMap(Ruta.init(texto:))
        let accion = response.actionIdentifier
        let respuesta = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            guard let estado = self.estado else { return }
            switch accion {
            case "responder":
                guard let texto = respuesta?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty else { return }
                Task { await Delegado.responder(estado, ruta: ruta, texto: texto, info: info) }
            case "confirmar":
                if let id = info["citaId"] as? String {
                    Task {
                        struct Cuerpo: Encodable { var estado = "confirmada" }
                        try? await estado.api.hacer("PATCH", "/v1/agenda/\(id)", Cuerpo())
                    }
                }
            case "llamar":
                if let t = info["telefono"] as? String, let u = URL(string: "tel://" + t.filter { $0.isNumber || $0 == "+" }) {
                    UIApplication.shared.open(u)
                }
            default:
                if let ruta { estado.ir(ruta) }
            }
        }
    }

    /// 14C: la respuesta escrita en el aviso va al chat de WhatsApp o a la pregunta de ML.
    @MainActor
    private static func responder(_ estado: Estado, ruta: Ruta?, texto: String, info: [AnyHashable: Any]) async {
        struct Mensaje: Encodable { var texto: String }
        do {
            if let c = ruta?.destino as? AChat {
                try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(c.id)/mensajes", Mensaje(texto: texto))
            } else if let p = ruta?.destino as? APreguntaML {
                try await estado.api.hacer("POST", "/v1/mercadolibre/preguntas/\(p.id)/respuesta", Mensaje(texto: texto))
            }
            estado.version += 1
        } catch {
            // Si no salió, se abre el chat con lo escrito para mandarlo a mano.
            if let ruta { estado.ir(ruta) }
            estado.avisar("No se mandó la respuesta. Probá desde el chat.", ok: false)
        }
    }
}
