import SwiftUI

/// 2C Buscar en todo (el ⌘K del panel, pantalla entera en el celular; lib/ui/shell/Buscador.svelte): los
/// filtros por tipo, los resultados agrupados con lo escrito resaltado, las acciones que se pueden
/// escribir («registrar cobro», «mira»), la acción rápida de cada resultado (mantener apretado o deslizar:
/// mandar la ficha, escribirle, registrar el cobro), los recientes y las secciones de la app.
struct BuscarTodo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var texto: String
    @State private var filtro = ""
    @State private var resultados: [Resultado] = []
    @State private var buscando = false
    @State private var fallo = false
    @State private var recientes: [Reciente] = BuscarTodo.leerRecientes()
    @FocusState private var foco: Bool

    /// Un resultado abierto hace poco (los últimos 5).
    struct Reciente: Codable, Hashable, Identifiable {
        var tipo: String
        var id: String
        var titulo: String
    }

    /// Los tipos que devuelve la API, en el orden de los grupos del panel (busqueda.ts · TIPOS).
    static let grupos: [(String, String, String)] = [
        ("propiedad", "Propiedades", "building.2"), ("contacto", "Contactos", "person"), ("contrato", "Contratos", "doc.text"),
        ("consorcio", "Consorcios", "building.columns"), ("operacion", "Operaciones", "rectangle.split.3x1"),
        ("emprendimiento", "Emprendimientos", "building"), ("reserva", "Reservas", "bookmark"),
        ("reserva_temporada", "Temporario", "beach.umbrella"),
    ]
    static let filtros: [(String, String)] = [("", "Todo"), ("propiedad", "Propiedades"), ("contacto", "Contactos"), ("contrato", "Contratos"),
                                              ("consorcio", "Consorcios"), ("accion", "Acciones")]

    /// Lo que se puede hacer desde la búsqueda (busqueda.ts · ACCIONES).
    struct Accion: Identifiable {
        var clave: String
        var texto: String
        var icono: String
        var palabras: String
        var id: String { clave }
    }
    static let acciones: [Accion] = [
        Accion(clave: "cobro", texto: "Registrar cobro", icono: "dollarsign.circle", palabras: "registrar cobro pago cobranza"),
        Accion(clave: "propiedad", texto: "Cargar propiedad", icono: "house", palabras: "cargar nueva propiedad alta"),
        Accion(clave: "mira", texto: "Captar con MIRA", icono: "viewfinder", palabras: "mira cartel foto captar"),
        Accion(clave: "visita", texto: "Agendar visita", icono: "calendar.badge.plus", palabras: "agendar visita cita"),
        Accion(clave: "contacto", texto: "Nuevo contacto", icono: "person.badge.plus", palabras: "nuevo contacto interesado persona"),
        Accion(clave: "inicio", texto: "Ir a Inicio", icono: "house", palabras: "ir inicio hoy"),
        Accion(clave: "propiedades", texto: "Ir a Propiedades", icono: "building.2", palabras: "ir propiedades cartera"),
        Accion(clave: "agenda", texto: "Ir a Agenda", icono: "calendar", palabras: "ir agenda calendario"),
    ]

    /// Las acciones que coinciden con lo escrito (todas las palabras, como prefijos).
    static func accionesPara(_ q: String) -> [Accion] {
        let palabras = MasRaiz.normal(q).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !palabras.isEmpty else { return [] }
        return acciones.filter { a in
            let t = MasRaiz.normal(a.texto + " " + a.palabras).split(separator: " ").map(String.init)
            return palabras.allSatisfy { p in t.contains { $0.hasPrefix(p) } }
        }
    }

    private var q: String { texto.trimmingCharacters(in: .whitespaces) }
    /// Dos letras, o un número solo (el código o el número de la propiedad).
    private var buscable: Bool { q.count >= 2 || (!q.isEmpty && q.allSatisfy(\.isNumber)) }

    private var accionesVisibles: [Accion] {
        guard filtro.isEmpty || filtro == "accion" else { return [] }
        let base = q.isEmpty ? (filtro == "accion" ? Self.acciones : []) : Self.accionesPara(q)
        return estado.escribe ? base : base.filter { ["inicio", "propiedades", "agenda"].contains($0.clave) }
    }

    private var sinResultados: [String] {
        guard q.count >= 2, !buscando, !fallo else { return [] }
        return Self.filtros.filter { f in !f.0.isEmpty && f.0 != "accion" && !resultados.contains(where: { r in r.tipo == f.0 }) }.map { f in f.1 }
    }

    var body: some View {
        VStack(spacing: 12) {
            barra
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.filtros, id: \.0) { f in ChipFiltro(texto: f.1, activo: filtro == f.0) { filtro = f.0 } }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            ScrollView { lista.padding(.bottom, 30) }
                .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { foco = true }
        .task(id: texto) {
            guard buscable else { resultados = []; fallo = false; buscando = false; return }
            buscando = true
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            do {
                resultados = try await estado.api.get("/v1/buscar", query: [.init(name: "q", value: q)])
                fallo = false
            } catch is CancellationError {
                return
            } catch {
                fallo = true
            }
            buscando = false
        }
    }

    private var barra: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(C.texto3)
                TextField("Propiedad, contacto, contrato…", text: $texto).estilo(.body).focused($foco)
                    .submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel("Buscar en Corredor")
                if !texto.isEmpty {
                    Button { texto = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }
                        .accessibilityLabel("Borrar")
                }
            }
            .padding(.horizontal, 10).frame(height: 38)
            .background(C.hundida, in: .rect(cornerRadius: 11, style: .continuous))
            Button("Cancelar") { cerrar() }.font(Estilo.body.font).foregroundStyle(C.accion)
        }
    }

    @ViewBuilder
    private var lista: some View {
        VStack(alignment: .leading, spacing: 18) {
            if fallo {
                Label("No pudimos buscar. Revisá la conexión y probá de nuevo.", systemImage: "exclamationmark.icloud")
                    .estilo(.footnote).foregroundStyle(C.errorTinta).padding(.horizontal, 4)
            }
            if q.isEmpty && filtro != "accion" && !recientes.isEmpty { bloqueRecientes }
            if filtro.isEmpty { seccionesApp }
            ForEach(Self.grupos, id: \.0) { tipo, titulo, icono in
                let items = resultados.filter { $0.tipo == tipo && (filtro.isEmpty || filtro == tipo) }
                if !items.isEmpty { grupo(titulo, icono, items) }
            }
            if !accionesVisibles.isEmpty { bloqueAcciones }
            if buscable && !buscando && !fallo && resultados.isEmpty && accionesVisibles.isEmpty {
                EstadoVacio(icono: "magnifyingglass", titulo: "No encontramos «\(q)»", texto: "Probá con la calle, el apellido o el número de la propiedad.")
                    .padding(.top, 30)
            } else if !sinResultados.isEmpty && !resultados.isEmpty && filtro.isEmpty {
                Text("Sin resultados en \(sinResultados.joined(separator: ", "))").estilo(.footnote).foregroundStyle(C.texto3).padding(.horizontal, 4)
            }
        }
    }

    private func encabezado(_ t: String) -> some View {
        Text(t.uppercased()).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
    }

    private var bloqueRecientes: some View {
        VStack(alignment: .leading, spacing: 6) {
            encabezado("Recientes")
            VStack(spacing: 0) {
                ForEach(Array(recientes.enumerated()), id: \.element.id) { i, r in
                    Button { abrir(Resultado(id: r.id, tipo: r.tipo, titulo: r.titulo, subtitulo: nil)) } label: {
                        filaSimple("clock.arrow.circlepath", r.titulo)
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
        }
    }

    /// Secciones y herramientas de la app («cobrar», «expensas», «dominio»): lo que la app hace, también se busca.
    @ViewBuilder
    private var seccionesApp: some View {
        let f = MasRaiz.normal(texto)
        let secciones = f.count < 2 ? [] : MasRaiz.secciones(estado.estructura, duenio: estado.esDuenio).filter { MasRaiz.coincide($0, f) }
        if !secciones.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                encabezado("En la app")
                VStack(spacing: 0) {
                    ForEach(Array(secciones.prefix(6).enumerated()), id: \.element.id) { i, it in
                        Button { if let d = Lugares.secciones[it.clave]?.1 { estado.abrir(d) } } label: {
                            filaSimple(Lugares.secciones[it.clave]?.0 ?? "square.grid.2x2", it.nombre)
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta(16)
            }
        }
    }

    private var bloqueAcciones: some View {
        VStack(alignment: .leading, spacing: 6) {
            encabezado("Acciones")
            VStack(spacing: 0) {
                ForEach(Array(accionesVisibles.enumerated()), id: \.element.id) { i, a in
                    Button { hacer(a) } label: { filaSimple(a.icono, a.texto) }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
        }
    }

    private func filaSimple(_ icono: String, _ t: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 24)
            Text(t).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
            Spacer()
            Chevron()
        }
        .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
    }

    private func grupo(_ titulo: String, _ icono: String, _ items: [Resultado]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            encabezado(titulo)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                    filaResultado(x, icono)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
        }
    }

    private func filaResultado(_ x: Resultado, _ icono: String) -> some View {
        let rapida = Self.rapida(x.tipo)
        return Button { abrir(x) } label: {
            HStack(spacing: 12) {
                if x.tipo == "contacto" {
                    AvatarIniciales(nombre: x.titulo, tam: 34, fondo: Tono.azul.fondo, tinta: Tono.azul.tinta)
                } else {
                    Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 34)
                }
                VStack(alignment: .leading, spacing: 0) {
                    resaltado(x.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                    if let d = x.subtitulo { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                }
                Spacer()
                if rapida != nil && estado.escribe {
                    Button { hacerRapida(x) } label: {
                        Image(systemName: rapida?.1 ?? "bolt").font(.system(size: 16, weight: .semibold)).foregroundStyle(C.accion).frame(width: 40, height: 44)
                    }
                    .accessibilityLabel(rapida?.0 ?? "")
                } else {
                    Chevron()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .contextMenu {
            Button { abrir(x) } label: { Label("Abrir", systemImage: "arrow.up.right") }
            if let r = rapida, estado.escribe { Button { hacerRapida(x) } label: { Label(r.0, systemImage: r.1) } }
        }
    }

    /// Lo escrito subrayado en oro al principio de cada palabra («Gorr|iti 4820»).
    private func resaltado(_ titulo: String) -> Text {
        let palabras = MasRaiz.normal(q).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !$0.isEmpty }
        guard !palabras.isEmpty else { return Text(titulo) }
        var t = Text("")
        var palabra = ""
        func cerrarPalabra(_ w: String) {
            guard !w.isEmpty else { return }
            if let p = palabras.first(where: { MasRaiz.normal(w).hasPrefix($0) }), p.count <= w.count {
                t = t + Text(String(w.prefix(p.count))).underline(true, color: C.oro).bold() + Text(String(w.dropFirst(p.count)))
            } else {
                t = t + Text(w)
            }
        }
        for ch in titulo {
            if ch.isLetter || ch.isNumber { palabra.append(ch) } else {
                cerrarPalabra(palabra)
                palabra = ""
                t = t + Text(String(ch))
            }
        }
        cerrarPalabra(palabra)
        return t
    }

    /// La acción rápida de cada tipo (busqueda.ts · rapida).
    static func rapida(_ tipo: String) -> (String, String)? {
        switch tipo {
        case "propiedad": return ("Mandar la ficha por WhatsApp", "paperplane")
        case "contacto": return ("Escribirle por WhatsApp", "bubble.left")
        case "contrato": return ("Registrar cobro", "dollarsign.circle")
        default: return nil
        }
    }

    private func hacerRapida(_ x: Resultado) {
        recordar(x)
        switch x.tipo {
        case "propiedad": estado.abrir(AMandarPropiedad(id: x.id))
        case "contacto":
            Task {
                struct T: Decodable { var telefono: String? }
                do {
                    let c: T = try await estado.api.get("/v1/contactos/\(x.id)")
                    if c.telefono?.nonEmpty == nil { estado.avisar("Este contacto no tiene teléfono.", ok: false) } else { Afuera.whatsapp(c.telefono) }
                } catch { estado.avisar(error) }
            }
        case "contrato": estado.abrir(ARegistrarCobro(contrato: x.id))
        default: abrir(x)
        }
    }

    private func hacer(_ a: Accion) {
        switch a.clave {
        case "cobro": estado.abrir(ARegistrarCobro())
        case "propiedad": estado.abrir(AAltaPropiedad())
        case "mira": estado.miraAbierta = true
        case "visita": estado.hojaRapida = .visita
        case "contacto": estado.hojaRapida = .contacto
        case "inicio":
            estado.pilas[.inicio] = NavigationPath()
            estado.pestana = .inicio
        case "propiedades": estado.ir(Ruta(.propiedades))
        case "agenda": estado.abrir(AAgendaDia())
        default: break
        }
    }

    private func abrir(_ x: Resultado) {
        recordar(x)
        switch x.tipo {
        case "propiedad": estado.abrir(AFichaPropiedad(id: x.id))
        case "contacto": estado.abrir(AFichaContacto(id: x.id))
        case "contrato": estado.abrir(AFichaContrato(id: x.id))
        case "operacion": estado.abrir(AFichaOperacion(id: x.id))
        // Las claves de la ficha son en singular (las de la lista, en plural, ignoran el id).
        case "emprendimiento", "consorcio": estado.abrir(ASeccion(clave: x.tipo, id: x.id))
        case "reserva": estado.abrir(AReserva(id: x.id))
        case "reserva_temporada": estado.abrir(AReservaTemporada(id: x.id))
        default: if let r = Ruta(texto: "/\(x.tipo)/\(x.id)"), let d = r.destino { estado.abrir(d) }
        }
    }

    // MARK: Recientes

    private static let claveRecientes = "corredor_recientes"

    static func leerRecientes() -> [Reciente] {
        guard let d = UserDefaults.standard.data(forKey: claveRecientes) else { return [] }
        return (try? JSONDecoder().decode([Reciente].self, from: d)) ?? []
    }

    private func recordar(_ x: Resultado) {
        let r = Reciente(tipo: x.tipo, id: x.id, titulo: x.titulo)
        recientes = Array(([r] + recientes.filter { !($0.id == r.id && $0.tipo == r.tipo) }).prefix(5))
        if let d = try? JSONEncoder().encode(recientes) { UserDefaults.standard.set(d, forKey: Self.claveRecientes) }
    }
}
