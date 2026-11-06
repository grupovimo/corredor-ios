import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import VisionKit

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
    /// El archivo del plano como lo guarda la API: el PUT reemplaza el masterplan entero, así que
    /// va siempre (si no, mover una marca borraba el plano).
    @State private var imagenId: String?
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
            struct E: Decodable { struct M: Decodable { struct Marca: Decodable { var propiedadId: String; var x: Double; var y: Double }; var imagen: String?; var lotes: [Marca]? }; var masterplan: M? }
            if let e: E = try? await estado.api.get("/v1/emprendimientos/\(emprendimiento)") {
                marcas = (e.masterplan?.lotes ?? []).map { ($0.propiedadId, $0.x, $0.y) }
                imagenId = e.masterplan?.imagen
            }
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
            try await estado.api.hacer("PUT", "/v1/emprendimientos/\(emprendimiento)/masterplan", C(imagen: nueva ?? imagenId, lotes: marcas.map { Marca(propiedadId: $0.0, x: $0.1, y: $0.2) }))
            if let nueva { imagenId = nueva }
        } catch { estado.avisar(error) }
    }
}

struct EmprendimientoAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var masterplanUrl: String?
    var tipo: String?
    var estado: String?
    var descripcion: String?
    var direccion: String?
    var barrio: String?
    var avance: Double?
    var entrega: String?
    var desarrolladora: String?
    var precioDesde: Double?
    var moneda: String?
    var fotosUrl: [String]?
    var unidades: [Propiedad]?
}

/// Emprendimientos: la lista y, en cada uno, el avance, la entrega y sus unidades (con su estado).
struct Emprendimientos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [EmprendimientoAPI]?
    @State private var nuevo = false
    @State private var nombre = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty { EstadoVacio(icono: "building", titulo: "Todavía no hay emprendimientos", accion: estado.escribe ? ("Cargar emprendimiento", { nuevo = true }) : nil).padding(.top, 40) }
                    ForEach(lista) { e in
                        NavigationLink(value: ASeccion(clave: "emprendimiento", id: e.id)) {
                            HStack(spacing: 12) {
                                Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                    Text([e.barrio, e.precioDesde.map { "desde \(Formato.plata($0, e.moneda ?? "USD"))" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                                    if let a = e.avance { ProgressView(value: a / 100).tint(C.oro).padding(.top, 4) }
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(10).tarjeta()
                        }
                        .buttonStyle(Presionable())
                    }
                } else { EsqueletoFilas(filas: 3, miniatura: 72) }
            }
            .padding(16)
        }
        .pantallaApilada("Emprendimientos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo emprendimiento") } }
        .task(id: estado.version) { lista = (try? await estado.api.get("/v1/emprendimientos")) ?? lista ?? [] }
        .alert("Emprendimiento nuevo", isPresented: $nuevo) {
            TextField("Nombre", text: $nombre)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") {
                Task {
                    // La API acepta preventa, en_obra o terminado (emprendimientos.Estados).
                    struct C: Encodable { var nombre: String; var tipo = "edificio"; var estado = "preventa" }
                    do {
                        try await estado.api.hacer("POST", "/v1/emprendimientos", C(nombre: nombre))
                        nombre = ""
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        }
    }
}

/// Un emprendimiento: avance, entrega, desarrolladora y las unidades (cada una abre su ficha).
struct FichaEmprendimiento: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var e: EmprendimientoAPI?
    @State private var unidades: [Propiedad] = []
    @State private var lotes = false

    var body: some View {
        ScrollView {
            if let e {
                VStack(alignment: .leading, spacing: 16) {
                    Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(height: 200).clipShape(.rect(cornerRadius: M.rDestacada))
                    Text(e.nombre).estilo(.titulo).foregroundStyle(C.texto)
                    Text([e.direccion, e.barrio, e.desarrolladora].compactMap { $0 }.joined(separator: " · ")).estilo(.subhead).foregroundStyle(C.texto2)
                    if let a = e.avance {
                        TarjetaAvance(titulo: "Avance de obra", cifra: "\(Int(a)) %", avance: a / 100, degrade: [Color(hex: 0xE9AD44), Color(hex: 0xF2BB57)],
                                      pie: e.entrega.map { "Entrega: \($0)" } ?? "Sin fecha de entrega")
                    }
                    if let d = e.descripcion { Text(d).estilo(.body16).foregroundStyle(C.texto) }
                    MasterplanVista(emprendimiento: id, imagen: e.masterplanUrl, unidades: unidades)
                    TituloBloque(texto: "Unidades", cuenta: "\(unidades.count)")
                    if estado.escribe { Button("Crear lotes en serie") { lotes = true }.buttonStyle(BotonHundido()) }
                    VStack(spacing: 0) {
                        ForEach(Array(unidades.enumerated()), id: \.element.id) { i, p in
                            Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto); Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2) }
                                    Spacer()
                                    let (chip, tono) = PropiedadesRaiz.chip(p, nil)
                                    Text(chip).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                                        .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                }
                .padding(16)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada(e?.nombre ?? "Emprendimiento")
        .sheet(isPresented: $lotes) { NuevosLotes(emprendimiento: id) }
        .task(id: estado.version) {
            e = try? await estado.api.get("/v1/emprendimientos/\(id)")
            unidades = (try? await estado.api.get("/v1/emprendimientos/\(id)/unidades")) ?? e?.unidades ?? []
        }
    }
}
