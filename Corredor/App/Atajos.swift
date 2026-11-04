import ActivityKit
import AppIntents
import CoreSpotlight
import SwiftUI
import UIKit

// 14F–14H: el menú del ícono, Spotlight, Atajos y Siri, y la Live Activity de la próxima visita.

/// Abre la app en una ruta (lo usan los atajos y el menú del ícono).
@MainActor
enum Abrir {
    static weak var estado: Estado?
    static var pendiente: Ruta?

    static func ir(_ r: Ruta) {
        if let estado, estado.fase == .adentro { estado.ir(r) } else { pendiente = r }
    }
}

struct CaptarConMira: AppIntent {
    static let title: LocalizedStringResource = "Captar con MIRA"
    static let description = IntentDescription("Abre la cámara de MIRA para fotografiar un cartel.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        Abrir.ir(Ruta(.mira))
        return .result()
    }
}

struct NuevaVisitaIntent: AppIntent {
    static let title: LocalizedStringResource = "Nueva visita en Corredor"
    static let description = IntentDescription("Agenda una visita.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        Abrir.ir(Ruta(.agenda, AAgendaDia()))
        return .result()
    }
}

struct ConsultasSinResponder: AppIntent {
    static let title: LocalizedStringResource = "Consultas sin responder"
    static let description = IntentDescription("Abre los mensajes pendientes.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        Abrir.ir(Ruta(.mensajes))
        return .result()
    }
}

struct CobrosDeHoy: AppIntent {
    static let title: LocalizedStringResource = "Cobros de hoy"
    static let description = IntentDescription("Abre lo que falta cobrar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        Abrir.ir(Ruta(.inicio, ACobranzas()))
        return .result()
    }
}

/// Los atajos que aparecen solos en Atajos y Siri: «Captar con MIRA», «Nueva visita en Corredor».
struct AtajosCorredor: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptarConMira(), phrases: ["Captar con MIRA en \(.applicationName)", "Captar con \(.applicationName)"],
                    shortTitle: "Captar con MIRA", systemImageName: "viewfinder")
        AppShortcut(intent: NuevaVisitaIntent(), phrases: ["Nueva visita en \(.applicationName)"], shortTitle: "Nueva visita", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: ConsultasSinResponder(), phrases: ["Consultas sin responder en \(.applicationName)"], shortTitle: "Sin responder", systemImageName: "bubble.left.and.bubble.right")
        AppShortcut(intent: CobrosDeHoy(), phrases: ["Cobros de hoy en \(.applicationName)"], shortTitle: "Cobros de hoy", systemImageName: "dollarsign.circle")
    }
}

/// 14F El menú del ícono (mantener apretado): las cuatro acciones rápidas.
enum MenuIcono {
    static func cargar() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: "mira", localizedTitle: "Captar con MIRA", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "viewfinder")),
            UIApplicationShortcutItem(type: "agenda", localizedTitle: "Nueva visita", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "calendar.badge.plus")),
            UIApplicationShortcutItem(type: "buscar", localizedTitle: "Buscar", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass")),
            UIApplicationShortcutItem(type: "mensajes", localizedTitle: "Consultas sin responder", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right")),
        ]
    }

    @MainActor
    static func abrir(_ tipo: String) {
        switch tipo {
        case "mira": Abrir.ir(Ruta(.mira))
        case "agenda": Abrir.ir(Ruta(.agenda, AAgendaDia()))
        case "buscar": Abrir.ir(Ruta(.inicio, ABuscar()))
        default: Abrir.ir(Ruta(.mensajes))
        }
    }
}

/// La escena: recibe el menú del ícono con la app cerrada o abierta.
final class EscenaDelegado: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let s = options.shortcutItem { Task { @MainActor in MenuIcono.abrir(s.type) } }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await MainActor.run { MenuIcono.abrir(shortcutItem.type) }
        return true
    }
}

/// 14G Spotlight: las propiedades y los contactos aparecen al buscar en el iPhone.
enum Spotlight {
    static func indexar(propiedades: [Propiedad]) {
        let items = propiedades.prefix(500).map { p -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = p.nombre
            a.contentDescription = "\(p.precioTexto) · \(p.resumen)"
            a.keywords = [p.barrio, p.direccion, p.numero.map { "LP-\($0)" }].compactMap { $0 }
            return CSSearchableItem(uniqueIdentifier: "propiedad/\(p.id)", domainIdentifier: "propiedades", attributeSet: a)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["propiedades"]) { _ in
            CSSearchableIndex.default().indexSearchableItems(Array(items))
        }
    }

    static func indexar(contactos: [Contacto]) {
        let items = contactos.prefix(1000).map { c -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .contact)
            a.title = c.nombre
            a.contentDescription = [c.tipoTexto, c.telefono].compactMap { $0 }.joined(separator: " · ")
            if let t = c.telefono { a.phoneNumbers = [t] }
            return CSSearchableItem(uniqueIdentifier: "contacto/\(c.id)", domainIdentifier: "contactos", attributeSet: a)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["contactos"]) { _ in
            CSSearchableIndex.default().indexSearchableItems(Array(items))
        }
    }

    static func olvidar() { CSSearchableIndex.default().deleteAllSearchableItems() }
}

/// 14A, 14D La Live Activity de la próxima visita: arranca una hora antes y se termina al pasar.
enum ActividadVisita {
    /// La API manda las actualizaciones (cambio de hora, hecha, cancelada) a este token.
    @MainActor static weak var api: Api?

    static func actualizar(_ cita: Cita?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let actuales = Activity<VisitaActividad>.activities
        guard let c = cita, c.empiezaEn.timeIntervalSinceNow < 3600, c.terminaEn > Date(), c.estado != "cancelada" else {
            for a in actuales { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let estado = VisitaActividad.ContentState(empieza: c.empiezaEn, estado: c.estado ?? "pendiente")
        if let a = actuales.first(where: { $0.attributes.citaId == c.id }) {
            Task { await a.update(ActivityContent(state: estado, staleDate: c.terminaEn)) }
        } else {
            for a in actuales { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            guard let a = try? Activity.request(attributes: VisitaActividad(citaId: c.id, donde: c.donde, con: c.contactoNombre),
                                                content: ActivityContent(state: estado, staleDate: c.terminaEn), pushType: .token) else { return }
            Task {
                for await t in a.pushTokenUpdates {
                    let hex = t.map { String(format: "%02x", $0) }.joined()
                    struct C: Encodable {
                        var token: String
                        var citaId: String
                        #if DEBUG
                        var entorno = "sandbox"
                        #else
                        var entorno = "produccion"
                        #endif
                    }
                    try? await api?.hacer("POST", "/v1/push/actividades", C(token: hex, citaId: c.id))
                }
            }
        }
    }
}
