import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Consorcios: no los dibuja el handoff (decía «quedan en la web»), pero Nahuel los quiere en el
// celular. Se arman con las piezas del handoff: tarjetas de cifras, filas, chips y hojas, con las
// funciones y los textos del panel web ((app)/consorcios).

// MARK: - Lista

/// Los edificios con lo que tiene cada uno (morosos, liquidar el mes, reclamos) y, abajo, «Lo que hay
/// que hacer» en todos (como /consorcios en el celular).
struct Consorcios: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [ConsorcioAPI]?
    @State private var alertas: [AlertaConsorcio] = []
    /// El período que toca liquidar en cada edificio (y si ya hay un borrador cargándose).
    @State private var liquidar: [String: (periodo: String, borrador: Bool)] = [:]
    @State private var vista: String?
    @State private var error: ErrorApi?
    @State private var nuevo = false

    private static let vistas = [("morosos", "Con morosos"), ("liquidar", "Para liquidar"), ("reclamos", "Con reclamos"), ("aldia", "Al día")]
    private static let enTexto = ["morosos": "con morosos", "liquidar": "para liquidar", "reclamos": "con reclamos", "aldia": "al día"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let lista {
                    if lista.isEmpty { vacio } else { contenido(lista) }
                } else if let error {
                    EstadoError(que: "los consorcios", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 4, miniatura: 56) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Consorcios")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo consorcio") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { EditarConsorcio(c: nil) }
    }

    private var vacio: some View {
        EstadoVacio(icono: "building.2", titulo: "Todavía no administrás edificios",
                    texto: "Cargá el consorcio con sus unidades y coeficientes. Después, cada mes, liquidás las expensas y le llega a cada propietario su link.",
                    accion: estado.escribe ? ("Cargar el primer consorcio", { nuevo = true }) : nil).padding(.top, 40)
    }

    private func enVista(_ c: ConsorcioAPI, _ v: String?) -> Bool {
        let m = c.metricas
        switch v {
        case "morosos": return (m?.deudores ?? 0) > 0
        case "liquidar": return liquidar[c.id] != nil
        case "reclamos": return (m?.trabajosPendientes ?? 0) > 0
        case "aldia": return (m?.deudores ?? 0) == 0 && liquidar[c.id] == nil && (m?.trabajosPendientes ?? 0) == 0
        default: return true
        }
    }

    @ViewBuilder private func contenido(_ lista: [ConsorcioAPI]) -> some View {
        let unidades = lista.reduce(0) { $0 + ($1.metricas?.unidades ?? 0) }
        Text("\(Cons.plural(lista.count, "edificio", "edificios")) · \(unidades) u.").estilo(.footnote).foregroundStyle(C.texto2)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipFiltro(texto: "Todos \(lista.count)", activo: vista == nil) { vista = nil }
                ForEach(Self.vistas, id: \.0) { k, t in
                    ChipFiltro(texto: "\(t) \(lista.filter { enVista($0, k) }.count)", activo: vista == k) { vista = vista == k ? nil : k }
                }
            }
        }
        if let v = vista {
            Button { vista = nil } label: {
                (Text("Edificios \(Self.enTexto[v] ?? "") · ").foregroundColor(C.texto2) + Text("ver todos").fontWeight(.semibold).foregroundColor(C.accion)).estilo(.footnote)
            }
            .buttonStyle(Presionable())
        }
        let filtrados = lista.filter { enVista($0, vista) }
        ForEach(filtrados) { c in tarjeta(c) }
        if filtrados.isEmpty { Text("Ningún edificio \(Self.enTexto[vista ?? ""] ?? "") por ahora.").estilo(.footnote).foregroundStyle(C.texto2) }
        HStack {
            Text("Lo que hay que hacer").estilo(.titulo3).foregroundStyle(C.texto)
            Spacer()
            if estado.escribe { Button("Nuevo consorcio") { nuevo = true }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion) }
        }
        .padding(.top, 8)
        hacer(lista)
    }

    private func tarjeta(_ c: ConsorcioAPI) -> some View {
        NavigationLink(value: ASeccion(clave: "consorcio", id: c.id)) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let u = c.fotoUrl.flatMap(URL.init(string:)) { Foto(url: u) } else {
                        ZStack { C.hundida; Image(systemName: "building.2").font(.system(size: 28)).foregroundStyle(C.texto3) }
                    }
                }
                .frame(height: 96).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(c.nombreCorto).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                    let u = c.metricas?.unidades ?? 0
                    Text("\(c.barrio.map { "\($0) · " } ?? "")\(u == 1 ? "1 unidad" : "\(u) unidades")").estilo(.footnote).foregroundStyle(C.texto2)
                    HStack(spacing: 6) {
                        ForEach(Cons.chipsEdificio(c, liquidar[c.id]?.periodo), id: \.0) { t, tono in ChipConsorcio(texto: t, tono: tono) }
                    }
                }
                .padding(12)
            }
            .tarjeta()
        }
        .buttonStyle(Presionable())
    }

    private struct Item: Identifiable {
        var id: String
        var icono: String
        var tono: Tono
        var titulo: String
        var detalle: String
        var monto: Double?
        var destino: AnyHashable
    }

    private func items(_ lista: [ConsorcioAPI]) -> [Item] {
        var out: [Item] = []
        for c in lista {
            guard let l = liquidar[c.id] else { continue }
            out.append(Item(id: "l" + c.id, icono: "hammer", tono: .oro, titulo: "Liquidar \(Cons.nombreMes(l.periodo))",
                            detalle: "\(c.nombreCorto) · \(l.borrador ? "los gastos ya están cargándose" : "todavía sin gastos")",
                            destino: AnyHashable(ALiquidarConsorcio(consorcio: c.id))))
        }
        for (i, a) in alertas.enumerated() {
            let (icono, tono, pestana, pedido): (String, Tono, String, String?) = {
                switch a.tipo {
                case "morosidad": return ("dollarsign.circle", .rojo, "unidades", "deben")
                case "trabajo": return ("wrench.and.screwdriver", .azul, "trabajos", nil)
                case "novedad": return ("book", .neutro, "novedades", nil)
                default: return ("wrench.adjustable", .oro, "resumen", nil)
                }
            }()
            let corto = a.consorcio.replacingOccurrences(of: "^consorcio\\s+", with: "", options: [.regularExpression, .caseInsensitive])
            out.append(Item(id: "a\(i)", icono: icono, tono: tono, titulo: Formato.mayuscula(a.texto),
                            detalle: corto + (a.dias.map { " · service en \($0) días" } ?? ""), monto: a.monto,
                            destino: AnyHashable(AFichaConsorcioEn(id: a.consorcioId, pestana: pestana, pedido: pedido))))
        }
        return out
    }

    @ViewBuilder private func hacer(_ lista: [ConsorcioAPI]) -> some View {
        let l = items(lista)
        if l.isEmpty {
            Label("Todo al día en tus edificios: sin morosos, sin reclamos abiertos y nada para liquidar.", systemImage: "checkmark.circle")
                .estilo(.texto14).foregroundStyle(C.okTinta).padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(l.enumerated()), id: \.element.id) { i, h in
                    Button { estado.abrir(h.destino) } label: {
                        RenglonConsorcio(primero: i == 0) {
                            IconoTono(icono: h.icono, tono: h.tono)
                            DosLineasConsorcio(titulo: h.titulo, detalle: h.detalle)
                            if let m = h.monto, m > 0 { Text(Formato.plata(m)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto) }
                            Chevron()
                        }
                    }
                    .buttonStyle(Presionable())
                }
            }
            .tarjeta()
        }
    }

    private func cargar() async {
        do {
            let l: [ConsorcioAPI] = try await estado.api.todas("/v1/consorcios")
            let a: [AlertaConsorcio] = (try? await estado.api.get("/v1/consorcios/alertas", query: [.init(name: "limite", value: "100")])) ?? []
            // Los períodos de cada edificio, en paralelo (como la web): para saber qué toca liquidar.
            let api = estado.api
            let periodos: [String: [PeriodoAPI]] = await withTaskGroup(of: (String, [PeriodoAPI]).self) { g in
                for c in l {
                    g.addTask {
                        let p: [PeriodoAPI] = (try? await api.get("/v1/consorcios/\(c.id)/periodos", query: [.init(name: "limite", value: "3")])) ?? []
                        return (c.id, p)
                    }
                }
                var out: [String: [PeriodoAPI]] = [:]
                for await (id, p) in g { out[id] = p }
                return out
            }
            var liq: [String: (periodo: String, borrador: Bool)] = [:]
            for c in l { if let x = Cons.liquidarEnLista(periodos[c.id] ?? []) { liq[c.id] = x } }
            liquidar = liq
            alertas = a
            lista = l
            error = nil
        } catch let e as ErrorApi {
            if lista == nil { error = e }
        } catch {}
    }
}

// MARK: - Alta y edición

/// Los datos del edificio (alta y edición): lo que sale en la liquidación y en el link de pago. En la
/// edición, también la foto (la fachada de la tarjeta).
struct EditarConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI?
    @State private var x = ConsorcioAPI(id: "", nombre: "", diaVencimiento: 10, diaSegundoVencimiento: 20, interesMensual: 3)
    @State private var guardando = false
    @State private var elegirFoto = false
    @State private var subiendoFoto = false
    @State private var fotoUrl: String?
    @State private var fotoId: String?

    var body: some View {
        NavigationStack {
            Form {
                if c != nil { Section { foto } }
                Section {
                    CampoConsorcio(etiqueta: "Nombre") { TextField("Consorcio Cabildo 2620", text: $x.nombre) }
                    CampoConsorcio(etiqueta: "Dirección y barrio (opcional)") { TextField("Av. Cabildo 2620, Belgrano", text: texto(\.direccion)) }
                    CampoConsorcio(etiqueta: "CUIT del consorcio (opcional)") { TextField("30-55912873-9", text: texto(\.cuit)).keyboardType(.numbersAndPunctuation) }
                    CampoConsorcio(etiqueta: "CBU o alias para transferir (opcional)", ayuda: "Sale en el link de cada unidad, con el botón para copiarlo.") {
                        TextField("", text: texto(\.cbu)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                }
                Section {
                    HStack(spacing: 12) {
                        CampoConsorcio(etiqueta: "Vence el día") { TextField("10", value: $x.diaVencimiento, format: .number).keyboardType(.numberPad) }
                        CampoConsorcio(etiqueta: "2.º vencimiento") { TextField("20", value: $x.diaSegundoVencimiento, format: .number).keyboardType(.numberPad) }
                    }
                    CampoConsorcio(etiqueta: "Interés por mora (% mensual)", ayuda: "Se suma a la deuda y es el recargo del 2.º vencimiento.") {
                        TextField("3", value: $x.interesMensual, format: .number).keyboardType(.decimalPad)
                    }
                    if let m = problema { Text(m).estilo(.footnote).foregroundStyle(C.error) }
                }
            }
            .navigationTitle(c == nil ? "Nuevo consorcio" : "Datos del consorcio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(c == nil ? "Crear y cargar unidades" : "Guardar") { Task { await guardar() } }
                        .disabled(x.nombre.trimmingCharacters(in: .whitespaces).isEmpty || problema != nil || guardando)
                }
            }
        }
        .onAppear { if let c { x = c; fotoUrl = c.fotoUrl; fotoId = c.fotoId } }
        .elegirArchivoConsorcio($elegirFoto, tipos: [.image]) { a in if let f = a.first { Task { await subirFoto(f.0, f.1, f.2) } } }
    }

    private func texto(_ k: WritableKeyPath<ConsorcioAPI, String?>) -> Binding<String> {
        Binding(get: { x[keyPath: k] ?? "" }, set: { x[keyPath: k] = $0 })
    }

    /// Lo que la API rechazaría, dicho antes (los días del 1 al 28; el 2.º después del 1.º).
    private var problema: String? {
        for d in [x.diaVencimiento, x.diaSegundoVencimiento].compactMap({ $0 }) where d < 1 || d > 28 { return "El día de vencimiento va del 1 al 28." }
        if let a = x.diaVencimiento, let b = x.diaSegundoVencimiento, b <= a { return "El 2.º vencimiento va después del 1.º." }
        if let i = x.interesMensual, i < 0 || i > 100 { return "La tasa va de 0 a 100% mensual." }
        return nil
    }

    @ViewBuilder private var foto: some View {
        HStack(spacing: 12) {
            ZStack {
                if let u = fotoUrl.flatMap(URL.init(string:)) { Foto(url: u) } else { ZStack { C.hundida; Image(systemName: "building.2").foregroundStyle(C.texto3) } }
            }
            .frame(width: 120, height: 72).clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Foto del edificio").estilo(.subheadFuerte)
                Text("La fachada que se ve en la tarjeta del\u{00A0}consorcio.").estilo(.footnote).foregroundStyle(C.texto2)
                HStack(spacing: 14) {
                    Button { elegirFoto = true } label: {
                        if subiendoFoto { ProgressView() } else { Text(fotoUrl == nil ? "Subir foto" : "Cambiar") }
                    }
                    .disabled(subiendoFoto)
                    if fotoUrl != nil { Button("Sacar", role: .destructive) { Task { await sacarFoto() } } }
                }
                .font(Estilo.subheadFuerte.font).buttonStyle(.borderless)
            }
        }
    }

    private struct FotoCuerpo: Encodable { var archivoId: String? }

    private func subirFoto(_ d: Data, _ n: String, _ t: String) async {
        guard let c else { return }
        subiendoFoto = true
        defer { subiendoFoto = false }
        do {
            let a = try await estado.api.subir(d, nombre: n, tipo: t, uso: "foto")
            let r: ConsorcioAPI = try await estado.api.enviar("PUT", "/v1/consorcios/\(c.id)/foto", FotoCuerpo(archivoId: a.id))
            fotoUrl = r.fotoUrl
            fotoId = r.fotoId
            estado.version += 1
            estado.avisar("Foto del edificio guardada")
        } catch { estado.avisar(error) }
    }

    private func sacarFoto() async {
        guard let c else { return }
        let antes = fotoId
        do {
            let _: ConsorcioAPI = try await estado.api.enviar("PUT", "/v1/consorcios/\(c.id)/foto", FotoCuerpo(archivoId: nil))
            fotoUrl = nil
            fotoId = nil
            estado.version += 1
            let api = estado.api
            estado.avisar("Sacaste la foto del edificio") {
                Task {
                    do {
                        let _: ConsorcioAPI = try await api.enviar("PUT", "/v1/consorcios/\(c.id)/foto", FotoCuerpo(archivoId: antes))
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        // El PUT reemplaza todo: se parte del consorcio entero y se cambia sólo lo editado (datos.ts).
        struct Cuerpo: Encodable {
            var nombre: String; var direccion: String?; var cuit: String?; var cbu: String?; var diaVencimiento: Int?; var diaSegundoVencimiento: Int?
            var interesMensual: Double; var modoExpensas: String; var fondoTipo: String; var fondoValor: Double; var notas: String?; var agenteId: String?
        }
        let cbu = x.cbu?.nonEmpty?.replacingOccurrences(of: "\\s+(?=\\d)", with: "", options: .regularExpression)
        let b = Cuerpo(nombre: x.nombre.trimmingCharacters(in: .whitespaces), direccion: x.direccion?.nonEmpty, cuit: x.cuit?.nonEmpty, cbu: cbu,
                       diaVencimiento: x.diaVencimiento, diaSegundoVencimiento: x.diaSegundoVencimiento, interesMensual: Cons.redondo(x.interesMensual ?? 0),
                       modoExpensas: c?.modoExpensas ?? "prorrateo", fondoTipo: c?.fondoTipo ?? "ninguno", fondoValor: Cons.redondo(c?.fondoValor ?? 0),
                       notas: c?.notas, agenteId: c?.agenteId)
        do {
            if let c {
                try await estado.api.hacer("PUT", "/v1/consorcios/\(c.id)", b)
                estado.avisar("Datos guardados")
                estado.version += 1
                cerrar()
            } else {
                let n: ConsorcioAPI = try await estado.api.enviar("POST", "/v1/consorcios", b)
                estado.version += 1
                cerrar()
                // Al crear, a cargar las unidades (como `?nueva=1` de la web).
                estado.abrir(AFichaConsorcioEn(id: n.id, pestana: "unidades", pedido: "nueva"))
            }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Ficha

/// Un edificio: la cabecera (CUIT, encargado y «Liquidar <mes>») y sus pestañas, como la web: Resumen,
/// Unidades, Expensas, Trabajos, Proveedores, Personal y Libro de novedades.
struct FichaConsorcio: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var c: ConsorcioAPI?
    @State private var empleados: [EmpleadoAPI] = []
    @State private var periodos: [PeriodoAPI] = []
    @State private var error: ErrorApi?
    @State private var pestana: String
    @State private var pedido: String?
    @State private var editando = false

    init(id: String, pestanaInicial: String = "resumen", pedidoInicial: String? = nil) {
        self.id = id
        _pestana = State(initialValue: pestanaInicial)
        _pedido = State(initialValue: pedidoInicial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c {
                    cabecera(c)
                    pestanas(c)
                    contenido(c)
                } else if let error {
                    EstadoError(que: "el consorcio", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada(c?.nombre ?? "Consorcio")
        .toolbar {
            Menu {
                if estado.escribe { Button { editando = true } label: { Label("Editar los datos del consorcio", systemImage: "pencil") } }
                Button { estado.abrir(ASeccion(clave: "bienes", id: id)) } label: { Label("Bienes del edificio", systemImage: "fire.extinguisher") }
                Button { estado.abrir(ASeccion(clave: "reglamento", id: id)) } label: { Label("Reglamento", systemImage: "doc.text") }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más acciones")
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editando) { EditarConsorcio(c: c) }
    }

    private func cabecera(_ c: ConsorcioAPI) -> some View {
        let enc = Cons.encargado(empleados)
        let rol = (enc?.categoria ?? "").range(of: "encargad", options: .caseInsensitive) != nil ? "encargado" : "personal"
        let sub = [c.cuit.map { "CUIT \($0)" }, enc.map { "\(rol) \($0.nombre)" }].compactMap { $0 }.joined(separator: " · ")
        let toca = Cons.aLiquidar(periodos).periodo
        return VStack(alignment: .leading, spacing: 10) {
            if !sub.isEmpty { Text(sub).estilo(.footnote).foregroundStyle(C.texto2) }
            HStack(spacing: 8) {
                Cifra(etiqueta: "Unidades", valor: "\(c.metricas?.unidades ?? 0)")
                Cifra(etiqueta: "Deuda", valor: Formato.plataCorta(c.metricas?.saldoAdeudado ?? 0))
                Cifra(etiqueta: "Reclamos", valor: "\(c.metricas?.trabajosPendientes ?? 0)")
            }
            if estado.escribe {
                Button("Liquidar \(Cons.nombreMes(toca))") { estado.abrir(ALiquidarConsorcio(consorcio: c.id)) }.buttonStyle(BotonAccion())
            }
        }
    }

    private func pestanas(_ c: ConsorcioAPI) -> some View {
        let u = c.metricas?.unidades ?? 0
        let t = c.metricas?.trabajosPendientes ?? 0
        let l: [(String, String)] = [("resumen", "Resumen"), ("unidades", u > 0 ? "Unidades\u{00A0}\(u)" : "Unidades"), ("expensas", "Expensas"),
                                     ("trabajos", t > 0 ? "Trabajos\u{00A0}\(t)" : "Trabajos"), ("proveedores", "Proveedores"), ("personal", "Personal"),
                                     ("novedades", "Libro de novedades")]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(l, id: \.0) { k, n in ChipFiltro(texto: n, activo: pestana == k) { pestana = k } } }
        }
    }

    /// Cambia de pestaña y le pasa lo que tiene que abrir (desde el Resumen).
    private func ir(_ p: String, _ q: String? = nil) {
        pedido = q
        pestana = p
    }

    @ViewBuilder private func contenido(_ c: ConsorcioAPI) -> some View {
        switch pestana {
        case "unidades": PestanaUnidadesConsorcio(c: c, pedido: $pedido)
        case "expensas": PestanaExpensasConsorcio(c: c, periodos: periodos)
        case "trabajos": PestanaTrabajosConsorcio(c: c, pedido: $pedido)
        case "proveedores": PestanaProveedoresConsorcio(c: c, periodos: periodos)
        case "personal": PestanaPersonalConsorcio(c: c, empleados: empleados, pedido: $pedido)
        case "novedades": PestanaNovedadesConsorcio(c: c, pedido: $pedido)
        default: ResumenConsorcio(c: c, empleados: empleados, periodos: periodos, ir: ir)
        }
    }

    private func cargar() async {
        let b = "/v1/consorcios/\(id)"
        do {
            let x: ConsorcioAPI = try await estado.api.get(b)
            empleados = (try? await estado.api.get("\(b)/empleados")) ?? []
            periodos = ((try? await estado.api.get("\(b)/periodos", query: [.init(name: "limite", value: "24")])) ?? [PeriodoAPI]()).sorted { $0.periodo > $1.periodo }
            c = x
            error = nil
        } catch let e as ErrorApi {
            if c == nil { error = e }
        } catch {}
    }
}

// MARK: - Resumen

/// Resumen del edificio: morosos (con «Intimar»), trabajos y reclamos abiertos, el personal con su
/// recibo del mes y el F931, y lo último del libro de novedades.
struct ResumenConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    var empleados: [EmpleadoAPI]
    var periodos: [PeriodoAPI]
    var ir: (String, String?) -> Void
    @State private var morosos: [MorosoConsorcio] = []
    @State private var parcial: Set<String> = []
    @State private var dias: [String: Int] = [:]
    @State private var trabajos: [TrabajoAPI] = []
    @State private var novedades: [NovedadAPI] = []
    @State private var recibos: [ReciboSueldoAPI] = []
    @State private var cargado = false
    @State private var error: ErrorApi?
    @State private var intimar = false
    @State private var previo: ArchivoPrevio?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error, !cargado {
                EstadoError(que: "el resumen", error: error) { Task { await cargar() } }
            } else if !cargado {
                EsqueletoFilas(filas: 4)
            } else {
                bloqueMorosos
                bloqueTrabajos
                bloquePersonal
                bloqueNovedades
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $intimar) { HojaIntimarMorosos(morosos: morosos, consorcioId: c.id, consorcio: c.nombre).hojaTLW([.large]) }
        .vistaPrevia($previo)
    }

    private func meses(_ m: MorosoConsorcio) -> String {
        if parcial.contains(m.unidadId) { return "parcial" }
        let n = max(1, Int((Double(dias[m.unidadId] ?? 0) / 30.5).rounded(.up)))
        return n == 1 ? "1 mes" : "\(n) meses"
    }

    @ViewBuilder private var bloqueMorosos: some View {
        let total = morosos.reduce(0) { $0 + $1.total }
        BloqueConsorcio(titulo: morosos.isEmpty ? "Morosos" : "Morosos · \(Formato.plata(total))", tono: morosos.isEmpty ? nil : .rojo,
                        accion: morosos.isEmpty ? nil : (morosos.count == 1 ? "Intimar" : "Intimar a los \(morosos.count)", { intimar = true })) {
            if morosos.isEmpty {
                VacioConsorcio(texto: "Nadie debe expensas. Cuando una unidad se atrase, aparece acá con lo que debe y el interés.")
            }
            ForEach(Array(morosos.enumerated()), id: \.element.unidadId) { i, m in
                Button { ir("unidades", "unidad:\(m.unidadId)") } label: {
                    RenglonConsorcio(primero: i == 0) {
                        Text(m.unidad).font(Estilo.filaLista.font).foregroundStyle(C.texto).frame(minWidth: 44, alignment: .leading)
                        Text("\(m.propietario ?? "Sin propietario") · \(meses(m))").estilo(.footnote).foregroundStyle(C.texto2).frame(maxWidth: .infinity, alignment: .leading)
                        Text(Cons.cifra(m.total)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.errorTinta)
                    }
                }
                .buttonStyle(Presionable())
            }
        }
    }

    private func cuando(_ f: String) -> String {
        guard let a = Fecha.dia(Cons.hoy), let b = Fecha.dia(f) else { return "" }
        let n = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        switch n {
        case 0: return "hoy"
        case 1: return "mañana"
        case -1: return "ayer"
        default: return n > 1 ? "el \(Cons.diaBarraMes(f))" : "desde el \(Cons.diaBarraMes(f))"
        }
    }

    private func detalle(_ t: TrabajoAPI) -> String {
        let d = Cons.diasDesde(t.creadoEn)
        var p: [String] = []
        if let u = t.unidad { p.append("reclamo de \(u)") }
        if let pr = t.proveedor { p.append(t.venceEl != nil && t.estado != "pendiente" ? "\(pr) va \(cuando(t.venceEl!))" : pr) }
        if t.estado == "pendiente" { p.append("presupuesto pendiente"); p.append(d == 1 ? "1 día" : "\(d) días") }
        return p.joined(separator: " · ")
    }

    @ViewBuilder private var bloqueTrabajos: some View {
        BloqueConsorcio(titulo: "Trabajos y reclamos", accion: estado.escribe ? ("Nuevo", { ir("trabajos", "nueva") }) : nil) {
            if trabajos.isEmpty { VacioConsorcio(texto: "Sin trabajos abiertos. Cargá un reclamo con fotos desde el edificio y seguilo hasta cerrarlo.") }
            ForEach(Array(trabajos.enumerated()), id: \.element.id) { i, t in
                let ch = Cons.chipTrabajo(t)
                Button { estado.abrir(ATrabajoConsorcio(consorcio: c.id, id: t.id)) } label: {
                    RenglonConsorcio(primero: i == 0) {
                        IconoTono(icono: Cons.iconoTrabajo(t), tono: t.prioridad == "alta" ? .rojo : .azul)
                        DosLineasConsorcio(titulo: t.titulo, detalle: detalle(t))
                        ChipConsorcio(texto: ch.0, tono: ch.1)
                    }
                }
                .buttonStyle(Presionable())
            }
        }
    }

    @ViewBuilder private var bloquePersonal: some View {
        let ultimo = recibos.first?.periodo
        let recibo: (String) -> ReciboSueldoAPI? = { e in recibos.first { $0.empleadoId == e && $0.periodo == ultimo } }
        BloqueConsorcio(titulo: ultimo.map { "Personal · recibos de \(Cons.nombreMes($0))" } ?? "Personal", accion: ultimo == nil ? ("Ver", { ir("personal", nil) }) : nil) {
            if empleados.isEmpty { VacioConsorcio(texto: "Sin personal cargado. Sumá al encargado y Corredor arma cada mes su recibo y el archivo para el F931.") }
            ForEach(Array(empleados.enumerated()), id: \.element.id) { i, e in
                Button { ir("personal", nil) } label: {
                    RenglonConsorcio(primero: i == 0) {
                        AvatarIniciales(nombre: e.nombre, tam: 36)
                        DosLineasConsorcio(titulo: e.nombre + (e.categoria.map { " · " + $0.lowercased().replacingOccurrences(of: " con vivienda", with: "").replacingOccurrences(of: " sin vivienda", with: "") } ?? ""),
                                  detalle: [e.notas, (e.categoria ?? "").range(of: "con vivienda", options: .caseInsensitive) != nil ? "con vivienda" : nil,
                                            Cons.antiguedad(e.ingreso).map { "\($0) años" }].compactMap { $0 }.joined(separator: " · "))
                        if let r = recibo(e.id), let b = r.bruto { Text(Cons.cifra(b)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto) }
                    }
                }
                .buttonStyle(Presionable())
            }
            if !empleados.isEmpty {
                RenglonConsorcio {
                    if let u = ultimo, let r = recibo(empleados[0].id) {
                        Button { ir("personal", "recibo:\(r.id)") } label: { Label("Recibo de \(Cons.nombreMes(u))", systemImage: "doc.text") }
                    } else if estado.escribe {
                        Button { ir("personal", "liquidar") } label: { Label("Liquidar sueldos", systemImage: "doc.text") }
                    }
                    Spacer()
                    Button { Task { await f931(ultimo) } } label: { Label("Exportar F931", systemImage: "square.and.arrow.down") }
                }
                .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private var bloqueNovedades: some View {
        BloqueConsorcio(titulo: "Libro de novedades", accion: estado.escribe ? ("Escribir", { ir("novedades", "nueva") }) : nil) {
            if novedades.isEmpty { VacioConsorcio(texto: "El libro está vacío. Anotá lo que pasa en el edificio: asambleas, arreglos, avisos a los vecinos.") }
            ForEach(Array(novedades.enumerated()), id: \.element.id) { i, n in
                Button { ir("novedades", nil) } label: {
                    RenglonConsorcio(primero: i == 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text([n.ocurrioEl.map { Cons.diaBarraMes($0) }, n.responsable].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                            Text(n.titulo).estilo(.texto14).foregroundStyle(C.texto)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(Presionable())
            }
        }
    }

    private func f931(_ periodo: String?) async {
        do {
            let ruta = "/v1/consorcios/\(c.id)/sueldos/f931" + (periodo.map { "?periodo=\($0)" } ?? "")
            let u = try await Documentos.archivo(ruta, nombre: periodo.map { "sueldos-\($0).csv" } ?? "sueldos-todos.csv", api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        let b = "/v1/consorcios/\(c.id)"
        do {
            let d: [DeudorAPI] = try await estado.api.get("\(b)/deudores")
            trabajos = (try? await estado.api.get("\(b)/trabajos", query: [.init(name: "estado", value: "pendiente,aprobado,en_curso"), .init(name: "limite", value: "6")])) ?? []
            novedades = (try? await estado.api.get("\(b)/novedades", query: [.init(name: "limite", value: "3")])) ?? []
            recibos = (try? await estado.api.get("\(b)/sueldos", query: [.init(name: "limite", value: "12")])) ?? []
            let unidades: [UnidadAPI] = (try? await estado.api.get("\(b)/unidades")) ?? []
            var ultimaDe: [String: Double] = [:]
            if let u = periodos.first(where: { $0.estado != "borrador" }), let f: PeriodoAPI = try? await estado.api.get("\(b)/periodos/\(u.id)") {
                for l in f.liquidaciones ?? [] { ultimaDe[l.unidadId] = l.total }
            }
            let tel = Dictionary(unidades.map { ($0.id, $0.propietarioTelefono) }, uniquingKeysWith: { a, _ in a })
            morosos = d.map { MorosoConsorcio(unidadId: $0.unidadId, unidad: $0.unidad, propietario: $0.propietario, telefono: tel[$0.unidadId] ?? nil, total: $0.total) }
            dias = Dictionary(d.map { ($0.unidadId, $0.dias ?? 0) }, uniquingKeysWith: { a, _ in a })
            parcial = Set(d.filter { ($0.dias ?? 0) <= 31 && (ultimaDe[$0.unidadId] ?? 0) > $0.saldo }.map(\.unidadId))
            cargado = true
            error = nil
        } catch let e as ErrorApi {
            error = e
        } catch {}
    }
}

// MARK: - Intimar

struct MorosoConsorcio: Hashable { var unidadId: String; var unidad: String; var propietario: String?; var telefono: String?; var total: Double }

/// «Intimar a los morosos»: a cada uno, un WhatsApp con su saldo y el link de su cuenta corriente,
/// que se arma al tocar. Sin celular cargado, el mensaje con el link se copia. Sale del teléfono de
/// quien lo manda (wa.me).
struct HojaIntimarMorosos: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var morosos: [MorosoConsorcio]
    var consorcioId: String
    var consorcio: String
    @State private var links: [String: String] = [:]
    @State private var armando: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A cada uno, su saldo con interés y el link de su cuenta.").estilo(.texto14).foregroundStyle(C.texto2)
                    VStack(spacing: 0) {
                        ForEach(Array(morosos.sorted { Cons.porUnidad($0.unidad, $1.unidad) }.enumerated()), id: \.element.unidadId) { i, m in fila(m, primera: i == 0) }
                    }
                    .tarjeta()
                }
                .padding(16)
            }
            .background(C.elevado)
            .navigationTitle("Intimar a los morosos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }

    private func fila(_ m: MorosoConsorcio, primera: Bool) -> some View {
        RenglonConsorcio(primero: primera) {
            Text(m.unidad).font(Estilo.filaLista.font).foregroundStyle(C.texto).frame(minWidth: 44, alignment: .leading)
            DosLineasConsorcio(titulo: m.propietario ?? "Sin propietario cargado", detalle: Formato.plata(m.total) + (m.telefono?.nonEmpty == nil ? " · sin celular" : ""))
            if let l = links[m.unidadId], let t = m.telefono?.nonEmpty {
                Button { Afuera.whatsapp(t, texto: texto(m, l)) } label: { Label("WhatsApp", systemImage: "bubble.left") }
                    .font(Estilo.footnoteFuerte.font).buttonStyle(.borderedProminent).tint(Color(hex: 0x25D366))
            } else {
                Button { Task { await armar(m) } } label: {
                    if armando == m.unidadId { Text("Armando…") } else { Label(m.telefono?.nonEmpty == nil ? "Copiar" : "Preparar", systemImage: m.telefono?.nonEmpty == nil ? "doc.on.doc" : "link") }
                }
                .font(Estilo.footnoteFuerte.font).buttonStyle(.bordered).disabled(armando != nil)
            }
        }
    }

    private func texto(_ m: MorosoConsorcio, _ url: String) -> String {
        let nombre = (m.propietario ?? "").split(separator: " ").first.map(String.init) ?? ""
        let inmo = estado.inmobiliaria?.nombre ?? ""
        return "Hola\(nombre.isEmpty ? "" : " " + nombre), te escribimos\(inmo.isEmpty ? "" : " de " + inmo) por las expensas de \(consorcio), unidad \(m.unidad). El saldo hoy es de \(Formato.plata(m.total)), con el interés por mora. Acá tenés el detalle y cómo pagar: \(url)"
    }

    private func armar(_ m: MorosoConsorcio) async {
        armando = m.unidadId
        defer { armando = nil }
        do {
            let ruta = "/v1/consorcios/\(consorcioId)/unidades/\(m.unidadId)/link"
            let l: LinkConsorcio = try await estado.api.enviar("POST", ruta, [String: String]())
            links[m.unidadId] = l.url
            if m.telefono?.nonEmpty == nil {
                Cons.copiar(texto(m, l.url))
                estado.avisar("Sin celular de \(m.propietario ?? m.unidad): copiamos el mensaje con el link")
            }
        } catch {
            estado.avisar(error)
        }
    }
}
