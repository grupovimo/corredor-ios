import PhotosUI
import SwiftUI

// Lo que completa el alcance del panel: documentos, bienes y reglamento de consorcios, y lotes y
// masterplan de emprendimientos.

// MARK: - Documentos

struct DocumentoAPI: Codable, Identifiable, Hashable {
    var id: String
    var archivoId: String?
    var nombre: String
    var tipo: String?
    var bytes: Int?
    var subidoPor: String?
    var creadoEn: Date?
    var url: String?
}

/// Los documentos de un contrato o de una propiedad: verlos, subir un PDF o una foto, y borrarlos.
struct DocumentosLista: View {
    @Environment(Estado.self) private var estado
    /// «contrato» o «propiedad».
    var de: String
    var id: String
    @State private var lista: [DocumentoAPI] = []
    @State private var eligiendo = false
    @State private var foto: PhotosPickerItem?
    @State private var previo: ArchivoPrevio?
    @State private var subiendo = false

    var body: some View {
        List {
            if lista.isEmpty { Text("El contrato firmado, el DNI, la escritura, los planos…").foregroundStyle(C.texto2) }
            ForEach(lista) { d in
                Button { Task { await abrir(d) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.tipo?.contains("pdf") == true ? "doc.richtext" : "photo").foregroundStyle(C.azulTinta).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(d.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                            Text([d.subidoPor, d.creadoEn.map { Formato.cuando($0) }, d.bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
                                .compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                    }
                }
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/documentos/\(d.id)"); await cargar() } } } }
            }
            if subiendo { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Documentos")
        .toolbar {
            if estado.escribe {
                Menu {
                    Button { eligiendo = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                    PhotosPicker(selection: $foto, matching: .images) { Label("Una foto", systemImage: "photo") }
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await cargar() }
        .vistaPrevia($previo)
        .fileImporter(isPresented: $eligiendo, allowedContentTypes: [.pdf, .image]) { r in
            if case .success(let u) = r {
                Task {
                    let acceso = u.startAccessingSecurityScopedResource()
                    defer { if acceso { u.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: u) { await subir(d, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg") }
                }
            }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) { await subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "Foto.jpg", tipo: "image/jpeg") }
                foto = nil
            }
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/documentos", query: [.init(name: de, value: id)])) ?? [] }

    private func subir(_ datos: Data, nombre: String, tipo: String) async {
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            struct C: Encodable { var archivoId: String; var nombre: String; var contratoId: String?; var propiedadId: String? }
            try await estado.api.hacer("POST", "/v1/documentos", C(archivoId: a.id, nombre: nombre, contratoId: de == "contrato" ? id : nil, propiedadId: de == "propiedad" ? id : nil))
            await cargar()
        } catch { estado.avisar(error) }
    }

    /// Lo baja con la sesión de la app y lo muestra con la vista previa (compartir, imprimir).
    private func abrir(_ d: DocumentoAPI) async {
        guard let a = d.archivoId else { return }
        do {
            let datos = try await estado.api.pedir("GET", "/v1/archivos/\(a)/contenido")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(d.nombre)
            try datos.write(to: u)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

// MARK: - Bienes del consorcio

struct BienAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var categoria: String?
    var ubicacion: String?
    var cantidad: Int?
    var estado: String?
    var proximoService: String?
    var responsable: String?
    var notas: String?

    static let categorias = [("matafuego", "Matafuego"), ("ascensor", "Ascensor"), ("bomba", "Bomba"), ("tanque", "Tanque"), ("luminaria", "Luminaria"),
                             ("motor", "Motor"), ("mobiliario", "Mobiliario"), ("herramienta", "Herramienta"), ("otro", "Otro")]
    static let estados = [("ok", "En orden"), ("a_revisar", "A revisar"), ("vencido", "Vencido"), ("baja", "De baja")]
}

/// Los bienes del edificio (matafuegos, ascensores, bombas…) con su estado y el próximo service.
struct BienesConsorcio: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    @State private var lista: [BienAPI] = []
    @State private var editando: BienAPI?

    var body: some View {
        List {
            if lista.isEmpty { Text("Matafuegos, ascensores, bombas: con su próximo service, te avisamos antes.").foregroundStyle(C.texto2) }
            ForEach(lista) { b in
                Button { editando = b } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(b.nombre + (b.cantidad.map { $0 > 1 ? " × \($0)" : "" } ?? "")).estilo(.filaLista).foregroundStyle(C.texto)
                            Text([b.ubicacion, b.proximoService.map { "service: \($0)" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        let t: Tono = b.estado == "vencido" ? .rojo : b.estado == "a_revisar" ? .oro : b.estado == "baja" ? .neutro : .verde
                        Text(BienAPI.estados.first { $0.0 == b.estado }?.1 ?? "En orden").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(t.tinta)
                            .padding(.horizontal, 9).frame(height: 24).background(t.fondo, in: Capsule())
                    }
                }
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/consorcios/\(consorcio)/bienes/\(b.id)"); await cargar() } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Bienes")
        .toolbar { if estado.escribe { Button { editando = BienAPI(id: "", nombre: "", categoria: "matafuego", cantidad: 1, estado: "ok") } label: { Image(systemName: "plus") } } }
        .task { await cargar() }
        .sheet(item: $editando) { b in
            NavigationStack { FormBien(b: b) { x in Task { await guardar(x) } } }
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/consorcios/\(consorcio)/bienes")) ?? [] }

    private func guardar(_ b: BienAPI) async {
        struct C: Encodable { var nombre: String; var categoria: String; var ubicacion: String?; var cantidad: Int; var estado: String; var proximoService: String?; var responsable: String?; var notas: String? }
        let c = C(nombre: b.nombre, categoria: b.categoria ?? "otro", ubicacion: b.ubicacion?.nonEmpty, cantidad: b.cantidad ?? 1, estado: b.estado ?? "ok",
                  proximoService: b.proximoService, responsable: b.responsable?.nonEmpty, notas: b.notas?.nonEmpty)
        do {
            if b.id.isEmpty { try await estado.api.hacer("POST", "/v1/consorcios/\(consorcio)/bienes", c) } else { try await estado.api.hacer("PUT", "/v1/consorcios/\(consorcio)/bienes/\(b.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormBien: View {
    @Environment(\.dismiss) private var cerrar
    @State var b: BienAPI
    var guardar: (BienAPI) -> Void
    var body: some View {
        Form {
            TextField("Nombre", text: $b.nombre)
            Picker("Categoría", selection: Binding(get: { b.categoria ?? "otro" }, set: { b.categoria = $0 })) { ForEach(BienAPI.categorias, id: \.0) { Text($0.1).tag($0.0) } }
            TextField("Dónde está", text: Binding(get: { b.ubicacion ?? "" }, set: { b.ubicacion = $0 }))
            Stepper("Cantidad: \(b.cantidad ?? 1)", value: Binding(get: { b.cantidad ?? 1 }, set: { b.cantidad = $0 }), in: 1...500)
            Picker("Estado", selection: Binding(get: { b.estado ?? "ok" }, set: { b.estado = $0 })) { ForEach(BienAPI.estados, id: \.0) { Text($0.1).tag($0.0) } }
            DatePicker("Próximo service", selection: Binding(get: { b.proximoService.flatMap(Fecha.dia) ?? Date() }, set: { b.proximoService = Formato.diaISO($0) }), displayedComponents: .date)
            TextField("Responsable", text: Binding(get: { b.responsable ?? "" }, set: { b.responsable = $0 }))
            TextField("Notas", text: Binding(get: { b.notas ?? "" }, set: { b.notas = $0 }), axis: .vertical)
        }
        .navigationTitle(b.id.isEmpty ? "Bien nuevo" : b.nombre).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(b); cerrar() }.disabled(b.nombre.isEmpty) }
        }
    }
}

// MARK: - Reglamento del consorcio

/// Los coeficientes del reglamento: si los de hoy cambiaron desde que se guardaron, cuáles; y
/// «Guardar los de hoy como reglamento».
struct ReglamentoConsorcio: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    @State private var r: R?

    struct R: Codable {
        struct Cambio: Codable, Hashable { var unidad: String?; var columna: String?; var reglamento: Double?; var hoy: Double? }
        var guardadoEn: Date?
        var sinCambios: Bool?
        var cambios: [Cambio]?
    }

    var body: some View {
        List {
            if let r {
                Section {
                    if r.guardadoEn == nil {
                        Text("Todavía no guardaste los coeficientes del reglamento.").foregroundStyle(C.texto2)
                    } else if r.sinCambios == true {
                        Label("Coeficientes del reglamento: sin cambios", systemImage: "checkmark.seal").foregroundStyle(C.okTinta)
                    } else {
                        Label("Hay coeficientes distintos a los del reglamento", systemImage: "exclamationmark.triangle").foregroundStyle(C.avisoTinta)
                    }
                    if let g = r.guardadoEn { Text("Guardado \(Formato.cuando(g))").estilo(.footnote).foregroundStyle(C.texto3) }
                }
                if let c = r.cambios, !c.isEmpty {
                    Section("Cambios") {
                        ForEach(c, id: \.self) { x in
                            LabeledContent("\(x.unidad ?? "") · \(x.columna ?? "")", value: "\(Self.num(x.reglamento)) → \(Self.num(x.hoy))")
                        }
                    }
                }
                if estado.esDuenio {
                    Section { Button("Guardar los de hoy como reglamento") { Task { try? await estado.api.hacer("PUT", "/v1/consorcios/\(consorcio)/reglamento"); await cargar(); estado.avisar("Reglamento guardado") } } }
                }
            } else { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Reglamento")
        .task { await cargar() }
    }

    static func num(_ n: Double?) -> String { n.map { String(format: "%.4f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—" }
    private func cargar() async { r = try? await estado.api.get("/v1/consorcios/\(consorcio)/reglamento") }
}

// MARK: - Lotes y masterplan de un emprendimiento

/// Crear lotes en serie (manzana, del 1 al 40, superficie, precio).
struct NuevosLotes: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var emprendimiento: String
    @State private var manzana = "A"
    @State private var desde = 1
    @State private var hasta = 20
    @State private var superficie: Double?
    @State private var frente: Double?
    @State private var fondo: Double?
    @State private var precio: Double?
    @State private var moneda = "USD"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Manzana", text: $manzana)
                Stepper("Desde el lote \(desde)", value: $desde, in: 1...999)
                Stepper("Hasta el lote \(hasta)", value: $hasta, in: desde...999)
                TextField("Superficie m²", value: $superficie, format: .number).keyboardType(.decimalPad)
                TextField("Frente m", value: $frente, format: .number).keyboardType(.decimalPad)
                TextField("Fondo m", value: $fondo, format: .number).keyboardType(.decimalPad)
                Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Precio", value: $precio, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Lotes en serie").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        Task {
                            struct C: Encodable { var manzana: String; var desde: Int; var hasta: Int; var superficie: Double?; var frente: Double?; var fondo: Double?; var precio: Double?; var moneda: String }
                            struct R: Decodable { var creados: Int?; var salteados: Int? }
                            do {
                                let r: R = try await estado.api.enviar("POST", "/v1/emprendimientos/\(emprendimiento)/lotes",
                                                                       C(manzana: manzana, desde: desde, hasta: hasta, superficie: superficie, frente: frente, fondo: fondo, precio: precio, moneda: moneda))
                                estado.avisar("Creamos \(Formato.cantidad(r.creados ?? 0, "lote", "lotes"))\((r.salteados ?? 0) > 0 ? " · \(r.salteados!) ya estaban" : "")")
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
        }
    }
}

/// El masterplan: el plano con cada lote marcado en el color de su estado. Tocando el plano se ubica el
/// lote elegido (como en el editor de la web).
struct MasterplanVista: View {
    @Environment(Estado.self) private var estado
    var emprendimiento: String
    var imagen: String?
    var unidades: [Propiedad]
    @State private var marcas: [(String, Double, Double)] = []
    @State private var ubicando: String?
    @State private var plano: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TituloBloque(texto: "Masterplan")
                if estado.escribe {
                    PhotosPicker(selection: $plano, matching: .images) { Text(imagen == nil ? "Subir el plano" : "Cambiar el plano").font(Estilo.footnoteFuerte.font) }
                }
            }
            if let imagen, let u = URL(string: imagen) {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { C.hundida }
                        ForEach(marcas, id: \.0) { m in
                            let p = unidades.first { $0.id == m.0 }
                            Circle().fill(Self.color(p?.estado)).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                                .position(x: g.size.width * m.1 / 100, y: g.size.height * m.2 / 100)
                                .onTapGesture { estado.abrir(AFichaPropiedad(id: m.0)) }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { punto in
                        guard let id = ubicando else { return }
                        marcas.removeAll { $0.0 == id }
                        marcas.append((id, Double(punto.x / g.size.width * 100), Double(punto.y / g.size.height * 100)))
                        ubicando = nil
                        Task { await guardar() }
                    }
                }
                .aspectRatio(1.4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                if estado.escribe {
                    Picker("Ubicar un lote", selection: Binding(get: { ubicando ?? "" }, set: { ubicando = $0.nonEmpty })) {
                        Text("Elegí un lote para ubicarlo").tag("")
                        ForEach(unidades) { Text($0.nombre).tag($0.id) }
                    }
                    if ubicando != nil { Text("Tocá el plano donde está el lote.").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                }
            }
        }
        .task {
            struct E: Decodable { struct M: Decodable { struct Marca: Decodable { var propiedadId: String; var x: Double; var y: Double }; var lotes: [Marca]? }; var masterplan: M? }
            if let e: E = try? await estado.api.get("/v1/emprendimientos/\(emprendimiento)") { marcas = (e.masterplan?.lotes ?? []).map { ($0.propiedadId, $0.x, $0.y) } }
        }
        .onChange(of: plano) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self), let a = try? await estado.api.subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "plano.jpg", tipo: "image/jpeg", uso: "foto") {
                    await guardar(imagen: a.id)
                    estado.version += 1
                }
                plano = nil
            }
        }
    }

    static func color(_ e: String?) -> Color {
        switch e {
        case "vendida": return C.error
        case "reservada": return C.oro
        case "pausada": return C.texto3
        default: return Color(hex: 0x2F9E6F)
        }
    }

    private func guardar(imagen nueva: String? = nil) async {
        struct Marca: Encodable { var propiedadId: String; var x: Double; var y: Double }
        struct C: Encodable { var imagen: String?; var lotes: [Marca] }
        do {
            try await estado.api.hacer("PUT", "/v1/emprendimientos/\(emprendimiento)/masterplan", C(imagen: nueva, lotes: marcas.map { Marca(propiedadId: $0.0, x: $0.1, y: $0.2) }))
        } catch { estado.avisar(error) }
    }
}
