import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Los widgets, la Live Activity de la próxima visita y la isla (handoff 14A–14E).

private let verde = Color(red: 15 / 255, green: 53 / 255, blue: 48 / 255)
private let oro = Color(red: 242 / 255, green: 187 / 255, blue: 87 / 255)
private let tinta2 = Color(red: 207 / 255, green: 224 / 255, blue: 216 / 255)

struct EntradaHoy: TimelineEntry {
    var date: Date
    var hoy: Hoy
}

struct ProveedorHoy: TimelineProvider {
    func placeholder(in context: Context) -> EntradaHoy {
        EntradaHoy(date: Date(), hoy: Hoy(visita: .init(id: "a", donde: "Arce 320, 4.º B", con: "Diego Fernández", empieza: Date().addingTimeInterval(1500)),
                                          sinResponder: 4, mensajes: [.init(id: "m", quien: "Valeria Gómez", canal: "wa", cuando: Date())], cobrosHoy: 2, actualizado: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (EntradaHoy) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : EntradaHoy(date: Date(), hoy: Hoy.leer()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaHoy>) -> Void) {
        Task {
            let hoy = await Hoy.traer()
            var fechas = [Date()]
            if let v = hoy.visita { fechas.append(v.empieza.addingTimeInterval(3600)) }
            completion(Timeline(entries: fechas.map { EntradaHoy(date: $0, hoy: hoy) }, policy: .after(Date().addingTimeInterval(900))))
        }
    }
}

/// 14E: la próxima visita (chico y mediano) con «Cómo llegar», y lo sin responder al lado.
struct VistaWidgetHoy: View {
    @Environment(\.widgetFamily) private var familia
    var e: EntradaHoy

    var body: some View {
        switch familia {
        case .accessoryRectangular:
            if let v = e.hoy.visita {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Próxima visita").font(.caption2.weight(.semibold))
                    Text("\(v.empieza, style: .time) · \(v.donde)").font(.caption.weight(.bold)).lineLimit(1)
                    if let c = v.con { Text(c).font(.caption2).lineLimit(1) }
                }
            } else {
                Text("\(e.hoy.sinResponder) sin responder").font(.caption.weight(.bold))
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.caption)
                    Text("\(e.hoy.sinResponder)").font(.headline.weight(.bold))
                }
            }
        case .systemMedium:
            HStack(spacing: 14) {
                visita
                Divider().overlay(.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 4) {
                    Text("SIN RESPONDER").font(.system(size: 11, weight: .bold)).foregroundStyle(oro)
                    Text("\(e.hoy.sinResponder)").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                    ForEach(e.hoy.mensajes.prefix(2), id: \.id) { m in
                        Text(m.quien).font(.system(size: 12, weight: .semibold)).foregroundStyle(tinta2).lineLimit(1)
                    }
                }
                .frame(maxWidth: 110, alignment: .leading)
            }
            .widgetURL(URL(string: "corredor://mensajes"))
        default:
            visita
        }
    }

    @ViewBuilder
    private var visita: some View {
        if let v = e.hoy.visita {
            VStack(alignment: .leading, spacing: 3) {
                Text(v.empieza > Date() ? "PRÓXIMA VISITA · \(v.empieza, style: .relative)".uppercased() : "VISITA EN CURSO")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(oro).lineLimit(1)
                Text(v.donde).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                Text("\(v.empieza, style: .time)\(v.con.map { " · con \($0)" } ?? "")").font(.system(size: 12)).foregroundStyle(tinta2).lineLimit(1)
                Spacer(minLength: 4)
                Link(destination: URL(string: "corredor://agenda/\(v.id)")!) {
                    Label("Cómo llegar", systemImage: "location.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(red: 26 / 255, green: 20 / 255, blue: 5 / 255))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(oro, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOY").font(.system(size: 11, weight: .bold)).foregroundStyle(oro)
                Text("Sin visitas").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("Agendá una y le avisamos al cliente.").font(.system(size: 12)).foregroundStyle(tinta2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "corredor://agenda"))
        }
    }
}

struct WidgetHoy: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "hoy", provider: ProveedorHoy()) { e in
            VistaWidgetHoy(e: e).containerBackground(verde, for: .widget)
        }
        .configurationDisplayName("Hoy")
        .description("Tu próxima visita y lo que hay que responder.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

/// 14A, 14D: la Live Activity de la visita en la pantalla bloqueada y en la isla.
struct ActividadVisitaWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitaActividad.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: "house.fill").font(.title3).foregroundStyle(oro).frame(width: 40, height: 40).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.con.map { "Visita con \($0)" } ?? "Visita").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    Text(ctx.attributes.donde).font(.footnote).foregroundStyle(tinta2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(timerInterval: Date()...max(Date(), ctx.state.empieza), countsDown: true).font(.title3.weight(.heavy)).foregroundStyle(oro).monospacedDigit()
                        .multilineTextAlignment(.trailing).frame(width: 70)
                    Text(ctx.state.empieza, style: .time).font(.caption).foregroundStyle(tinta2)
                }
            }
            .padding(16)
            .activityBackgroundTint(verde)
            .widgetURL(URL(string: "corredor://agenda/\(ctx.attributes.citaId)"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "house.fill").foregroundStyle(oro).font(.title2) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), ctx.state.empieza), countsDown: true).font(.title3.weight(.bold)).foregroundStyle(oro).monospacedDigit().frame(width: 64)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(ctx.attributes.con.map { "Visita con \($0)" } ?? "Visita").font(.subheadline.weight(.bold))
                        Text(ctx.attributes.donde).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Link(destination: URL(string: "corredor://agenda/\(ctx.attributes.citaId)")!) {
                            Label("Cómo llegar", systemImage: "location.fill").frame(maxWidth: .infinity).padding(8).background(oro.opacity(0.25), in: Capsule())
                        }
                        Link(destination: URL(string: "corredor://agenda/\(ctx.attributes.citaId)?llegando=1")!) {
                            Text("Estoy llegando").frame(maxWidth: .infinity).padding(8).background(.green.opacity(0.3), in: Capsule())
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            } compactLeading: {
                Image(systemName: "house.fill").foregroundStyle(oro)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date(), ctx.state.empieza), countsDown: true).monospacedDigit().frame(width: 44).foregroundStyle(oro)
            } minimal: {
                Image(systemName: "house.fill").foregroundStyle(oro)
            }
        }
    }
}

@main
struct CorredorWidgets: WidgetBundle {
    var body: some Widget {
        WidgetHoy()
        ActividadVisitaWidget()
    }
}
