import SwiftUI

// Lo que hace el editor de la web (web: lib/web/editor.ts, lib/sitio/armado.ts): las reglas para
// sumar, duplicar y quitar secciones y páginas, y medir si el título se lee sobre el velo.

enum EditorWeb {
    static let maxSecciones = 16
    static let maxPaginasPropias = 6
    static let tiposSeccion = ["portada", "destacadas", "barrios", "emprendimiento", "temporada", "texto", "testimonios", "equipo", "tasacion", "contacto"]
    static let paginasFijas = ["inicio", "propiedades", "temporada", "emprendimientos", "tasaciones", "nosotros"]
    static let rutasTomadas = ["propiedades", "lotes", "locales", "temporarios", "emprendimientos", "barrios", "tasaciones", "nosotros", "contacto",
                               "favoritos", "alertas", "privacidad", "terminos", "expensas", "sueldos", "recibo", "og", "robots.txt", "sitemap.xml",
                               "p", "api", "panel", "guardadas"]

    /// «Cómo trabajamos» → «como-trabajamos».
    static func rutaDe(_ titulo: String) -> String {
        titulo.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .replacingOccurrences(of: "ñ", with: "n")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// Las secciones que se pueden sumar: el texto, siempre; las demás, si no están ya (hasta 16).
    static func tiposParaSumar(_ inicio: [JSONLibre]) -> [String] {
        guard inicio.count < maxSecciones else { return [] }
        return tiposSeccion.filter { t in t != "portada" && (t == "texto" || !inicio.contains { $0["tipo"]?.texto == t }) }
    }

    static func idNuevo(_ inicio: [JSONLibre], _ tipo: String) -> String {
        guard tipo == "texto" else { return tipo }
        var n = 1
        while inicio.contains(where: { $0["id"]?.texto == "texto-\(n)" }) { n += 1 }
        return "texto-\(n)"
    }

    /// Por qué no sirve el nombre de una página nueva, o nil si sirve.
    static func problemaPagina(_ paginas: [JSONLibre], _ titulo: String) -> String? {
        let t = titulo.trimmingCharacters(in: .whitespaces)
        if t.count < 2 { return "Escribí el nombre de la página." }
        if t.count > 40 { return "Hasta 40 letras." }
        let ruta = rutaDe(t)
        if ruta.isEmpty { return "Usá letras o números." }
        if rutasTomadas.contains(ruta) || paginasFijas.contains(ruta) { return "Ese nombre ya lo usa una página de tu web." }
        if paginas.contains(where: { $0["ruta"]?.texto == ruta }) { return "Ya tenés una página con ese nombre." }
        if paginas.filter({ ($0["id"]?.texto ?? "").hasPrefix("p-") }).count >= maxPaginasPropias { return "Hasta \(maxPaginasPropias) páginas propias." }
        return nil
    }

    /// El color «noche» de la marca (el velo de la portada): el primario oscurecido.
    static func noche(_ primario: String?) -> UInt32 {
        let p = Acento.rgb(primario).map(Acento.hex) ?? 0x16443B
        return Acento.mezclar(p, 0x000000, 0.4)
    }

    /// ¿El título blanco se lee sobre la foto con ese velo? (peor caso: una foto blanca).
    static func seLeeConVelo(_ noche: UInt32, _ velo: Double) -> Bool {
        Acento.contraste(Acento.mezclar(0xFFFFFF, noche, max(0, min(90, velo)) / 100), 0xFFFFFF) >= 4.5
    }

    /// El velo mínimo para que el título llegue a AA (o 90 si ni así).
    static func veloMinimo(_ noche: UInt32) -> Int {
        for v in stride(from: 0, through: 90, by: 5) where seLeeConVelo(noche, Double(v)) { return v }
        return 90
    }

    /// Las plantillas (web: lib/web/marca.ts PLANTILLAS) con su grupo.
    static let plantillas: [(id: String, nombre: String, texto: String, grupo: String)] = [
        ("barrio", "Barrio", "Buscador sobre foto, destacadas, barrios.", "ciudad"),
        ("costa", "Costa", "Calendario de disponibilidad y tarifas al frente.", "costa"),
        ("clasica", "Clásica", "Sobria, listado primero. Para carteras grandes.", "ciudad"),
        ("emprendimiento", "Emprendimiento", "Una web por proyecto, con masterplan.", "emprendimientos"),
    ]

    /// Los colores sugeridos (40E).
    static let colores: [String] = ["#1e3a5f", "#7c2d12", "#1f5a2a", "#4a2c5a"]
}

/// Una versión publicada de la web (GET /v1/web/versiones).
struct VersionWeb: Codable, Identifiable {
    var id: String
    var creadaEn: String?
    var autor: String?
    var desdeId: String?
    var plantilla: String?
}

/// «Versiones publicadas»: cada vez que publicás queda una. Volver a una la publica de nuevo (y se
/// descarta el borrador).
struct HojaVersionesWeb: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var alVolver: () -> Void
    @State private var lista: [VersionWeb]?
    @State private var error: ErrorApi?
    @State private var volviendo: String?

    var body: some View {
        NavigationStack {
            List {
                Section { Text("Cada vez que publicás queda una. Volver a una la publica de nuevo.").estilo(.footnote).foregroundStyle(C.texto2) }
                if let lista {
                    if lista.isEmpty { Text("Todavía no publicaste la web.").foregroundStyle(C.texto2) }
                    ForEach(Array(lista.enumerated()), id: \.element.id) { i, v in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i == 0 ? "La de ahora" : (v.creadaEn.flatMap(Fecha.iso).map { Formato.cuando($0) } ?? "")).estilo(.filaLista)
                                Text([i == 0 ? v.creadaEn.flatMap(Fecha.iso).map { Formato.cuando($0) } : nil, v.autor,
                                      v.plantilla.map { p in "plantilla \(EditorWeb.plantillas.first { $0.id == p }?.nombre ?? p)" }]
                                    .compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            if i > 0, estado.esDuenio {
                                Button(volviendo == v.id ? "Volviendo…" : "Volver a esta") { Task { await volver(v) } }
                                    .buttonStyle(BotonTonal(alto: 32)).disabled(volviendo != nil)
                            }
                        }
                    }
                } else if let error {
                    EstadoError(que: "las versiones", error: error) { Task { await cargar() } }
                } else { ProgressView() }
            }
            .navigationTitle("Versiones publicadas").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .task { await cargar() }
        }
    }

    private func cargar() async {
        do { lista = try await estado.api.get("/v1/web/versiones"); error = nil } catch let e as ErrorApi { error = e } catch {}
    }

    private func volver(_ v: VersionWeb) async {
        volviendo = v.id
        defer { volviendo = nil }
        do {
            try await estado.api.hacer("POST", "/v1/web/versiones/\(v.id)/restaurar")
            do { try await BorradorWeb.descartar(estado.api) } catch let e as ErrorApi where e.estado == 404 {} catch { estado.avisar(error) }
            await estado.cargarEstructura()
            estado.avisar("Volviste a la versión del \(v.creadaEn.flatMap(Fecha.iso).map { Formato.cuando($0) } ?? "")")
            alVolver()
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// Una página propia de la web: el título, el texto (con «Reescribir con IA») y la vista previa.
struct EditorPaginaWeb: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var pagina: JSONLibre
    var web: String?
    var guardar: (String, String) -> Void
    @State private var titulo = ""
    @State private var texto = ""
    @State private var reescribiendo = false

    private var ruta: String { pagina["ruta"]?.texto ?? EditorWeb.rutaDe(titulo) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") { TextField("Servicios", text: $titulo) }
                Section("Texto") {
                    TextField("Lo que querés contar en esta página", text: $texto, axis: .vertical).lineLimit(5...16)
                    Button { Task { await reescribir() } } label: {
                        Label(reescribiendo ? "Reescribiendo…" : "Reescribir con IA", systemImage: "sparkles").foregroundStyle(C.avisoTinta)
                    }
                    .disabled(texto.isEmpty || reescribiendo)
                }
                if let w = web, let u = URL(string: "\(w)/\(ruta)") {
                    Section { Link(destination: u) { Label("Vista previa · \(u.absoluteString.replacingOccurrences(of: "https://", with: ""))", systemImage: "safari") } }
                }
            }
            .navigationTitle(titulo.nonEmpty ?? "Página").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { guardar(titulo, texto); cerrar() }.disabled(titulo.trimmingCharacters(in: .whitespaces).count < 2) }
            }
            .onAppear { titulo = pagina["titulo"]?.texto ?? ""; texto = pagina["texto"]?.texto ?? "" }
        }
    }

    private func reescribir() async {
        reescribiendo = true
        defer { reescribiendo = false }
        struct C: Encodable { var campo = "texto"; var texto: String }
        struct R: Decodable { var texto: String }
        let antes = texto
        do {
            let r: R = try await estado.api.enviar("POST", "/v1/web/reescribir", C(texto: texto))
            texto = r.texto
            estado.avisar("Reescrito") { texto = antes }
        } catch { estado.avisar(error) }
    }
}

/// «Nueva página»: el nombre (2 a 40 letras, que no use una ruta tomada) y dónde va a estar.
struct NuevaPaginaWeb: View {
    @Environment(\.dismiss) private var cerrar
    var paginas: [JSONLibre]
    var web: String?
    var crear: (String) -> Void
    @State private var titulo = ""

    var body: some View {
        let problema = titulo.isEmpty ? nil : EditorWeb.problemaPagina(paginas, titulo)
        NavigationStack {
            Form {
                Section {
                    TextField("Servicios", text: $titulo)
                    if let problema { MensajeError(texto: problema) }
                    else if let w = web, !titulo.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Va a estar en \(w.replacingOccurrences(of: "https://", with: ""))/\(EditorWeb.rutaDe(titulo))").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                } header: { Text("Nombre de la página") } footer: {
                    Text("Una página tuya con un título y un texto: servicios, cómo trabajamos, preguntas.")
                }
            }
            .navigationTitle("Nueva página").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear página") { crear(titulo.trimmingCharacters(in: .whitespaces)); cerrar() }.disabled(titulo.isEmpty || problema != nil)
                }
            }
        }
    }
}

/// La foto de portada sacada de una propiedad publicada.
struct ElegirFotoPortada: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var elegir: (String) -> Void
    @State private var props: [Propiedad]?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let props {
                    if props.filter({ !($0.fotosUrl ?? []).isEmpty }).isEmpty {
                        EstadoVacio(icono: "photo", titulo: "Ninguna publicada tiene fotos", accion: ("Volver", { cerrar() })).padding(.top, 40)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(props.filter { !($0.fotosUrl ?? []).isEmpty }) { p in
                            Button { if let u = p.fotosUrl?.first { elegir(u); cerrar() } } label: {
                                Foto(url: p.miniatura).frame(height: 120).clipShape(.rect(cornerRadius: 12))
                                    .overlay(alignment: .bottomLeading) {
                                        Text(p.direccion ?? p.nombre).font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(.white)
                                            .lineLimit(1).padding(6).background(.black.opacity(0.45), in: Capsule()).padding(6)
                                    }
                            }
                            .buttonStyle(Presionable())
                        }
                    }
                    .padding(16)
                } else { ProgressView().padding(.top, 60) }
            }
            .navigationTitle("Foto de una propiedad").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .task { props = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "publicada", value: "si"), .init(name: "limite", value: "24")])) ?? [] }
        }
    }
}

/// Plantillas: el filtro por tipo y aplicar una a la web publicada (tu contenido queda como estaba),
/// con deshacer.
struct HojaPlantillas: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var alCambiar: () -> Void
    @State private var grupo = "todas"
    @State private var enUso = "barrio"
    @State private var marca: JSONLibre?
    @State private var aplicando: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Se ven con tus propiedades y tu logo, no con fotos de muestra.").estilo(.subhead).foregroundStyle(C.texto2)
                    Segmentado(opciones: [("todas", "Todas"), ("ciudad", "Ciudad"), ("costa", "Costa"), ("emprendimientos", "Emprendimientos")], elegido: $grupo)
                    ForEach(EditorWeb.plantillas.filter { grupo == "todas" || $0.grupo == grupo }, id: \.id) { p in
                        Button { Task { await usar(p.id) } } label: {
                            HStack(spacing: 12) {
                                IconoTono(icono: p.id == "costa" ? "beach.umbrella" : p.id == "emprendimiento" ? "building.2" : p.id == "clasica" ? "list.bullet.rectangle" : "magnifyingglass", tono: p.id == enUso ? .verde : .neutro)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(p.texto).estilo(.footnote).foregroundStyle(C.texto2)
                                }
                                Spacer()
                                if aplicando == p.id { ProgressView() } else if p.id == enUso { Text("En uso").estilo(.footnoteFuerte).foregroundStyle(C.okTinta) }
                            }
                            .padding(14).tarjeta()
                        }
                        .buttonStyle(Presionable()).disabled(!estado.esDuenio || aplicando != nil)
                    }
                    if !estado.esDuenio { Text("La web la cambia el dueño o la dueña. Vos la podés ver como queda.").estilo(.footnote).foregroundStyle(C.texto2) }
                }
                .padding(16)
            }
            .navigationTitle("Elegí cómo arranca tu web").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .task { await cargar() }
        }
    }

    private func cargar() async {
        if let i: Inmobiliaria = try? await estado.api.get("/v1/inmobiliaria") {
            marca = i.marca
            enUso = i.marca?["plantilla"]?.texto ?? "barrio"
        }
    }

    private func poner(_ id: String) async throws {
        struct C: Encodable { var marca: JSONLibre }
        var o: [String: JSONLibre] = [:]
        if case .objeto(let x)? = marca { o = x }
        o["plantilla"] = .texto(id)
        try await estado.api.hacer("PATCH", "/v1/inmobiliaria", C(marca: .objeto(o)))
        marca = .objeto(o)
        enUso = id
        alCambiar()
    }

    private func usar(_ id: String) async {
        guard estado.esDuenio, id != enUso else { return }
        let antes = enUso
        aplicando = id
        defer { aplicando = nil }
        do {
            try await poner(id)
            estado.avisar("Plantilla \(EditorWeb.plantillas.first { $0.id == id }?.nombre ?? id): tu contenido queda como estaba") {
                Task { do { try await poner(antes) } catch { estado.avisar(error) } }
            }
        } catch { estado.avisar(error) }
    }
}

/// El QR de la web, para la vidriera o las tarjetas.
struct HojaQRWeb: View {
    var web: String
    var nombre: String
    var body: some View {
        VStack(spacing: 16) {
            Grabber()
            Text("El QR de tu web").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            if let q = FichaImpresa.qr(web) {
                Image(uiImage: q).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220)
                    .padding(14).background(.white, in: .rect(cornerRadius: 16))
                ShareLink(item: Image(uiImage: q), preview: SharePreview("QR de \(nombre)", image: Image(uiImage: q))) {
                    Label("Compartir el QR", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BotonPrincipal())
            }
            Text("Para la vidriera o las tarjetas: abre \(web.replacingOccurrences(of: "https://", with: "")).").estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }
}
