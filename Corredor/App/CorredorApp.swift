import CoreSpotlight
import SwiftUI
import WidgetKit

@main
struct CorredorApp: App {
    @UIApplicationDelegateAdaptor(Delegado.self) private var delegado
    @State private var estado = Estado()
    @Environment(\.scenePhase) private var fase
    @AppStorage("tema") private var tema = "sistema"
    @State private var enSegundoPlano: Date?

    init() {
        Apariencia.aplicar()
        Consejos.configurar()
    }

    var body: some Scene {
        WindowGroup {
            GeometryReader { g in
                Raiz()
                    .environment(estado)
                    .environment(estado.cola)
                    .environment(\.anchoPantalla, g.size.width)
            }
            .preferredColorScheme(tema == "claro" ? .light : (tema == "oscuro" ? .dark : nil))
            .tint(C.accion)
            .onAppear {
                delegado.estado = estado
                Abrir.estado = estado
                ActividadVisita.api = estado.api
            }
            .onChange(of: estado.fase) { _, f in
                if f == .adentro, let r = Abrir.pendiente {
                    Abrir.pendiente = nil
                    estado.ir(r)
                }
                if f == .afuera { Spotlight.olvidar() }
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onContinueUserActivity(CSSearchableItemActionType) { a in
                if let id = a.userInfo?[CSSearchableItemActivityIdentifier] as? String, let r = Ruta(texto: id) { estado.ir(r) }
            }
            .onOpenURL { url in
                // El link de una invitación (corredor.com.ar/invitacion/<token>): entra directo a la inmobiliaria.
                if url.host?.hasSuffix("corredor.com.ar") == true, url.pathComponents.count > 2, url.pathComponents[1] == "invitacion" {
                    Task { await estado.aceptarInvitacion(url.pathComponents[2]) }
                } else if let r = Ruta(texto: url.absoluteString) { estado.ir(r) }
            }
            .onContinueUserActivity("ar.com.corredor.app.propiedad") { a in
                if let id = a.userInfo?["id"] as? String { estado.ir(Ruta(.propiedades, AFichaPropiedad(id: id))) }
            }
            .onContinueUserActivity("ar.com.corredor.app.contacto") { a in
                if let id = a.userInfo?["id"] as? String { estado.ir(Ruta(.inicio, AFichaContacto(id: id))) }
            }
            .onChange(of: fase) { _, nueva in
                switch nueva {
                case .background:
                    enSegundoPlano = Date()
                case .active:
                    // Con Face ID prendido, volver después de un minuto pide identificarse (1D).
                    if estado.conFaceID, estado.fase == .adentro, let d = enSegundoPlano, Date().timeIntervalSince(d) > 60 {
                        estado.bloqueada = true
                    }
                    enSegundoPlano = nil
                    if estado.fase == .adentro {
                        estado.cola.subir()
                        estado.version += 1
                    }
                default:
                    break
                }
            }
        }
    }
}

/// Qué se ve según la sesión: lanzamiento, entrada (1A–1B), elegir inmobiliaria (1C) o la app.
struct Raiz: View {
    @Environment(Estado.self) private var estado

    var body: some View {
        ZStack {
            switch estado.fase {
            case .arrancando:
                Lanzamiento()
            case .afuera:
                Entrada().transition(.opacity)
            case .eligiendo:
                ElegirInmobiliaria().transition(.opacity)
            case .adentro:
                // Los colores de la acción leen el acento de la inmobiliaria al pintarse: si cambia (se
                // publicó la web con otro color), la app se pinta de nuevo. La navegación vive en
                // `Estado`, así que no se pierde (y el arranque, acá arriba, no se repite).
                Principal().id(estado.marcaVersion).transition(.opacity)
            }
            if estado.bloqueada {
                Bloqueo().transition(.opacity).zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: estado.fase)
        .animation(.easeInOut(duration: 0.2), value: estado.bloqueada)
        .task { await estado.arrancar() }
    }
}

/// La pantalla de lanzamiento: verde 0f3530 con la rr en oro, sin texto (igual que la de iOS).
struct Lanzamiento: View {
    var body: some View {
        ZStack {
            C.verde800.ignoresSafeArea()
            Image("Lanzamiento").resizable().scaledToFit().frame(width: 120)
                .accessibilityLabel("Corredor")
        }
    }
}
