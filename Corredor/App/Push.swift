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
        // pidiendo desbloquear el iPhone. La consulta (`/contactos/<id>`) no tiene un canal donde mandar
        // la respuesta: se llama o se abre, sin «Responder».
        let responder = UNTextInputNotificationAction(identifier: "responder", title: "Responder", options: [.authenticationRequired],
                                                      textInputButtonTitle: "Enviar", textInputPlaceholder: "Escribí tu respuesta")
        let ver = UNNotificationAction(identifier: "ver", title: "Abrir", options: [.foreground])
        let llamar = UNNotificationAction(identifier: "llamar", title: "Llamar", options: [.foreground])
        let cobrar = UNNotificationAction(identifier: "cobrar", title: "Registrar cobro", options: [.authenticationRequired, .foreground])
        let hecha = UNNotificationAction(identifier: "hecha", title: "Marcar como hecha", options: [.authenticationRequired])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "mensaje", actions: [responder, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "consulta", actions: [llamar, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "cobro", actions: [cobrar, ver], intentIdentifiers: []),
            UNNotificationCategory(identifier: "visita", actions: [ver, hecha], intentIdentifiers: []),
        ])
        MenuIcono.cargar()
        return true
    }

    // El menú del ícono llega por la escena (14F).
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = EscenaDelegado.self
        return c
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
                Task { await Delegado.responder(estado, ruta: ruta, rutaTexto: info["ruta"] as? String, texto: texto) }
            case "hecha":
                if let id = (ruta?.destino as? ACita)?.id ?? info["citaId"] as? String {
                    Task {
                        struct Cuerpo: Encodable { var estado = "hecha" }
                        try? await estado.api.hacer("PATCH", "/v1/agenda/\(id)", Cuerpo())
                    }
                }
            case "llamar":
                if let t = info["telefono"] as? String, let u = URL(string: "tel://" + t.filter { $0.isNumber || $0 == "+" }) {
                    UIApplication.shared.open(u, options: [:], completionHandler: nil)
                } else if let ruta {
                    // Sin teléfono en el aviso: el contacto, para llamarlo desde ahí.
                    estado.ir(ruta)
                }
            default:
                let aviso = info["avisoId"] as? String
                if accion != UNNotificationDefaultActionIdentifier, let aviso {
                    // Otra acción del aviso (las que pide la API): el aviso con esa acción abierta.
                    Avisos.abrir(estado, aviso: aviso, responder: accion)
                } else if let ruta {
                    estado.ir(ruta)
                } else if let aviso {
                    Avisos.abrir(estado, aviso: aviso, responder: nil)
                }
            }
        }
    }

    private struct SinDestino: Error {}

    /// 14C: la respuesta escrita en el aviso va al chat de WhatsApp o a la pregunta de ML. Si el aviso no
    /// lleva a ninguno de los dos, o la API no la toma, no se da por mandada: se avisa con lo escrito.
    @MainActor
    private static func responder(_ estado: Estado, ruta: Ruta?, rutaTexto: String?, texto: String) async {
        struct Mensaje: Encodable { var texto: String }
        do {
            if let c = ruta?.destino as? AChat {
                try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(c.id)/mensajes", Mensaje(texto: texto))
            } else if let p = ruta?.destino as? APreguntaML {
                try await estado.api.hacer("POST", "/v1/mercadolibre/preguntas/\(p.id)/respuesta", Mensaje(texto: texto))
            } else {
                throw SinDestino()
            }
            estado.version += 1
        } catch {
            noSeMando(estado, ruta: ruta, rutaTexto: rutaTexto, texto: texto)
        }
    }

    /// La respuesta no salió. Con la app abierta, el aviso de abajo y el chat; en segundo plano, una
    /// notificación con lo escrito que, al tocarla, abre la conversación para mandarlo a mano.
    @MainActor
    private static func noSeMando(_ estado: Estado, ruta: Ruta?, rutaTexto: String?, texto: String) {
        if UIApplication.shared.applicationState == .active {
            if let ruta { estado.ir(ruta) }
            estado.avisar("No se mandó la respuesta. Probá desde el chat.", ok: false)
            return
        }
        let c = UNMutableNotificationContent()
        c.title = "No se mandó tu respuesta"
        c.body = Formato.sinViudas("Escribiste: «\(texto)». Tocá acá para mandarla desde Corredor.")
        c.sound = .default
        if let rutaTexto { c.userInfo = ["ruta": rutaTexto] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "no-se-mando-\(UUID().uuidString)", content: c, trigger: nil))
    }
}
