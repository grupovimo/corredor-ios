import SwiftUI

// MARK: - Unidades

/// Unidades del edificio: coeficiente, propietario (y si le llega por mail) y saldo. Tocar una abre su
/// cuenta corriente: los movimientos, registrar un pago (con deshacer), el link público y editarla.
struct PestanaUnidadesConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    @Binding var pedido: String?
    @State private var unidades: [UnidadAPI]?
    @State private var deudores: [DeudorAPI] = []
    @State private var error: ErrorApi?
    @State private var soloDeben = false
    @State private var cuenta: UnidadAPI?
    @State private var editando: EdicionUnidad?
    @State private var intimar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let unidades {
                barra(unidades)
                if unidades.isEmpty {
                    EstadoVacio(icono: "door.left.hand.open", titulo: "Cargá las unidades del edificio",
                                texto: "Con su propietario y el coeficiente del reglamento. Con eso, Corredor reparte los gastos de cada mes al centavo.",
                                accion: estado.escribe ? ("Cargar la primera unidad", { editando = EdicionUnidad(u: nil) }) : nil)
                } else {
                    tabla(unidades)
                }
            } else if let error {
                EstadoError(que: "las unidades", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 5) }
        }
        .task(id: estado.version) { await cargar() }
        .onChange(of: pedido, initial: true) { _, p in atender(p) }
        .onChange(of: unidades) { _, _ in atender(pedido) }
        .sheet(item: $cuenta) { u in HojaCuentaUnidad(c: c, u: u) { editando = EdicionUnidad(u: u) }.hojaTLW([.large]) }
        .sheet(item: $editando) { e in HojaUnidadConsorcio(c: c, u: e.u) }
        .sheet(isPresented: $intimar) { HojaIntimarMorosos(morosos: morosos, consorcioId: c.id, consorcio: c.nombre).hojaTLW([.large]) }
    }

    struct EdicionUnidad: Identifiable { var u: UnidadAPI?; var id: String { u?.id ?? "nueva" } }

    private var morosos: [MorosoConsorcio] {
        let u = unidades ?? []
        return deudores.map { d in MorosoConsorcio(unidadId: d.unidadId, unidad: d.unidad, propietario: d.propietario, telefono: u.first { $0.id == d.unidadId }?.propietarioTelefono, total: d.total) }
    }

    /// Lo que pidió el Resumen o la lista: sólo las que deben, la alta, o la cuenta de una unidad.
    private func atender(_ p: String?) {
        guard let p else { return }
        if p == "deben" { soloDeben = true; pedido = nil }
        else if p == "nueva" { if estado.escribe { editando = EdicionUnidad(u: nil) }; pedido = nil }
        else if p.hasPrefix("unidad:") {
            let id = String(p.dropFirst(7))
            guard let u = unidades?.first(where: { $0.id == id }) else { return }
            cuenta = u
            pedido = nil
        }
    }

    private func barra(_ unidades: [UnidadAPI]) -> some View {
        HStack(spacing: 8) {
            ChipFiltro(texto: "Todas \(unidades.count)", activo: !soloDeben) { soloDeben = false }
            ChipFiltro(texto: "Deben \(deudores.count)", activo: soloDeben) { soloDeben = true }
            Spacer()
            if !deudores.isEmpty {
                Button { intimar = true } label: { Label("Intimar", systemImage: "hammer") }.font(Estilo.footnoteFuerte.font).buttonStyle(.bordered)
            }
            if estado.escribe {
                Button { editando = EdicionUnidad(u: nil) } label: { Label("Nueva unidad", systemImage: "plus") }.font(Estilo.footnoteFuerte.font).buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func tabla(_ todas: [UnidadAPI]) -> some View {
        let deuda = Dictionary(deudores.map { ($0.unidadId, $0) }, uniquingKeysWith: { a, _ in a })
        let l = todas.sorted { Cons.porUnidad($0.etiqueta, $1.etiqueta) }.filter { !soloDeben || deuda[$0.id] != nil }
        let general = c.general
        VStack(spacing: 0) {
            if l.isEmpty { VacioConsorcio(texto: "Nadie debe: todas las unidades están al día.") }
            ForEach(Array(l.enumerated()), id: \.element.id) { i, u in
                Button { cuenta = u } label: {
                    RenglonConsorcio(primero: i == 0) {
                        Text(u.etiqueta).font(Estilo.filaLista.font).foregroundStyle(C.texto).frame(minWidth: 44, alignment: .leading)
                        DosLineasConsorcio(titulo: u.propietario ?? "Sin propietario",
                                  detalle: u.propietarioEmail != nil ? "le llega por mail" : u.propietario != nil ? "sin mail · va impresa" : "cargá quién es el dueño")
                        VStack(alignment: .trailing, spacing: 2) {
                            if let d = deuda[u.id] {
                                Text(Cons.cifra(d.total)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.errorTinta)
                            } else if (u.saldo ?? 0) < 0 {
                                Text("a favor \(Cons.cifra(-(u.saldo ?? 0)))").font(Estilo.footnoteFuerte.font).foregroundStyle(C.okTinta)
                            } else {
                                Text("al día").font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto2)
                            }
                            Text(general.map { Cons.coeficiente(u.coeficientes?[$0.id] ?? 0) } ?? "—").estilo(.footnote).foregroundStyle(C.texto3)
                        }
                    }
                }
                .buttonStyle(Presionable())
            }
        }
        .tarjeta()
    }

    private func cargar() async {
        let b = "/v1/consorcios/\(c.id)"
        do {
            let u: [UnidadAPI] = try await estado.api.get("\(b)/unidades")
            deudores = (try? await estado.api.get("\(b)/deudores")) ?? []
            unidades = u
            error = nil
        } catch let e as ErrorApi {
            if unidades == nil { error = e }
        } catch {}
    }
}

// MARK: - Cuenta corriente

/// La cuenta de una unidad: «Saldo hoy» con el interés por mora y los movimientos (pago, expensas,
/// interés, ajuste); registrar un pago, copiar el link público o editar la unidad.
struct HojaCuentaUnidad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var u: UnidadAPI
    var editar: () -> Void
    @State private var cuenta: CuentaUnidadAPI?
    @State private var error: ErrorApi?
    @State private var pagando = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(u.propietario ?? "Sin propietario").estilo(.texto14).foregroundStyle(C.texto2)
                    if let cuenta { contenido(cuenta) } else if let error {
                        EstadoError(que: "la cuenta", error: error) { Task { await cargar() } }
                    } else { EsqueletoFilas(filas: 4) }
                }
                .padding(16)
            }
            .background(C.elevado)
            .navigationTitle("Cuenta de \(u.etiqueta)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .barraAccion {
                if estado.escribe {
                    HStack(spacing: 8) {
                        Button { cerrar(); Task { try? await Task.sleep(for: .milliseconds(450)); editar() } } label: { Label("Editar", systemImage: "pencil") }.buttonStyle(BotonHundido())
                        Button { Task { await copiarLink() } } label: { Label("Copiar link", systemImage: "link") }.buttonStyle(BotonHundido())
                    }
                    Button { pagando = true } label: { Label("Registrar pago", systemImage: "dollarsign.circle") }.buttonStyle(BotonAccion())
                }
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $pagando) {
            HojaPagoUnidad(c: c, u: u, saldo: cuenta?.saldo ?? 0).hojaTLW([.medium, .large])
        }
    }

    @ViewBuilder private func contenido(_ k: CuentaUnidadAPI) -> some View {
        let interes = k.interesEstimado ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Text("Saldo hoy").estilo(.footnote).foregroundStyle(C.texto2)
            Text(Formato.plata(k.saldo + interes)).font(Estilo(tamano: 28, peso: .bold, tracking: -0.02, relativo: .title).font)
                .foregroundStyle(k.saldo > 0 ? C.errorTinta : C.texto)
            if interes > 0 { Text("Incluye \(Formato.plata(interes)) de interés por mora.").estilo(.footnote).foregroundStyle(C.texto2) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(k.saldo > 0 ? C.errorFondo : C.hundida, in: .rect(cornerRadius: 16))
        VStack(spacing: 0) {
            let ms = Array((k.movimientos ?? []).prefix(12))
            if ms.isEmpty { VacioConsorcio(texto: "Sin movimientos todavía.") }
            ForEach(Array(ms.enumerated()), id: \.element.id) { i, m in
                let nombre = MovimientoUnidad.nombres[m.tipo] ?? m.tipo
                RenglonConsorcio(primero: i == 0) {
                    DosLineasConsorcio(titulo: m.notas?.nonEmpty ?? nombre, detalle: "\(nombre) · \(Cons.fechaPapel(m.fecha))")
                    Text((m.signo < 0 ? "−" : "") + Cons.cifra(abs(m.signo))).font(Estilo.footnoteFuerte.font)
                        .foregroundStyle(m.tipo == "pago" ? C.okTinta : C.texto)
                }
            }
        }
        .tarjeta()
    }

    private func copiarLink() async {
        do {
            let l: LinkConsorcio = try await estado.api.enviar("POST", "/v1/consorcios/\(c.id)/unidades/\(u.id)/link", [String: String]())
            Cons.copiar(l.url)
            estado.avisar("Link de la cuenta de \(u.etiqueta) copiado. Pegalo donde quieras mandarlo.")
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            cuenta = try await estado.api.get("/v1/consorcios/\(c.id)/unidades/\(u.id)/cuenta")
            error = nil
        } catch let e as ErrorApi {
            if cuenta == nil { error = e }
        } catch {}
    }
}

/// Registrar un pago en la cuenta de la unidad: lo que pagó, la fecha y una nota. Con deshacer.
struct HojaPagoUnidad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var u: UnidadAPI
    var saldo: Double
    @State private var monto: Double?
    @State private var fecha = Date()
    @State private var notas = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                CampoConsorcio(etiqueta: "Pagó") { TextField("Monto", value: $monto, format: .number).keyboardType(.decimalPad) }
                if let m = monto, m <= 0 { Text("Poné el monto que pagó.").estilo(.footnote).foregroundStyle(C.error) }
                DatePicker("Fecha", selection: $fecha, in: ...Date(), displayedComponents: .date)
                CampoConsorcio(etiqueta: "Nota (opcional)") { TextField("Transferencia, efectivo en la administración…", text: $notas) }
            }
            .navigationTitle("Pago de \(u.etiqueta)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar pago") { Task { await pagar() } }.disabled((monto ?? 0) <= 0 || guardando)
                }
            }
        }
        .onAppear { if monto == nil, saldo > 0 { monto = saldo } }
    }

    private func pagar() async {
        guardando = true
        defer { guardando = false }
        struct M: Encodable { var tipo = "pago"; var monto: Double; var fecha: String; var notas: String? }
        let ruta = "/v1/consorcios/\(c.id)/unidades/\(u.id)/movimientos"
        do {
            let m: MovimientoUnidad = try await estado.api.enviar("POST", ruta, M(monto: Cons.redondo(monto ?? 0), fecha: Formato.diaISO(fecha), notas: String(notas.prefix(200)).nonEmpty))
            Haptico.exito()
            estado.version += 1
            cerrar()
            let api = estado.api
            estado.avisar("Pago de \(u.etiqueta) · \(Formato.plata(m.monto))") {
                Task {
                    do {
                        try await api.hacer("DELETE", "\(ruta)/\(m.id)")
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Alta y edición

/// Alta o edición de una unidad: etiqueta, tipo, propietario (elegido o uno nuevo con mail y celular)
/// y el coeficiente de cada columna del reglamento.
struct HojaUnidadConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var u: UnidadAPI?
    @State private var etiqueta = ""
    @State private var tipo = "departamento"
    @State private var propietario = ""
    @State private var nuevoNombre = ""
    @State private var nuevoEmail = ""
    @State private var nuevoTelefono = ""
    @State private var coef: [String: Double] = [:]
    @State private var propietarios: [Prop] = []
    @State private var guardando = false
    @State private var listo = false

    struct Prop: Codable, Identifiable, Hashable { var id: String; var nombre: String }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CampoConsorcio(etiqueta: "Unidad") { TextField("3.º A", text: $etiqueta) }
                    Picker("Es", selection: $tipo) { ForEach(UnidadAPI.tipos, id: \.0) { Text($0.1).tag($0.0) } }
                }
                Section {
                    Picker("Propietario", selection: $propietario) {
                        Text("Sin cargar").tag("")
                        ForEach(propietarios) { Text($0.nombre).tag($0.id) }
                        Text("Otro (cargarlo)…").tag("nuevo")
                    }
                    if propietario == "nuevo" {
                        CampoConsorcio(etiqueta: "Nombre del propietario") { TextField("", text: $nuevoNombre) }
                        CampoConsorcio(etiqueta: "Mail (opcional)", ayuda: "Para mandarle la liquidación.") {
                            TextField("", text: $nuevoEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        CampoConsorcio(etiqueta: "Celular (opcional)") { TextField("", text: $nuevoTelefono).keyboardType(.phonePad) }
                    }
                }
                Section {
                    ForEach(c.columnas ?? []) { col in
                        CampoConsorcio(etiqueta: (c.columnas?.count ?? 0) > 1 ? "Coeficiente · \(col.nombre) (%)" : "Coeficiente del reglamento (%)") {
                            TextField("4,12", value: Binding(get: { coef[col.id] }, set: { coef[col.id] = $0 }), format: .number).keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle(u.map { "Editar \($0.etiqueta)" } ?? "Nueva unidad").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guardar() } }
                        .disabled(etiqueta.trimmingCharacters(in: .whitespaces).isEmpty || (propietario == "nuevo" && nuevoNombre.trimmingCharacters(in: .whitespaces).isEmpty) || guardando)
                }
            }
        }
        .task {
            if let u, !listo {
                etiqueta = u.etiqueta
                tipo = u.tipo ?? "departamento"
                propietario = u.propietarioId ?? ""
                coef = u.coeficientes ?? [:]
            }
            listo = true
            propietarios = (try? await estado.api.todas("/v1/contactos", query: [.init(name: "tipo", value: "propietario")])) ?? []
            // El propietario de la unidad, aunque no esté cargado como tipo propietario.
            if let u, let pid = u.propietarioId, !propietarios.contains(where: { $0.id == pid }) {
                propietarios.insert(Prop(id: pid, nombre: u.propietario ?? "Propietario"), at: 0)
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct NuevoContacto: Encodable { var nombre: String; var email: String?; var telefono: String?; var tipo = "propietario" }
        struct Datos: Encodable {
            var etiqueta: String; var piso: String?; var tipo: String; var propietarioId: String?; var inquilinoId: String?
            var notas: String?; var expensaFija: Double; var coeficientes: [String: Double]
        }
        do {
            var pid: String? = propietario.isEmpty ? nil : propietario
            if propietario == "nuevo" {
                let n: Prop = try await estado.api.enviar("POST", "/v1/contactos", NuevoContacto(nombre: nuevoNombre.trimmingCharacters(in: .whitespaces), email: nuevoEmail.nonEmpty, telefono: nuevoTelefono.nonEmpty))
                pid = n.id
                propietario = n.id
                propietarios.append(n)
            }
            let cols = Set((c.columnas ?? []).map(\.id))
            let d = Datos(etiqueta: etiqueta.trimmingCharacters(in: .whitespaces), piso: u?.piso, tipo: tipo, propietarioId: pid, inquilinoId: u?.inquilinoId,
                          notas: u?.notas, expensaFija: Cons.redondo(u?.expensaFija ?? 0), coeficientes: coef.filter { cols.contains($0.key) })
            if let u {
                try await estado.api.hacer("PUT", "/v1/consorcios/\(c.id)/unidades/\(u.id)", d)
                estado.avisar("Unidad guardada")
            } else {
                try await estado.api.hacer("POST", "/v1/consorcios/\(c.id)/unidades", d)
                estado.avisar("Unidad cargada")
            }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
