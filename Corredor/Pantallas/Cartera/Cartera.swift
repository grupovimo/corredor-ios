import Contacts
import ContactsUI
import SwiftUI

extension View {
    /// Los destinos de Contactos y Operaciones.
    func destinosCartera() -> some View {
        self
            .navigationDestination(for: AContactos.self) { _ in Contactos() }
            .navigationDestination(for: AFichaContacto.self) { c in FichaContacto(id: c.id) }
            .navigationDestination(for: AOperaciones.self) { _ in Operaciones() }
            .navigationDestination(for: AFichaOperacion.self) { o in FichaOperacion(id: o.id) }
    }
}

/// Un contacto (GET /v1/contactos).
struct Contacto: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var telefono: String?
    var email: String?
    var tipo: String?
    var origen: String?
    var notas: String?
    var agenteId: String?
    var buscaOperacion: String?
    var buscaTipo: String?
    var buscaMoneda: String?
    var buscaDesde: Double?
    var buscaHasta: Double?
    var buscaAmbientes: Int?
    var buscaBarrios: [String]?
    /// Lo que pide además («Con balcón», «Apto crédito»): una lista, como los chips de la web.
    var buscaDetalles: [String]?
    var etiquetas: [String]?
    var creadoEn: Date?

    static let tipos = [("comprador", "Comprador"), ("vendedor", "Vendedor"), ("inquilino", "Inquilino"), ("propietario", "Propietario"), ("garante", "Garante")]
    var tipoTexto: String { Contacto.tipos.first { $0.0 == tipo }?.1 ?? "Contacto" }

    /// Lo que busca, en chips: «3 ambientes», «Palermo o Belgrano», «USD 150 a 180 mil».
    var busca: [String] {
        var b: [String] = []
        if let o = buscaOperacion { b.append(o == "alquiler" ? "Alquilar" : o == "venta" ? "Comprar" : o.capitalized) }
        if let t = buscaTipo { b.append(Propiedad.tipos.first { $0.0 == t }?.1 ?? t) }
        if let a = buscaAmbientes { b.append("\(a) ambientes") }
        if let l = buscaBarrios, !l.isEmpty { b.append(l.count == 1 ? l[0] : l.dropLast().joined(separator: ", ") + " o " + l.last!) }
        let m = buscaMoneda ?? "USD"
        switch (buscaDesde, buscaHasta) {
        case let (d?, h?): b.append("\(m) \(Formato.numero(Int(d))) a \(Formato.numero(Int(h)))")
        case let (nil, h?): b.append("Hasta \(Formato.plata(h, m))")
        case let (d?, nil): b.append("Desde \(Formato.plata(d, m))")
        default: break
        }
        b += (buscaDetalles ?? []).compactMap(\.nonEmpty)
        return b
    }
}

struct NotaContacto: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var texto: String
    var ocurrioEn: Date
    var autorId: String?
}

/// Una propiedad que le puede interesar a un contacto (GET /v1/contactos/{id}/propiedades): las que
/// ya mira (con operación o visita) y las de la cartera que coinciden con lo que busca.
struct PropiedadDeContacto: Codable, Identifiable, Hashable {
    var propiedadId: String
    var titulo: String?
    var direccion: String?
    var barrio: String?
    var precio: Double?
    var moneda: String?
    var fotoId: String?
    /// La etapa de su operación (nuevo… cierre), «visita» si sólo tiene una visita, «nueva» si es una coincidencia.
    var estado: String?
    var visitaEn: Date?
    var operacionId: String?
    var puntaje: Double?
    var enviadaEn: Date?
    var reservaVenceEl: String?
    var id: String { propiedadId }

    var nombre: String { titulo?.nonEmpty ?? direccion ?? "Propiedad" }
    var precioTexto: String { precio.map { Formato.plata($0, moneda ?? "USD") } ?? "Consultar precio" }
    /// «Coincide», «Visita» o la etapa de su operación.
    var estadoTexto: String {
        switch estado {
        case "nueva", nil: return "Coincide"
        case "visita": return "Visita"
        case let e?: return Operacion.etapaTexto(e)
        }
    }
    /// La miniatura: las fotos de las propiedades son públicas (/publico/archivos/{inmobiliaria}/{id}).
    func miniatura(_ api: URL, inmobiliaria: String?) -> URL? {
        guard let fotoId, let inmobiliaria else { return nil }
        return URL(string: api.appendingPathComponent("/publico/archivos/\(inmobiliaria)/\(fotoId)").absoluteString + "?tam=chica")
    }
}

// MARK: - 8A Contactos

/// 8A Contactos: por letra, con el índice a la derecha, llamar y WhatsApp en cada fila.
struct Contactos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Contacto]?
    @State private var q = ""
    @State private var tipo: String?
    @State private var nuevo = false
    @State private var error: ErrorApi?

    private var grupos: [(String, [Contacto])] {
        let l = (lista ?? []).filter { (tipo == nil || $0.tipo == tipo) && (q.isEmpty || $0.nombre.localizedCaseInsensitiveContains(q) || ($0.telefono ?? "").contains(q)) }
        let d = Dictionary(grouping: l) { String($0.nombre.folding(options: .diacriticInsensitive, locale: nil).prefix(1)).uppercased() }
        return d.keys.sorted().map { ($0, d[$0]!.sorted { $0.nombre < $1.nombre }) }
    }

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChipFiltro(texto: "Todos", activo: tipo == nil) { tipo = nil }
                            ForEach(Contacto.tipos, id: \.0) { k, n in ChipFiltro(texto: n + "es".replacingOccurrences(of: "es", with: n.hasSuffix("r") ? "es" : "s"), activo: tipo == k) { tipo = k } }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                    if let lista {
                        if lista.isEmpty {
                            EstadoVacio(icono: "person.2", titulo: "Todavía no hay contactos", texto: "Los que te escriben por WhatsApp, la web o Mercado Libre se cargan solos.",
                                        accion: estado.escribe ? ("Cargar contacto", { nuevo = true }) : nil).padding(.top, 40)
                        }
                        ForEach(grupos, id: \.0) { letra, cs in
                            Text(letra).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto3)
                                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4).id(letra)
                            ForEach(cs) { c in fila(c) }
                        }
                    } else if let error {
                        EstadoError(que: "los contactos", error: error) { Task { await cargar() } }.padding(.top, 30)
                    } else { EsqueletoFilas(filas: 8).padding(.horizontal, 16) }
                }
                .padding(.trailing, 14).padding(.bottom, 30)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 1) {
                    ForEach(grupos.map(\.0), id: \.self) { l in
                        Button(l) { withAnimation { lector.scrollTo(l, anchor: .top) } }
                            .font(Estilo(tamano: 10, peso: .bold, relativo: .caption2).font).foregroundStyle(C.accion).frame(height: 14)
                    }
                }
                .padding(.trailing, 4)
                .accessibilityHidden(true)
            }
        }
        .searchable(text: $q, prompt: "Nombre o teléfono")
        .refreshable { await cargar() }
        .pantallaApilada("Contactos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Contacto nuevo") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { EditarContacto() }
    }

    private func fila(_ c: Contacto) -> some View {
        HStack(spacing: 12) {
            Button { estado.abrir(AFichaContacto(id: c.id)) } label: {
                HStack(spacing: 12) {
                    let t = Self.tono(c.tipo)
                    Text(Formato.iniciales(c.nombre)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).foregroundStyle(t.tinta)
                        .frame(width: 42, height: 42).background(t.fondo, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.nombre).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                        Text(c.busca.first.map { "\(c.tipoTexto) · \($0)" } ?? c.tipoTexto).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if c.telefono != nil {
                Button { Afuera.llamar(c.telefono) } label: {
                    Image(systemName: "phone.fill").font(.system(size: 17)).foregroundStyle(C.accion).frame(width: 44, height: 44).background(C.hundida, in: Circle())
                }
                .accessibilityLabel("Llamar a \(c.nombre)")
                Button { Afuera.whatsapp(c.telefono) } label: {
                    Image("LogoWhatsApp").renderingMode(.template).resizable().frame(width: 20, height: 20).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color(hex: 0x25D366), in: Circle())
                }
                .accessibilityLabel("WhatsApp a \(c.nombre)")
            }
        }
        .padding(.leading, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 16) }
    }

    static func tono(_ t: String?) -> Tono {
        switch t {
        case "comprador": return .oro
        case "inquilino": return .azul
        case "propietario", "vendedor": return .verde
        case "garante": return .violeta
        default: return .neutro
        }
    }

    private func cargar() async {
        do {
            // La API da hasta 200 por página (?limite=&desde=): se piden todas para el índice por letra.
            var todos: [Contacto] = []
            while todos.count < 10_000 {
                let pagina: [Contacto] = try await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "200"), .init(name: "desde", value: String(todos.count))])
                todos += pagina
                if pagina.count < 200 { break }
            }
            // Si alguien se movió de página mientras se pedían, no sale dos veces.
            var vistos = Set<String>()
            lista = todos.filter { vistos.insert($0.id).inserted }
            error = nil
            Guardado.guardar(lista, clave: "contactos")
            if let lista { Spotlight.indexar(contactos: lista) }
        } catch let e as ErrorApi {
            if lista == nil { lista = Guardado.leer([Contacto].self, clave: "contactos")?.0 }
            if lista == nil { error = e }
        } catch {}
    }
}

// MARK: - 8B Ficha de contacto

/// 8B Ficha de un contacto: llamar, WhatsApp, agendar y mail; qué busca; las propiedades que le
/// interesan; las operaciones; la historia (notas y eventos) y sumar una nota.
struct FichaContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State private var c: Contacto?
    @State private var props: [PropiedadDeContacto] = []
    @State private var notas: [NotaContacto] = []
    @State private var ops: [Operacion] = []
    @State private var nota = ""
    @State private var editando = false
    @State private var agendar = false

    var body: some View {
        ScrollView {
            if let c {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 6) {
                        let t = Contactos.tono(c.tipo)
                        Text(Formato.iniciales(c.nombre)).font(Estilo(tamano: 30, peso: .bold, relativo: .largeTitle).font).foregroundStyle(t.tinta)
                            .frame(width: 84, height: 84).background(t.fondo, in: Circle())
                        Text(c.nombre).font(Estilo(tamano: 26, peso: .bold, tracking: -0.02, relativo: .title).font).foregroundStyle(C.texto).multilineTextAlignment(.center)
                        Text([c.tipoTexto, c.telefono].compactMap { $0 }.joined(separator: " · ")).estilo(.subhead).foregroundStyle(C.texto2)
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 8) {
                        accion("phone.fill", "Llamar") { Afuera.llamar(c.telefono) }
                        accion("bubble.left.fill", "WhatsApp") { abrirChat(c) }
                        accion("calendar", "Agendar") { agendar = true }
                        accion("envelope.fill", "Mail") { if let m = c.email, let u = URL(string: "mailto:\(m)") { UIApplication.shared.open(u) } }
                    }
                    if !c.busca.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Qué busca").estilo(.subheadFuerte).foregroundStyle(C.texto)
                            FlowLayout(espacio: 6) {
                                ForEach(c.busca, id: \.self) { b in
                                    Text(b).font(Estilo(tamano: 14, peso: .medium, relativo: .footnote).font).foregroundStyle(C.texto)
                                        .padding(.horizontal, 11).frame(height: 30).background(C.hundida, in: Capsule())
                                }
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
                    }
                    if !props.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "Le interesan")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(props) { p in
                                        Button { estado.abrir(AFichaPropiedad(id: p.propiedadId)) } label: {
                                            VStack(alignment: .leading, spacing: 0) {
                                                Foto(url: p.miniatura(estado.api.base, inmobiliaria: estado.sesion?.inmobiliariaId)).frame(width: 200, height: 110)
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(p.nombre).estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1)
                                                    HStack(spacing: 6) {
                                                        Text(p.precioTexto).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.okTinta)
                                                            .padding(.horizontal, 8).frame(height: 22).background(C.okFondo, in: Capsule())
                                                        Text(p.estadoTexto).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1)
                                                    }
                                                }
                                                .padding(.horizontal, 12).padding(.vertical, 10)
                                            }
                                            .frame(width: 200).tarjeta()
                                        }
                                        .buttonStyle(Presionable())
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 10)
                            }
                            .padding(.horizontal, -16)
                        }
                    }
                    if !ops.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "Operaciones")
                            VStack(spacing: 0) {
                                ForEach(Array(ops.enumerated()), id: \.element.id) { i, o in
                                    Button { estado.abrir(AFichaOperacion(id: o.id)) } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(o.propiedadTitulo ?? o.titulo ?? "Operación").estilo(.filaLista).foregroundStyle(C.texto)
                                                Text(Operacion.etapaTexto(o.etapa)).estilo(.footnote).foregroundStyle(C.texto2)
                                            }
                                            Spacer()
                                            Chevron()
                                        }
                                        .padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
                                    }
                                    .buttonStyle(Presionable())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: "Historia")
                        VStack(alignment: .leading, spacing: 0) {
                            if estado.escribe {
                                HStack {
                                    TextField("Sumar una nota", text: $nota, axis: .vertical).estilo(.body16)
                                    if !nota.isEmpty {
                                        Button { Task { await sumarNota() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).foregroundStyle(C.accion) }
                                            .accessibilityLabel("Guardar la nota")
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                            ForEach(Array(notas.enumerated()), id: \.element.id) { i, n in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(spacing: 0) {
                                        Image(systemName: Self.icono(n.tipo)).font(.system(size: 15)).foregroundStyle(C.accion)
                                            .frame(width: 32, height: 32).background(C.hundida, in: Circle())
                                        if i < notas.count - 1 { Rectangle().fill(C.linea2).frame(width: 2).frame(maxHeight: .infinity) }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Formato.cuando(n.ocurrioEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
                                        Text(n.texto).estilo(.subhead).foregroundStyle(C.texto)
                                    }
                                    .padding(.bottom, 14)
                                }
                            }
                            if notas.isEmpty { Text("Todavía no hay nada.").estilo(.texto14).foregroundStyle(C.texto3) }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("")
        .toolbar {
            if estado.escribe, c != nil {
                Menu {
                    Button { editando = true } label: { Label("Editar", systemImage: "pencil") }
                    if estado.esDuenio { Button(role: .destructive) { borrar() } label: { Label("Mandar a la papelera", systemImage: "trash") } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más acciones")
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editando) { if let c { EditarContacto(contacto: c) } }
        .sheet(isPresented: $agendar) { if let c { NuevaCita(contacto: (c.id, c.nombre)).presentationDetents([.large]) } }
        .userActivity("ar.com.corredor.app.contacto", isActive: c != nil) { a in
            a.title = c?.nombre
            a.userInfo = ["id": id]
            a.isEligibleForSearch = true
        }
    }

    private func accion(_ i: String, _ t: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            VStack(spacing: 4) {
                Image(systemName: i).font(.system(size: 21))
                Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
            }
            .foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 64).tarjeta(14)
        }
        .buttonStyle(Presionable())
    }

    static func icono(_ t: String?) -> String {
        switch t {
        case "whatsapp": return "bubble.left"
        case "visita", "cita": return "calendar"
        case "web", "consulta": return "globe"
        case "envio", "ficha": return "paperplane"
        case "llamado", "llamada": return "phone"
        case "vista": return "eye"
        default: return "text.bubble"
        }
    }

    private func abrirChat(_ c: Contacto) {
        Task {
            struct Cuerpo: Encodable { var contactoId: String }
            struct Conv: Decodable { var id: String }
            if let x: Conv = try? await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: c.id)) {
                estado.abrir(AChat(id: x.id))
            } else { Afuera.whatsapp(c.telefono) }
        }
    }

    private func cargar() async {
        c = try? await estado.api.get("/v1/contactos/\(id)")
        props = (try? await estado.api.get("/v1/contactos/\(id)/propiedades")) ?? []
        notas = ((try? await estado.api.get("/v1/contactos/\(id)/notas")) ?? [NotaContacto]()).sorted { $0.ocurrioEn > $1.ocurrioEn }
        ops = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "contacto", value: id)])) ?? []
    }

    private func sumarNota() async {
        struct Cuerpo: Encodable { var tipo = "nota"; var texto: String }
        let t = nota
        nota = ""
        do {
            try await estado.cola.enviar("POST", "/v1/contactos/\(id)/notas", Cuerpo(texto: t), etiqueta: "Nota en \(c?.nombre ?? "")")
            await cargar()
        } catch { nota = t; estado.avisar(error) }
    }

    private func borrar() {
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            try? await estado.api.hacer("DELETE", "/v1/contactos/\(id)")
            estado.version += 1
        }
        cerrar()
        estado.avisar("\(c?.nombre ?? "El contacto") va a la papelera") { tarea.cancel() }
    }
}

/// Alta o edición de un contacto (también lo trae de la agenda del iPhone).
struct EditarContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var contacto: Contacto? = nil
    @State private var c = Contacto(id: "", nombre: "", tipo: "comprador")
    @State private var barrios = ""
    @State private var detalles = ""
    @State private var agenda = false
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre y apellido", text: $c.nombre)
                    TextField("Teléfono", text: Binding(get: { c.telefono ?? "" }, set: { c.telefono = $0.nonEmpty })).keyboardType(.phonePad)
                    TextField("Mail", text: Binding(get: { c.email ?? "" }, set: { c.email = $0.nonEmpty })).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    Picker("Tipo", selection: Binding(get: { c.tipo ?? "comprador" }, set: { c.tipo = $0 })) { ForEach(Contacto.tipos, id: \.0) { Text($0.1).tag($0.0) } }
                    if contacto == nil { Button { agenda = true } label: { Label("Traer de la agenda del iPhone", systemImage: "person.crop.circle") } }
                }
                Section("Qué busca") {
                    Picker("Para", selection: Binding(get: { c.buscaOperacion ?? "" }, set: { c.buscaOperacion = $0.nonEmpty })) {
                        Text("—").tag(""); Text("Comprar").tag("venta"); Text("Alquilar").tag("alquiler"); Text("Temporada").tag("temporario")
                    }
                    Picker("Tipo", selection: Binding(get: { c.buscaTipo ?? "" }, set: { c.buscaTipo = $0.nonEmpty })) {
                        Text("—").tag(""); ForEach(Propiedad.tipos, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Stepper("Ambientes: \(c.buscaAmbientes.map(String.init) ?? "—")", value: Binding(get: { c.buscaAmbientes ?? 0 }, set: { c.buscaAmbientes = $0 == 0 ? nil : $0 }), in: 0...10)
                    TextField("Barrios (separados por coma)", text: $barrios)
                    Picker("Moneda", selection: Binding(get: { c.buscaMoneda ?? "USD" }, set: { c.buscaMoneda = $0 })) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("Desde", value: $c.buscaDesde, format: .number).keyboardType(.numberPad)
                    TextField("Hasta", value: $c.buscaHasta, format: .number).keyboardType(.numberPad)
                    TextField("Detalles (balcón, apto crédito…, separados por coma)", text: $detalles)
                }
                Section("Notas") { TextField("Notas internas", text: Binding(get: { c.notas ?? "" }, set: { c.notas = $0.nonEmpty }), axis: .vertical) }
            }
            .navigationTitle(contacto == nil ? "Contacto nuevo" : "Editar contacto").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(c.nombre.trimmingCharacters(in: .whitespaces).isEmpty || guardando) }
            }
            .sheet(isPresented: $agenda) {
                SelectorAgenda { cn in
                    c.nombre = [cn.givenName, cn.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    c.telefono = cn.phoneNumbers.first?.value.stringValue
                    c.email = cn.emailAddresses.first.map { String($0.value) }
                }
            }
        }
        .onAppear {
            if let contacto {
                c = contacto
                barrios = (contacto.buscaBarrios ?? []).joined(separator: ", ")
                detalles = (contacto.buscaDetalles ?? []).joined(separator: ", ")
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        let lista = { (t: String) in t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        c.buscaBarrios = lista(barrios)
        c.buscaDetalles = lista(detalles)
        // El PUT reemplaza todo: va el contacto entero como vino de la API (origen, etiquetas, agente)
        // con lo editado encima; si no, se borra lo que esta pantalla no muestra.
        struct Cuerpo: Encodable {
            var nombre: String; var telefono: String?; var email: String?; var tipo: String?; var origen: String?; var notas: String?
            var buscaOperacion: String?; var buscaTipo: String?; var buscaMoneda: String?; var buscaDesde: Double?; var buscaHasta: Double?
            var buscaAmbientes: Int?; var buscaBarrios: [String]?; var buscaDetalles: [String]?; var etiquetas: [String]?; var agenteId: String?
        }
        let cuerpo = Cuerpo(nombre: c.nombre, telefono: c.telefono, email: c.email, tipo: c.tipo, origen: c.origen, notas: c.notas, buscaOperacion: c.buscaOperacion,
                            buscaTipo: c.buscaTipo, buscaMoneda: c.buscaMoneda, buscaDesde: c.buscaDesde, buscaHasta: c.buscaHasta, buscaAmbientes: c.buscaAmbientes,
                            buscaBarrios: c.buscaBarrios, buscaDetalles: c.buscaDetalles, etiquetas: c.etiquetas ?? [],
                            agenteId: contacto == nil ? estado.usuario?.id : c.agenteId)
        do {
            if let contacto {
                try await estado.cola.enviar("PUT", "/v1/contactos/\(contacto.id)", cuerpo, etiqueta: "Cambios en \(c.nombre)")
            } else {
                try await estado.cola.enviar("POST", "/v1/contactos", cuerpo, etiqueta: "Alta de \(c.nombre)")
                estado.sugerir("\(c.nombre) quedó en Contactos", "Agendar", AAgendaDia())
            }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// La agenda del iPhone para elegir un contacto.
struct SelectorAgenda: UIViewControllerRepresentable {
    var alElegir: (CNContact) -> Void
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let c = CNContactPickerViewController()
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(alElegir) }
    final class Coordinador: NSObject, CNContactPickerDelegate {
        let alElegir: (CNContact) -> Void
        init(_ a: @escaping (CNContact) -> Void) { alElegir = a }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { alElegir(contact) }
    }
}

// MARK: - 9 Operaciones

/// Una operación del tablero.
struct Operacion: Codable, Identifiable, Hashable {
    /// Un paso tildado de la lista del cierre: cuándo y quién.
    struct Tildado: Codable, Hashable { var en: Date?; var por: String? }
    /// Un paso de «Para pasar a Cierre», con el texto que le pone el panel.
    struct Paso: Hashable { var clave: String; var texto: String; var hecho: Bool; var auto = false; var detalle: String? = nil }
    var id: String
    var titulo: String?
    var etapa: String
    var valor: Double?
    var moneda: String?
    var contactoId: String?
    var propiedadId: String?
    var agenteId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var agenteNombre: String?
    var creadaEn: Date?
    var actualizadoEn: Date?
    var sena: Double?
    var senaMoneda: String?
    var caidaEn: Date?
    var caidaMotivo: String?
    var honorariosComprador: Double?
    var honorariosVendedor: Double?
    var comisionAgente: Double?
    /// Lo tildado para el cierre: clave del paso (dominio, credito, aceptacion, boleto, garantia,
    /// documentacion, firma) → cuándo y quién.
    var checklist: [String: Tildado]?
    /// Los ids de los archivos adjuntos (GET /v1/archivos/{id} da el nombre).
    var adjuntos: [String]?
    var propiedadOperacion: String?
    var propiedadPrecio: Double?
    var propiedadMoneda: String?
    var senaRecibo: String?
    var propietarioNombre: String?
    var propietarioTelefono: String?

    static let etapas = [("nuevo", "Nuevo"), ("contactado", "Contactado"), ("visita", "Visita"), ("reserva", "Reserva"), ("cierre", "Cierre")]
    static func etapaTexto(_ e: String) -> String { etapas.first { $0.0 == e }?.1 ?? e.capitalized }
    var siguiente: String? { Operacion.etapas.firstIndex { $0.0 == etapa }.flatMap { $0 + 1 < Operacion.etapas.count ? Operacion.etapas[$0 + 1].0 : nil } }

    /// «Para pasar a Cierre» según sea venta o alquiler (los mismos pasos y textos que el panel,
    /// lib/crm/etapas.ts). La seña se tilda sola al cargarla; lo demás, a mano.
    var pasos: [Paso] {
        let hecho = { (k: String) in checklist?[k] != nil }
        let sena = Paso(clave: "sena", texto: self.sena.map { "Seña \(Formato.plata($0, senaMoneda ?? moneda ?? "USD")) recibida" } ?? "Seña recibida",
                        hecho: self.sena != nil, auto: true, detalle: self.sena != nil ? senaRecibo.map { "recibo \($0)" } : nil)
        let aceptacion = Paso(clave: "aceptacion", texto: "Aceptación del propietario", hecho: hecho("aceptacion"))
        var l: [Paso] = propiedadOperacion == "alquiler" || propiedadOperacion == "temporario"
            ? [sena, Paso(clave: "garantia", texto: "Garantía aprobada", hecho: hecho("garantia")),
               Paso(clave: "documentacion", texto: "Documentación del inquilino", hecho: hecho("documentacion")), aceptacion,
               Paso(clave: "firma", texto: "Fecha de firma del contrato", hecho: hecho("firma"))]
            : [sena, Paso(clave: "dominio", texto: "Informe de dominio", hecho: hecho("dominio")),
               Paso(clave: "credito", texto: "Pre-aprobación del crédito", hecho: hecho("credito")), aceptacion,
               Paso(clave: "boleto", texto: "Fecha de boleto y escribana", hecho: hecho("boleto"))]
        if !l[l.count - 1].hecho && !aceptacion.hecho { l[l.count - 1].detalle = "después de la aceptación" }
        return l
    }
}

/// Un evento del historial de una operación (GET /v1/operaciones/{id}/historial).
struct EventoOperacion: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String
    var texto: String?
    var datos: JSONLibre?
    var autorId: String?
    var autorNombre: String?
    var creadoEn: Date

    /// Lo que se lee, como en el panel: «Pasó a Visita · Sofía», «Se cayó · Precio».
    var descripcion: String {
        let quien = autorNombre?.split(separator: " ").first.map { " · \($0)" } ?? ""
        let dato = { (k: String) -> String? in
            switch datos?[k] {
            case .texto(let s)?: return s
            case .numero(let n)?: return String(n)
            default: return nil
            }
        }
        switch tipo {
        case "alta": return "Entró en \(Operacion.etapaTexto(dato("etapa") ?? "nuevo"))"
        case "etapa": return "Pasó a \(Operacion.etapaTexto(dato("hasta") ?? ""))\(quien)"
        case "nota": return (texto ?? "") + quien
        case "asignacion": return dato("hasta") != nil ? "Cambió de agente" : "Quedó sin agente"
        case "caida": return "Se cayó · \(dato("motivo") ?? "")"
        case "reabierta": return "Volvió al tablero"
        case "sena":
            if case .numero(let n)? = datos?["monto"] { return "Dejó seña de \(Formato.plata(n, dato("moneda") ?? "USD"))" }
            return "Dejó seña"
        default: return texto ?? tipo
        }
    }
}

/// 9A–9B Tablero de operaciones: una etapa por vez (chips con la cuenta), «Pasar a …» en cada una y,
/// manteniendo apretado, todas las etapas, perder o reabrir.
struct Operaciones: View {
    @Environment(Estado.self) private var estado
    @State private var etapa = "nuevo"
    @State private var ops: [Operacion]?
    @State private var nueva = false
    @State private var cayendo: Operacion?
    @State private var motivo = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Operacion.etapas, id: \.0) { k, n in
                            let cnt = (ops ?? []).filter { $0.etapa == k && $0.caidaEn == nil }.count
                            ChipFiltro(texto: "\(n) \(cnt)", activo: etapa == k) { etapa = k }
                        }
                        ChipFiltro(texto: "Caídas", activo: etapa == "caidas") { etapa = "caidas" }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 2)
                }
                VStack(spacing: 10) {
                    let vis = (ops ?? []).filter { etapa == "caidas" ? $0.caidaEn != nil : ($0.etapa == etapa && $0.caidaEn == nil) }
                    if ops == nil { EsqueletoFilas(filas: 3, miniatura: 56) }
                    else if vis.isEmpty {
                        Text("Nada en esta etapa.").estilo(.subhead).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(28)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    ForEach(vis) { o in tarjeta(o) }
                    Text("Mantené apretada una operación para ver todas las etapas.").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8).padding(.bottom, 30)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Operaciones")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Operación nueva") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nueva) { NuevaOperacion() }
        .alert("¿Por qué se cayó?", isPresented: Binding(get: { cayendo != nil }, set: { if !$0 { cayendo = nil } })) {
            TextField("Motivo", text: $motivo)
            Button("Cancelar", role: .cancel) {}
            Button("Marcar caída") { if let o = cayendo { Task { await caer(o) } } }
        }
    }

    private func tarjeta(_ o: Operacion) -> some View {
        VStack(spacing: 0) {
            Button { estado.abrir(AFichaOperacion(id: o.id)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "house").foregroundStyle(C.accion).frame(width: 56, height: 56).background(C.hundida, in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.propiedadTitulo ?? o.titulo ?? "Operación").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                        Text([o.contactoNombre, o.valor.map { Formato.plata($0, o.moneda ?? "USD") }].compactMap { $0 }.joined(separator: " · ")).estilo(.texto14).foregroundStyle(C.texto2)
                        Text(o.caidaEn != nil ? "Caída · \(o.caidaMotivo ?? "")" : "En \(Operacion.etapaTexto(o.etapa).lowercased()) \(o.actualizadoEn.map { Formato.hace($0) } ?? "")")
                            .font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
                    }
                    Spacer()
                    Text(Formato.iniciales(o.agenteNombre ?? "")).font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(C.texto)
                        .frame(width: 28, height: 28).background(C.hundida, in: Circle())
                }
                .padding(12).contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if estado.escribe {
                HStack(spacing: 0) {
                    if o.caidaEn != nil {
                        Button { Task { await reabrir(o) } } label: { Label("Reabrir", systemImage: "arrow.uturn.left").frame(maxWidth: .infinity, minHeight: 46) }
                    } else if let s = o.siguiente {
                        Button { Task { await mover(o, a: s) } } label: { Label("Pasar a \(Operacion.etapaTexto(s).lowercased())", systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 46) }
                    } else {
                        Text("Cerrada").frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(C.okTinta)
                    }
                    Rectangle().fill(C.linea).frame(width: 0.5)
                    menu(o)
                }
                .font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font).foregroundStyle(C.accion)
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
        .tarjeta()
        .contextMenu { if estado.escribe { menuItems(o) } } preview: {
            VStack(alignment: .leading, spacing: 2) {
                Text(o.propiedadTitulo ?? "Operación").font(Estilo.headline.font)
                Text("\(o.contactoNombre ?? "") · \(o.valor.map { Formato.plata($0, o.moneda ?? "USD") } ?? "")").estilo(.texto14).foregroundStyle(C.texto2)
            }
            .padding(14).frame(width: 300, alignment: .leading).background(C.superficie)
        }
    }

    private func menu(_ o: Operacion) -> some View {
        Menu { menuItems(o) } label: { Image(systemName: "ellipsis").frame(width: 56, height: 46).foregroundStyle(C.texto2) }
            .accessibilityLabel("Más acciones")
    }

    @ViewBuilder
    private func menuItems(_ o: Operacion) -> some View {
        ForEach(Operacion.etapas.filter { $0.0 != o.etapa }, id: \.0) { k, n in
            Button { Task { await mover(o, a: k) } } label: { Label("Mover a \(n.lowercased())", systemImage: "arrow.right.circle") }
        }
        Divider()
        if o.caidaEn == nil {
            Button(role: .destructive) { motivo = ""; cayendo = o } label: { Label("Se cayó", systemImage: "xmark.circle") }
        } else {
            Button { Task { await reabrir(o) } } label: { Label("Reabrir", systemImage: "arrow.uturn.left") }
        }
    }

    private func mover(_ o: Operacion, a e: String) async {
        struct Cuerpo: Encodable { var etapa: String }
        let antes = o.etapa
        if let i = ops?.firstIndex(where: { $0.id == o.id }) { ops?[i].etapa = e }
        Haptico.impacto()
        do {
            try await estado.cola.enviar("POST", "/v1/operaciones/\(o.id)/mover", Cuerpo(etapa: e), etiqueta: "Mover \(o.propiedadTitulo ?? "")")
            if e == "cierre" && o.propiedadOperacion == "alquiler" {
                // Un alquiler que cierra lleva a su contrato.
                estado.sugerir("\(o.propiedadTitulo ?? "La operación") llegó al cierre", "Hacer contrato", AFichaOperacion(id: o.id))
            } else {
                estado.avisar("Movida a \(Operacion.etapaTexto(e).lowercased())") {
                    Task { try? await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/mover", Cuerpo(etapa: antes)); estado.version += 1 }
                }
            }
            estado.version += 1
        } catch { estado.avisar(error); await cargar() }
    }

    private func caer(_ o: Operacion) async {
        struct Cuerpo: Encodable { var motivo: String }
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/caer", Cuerpo(motivo: motivo.nonEmpty ?? "Sin motivo"))
            estado.avisar("Operación caída") { Task { try? await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/reabrir"); estado.version += 1 } }
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func reabrir(_ o: Operacion) async {
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/reabrir")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// El tablero no trae las caídas: van aparte con ?caidas=si.
    private func cargar() async {
        let t: [Operacion]? = try? await estado.api.todas("/v1/operaciones", query: [])
        let c: [Operacion]? = try? await estado.api.todas("/v1/operaciones", query: [.init(name: "caidas", value: "si")])
        if let t { ops = t + (c ?? ops?.filter { $0.caidaEn != nil } ?? []) } else if ops == nil { ops = [] }
    }
}

/// Una operación nueva: propiedad, contacto, valor.
struct NuevaOperacion: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var prop: Propiedad?
    @State private var con: Resultado?
    @State private var valor: Double?
    @State private var moneda = "USD"
    @State private var elegirP = false
    @State private var elegirC = false

    var body: some View {
        NavigationStack {
            Form {
                Button { elegirP = true } label: { LabeledContent("Propiedad", value: prop?.nombre ?? "Elegí") }
                Button { elegirC = true } label: { LabeledContent("Contacto", value: con?.titulo ?? "Elegí") }
                Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Valor", value: $valor, format: .number).keyboardType(.numberPad)
            }
            .navigationTitle("Operación nueva").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        Task {
                            struct Cuerpo: Encodable { var titulo: String; var etapa = "nuevo"; var valor: Double?; var moneda: String; var contactoId: String?; var propiedadId: String?; var agenteId: String? }
                            do {
                                try await estado.cola.enviar("POST", "/v1/operaciones", Cuerpo(titulo: prop?.nombre ?? con?.titulo ?? "Operación", valor: valor ?? prop?.precio, moneda: moneda,
                                                                                               contactoId: con?.id, propiedadId: prop?.id, agenteId: estado.usuario?.id), etiqueta: "Operación nueva")
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                    .disabled(prop == nil && con == nil)
                }
            }
            .sheet(isPresented: $elegirP) { ElegirPropiedad { prop = $0; moneda = $0.moneda ?? moneda } }
            .sheet(isPresented: $elegirC) { ElegirContacto { con = $0 } }
        }
    }
}

/// 9C Ficha de la operación: las etapas, el próximo paso, precio, seña y comisión, los documentos, el
/// checklist, las notas y «Pasar a …».
struct FichaOperacion: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var haciendoContrato = false
    @State private var o: Operacion?
    @State private var historial: [EventoOperacion] = []
    @State private var adjuntos: [Archivo] = []
    @State private var previo: ArchivoPrevio?
    @State private var proxima: Cita?
    @State private var nota = ""

    var body: some View {
        ScrollView {
            if let o {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "house").font(.system(size: 24)).foregroundStyle(C.accion).frame(width: 64, height: 64).background(C.hundida, in: .rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(o.propiedadTitulo ?? o.titulo ?? "Operación").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
                            Text([o.propiedadOperacion?.capitalized, o.contactoNombre, o.agenteNombre].compactMap { $0 }.joined(separator: " · ")).estilo(.texto14).foregroundStyle(C.texto2)
                        }
                    }
                    pasos(o)
                    if let p = proxima {
                        Button { estado.abrir(ACita(id: p.id)) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar").font(.system(size: 24)).foregroundStyle(C.avisoTinta)
                                VStack(alignment: .leading) {
                                    Text("Próximo paso").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
                                    Text("\(p.tipoTexto) · \(Formato.diaCompleto(p.empiezaEn)), \(Formato.horaDe(p.empiezaEn))").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                }
                                Spacer()
                            }
                            .padding(14).background(C.avisoFondo, in: .rect(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(Presionable())
                    }
                    VStack(spacing: 0) {
                        dato("Precio", o.valor.map { Formato.plata($0, o.moneda ?? "USD") } ?? "—", primera: true)
                        if let s = o.sena { dato("Seña recibida", Formato.plata(s, o.senaMoneda ?? o.moneda ?? "USD")) }
                        if let h = o.honorariosComprador, let v = o.valor { dato("Comisión \(Formato.numero(Int(h))) %", Formato.plata(v * h / 100, o.moneda ?? "USD")) }
                        if let h = o.honorariosVendedor, let v = o.valor { dato("Comisión vendedor \(Formato.numero(Int(h))) %", Formato.plata(v * h / 100, o.moneda ?? "USD")) }
                        // Los adjuntos se bajan con la sesión y se abren con la vista previa (compartir, imprimir).
                        ForEach(adjuntos) { a in
                            Button { Task { await abrir(a) } } label: {
                                HStack {
                                    Label(a.nombre ?? "Documento", systemImage: "doc.text").foregroundStyle(C.texto)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up").foregroundStyle(C.accion)
                                }
                                .estilo(.body16).padding(.horizontal, 14).frame(minHeight: 46).contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                        }
                    }
                    .tarjeta()
                    if o.caidaEn == nil {
                        let l = o.pasos
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "\(o.etapa == "cierre" ? "Para cerrar" : "Para pasar a Cierre") · \(l.filter(\.hecho).count) de \(l.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(l.enumerated()), id: \.element.clave) { i, p in
                                    Button { Task { await marcar(p) } } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: p.hecho ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(p.hecho ? Color(hex: 0x2F9E6F) : C.texto3)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(p.texto).estilo(.body16).foregroundStyle(C.texto).strikethrough(p.hecho)
                                                if let d = p.detalle { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                                    }
                                    // La seña se tilda sola al cargarla.
                                    .buttonStyle(Presionable()).disabled(!estado.escribe || p.auto)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: "Historia")
                        VStack(alignment: .leading, spacing: 10) {
                            if estado.escribe {
                                HStack {
                                    TextField("Sumar una nota", text: $nota, axis: .vertical).estilo(.body16)
                                    if !nota.isEmpty { Button { Task { await sumarNota() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).foregroundStyle(C.accion) }.accessibilityLabel("Guardar la nota") }
                                }
                            }
                            ForEach(historial) { n in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Formato.cuando(n.creadoEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
                                    Text(n.descripcion).estilo(.subhead).foregroundStyle(C.texto)
                                }
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
                    }
                    HStack(spacing: 8) {
                        if let c = o.contactoId { Button("Contacto") { estado.abrir(AFichaContacto(id: c)) }.buttonStyle(BotonHundido()) }
                        if let p = o.propiedadId { Button("Propiedad") { estado.abrir(AFichaPropiedad(id: p)) }.buttonStyle(BotonHundido()) }
                        if o.etapa == "cierre" && o.propiedadOperacion == "alquiler" { Button("Hacer el contrato") { haciendoContrato = true }.buttonStyle(BotonHundido()) }
                    }
                    if estado.escribe, o.caidaEn == nil, let s = o.siguiente {
                        Button { Task { await mover(o, s) } } label: {
                            Label("Pasar a \(Operacion.etapaTexto(s).lowercased())", systemImage: "arrow.right").labelStyle(TextoDespues())
                                .font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font).foregroundStyle(C.sobreAccion)
                                .frame(maxWidth: .infinity, minHeight: 52).background(C.accion, in: .rect(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("Operación")
        .sheet(isPresented: $haciendoContrato) { AltaContrato(operacion: id) }
        .vistaPrevia($previo)
        .task(id: estado.version) { await cargar() }
    }

    private func pasos(_ o: Operacion) -> some View {
        let actual = Operacion.etapas.firstIndex { $0.0 == o.etapa } ?? 0
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(Operacion.etapas.enumerated()), id: \.offset) { i, e in
                VStack(spacing: 6) {
                    Image(systemName: i < actual ? "checkmark" : (i == actual ? "smallcircle.filled.circle" : "circle"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(i < actual ? C.sobreAccion : (i == actual ? Color(hex: 0x1A1405) : C.texto3))
                        .frame(width: 28, height: 28).background(i < actual ? C.accion : (i == actual ? C.oro : C.hundida), in: Circle())
                    Text(e.1).font(Estilo(tamano: 11, peso: i == actual ? .bold : .medium, relativo: .caption2).font).foregroundStyle(i <= actual ? C.texto : C.texto3)
                }
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    if i < Operacion.etapas.count - 1 {
                        Rectangle().fill(i < actual ? C.accion : C.linea2).frame(height: 2).offset(x: 50, y: 13).padding(.horizontal, 15)
                    }
                }
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 12).tarjeta()
    }

    private func dato(_ l: String, _ v: String, primera: Bool = false) -> some View {
        HStack {
            Text(l).foregroundStyle(C.texto2)
            Spacer()
            Text(v).fontWeight(.bold).foregroundStyle(C.texto)
        }
        .estilo(.body16).padding(.horizontal, 14).padding(.vertical, 13)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cargar() async {
        o = try? await estado.api.get("/v1/operaciones/\(id)")
        historial = ((try? await estado.api.get("/v1/operaciones/\(id)/historial")) ?? [EventoOperacion]()).sorted { $0.creadoEn > $1.creadoEn }
        // Los adjuntos vienen como ids: el nombre lo da cada archivo.
        var l: [Archivo] = []
        for a in o?.adjuntos ?? [] { if let x: Archivo = try? await estado.api.get("/v1/archivos/\(a)") { l.append(x) } }
        adjuntos = l
        let hoy = Formato.diaISO(Date())
        let citas: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "desde", value: hoy), .init(name: "operacion", value: id), .init(name: "limite", value: "5")])) ?? []
        proxima = citas.filter { $0.operacionId == id && $0.empiezaEn > Date() }.sorted { $0.empiezaEn < $1.empiezaEn }.first
    }

    private func mover(_ o: Operacion, _ e: String) async {
        struct Cuerpo: Encodable { var etapa: String }
        do {
            try await estado.cola.enviar("POST", "/v1/operaciones/\(o.id)/mover", Cuerpo(etapa: e), etiqueta: "Mover \(o.propiedadTitulo ?? "")")
            Haptico.impacto()
            if e == "cierre" && o.propiedadOperacion == "alquiler" {
                estado.sugerir("Llegó al cierre: armá el contrato", "Hacer contrato") { haciendoContrato = true }
            } else {
                estado.avisar("Movida a \(Operacion.etapaTexto(e).lowercased())") {
                    Task { try? await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/mover", Cuerpo(etapa: o.etapa)); estado.version += 1 }
                }
            }
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func marcar(_ p: Operacion.Paso) async {
        guard !p.auto else { return }
        struct Cuerpo: Encodable { var paso: String; var hecho: Bool }
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/checklist", Cuerpo(paso: p.clave, hecho: !p.hecho))
            Haptico.impacto()
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func sumarNota() async {
        struct Cuerpo: Encodable { var texto: String }
        let t = nota
        nota = ""
        do {
            try await estado.cola.enviar("POST", "/v1/operaciones/\(id)/notas", Cuerpo(texto: t), etiqueta: "Nota en la operación")
            await cargar()
        } catch { nota = t; estado.avisar(error) }
    }

    /// Lo baja con la sesión de la app y lo muestra con la vista previa.
    private func abrir(_ a: Archivo) async {
        do {
            let datos = try await estado.api.pedir("GET", "/v1/archivos/\(a.id)/contenido")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(a.nombre?.nonEmpty ?? "documento-\(a.id)")
            try datos.write(to: u)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

/// El texto antes del ícono («Pasar a boleto →»).
struct TextoDespues: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}
