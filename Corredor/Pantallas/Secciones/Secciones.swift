import AuthenticationServices
import SwiftUI

extension View {
    /// Lo que el handoff no dibuja y el panel sí tiene: una sección por clave (ver `ASeccion`).
    func destinosSecciones() -> some View {
        navigationDestination(for: ASeccion.self) { s in Seccion(clave: s.clave, id: s.id) }
    }
}

/// Elige la pantalla de cada sección. Lo no dibujado se arma con las piezas del handoff (tarjetas,
/// filas, chips, hojas), nunca con diseño nuevo.
struct Seccion: View {
    var clave: String
    var id: String?

    var body: some View {
        switch clave {
        case "mas": Todo()
        case "configuracion", "inmobiliaria": ConfigInmobiliaria()
        case "equipo": Equipo()
        case "integraciones", "whatsapp", "mercadolibre": Integraciones()
        case "respuestas": RespuestasGuardadas()
        case "proveedores": Proveedores()
        case "objetivos": Objetivos()
        case "inventarios": ListaActas()
        case "actas": if let id { Inventario(propiedad: id) }
        case "rendiciones": RendicionesListas()
        case "papelera": Papelera()
        case "actividad": ListaGenerica(titulo: "Actividad", ruta: "/v1/actividad", icono: "clock.arrow.circlepath", vacio: "Todavía no hay movimientos.")
        case "revision": Revision()
        case "informe": Informe()
        case "indices": Indices()
        case "vistas": if let id { ListaGenerica(titulo: "Vistas y consultas", ruta: "/v1/propiedades/\(id)/vistas", icono: "eye", vacio: "Todavía nadie la vio.") }
        case "tarifas": if let id { Tarifas(propiedad: id) }
        case "web", "plantillas", "editor": MiWeb()
        case "difusion": ListaGenerica(titulo: "Difusión", ruta: "/v1/publicaciones", icono: "megaphone", vacio: "Todavía no publicaste en portales.")
        case "emprendimientos": Emprendimientos()
        case "emprendimiento": if let id { FichaEmprendimiento(id: id) }
        case "temporada": Temporada()
        case "reservas": ListaGenerica(titulo: "Reservas", ruta: "/v1/reservas", icono: "hand.raised", vacio: "No hay reservas abiertas.")
        case "consorcios": Consorcios()
        case "consorcio": if let id { FichaConsorcio(id: id) }
        case "ia": ConectarIA()
        default: EstadoVacio(icono: "questionmark.folder", titulo: "No encontramos esta sección").frame(maxHeight: .infinity).background(FondoApp())
        }
    }
}

// MARK: - Todo

/// «Todo»: todas las secciones del panel, agrupadas, para llegar a cualquier cosa desde el celular.
struct Todo: View {
    @Environment(Estado.self) private var estado

    private var grupos: [(String, [(String, String, AnyHashable)])] {
        var g: [(String, [(String, String, AnyHashable)])] = [
            ("Cartera", [("building.2", "Propiedades", ASeccion(clave: "_propiedades")), ("person.2", "Contactos", AContactos()),
                         ("rectangle.split.3x1", "Operaciones", AOperaciones()), ("hand.raised", "Reservas", ASeccion(clave: "reservas")),
                         ("building", "Emprendimientos", ASeccion(clave: "emprendimientos")), ("beach.umbrella", "Temporada", ASeccion(clave: "temporada"))]),
            ("Alquileres", [("dollarsign.circle", "Cobranzas", ACobranzas()), ("doc.text", "Contratos", AContratos()),
                            ("doc.plaintext", "Rendiciones", ASeccion(clave: "rendiciones")), ("checklist", "Actas de entrega", ASeccion(clave: "inventarios")),
                            ("chart.line.uptrend.xyaxis", "Índices", ASeccion(clave: "indices")), ("building.columns", "Consorcios", ASeccion(clave: "consorcios"))]),
            ("Difusión", [("globe", "Mi web", ASeccion(clave: "web")), ("megaphone", "Portales", ASeccion(clave: "difusion")),
                          ("quote.bubble", "Respuestas guardadas", ASeccion(clave: "respuestas"))]),
            ("Equipo", [("flag", "Objetivos", ASeccion(clave: "objetivos")), ("chart.bar", "Informe", ASeccion(clave: "informe")),
                        ("checkmark.shield", "Revisión de la IA", ASeccion(clave: "revision")), ("clock.arrow.circlepath", "Actividad", ASeccion(clave: "actividad"))]),
        ]
        var ajustes: [(String, String, AnyHashable)] = [("storefront", "Inmobiliaria", ASeccion(clave: "configuracion")), ("person.3", "Equipo", ASeccion(clave: "equipo")),
                                                        ("puzzlepiece.extension", "Integraciones", ASeccion(clave: "integraciones")), ("wrench.and.screwdriver", "Proveedores", ASeccion(clave: "proveedores")),
                                                        ("sparkles", "Corredor en tu IA", ASeccion(clave: "ia")), ("trash", "Papelera", ASeccion(clave: "papelera"))]
        if !estado.esDuenio { ajustes.removeAll { ["Integraciones", "Corredor en tu IA"].contains($0.1) } }
        g.append(("Configuración", ajustes))
        return g
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(grupos, id: \.0) { titulo, items in
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: titulo)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(items, id: \.1) { icono, texto, destino in
                                Button {
                                    if (destino as? ASeccion)?.clave == "_propiedades" { estado.pestana = .propiedades } else { estado.abrir(destino) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icono).font(.system(size: 20, weight: .medium)).foregroundStyle(C.accion).frame(width: 24)
                                        Text(texto).estilo(.filaLista).foregroundStyle(C.texto).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 64).tarjeta(16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .pantallaApilada("Todo")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Lista genérica

/// Una lista de lo que devuelva la API (cualquier forma): toma el título, el detalle y la fecha de los
/// campos habituales. Para secciones de consulta (actividad, vistas, portales).
struct ListaGenerica: View {
    @Environment(Estado.self) private var estado
    var titulo: String
    var ruta: String
    var icono: String
    var vacio: String
    var acciones: ((JSONLibre) -> [(String, () -> Void)])? = nil
    @State private var items: [JSONLibre]?
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let items {
                    if items.isEmpty { EstadoVacio(icono: icono, titulo: vacio).padding(.top, 50) }
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                            HStack(alignment: .top, spacing: 12) {
                                IconoTono(icono: icono, tono: .verde, tam: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.titulo(x)).estilo(.filaLista).foregroundStyle(C.texto)
                                    if let d = Self.detalle(x) { Text(d).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(3) }
                                    if let f = Self.fecha(x) { Text(Formato.cuando(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                                    if let a = acciones?(x), !a.isEmpty {
                                        HStack { ForEach(a, id: \.0) { t, h in Button(t, action: h).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion) } }.padding(.top, 4)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { abrir(x) }
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                } else if let error {
                    EstadoError(que: titulo.lowercased(), error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 6) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada(titulo)
        .navigationBarTitleDisplayMode(.large)
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        do {
            let d = try await estado.api.pedir("GET", ruta, query: [.init(name: "limite", value: "200")])
            let j = try Api.decodificador.decode(JSONLibre.self, from: d)
            if case .lista(let l) = j { items = l }
            else if case .objeto(let o) = j, let l = o.values.first(where: { if case .lista = $0 { return true }; return false }), case .lista(let x) = l { items = x }
            else { items = [] }
            error = nil
        } catch let e as ErrorApi { error = e } catch { items = [] }
    }

    private func abrir(_ x: JSONLibre) {
        if let p = x["propiedadId"]?.texto { estado.abrir(AFichaPropiedad(id: p)) }
        else if let c = x["contactoId"]?.texto { estado.abrir(AFichaContacto(id: c)) }
        else if let c = x["contratoId"]?.texto { estado.abrir(AFichaContrato(id: c)) }
    }

    static func titulo(_ x: JSONLibre) -> String {
        for k in ["titulo", "nombre", "descripcion", "propiedadTitulo", "propiedad", "texto", "accion", "codigo", "portal"] { if let t = x[k]?.texto?.nonEmpty { return t } }
        return "—"
    }

    static func detalle(_ x: JSONLibre) -> String? {
        let partes = ["detalle", "contactoNombre", "estado", "entidad", "autorNombre", "agenteNombre", "direccion", "barrio", "motivo"].compactMap { x[$0]?.texto?.nonEmpty }
        return partes.isEmpty ? nil : partes.prefix(3).joined(separator: " · ")
    }

    static func fecha(_ x: JSONLibre) -> Date? {
        for k in ["ocurrioEn", "creadoEn", "creadaEn", "borradoEn", "actualizadoEn", "en", "fecha"] { if let t = x[k]?.texto, let f = Fecha.iso(t) ?? Fecha.dia(t) { return f } }
        return nil
    }
}

// MARK: - Configuración

/// Inmobiliaria: nombre, zona horaria, CBU o alias, y los datos legales del pie y los recibos.
struct ConfigInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var nombre = ""
    @State private var cbu = ""
    @State private var zona = "America/Argentina/Buenos_Aires"
    @State private var legales: [String: String] = [:]
    @State private var guardando = false

    private static let camposLegales = [("razonSocial", "Razón social"), ("cuit", "CUIT"), ("corredorResponsable", "Corredor responsable"), ("matricula", "Matrícula"), ("colegio", "Colegio")]

    var body: some View {
        Form {
            Section("Datos") {
                TextField("Nombre de la inmobiliaria", text: $nombre)
                TextField("CBU o alias para cobrar", text: $cbu).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Zona horaria", selection: $zona) {
                    ForEach(["America/Argentina/Buenos_Aires", "America/Argentina/Cordoba", "America/Argentina/Mendoza", "America/Argentina/Salta", "America/Argentina/Ushuaia"], id: \.self) {
                        Text($0.replacingOccurrences(of: "America/Argentina/", with: "").replacingOccurrences(of: "_", with: " ")).tag($0)
                    }
                }
            }
            Section(header: Text("Datos legales"), footer: Text("Van en el pie de tu web y en los recibos. En CABA y Provincia, la matrícula es obligatoria.")) {
                ForEach(Self.camposLegales, id: \.0) { k, n in
                    TextField(n, text: Binding(get: { legales[k] ?? "" }, set: { legales[k] = $0 }))
                        .keyboardType(k == "cuit" || k == "matricula" ? .numbersAndPunctuation : .default)
                }
            }
            Section { Button("Mi web: logo, colores y dominio") { estado.abrir(ASeccion(clave: "web")) } }
        }
        .disabled(!estado.esDuenio)
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Inmobiliaria")
        .toolbar { if estado.esDuenio { Button("Guardar") { Task { await guardar() } }.disabled(guardando) } }
        .task {
            struct I: Decodable { var nombre: String?; var cbu: String?; var zonaHoraria: String?; var legales: [String: String?]? }
            if let i: I = try? await estado.api.get("/v1/inmobiliaria") {
                nombre = i.nombre ?? ""
                cbu = i.cbu ?? ""
                zona = i.zonaHoraria ?? zona
                legales = (i.legales ?? [:]).compactMapValues { $0 }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var nombre: String; var cbu: String; var zonaHoraria: String; var legales: [String: String] }
        do {
            try await estado.api.hacer("PATCH", "/v1/inmobiliaria", Cuerpo(nombre: nombre, cbu: cbu.trimmingCharacters(in: .whitespaces), zonaHoraria: zona, legales: legales))
            estado.avisar("Guardado")
        } catch { estado.avisar(error) }
    }
}

/// Equipo: las personas con su rol (el dueño lo cambia con «Deshacer»), invitar por link, las
/// invitaciones pendientes y las licencias.
struct Equipo: View {
    @Environment(Estado.self) private var estado
    @State private var equipo: [Miembro] = []
    @State private var invitaciones: [Invitacion] = []
    @State private var licencias: [Licencia] = []
    @State private var invitando = false
    @State private var mail = ""
    @State private var rol = "agente"
    @State private var licencia = false

    struct Invitacion: Codable, Identifiable { var id: String; var email: String; var rol: String; var venceEn: Date?; var link: String? }

    var body: some View {
        List {
            Section("Personas") {
                ForEach(equipo) { m in
                    HStack(spacing: 12) {
                        Text(Formato.iniciales(m.completo)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).frame(width: 40, height: 40).background(C.hundida, in: Circle())
                        VStack(alignment: .leading) {
                            Text(m.completo).estilo(.filaLista)
                            Text("\(ElegirInmobiliaria.rol(m.rol ?? "")) · \(Formato.cantidad(m.propiedades ?? 0, "propiedad", "propiedades"))").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        if estado.esDuenio && m.usuarioId != estado.usuario?.id {
                            Menu {
                                ForEach(["duenio", "agente", "lector"], id: \.self) { r in
                                    Button(ElegirInmobiliaria.rol(r)) { Task { await cambiarRol(m, r) } }
                                }
                                Divider()
                                Button("Sacar del equipo", role: .destructive) { Task { await sacar(m) } }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(C.accion) }
                        }
                    }
                }
            }
            if !invitaciones.isEmpty {
                Section("Invitaciones pendientes") {
                    ForEach(invitaciones) { i in
                        HStack {
                            VStack(alignment: .leading) { Text(i.email).estilo(.filaLista); Text(ElegirInmobiliaria.rol(i.rol)).estilo(.footnote).foregroundStyle(C.texto2) }
                            Spacer()
                            if let l = i.link.flatMap(URL.init(string:)) { ShareLink(item: l) { Image(systemName: "square.and.arrow.up") } }
                        }
                        .swipeActions { Button("Anular", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/invitaciones/\(i.id)"); await cargar() } } }
                    }
                }
            }
            Section("Licencias y ausencias") {
                ForEach(licencias) { l in
                    VStack(alignment: .leading) {
                        Text("\(l.usuarioNombre ?? "") · \(l.tipo?.capitalized ?? "Licencia")").estilo(.filaLista)
                        Text("Del \(Fecha.dia(l.desde).map { Formato.diaCompleto($0) } ?? l.desde) al \(Fecha.dia(l.hasta).map { Formato.diaCompleto($0) } ?? l.hasta)").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions { Button("Quitar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)"); await cargar() } } }
                }
                Button { licencia = true } label: { Label("Cargar una licencia", systemImage: "plus") }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Equipo")
        .toolbar { if estado.esDuenio { Button { invitando = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Invitar") } }
        .task(id: estado.version) { await cargar() }
        .alert("Invitar a alguien", isPresented: $invitando) {
            TextField("Mail", text: $mail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Como agente") { rol = "agente"; Task { await invitar() } }
            Button("Como lector") { rol = "lector"; Task { await invitar() } }
            Button("Como dueño") { rol = "duenio"; Task { await invitar() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Le llega un mail con el link para entrar.") }
        .sheet(isPresented: $licencia) { NuevaLicencia(equipo: equipo).presentationDetents([.medium]) }
    }

    private func cargar() async {
        equipo = (try? await estado.api.get("/v1/equipo")) ?? []
        if estado.esDuenio { invitaciones = (try? await estado.api.get("/v1/invitaciones")) ?? [] }
        let hoy = Formato.diaISO(Date())
        licencias = (try? await estado.api.get("/v1/licencias", query: [.init(name: "desde", value: hoy), .init(name: "hasta", value: Formato.diaISO(Date().addingTimeInterval(180 * 86400)))])) ?? []
    }

    private func invitar() async {
        struct Cuerpo: Encodable { var email: String; var rol: String }
        do {
            let i: Invitacion = try await estado.api.enviar("POST", "/v1/invitaciones", Cuerpo(email: mail, rol: rol))
            estado.avisar("Invitación mandada a \(mail)")
            mail = ""
            if let l = i.link { UIPasteboard.general.string = l }
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func cambiarRol(_ m: Miembro, _ r: String) async {
        struct Cuerpo: Encodable { var rol: String }
        let antes = m.rol ?? "agente"
        do {
            try await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: r))
            await cargar()
            estado.avisar("\(m.nombre ?? "") ahora es \(ElegirInmobiliaria.rol(r).lowercased())") {
                Task { try? await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: antes)); await cargar() }
            }
        } catch { estado.avisar(error) }
    }

    private func sacar(_ m: Miembro) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/equipo/\(m.usuarioId)")
            estado.avisar("\(m.completo) ya no está en el equipo")
            await cargar()
        } catch { estado.avisar(error) }
    }
}

/// Cargar una licencia o ausencia (la propia; el dueño, la de cualquiera).
struct NuevaLicencia: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var equipo: [Miembro]
    @State private var quien = ""
    @State private var tipo = "vacaciones"
    @State private var desde = Date()
    @State private var hasta = Date().addingTimeInterval(7 * 86400)

    var body: some View {
        NavigationStack {
            Form {
                if estado.esDuenio {
                    Picker("Quién", selection: $quien) { ForEach(equipo) { Text($0.completo).tag($0.usuarioId) } }
                }
                Picker("Tipo", selection: $tipo) { Text("Vacaciones").tag("vacaciones"); Text("Licencia").tag("licencia"); Text("Enfermedad").tag("enfermedad"); Text("Trámite").tag("tramite") }
                DatePicker("Desde", selection: $desde, displayedComponents: .date)
                DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
            }
            .navigationTitle("Licencia").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cargar") {
                        Task {
                            struct Cuerpo: Encodable { var usuarioId: String; var tipo: String; var desde: String; var hasta: String }
                            do {
                                try await estado.api.hacer("POST", "/v1/licencias", Cuerpo(usuarioId: quien.isEmpty ? (estado.usuario?.id ?? "") : quien, tipo: tipo, desde: Formato.diaISO(desde), hasta: Formato.diaISO(hasta)))
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
        }
        .onAppear { quien = estado.usuario?.id ?? "" }
    }
}

/// Integraciones: el número de WhatsApp, Mercado Libre (conectar con su hoja) y los feeds de portales.
struct Integraciones: View {
    @Environment(Estado.self) private var estado
    @State private var numero: JSONLibre?
    @State private var ml: JSONLibre?
    @State private var feeds: JSONLibre?

    var body: some View {
        List {
            Section(header: Text("WhatsApp"), footer: Text("Las consultas llegan a Mensajes y podés responder desde la app.")) {
                if let n = numero, let t = n["telefono"]?.texto ?? n["numero"]?.texto {
                    LabeledContent("Número", value: t)
                    LabeledContent("Estado", value: n["estado"]?.texto?.capitalized ?? "Conectado")
                } else {
                    Text("Todavía no conectaste tu número.").foregroundStyle(C.texto2)
                    Link("Conectar WhatsApp", destination: Api.web().appendingPathComponent("configuracion/integraciones"))
                }
            }
            Section(header: Text("Mercado Libre"), footer: Text("Publicás desde la ficha y respondés las preguntas en Mensajes.")) {
                if let m = ml, m["conectado"].map({ if case .bool(true) = $0 { return true }; return false }) == true || m["usuario"]?.texto != nil {
                    LabeledContent("Cuenta", value: m["usuario"]?.texto ?? m["apodo"]?.texto ?? "Conectada")
                    Button("Desconectar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/mercadolibre"); await cargar() } }
                } else {
                    Button("Conectar Mercado Libre") { Task { await conectarML() } }
                }
            }
            if let f = feeds {
                Section(header: Text("Portales"), footer: Text("Zonaprop, Argenprop y los demás leen tu cartera desde estos links.")) {
                    ForEach(["zonaprop", "argenprop", "properati", "inmuebles24"], id: \.self) { p in
                        if let u = f[p]?.texto ?? f["url"]?.texto {
                            HStack { Text(PublicacionPortal.nombres[p] ?? p.capitalized); Spacer(); ShareLink(item: u) { Image(systemName: "doc.on.doc") } }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Integraciones")
        .task { await cargar() }
    }

    private func cargar() async {
        numero = try? await estado.api.get("/v1/whatsapp/numero")
        ml = try? await estado.api.get("/v1/mercadolibre")
        feeds = try? await estado.api.get("/v1/inmobiliaria/feeds")
    }

    private func conectarML() async {
        struct L: Decodable { var url: String }
        guard let l: L = try? await estado.api.enviar("POST", "/v1/mercadolibre/conectar", [String: String]()), let u = URL(string: l.url) else {
            return estado.avisar("No se pudo abrir Mercado Libre.", ok: false)
        }
        if let vuelta = try? await HojaWeb().abrir(u), let c = URLComponents(url: vuelta, resolvingAgainstBaseURL: false) {
            struct Cuerpo: Encodable { var code: String; var state: String }
            if let code = c.queryItems?.first(where: { $0.name == "code" })?.value {
                try? await estado.api.hacer("POST", "/v1/mercadolibre/vuelta", Cuerpo(code: code, state: c.queryItems?.first { $0.name == "state" }?.value ?? ""))
            }
        }
        await cargar()
    }
}

/// Respuestas guardadas de WhatsApp: cargar, corregir y borrar.
struct RespuestasGuardadas: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [RespuestaGuardada] = []
    @State private var editando: RespuestaGuardada?
    @State private var nueva = false

    var body: some View {
        List {
            if lista.isEmpty { Text("Lo que escribís siempre: requisitos, horarios, cómo llegar.").foregroundStyle(C.texto2) }
            ForEach(lista) { r in
                Button { editando = r } label: {
                    VStack(alignment: .leading, spacing: 2) { Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto); Text(r.texto).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2) }
                }
                .swipeActions { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/respuestas-guardadas/\(r.id)"); await cargar() } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Respuestas guardadas")
        .toolbar { if estado.escribe { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva") } }
        .task { await cargar() }
        .sheet(item: $editando) { r in EditorTexto(titulo: r.titulo, texto: r.texto) { t, x in Task { await guardar(r.id, t, x) } } }
        .sheet(isPresented: $nueva) { EditorTexto(titulo: "", texto: "") { t, x in Task { await guardar(nil, t, x) } } }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/respuestas-guardadas")) ?? [] }

    private func guardar(_ id: String?, _ t: String, _ x: String) async {
        struct Cuerpo: Encodable { var titulo: String; var texto: String }
        do {
            if let id { try await estado.api.hacer("PUT", "/v1/respuestas-guardadas/\(id)", Cuerpo(titulo: t, texto: x)) }
            else { try await estado.api.hacer("POST", "/v1/respuestas-guardadas", Cuerpo(titulo: t, texto: x)) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

/// Un título y un texto (respuestas guardadas, notas).
struct EditorTexto: View {
    @Environment(\.dismiss) private var cerrar
    @State var titulo: String
    @State var texto: String
    var guardar: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $titulo)
                TextField("Texto", text: $texto, axis: .vertical).lineLimit(5...14)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(titulo, texto); cerrar() }.disabled(titulo.isEmpty || texto.isEmpty) }
            }
        }
    }
}

/// Proveedores (plomeros, electricistas…): los comparten todos los consorcios.
struct Proveedores: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Prov] = []
    @State private var editando: Prov?

    struct Prov: Codable, Identifiable, Hashable {
        var id: String; var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String?; var trabajos: Int?
    }

    var body: some View {
        List {
            if lista.isEmpty { Text("Los cargás una vez y los usás en todos los consorcios.").foregroundStyle(C.texto2) }
            ForEach(lista) { p in
                HStack {
                    Button { editando = p } label: {
                        VStack(alignment: .leading) { Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto); Text([p.rubro?.capitalized, p.trabajos.map { Formato.cantidad($0, "trabajo", "trabajos") }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                    Spacer()
                    if p.telefono != nil { Button { Afuera.whatsapp(p.telefono) } label: { Image("LogoWhatsApp").resizable().frame(width: 22, height: 22) }.buttonStyle(.plain) }
                }
                .swipeActions { if estado.esDuenio { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/proveedores/\(p.id)"); await cargar() } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Proveedores")
        .toolbar { if estado.escribe { Button { editando = Prov(id: "", nombre: "") } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo") } }
        .task { await cargar() }
        .sheet(item: $editando) { p in
            NavigationStack {
                FormProveedor(p: p) { x in Task { await guardar(x) } }
            }
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/proveedores", query: [.init(name: "limite", value: "500")])) ?? [] }

    private func guardar(_ p: Prov) async {
        struct Cuerpo: Encodable { var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String? }
        let c = Cuerpo(nombre: p.nombre, cuit: p.cuit?.nonEmpty, rubro: p.rubro?.nonEmpty, telefono: p.telefono?.nonEmpty, email: p.email?.nonEmpty, notas: p.notas?.nonEmpty)
        do {
            if p.id.isEmpty { try await estado.api.hacer("POST", "/v1/proveedores", c) } else { try await estado.api.hacer("PUT", "/v1/proveedores/\(p.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormProveedor: View {
    @Environment(\.dismiss) private var cerrar
    @State var p: Proveedores.Prov
    var guardar: (Proveedores.Prov) -> Void
    var body: some View {
        Form {
            TextField("Nombre", text: $p.nombre)
            Picker("Rubro", selection: Binding(get: { p.rubro ?? "" }, set: { p.rubro = $0 })) {
                Text("Sin rubro").tag("")
                ForEach(["plomeria", "electricidad", "gas", "herreria", "pintura", "limpieza", "ascensores", "cerrajeria", "albanileria", "jardineria", "otro"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            TextField("CUIT", text: Binding(get: { p.cuit ?? "" }, set: { p.cuit = $0 })).keyboardType(.numbersAndPunctuation)
            TextField("Teléfono o WhatsApp", text: Binding(get: { p.telefono ?? "" }, set: { p.telefono = $0 })).keyboardType(.phonePad)
            TextField("Mail", text: Binding(get: { p.email ?? "" }, set: { p.email = $0 })).keyboardType(.emailAddress)
            TextField("Notas", text: Binding(get: { p.notas ?? "" }, set: { p.notas = $0 }), axis: .vertical)
        }
        .navigationTitle(p.id.isEmpty ? "Proveedor nuevo" : p.nombre).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(p); cerrar() }.disabled(p.nombre.isEmpty) }
        }
    }
}

/// Objetivos del mes: los de cada persona con su avance; el dueño los carga.
struct Objetivos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Objetivo] = []
    @State private var nuevo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if lista.isEmpty { EstadoVacio(icono: "flag", titulo: "Sin objetivos este mes", texto: "Ponele una meta a cada persona y seguí el avance.", accion: estado.esDuenio ? ("Cargar objetivo", { nuevo = true }) : nil).padding(.top, 40) }
                ForEach(lista) { o in
                    TarjetaObjetivo(o: o)
                        .overlay(alignment: .topTrailing) {
                            if let n = o.agenteNombre { Text(n).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2).padding(10) }
                        }
                        .contextMenu { if estado.esDuenio { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/objetivos/\(o.id)"); await cargar() } } } }
                }
            }
            .padding(16)
        }
        .pantallaApilada("Objetivos")
        .toolbar { if estado.esDuenio { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo objetivo") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { NuevoObjetivo().presentationDetents([.medium]) }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/objetivos")) ?? [] }
}

struct NuevoObjetivo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var equipo: [Miembro] = []
    @State private var quien = ""
    @State private var metrica = "operaciones"
    @State private var meta = 5.0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quién", selection: $quien) { Text("Toda la inmobiliaria").tag(""); ForEach(equipo) { Text($0.completo).tag($0.usuarioId) } }
                Picker("Qué", selection: $metrica) { ForEach(Objetivo.metricas.keys.sorted(), id: \.self) { Text(Objetivo.metricas[$0]!.1.capitalized).tag($0) } }
                Stepper("Meta: \(Int(meta))", value: $meta, in: 1...1000)
            }
            .navigationTitle("Objetivo del mes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cargar") {
                        Task {
                            let cal = Calendar.current
                            let ini = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
                            let fin = cal.date(byAdding: DateComponents(month: 1, day: -1), to: ini)!
                            struct Cuerpo: Encodable { var agenteId: String?; var metrica: String; var meta: Double; var desde: String; var hasta: String }
                            do {
                                try await estado.api.hacer("POST", "/v1/objetivos", Cuerpo(agenteId: quien.nonEmpty, metrica: metrica, meta: meta, desde: Formato.diaISO(ini), hasta: Formato.diaISO(fin)))
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
            .task { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
        }
    }
}

/// Todas las actas de entrega y devolución.
struct ListaActas: View {
    @Environment(Estado.self) private var estado
    @State private var actas: [Acta] = []
    @State private var elegir = false

    var body: some View {
        List {
            if actas.isEmpty { Text("Hacé la recorrida de una propiedad y firmala acá mismo.").foregroundStyle(C.texto2) }
            ForEach(actas) { a in
                Button { if let p = a.propiedadId { estado.abrir(AFirmas(id: "\(p)/\(a.id)")) } } label: {
                    VStack(alignment: .leading) {
                        Text(a.propiedadTitulo ?? "Acta").estilo(.filaLista).foregroundStyle(C.texto)
                        Text("\(a.tipo == "devolucion" ? "Devolución" : "Entrega") · \(a.fecha.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "") · \(a.firmas?.count ?? 0) de 3 firmas").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Actas de entrega")
        .toolbar { if estado.escribe { Button { elegir = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva recorrida") } }
        .task { actas = (try? await estado.api.get("/v1/actas")) ?? [] }
        .sheet(isPresented: $elegir) { ElegirPropiedad { estado.abrir(AInventario(id: $0.id)) } }
    }
}

/// Las rendiciones listas para mandar (el dueño las revisa y las emite).
struct RendicionesListas: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [RendicionAPI] = []

    var body: some View {
        List {
            if lista.isEmpty { Text("Se arman solas con lo cobrado. Acá aparecen cuando están listas.").foregroundStyle(C.texto2) }
            ForEach(lista) { r in
                Button { if let c = r.contratoId { estado.abrir(ARendicion(contrato: c, id: r.id)) } } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Formato.mayuscula(ReciboVista.mes(r.periodo))).estilo(.filaLista).foregroundStyle(C.texto)
                            Text(RendicionAPI.estadoTexto(r.estado)).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Text(Formato.plata(r.neto ?? 0, r.moneda ?? "ARS")).fontWeight(.semibold)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Rendiciones")
        .task(id: estado.version) { lista = (try? await estado.api.get("/v1/rendiciones/listas")) ?? [] }
    }
}

/// La papelera (30 días): restaurar lo borrado.
struct Papelera: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        ListaGenerica(titulo: "Papelera", ruta: "/v1/papelera", icono: "trash", vacio: "La papelera está vacía.") { x in
            guard let ent = x["entidad"]?.texto, let id = x["id"]?.texto else { return [] }
            return [("Restaurar", {
                Task {
                    try? await estado.api.hacer("POST", "/v1/papelera/\(ent)/\(id)/restaurar")
                    estado.version += 1
                    estado.avisar("Restaurado")
                }
            })]
        }
    }
}

/// Revisión: lo que tu IA (Corredor en tu IA) quiere cambiar y espera tu ok.
struct Revision: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        ListaGenerica(titulo: "Revisión de la IA", ruta: "/v1/revision", icono: "checkmark.shield", vacio: "Nada para revisar.") { x in
            guard let id = x["id"]?.texto, estado.escribe else { return [] }
            struct Cuerpo: Encodable { var estado: String }
            return [("Aprobar", { Task { try? await estado.api.hacer("PATCH", "/v1/revision/\(id)", Cuerpo(estado: "aprobado")); estado.version += 1 } }),
                    ("Descartar", { Task { try? await estado.api.hacer("DELETE", "/v1/revision/\(id)"); estado.version += 1 } })]
        }
    }
}

/// El informe: visitas, consultas por origen, embudo, cierres, honorarios; y exportar a Excel.
struct Informe: View {
    @Environment(Estado.self) private var estado
    @State private var dias = 30
    @State private var inf: JSONLibre?
    @State private var exportando: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Segmentado(opciones: [(7, "7 días"), (30, "30 días"), (90, "90 días")], elegido: $dias)
                if let i = inf {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Visitas", valor: Self.num(i["totalVistas"]))
                        Cifra(etiqueta: "Contactos", valor: Self.num(i["totalContactos"]))
                        Cifra(etiqueta: "Cerradas", valor: Self.num(i["cerradas"]))
                    }
                    if case .lista(let o)? = i["origenes"] {
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "De dónde llegan")
                            VStack(spacing: 0) {
                                ForEach(Array(o.enumerated()), id: \.offset) { n, x in
                                    HStack { Text(x["origen"]?.texto ?? "—"); Spacer(); Text(Self.num(x["cantidad"])).fontWeight(.semibold) }
                                        .estilo(.subhead).padding(.horizontal, 14).frame(minHeight: 44)
                                        .overlay(alignment: .top) { if n > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                    if case .lista(let m)? = i["masVistas"] {
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "Las más vistas")
                            VStack(spacing: 0) {
                                ForEach(Array(m.prefix(8).enumerated()), id: \.offset) { n, x in
                                    Button { if let p = x["propiedadId"]?.texto { estado.abrir(AFichaPropiedad(id: p)) } } label: {
                                        HStack { Text(x["titulo"]?.texto ?? "—").foregroundStyle(C.texto); Spacer(); Text(Self.num(x["vistas"])).fontWeight(.semibold).foregroundStyle(C.texto) }
                                            .estilo(.subhead).padding(.horizontal, 14).frame(minHeight: 44).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .top) { if n > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    TituloBloque(texto: "Exportar a Excel")
                    VStack(spacing: 0) {
                        ForEach([("propiedades", "Propiedades"), ("contactos", "Contactos"), ("operaciones", "Operaciones"), ("contratos", "Contratos"), ("cobros", "Cobros")], id: \.0) { r, n in
                            Button { Task { await exportar(r) } } label: {
                                HStack { Label(n, systemImage: "tablecells"); Spacer(); Image(systemName: "square.and.arrow.down") }
                                    .estilo(.body16).foregroundStyle(C.texto).padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                        }
                    }
                    .tarjeta()
                }
            }
            .padding(16)
        }
        .pantallaApilada("Informe")
        .task(id: dias) { inf = try? await estado.api.get("/v1/informe", query: [.init(name: "dias", value: "\(dias)")]) }
        .sheet(item: Binding(get: { exportando.map { URLHoja(url: $0) } }, set: { exportando = $0?.url })) { x in ShareLink(item: x.url) { Label("Compartir \(x.url.lastPathComponent)", systemImage: "square.and.arrow.up") }.padding(40).presentationDetents([.height(160)]) }
    }

    static func num(_ v: JSONLibre?) -> String {
        if case .numero(let n)? = v { return Formato.numero(Int(n)) }
        return "—"
    }

    private func exportar(_ r: String) async {
        do {
            let d = try await estado.api.pedir("GET", "/v1/exportar/\(r)")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(r)-\(Formato.diaISO(Date())).xlsx")
            try d.write(to: u)
            exportando = u
        } catch { estado.avisar(error) }
    }
}

struct URLHoja: Identifiable { var url: URL; var id: String { url.absoluteString } }

/// Los índices de ajuste (ICL, IPC, UVA): el último valor y cuándo se actualizó.
struct Indices: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Ind] = []
    struct Ind: Codable, Identifiable { var codigo: String; var ultimoPeriodo: String?; var ultimoValor: Double?; var actualizadoEn: Date?; var id: String { codigo } }

    var body: some View {
        List(lista) { i in
            HStack {
                VStack(alignment: .leading) {
                    Text(i.codigo.uppercased()).estilo(.filaLista)
                    Text(i.ultimoPeriodo.map { "Último: \($0)" } ?? "").estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer()
                Text(i.ultimoValor.map { String(format: "%.4f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—").fontWeight(.semibold)
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .navigationTitle("Índices")
        .task { lista = (try? await estado.api.get("/v1/indices")) ?? [] }
    }
}

/// Tarifas de temporada de una propiedad.
struct Tarifas: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    var body: some View {
        ListaGenerica(titulo: "Tarifas", ruta: "/v1/propiedades/\(propiedad)/tarifas", icono: "calendar.badge.clock", vacio: "Cargá las tarifas desde la web por ahora.")
    }
}

/// Corredor en tu IA: las conexiones (Claude, ChatGPT) con permiso para leer y proponer cambios.
struct ConectarIA: View {
    var body: some View {
        ListaGenerica(titulo: "Corredor en tu IA", ruta: "/v1/ia/conexiones", icono: "sparkles", vacio: "Todavía no conectaste tu IA. Agregá Corredor como conector en Claude o ChatGPT con mcp.corredor.com.ar.")
    }
}

// MARK: - Mi web

/// Mi web: el link para compartir, la plantilla, los colores, la frase, nosotros, contacto y los
/// textos de cada barrio. Se guarda solo: guardar es publicar.
struct MiWeb: View {
    @Environment(Estado.self) private var estado
    @State private var web: String?
    @State private var marca: [String: String] = [:]
    /// La marca entera como la guarda la API (logo, `web` del editor…): PATCH la reemplaza toda, así
    /// que se manda completa con los textos cambiados encima.
    @State private var completa: [String: JSONLibre] = [:]
    @State private var barrios: [BarrioWeb] = []
    @State private var guardado: Task<Void, Never>?

    struct BarrioWeb: Codable, Identifiable { var nombre: String; var cantidad: Int?; var texto: String?; var id: String { nombre } }

    private static let plantillas = [("barrio", "Barrio", "Buscador sobre foto, destacadas, barrios."), ("costa", "Costa", "Calendario y tarifas al frente."),
                                     ("clasica", "Clásica", "Sobria, listado primero."), ("emprendimiento", "Emprendimiento", "Una web por proyecto.")]

    var body: some View {
        Form {
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
            Section("Marca") {
                ColorPicker("Color principal", selection: color("colorPrimario", 0x16443B), supportsOpacity: false)
                ColorPicker("Color de acento", selection: color("colorSecundario", 0xF2BB57), supportsOpacity: false)
                TextField("Frase de la portada", text: campo("frase", ""))
            }
            Section("Nosotros") {
                TextField("Título", text: campo("nosotrosTitulo", ""))
                TextField("Quiénes son, desde cuándo, en qué barrios trabajan.", text: campo("nosotros", ""), axis: .vertical).lineLimit(3...8)
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
        .navigationTitle("Mi web")
        .task {
            struct I: Decodable { var web: String?; var marca: [String: JSONLibre]? }
            if let i: I = try? await estado.api.get("/v1/inmobiliaria") {
                web = i.web
                completa = i.marca ?? [:]
                marca = (i.marca ?? [:]).compactMapValues { $0.texto }
            }
            barrios = (try? await estado.api.get("/v1/web/barrios")) ?? []
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

    private func programar() {
        guardado?.cancel()
        guardado = Task {
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { return }
            struct Cuerpo: Encodable { var marca: [String: JSONLibre] }
            var m = completa
            for (k, v) in marca { m[k] = .texto(v) }
            do {
                try await estado.api.hacer("PATCH", "/v1/inmobiliaria", Cuerpo(marca: m))
                completa = m
            } catch { estado.avisar(error) }
        }
    }

    private func guardarBarrio(_ b: BarrioWeb) async {
        struct Cuerpo: Encodable { var texto: String }
        try? await estado.api.hacer("PUT", "/v1/web/barrios/\(b.nombre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? b.nombre)", Cuerpo(texto: b.texto ?? ""))
        estado.avisar("Guardado el texto de \(b.nombre)")
    }
}
