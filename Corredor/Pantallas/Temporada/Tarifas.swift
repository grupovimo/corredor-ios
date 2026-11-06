import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tarifas de temporada

struct TarifaAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String?
    var desde: String
    var hasta: String
    var precio: Double
    var moneda: String?
    var periodo: String?
    var nochesMinimas: Int?

    /// Los que acepta la API (sin período, la API pone «temporada»).
    static let periodos = [("noche", "Noche"), ("semana", "Semana"), ("quincena", "Quincena"), ("mes", "Mes"), ("temporada", "Temporada")]
}

/// Tarifas de temporada de una propiedad: por rango de fechas, con noches mínimas.
struct TarifasTemporada: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var lista: [TarifaAPI] = []
    @State private var editando: TarifaAPI?

    var body: some View {
        List {
            if lista.isEmpty { Text("Cargá la tarifa de cada temporada (alta, baja, fines de semana largos).").foregroundStyle(C.texto2) }
            ForEach(lista) { t in
                Button { editando = t } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.nombre ?? "Tarifa").estilo(.filaLista).foregroundStyle(C.texto)
                            Text("\(t.desde) al \(t.hasta)\(t.nochesMinimas.map { " · mínimo \($0) noches" } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Text("\(Formato.plata(t.precio, t.moneda ?? "USD")) / \(TarifaAPI.periodos.first { $0.0 == (t.periodo ?? "temporada") }?.1.lowercased() ?? "temporada")").fontWeight(.semibold).foregroundStyle(C.texto)
                    }
                }
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/tarifas/\(t.id)"); await cargar() } catch { estado.avisar(error) } } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Tarifas")
        .toolbar { if estado.escribe { Button { editando = TarifaAPI(id: "", desde: Formato.diaISO(Date()), hasta: Formato.diaISO(Date().addingTimeInterval(30 * 86400)), precio: 0, moneda: "USD", periodo: "noche") } label: { Image(systemName: "plus") }.accessibilityLabel("Sumar") } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { t in FormTarifa(t: t) { x in Task { await guardar(x) } } }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/propiedades/\(propiedad)/tarifas")) ?? [] }

    private func guardar(_ t: TarifaAPI) async {
        struct C: Encodable { var nombre: String?; var desde: String; var hasta: String; var precio: Double; var moneda: String; var periodo: String; var nochesMinimas: Int? }
        let c = C(nombre: t.nombre?.nonEmpty, desde: t.desde, hasta: t.hasta, precio: t.precio, moneda: t.moneda ?? "USD", periodo: t.periodo ?? "noche", nochesMinimas: t.nochesMinimas)
        do {
            if t.id.isEmpty { try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad)/tarifas", c) } else { try await estado.api.hacer("PUT", "/v1/propiedades/\(propiedad)/tarifas/\(t.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormTarifa: View {
    @Environment(\.dismiss) private var cerrar
    @State var t: TarifaAPI
    var guardar: (TarifaAPI) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (temporada alta…)", text: Binding(get: { t.nombre ?? "" }, set: { t.nombre = $0 }))
                DatePicker("Desde", selection: Binding(get: { Fecha.dia(t.desde) ?? Date() }, set: { t.desde = Formato.diaISO($0) }), displayedComponents: .date)
                DatePicker("Hasta", selection: Binding(get: { Fecha.dia(t.hasta) ?? Date() }, set: { t.hasta = Formato.diaISO($0) }), displayedComponents: .date)
                Picker("Moneda", selection: Binding(get: { t.moneda ?? "USD" }, set: { t.moneda = $0 })) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Precio", value: $t.precio, format: .number).keyboardType(.decimalPad)
                Picker("Por", selection: Binding(get: { t.periodo ?? "noche" }, set: { t.periodo = $0 })) { ForEach(TarifaAPI.periodos, id: \.0) { Text($0.1).tag($0.0) } }
                Stepper("Mínimo \(t.nochesMinimas ?? 1) noches", value: Binding(get: { t.nochesMinimas ?? 1 }, set: { t.nochesMinimas = $0 }), in: 1...120)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(t); cerrar() }.disabled(t.precio <= 0 || (t.nombre ?? "").nonEmpty == nil) }
            }
        }
    }
}
