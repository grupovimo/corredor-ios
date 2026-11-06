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
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { await HojaTarifasTemporada.borrar(t, de: propiedad, estado: estado); await cargar() } } } }
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

/// Tarifas por temporada (15E): las de todas las casas, con borrar (y deshacer), y sumar una
/// temporada a una casa o a todas a la vez. El precio de cada noche sale de la temporada en la que cae.
struct HojaTarifasTemporada: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var casas: [CasaTemporada]
    @State private var tarifas: [String: [TarifaAPI]] = [:]
    @State private var casa = "todas"
    @State private var nombre = "Alta"
    @State private var desde = Date()
    @State private var hasta = Date().addingTimeInterval(14 * 86400)
    @State private var precio: Double?
    @State private var moneda = "USD"
    @State private var periodo = "noche"
    @State private var minimo: Int?
    @State private var errores: [String: String] = [:]
    @State private var enviando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("El precio de cada noche sale de la temporada en la que cae. La última cargada manda si se pisan.").estilo(.footnote).foregroundStyle(C.texto2)
                }
                ForEach(casas) { c in
                    Section(c.direccion) {
                        let ts = tarifas[c.id] ?? c.tarifas
                        if ts.isEmpty { Text("Sin tarifas: se cobra el precio por noche de la ficha.").estilo(.footnote).foregroundStyle(C.texto2) }
                        ForEach(ts) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.nombre ?? "Tarifa").estilo(.filaLista)
                                    Text("\(TempFechas.corto(t.desde)) al \(TempFechas.corto(t.hasta))").estilo(.footnote).foregroundStyle(C.texto2)
                                }
                                Spacer()
                                Text("\(Formato.plata(t.precio, t.moneda ?? "USD")) / \(t.periodo ?? "temporada")\(t.nochesMinimas.map { " · mín. \($0)" } ?? "")").estilo(.footnote)
                            }
                            .swipeActions {
                                if estado.escribe {
                                    Button("Borrar", role: .destructive) {
                                        Task { await HojaTarifasTemporada.borrar(t, de: c.id, estado: estado); await recargar(c.id) }
                                    }
                                }
                            }
                        }
                    }
                }
                if estado.escribe {
                    Section("Sumar una temporada") {
                        Picker("Casa", selection: $casa) {
                            Text("Todas las casas").tag("todas")
                            ForEach(casas) { Text($0.direccion).tag($0.id) }
                        }
                        TextField("Alta, Media, Baja", text: $nombre)
                        if let e = errores["nombre"] { MensajeError(texto: e) }
                        DatePicker("Desde", selection: $desde, displayedComponents: .date)
                        DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
                        if let e = errores["desde"] ?? errores["hasta"] { MensajeError(texto: e) }
                        Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                        TextField("Precio", value: $precio, format: .number).keyboardType(.decimalPad)
                        if let e = errores["precio"] { MensajeError(texto: e) }
                        Picker("Por", selection: $periodo) { ForEach(["noche", "semana", "quincena", "mes"], id: \.self) { Text($0).tag($0) } }
                        Stepper(minimo.map { "Mín. \($0) noches" } ?? "Mín. noches (opcional)", value: Binding(get: { minimo ?? 0 }, set: { minimo = $0 == 0 ? nil : $0 }), in: 0...120)
                        Button(enviando ? "Guardando…" : "Sumar temporada") { Task { await sumar() } }.disabled(enviando || precio == nil || nombre.nonEmpty == nil)
                    }
                }
            }
            .navigationTitle("Tarifas por temporada").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { estado.version += 1; cerrar() } } }
        }
    }

    private func recargar(_ id: String) async {
        tarifas[id] = (try? await estado.api.get("/v1/propiedades/\(id)/tarifas")) ?? []
    }

    struct Cuerpo: Encodable { var nombre: String; var desde: String; var hasta: String; var precio: Double; var moneda: String; var periodo: String; var nochesMinimas: Int? }

    /// Borrar con deshacer (la vuelve a cargar igual).
    @MainActor
    static func borrar(_ t: TarifaAPI, de propiedad: String, estado: Estado) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/tarifas/\(t.id)")
            estado.avisar("Tarifa \(t.nombre ?? "") borrada") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad)/tarifas",
                                                   Cuerpo(nombre: t.nombre ?? "Tarifa", desde: t.desde, hasta: t.hasta, precio: t.precio, moneda: t.moneda ?? "USD",
                                                          periodo: t.periodo ?? "temporada", nochesMinimas: t.nochesMinimas))
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func sumar() async {
        guard let precio else { return }
        let destino = casa == "todas" ? casas : casas.filter { $0.id == casa }
        let c = Cuerpo(nombre: nombre.trimmingCharacters(in: .whitespaces), desde: Formato.diaISO(desde), hasta: Formato.diaISO(hasta), precio: precio,
                       moneda: moneda, periodo: periodo, nochesMinimas: minimo)
        enviando = true
        errores = [:]
        defer { enviando = false }
        do {
            for x in destino {
                _ = try await estado.api.conCampos("POST", "/v1/propiedades/\(x.id)/tarifas", c, envio: UUID().uuidString)
                await recargar(x.id)
            }
            estado.avisar("Temporada \(c.nombre) cargada en \(destino.count == 1 ? destino[0].direccion : "\(destino.count) casas")")
            self.precio = nil
            minimo = nil
        } catch let e as ErrorConCampos {
            errores = e.campos
        } catch { estado.avisar(error) }
    }
}
