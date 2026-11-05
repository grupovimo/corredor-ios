import Charts
import SwiftUI

// Los gráficos de Corredor (Swift Charts): la plata, las visitas y las métricas. Cada uno arranca en
// cero y crece al aparecer; los colores salen de la paleta (oro y verde de la marca, más los tonos).

/// Una tarjeta con título y su gráfico.
struct TarjetaGrafico<Contenido: View>: View {
    var titulo: String
    var detalle: String? = nil
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).estilo(.subheadFuerte).foregroundStyle(C.texto)
                if let detalle { Text(detalle).estilo(.footnote).foregroundStyle(C.texto3) }
            }
            contenido
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }
}

/// Crece desde cero al aparecer (para que el gráfico «se dibuje»).
private struct Crecer: ViewModifier {
    @Binding var listo: Bool
    func body(content: Content) -> some View {
        content.onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.15).delay(0.1)) { listo = true } }
    }
}

// MARK: - Plata: cobrado y pendiente de los últimos 6 meses

struct GraficoCobranzaMeses: View {
    @Environment(Estado.self) private var estado
    @State private var meses: [(mes: Date, cobrado: Double, pendiente: Double)] = []
    @State private var listo = false

    var body: some View {
        TarjetaGrafico(titulo: "Los últimos 6 meses", detalle: "Cobrado y pendiente, en pesos") {
            if meses.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(meses, id: \.mes) { m in
                        BarMark(x: .value("Mes", m.mes, unit: .month), y: .value("Pesos", listo ? m.cobrado : 0))
                            .foregroundStyle(by: .value("Estado", "Cobrado"))
                            .cornerRadius(5)
                        BarMark(x: .value("Mes", m.mes, unit: .month), y: .value("Pesos", listo ? m.pendiente : 0))
                            .foregroundStyle(by: .value("Estado", "Pendiente"))
                            .cornerRadius(5)
                    }
                }
                .chartForegroundStyleScale(["Cobrado": Color(hex: 0x2F9E6F), "Pendiente": C.oro.opacity(0.55)])
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Formato.plataCorta(d).replacingOccurrences(of: "ARS ", with: "")) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)
                .modifier(Crecer(listo: $listo))
            }
        }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        var r: [(Date, Double, Double)] = []
        let cal = Calendar.current
        let hoy = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        for n in (0..<6).reversed() {
            guard let m = cal.date(byAdding: .month, value: -n, to: hoy) else { continue }
            let p = String(Formato.diaISO(m).prefix(7))
            let x: MesCobranzas? = try? await estado.api.get("/v1/cobranzas", query: [.init(name: "periodo", value: p)])
            r.append((m, x?.totalCobrado?["ARS"] ?? 0, x?.totalPendiente?["ARS"] ?? 0))
        }
        meses = r.map { (mes: $0.0, cobrado: $0.1, pendiente: $0.2) }
    }
}

// MARK: - Visitas por semana (últimas 8)

struct GraficoVisitasSemanas: View {
    @Environment(Estado.self) private var estado
    @State private var semanas: [(semana: Date, hechas: Int, otras: Int)] = []
    @State private var listo = false

    var body: some View {
        TarjetaGrafico(titulo: "Visitas por semana", detalle: "Las últimas 8 semanas") {
            if semanas.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(semanas, id: \.semana) { s in
                        BarMark(x: .value("Semana", s.semana, unit: .weekOfYear), y: .value("Visitas", listo ? s.hechas : 0))
                            .foregroundStyle(by: .value("Estado", "Hechas"))
                            .cornerRadius(5)
                        BarMark(x: .value("Semana", s.semana, unit: .weekOfYear), y: .value("Visitas", listo ? s.otras : 0))
                            .foregroundStyle(by: .value("Estado", "Agendadas"))
                            .cornerRadius(5)
                    }
                }
                .chartForegroundStyleScale(["Hechas": C.accion, "Agendadas": C.oro.opacity(0.5)])
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 170)
                .modifier(Crecer(listo: $listo))
            }
        }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        let cal = Calendar(identifier: .iso8601)
        let inicio = cal.date(byAdding: .weekOfYear, value: -7, to: cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()) ?? Date()
        let citas: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "desde", value: Formato.diaISO(inicio)),
                                                                            .init(name: "hasta", value: Formato.diaISO(Date())),
                                                                            .init(name: "limite", value: "500")])) ?? []
        var r: [(Date, Int, Int)] = []
        for n in 0..<8 {
            guard let s = cal.date(byAdding: .weekOfYear, value: n, to: inicio), let fin = cal.date(byAdding: .day, value: 7, to: s) else { continue }
            let deLaSemana = citas.filter { ($0.tipo ?? "visita") == "visita" && $0.empiezaEn >= s && $0.empiezaEn < fin }
            let hechas = deLaSemana.filter { $0.estado == "hecha" }.count
            r.append((s, hechas, deLaSemana.count - hechas))
        }
        semanas = r.map { (semana: $0.0, hechas: $0.1, otras: $0.2) }
    }
}

// MARK: - Métricas del informe

/// De dónde vienen las consultas: una dona con la cantidad en el centro.
struct GraficoOrigenes: View {
    var origenes: [(String, Double)]
    @State private var listo = false
    private let colores: [Color] = [C.oro, Color(hex: 0x2F9E6F), Color(hex: 0x9CC2EF), Color(hex: 0xC9A8EF), Color(hex: 0xF29B92), C.texto3]

    var body: some View {
        let total = origenes.reduce(0) { $0 + $1.1 }
        TarjetaGrafico(titulo: "De dónde vienen las consultas") {
            HStack(alignment: .center, spacing: 16) {
                Chart(Array(origenes.enumerated()), id: \.offset) { i, o in
                    SectorMark(angle: .value("Consultas", listo ? o.1 : (i == 0 ? 1 : 0)), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(colores[i % colores.count])
                        .cornerRadius(4)
                }
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("\(Int(total))").font(Estilo(tamano: 22, peso: .extrabold, relativo: .title2).font).foregroundStyle(C.texto)
                            .contentTransition(.numericText())
                        Text("consultas").estilo(.footnote).foregroundStyle(C.texto3)
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(origenes.prefix(6).enumerated()), id: \.offset) { i, o in
                        HStack(spacing: 8) {
                            Circle().fill(colores[i % colores.count]).frame(width: 9, height: 9)
                            Text(o.0).estilo(.footnote).foregroundStyle(C.texto).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(total > 0 ? "\(Int((o.1 / total * 100).rounded())) %" : "—").font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto2)
                        }
                    }
                }
            }
            .modifier(Crecer(listo: $listo))
        }
    }
}

/// Barras horizontales (el embudo de operaciones, las propiedades más vistas).
struct GraficoBarras: View {
    var titulo: String
    var detalle: String? = nil
    var filas: [(String, Double)]
    var color: Color = C.oro
    @State private var listo = false

    var body: some View {
        TarjetaGrafico(titulo: titulo, detalle: detalle) {
            Chart(Array(filas.enumerated()), id: \.offset) { _, f in
                BarMark(x: .value("Cantidad", listo ? f.1 : 0), y: .value("Nombre", f.0))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(Formato.numero(Int(f.1))).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto2)
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { _ in AxisValueLabel().font(Estilo(tamano: 12, peso: .medium, relativo: .caption).font) } }
            .frame(height: CGFloat(max(filas.count, 1)) * 34)
            .modifier(Crecer(listo: $listo))
        }
    }
}
