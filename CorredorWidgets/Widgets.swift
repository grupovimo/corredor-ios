import SwiftUI
import WidgetKit

// Los widgets, la Live Activity de la próxima visita y la isla (handoff 14A–14E).

struct EntradaHoy: TimelineEntry {
    var date: Date
}

struct ProveedorHoy: TimelineProvider {
    func placeholder(in context: Context) -> EntradaHoy { EntradaHoy(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (EntradaHoy) -> Void) { completion(EntradaHoy(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaHoy>) -> Void) {
        completion(Timeline(entries: [EntradaHoy(date: Date())], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct WidgetHoy: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "hoy", provider: ProveedorHoy()) { _ in
            Text("Corredor").containerBackground(Color(red: 15 / 255, green: 53 / 255, blue: 48 / 255), for: .widget)
        }
        .configurationDisplayName("Hoy")
        .description("Tu próxima visita y lo que hay que hacer.")
    }
}

@main
struct CorredorWidgets: WidgetBundle {
    var body: some Widget {
        WidgetHoy()
    }
}
