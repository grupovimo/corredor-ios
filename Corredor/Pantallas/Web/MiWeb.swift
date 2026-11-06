import AuthenticationServices
import SwiftUI

// MARK: - Mi web

/// Mi web: arriba la web real con los cambios (tocás una parte y se abre su editor), el logo y la
/// portada, el link para compartir, la plantilla, los colores, la frase, nosotros, contacto y los
/// textos de cada barrio. Todo se guarda solo en el borrador (el mismo que el panel web) y sale a la
/// web con «Publicar»; los barrios y el dominio, al instante (no son de la marca).
struct MiWeb: View {
    @Environment(Estado.self) private var estado
    @State private var web: String?
    @State private var marca: [String: String] = [:]
    /// La marca entera como la guarda la API (logo, `web` del editor…): PATCH la reemplaza toda, así
    /// que se manda completa con los textos cambiados encima.
    @State private var completa: [String: JSONLibre] = [:]
    @State private var barrios: [BarrioWeb] = []
    @State private var guardado: Task<Void, Never>?
    @State private var guardadas: JSONLibre?
    @State private var dominio: JSONLibre?
    @State private var dominioNuevo = ""
    @State private var reescribiendo: String?
    @State private var paginaNueva = false
    @State private var tituloPagina = ""
    @State private var editandoSeccion: Int?
    /// El borrador: el `en` del último guardado (para no pisar lo de otro), si hay cambios sin publicar,
    /// la vista previa y lo que se tocó en ella.
    @State private var en: String?
    @State private var hayBorrador = false
    @State private var previa: URL?
    @State private var recarga = 0
    @State private var zona: ZonaWeb?
    @State private var publicando = false

    /// Una parte de la web tocada en la vista previa.
    struct ZonaWeb: Identifiable { var clave: String; var id: String { clave } }

    struct BarrioWeb: Codable, Identifiable { var nombre: String; var cantidad: Int?; var texto: String?; var id: String { nombre } }

    private static let plantillas = [("barrio", "Barrio", "Buscador sobre foto, destacadas, barrios."), ("costa", "Costa", "Calendario y tarifas al frente."),
                                     ("clasica", "Clásica", "Sobria, listado primero."), ("emprendimiento", "Emprendimiento", "Una web por proyecto.")]

    var body: some View {
        Form {
            Section {
                MarcoPrevia(url: previa, recarga: recarga) { tocar($0) }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                    .listRowBackground(Color.clear)
            }
            Section(header: Text("Logo y portada"), footer: Text("El logo va en tu web, en los recibos y en la app.")) {
                SubirImagenMarca(titulo: "Subí tu logo", url: marca["logoUrl"]) { u, _ in marca["logoUrl"] = u; programar(ya: true) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                SubirImagenMarca(titulo: "Subí la foto de portada", url: marca["portadaUrl"], ancha: true) { u, _ in marca["portadaUrl"] = u; programar(ya: true) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if let w = web, let u = URL(string: w) {
                Section {
                    Link(destination: u) { Label(w.replacingOccurrences(of: "https://", with: ""), systemImage: "globe") }
                    ShareLink(item: u) { Label("Compartir tu web", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.url = u; estado.avisar("Link copiado") } label: { Label("Copiar el link", systemImage: "doc.on.doc") }
                }
            }
            Section("Plantilla") {
                Picker("Plantilla", selection: campo("plantilla", "barrio")) {
                    ForEach(Self.plantillas, id: \.0) { k, n, d in VStack(alignment: .leading) { Text(n); Text(d).font(.footnote).foregroundStyle(.secondary) }.tag(k) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section(header: Text("Página de inicio"), footer: Text("Arrastrá para ordenar. Lo apagado no se ve en tu web.")) {
                ForEach(Array(secciones.enumerated()), id: \.offset) { i, x in
                    Toggle(Self.nombreSeccion(x["tipo"]?.texto), isOn: Binding(get: { x["oculta"].map { if case .bool(true) = $0 { return false }; return true } ?? true },
                                                                         set: { on in ocultar(i, !on) }))
                        .disabled(x["tipo"]?.texto == "portada")
                }
                .onMove { desde, hacia in mover(desde, hacia) }
                Picker("Portada", selection: Binding(get: { completa["web"]?["portada"]?["variante"]?.texto ?? "foto" }, set: { variante($0) })) {
                    Text("Foto de fondo").tag("foto"); Text("Foto arriba").tag("arriba"); Text("Partida").tag("partida")
                }
            }
            Section(header: Text("Sumar a la página de inicio")) {
                Menu {
                    ForEach(["texto", "testimonios", "equipo", "tasacion", "contacto", "temporada", "emprendimiento"], id: \.self) { t in
                        Button(Self.nombreSeccion(t)) { sumarSeccion(t) }
                    }
                } label: { Label("Sumar sección", systemImage: "plus.rectangle.on.rectangle") }
                ForEach(Array(secciones.enumerated()).filter { ["texto", "testimonios"].contains($0.element["tipo"]?.texto ?? "") }, id: \.offset) { i, x in
                    Button { editandoSeccion = i } label: {
                        LabeledContent(Self.nombreSeccion(x["tipo"]?.texto), value: x["titulo"]?.texto ?? "Editar")
                    }
                }
            }
            Section(header: Text("Páginas"), footer: Text("Las propias viven en tu web con su link. Lo apagado no sale en el menú.")) {
                ForEach(Array(paginas.enumerated()), id: \.offset) { i, x in
                    let id = x["id"]?.texto ?? ""
                    Toggle(Self.nombrePagina(x), isOn: Binding(get: { x["oculta"].map { if case .bool(true) = $0 { return false }; return true } ?? true },
                                                               set: { on in ocultarPagina(i, !on) }))
                        .disabled(id == "inicio" || id == "propiedades")
                        .swipeActions { if id.hasPrefix("p-") { Button("Quitar", role: .destructive) { quitarPagina(i) } } }
                }
                Button { paginaNueva = true } label: { Label("Nueva página", systemImage: "plus") }
            }
            if let g = guardadas {
                Section("Guardadas esta semana") {
                    LabeledContent("Corazones", value: Informe.num(g["favoritos"]))
                    LabeledContent("Búsquedas con alerta", value: Informe.num(g["busquedas"]))
                    if let m = g["masGuardada"], let t = m["titulo"]?.texto {
                        Button { if let id = m["id"]?.texto { estado.abrir(AFichaPropiedad(id: id)) } } label: { LabeledContent("La más guardada", value: t) }
                    }
                }
            }
            Section(header: Text("Dominio propio"), footer: Text("Apuntá un registro A a 187.41.102.190 (o un CNAME de www). Se conecta solo, con certificado.")) {
                if let d = dominio?["dominio"]?.texto {
                    LabeledContent(d, value: dominio?["verificado"].map { if case .bool(true) = $0 { return "Conectado" }; return "Verificando" } ?? "Verificando")
                    Button("Verificar ahora") { Task { do { try await estado.api.hacer("POST", "/v1/inmobiliaria/dominio/verificar"); await cargarDominio() } catch { estado.avisar(error) } } }
                    Button("Quitar el dominio", role: .destructive) { Task { await ponerDominio("") } }
                } else {
                    TextField("tuinmobiliaria.com.ar", text: $dominioNuevo).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Conectar") { Task { await ponerDominio(dominioNuevo) } }.disabled(!dominioNuevo.contains("."))
                }
            }
            Section("Marca") {
                ColorPicker("Color principal", selection: color("colorPrimario", 0x16443B), supportsOpacity: false)
                ColorPicker("Color de acento", selection: color("colorSecundario", 0xF2BB57), supportsOpacity: false)
                TextField("Frase de la portada", text: campo("frase", ""))
                botonIA("frase")
            }
            Section("Nosotros") {
                TextField("Título", text: campo("nosotrosTitulo", ""))
                TextField("Quiénes son, desde cuándo, en qué barrios trabajan.", text: campo("nosotros", ""), axis: .vertical).lineLimit(3...8)
                botonIA("nosotros")
            }
            Section("Contacto") {
                TextField("WhatsApp", text: campo("whatsapp", "")).keyboardType(.phonePad)
                TextField("Teléfono", text: campo("telefono", "")).keyboardType(.phonePad)
                TextField("Mail", text: campo("email", "")).keyboardType(.emailAddress)
                TextField("Dirección", text: campo("direccion", ""))
                TextField("Horario", text: campo("horario", ""))
            }
            if !barrios.isEmpty {
                Section(header: Text("Barrios"), footer: Text("Lo que contás de cada uno sale en su página de tu web.")) {
                    ForEach($barrios) { $b in
                        VStack(alignment: .leading) {
                            Text(b.nombre).estilo(.filaLista)
                            TextField("Cómo es vivir en \(b.nombre)", text: Binding(get: { b.texto ?? "" }, set: { b.texto = $0 }), axis: .vertical)
                                .onSubmit { Task { await guardarBarrio(b) } }
                        }
                    }
                }
            }
        }
        .disabled(!estado.esDuenio)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Mi web")
        .safeAreaInset(edge: .bottom) { if estado.esDuenio { barraPublicar } }
        .sheet(item: $zona) { z in
            EditorZonaWeb(zona: z.clave, marca: $marca) { programar(ya: true) }
                .presentationDetents([.medium, .large])
        }
        // Lo cambiado desde la computadora (o el alta) se trae, si acá no hay nada esperando guardarse.
        .task(id: estado.version) { if guardado == nil, !publicando { await traerBorrador() } }
        .task {
            struct I: Decodable { var web: String? }
            if let i: I = try? await estado.api.get("/v1/inmobiliaria") { web = i.web }
            await traerBorrador()
            if estado.esDuenio { previa = try? await BorradorWeb.urlPrevia(estado.api, slug: estado.inmobiliaria?.slug ?? "") }
            barrios = (try? await estado.api.get("/v1/web/barrios")) ?? []
            guardadas = try? await estado.api.get("/v1/web/guardadas", query: [.init(name: "dias", value: "7")])
            await cargarDominio()
        }
        .alert("Página nueva", isPresented: $paginaNueva) {
            TextField("Servicios, Tasaciones…", text: $tituloPagina)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") { sumarPagina(tituloPagina); tituloPagina = "" }
        }
        .sheet(item: Binding(get: { editandoSeccion.map { CampoAlta(id: String($0)) } }, set: { editandoSeccion = $0.flatMap { Int($0.id) } })) { x in
            EditorSeccionWeb(seccion: secciones[Int(x.id) ?? 0]) { nueva in
                var l = secciones
                l[Int(x.id) ?? 0] = nueva
                conWeb { $0["inicio"] = .lista(l) }
            }
        }
    }

    private var secciones: [JSONLibre] {
        if case .lista(let l)? = completa["web"]?["inicio"] { return l }
        return [.objeto(["id": .texto("portada"), "tipo": .texto("portada")]), .objeto(["id": .texto("destacadas"), "tipo": .texto("destacadas")]),
                .objeto(["id": .texto("barrios"), "tipo": .texto("barrios")])]
    }

    static func nombreSeccion(_ t: String?) -> String {
        ["portada": "Portada con buscador", "destacadas": "Destacadas", "barrios": "Barrios", "emprendimiento": "Emprendimiento", "temporada": "Temporada",
         "texto": "Texto", "testimonios": "Testimonios", "equipo": "Equipo", "tasacion": "Tasá tu propiedad", "contacto": "Contacto"][t ?? ""] ?? (t ?? "Sección")
    }

    private func conWeb(_ f: (inout [String: JSONLibre]) -> Void) {
        var w: [String: JSONLibre] = [:]
        if case .objeto(let o)? = completa["web"] { w = o }
        f(&w)
        completa["web"] = .objeto(w)
        programar()
    }

    private func ocultar(_ i: Int, _ oculta: Bool) {
        var l = secciones
        guard case .objeto(var o) = l[i] else { return }
        o["oculta"] = oculta ? .bool(true) : nil
        l[i] = .objeto(o)
        conWeb { $0["inicio"] = .lista(l) }
    }

    private func mover(_ desde: IndexSet, _ hacia: Int) {
        var l = secciones
        l.move(fromOffsets: desde, toOffset: hacia)
        // La portada siempre primera.
        if let i = l.firstIndex(where: { $0["tipo"]?.texto == "portada" }), i != 0 { l.insert(l.remove(at: i), at: 0) }
        Haptico.impacto()
        conWeb { $0["inicio"] = .lista(l) }
    }

    private func variante(_ v: String) {
        conWeb { w in
            var p: [String: JSONLibre] = [:]
            if case .objeto(let o)? = w["portada"] { p = o }
            p["variante"] = .texto(v)
            w["portada"] = .objeto(p)
        }
    }

    private var paginas: [JSONLibre] {
        if case .lista(let l)? = completa["web"]?["paginas"] { return l }
        return ["inicio", "propiedades", "temporada", "emprendimientos", "tasaciones", "nosotros"].map { .objeto(["id": .texto($0)]) }
    }

    static func nombrePagina(_ x: JSONLibre) -> String {
        if let t = x["titulo"]?.texto { return t }
        return ["inicio": "Inicio", "propiedades": "Comprar · Alquilar", "temporada": "Temporada", "emprendimientos": "Emprendimientos",
                "tasaciones": "Tasá tu propiedad", "nosotros": "Nosotros"][x["id"]?.texto ?? ""] ?? "Página"
    }

    private func ocultarPagina(_ i: Int, _ oculta: Bool) {
        var l = paginas
        guard case .objeto(var o) = l[i] else { return }
        o["oculta"] = oculta ? .bool(true) : nil
        l[i] = .objeto(o)
        conWeb { $0["paginas"] = .lista(l) }
    }

    private func quitarPagina(_ i: Int) {
        var l = paginas
        let antes = l
        l.remove(at: i)
        conWeb { $0["paginas"] = .lista(l) }
        estado.avisar("Página quitada") { conWeb { $0["paginas"] = .lista(antes) } }
    }

    private func sumarPagina(_ titulo: String) {
        let ruta = titulo.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "ñ", with: "n").components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        guard !ruta.isEmpty else { return }
        var l = paginas
        l.append(.objeto(["id": .texto("p-\(ruta)"), "titulo": .texto(titulo), "ruta": .texto(ruta), "texto": .texto("")]))
        conWeb { $0["paginas"] = .lista(l) }
    }

    private func sumarSeccion(_ tipo: String) {
        var l = secciones
        var o: [String: JSONLibre] = ["id": .texto(tipo == "texto" ? "texto-\(Int(Date().timeIntervalSince1970))" : tipo), "tipo": .texto(tipo)]
        if tipo == "texto" { o["titulo"] = .texto("Un título"); o["texto"] = .texto("") }
        if tipo != "texto", l.contains(where: { $0["tipo"]?.texto == tipo }) { return estado.avisar("Esa sección ya está.", ok: false) }
        l.append(.objeto(o))
        conWeb { $0["inicio"] = .lista(l) }
        estado.avisar("Sumaste «\(Self.nombreSeccion(tipo))»")
    }

    @ViewBuilder
    private func botonIA(_ k: String) -> some View {
        Button {
            Task {
                reescribiendo = k
                defer { reescribiendo = nil }
                struct C: Encodable { var campo: String; var texto: String }
                struct R: Decodable { var texto: String }
                do {
                    let antes = marca[k] ?? ""
                    let r: R = try await estado.api.enviar("POST", "/v1/web/reescribir", C(campo: k, texto: antes))
                    marca[k] = r.texto
                    programar()
                    estado.avisar("Reescrito") { marca[k] = antes; programar() }
                } catch { estado.avisar(error) }
            }
        } label: {
            Label(reescribiendo == k ? "Reescribiendo…" : "Reescribir con IA", systemImage: "sparkles").foregroundStyle(C.avisoTinta)
        }
        .disabled(reescribiendo != nil || (marca[k] ?? "").isEmpty)
    }

    private func cargarDominio() async { dominio = try? await estado.api.get("/v1/inmobiliaria/dominio") }

    private func ponerDominio(_ d: String) async {
        struct C: Encodable { var dominio: String }
        do {
            try await estado.api.hacer("PATCH", "/v1/inmobiliaria", C(dominio: d.trimmingCharacters(in: .whitespaces).lowercased()))
            dominioNuevo = ""
            await cargarDominio()
        } catch { estado.avisar(error) }
    }

    private func campo(_ k: String, _ def: String) -> Binding<String> {
        Binding(get: { marca[k] ?? def }, set: { marca[k] = $0; programar() })
    }

    private func color(_ k: String, _ def: UInt32) -> Binding<Color> {
        Binding(get: {
            if let h = marca[k], let n = UInt32(h.replacingOccurrences(of: "#", with: ""), radix: 16) { return Color(hex: n) }
            return Color(hex: def)
        }, set: { c in
            let u = UIColor(c)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            marca[k] = String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
            programar()
        })
    }

    /// Guarda el borrador (no publica): enseguida con `ya`, o un ratito después de dejar de escribir.
    private func programar(ya: Bool = false) {
        guardado?.cancel()
        hayBorrador = true
        guardado = Task {
            if !ya { try? await Task.sleep(for: .milliseconds(900)) }
            if Task.isCancelled { return }
            var m = completa
            for (k, v) in marca { m.poner(k, v) }
            // Lo que se borró del todo (un texto vaciado) también sale.
            for k in completa.keys where completa[k]?.texto != nil && marca[k] == nil { m[k] = nil }
            do {
                let b = try await BorradorWeb.guardar(estado.api, marca: m, si: en)
                completa = b.marca
                en = b.en
                hayBorrador = b.hayBorrador
                recarga += 1
            } catch let e as ErrorApi where e.codigo == "borrador_cambiado" {
                estado.avisar("Tu web se cambió desde otro lado. Trajimos lo último.", ok: false)
                await traerBorrador()
            } catch { estado.avisar(error) }
            guardado = nil
        }
    }

    private func traerBorrador() async {
        guard let b = try? await BorradorWeb.leer(estado.api) else { return }
        guard b.en != en || b.hayBorrador != hayBorrador || completa.isEmpty else { return }
        completa = b.marca
        marca = b.marca.compactMapValues { $0.texto }
        en = b.en
        hayBorrador = b.hayBorrador
        recarga += 1
    }

    /// Lo tocado en la vista previa: su editor (o, una sección, la de «Página de inicio»).
    private func tocar(_ z: String) {
        if z.hasPrefix("seccion:") {
            let id = String(z.dropFirst(8))
            guard let i = secciones.firstIndex(where: { $0["id"]?.texto == id }) else { return }
            switch secciones[i]["tipo"]?.texto {
            case "texto", "testimonios": editandoSeccion = i
            case "portada": zona = ZonaWeb(clave: "portada")
            default: estado.avisar("Esa sección se ordena o se apaga en «Página de inicio», más abajo.")
            }
        } else {
            zona = ZonaWeb(clave: z)
        }
    }

    /// «Publicar cambios» y «Descartar», siempre a mano mientras haya cambios sin publicar.
    private var barraPublicar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(hayBorrador ? "Cambios sin publicar" : "Igual a la publicada").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(hayBorrador ? "Se guardan solos; salen con «Publicar»" : "Lo que cambies se guarda aparte").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
            if hayBorrador {
                Button("Descartar") { Task { await descartar() } }
                    .font(Estilo.subheadFuerte.font).foregroundStyle(C.texto2).disabled(publicando)
                Button { Task { await publicar() } } label: { Text(publicando ? "Publicando…" : "Publicar").padding(.horizontal, 16) }
                    .buttonStyle(BotonPrincipal(alto: 44)).fixedSize().disabled(publicando)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func publicar() async {
        publicando = true
        defer { publicando = false }
        if let g = guardado { await g.value }
        do {
            try await BorradorWeb.publicar(estado.api)
            hayBorrador = false
            en = nil
            Haptico.exito()
            estado.avisar("Cambios publicados en tu web")
            await estado.cargarEstructura()
        } catch { estado.avisar(error) }
    }

    private func descartar() async {
        guardado?.cancel()
        guardado = nil
        do {
            try await BorradorWeb.descartar(estado.api)
            en = nil
            completa = [:]
            await traerBorrador()
            estado.avisar("Volviste a la web publicada")
        } catch { estado.avisar(error) }
    }

    private func guardarBarrio(_ b: BarrioWeb) async {
        struct Cuerpo: Encodable { var texto: String }
        do {
            try await estado.api.hacer("PUT", "/v1/web/barrios/\(b.nombre)", Cuerpo(texto: b.texto ?? ""))
            estado.avisar("Guardado el texto de \(b.nombre)")
        } catch { estado.avisar(error) }
    }
}

/// Editar una sección de texto o de testimonios del inicio de la web (con «Reescribir con IA»).
struct EditorSeccionWeb: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var seccion: JSONLibre
    var guardar: (JSONLibre) -> Void
    @State private var titulo = ""
    @State private var texto = ""
    @State private var items: [(String, String)] = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $titulo)
                if seccion["tipo"]?.texto == "testimonios" {
                    ForEach(items.indices, id: \.self) { i in
                        VStack {
                            TextField("Lo que dijo", text: Binding(get: { items[i].0 }, set: { items[i].0 = $0 }), axis: .vertical)
                            TextField("Quién", text: Binding(get: { items[i].1 }, set: { items[i].1 = $0 }))
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button { items.append(("", "")) } label: { Label("Sumar testimonio", systemImage: "plus") }
                } else {
                    TextField("Texto", text: $texto, axis: .vertical).lineLimit(4...14)
                    Button {
                        Task {
                            struct C: Encodable { var campo = "texto"; var texto: String }
                            struct R: Decodable { var texto: String }
                            if let r: R = try? await estado.api.enviar("POST", "/v1/web/reescribir", C(texto: texto)) { texto = r.texto }
                        }
                    } label: { Label("Reescribir con IA", systemImage: "sparkles") }
                    .disabled(texto.isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        guard case .objeto(var o) = seccion else { return cerrar() }
                        o["titulo"] = titulo.isEmpty ? nil : .texto(titulo)
                        if seccion["tipo"]?.texto == "testimonios" {
                            o["items"] = .lista(items.filter { !$0.0.isEmpty }.map { .objeto(["texto": .texto($0.0), "autor": .texto($0.1)]) })
                        } else { o["texto"] = .texto(texto) }
                        guardar(.objeto(o))
                        cerrar()
                    }
                }
            }
        }
        .onAppear {
            titulo = seccion["titulo"]?.texto ?? ""
            texto = seccion["texto"]?.texto ?? ""
            if case .lista(let l)? = seccion["items"] { items = l.map { ($0["texto"]?.texto ?? "", $0["autor"]?.texto ?? "") } }
        }
    }
}
