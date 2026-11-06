import AppIntents
import SwiftUI
import TipKit
import UserNotifications

// MARK: - 2C Búsqueda global

/// 2C Buscar: propiedades, contactos, contratos y operaciones por grupos, mientras se escribe.
struct Buscar: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var texto: String
    @State private var resultados: [Resultado] = []
    @State private var buscando = false
    @FocusState private var foco: Bool

    /// Los tipos que devuelve la API, en el orden de los grupos del panel (lib/ui/shell/busqueda.ts).
    private static let grupos: [(String, String, String)] = [
        ("propiedad", "Propiedades", "building.2"), ("contacto", "Contactos", "person"), ("contrato", "Contratos", "doc.text"),
        ("consorcio", "Consorcios", "building.columns"), ("operacion", "Operaciones", "rectangle.split.3x1"),
        ("emprendimiento", "Emprendimientos", "building"), ("reserva", "Reservas", "hand.raised"),
        ("reserva_temporada", "Temporario", "beach.umbrella"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(C.texto3)
                    TextField("Calle, persona, contrato…", text: $texto).estilo(.body).focused($foco)
                        .submitLabel(.search).autocorrectionDisabled()
                    if !texto.isEmpty {
                        Button { texto = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }
                            .accessibilityLabel("Borrar")
                    }
                }
                .padding(.horizontal, 10).frame(height: 38)
                .background(C.hundida, in: .rect(cornerRadius: 11, style: .continuous))
                Button("Cancelar") { cerrar() }.font(Estilo.body.font).foregroundStyle(C.accion)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Secciones y acciones («cobrar», «expensas», «dominio»): lo que la app hace, también se busca.
                    let f = MasRaiz.normal(texto)
                    let secciones = f.count < 2 ? [] : MasRaiz.secciones(estado.estructura, duenio: estado.esDuenio).filter { MasRaiz.coincide($0, f) }
                    if !secciones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EN LA APP").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                                .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(secciones.prefix(6).enumerated()), id: \.element.id) { i, it in
                                    Button { if let d = Lugares.secciones[it.clave]?.1 { estado.abrir(d) } } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: Lugares.secciones[it.clave]?.0 ?? "square.grid.2x2").font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 24)
                                            Text(it.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                            Spacer()
                                            Chevron()
                                        }
                                        .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                                    }
                                    .buttonStyle(Presionable())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta(16)
                        }
                    }
                    ForEach(Self.grupos, id: \.0) { tipo, titulo, icono in
                        let items = resultados.filter { $0.tipo == tipo }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(titulo.uppercased()).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                                    .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                                        Button { abrir(x) } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 24)
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(x.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                                                    if let d = x.subtitulo { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                                                }
                                                Spacer()
                                                Chevron()
                                            }
                                            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
                                        }
                                        .buttonStyle(Presionable())
                                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                    }
                                }
                                .tarjeta(16)
                            }
                        }
                    }
                    if !buscando && texto.count >= 2 && resultados.isEmpty {
                        EstadoVacio(icono: "magnifyingglass", titulo: "No encontramos «\(texto)»", texto: "Probá con la calle, el apellido o el código.")
                            .padding(.top, 30)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { foco = true }
        .task(id: texto) {
            guard texto.count >= 2 else { resultados = []; return }
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }
            buscando = true
            resultados = (try? await estado.api.get("/v1/buscar", query: [.init(name: "q", value: texto)])) ?? []
            buscando = false
        }
    }

    private func abrir(_ x: Resultado) {
        switch x.tipo {
        case "propiedad": estado.abrir(AFichaPropiedad(id: x.id))
        case "contacto": estado.abrir(AFichaContacto(id: x.id))
        case "contrato": estado.abrir(AFichaContrato(id: x.id))
        case "operacion": estado.abrir(AFichaOperacion(id: x.id))
        // Las claves de la ficha son en singular (las de la lista, en plural, ignoran el id).
        case "emprendimiento", "consorcio": estado.abrir(ASeccion(clave: x.tipo, id: x.id))
        // Las reservas todavía no tienen ficha en la app: se abre su lista.
        case "reserva": estado.abrir(ASeccion(clave: "reservas"))
        case "reserva_temporada": estado.abrir(ASeccion(clave: "temporada"))
        default: if let r = Ruta(texto: "/\(x.tipo)/\(x.id)"), let d = r.destino { estado.abrir(d) }
        }
    }
}

// MARK: - 12A Avisos

/// 12A Avisos (con el segmentado «Avisos · Configurar»), como el centro de avisos del panel: «Para
/// hacer» o «Todo», por tipo, de a 30 con «Ver más»; cada aviso con quién lo tiene que resolver y sus
/// acciones, y las que piden texto con la hoja para escribir.
struct Avisos: View {
    @Environment(Estado.self) private var estado
    @State private var seg = 0
    @State private var vista = "para_hacer"
    @State private var tipo: String?
    @State private var avisos: [AvisoCentro]?
    @State private var enfocado: AvisoCentro?
    @State private var siguiente: String?
    @State private var noLeidos = 0
    @State private var paraHacer = 0
    @State private var cargandoMas = false
    @State private var error: ErrorApi?
    @State private var ocupado: String?
    /// La acción que pide un texto antes de mandarse (responder desde el aviso).
    @State private var escribiendo: Escribir?

    struct Escribir: Identifiable { var aviso: AvisoCentro; var accion: AvisoCentro.Accion; var id: String { aviso.id + (accion.accion ?? "") } }

    /// Lo que abre el push (`?aviso=<id>&responder=<acción>` en la web): el aviso arriba y, si pide
    /// texto, la hoja ya abierta. App/Push.swift lo deja con `Avisos.abrir(...)`.
    @MainActor static var foco: (id: String, responder: String?)?

    /// Para el push: abre los avisos con ese aviso arriba (y la hoja de respuesta si `responder`).
    @MainActor static func abrir(_ estado: Estado, aviso: String, responder: String?) {
        foco = (aviso, responder)
        estado.ir(Ruta(.inicio, AAvisos()))
    }

    static let tipos: [(String, String)] = [("consulta", "Consultas"), ("whatsapp", "WhatsApp"), ("mercadolibre", "Mercado Libre"), ("visita", "Visitas"),
                                            ("cobro", "Cobros"), ("resumen", "Resumen"), ("operacion", "Operaciones")]

    private var visibles: [AvisoCentro] {
        let l = (enfocado.map { [$0] } ?? []) + (avisos ?? []).filter { $0.id != enfocado?.id }
        return vista == "para_hacer" ? l.filter { !$0.estaHecho || $0.id == enfocado?.id } : l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Segmentado(opciones: [(0, "Avisos"), (1, "Configurar")], elegido: $seg)
                if seg == 1 {
                    ConfigAvisos.Contenido()
                } else {
                    filtros
                    contenido
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Avisos")
        .toolbar {
            if seg == 0, noLeidos > 0 {
                Button("Marcar todo leído") { Task { await todoLeido() } }
            }
        }
        .task(id: "\(estado.version)-\(vista)-\(tipo ?? "")") { await cargar() }
        .sheet(item: $escribiendo) { e in
            HojaResponderAviso(aviso: e.aviso, accion: e.accion) { t in await hacer(e.aviso, e.accion, texto: t) }
                .hojaTLW([.medium, .large])
        }
    }

    private var filtros: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ChipFiltro(texto: "Para hacer" + (paraHacer > 0 ? " \(paraHacer)" : ""), activo: vista == "para_hacer") { vista = "para_hacer" }
                ChipFiltro(texto: "Todo", activo: vista == "todo") { vista = "todo" }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.tipos, id: \.0) { t, n in
                        let (icono, _) = Self.icono(t)
                        Button { Haptico.seleccion(); tipo = tipo == t ? nil : t } label: {
                            Label(n, systemImage: icono).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                                .foregroundStyle(tipo == t ? C.sobreAccion : C.texto2)
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(tipo == t ? C.accion : C.hundida, in: Capsule())
                        }
                        .buttonStyle(Presionable())
                        .accessibilityAddTraits(tipo == t ? .isSelected : [])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contenido: some View {
        if avisos != nil {
            let l = visibles
            if l.isEmpty {
                EstadoVacio(icono: "bell", titulo: vista == "para_hacer" ? "No hay nada para hacer" : "Todavía no hay avisos",
                            texto: vista == "para_hacer" ? "Cuando entre una consulta, un WhatsApp o venza un cobro, aparece acá con la acción."
                                : "Un aviso existe sólo si hay algo que hacer, y trae la acción.",
                            accion: vista == "para_hacer" ? ("Ver todo", { vista = "todo" }) : nil,
                            secundaria: ("Configurar avisos", { seg = 1 }))
                    .padding(.top, 30)
            }
            ForEach(grupos(l), id: \.0) { titulo, lista in
                Text(titulo.uppercased()).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                    .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(lista.enumerated()), id: \.element.id) { i, a in fila(a, primera: i == 0) }
                }
                .tarjeta()
            }
            if siguiente != nil {
                Button(cargandoMas ? "Trayendo…" : "Ver más") { Task { await verMas() } }
                    .buttonStyle(BotonTexto()).disabled(cargandoMas)
            }
        } else if let error {
            EstadoError(que: "tus avisos", error: error) { Task { await cargar() } }
        } else {
            EsqueletoFilas(filas: 6)
        }
    }

    /// El título con lo que nombra (persona o propiedad) en negrita.
    private func titulo(_ a: AvisoCentro) -> Text {
        let t = a.titulo ?? ""
        let nombres = ["contactoNombre", "nombre", "propiedad", "direccion"].compactMap { a.datos?[$0]?.texto } + [a.actorNombre].compactMap { $0 }
        var base = Text(t)
        for n in nombres.filter({ $0.count > 2 }).sorted(by: { $0.count > $1.count }) {
            if let r = t.range(of: n) {
                base = Text(String(t[..<r.lowerBound])) + Text(String(t[r])).bold() + Text(String(t[r.upperBound...]))
                break
            }
        }
        if let c = a.cuerpo?.nonEmpty, a.tipo != "operacion" { base = base + Text((a.tipo == "mercadolibre" ? ": " : " · ") + c) }
        return base
    }

    /// «Sofía no respondió · 2 h» o «sin asignar» (sólo lo que pide responder y está sin hacer).
    private func quien(_ a: AvisoCentro) -> (String, Bool)? {
        guard a.accionable == true, !a.estaHecho, ["mercadolibre", "whatsapp", "consulta"].contains(a.tipo ?? "") else { return nil }
        guard let r = a.responsableNombre?.nonEmpty else { return ("sin asignar", false) }
        let hace = a.creadoEn.map { Formato.hace($0).replacingOccurrences(of: "hace ", with: "") } ?? ""
        return ("\(Charla.primerNombre(r)) \(a.tipo == "mercadolibre" ? "no la respondió" : "no respondió") · \(hace)", true)
    }

    private func cuando(_ a: AvisoCentro) -> String {
        guard let f = a.creadoEn else { return "" }
        let cal = Formato.calendario
        if cal.isDateInToday(f) { return Formato.horaDe(f) }
        if cal.isDateInYesterday(f) { return "ayer" }
        return Formato.hace(f)
    }

    private func fila(_ a: AvisoCentro, primera: Bool) -> some View {
        let (icono, tono) = Self.icono(a.tipo)
        let pendiente = a.accionable == true && !a.estaHecho
        let acciones = pendiente ? (a.acciones ?? []) : []
        let conCara = a.tipo == "operacion" && a.actorNombre != nil
        return HStack(alignment: .top, spacing: 12) {
            if conCara {
                Text(Formato.iniciales(a.actorNombre ?? "")).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.okTinta)
                    .frame(width: 38, height: 38).background(C.okFondo, in: Circle())
            } else {
                IconoTono(icono: icono, tono: tono, tam: 38)
            }
            VStack(alignment: .leading, spacing: 4) {
                Button { abrir(a) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        titulo(a).font(Estilo(tamano: 15, peso: a.estaLeido ? .regular : .semibold, relativo: .subheadline).font)
                            .foregroundStyle(!pendiente && a.tipo == "operacion" ? C.texto2 : C.texto)
                            .multilineTextAlignment(.leading)
                        if let q = quien(a) {
                            Text(q.0).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(q.1 ? C.avisoTinta : C.texto3)
                        }
                        if a.estaHecho {
                            Label("Hecho", systemImage: "checkmark").font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.okTinta)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                if !acciones.isEmpty && estado.escribe {
                    FlowLayout(espacio: 6) {
                        ForEach(Array(acciones.enumerated()), id: \.offset) { i, x in botonAccion(a, x, primera: i == 0) }
                    }
                    .padding(.top, 4)
                }
            }
            Text(cuando(a)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(a.estaLeido ? Color.clear : C.okFondo.opacity(0.35))
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contextMenu {
            if a.estaLeido {
                Button { Task { await marcarNoLeido([a.id]); await cargar() } } label: { Label("Marcar como no leído", systemImage: "envelope.badge") }
            } else {
                Button { Task { await leido(a) } } label: { Label("Marcar como leído", systemImage: "envelope.open") }
            }
            if let u = a.url, let r = Ruta(texto: u) { Button { estado.ir(r) } label: { Label("Abrir", systemImage: "arrow.up.right") } }
        }
    }

    private func botonAccion(_ a: AvisoCentro, _ x: AvisoCentro.Accion, primera: Bool) -> some View {
        Button { Task { await hacer(a, x) } } label: {
            HStack(spacing: 6) {
                if ocupado == a.id + (x.accion ?? "") { ProgressView().controlSize(.mini) }
                Text(x.titulo ?? "Ver")
            }
            .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
            .foregroundStyle(primera ? C.sobreAccion : C.accion)
            .padding(.horizontal, 14).frame(height: 34)
            .background(primera ? C.accion : C.superficie, in: Capsule())
            .overlay(Capsule().strokeBorder(primera ? Color.clear : C.linea2, lineWidth: 1))
        }
        .buttonStyle(Presionable())
        .disabled(ocupado != nil)
    }

    private func abrir(_ a: AvisoCentro) {
        if !a.estaLeido { Task { await leido(a) } }
        if let u = a.url, let r = Ruta(texto: u) { estado.ir(r) }
    }

    private func leido(_ a: AvisoCentro) async {
        do {
            try await estado.api.hacer("POST", "/v1/avisos/\(a.id)/leido")
            marcarLocal([a.id]) { $0.leido = true; $0.leidoEn = Date() }
            noLeidos = max(0, noLeidos - 1)
            estado.avisosPendientes = noLeidos
        } catch { estado.avisar(error) }
    }

    private func marcarLocal(_ ids: [String], _ f: (inout AvisoCentro) -> Void) {
        guard var l = avisos else { return }
        for i in l.indices where ids.contains(l[i].id) { f(&l[i]) }
        avisos = l
        if var e = enfocado, ids.contains(e.id) { f(&e); enfocado = e }
    }

    private func marcarNoLeido(_ ids: [String]) async {
        for id in ids {
            do { try await estado.api.hacer("DELETE", "/v1/avisos/\(id)/leido") } catch { estado.avisar(error); return }
        }
    }

    /// «Marcar todo leído» (sólo el tipo elegido, si hay uno), con Deshacer.
    private func todoLeido() async {
        let antes = (avisos ?? []).filter { !$0.estaLeido }.map(\.id)
        struct Cuerpo: Encodable { var tipos: [String] }
        marcarLocal(antes) { $0.leido = true; $0.leidoEn = Date() }
        do {
            try await estado.api.hacer("POST", "/v1/avisos/leidos", Cuerpo(tipos: tipo.map { [$0] } ?? []))
            estado.avisar(antes.count == 1 ? "Marcaste 1 aviso como leído" : "Marcaste \(antes.count) avisos como leídos") {
                Task {
                    await marcarNoLeido(antes)
                    estado.version += 1
                }
            }
            await cargar()
            await Insignias.compartidas.refrescar(estado)
        } catch {
            marcarLocal(antes) { $0.leido = false; $0.leidoEn = nil }
            estado.avisarReintentar(Estado.texto(error, si: "No se guardó")) { Task { await todoLeido() } }
        }
    }

    /// Una acción del aviso, como la hace el panel (avisos/[id]/accion): con ruta se llama a la API con
    /// su método y su cuerpo (o {"texto": …} si pide escribir); sin ruta, se abre su link. Si sale bien
    /// queda hecho (si pedía algo y no estaba hecho) o leído. Devuelve el error para la hoja.
    @discardableResult
    private func hacer(_ a: AvisoCentro, _ x: AvisoCentro.Accion, texto: String? = nil) async -> String? {
        guard let r = x.ruta?.nonEmpty else {
            if let u = x.url ?? a.url, let r = Ruta(texto: u) { estado.ir(r) }
            return nil
        }
        if x.entrada == "texto" && texto == nil {
            escribiendo = Escribir(aviso: a, accion: x)
            return nil
        }
        let cuerpo: JSONLibre
        if x.entrada == "texto" { cuerpo = .objeto(["texto": .texto(texto ?? "")]) }
        else if let c = x.cuerpo, c != .nulo { cuerpo = c }
        else { cuerpo = .objeto([:]) }
        let metodo = (x.metodo ?? "POST").uppercased()
        guard ["POST", "PUT", "PATCH", "DELETE"].contains(metodo), r.hasPrefix("/v1/") else { estado.avisar("Acción desconocida.", ok: false); return nil }
        ocupado = a.id + (x.accion ?? "")
        defer { ocupado = nil }
        do {
            _ = try await estado.api.pedir(metodo, r, cuerpo: Api.codificador.encode(cuerpo))
            if a.accionable == true && !a.estaHecho { try? await estado.api.hacer("POST", "/v1/avisos/\(a.id)/hecho") }
            else { try? await estado.api.hacer("POST", "/v1/avisos/\(a.id)/leido") }
            marcarLocal([a.id]) { $0.hecho = true; $0.hechoEn = Date(); $0.leido = true; $0.leidoEn = Date() }
            escribiendo = nil
            if let u = a.url, let ruta = Ruta(texto: u) {
                estado.sugerir("\(x.titulo ?? "Listo") · listo", "Ver") { estado.ir(ruta) }
            } else { estado.avisar("\(x.titulo ?? "Listo") · listo") }
            await Insignias.compartidas.refrescar(estado)
            return nil
        } catch {
            let t = Estado.texto(error, si: "No salió. Probá de nuevo.")
            if escribiendo != nil { return t }
            estado.avisarReintentar(t) { Task { await hacer(a, x, texto: texto) } }
            return t
        }
    }

    private func cargar() async {
        do {
            var q: [URLQueryItem] = [.init(name: "limite", value: "30"), .init(name: "vista", value: vista)]
            if let tipo { q.append(.init(name: "tipo", value: tipo)) }
            let l: PaginaAvisos = try await estado.api.get("/v1/avisos", query: q)
            avisos = l.avisos
            siguiente = l.siguiente
            noLeidos = l.noLeidos ?? 0
            paraHacer = l.paraHacer ?? 0
            estado.avisosPendientes = noLeidos
            error = nil
            if let f = Self.foco {
                Self.foco = nil
                var a: AvisoCentro? = l.avisos.first { $0.id == f.id }
                if a == nil { a = try? await estado.api.get("/v1/avisos/\(f.id)") }
                if let a {
                    if !l.avisos.contains(where: { $0.id == a.id }) { enfocado = a }
                    if let r = f.responder, !a.estaHecho, let x = a.acciones?.first(where: { $0.accion == r }) { escribiendo = Escribir(aviso: a, accion: x) }
                }
            }
        } catch let e as ErrorApi { if avisos == nil { error = e } } catch {}
    }

    private func verMas() async {
        guard let s = siguiente else { return }
        cargandoMas = true
        defer { cargandoMas = false }
        var q: [URLQueryItem] = [.init(name: "limite", value: "30"), .init(name: "vista", value: vista), .init(name: "antes", value: s)]
        if let tipo { q.append(.init(name: "tipo", value: tipo)) }
        do {
            let l: PaginaAvisos = try await estado.api.get("/v1/avisos", query: q)
            avisos = (avisos ?? []) + l.avisos
            siguiente = l.siguiente
        } catch {
            estado.avisarReintentar("No pudimos traer más") { Task { await verMas() } }
        }
    }

    private func grupos(_ l: [AvisoCentro]) -> [(String, [AvisoCentro])] {
        let cal = Formato.calendario
        var hoy: [AvisoCentro] = [], ayer: [AvisoCentro] = [], antes: [AvisoCentro] = []
        for a in l {
            let f = a.creadoEn ?? Date()
            if cal.isDateInToday(f) { hoy.append(a) } else if cal.isDateInYesterday(f) { ayer.append(a) } else { antes.append(a) }
        }
        return [("Hoy", hoy), ("Ayer", ayer), ("Antes", antes)].filter { !$0.1.isEmpty }
    }

    /// Ícono y tono de cada tipo (cobro rojo, Mercado Libre y visitas oro, la web azul, el resto verde).
    static func icono(_ tipo: String?) -> (String, Tono) {
        switch tipo {
        case "whatsapp": return ("bubble.left", .verde)
        case "mercadolibre": return ("storefront", .oro)
        case "consulta", "tasacion": return ("globe", .azul)
        case "visita": return ("calendar", .oro)
        case "cobro": return ("dollarsign.circle", .rojo)
        case "resumen": return ("sun.max", .neutro)
        case "operacion": return ("rectangle.split.3x1", .verde)
        case "mira": return ("viewfinder", .oro)
        default: return ("bell", .neutro)
        }
    }
}

/// La hoja para responder desde el aviso (el WhatsApp o la pregunta de Mercado Libre): con la
/// sugerencia ya escrita, la ayuda de ML y el error en la misma hoja.
struct HojaResponderAviso: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(Estado.self) private var estado
    var aviso: AvisoCentro
    var accion: AvisoCentro.Accion
    var mandar: (String) async -> String?
    @State private var texto = ""
    @State private var error: String?
    @State private var mandando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grabber().frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                IconoTono(icono: Avisos.icono(aviso.tipo).0, tono: .verde, tam: 36)
                Text(aviso.titulo ?? "Responder").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            }
            if let c = aviso.cuerpo?.nonEmpty { Text(c).estilo(.subhead).foregroundStyle(C.texto2) }
            Etiquetado("Tu respuesta") {
                TextField("", text: $texto, axis: .vertical).lineLimit(4...8).campoCorredor()
            }
            if let error { MensajeError(texto: error) }
            else if aviso.tipo == "mercadolibre" { Text("Mercado Libre no deja poner teléfonos.").estilo(.footnote).foregroundStyle(C.texto3) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                if let u = aviso.url, let r = Ruta(texto: u) { Button("Abrir") { cerrar(); estado.ir(r) }.buttonStyle(BotonSecundario()) }
                Button(mandando ? "Mandando…" : (accion.titulo ?? "Responder")) {
                    Task {
                        mandando = true
                        error = await mandar(texto.trimmingCharacters(in: .whitespacesAndNewlines))
                        mandando = false
                    }
                }
                .buttonStyle(BotonPrincipal())
                .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mandando)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .onAppear { texto = aviso.datos?["sugerencia"]?.texto ?? "" }
    }
}

// MARK: - 12B Configurar avisos

/// 12B Configurar avisos: este dispositivo (probar, apagar), por tipo al celular y por mail, y el
/// horario de silencio.
struct ConfigAvisos: View {
    var body: some View {
        ScrollView { Contenido().padding(.horizontal, 16).padding(.vertical, 8) }
            .pantallaApilada("Configurar avisos")
    }

    struct Vista: Codable, Equatable {
        struct Canales: Codable, Hashable { var tipo: String; var nombre: String?; var push: Bool; var mail: Bool; var sinPush: Bool? }
        struct Silencio: Codable, Equatable { var activo: Bool; var desde: Int; var hasta: Int; var domingos: Bool }
        var tipos: [Canales]
        var silencio: Silencio
    }

    /// Apagados a mano en este iPhone (App/Estado no vuelve a registrar el token si está prendido).
    static var apagadosAca: Bool {
        get { UserDefaults.standard.bool(forKey: "avisosApagadosAca") }
        set { UserDefaults.standard.set(newValue, forKey: "avisosApagadosAca") }
    }

    struct Contenido: View {
        @Environment(Estado.self) private var estado
        @State private var v: Vista?
        @State private var error: ErrorApi?
        @State private var permiso: UNAuthorizationStatus?
        @State private var apagados = ConfigAvisos.apagadosAca
        @State private var horario = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                dispositivo
                if let v {
                    tabla(v)
                    silencio(v)
                } else if let error {
                    EstadoError(que: "tus avisos", error: error) { Task { await cargar() } }
                } else {
                    EsqueletoFilas(filas: 6)
                }
            }
            .task { await cargar() }
            .sheet(isPresented: $horario) {
                if let s = v?.silencio {
                    HorarioSilencio(desde: s.desde, hasta: s.hasta, domingos: s.domingos) { d, h, dom in
                        guard var n = v else { return }
                        n.silencio = .init(activo: true, desde: d, hasta: h, domingos: dom)
                        guardar(n)
                    }
                    .hojaTLW([.medium])
                }
            }
        }

        private var dispositivo: some View {
            let activo = permiso == .authorized || permiso == .provisional || permiso == .ephemeral
            let texto: String = permiso == .denied ? "Están bloqueados en este dispositivo."
                : (activo && !apagados ? "Llegan a este dispositivo." : "Activalos para que lleguen a este dispositivo.")
            return HStack(spacing: 12) {
                IconoTono(icono: activo && !apagados ? "bell.badge" : "bell.slash", tono: activo && !apagados ? .verde : .neutro, tam: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avisos en este dispositivo").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(texto).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
                if permiso == .denied {
                    Button("Ver cómo") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.buttonStyle(BotonTonal())
                } else if !activo || apagados {
                    Button("Activar") { Task { await activar() } }.buttonStyle(BotonTonal())
                } else {
                    VStack(spacing: 6) {
                        Button("Probar") { Task { await probar() } }.buttonStyle(BotonTonal())
                        Button("Apagar") { Task { await apagar() } }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.error)
                    }
                }
            }
            .padding(14).tarjeta()
        }

        private func tabla(_ v: Vista) -> some View {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("Celular").frame(width: 58)
                    Text("Mail").frame(width: 58)
                }
                .font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityHidden(true)
                ForEach(Array(v.tipos.enumerated()), id: \.element.tipo) { i, c in
                    HStack(spacing: 0) {
                        Text(c.nombre ?? c.tipo).font(Estilo(tamano: 16, peso: .medium, relativo: .body).font).foregroundStyle(C.texto)
                        Spacer()
                        if c.sinPush == true { Color.clear.frame(width: 58, height: 1) } else { casilla(c.push, "\(c.nombre ?? c.tipo) por celular") { tocar(i, push: true) } }
                        casilla(c.mail, "\(c.nombre ?? c.tipo) por mail") { tocar(i, push: false) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 54)
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
            }
            .tarjeta()
        }

        private func casilla(_ on: Bool, _ etiqueta: String, _ hacer: @escaping () -> Void) -> some View {
            Button { Haptico.seleccion(); hacer() } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 24))
                    .foregroundStyle(on ? C.accion : C.texto3).frame(width: 58, height: 44)
            }
            .buttonStyle(Presionable())
            .accessibilityLabel(etiqueta)
            .accessibilityAddTraits(on ? .isSelected : [])
        }

        private func silencio(_ v: Vista) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill").font(.system(size: 22)).foregroundStyle(C.oro)
                Button { horario = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silencio de \(v.silencio.desde) a \(v.silencio.hasta)").font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                        Text(Formato.sinViudas((v.silencio.domingos ? "y domingos. " : "") + "Lo urgente espera a la mañana.")).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                Toggle("Silencio", isOn: Binding(get: { v.silencio.activo }, set: { n in
                    guard var x = self.v else { return }
                    x.silencio.activo = n
                    guardar(x)
                })).labelsHidden().tint(Color(hex: 0x2F9E6F))
            }
            .padding(14).tarjeta()
        }

        private func tocar(_ i: Int, push: Bool) {
            guard var x = v, x.tipos.indices.contains(i) else { return }
            if push { x.tipos[i].push.toggle() } else { x.tipos[i].mail.toggle() }
            guardar(x)
        }

        /// Se ve al instante y se guarda; si falla, vuelve como estaba y avisa.
        private func guardar(_ nuevo: Vista) {
            let antes = v
            v = nuevo
            Task {
                do { try await estado.api.hacer("PUT", "/v1/avisos/preferencias", nuevo) } catch {
                    v = antes
                    estado.avisar(Estado.texto(error, si: "No se guardó"), ok: false)
                }
            }
        }

        private func cargar() async {
            permiso = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            do {
                v = try await estado.api.get("/v1/avisos/preferencias")
                error = nil
            } catch let e as ErrorApi { if v == nil { error = e } } catch {}
        }

        private func activar() async {
            ConfigAvisos.apagadosAca = false
            apagados = false
            await estado.pedirPermisoPush()
            permiso = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }

        private func probar() async {
            do {
                try await estado.api.hacer("POST", "/v1/push/prueba")
                estado.avisar("Mandamos uno de prueba")
            } catch { estado.avisar("No salió la prueba", ok: false) }
        }

        private func apagar() async {
            guard let t = estado.tokenPush else {
                ConfigAvisos.apagadosAca = true
                apagados = true
                return
            }
            do {
                try await estado.api.hacer("DELETE", "/v1/push/dispositivos/\(t)")
                ConfigAvisos.apagadosAca = true
                apagados = true
                estado.avisar("Este dispositivo ya no recibe avisos") {
                    Task {
                        ConfigAvisos.apagadosAca = false
                        apagados = false
                        await estado.registrarTokenPush(t)
                    }
                }
            } catch { estado.avisar(error) }
        }
    }
}

/// El horario de silencio: desde, hasta y los domingos.
struct HorarioSilencio: View {
    @Environment(\.dismiss) private var cerrar
    @State var desde: Int
    @State var hasta: Int
    @State var domingos: Bool
    var guardar: (Int, Int, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("Horario de silencio", systemImage: "moon").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Los avisos al celular esperan a que termine. El centro de avisos los guarda igual.")).estilo(.subhead).foregroundStyle(C.texto2)
            HStack(spacing: 12) {
                Etiquetado("Desde") { Picker("Desde", selection: $desde) { ForEach(0..<24, id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.menu) }
                Etiquetado("Hasta") { Picker("Hasta", selection: $hasta) { ForEach(0..<24, id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.menu) }
            }
            Toggle("Los domingos, todo el día", isOn: $domingos).estilo(.body16).tint(Color(hex: 0x2F9E6F))
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button("Guardar") { guardar(desde, hasta, domingos); cerrar() }.buttonStyle(BotonPrincipal())
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

// MARK: - 13A Perfil

/// 13A Perfil: datos propios, inmobiliarias, Face ID, accesos, lo que antes «quedaba en la web» (ahora
/// todo nativo, en «Todo») y borrar la cuenta, como pide Apple.
struct Perfil: View {
    @Environment(Estado.self) private var estado
    @AppStorage("tema") private var tema = "sistema"
    @State private var faceID = false
    @State private var editando = false
    @State private var borrando = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TipView(ConsejoSiri()).tipBackground(C.superficie)
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline).frame(maxWidth: .infinity)
                Button { editando = true } label: {
                    HStack(spacing: 14) {
                        Text(Formato.iniciales(estado.usuario?.completo ?? "")).font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font)
                            .foregroundStyle(C.oro).frame(width: 60, height: 60).background(C.verde700, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(estado.usuario?.completo ?? "").font(Estilo(tamano: 19, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                            Text(estado.usuario?.email ?? "").estilo(.texto14).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Chevron()
                    }
                    .padding(14).tarjeta()
                }
                .buttonStyle(Presionable())

                VStack(alignment: .leading, spacing: 6) {
                    Text("INMOBILIARIAS").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array((estado.sesion?.inmobiliarias ?? []).enumerated()), id: \.element.id) { i, m in
                            Button {
                                guard m.id != estado.sesion?.inmobiliariaId else { return }
                                Task {
                                    do {
                                        try await estado.elegir(m)
                                        estado.avisar("Estás en \(m.nombre) como \(ElegirInmobiliaria.rol(m.rol).lowercased())")
                                    } catch { estado.avisar(error) }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(m.nombre.prefix(1))).font(Estilo.headline.font).foregroundStyle(C.texto)
                                        .frame(width: 36, height: 36).background(C.hundida, in: .rect(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(m.nombre).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                                        Text(ElegirInmobiliaria.rol(m.rol)).estilo(.footnote).foregroundStyle(C.texto2)
                                    }
                                    Spacer()
                                    if m.id == estado.sesion?.inmobiliariaId { Image(systemName: "checkmark").foregroundStyle(C.accion) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58).contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                }

                VStack(spacing: 0) {
                    Toggle(isOn: $faceID) {
                        Label { Text("Desbloquear con Face ID").estilo(.body16) } icon: { Image(systemName: "faceid").foregroundStyle(C.accion) }
                    }
                    .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 14).frame(minHeight: 54)
                    .onChange(of: faceID) { _, n in estado.conFaceID = n }
                    filaTema
                    ForEach(Self.accesos, id: \.1) { icono, texto, destino in
                        Rectangle().fill(C.linea).frame(height: 0.5)
                        fila(icono, texto) { estado.abrir(destino) }
                    }
                }
                .tarjeta()

                VStack(spacing: 0) {
                    Button("Cerrar sesión") { Task { await estado.salir() } }
                        .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    Rectangle().fill(C.linea).frame(height: 0.5)
                    Button("Borrar mi cuenta") { borrando = true }
                        .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.error)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .tarjeta()
                Text(Formato.sinViudas("Al borrar tu cuenta se eliminan tus datos personales. Las operaciones y contratos quedan en la inmobiliaria."))
                    .estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Text("Corredor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .pantallaApilada("Perfil")
        .onAppear { faceID = estado.conFaceID }
        .sheet(isPresented: $editando) { EditarPerfil().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $borrando) { BorrarCuenta().presentationDetents([.medium]) }
    }

    private static let accesos: [(String, String, AnyHashable)] = [
        ("person.2", "Contactos", AContactos()), ("rectangle.split.3x1", "Operaciones", AOperaciones()),
        ("doc.text", "Contratos y cobranzas", ACobranzas()), ("checklist", "Actas de entrega", ASeccion(clave: "inventarios")),
        ("flag", "Objetivo del mes", ASeccion(clave: "objetivos")), ("bell", "Avisos", AAvisos()),
        ("signature", "Firma y sesiones abiertas", ASeccion(clave: "firma")),
        ("gearshape", "Configuración, consorcios e informes", ASeccion(clave: "mas")),
    ]

    private var filaTema: some View {
        VStack(spacing: 0) {
            Rectangle().fill(C.linea).frame(height: 0.5)
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                Text("Apariencia").estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Picker("Apariencia", selection: $tema) {
                    Text("Como el iPhone").tag("sistema"); Text("Claro").tag("claro"); Text("Oscuro").tag("oscuro")
                }
                .pickerStyle(.menu).tint(C.texto2)
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
        }
    }

    private func fila(_ icono: String, _ texto: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                Text(texto).estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
    }
}

/// Teléfono y WhatsApp propios (salen en la web y en las fichas que mandás).
struct EditarPerfil: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var telefono = ""
    @State private var whatsapp = ""
    @State private var guardando = false

    struct Datos: Codable { var telefono: String?; var whatsapp: String? }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tus datos").estilo(.titulo)
            Text("Tu nombre y tu mail vienen de tu cuenta de Apple, Google o tu mail. El teléfono sale en tu web y en las fichas.")
                .estilo(.subhead).foregroundStyle(C.texto2)
            Etiquetado("Teléfono") { TextField("+54 9 11 4823-1190", text: $telefono).keyboardType(.phonePad).campoCorredor() }
            Etiquetado("WhatsApp") { TextField("+54 9 11 4823-1190", text: $whatsapp).keyboardType(.phonePad).campoCorredor() }
            Button("Guardar") {
                guardando = true
                Task {
                    do {
                        try await estado.api.hacer("PATCH", "/v1/perfil", Datos(telefono: telefono.nonEmpty, whatsapp: whatsapp.nonEmpty))
                        estado.avisar("Guardado")
                        cerrar()
                    } catch { estado.avisar(error) }
                    guardando = false
                }
            }
            .buttonStyle(BotonPrincipal()).disabled(guardando)
            Spacer()
        }
        .padding(20)
        .background(C.fondo)
        .task {
            if let d: Datos = try? await estado.api.get("/v1/perfil") {
                telefono = d.telefono ?? ""
                whatsapp = d.whatsapp ?? ""
            }
        }
    }
}

/// Borrar la cuenta (lo pide Apple): se confirma escribiendo BORRAR.
struct BorrarCuenta: View {
    @Environment(Estado.self) private var estado
    @State private var texto = ""
    @State private var borrando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Borrás tu cuenta?").estilo(.titulo)
            Text(Formato.sinViudas("Se eliminan tu nombre, tu mail, tu teléfono y tus sesiones. Las operaciones, contratos y conversaciones quedan en la inmobiliaria, sin tu nombre. Esto no se puede deshacer."))
                .estilo(.subhead).foregroundStyle(C.texto2)
            Link("Términos y privacidad", destination: Api.web().appendingPathComponent("terminos")).font(Estilo.subheadFuerte.font)
            TextField("Escribí BORRAR", text: $texto).textInputAutocapitalization(.characters).campoCorredor()
            Button("Borrar mi cuenta") {
                borrando = true
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/auth/cuenta")
                        await estado.salir()
                    } catch { estado.avisar(error) }
                    borrando = false
                }
            }
            .buttonStyle(BotonDestructivo()).disabled(texto != "BORRAR" || borrando)
            Spacer()
        }
        .padding(20)
        .background(C.fondo)
    }
}
