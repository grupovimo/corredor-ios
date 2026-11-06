import SwiftUI

// MARK: - Personal

/// Personal del edificio: cada empleado con su categoría, antigüedad y recibos; liquidar el sueldo del
/// mes (con deshacer), el recibo (A4 y link público), la escala vigente y el F931.
struct PestanaPersonalConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    var empleados: [EmpleadoAPI]
    @Binding var pedido: String?
    @State private var recibos: [ReciboSueldoAPI]?
    @State private var escalas: [EscalaAPI] = []
    @State private var error: ErrorApi?
    @State private var recibo: ReciboSueldoAPI?
    @State private var liquidar: LiquidarPara?
    @State private var empleado: EdicionEmpleado?
    @State private var escala = false
    @State private var previo: ArchivoPrevio?

    struct LiquidarPara: Identifiable { var empleado: String; var id: String { empleado } }
    struct EdicionEmpleado: Identifiable { var e: EmpleadoAPI?; var id: String { e?.id ?? "nuevo" } }

    private var ultimoMes: String? { recibos?.first?.periodo }
    private var mesALiquidar: String { ultimoMes.map { Cons.mesSiguiente($0) } ?? String(Cons.hoy.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recibos { contenido(recibos) } else if let error {
                EstadoError(que: "el personal", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 4) }
        }
        .task(id: estado.version) { await cargar() }
        .onChange(of: pedido, initial: true) { _, p in atender(p) }
        .onChange(of: recibos) { _, _ in atender(pedido) }
        .sheet(item: $recibo) { r in HojaReciboSueldo(c: c, r: r).hojaTLW([.large]) }
        .sheet(item: $liquidar) { l in HojaLiquidarSueldo(c: c, empleados: empleados, recibos: recibos ?? [], inicial: l.empleado, porDefecto: mesALiquidar) }
        .sheet(item: $empleado) { e in HojaEmpleadoConsorcio(c: c, e: e.e, escalas: escalas) }
        .sheet(isPresented: $escala) { HojaEscalaSueldos() }
        .vistaPrevia($previo)
    }

    private func atender(_ p: String?) {
        guard let p else { return }
        if p == "liquidar" {
            if estado.escribe, let e = empleados.first { liquidar = LiquidarPara(empleado: e.id) }
            pedido = nil
        } else if p.hasPrefix("recibo:") {
            guard let r = recibos?.first(where: { $0.id == String(p.dropFirst(7)) }) else { return }
            recibo = r
            pedido = nil
        }
    }

    @ViewBuilder private func contenido(_ recibos: [ReciboSueldoAPI]) -> some View {
        HStack(spacing: 8) {
            Text(ultimoMes.map { "Último liquidado: \(Cons.nombreMes($0))" } ?? "Todavía sin recibos").estilo(.footnote).foregroundStyle(C.texto2)
            Spacer()
            Button { Task { await f931() } } label: { Label("Exportar F931", systemImage: "square.and.arrow.down") }.font(Estilo.footnoteFuerte.font).buttonStyle(.bordered)
        }
        if estado.escribe {
            Button { empleado = EdicionEmpleado(e: nil) } label: { Label("Sumar empleado", systemImage: "person.badge.plus") }.buttonStyle(BotonHundido())
        }
        if empleados.isEmpty {
            BloqueConsorcio(titulo: nil) {
                VacioConsorcio(texto: "Sin personal cargado. Sumá al encargado con su categoría y fecha de ingreso: Corredor calcula la antigüedad, las retenciones y arma el recibo y el F931.")
            }
        }
        ForEach(empleados) { e in bloque(e, recibos.filter { $0.empleadoId == e.id }) }
        bloqueEscala
    }

    private func bloque(_ e: EmpleadoAPI, _ rs: [ReciboSueldoAPI]) -> some View {
        BloqueConsorcio(titulo: nil) {
            RenglonConsorcio(primero: true) {
                AvatarIniciales(nombre: e.nombre, tam: 40)
                DosLineasConsorcio(titulo: e.nombre + (e.categoria.map { " · " + $0.lowercased() } ?? ""),
                          detalle: [e.documento.map { "CUIL \($0)" }, e.notas, Cons.antiguedad(e.ingreso).map { "\($0) años" },
                                    e.basico.flatMap { $0 > 0 ? "básico \(Formato.plata($0))" : nil }].compactMap { $0 }.joined(separator: " · "))
                if estado.escribe {
                    Button { empleado = EdicionEmpleado(e: e) } label: { Image(systemName: "pencil").frame(width: 36, height: 36) }
                        .accessibilityLabel("Editar a \(e.nombre)").buttonStyle(.borderless)
                }
            }
            ForEach(rs.prefix(6)) { r in
                Button { recibo = r } label: {
                    RenglonConsorcio {
                        Image(systemName: "doc.text").foregroundStyle(C.okTinta)
                        DosLineasConsorcio(titulo: "Recibo de \(Cons.nombreMes(r.periodo))\(r.periodo.prefix(4) != Cons.hoy.prefix(4) ? " \(r.periodo.prefix(4))" : "")",
                                  detalle: "bruto \(Cons.cifra(r.bruto ?? 0)) · retenciones \(Cons.cifra(r.deduccionesTotal ?? 0))")
                        Text(Cons.cifra(r.neto ?? 0)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto)
                    }
                }
                .buttonStyle(Presionable())
            }
            if estado.escribe {
                RenglonConsorcio {
                    Button { liquidar = LiquidarPara(empleado: e.id) } label: {
                        Label("Liquidar \(Cons.nombreMes(rs.first.map { Cons.mesSiguiente($0.periodo) } ?? mesALiquidar))", systemImage: "plus")
                    }
                    .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).buttonStyle(.borderless)
                }
            }
        }
    }

    private var bloqueEscala: some View {
        BloqueConsorcio(titulo: "Escala de sueldos", accion: estado.esDuenio ? ("Sumar categoría", { escala = true }) : nil) {
            if escalas.isEmpty { VacioConsorcio(texto: "Cargá los básicos de cada categoría (SUTERH): al sumar un empleado, toma el de su categoría.") }
            ForEach(Array(escalas.enumerated()), id: \.element.id) { i, s in
                RenglonConsorcio(primero: i == 0) {
                    DosLineasConsorcio(titulo: s.categoria, detalle: [s.notas, s.vigenteDesde.map { "desde el \(Cons.fechaPapel($0))" }].compactMap { $0 }.joined(separator: " · "))
                    Text(Cons.cifra(s.basico)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto)
                }
            }
        }
    }

    /// El F931 del mes del último recibo, como CSV para Excel.
    private func f931() async {
        do {
            let ruta = "/v1/consorcios/\(c.id)/sueldos/f931" + (ultimoMes.map { "?periodo=\($0)" } ?? "")
            let u = try await Documentos.archivo(ruta, nombre: ultimoMes.map { "sueldos-\($0).csv" } ?? "sueldos-todos.csv", api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            let r: [ReciboSueldoAPI] = try await estado.api.get("/v1/consorcios/\(c.id)/sueldos", query: [.init(name: "limite", value: "60")])
            escalas = (try? await estado.api.get("/v1/sueldos/escalas")) ?? []
            recibos = r
            error = nil
        } catch let e as ErrorApi {
            if recibos == nil { error = e }
        } catch {}
    }
}

// MARK: - Recibo

/// El recibo en pantalla: haberes (básico, antigüedad, otros), descuentos con su tasa, el neto y la
/// provisión de aguinaldo; el A4, y el link para mandárselo al empleado.
struct HojaReciboSueldo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var r: ReciboSueldoAPI
    @State private var link: String?
    @State private var armando = false
    @State private var previo: ArchivoPrevio?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(r.empleado).estilo(.texto14).foregroundStyle(C.texto2)
                    VStack(spacing: 0) {
                        linea("Concepto", "Haberes", "Descuentos", cabeza: true)
                        linea("Sueldo básico", Cons.cifra(r.basico ?? 0), "")
                        if (r.antiguedad ?? 0) > 0 { linea("Antigüedad", Cons.cifra(r.antiguedad ?? 0), "") }
                        if (r.otrosRemunerativos ?? 0) > 0 { linea("Otros remunerativos", Cons.cifra(r.otrosRemunerativos ?? 0), "") }
                        ForEach(r.deducciones ?? [], id: \.nombre) { d in linea("\(d.nombre) \(Cons.coma(d.tasa))\u{00A0}%", "", Cons.cifra(d.monto)) }
                    }
                    .tarjeta()
                    HStack {
                        Text("Neto a cobrar").estilo(.subheadFuerte)
                        Spacer()
                        Text(Formato.plata(r.neto ?? 0)).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font)
                    }
                    .foregroundStyle(C.texto)
                    Text("Provisión de aguinaldo del mes: \(Formato.plata(r.sac ?? 0)).").estilo(.footnote).foregroundStyle(C.texto2)
                }
                .padding(16)
            }
            .background(C.elevado)
            .navigationTitle("Recibo de \(Cons.nombreMes(r.periodo))").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .barraAccion {
                Button { Task { await imprimir() } } label: { Label("Imprimir", systemImage: "printer") }.buttonStyle(BotonHundido())
                if let link {
                    let nombre = r.empleado.split(separator: " ").first.map(String.init) ?? ""
                    HStack(spacing: 8) {
                        Button { Cons.copiar(link); estado.avisar("Link del recibo de \(r.empleado) copiado.") } label: { Label("Copiar link", systemImage: "link") }.buttonStyle(BotonHundido())
                        Button { Afuera.whatsapp(nil, texto: "Hola \(nombre), te paso tu recibo de sueldo de \(Cons.nombreMes(r.periodo)): \(link)") } label: {
                            Label("Mandar por WhatsApp", systemImage: "bubble.left")
                        }
                        .buttonStyle(BotonAccion())
                    }
                } else if estado.escribe {
                    Button { Task { await armar() } } label: { Label(armando ? "Armando…" : "Armar el link", systemImage: "link") }.buttonStyle(BotonAccion()).disabled(armando)
                }
            }
        }
        .vistaPrevia($previo)
    }

    private func linea(_ a: String, _ b: String, _ d: String, cabeza: Bool = false) -> some View {
        RenglonConsorcio(primero: cabeza) {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(width: 84, alignment: .trailing)
            Text(d).frame(width: 84, alignment: .trailing)
        }
        .font(cabeza ? Estilo.footnoteFuerte.font : Estilo.texto14.font).foregroundStyle(cabeza ? C.texto2 : C.texto)
    }

    private func armar() async {
        armando = true
        defer { armando = false }
        do {
            let l: LinkConsorcio = try await estado.api.enviar("POST", "/v1/consorcios/\(c.id)/sueldos/\(r.id)/link", [String: String]())
            link = l.url
            Cons.copiar(l.url)
            estado.avisar("Link del recibo de \(r.empleado) copiado.")
        } catch { estado.avisar(error) }
    }

    private func imprimir() async {
        do {
            let u = try await Documentos.sueldo(consorcio: c.id, recibo: r.id, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

// MARK: - Liquidar el sueldo

/// Liquidar el sueldo de un mes: el empleado, el mes (el siguiente al último recibo), otros
/// remunerativos y una nota. Con deshacer (borra el recibo).
struct HojaLiquidarSueldo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var empleados: [EmpleadoAPI]
    var recibos: [ReciboSueldoAPI]
    var inicial: String
    var porDefecto: String
    @State private var empleado = ""
    @State private var periodo = ""
    @State private var otros: Double?
    @State private var notas = ""
    @State private var guardando = false

    private func mesPara(_ e: String) -> String {
        recibos.first { $0.empleadoId == e }.map { Cons.mesSiguiente($0.periodo) } ?? porDefecto
    }

    /// Los meses para elegir: un año para atrás y dos para adelante del de hoy (y el que toca).
    private var meses: [String] {
        let hoy = String(Cons.hoy.prefix(7))
        var l = (-12...2).map { Cons.mesSiguiente(hoy, $0) }
        if !periodo.isEmpty, !l.contains(periodo) { l.append(periodo) }
        return l.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Empleado", selection: $empleado) { ForEach(empleados) { Text($0.nombre).tag($0.id) } }
                Picker("Mes", selection: $periodo) { ForEach(meses, id: \.self) { Text(Cons.mesConAnio($0)).tag($0) } }
                CampoConsorcio(etiqueta: "Otros remunerativos (opcional)", ayuda: "Horas extra, plus por tareas. El básico y la antigüedad salen de la ficha.") {
                    TextField("Monto", value: $otros, format: .number).keyboardType(.decimalPad)
                }
                CampoConsorcio(etiqueta: "Nota (opcional)") { TextField("", text: $notas) }
            }
            .navigationTitle("Liquidar sueldo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Liquidar") { Task { await liquidar() } }.disabled(empleado.isEmpty || periodo.isEmpty || guardando) }
            }
        }
        .onAppear {
            if empleado.isEmpty { empleado = inicial; periodo = mesPara(inicial) }
        }
        .onChange(of: empleado) { _, e in periodo = mesPara(e) }
    }

    private func liquidar() async {
        guardando = true
        defer { guardando = false }
        struct R: Encodable { var empleadoId: String; var periodo: String; var otrosRemunerativos: Double; var notas: String? }
        let base = "/v1/consorcios/\(c.id)/sueldos"
        do {
            let r: ReciboSueldoAPI = try await estado.api.enviar("POST", base, R(empleadoId: empleado, periodo: periodo, otrosRemunerativos: Cons.redondo(otros ?? 0), notas: String(notas.prefix(200)).nonEmpty))
            estado.version += 1
            cerrar()
            let api = estado.api
            estado.avisar("Recibo de \(Cons.nombreMes(r.periodo)) de \(r.empleado) · neto \(Formato.plata(r.neto ?? 0))") {
                Task {
                    do { try await api.hacer("DELETE", "\(base)/\(r.id)") } catch { estado.avisar(error) }
                    estado.version += 1
                }
            }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Empleado y escala

/// Alta o edición de un empleado: nombre, CUIL, ingreso, categoría (de la escala), básico (vacío: el de
/// la escala), horario y nota.
struct HojaEmpleadoConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var e: EmpleadoAPI?
    var escalas: [EscalaAPI]
    @State private var nombre = ""
    @State private var documento = ""
    @State private var conIngreso = false
    @State private var ingreso = Date()
    @State private var categoria = ""
    @State private var basico: Double?
    @State private var horario = ""
    @State private var notas = ""
    @State private var listo = false
    @State private var guardando = false

    private var categorias: [String] {
        var l: [String] = []
        for s in escalas where !l.contains(s.categoria) { l.append(s.categoria) }
        if let x = e?.categoria, !l.contains(x) { l.append(x) }
        return l
    }

    var body: some View {
        NavigationStack {
            Form {
                CampoConsorcio(etiqueta: "Nombre") { TextField("", text: $nombre) }
                CampoConsorcio(etiqueta: "CUIL (opcional)") { TextField("", text: $documento).keyboardType(.numbersAndPunctuation) }
                Toggle("Ingresó el", isOn: $conIngreso)
                if conIngreso { DatePicker("Fecha de ingreso", selection: $ingreso, in: ...Date(), displayedComponents: .date) }
                Picker("Categoría", selection: $categoria) {
                    Text("Sin categoría").tag("")
                    ForEach(categorias, id: \.self) { Text($0).tag($0) }
                }
                CampoConsorcio(etiqueta: "Básico (opcional)", ayuda: "Vacío: el de la escala de su categoría.") {
                    TextField("Monto", value: $basico, format: .number).keyboardType(.decimalPad)
                }
                CampoConsorcio(etiqueta: "Horario (opcional)") { TextField("", text: $horario) }
                CampoConsorcio(etiqueta: "Nota (opcional)") { TextField("2.ª categoría", text: $notas) }
            }
            .navigationTitle(e.map { "Editar a \($0.nombre)" } ?? "Sumar empleado").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || guardando) }
            }
        }
        .onAppear {
            guard !listo else { return }
            listo = true
            if let e {
                nombre = e.nombre
                documento = e.documento ?? ""
                if let f = e.ingreso.flatMap(Fecha.dia) { conIngreso = true; ingreso = f }
                categoria = e.categoria ?? ""
                basico = e.basico
                horario = e.horario ?? ""
                notas = e.notas ?? ""
            } else {
                categoria = escalas.first?.categoria ?? ""
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct D: Encodable { var nombre: String; var documento: String?; var categoria: String?; var ingreso: String?; var basico: Double?; var horario: String?; var notas: String? }
        let d = D(nombre: nombre.trimmingCharacters(in: .whitespaces), documento: documento.nonEmpty, categoria: categoria.nonEmpty, ingreso: conIngreso ? Formato.diaISO(ingreso) : nil,
                  basico: basico.map(Cons.redondo), horario: horario.nonEmpty, notas: notas.nonEmpty)
        let base = "/v1/consorcios/\(c.id)/empleados"
        do {
            if let e {
                try await estado.api.hacer("PUT", "\(base)/\(e.id)", d)
                estado.avisar("Empleado guardado")
            } else {
                try await estado.api.hacer("POST", base, d)
                estado.avisar("Empleado cargado")
            }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// Una categoría nueva en la escala de sueldos (SUTERH), con su básico y desde cuándo vale. Sólo el dueño.
struct HojaEscalaSueldos: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var categoria = ""
    @State private var basico: Double?
    @State private var desde = Fecha.dia(String(Cons.hoy.prefix(8)) + "01") ?? Date()
    @State private var notas = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                CampoConsorcio(etiqueta: "Categoría") { TextField("Encargado permanente con vivienda", text: $categoria) }
                CampoConsorcio(etiqueta: "Básico") { TextField("Monto", value: $basico, format: .number).keyboardType(.decimalPad) }
                DatePicker("Vigente desde", selection: $desde, displayedComponents: .date)
                CampoConsorcio(etiqueta: "Nota (opcional)") { TextField("Escala SUTERH noviembre", text: $notas) }
            }
            .navigationTitle("Sumar categoría").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guardar() } }.disabled(categoria.trimmingCharacters(in: .whitespaces).isEmpty || (basico ?? -1) < 0 || guardando)
                }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct E: Encodable { var categoria: String; var basico: Double; var vigenteDesde: String?; var notas: String? }
        do {
            try await estado.api.hacer("POST", "/v1/sueldos/escalas", E(categoria: categoria.trimmingCharacters(in: .whitespaces), basico: Cons.redondo(basico ?? 0), vigenteDesde: Formato.diaISO(desde), notas: notas.nonEmpty))
            estado.avisar("Escala guardada")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
