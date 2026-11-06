import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Vistas de una propiedad

/// Vistas de una propiedad en la web: el total y el gráfico por día de los últimos 90 días.
struct VistasPropiedad: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var r: Respuesta?
    struct Dia: Codable, Identifiable { var dia: String; var cantidad: Int; var id: String { dia } }
    /// `GET /v1/propiedades/{id}/vistas`: el total de siempre y los días (sólo los que tuvieron vistas).
    struct Respuesta: Codable { var total: Int?; var dias: [Dia]? }

    private var dias: [Dia] { r?.dias ?? [] }

    /// Las vistas desde hace `n` días (por fecha: los días sin vistas no vienen).
    private func ultimos(_ n: Int) -> Int {
        let desde = Calendar.current.date(byAdding: .day, value: -n, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return dias.filter { (Fecha.dia($0.dia) ?? .distantPast) > desde }.reduce(0) { $0 + $1.cantidad }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Cifra(etiqueta: "Desde siempre", valor: Formato.numero(r?.total ?? 0))
                    Cifra(etiqueta: "Últimos 90 días", valor: Formato.numero(dias.reduce(0) { $0 + $1.cantidad }))
                    Cifra(etiqueta: "Últimos 7 días", valor: Formato.numero(ultimos(7)))
                }
                Chart(dias) { d in
                    BarMark(x: .value("Día", Fecha.dia(d.dia) ?? Date(), unit: .day), y: .value("Vistas", d.cantidad))
                        .foregroundStyle(C.accion).cornerRadius(3)
                }
                .frame(height: 220).padding(14).tarjeta()
                if r != nil, dias.isEmpty { Text("Todavía nadie la vio. Publicala y compartila para que llegue.").estilo(.subhead).foregroundStyle(C.texto2) }
            }
            .padding(16)
        }
        .pantallaApilada("Vistas")
        .task {
            r = (try? await estado.api.get("/v1/propiedades/\(propiedad)/vistas")) ?? Respuesta(total: 0, dias: [])
        }
    }
}
