import AVFoundation
import PhotosUI
import SwiftUI

extension View {
    /// Los destinos de Mensajes: el chat de WhatsApp y la pregunta de Mercado Libre.
    func destinosMensajes() -> some View {
        self
            .navigationDestination(for: AChat.self) { c in Chat(id: c.id) }
            .navigationDestination(for: APreguntaML.self) { p in RespuestaML(id: p.id) }
    }
}

/// Una fila de la bandeja: WhatsApp, Mercado Libre o la web.
struct FilaBandeja: Identifiable {
    var id: String
    var canal: String
    var nombre: String
    var texto: String
    var cuando: Date?
    var propiedad: String?
    var nuevo: Bool
    var mio: Bool
    var sinDueno: Bool
    var fuera: Bool
    var ir: AnyHashable
    var contactoId: String? = nil
}

/// 6A Bandeja: WhatsApp, Mercado Libre y las consultas de la web juntas, con filtros.
struct MensajesRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var filtro = 0
    @State private var filas: [FilaBandeja]?
    @State private var error: ErrorApi?
    @State private var nuevo = false

    private static let filtros = ["Pendientes", "Míos", "Sin dueño", "Todos"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CabeceraPestana(titulo: "Mensajes",
                                acciones: estado.escribe ? [AccionCabecera(icono: "square.and.pencil", etiqueta: "Mensaje nuevo") { nuevo = true }] : [],
                                busca: "Persona o propiedad") { estado.abrir(ABuscar()) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(Self.filtros.enumerated()), id: \.offset) { i, n in
                            ChipFiltro(texto: n + (cuenta(i).map { " \($0)" } ?? ""), activo: filtro == i) { filtro = i }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 2)
                }
                if let filas {
                    let l = filas.filter(pasa)
                    if l.isEmpty {
                        EstadoVacio(icono: "bubble.left.and.bubble.right", titulo: filtro == 0 ? "Respondiste todo" : "No hay mensajes acá",
                                    texto: filas.isEmpty ? "Conectá tu WhatsApp y Mercado Libre para recibir las consultas en un solo lugar." : nil,
                                    accion: filas.isEmpty && estado.esDuenio ? ("Conectar WhatsApp", { estado.abrir(ASeccion(clave: "integraciones")) }) : nil)
                            .padding(.top, 30)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(l.enumerated()), id: \.element.id) { i, x in fila(x, primera: i == 0) }
                        }
                        .tarjeta()
                        .padding(.horizontal, 16)
                    }
                } else if let error {
                    EstadoError(que: "los mensajes", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else {
                    EsqueletoFilas(filas: 6).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable { await cargar() }
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { MensajeNuevo().presentationDetents([.medium, .large]) }
    }

    private func pasa(_ x: FilaBandeja) -> Bool {
        switch filtro {
        case 0: return x.nuevo
        case 1: return x.mio
        case 2: return x.sinDueno
        default: return true
        }
    }

    private func cuenta(_ i: Int) -> Int? {
        guard let filas else { return nil }
        let n = filas.filter { f in
            switch i { case 0: return f.nuevo; case 1: return f.mio; case 2: return f.sinDueno; default: return true }
        }.count
        return n > 0 && i < 3 ? n : nil
    }

    private func fila(_ x: FilaBandeja, primera: Bool) -> some View {
        Button { estado.abrir(x.ir) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(Formato.iniciales(x.nombre)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                    .frame(width: 48, height: 48).background(C.hundida, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Group {
                            switch x.canal {
                            case "wa": Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 16, height: 16)
                            case "ml": Image("LogoMercadoLibre").resizable().scaledToFit().frame(width: 16, height: 16)
                            default: Image(systemName: "globe").font(.system(size: 14)).foregroundStyle(C.azulTinta)
                            }
                        }
                        .frame(width: 22, height: 22).background(C.superficie, in: Circle()).offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(x.nombre).font(Estilo(tamano: 16, peso: x.nuevo ? .bold : .medium, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                        Spacer()
                        Text(x.cuando.map { Calendar.current.isDateInToday($0) ? Formato.horaDe($0) : Formato.dia($0) } ?? "")
                            .estilo(.footnote).foregroundStyle(x.nuevo ? C.accion : C.texto3)
                    }
                    HStack(spacing: 8) {
                        Text(x.texto).estilo(.texto14).foregroundStyle(C.texto2).lineLimit(1)
                        Spacer()
                        if x.nuevo { Circle().fill(C.accion).frame(width: 10, height: 10) }
                    }
                    HStack(spacing: 6) {
                        if let p = x.propiedad { etiqueta(p, C.hundida, C.texto2) }
                        if x.sinDueno { etiqueta("Sin dueño", C.azulFondo, C.azulTinta) }
                        if x.fuera { etiqueta("Fuera de 24 h", C.avisoFondo, C.avisoTinta) }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contextMenu {
            if x.canal == "web", x.sinDueno, estado.escribe, let c = x.contactoId {
                Button { Task { await tomar(c) } } label: { Label("Tomarla yo", systemImage: "person.crop.circle.badge.checkmark") }
            }
        }
        .swipeActions {
            if x.canal == "web", x.sinDueno, estado.escribe, let c = x.contactoId {
                Button("Tomarla") { Task { await tomar(c) } }.tint(C.verde700)
            }
        }
    }

    private func tomar(_ contacto: String) async {
        struct C: Encodable { var agenteId: String? }
        do {
            try await estado.api.hacer("POST", "/v1/consultas/\(contacto)/asignar", C(agenteId: estado.usuario?.id))
            estado.avisar("La consulta es tuya")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func etiqueta(_ t: String, _ f: Color, _ c: Color) -> some View {
        Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(c)
            .padding(.horizontal, 8).frame(height: 22).background(f, in: .rect(cornerRadius: 6))
    }

    private func cargar() async {
        do {
            let yo = estado.usuario?.id
            let wa: [Conversacion] = try await estado.api.get("/v1/whatsapp/conversaciones", query: [.init(name: "limite", value: "100")])
            let ml: [PreguntaML] = (try? await estado.api.get("/v1/mercadolibre/preguntas", query: [.init(name: "limite", value: "50")])) ?? []
            struct Lista: Decodable { var avisos: [AvisoCentro] }
            let web = (try? await estado.api.get("/v1/avisos", query: [.init(name: "vista", value: "para_hacer"), .init(name: "tipo", value: "consulta"), .init(name: "limite", value: "30")]) as Lista)?.avisos ?? []
            var f: [FilaBandeja] = wa.map { c in
                FilaBandeja(id: "wa" + c.id, canal: "wa", nombre: c.quien, texto: c.ultimoTexto ?? "", cuando: c.ultimoMensajeEn, propiedad: c.propiedadTitulo,
                            nuevo: (c.noLeidos ?? 0) > 0, mio: c.agenteId == yo, sinDueno: c.agenteId == nil, fuera: c.enVentana == false, ir: AChat(id: c.id))
            }
            f += ml.map { p in
                FilaBandeja(id: "ml" + p.id, canal: "ml", nombre: p.compradorApodo ?? "Mercado Libre", texto: p.texto ?? "", cuando: p.creadaEn, propiedad: p.propiedad,
                            nuevo: p.estado == "sin_responder", mio: true, sinDueno: false, fuera: false, ir: APreguntaML(id: p.id))
            }
            f += web.map { a in
                FilaBandeja(id: "web" + a.id, canal: "web", nombre: a.titulo ?? "Consulta desde tu web", texto: a.cuerpo ?? "", cuando: a.creadoEn, propiedad: nil,
                            nuevo: a.hechoEn == nil, mio: false, sinDueno: true, fuera: false,
                            ir: a.url.flatMap { Ruta(texto: $0)?.destino } ?? AnyHashable(AAvisos()),
                            contactoId: a.url.flatMap { Ruta(texto: $0)?.destino as? AFichaContacto }?.id)
            }
            filas = f.sorted { ($0.cuando ?? .distantPast) > ($1.cuando ?? .distantPast) }
            estado.sinLeer = wa.reduce(0) { $0 + ($1.noLeidos ?? 0) } + ml.filter { $0.estado == "sin_responder" }.count
            error = nil
        } catch let e as ErrorApi { if filas == nil { error = e } } catch {}
    }
}

/// Mensaje nuevo: elegir un contacto y abrir (o crear) la conversación de WhatsApp.
struct MensajeNuevo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var q = ""
    @State private var res: [Resultado] = []

    var body: some View {
        NavigationStack {
            List(res) { r in
                Button {
                    Task {
                        struct Cuerpo: Encodable { var contactoId: String }
                        struct Conv: Decodable { var id: String }
                        do {
                            let c: Conv = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: r.id))
                            cerrar()
                            estado.abrir(AChat(id: c.id), en: .mensajes)
                        } catch { estado.avisar(error) }
                    }
                } label: {
                    VStack(alignment: .leading) { Text(r.titulo).estilo(.filaLista); if let s = r.subtitulo { Text(s).estilo(.footnote).foregroundStyle(C.texto2) } }
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nombre o teléfono")
            .navigationTitle("Mensaje nuevo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .task(id: q) {
                guard q.count >= 2 else { res = []; return }
                try? await Task.sleep(for: .milliseconds(220))
                res = (try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: q)])) ?? []
            }
        }
    }
}

/// Un mensaje de WhatsApp.
struct MensajeWA: Codable, Identifiable, Hashable {
    var id: String
    var direccion: String
    var tipo: String?
    var texto: String?
    var mediaTipo: String?
    var archivoId: String?
    var archivoUrl: String?
    var estado: String?
    var error: String?
    var ocurrioEn: Date
    var saliente: Bool { direccion == "saliente" || direccion == "out" }
}

struct PlantillaWA: Codable, Identifiable, Hashable {
    var nombre: String
    var idioma: String?
    var categoria: String?
    var cuerpo: String?
    var parametros: Int?
    var id: String { nombre }
}

struct RespuestaGuardada: Codable, Identifiable, Hashable {
    var id: String
    var titulo: String
    var texto: String
}

/// 6B–6C Chat de WhatsApp: la propiedad vinculada, los mensajes (texto, foto, voz), respuestas guardadas
/// y, fuera de las 24 h, sólo plantillas aprobadas.
struct Chat: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var conv: Conversacion?
    @State private var mensajes: [MensajeWA] = []
    @State private var texto = ""
    @State private var plantillas: [PlantillaWA] = []
    @State private var respuestas: [RespuestaGuardada] = []
    @State private var foto: PhotosPickerItem?
    @State private var vincular = false
    @State private var grabadora = Grabadora()
    @State private var enviando = false

    var body: some View {
        VStack(spacing: 0) {
            if let c = conv {
                Button { vincular = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "house").foregroundStyle(C.accion).frame(width: 40, height: 40).background(C.hundida, in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.propiedadTitulo == nil ? "Sin propiedad vinculada" : "Vinculada a").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2)
                            Text(c.propiedadTitulo ?? "Vincular una propiedad").estilo(.label).foregroundStyle(C.texto)
                        }
                        Spacer()
                        Text(c.propiedadTitulo == nil ? "Vincular" : "Cambiar").font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(C.accion).padding(.horizontal, 10).frame(height: 32).background(C.hundida, in: Capsule())
                    }
                    .padding(8).tarjeta(14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.top, 10)
            }
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(mensajes) { m in burbuja(m).id(m.id) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 14)
                }
                .onChange(of: mensajes.count) { _, _ in if let u = mensajes.last { withAnimation { lector.scrollTo(u.id, anchor: .bottom) } } }
            }
            if conv?.enVentana == false { fueraDeVentana } else { entrada }
        }
        .background(FondoApp())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { if let c = conv?.contactoId { estado.abrir(AFichaContacto(id: c)) } } label: {
                    HStack(spacing: 8) {
                        Text(Formato.iniciales(conv?.quien ?? "")).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto)
                            .frame(width: 34, height: 34).background(C.hundida, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(conv?.quien ?? "").font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                            Text(conv?.agenteNombre.map { "Lo atiende \($0)" } ?? (conv?.waId.map { "+\($0)" } ?? "")).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Afuera.llamar(conv?.waId.map { "+" + $0 }) } label: { Label("Llamar", systemImage: "phone") }
                    if estado.escribe {
                        Button { Task { await tomar() } } label: { Label("Atenderla yo", systemImage: "person.crop.circle.badge.checkmark") }
                        Button { Task { await archivar() } } label: { Label("Archivar", systemImage: "archivebox") }
                    }
                } label: { Image(systemName: "phone") } primaryAction: { Afuera.llamar(conv?.waId.map { "+" + $0 }) }
                .accessibilityLabel("Llamar")
            }
        }
        .task(id: estado.version) { await cargar() }
        .task {
            // Respaldo: en vivo los mensajes llegan por el stream; si está caído, se consulta cada 8 s.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                if !estado.enVivo { await cargarMensajes() }
            }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) { await mandarArchivo(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, tipo: "image/jpeg", uso: "adjunto", nombre: "foto.jpg") }
                foto = nil
            }
        }
        .sheet(isPresented: $vincular) {
            ElegirPropiedad { p in
                Task {
                    struct Cuerpo: Encodable { var propiedadId: String }
                    try? await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", Cuerpo(propiedadId: p.id))
                    await cargar()
                }
            }
            .presentationDetents([.large])
        }
    }

    private func burbuja(_ m: MensajeWA) -> some View {
        let sal = m.saliente
        return HStack {
            if sal { Spacer(minLength: 60) }
            VStack(alignment: sal ? .trailing : .leading, spacing: 2) {
                Group {
                    if let u = m.archivoUrl, m.mediaTipo?.hasPrefix("image") == true || m.tipo == "image" {
                        AsyncImage(url: URL(string: u)) { $0.resizable().scaledToFill() } placeholder: { C.hundida }
                            .frame(width: 220, height: 220).clipShape(.rect(cornerRadius: 14))
                    } else if let u = m.archivoUrl, m.mediaTipo?.hasPrefix("audio") == true || m.tipo == "audio" {
                        AudioMensaje(url: URL(string: u))
                    } else {
                        Text(m.texto ?? "").estilo(.body16).foregroundStyle(C.texto)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(sal ? Color.tema(0xDCEBE3, 0x1F3B33) : C.superficie,
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: sal ? 18 : 6, bottomTrailingRadius: sal ? 6 : 18, topTrailingRadius: 18, style: .continuous))
                .sombraE1()
                HStack(spacing: 4) {
                    Text(Formato.horaDe(m.ocurrioEn))
                    if sal { Image(systemName: m.estado == "leido" ? "checkmark.circle.fill" : m.estado == "fallido" ? "exclamationmark.circle" : "checkmark") }
                }
                .font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font).foregroundStyle(m.estado == "fallido" ? C.error : C.texto3)
                if m.estado == "fallido" {
                    Button("Reintentar") { Task { try? await estado.api.hacer("POST", "/v1/whatsapp/mensajes/\(m.id)/reintentar"); await cargarMensajes() } }
                        .font(Estilo.footnoteFuerte.font).foregroundStyle(C.error)
                }
            }
            if !sal { Spacer(minLength: 60) }
        }
    }

    private var entrada: some View {
        VStack(spacing: 8) {
            if !respuestas.isEmpty && texto.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(respuestas) { r in
                            Button(r.titulo) {
                                texto = r.texto
                                Task { try? await estado.api.hacer("POST", "/v1/respuestas-guardadas/\(r.id)/uso") }
                            }
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                            .padding(.horizontal, 10).frame(height: 30).background(C.hundida, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            HStack(spacing: 6) {
                PhotosPicker(selection: $foto, matching: .images) {
                    Image(systemName: "plus").font(.system(size: 24)).foregroundStyle(C.accion).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Adjuntar una foto")
                TextField("Mensaje", text: $texto, axis: .vertical).estilo(.body16).lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(C.superficie, in: .rect(cornerRadius: 19))
                    .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(C.linea2, lineWidth: 0.5))
                if texto.isEmpty {
                    Image(systemName: grabadora.grabando ? "waveform" : "mic").font(.system(size: 22)).foregroundStyle(grabadora.grabando ? C.error : C.accion)
                        .frame(width: 40, height: 40)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !grabadora.grabando { grabadora.empezar() } }
                            .onEnded { _ in if let u = grabadora.terminar(), let d = try? Data(contentsOf: u) { Task { await mandarArchivo(d, tipo: "audio/mp4", uso: "audio", nombre: "nota.m4a") } } })
                        .accessibilityLabel("Nota de voz: mantené apretado para grabar")
                } else {
                    Button { Task { await mandar() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(C.sobreAccion)
                            .frame(width: 36, height: 36).background(C.accion, in: Circle())
                    }
                    .disabled(enviando)
                    .accessibilityLabel("Mandar")
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var fueraDeVentana: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock").font(.system(size: 20)).foregroundStyle(C.avisoTinta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pasaron más de 24 h desde su último mensaje").estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Text("WhatsApp sólo deja mandar una plantilla aprobada. Cuando responda, seguís escribiendo libre.").estilo(.texto14).foregroundStyle(C.texto2)
                }
            }
            VStack(spacing: 6) {
                ForEach(plantillas.prefix(4)) { p in
                    Button { Task { await mandarPlantilla(p) } } label: {
                        HStack {
                            Text(p.nombre.replacingOccurrences(of: "_", with: " ").capitalized).font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font).foregroundStyle(C.texto)
                            Spacer()
                            Image(systemName: "paperplane").foregroundStyle(C.accion)
                        }
                        .padding(.horizontal, 14).frame(height: 44).background(C.superficie, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if plantillas.isEmpty { Text("Todavía no tenés plantillas aprobadas en Meta.").estilo(.footnote).foregroundStyle(C.texto2) }
            }
        }
        .padding(14)
        .background(C.avisoFondo, in: .rect(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 24)
    }

    // MARK: Datos

    private func cargar() async {
        conv = try? await estado.api.get("/v1/whatsapp/conversaciones/\(id)")
        await cargarMensajes()
        try? await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/leida")
        if plantillas.isEmpty { plantillas = (try? await estado.api.get("/v1/whatsapp/plantillas")) ?? [] }
        if respuestas.isEmpty { respuestas = (try? await estado.api.get("/v1/respuestas-guardadas")) ?? [] }
    }

    private func cargarMensajes() async {
        if let m: [MensajeWA] = try? await estado.api.get("/v1/whatsapp/conversaciones/\(id)/mensajes", query: [.init(name: "limite", value: "200")]) {
            mensajes = m.sorted { $0.ocurrioEn < $1.ocurrioEn }
        }
    }

    private func mandar() async {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        enviando = true
        defer { enviando = false }
        struct Cuerpo: Encodable { var texto: String }
        texto = ""
        do {
            let subio = try await estado.cola.enviar("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(texto: t), etiqueta: "Mensaje a \(conv?.quien ?? "")")
            if !subio { estado.avisar("Sin señal · el mensaje sale cuando vuelva") }
            await cargarMensajes()
        } catch {
            texto = t
            estado.avisar(error)
        }
    }

    private func mandarArchivo(_ d: Data, tipo: String, uso: String, nombre: String) async {
        do {
            let a = try await estado.api.subir(d, nombre: nombre, tipo: tipo, uso: uso)
            struct Cuerpo: Encodable { var texto = ""; var archivoId: String }
            try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(archivoId: a.id))
            await cargarMensajes()
        } catch { estado.avisar(error) }
    }

    private func mandarPlantilla(_ p: PlantillaWA) async {
        struct Datos: Encodable { var nombre: String; var idioma: String; var parametros: [String] }
        struct Cuerpo: Encodable { var texto = ""; var plantilla: Datos }
        let params = Array(repeating: conv?.quien.split(separator: " ").first.map(String.init) ?? "", count: p.parametros ?? 0)
        do {
            try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(plantilla: Datos(nombre: p.nombre, idioma: p.idioma ?? "es_AR", parametros: params)))
            estado.avisar("Plantilla enviada. Cuando responda, se reabre la conversación.")
            await cargarMensajes()
        } catch { estado.avisar(error) }
    }

    private func tomar() async {
        struct Cuerpo: Encodable { var agenteId: String }
        guard let yo = estado.usuario?.id else { return }
        try? await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", Cuerpo(agenteId: yo))
        estado.avisar("La atendés vos")
        await cargar()
    }

    private func archivar() async {
        struct Cuerpo: Encodable { var archivada = true }
        try? await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", Cuerpo())
        estado.version += 1
        estado.avisar("Conversación archivada") {
            Task {
                struct Volver: Encodable { var archivada = false }
                try? await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", Volver())
                estado.version += 1
            }
        }
    }
}

/// Elegir una propiedad de la cartera (vincular un chat, una visita, un contrato).
struct ElegirPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var alElegir: (Propiedad) -> Void
    @State private var q = ""
    @State private var props: [Propiedad] = []

    var body: some View {
        NavigationStack {
            List(props.filter { q.isEmpty || $0.nombre.localizedCaseInsensitiveContains(q) || ($0.barrio ?? "").localizedCaseInsensitiveContains(q) }) { p in
                Button {
                    alElegir(p)
                    cerrar()
                } label: {
                    HStack(spacing: 10) {
                        Foto(url: p.miniatura).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading) { Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto); Text(p.precioTexto).estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                }
            }
            .searchable(text: $q, prompt: "Calle o barrio")
            .navigationTitle("Elegí la propiedad").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .task { props = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "500")])) ?? [] }
        }
    }
}

/// Una nota de voz: play, ondas y la duración.
struct AudioMensaje: View {
    var url: URL?
    @State private var reproductor: AVPlayer?
    @State private var sonando = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if reproductor == nil, let url { reproductor = AVPlayer(url: url) }
                if sonando { reproductor?.pause() } else { reproductor?.seek(to: .zero); reproductor?.play() }
                sonando.toggle()
            } label: {
                Image(systemName: sonando ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30)).foregroundStyle(C.accion)
            }
            .accessibilityLabel(sonando ? "Pausar" : "Escuchar")
            HStack(spacing: 2) {
                ForEach(0..<22, id: \.self) { i in Capsule().fill(C.texto3).frame(width: 3, height: CGFloat(6 + (i * 7) % 18)) }
            }
            .frame(height: 26)
        }
        .frame(width: 196)
    }
}

/// Graba una nota de voz mientras se mantiene apretado el micrófono.
@Observable
@MainActor
final class Grabadora {
    var grabando = false
    private var grabador: AVAudioRecorder?
    private var url: URL?

    func empezar() {
        AVAudioApplication.requestRecordPermission { ok in
            Task { @MainActor in
                guard ok else { return }
                let s = AVAudioSession.sharedInstance()
                try? s.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
                try? s.setActive(true)
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("nota-\(UUID().uuidString).m4a")
                self.url = u
                self.grabador = try? AVAudioRecorder(url: u, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
                self.grabador?.record()
                self.grabando = true
                Haptico.impacto()
            }
        }
    }

    func terminar() -> URL? {
        guard grabando else { return nil }
        let duracion = grabador?.currentTime ?? 0
        grabador?.stop()
        grabando = false
        return duracion > 0.8 ? url : nil
    }
}

/// 6D Pregunta de Mercado Libre: la propiedad, la pregunta y la respuesta armada con los datos de la
/// ficha (sin teléfonos ni mails, que ML no permite).
struct RespuestaML: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State private var p: PreguntaML?
    @State private var prop: Propiedad?
    @State private var texto = ""
    @State private var fuentes: [String] = []
    @State private var enviando = false

    private var prohibido: Bool {
        texto.range(of: #"\d{6,}|@|\b(\d{2,4}[\s-]?){3,}\b"#, options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let prop {
                    Button { estado.abrir(AFichaPropiedad(id: prop.id)) } label: {
                        HStack(spacing: 12) {
                            Foto(url: prop.miniatura).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prop.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                Text("\(prop.operacionTexto.capitalized) · \(prop.ambientes.map { "\($0) amb · " } ?? "")\(prop.precioTexto)").estilo(.texto14).foregroundStyle(C.texto2)
                                HStack(spacing: 6) {
                                    Image("LogoMercadoLibre").resizable().scaledToFit().frame(height: 14)
                                    Text("Publicada en Mercado Libre").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2)
                                }
                            }
                            Spacer()
                            Chevron()
                        }
                        .padding(10).tarjeta()
                    }
                    .buttonStyle(.plain)
                }
                if let p {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(p.compradorApodo ?? "Alguien") preguntó \(p.creadaEn.map { Formato.hace($0) } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                        Text(p.texto ?? "").estilo(.body16).foregroundStyle(C.texto)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(C.superficie, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18))
                            .sombraE2()
                    }
                    if let r = p.respuesta {
                        Label("Respondida: \(r)", systemImage: "checkmark.circle").estilo(.subhead).foregroundStyle(C.okTinta)
                            .padding(14).background(C.okFondo, in: .rect(cornerRadius: 14))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Respuesta armada con los datos de la ficha", systemImage: "sparkles")
                                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
                            TextField("Escribí la respuesta", text: $texto, axis: .vertical).estilo(.body16).lineSpacing(3).lineLimit(3...10)
                            if !fuentes.isEmpty {
                                FlowLayout(espacio: 6) {
                                    ForEach(fuentes, id: \.self) { f in
                                        Text(f).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                                            .padding(.horizontal, 10).frame(height: 30).background(C.hundida, in: Capsule())
                                    }
                                }
                            }
                            Text(prohibido ? "Sacá teléfonos y mails: Mercado Libre no los permite." : "Mercado Libre no permite teléfonos ni mails en las respuestas.")
                                .font(Estilo(tamano: 12, peso: prohibido ? .bold : .regular, relativo: .caption).font).foregroundStyle(prohibido ? C.error : C.texto3)
                        }
                        .padding(14).tarjeta()
                        Button { Task { await responder() } } label: {
                            Text("Responder en Mercado Libre").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font).foregroundStyle(C.sobreAccion)
                                .frame(maxWidth: .infinity, minHeight: 52).background(C.accion, in: .rect(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty || prohibido || enviando)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .pantallaApilada("Mercado Libre")
        .task {
            let l: [PreguntaML] = (try? await estado.api.get("/v1/mercadolibre/preguntas", query: [.init(name: "limite", value: "200")])) ?? []
            p = l.first { $0.id == id }
            if let pid = p?.propiedadId { prop = try? await estado.api.get("/v1/propiedades/\(pid)") }
            struct Sug: Decodable { var sugerencia: String?; var fuentes: [String]? }
            if p?.respuesta == nil, let s: Sug = try? await estado.api.get("/v1/mercadolibre/preguntas/\(id)/sugerencia") {
                if texto.isEmpty { texto = s.sugerencia ?? "" }
                fuentes = s.fuentes ?? []
            }
        }
    }

    private func responder() async {
        enviando = true
        defer { enviando = false }
        struct Cuerpo: Encodable { var texto: String }
        do {
            try await estado.cola.enviar("POST", "/v1/mercadolibre/preguntas/\(id)/respuesta", Cuerpo(texto: texto), etiqueta: "Respuesta en Mercado Libre")
            estado.version += 1
            estado.avisar("Respondida en Mercado Libre")
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// Acomoda chips en renglones (los datos usados, los filtros que no entran en una fila).
struct FlowLayout: Layout {
    var espacio: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x + t.width > ancho, x > 0 { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            alto = max(alto, t.height)
        }
        return CGSize(width: ancho == .infinity ? x : ancho, height: y + alto)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}
