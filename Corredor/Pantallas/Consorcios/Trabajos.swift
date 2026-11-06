import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Trabajos

/// Trabajos y reclamos: lo abierto primero, con quién lo arregla y en qué está; cada uno abre su
/// ficha con fotos y estado. Abiertos o cerrados.
struct PestanaTrabajosConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    @Binding var pedido: String?
    @State private var cerrados = false
    @State private var trabajos: [TrabajoAPI]?
    @State private var error: ErrorApi?
    @State private var nuevo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ChipFiltro(texto: "Abiertos", activo: !cerrados) { cerrados = false }
                ChipFiltro(texto: "Cerrados", activo: cerrados) { cerrados = true }
                Spacer()
                if estado.escribe { Button { nuevo = true } label: { Label("Nuevo", systemImage: "plus") }.font(Estilo.footnoteFuerte.font).buttonStyle(.borderedProminent).tint(C.accion) }
            }
            if let trabajos { lista(trabajos) } else if let error {
                EstadoError(que: "los trabajos", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 4) }
        }
        .task(id: "\(estado.version)-\(cerrados)") { await cargar() }
        .onChange(of: pedido, initial: true) { _, p in
            if p == "nueva" { if estado.escribe { nuevo = true }; pedido = nil }
        }
        .sheet(isPresented: $nuevo) {
            HojaTrabajoConsorcio(c: c, t: nil) { t in estado.abrir(ATrabajoConsorcio(consorcio: c.id, id: t.id)) }
        }
    }

    private func detalle(_ t: TrabajoAPI) -> String {
        [t.unidad.map { "reclamo de \($0)" }, t.proveedor ?? "sin proveedor", t.presupuesto.map { "presupuesto \(Formato.plata($0))" },
         t.venceEl != nil && t.estado != "hecho" ? "va el \(Cons.diaBarraMes(t.venceEl!))" : nil, Cons.haceDias(Cons.diasDesde(t.creadoEn))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func lista(_ l: [TrabajoAPI]) -> some View {
        VStack(spacing: 0) {
            if l.isEmpty {
                VacioConsorcio(texto: cerrados ? "Todavía no cerraste ningún trabajo." : "Sin trabajos abiertos. Cuando un vecino reclame algo, cargalo con fotos y seguilo hasta cerrarlo.")
            }
            ForEach(Array(l.enumerated()), id: \.element.id) { i, t in
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
        .tarjeta()
    }

    private func cargar() async {
        do {
            trabajos = try await estado.api.get("/v1/consorcios/\(c.id)/trabajos",
                                                query: [.init(name: "limite", value: "200"), .init(name: "estado", value: cerrados ? "hecho,cancelado" : "pendiente,aprobado,en_curso")])
            error = nil
        } catch let e as ErrorApi {
            if trabajos == nil { error = e }
        } catch {}
    }
}

// MARK: - Ficha del trabajo

/// Un trabajo o reclamo: los cuatro pasos (Abierto · Presupuesto · En obra · Cerrado) que cambian al
/// toque con deshacer; las fotos con la cámara; el proveedor a un toque por WhatsApp; y «Avisar a los
/// vecinos», que deja el aviso en el libro de novedades y lo comparte.
struct FichaTrabajoConsorcio: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    var id: String
    @State private var t: TrabajoAPI?
    @State private var c: ConsorcioAPI?
    @State private var error: ErrorApi?
    @State private var local: String?
    @State private var sacadas: Set<String> = []
    @State private var sumar = false
    @State private var subiendo = 0
    @State private var editando = false
    @State private var avisando = false
    @State private var previo: ArchivoPrevio?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let t, let c { contenido(t, c) } else if let error {
                    EstadoError(que: "el trabajo", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada(t?.titulo ?? "Trabajo")
        .toolbar {
            if estado.escribe, let t {
                Menu {
                    Button { editando = true } label: { Label("Editar el trabajo", systemImage: "pencil") }
                    if t.estado != "cancelado" { Button(role: .destructive) { Task { await cambiar("cancelado") } } label: { Label("Cancelar el trabajo", systemImage: "xmark.circle") } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más acciones")
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editando) { if let c, let t { HojaTrabajoConsorcio(c: c, t: t) { _ in } } }
        .sheet(isPresented: $avisando) { if let c, let t { HojaAvisoVecinos(c: c, t: t) } }
        .elegirArchivoConsorcio($sumar, tipos: [.image, .pdf], multiple: true) { a in Task { await subir(a) } }
        .vistaPrevia($previo)
    }

    @ViewBuilder private func contenido(_ t0: TrabajoAPI, _ c: ConsorcioAPI) -> some View {
        let estadoT = local ?? t0.estado
        let i = Cons.pasosTrabajo.firstIndex { $0.0 == estadoT } ?? -1
        Text(c.nombreCorto).estilo(.footnote).foregroundStyle(C.texto2)
        HStack(spacing: 6) {
            ForEach(Array(Cons.pasosTrabajo.enumerated()), id: \.element.0) { n, p in
                let on = n == i
                let hecho = i >= 0 && n < i
                Button { Task { await cambiar(p.0) } } label: {
                    Text(p.1).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                        .foregroundStyle(on ? C.sobreAccion : hecho ? C.okTinta : C.texto2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? C.accion : hecho ? C.okFondo : C.hundida, in: Capsule())
                }
                .buttonStyle(Presionable()).disabled(!estado.escribe)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        if estadoT == "cancelado" { Text("Este trabajo está cancelado. Tocá un paso para reabrirlo.").estilo(.footnote).foregroundStyle(C.avisoTinta) }
        fotos(t0)
        proveedor(t0, c, estadoT)
        if let d = t0.descripcion?.nonEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text([t0.unidad.map { "Reclamó \($0)" } ?? "Lo cargó la administración", t0.creadoEn.map { Cons.diaBarraMes(String($0.prefix(10))) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .estilo(.footnote).foregroundStyle(C.texto2)
                Text(d).estilo(.body16).foregroundStyle(C.texto)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        }
        if estado.escribe { Button("Avisar a los vecinos") { avisando = true }.buttonStyle(BotonAccion()).padding(.top, 6) }
    }

    @ViewBuilder private func fotos(_ t: TrabajoAPI) -> some View {
        let adj = (t.adjuntos ?? []).filter { !sacadas.contains($0.archivoId) }
        let imagenes = adj.filter { $0.tipo.hasPrefix("image/") }
        let otros = adj.filter { !$0.tipo.hasPrefix("image/") }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(imagenes) { a in
                ImagenConsorcio(id: a.archivoId).frame(height: 96).clipShape(.rect(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if estado.escribe {
                            Button { sacar(a) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.5)) }
                                .padding(4).accessibilityLabel("Sacar esta foto")
                        }
                    }
                    .onTapGesture { Task { await ver(a.archivoId) } }
            }
            if estado.escribe {
                Button { sumar = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        if subiendo > 0 { ProgressView() } else { Image(systemName: "camera").font(.system(size: 24)).foregroundStyle(C.texto2) }
                    }
                    .frame(height: 96)
                }
                .buttonStyle(Presionable()).accessibilityLabel("Sumar fotos")
            }
        }
        ForEach(otros) { a in
            HStack {
                Button { Task { await ver(a.archivoId) } } label: { Label(a.nombre, systemImage: "doc") }.font(Estilo.subheadFuerte.font)
                Spacer()
                if estado.escribe { Button { sacar(a) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }.accessibilityLabel("Sacar \(a.nombre)") }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder private func proveedor(_ t: TrabajoAPI, _ c: ConsorcioAPI, _ e: String) -> some View {
        if let p = t.proveedor {
            let dias = Cons.diasDesde(t.creadoEn)
            let det: (String, Bool) = {
                if e == "pendiente" { return ("Presupuesto pedido \(Cons.haceDias(dias))", true) }
                if let v = t.venceEl, e != "hecho" { return ("Va el \(Cons.diaBarraMes(v))\(t.presupuesto.map { " · \(Formato.plata($0))" } ?? "")", false) }
                if let pr = t.presupuesto { return ("Presupuesto \(Formato.plata(pr))", false) }
                return (t.proveedorRubro ?? "Proveedor", false)
            }()
            HStack(spacing: 12) {
                IconoTono(icono: Cons.iconoRubro(t.proveedorRubro), tono: .neutro)
                DosLineasConsorcio(titulo: p, detalle: det.0, tonoDetalle: det.1 ? C.avisoTinta : C.texto2)
                if let tel = t.proveedorTelefono?.nonEmpty {
                    Button { Afuera.whatsapp(tel, texto: "Hola, te escribo de la administración del \(c.nombre) por «\(t.titulo)».") } label: {
                        Image("LogoWhatsApp").resizable().frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Escribirle a \(p) por WhatsApp")
                }
            }
            .padding(12).tarjeta()
        } else {
            Button { if estado.escribe { editando = true } } label: {
                HStack(spacing: 12) {
                    IconoTono(icono: "wrench.and.screwdriver", tono: .neutro)
                    DosLineasConsorcio(titulo: "Sin proveedor", detalle: "Tocá para elegir quién lo arregla.")
                }
                .padding(12).tarjeta()
            }
            .buttonStyle(Presionable())
        }
    }

    private var ruta: String { "/v1/consorcios/\(consorcio)/trabajos/\(id)" }

    private func cargar() async {
        do {
            let x: TrabajoAPI = try await estado.api.get(ruta)
            if c == nil { c = try await estado.api.get("/v1/consorcios/\(consorcio)") }
            t = x
            local = nil
            sacadas = []
            error = nil
        } catch let e as ErrorApi {
            if t == nil { error = e }
        } catch {}
    }

    private struct Paso: Encodable { var estado: String }

    private func cambiar(_ nuevo: String) async {
        guard let t else { return }
        let antes = local ?? t.estado
        guard nuevo != antes else { return }
        local = nuevo
        do {
            let _: TrabajoAPI = try await estado.api.enviar("PATCH", ruta, Paso(estado: nuevo))
            let nombre = Cons.pasosTrabajo.first { $0.0 == nuevo }?.1 ?? (nuevo == "cancelado" ? "Cancelado" : nuevo)
            let api = estado.api
            let r = ruta
            estado.avisar("\(t.titulo) · \(nombre)") {
                Task {
                    do {
                        let _: TrabajoAPI = try await api.enviar("PATCH", r, Paso(estado: antes))
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            estado.version += 1
        } catch {
            local = nil
            let d = (error as? ErrorApi)?.detalle ?? "Probá de nuevo."
            estado.sugerir("No se guardó · \(d)", "Reintentar") { Task { await cambiar(nuevo) } }
        }
    }

    private func subir(_ archivos: [(Data, String, String)]) async {
        for a in archivos {
            subiendo += 1
            do {
                let x = try await estado.api.subir(a.0, nombre: a.1, tipo: a.2, uso: a.2.hasPrefix("image/") ? "foto" : "documento")
                struct Adj: Encodable { var archivoId: String }
                let _: TrabajoAPI = try await estado.api.enviar("POST", "\(ruta)/adjuntos", Adj(archivoId: x.id))
            } catch let e as ErrorApi where e.sinConexion {
                estado.avisar("Sin señal: sacá las fotos de nuevo cuando vuelva.", ok: false)
                subiendo -= 1
                break
            } catch {
                estado.avisar("No se subió \(a.1) · \((error as? ErrorApi)?.detalle ?? "probá de nuevo")", ok: false)
            }
            subiendo -= 1
        }
        estado.version += 1
    }

    private func sacar(_ a: AdjuntoTrabajo) {
        sacadas.insert(a.archivoId)
        let api = estado.api
        let r = ruta
        Task {
            do {
                try await api.hacer("DELETE", "\(r)/adjuntos/\(a.archivoId)")
                estado.avisar("Sacaste \(a.tipo.hasPrefix("image/") ? "una foto" : a.nombre)") {
                    Task {
                        struct Adj: Encodable { var archivoId: String }
                        do { let _: TrabajoAPI = try await api.enviar("POST", "\(r)/adjuntos", Adj(archivoId: a.archivoId)) } catch { estado.avisar(error) }
                        estado.version += 1
                    }
                }
            } catch {
                sacadas.remove(a.archivoId)
                estado.avisar(error)
            }
        }
    }

    private func ver(_ archivo: String) async {
        do {
            let u = try await Documentos.archivoConsorcio(archivo, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

// MARK: - Alta y edición

/// Los datos de un trabajo o reclamo (alta y edición): qué pasa, el detalle o lo que dijo el vecino,
/// quién lo reclamó, la prioridad, el proveedor (o uno nuevo), el presupuesto y el día que va.
struct HojaTrabajoConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var t: TrabajoAPI?
    var alCrear: (TrabajoAPI) -> Void
    @State private var titulo = ""
    @State private var descripcion = ""
    @State private var unidad = ""
    @State private var prioridad = "media"
    @State private var proveedor = ""
    @State private var nuevoProveedor = ""
    @State private var rubro = ""
    @State private var telefono = ""
    @State private var presupuesto: Double?
    @State private var conDia = false
    @State private var dia = Date()
    @State private var unidades: [UnidadAPI] = []
    @State private var proveedores: [ProveedorConsorcio] = []
    @State private var listo = false
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CampoConsorcio(etiqueta: "Qué pasa") { TextField("Filtración en cochera", text: $titulo) }
                    CampoConsorcio(etiqueta: "Detalle o lo que dijo el vecino (opcional)") {
                        TextField("«Gotea sobre mi cochera desde el lunes.»", text: $descripcion, axis: .vertical).lineLimit(3...6)
                    }
                    Picker("Lo reclamó", selection: $unidad) {
                        Text("El edificio (común)").tag("")
                        ForEach(unidades.sorted { Cons.porUnidad($0.etiqueta, $1.etiqueta) }) { Text($0.etiqueta).tag($0.id) }
                    }
                    Picker("Prioridad", selection: $prioridad) {
                        Text("Alta").tag("alta")
                        Text("Media").tag("media")
                        Text("Baja").tag("baja")
                    }
                }
                Section {
                    Picker("Proveedor", selection: $proveedor) {
                        Text("Todavía nadie").tag("")
                        ForEach(proveedores) { Text($0.conRubro).tag($0.id) }
                        Text("Otro (cargarlo)…").tag("otro")
                    }
                    if proveedor == "otro" {
                        CampoConsorcio(etiqueta: "Nombre del proveedor") { TextField("", text: $nuevoProveedor) }
                        CampoConsorcio(etiqueta: "Rubro (opcional)") { TextField("Plomería", text: $rubro) }
                        CampoConsorcio(etiqueta: "Celular (opcional)") { TextField("", text: $telefono).keyboardType(.phonePad) }
                    }
                    CampoConsorcio(etiqueta: "Presupuesto (opcional)") { TextField("Monto", value: $presupuesto, format: .number).keyboardType(.decimalPad) }
                    Toggle("Va el día", isOn: $conDia)
                    if conDia { DatePicker("Día", selection: $dia, displayedComponents: .date) }
                }
            }
            .navigationTitle(t == nil ? "Nuevo trabajo o reclamo" : "Editar el trabajo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t == nil ? "Cargar" : "Guardar") { Task { await guardar() } }
                        .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty || (proveedor == "otro" && nuevoProveedor.trimmingCharacters(in: .whitespaces).isEmpty) || guardando)
                }
            }
        }
        .task {
            if !listo, let t {
                titulo = t.titulo
                descripcion = t.descripcion ?? ""
                unidad = t.unidadId ?? ""
                prioridad = t.prioridad ?? "media"
                proveedor = t.proveedorId ?? ""
                presupuesto = t.presupuesto
                if let v = t.venceEl.flatMap(Fecha.dia) { conDia = true; dia = v }
            }
            listo = true
            unidades = (try? await estado.api.get("/v1/consorcios/\(c.id)/unidades")) ?? []
            proveedores = (try? await ProveedoresConsorcio.todos(estado.api)) ?? []
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct Datos: Encodable {
            var titulo: String; var descripcion: String?; var unidadId: String?; var proveedorId: String?; var estado: String; var prioridad: String
            var presupuesto: Double?; var costoReal: Double?; var responsable: String?; var venceEl: String?; var hechoEl: String?
        }
        do {
            var pid: String? = proveedor.isEmpty ? nil : proveedor
            if proveedor == "otro" {
                let p = try await ProveedoresConsorcio.crear(estado.api, .init(nombre: nuevoProveedor.trimmingCharacters(in: .whitespaces), rubro: rubro.nonEmpty, telefono: telefono.nonEmpty))
                pid = p.id
                proveedor = p.id
                proveedores.append(p)
            }
            let d = Datos(titulo: titulo.trimmingCharacters(in: .whitespaces), descripcion: descripcion.nonEmpty, unidadId: unidad.nonEmpty, proveedorId: pid,
                          estado: t?.estado ?? "pendiente", prioridad: prioridad, presupuesto: presupuesto.map(Cons.redondo), costoReal: t?.costoReal,
                          responsable: t?.responsable, venceEl: conDia ? Formato.diaISO(dia) : nil, hechoEl: t?.hechoEl)
            let base = "/v1/consorcios/\(c.id)/trabajos"
            if let t {
                let _: TrabajoAPI = try await estado.api.enviar("PUT", "\(base)/\(t.id)", d)
                estado.avisar("Trabajo guardado")
                estado.version += 1
                cerrar()
            } else {
                let n: TrabajoAPI = try await estado.api.enviar("POST", base, d)
                estado.version += 1
                cerrar()
                alCrear(n)
            }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Avisar a los vecinos

/// «Avisar a los vecinos»: el texto armado según el estado queda en el libro de novedades y se comparte
/// con la hoja del sistema (el grupo del edificio).
struct HojaAvisoVecinos: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    var t: TrabajoAPI
    @State private var texto = ""
    @State private var guardando = false
    @State private var compartir: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Queda en el libro de novedades y lo compartís en el grupo del edificio.").estilo(.footnote).foregroundStyle(C.texto2)
                    CampoConsorcio(etiqueta: "Aviso") { TextField("", text: $texto, axis: .vertical).lineLimit(5...12) }
                }
            }
            .navigationTitle("Avisar a los vecinos").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anotar y compartir") { Task { await anotar() } }.disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || guardando)
                }
            }
        }
        .onAppear { if texto.isEmpty { texto = textoAviso } }
        .sheet(item: Binding(get: { compartir.map { TextoCompartir(texto: $0) } }, set: { if $0 == nil { compartir = nil; cerrar() } })) { x in
            CompartirConsorcio(items: [x.texto]).ignoresSafeArea()
        }
    }

    struct TextoCompartir: Identifiable { var texto: String; var id: String { texto } }

    private var textoAviso: String {
        let tit = t.titulo.prefix(1).lowercased() + t.titulo.dropFirst()
        let medio: String
        if t.estado == "hecho" { medio = "Ya quedó resuelto." }
        else if let p = t.proveedor { medio = "Ya está \(p)\(t.venceEl.map { " y va el \(Cons.diaBarraMes($0))" } ?? " viéndolo")." }
        else { medio = "Ya lo estamos viendo." }
        return "Vecinos de \(c.nombreCorto): \(tit). \(medio) Cualquier cosa, escribannos. La administración."
    }

    private func anotar() async {
        guardando = true
        defer { guardando = false }
        struct N: Encodable { var tipo = "aviso"; var estado = "resuelto"; var titulo: String; var descripcion: String?; var unidadId: String? }
        let x = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(c.id)/novedades", N(titulo: String(x.prefix(200)), descripcion: x.count > 200 ? x : nil, unidadId: t.unidadId))
            estado.avisar("Aviso anotado en el libro de novedades.")
            estado.version += 1
            compartir = x
        } catch { estado.avisar(error) }
    }
}

/// La hoja de compartir del sistema.
struct CompartirConsorcio: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
