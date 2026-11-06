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
    @State private var versiones = false
    @State private var plantillas = false
    @State private var qr = false
    @State private var fotoPortada = false
    @State private var editandoPagina: Int?
    @State private var legales: JSONLibre?
    @State private var informe: JSONLibre?
    @State private var errorDominio: String?
    @State private var verificando = false
    @State private var nombreInmo = ""
    @FocusState private var barrioFoco: String?
    /// Deshacer y rehacer (50 pasos): la marca entera antes de cada cambio.
    @State private var pasado: [[String: JSONLibre]] = []
    @State private var futuro: [[String: JSONLibre]] = []
    @State private var ultimoPaso = Date.distantPast

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
            if !estado.esDuenio {
                Section { Label("La web la cambia el dueño o la dueña. Vos la podés ver como queda.", systemImage: "lock").estilo(.footnote).foregroundStyle(C.texto2) }
            }
            if let w = web, let u = URL(string: w) {
                Section {
                    Link(destination: u) { Label(w.replacingOccurrences(of: "https://", with: ""), systemImage: "globe") }
                    Button { Afuera.whatsapp(nil, texto: "Mirá las propiedades de \(nombreInmo.nonEmpty ?? "la inmobiliaria"): \(w)") } label: { Label("Mandar por WhatsApp", systemImage: "bubble.left") }
                    ShareLink(item: u, subject: Text(nombreInmo), message: Text("Mirá las propiedades de \(nombreInmo)")) { Label("Compartir tu web", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.url = u; estado.avisar("Copiaste el link de tu web") } label: { Label("Copiar el link", systemImage: "doc.on.doc") }
                    Button { qr = true } label: { Label("El QR de tu web", systemImage: "qrcode") }
                }
            }
            if let i = informe {
                Section("Esta semana") {
                    LabeledContent("Visitas a tus propiedades", value: Informe.num(i["totalVistas"]))
                    LabeledContent("Consultas desde tu web", value: {
                        if case .lista(let l)? = i["origenes"], let o = l.first(where: { $0["origen"]?.texto == "Web propia" }) { return Informe.num(o["cantidad"]) }
                        return "0"
                    }())
                }
            }
            Section("Plantilla") {
                let id = completa["plantilla"]?.texto ?? "barrio"
                LabeledContent("En uso", value: EditorWeb.plantillas.first { $0.id == id }?.nombre ?? id)
                Button { plantillas = true } label: { Label("Ver las plantillas", systemImage: "rectangle.3.group") }
                Button { versiones = true } label: { Label("Versiones publicadas", systemImage: "clock.arrow.circlepath") }
            }
            Section(header: Text("Página de inicio"), footer: Text("Arrastrá para ordenar. Lo apagado no se ve en tu web.")) {
                ForEach(Array(secciones.enumerated()), id: \.offset) { i, x in
                    Toggle(Self.nombreSeccion(x["tipo"]?.texto), isOn: Binding(get: { x["oculta"].map { if case .bool(true) = $0 { return false }; return true } ?? true },
                                                                         set: { on in ocultar(i, !on) }))
                        .disabled(x["tipo"]?.texto == "portada")
                        .swipeActions {
                            if x["tipo"]?.texto != "portada" { Button("Quitar", role: .destructive) { quitarSeccion(i) } }
                            if x["tipo"]?.texto == "texto" { Button("Duplicar") { duplicarSeccion(i) }.tint(C.accion) }
                        }
                        .contextMenu {
                            if x["tipo"]?.texto == "texto" { Button { duplicarSeccion(i) } label: { Label("Duplicar", systemImage: "plus.square.on.square") } }
                            Menu {
                                ForEach(EditorWeb.tiposParaSumar(secciones), id: \.self) { t in Button(Self.nombreSeccion(t)) { sumarSeccion(t, despuesDe: i) } }
                            } label: { Label("Sumar sección acá", systemImage: "plus.rectangle.on.rectangle") }
                            if x["tipo"]?.texto != "portada" { Button(role: .destructive) { quitarSeccion(i) } label: { Label("Quitar", systemImage: "trash") } }
                        }
                }
                .onMove { desde, hacia in mover(desde, hacia) }
                Toggle("Buscador en la portada (Comprar · Alquilar · Temporada)", isOn: Binding(get: { portada["buscador"].map { if case .bool(false) = $0 { return false }; return true } ?? true },
                                                                                             set: { v in conPortada { $0["buscador"] = .bool(v) } }))
                VStack(alignment: .leading, spacing: 6) {
                    let v = veloActual
                    let noche = EditorWeb.noche(marca["colorPrimario"])
                    let variante = portada["variante"]?.texto ?? "foto"
                    let seLee = variante == "foto" ? EditorWeb.seLeeConVelo(noche, v)
                        : Acento.contraste(Acento.rgb(marca["colorPrimario"]).map(Acento.hex) ?? 0x16443B, Acento.rgb(marca["colorFondo"]).map(Acento.hex) ?? 0xFAF8F3) >= 4.5
                    Text("Velo sobre la foto · \(Int(v)) %").estilo(.subhead)
                    Slider(value: Binding(get: { veloActual }, set: { n in conPortada { $0["velo"] = .numero((n / 5).rounded() * 5) } }), in: 0...90, step: 5)
                    if seLee {
                        Label("El título se lee bien (contraste AA)", systemImage: "checkmark.circle").estilo(.footnote).foregroundStyle(C.okTinta)
                    } else if variante == "foto" {
                        let m = EditorWeb.veloMinimo(noche)
                        HStack {
                            Text("El título cuesta leerse.").estilo(.footnote).foregroundStyle(C.avisoTinta)
                            Button("Subir el velo a \(m) %") { conPortada { $0["velo"] = .numero(Double(m)) } }.estilo(.footnoteFuerte)
                        }
                    } else {
                        Text("El título puede costar leerse: probá un color más oscuro").estilo(.footnote).foregroundStyle(C.avisoTinta)
                    }
                }
                Button { fotoPortada = true } label: { Label("Usar la foto de una propiedad", systemImage: "photo.on.rectangle") }
                Picker("Portada", selection: Binding(get: { completa["web"]?["portada"]?["variante"]?.texto ?? "foto" }, set: { variante($0) })) {
                    Text("Foto de fondo").tag("foto"); Text("Foto arriba").tag("arriba"); Text("Partida").tag("partida")
                }
            }
            Section(header: Text("Sumar a la página de inicio")) {
                Menu {
                    ForEach(EditorWeb.tiposParaSumar(secciones), id: \.self) { t in
                        Button(Self.nombreSeccion(t)) { sumarSeccion(t) }
                    }
                } label: { Label("Sumar sección", systemImage: "plus.rectangle.on.rectangle") }
                .disabled(EditorWeb.tiposParaSumar(secciones).isEmpty)
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
                    if id.hasPrefix("p-") {
                        Button { editandoPagina = i } label: { Label("Editar «\(Self.nombrePagina(x))»", systemImage: "pencil") }
                    }
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
            if estado.esDuenio { seccionDominio }
            Section {
                if let l = legales, l["razonSocial"]?.texto != nil || l["cuit"]?.texto != nil || l["matricula"]?.texto != nil {
                    if let r = l["razonSocial"]?.texto { LabeledContent("Razón social", value: r) }
                    if let c = l["cuit"]?.texto { LabeledContent("CUIT", value: c) }
                    if let m = l["matricula"]?.texto { LabeledContent("Matrícula", value: [l["colegio"]?.texto, m].compactMap { $0 }.joined(separator: " ")) }
                } else {
                    Text("Faltan la razón social, el CUIT y la matrícula. En CABA y Provincia el corredor tiene que exhibirlos.").estilo(.footnote).foregroundStyle(C.avisoTinta)
                }
                Button("Editar") { estado.abrir(ASeccion(clave: "configuracion")) }
            } header: { Text("Datos legales del pie") }
            Section("Marca") {
                HStack(spacing: 10) {
                    ForEach(EditorWeb.colores, id: \.self) { c in
                        Button { recordar(); marca["colorPrimario"] = c; programar() } label: {
                            Circle().fill(Color(hex: UInt32(c.dropFirst(), radix: 16) ?? 0)).frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(C.oro, lineWidth: (marca["colorPrimario"] ?? "").lowercased() == c ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(c)")
                    }
                }
                ColorPicker("Color principal", selection: color("colorPrimario", 0x16443B), supportsOpacity: false)
                avisoContraste
                ColorPicker("Color de acento", selection: color("colorSecundario", 0xF2BB57), supportsOpacity: false)
                ColorPicker("Fondo", selection: color("colorFondo", 0xFAF8F3), supportsOpacity: false)
                if let f = Acento.rgb(marca["colorFondo"]).map(Acento.hex), Acento.contraste(f, 0x18201D) < 7 {
                    Label("El fondo tiene que ser claro para que el texto se lea: usamos el papel", systemImage: "slider.horizontal.3").estilo(.footnote).foregroundStyle(C.avisoTinta)
                }
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
                            TextField("Cómo es vivir en \(b.nombre): plazas, transporte, colegios.", text: Binding(get: { b.texto ?? "" }, set: { b.texto = String($0.prefix(600)) }), axis: .vertical)
                                .focused($barrioFoco, equals: b.nombre)
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
        .toolbar {
            if estado.esDuenio {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { deshacer() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(pasado.isEmpty).accessibilityLabel("Deshacer")
                    Button { rehacer() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(futuro.isEmpty).accessibilityLabel("Rehacer")
                }
            }
        }
        .onChange(of: barrioFoco) { viejo, _ in
            if let v = viejo, let b = barrios.first(where: { $0.nombre == v }) { Task { await guardarBarrio(b) } }
        }
        .sheet(isPresented: $versiones) { HojaVersionesWeb { completa = [:]; Task { await traerBorrador() } } }
        .sheet(isPresented: $plantillas) { HojaPlantillas { completa = [:]; Task { await traerBorrador() } } }
        .sheet(isPresented: $qr) { if let w = web { HojaQRWeb(web: w, nombre: nombreInmo).presentationDetents([.medium]) } }
        .sheet(isPresented: $fotoPortada) { ElegirFotoPortada { u in recordar(); marca["portadaUrl"] = u; programar(ya: true) } }
        .sheet(item: Binding(get: { editandoPagina.map { CampoAlta(id: String($0)) } }, set: { editandoPagina = $0.flatMap { Int($0.id) } })) { x in
            let i = Int(x.id) ?? 0
            EditorPaginaWeb(pagina: paginas[safe: i] ?? .objeto([:]), web: web) { t, texto in
                var l = paginas
                guard case .objeto(var o)? = l[safe: i] else { return }
                o["titulo"] = .texto(t)
                o["texto"] = .texto(texto)
                l[i] = .objeto(o)
                conWeb { $0["paginas"] = .lista(l) }
            }
        }
        .sheet(item: $zona) { z in
            EditorZonaWeb(zona: z.clave, marca: $marca) { programar(ya: true) }
                .presentationDetents([.medium, .large])
        }
        // Lo cambiado desde la computadora (o el alta) se trae, si acá no hay nada esperando guardarse.
        .task(id: estado.version) { if guardado == nil, !publicando { await traerBorrador() } }
        .task {
            struct I: Decodable { var web: String?; var nombre: String?; var legales: JSONLibre? }
            if let i: I = try? await estado.api.get("/v1/inmobiliaria") { web = i.web; nombreInmo = i.nombre ?? ""; legales = i.legales }
            informe = try? await estado.api.get("/v1/informe", query: [.init(name: "dias", value: "7")])
            await traerBorrador()
            if estado.esDuenio { previa = try? await BorradorWeb.urlPrevia(estado.api, slug: estado.inmobiliaria?.slug ?? "") }
            barrios = (try? await estado.api.get("/v1/web/barrios")) ?? []
            guardadas = try? await estado.api.get("/v1/web/guardadas", query: [.init(name: "dias", value: "7")])
            await cargarDominio()
        }
        .sheet(isPresented: $paginaNueva) { NuevaPaginaWeb(paginas: paginas, web: web) { t in sumarPagina(t) } }
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
        recordar(forzar: true)
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
        if let p = EditorWeb.problemaPagina(paginas, titulo) { return estado.avisar(p, ok: false) }
        let ruta = EditorWeb.rutaDe(titulo)
        var l = paginas
        l.append(.objeto(["id": .texto("p-\(ruta)"), "titulo": .texto(titulo), "ruta": .texto(ruta), "texto": .texto("")]))
        conWeb { $0["paginas"] = .lista(l) }
    }

    private func sumarSeccion(_ tipo: String, despuesDe: Int? = nil) {
        var l = secciones
        guard EditorWeb.tiposParaSumar(l).contains(tipo) else { return estado.avisar(l.count >= EditorWeb.maxSecciones ? "Hasta \(EditorWeb.maxSecciones) secciones." : "Esa sección ya está.", ok: false) }
        var o: [String: JSONLibre] = ["id": .texto(EditorWeb.idNuevo(l, tipo)), "tipo": .texto(tipo)]
        if tipo == "texto" { o["titulo"] = .texto("Un título"); o["texto"] = .texto("") }
        if tipo == "testimonios" { o["items"] = .lista([]) }
        l.insert(.objeto(o), at: despuesDe.map { min(l.count, $0 + 1) } ?? l.count)
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
        errorDominio = nil
        do {
            _ = try await estado.api.conCampos("PATCH", "/v1/inmobiliaria", C(dominio: d.trimmingCharacters(in: .whitespaces).lowercased()))
            dominioNuevo = ""
            await cargarDominio()
        } catch let e as ErrorConCampos {
            errorDominio = e.campos["dominio"] ?? e.error.detalle
        } catch let e as ErrorApi where e.estado == 409 || e.estado == 400 {
            errorDominio = e.detalle
        } catch { estado.avisar(error) }
    }

    private func campo(_ k: String, _ def: String) -> Binding<String> {
        Binding(get: { marca[k] ?? def }, set: { recordar(); marca[k] = $0; programar() })
    }

    private func color(_ k: String, _ def: UInt32) -> Binding<Color> {
        Binding(get: {
            if let h = marca[k], let n = UInt32(h.replacingOccurrences(of: "#", with: ""), radix: 16) { return Color(hex: n) }
            return Color(hex: def)
        }, set: { c in
            let u = UIColor(c)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            recordar()
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
            } catch {
                let msj = (error as? ErrorApi)?.detalle ?? "No se guardó"
                estado.sugerir("\(msj) · No se guardó", "Reintentar") { programar(ya: true) }
            }
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
        let antes = actual()
        do {
            try await BorradorWeb.descartar(estado.api)
            en = nil
            completa = [:]
            await traerBorrador()
            estado.avisar("Volviste a la web publicada") { aplicar(antes) }
        } catch { estado.avisar(error) }
    }

    // MARK: Deshacer, quitar, duplicar y el dominio

    /// La marca entera con lo que se está escribiendo encima.
    private func actual() -> [String: JSONLibre] {
        var m = completa
        for (k, v) in marca { m.poner(k, v) }
        return m
    }

    /// Guarda el paso para deshacer (al escribir, uno cada tanto; los demás cambios, siempre).
    private func recordar(forzar: Bool = false) {
        guard forzar || Date().timeIntervalSince(ultimoPaso) > 1.5 else { return }
        ultimoPaso = Date()
        pasado.append(actual())
        if pasado.count > 50 { pasado.removeFirst() }
        futuro = []
    }

    private func aplicar(_ m: [String: JSONLibre]) {
        completa = m
        marca = m.compactMapValues { $0.texto }
        programar(ya: true)
    }

    private func deshacer() {
        guard let m = pasado.popLast() else { return }
        futuro.append(actual())
        aplicar(m)
    }

    private func rehacer() {
        guard let m = futuro.popLast() else { return }
        pasado.append(actual())
        aplicar(m)
    }

    private func quitarSeccion(_ i: Int) {
        var l = secciones
        guard l.indices.contains(i), l[i]["tipo"]?.texto != "portada" else { return }
        let antes = l
        let nombre = Self.nombreSeccion(l[i]["tipo"]?.texto)
        l.remove(at: i)
        conWeb { $0["inicio"] = .lista(l) }
        estado.avisar("Quitaste «\(nombre)»") { conWeb { $0["inicio"] = .lista(antes) } }
    }

    private func duplicarSeccion(_ i: Int) {
        var l = secciones
        guard l.indices.contains(i), l[i]["tipo"]?.texto == "texto", l.count < EditorWeb.maxSecciones, case .objeto(var o) = l[i] else { return }
        o["id"] = .texto(EditorWeb.idNuevo(l, "texto"))
        l.insert(.objeto(o), at: i + 1)
        conWeb { $0["inicio"] = .lista(l) }
        estado.avisar("Duplicaste la sección de texto")
    }

    private var portada: [String: JSONLibre] {
        if case .objeto(let o)? = completa["web"]?["portada"] { return o }
        return [:]
    }

    private var veloActual: Double { if case .numero(let n)? = portada["velo"] { return n }; return 45 }

    private func conPortada(_ f: (inout [String: JSONLibre]) -> Void) {
        conWeb { w in
            var p: [String: JSONLibre] = [:]
            if case .objeto(let o)? = w["portada"] { p = o }
            f(&p)
            w["portada"] = .objeto(p)
        }
    }

    /// «Lo oscurecimos un poco…» si el color no llega a contraste AA con el blanco.
    @ViewBuilder
    private var avisoContraste: some View {
        if let p = Acento.rgb(marca["colorPrimario"]).map(Acento.hex) {
            if Acento.contraste(p, 0xFFFFFF) < 4.5 {
                Label("Lo oscurecimos un poco para que botones y textos lleguen a contraste AA", systemImage: "slider.horizontal.3").estilo(.footnote).foregroundStyle(C.avisoTinta)
            } else {
                Label("Contraste AA en botones y textos", systemImage: "checkmark.circle").estilo(.footnote).foregroundStyle(C.okTinta)
            }
        }
    }

    /// El dominio propio en tres pasos, con los registros DNS para copiar.
    @ViewBuilder
    private var seccionDominio: some View {
        let d = dominio?["dominio"]?.texto
        let verificado: Bool = { if case .bool(true)? = dominio?["verificado"] { return true }; return false }()
        Section {
            if let d {
                LabeledContent(d, value: verificado ? "Conectado" : "Verificando")
                Label("1. Lo compraste en NIC.ar u otro registro", systemImage: "checkmark.circle.fill").foregroundStyle(C.okTinta)
                let registros: [JSONLibre] = { if case .lista(let l)? = dominio?["registros"] { return l }; return [] }()
                let principal = registros.first
                Label("2. Cargaste \(principal?["tipo"]?.texto == "A" ? "el registro A" : "el CNAME") \(principal?["valor"]?.texto ?? "")",
                      systemImage: verificado ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(verificado ? C.okTinta : C.texto)
                if !verificado {
                    ForEach(Array(registros.enumerated()), id: \.offset) { _, r in
                        Button {
                            UIPasteboard.general.string = r["valor"]?.texto
                            estado.avisar("Copiado")
                        } label: {
                            HStack {
                                Text(r["tipo"]?.texto ?? "").frame(width: 56, alignment: .leading)
                                Text(r["nombre"]?.texto ?? "").frame(width: 60, alignment: .leading)
                                Text(r["valor"]?.texto ?? "").lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                            }
                            .font(.system(size: 13, design: .monospaced))
                        }
                    }
                    Label("3. Esperando que se propague · suele tardar hasta 2 h", systemImage: "hourglass").foregroundStyle(C.texto2)
                    Button(verificando ? "Verificando…" : "Verificar ahora") { Task { await verificar() } }.disabled(verificando)
                } else if let u = URL(string: "https://\(d)") {
                    Link(destination: u) { Label("3. Tu web responde en \(d)", systemImage: "checkmark.circle.fill") }
                }
                Button("Quitar", role: .destructive) { Task { await quitarDominio(d) } }
            } else {
                TextField("tuinmobiliaria.com.ar", text: $dominioNuevo).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                if let e = errorDominio { MensajeError(texto: e) }
                Button("Conectar") { Task { await ponerDominio(dominioNuevo) } }.disabled(!dominioNuevo.contains("."))
            }
        } header: { Text("Dominio propio") } footer: {
            if d == nil { Text("Hoy tu web está en \((web ?? "").replacingOccurrences(of: "https://", with: "")). Si tenés un dominio (de NIC.ar u otro), la ponemos ahí en tres pasos.") }
        }
    }

    private func verificar() async {
        verificando = true
        defer { verificando = false }
        do {
            try await estado.api.hacer("POST", "/v1/inmobiliaria/dominio/verificar")
            await cargarDominio()
            estado.avisar("¡Listo! Tu web ya responde en tu dominio.")
        } catch { estado.avisar(error) }
    }

    private func quitarDominio(_ antes: String) async {
        await ponerDominio("")
        if dominio?["dominio"]?.texto == nil {
            estado.avisar("Quitaste el dominio propio") { Task { await ponerDominio(antes) } }
        }
    }

    private func guardarBarrio(_ b: BarrioWeb) async {
        struct Cuerpo: Encodable { var texto: String }
        do {
            try await estado.api.hacer("PUT", "/v1/web/barrios/\(b.nombre)", Cuerpo(texto: b.texto ?? ""))
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
                        .disabled(items.count >= 6)
                    if items.count >= 6 { Text("Hasta 6 testimonios.").estilo(.footnote).foregroundStyle(C.texto2) }
                } else {
                    TextField("Texto", text: $texto, axis: .vertical).lineLimit(4...14)
                    Button {
                        Task {
                            struct C: Encodable { var campo = "texto"; var texto: String }
                            struct R: Decodable { var texto: String }
                            do {
                                let r: R = try await estado.api.enviar("POST", "/v1/web/reescribir", C(texto: texto))
                                texto = r.texto
                            } catch { estado.avisar(error) }
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
