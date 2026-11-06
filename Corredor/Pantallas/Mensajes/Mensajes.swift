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
    /// La conversación de WhatsApp (para los datos de la fila y «Tomar»).
    var conversacion: Conversacion? = nil
}

/// Las vistas de la bandeja (los chips del celular de la web): se piden filtradas a la API.
enum VistaBandeja: String, CaseIterable, Hashable {
    case pendientes, mios, sinDueno, fuera, todas

    var texto: String {
        switch self {
        case .pendientes: return "Sin responder"
        case .mios: return "Míos"
        case .sinDueno: return "Sin dueño"
        case .fuera: return "Fuera de 24 h"
        case .todas: return "Todos"
        }
    }

    var query: [URLQueryItem] {
        switch self {
        case .pendientes: return [.init(name: "esperando", value: "si")]
        case .mios: return [.init(name: "agente", value: "yo")]
        case .sinDueno: return [.init(name: "agente", value: "libre")]
        case .fuera: return [.init(name: "ventana", value: "fuera")]
        case .todas: return []
        }
    }

    func cuenta(_ c: CuentasBandeja?) -> Int? {
        guard let c else { return nil }
        switch self {
        case .pendientes: return c.esperando
        case .mios: return c.mias
        case .sinDueno: return c.sinDueno
        case .fuera: return c.fueraDeVentana
        case .todas: return c.todas
        }
    }
}

/// 6A Bandeja: WhatsApp (con las vistas resueltas en la API), las preguntas de Mercado Libre y las
/// consultas de la web; el estado del número, las plantillas aprobadas y los otros canales.
struct MensajesRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var vista: VistaBandeja?
    @State private var q = ""
    @State private var conversaciones: [Conversacion]?
    @State private var otras: [FilaBandeja] = []
    @State private var cuentas: CuentasBandeja?
    @State private var numero: NumeroWA?
    @State private var plantillas: [PlantillaWA] = []
    @State private var ml: EstadoML?
    @State private var soloML = false
    @State private var tomadas: Set<String> = []
    @State private var error: ErrorApi?
    @State private var nuevo = false

    struct EstadoML: Decodable { var conectada: Bool?; var preguntasSinResponder: Int? }

    private var elegida: VistaBandeja { vista ?? ((cuentas?.esperando ?? 0) > 0 ? .pendientes : .todas) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CabeceraPestana(titulo: "Mensajes",
                                acciones: estado.escribe ? [AccionCabecera(icono: "square.and.pencil", etiqueta: "Mensaje nuevo") { nuevo = true }] : [])
                Buscador(placeholder: "Nombre, número o mensaje…", texto: $q).padding(.horizontal, 16)
                if numero?.conectado == true { chips }
                if let n = numero, n.caido { NumeroCaido(numero: n).padding(.horizontal, 16) }
                if numero?.conectado == false { SinWhatsApp().padding(.horizontal, 16) }
                lista
                otrosBloques
            }
            .padding(.bottom, 32)
        }
        .refreshable { await cargar() }
        .pantallaRaiz()
        .task(id: "\(estado.version)-\(elegida.rawValue)-\(q)") {
            if !q.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            if Task.isCancelled { return }
            await cargar()
        }
        .sheet(isPresented: $nuevo) { MensajeNuevo().presentationDetents([.medium, .large]) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VistaBandeja.allCases, id: \.self) { v in
                    let n = v.cuenta(cuentas) ?? 0
                    ChipFiltro(texto: v.texto + (n > 0 && v != .todas ? " \(n)" : ""), activo: elegida == v && !soloML) {
                        soloML = false
                        vista = v
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
    }

    /// Las filas de la vista: las conversaciones que dio la API, y las preguntas de ML y las consultas
    /// de la web que van en esa vista.
    private var filas: [FilaBandeja] {
        let yo = estado.usuario?.id
        let wa: [FilaBandeja] = soloML ? [] : (conversaciones ?? []).map { (c0: Conversacion) -> FilaBandeja in
            var c = c0
            if tomadas.contains(c.id), c.agenteId == nil { c.agenteId = yo; c.agenteNombre = estado.usuario?.completo }
            return FilaBandeja(id: "wa" + c.id, canal: "wa", nombre: c.quien, texto: c.ultimoTexto ?? "", cuando: c.ultimoMensajeEn, propiedad: c.propiedadTitulo,
                               nuevo: c.esperando ?? ((c.noLeidos ?? 0) > 0), mio: c.agenteId == yo, sinDueno: c.agenteId == nil, fuera: c.fuera,
                               ir: AChat(id: c.id), contactoId: c.contactoId, conversacion: c)
        }
        let f = MasRaiz.normal(q)
        let extra = otras.filter { x in
            let enVista: Bool
            if soloML { enVista = x.canal == "ml" }
            else {
                switch elegida {
                case .pendientes: enVista = x.nuevo
                case .sinDueno: enVista = x.sinDueno
                case .todas: enVista = true
                case .mios, .fuera: enVista = false
                }
            }
            return enVista && (f.isEmpty || MasRaiz.normal(x.nombre + " " + x.texto + " " + (x.propiedad ?? "")).contains(f))
        }
        return (wa + extra).sorted { ($0.cuando ?? .distantPast) > ($1.cuando ?? .distantPast) }
    }

    @ViewBuilder
    private var lista: some View {
        if conversaciones != nil {
            let l = filas
            if l.isEmpty {
                vacio.padding(.top, 20)
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

    @ViewBuilder
    private var vacio: some View {
        if !q.isEmpty {
            EstadoVacio(icono: "magnifyingglass", titulo: "No encontramos «\(q)»", texto: "Probá con el nombre, el número o lo que escribió.",
                        accion: ("Borrar la búsqueda", { q = "" }))
        } else if numero?.conectado == false {
            EmptyView()
        } else {
            EstadoVacio(icono: "bubble.left.and.bubble.right",
                        titulo: elegida == .pendientes && !soloML ? "No hay nadie esperando respuesta" : "No hay conversaciones acá",
                        texto: "WhatsApp, Mercado Libre y tu web entran acá.",
                        accion: elegida != .todas || soloML ? ("Ver todas", { soloML = false; vista = .todas })
                            : (estado.esDuenio ? ("Conectar WhatsApp", { estado.abrir(ASeccion(clave: "integraciones")) }) : nil))
        }
    }

    /// Las plantillas aprobadas con sus usos y los otros canales (el panel de sección de la web).
    @ViewBuilder
    private var otrosBloques: some View {
        if !plantillas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Plantillas aprobadas")
                VStack(spacing: 0) {
                    ForEach(Array(plantillas.prefix(4).enumerated()), id: \.element.id) { i, p in
                        HStack(spacing: 12) {
                            IconoTono(icono: "text.bubble", tono: .neutro, tam: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Charla.nombrePlantilla(p.nombre)).estilo(.filaLista).foregroundStyle(C.texto)
                                Text((p.usos ?? 0) > 0 ? "usada \(p.usos == 1 ? "1 vez" : "\(p.usos ?? 0) veces")" : "sin usar todavía")
                                    .estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
            .padding(.horizontal, 16).padding(.top, 10)
        }
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Otros canales")
            VStack(spacing: 0) {
                canal("storefront", .oro, "Mercado Libre", ml?.conectada == true ? "preguntas" : "sin conectar", cuenta: ml?.preguntasSinResponder ?? 0, primera: true) {
                    if ml?.conectada == true { soloML = true } else { estado.abrir(ASeccion(clave: "mercadolibre")) }
                }
                canal("megaphone", .azul, "Difusión a portales", "Zonaprop, Argenprop", cuenta: 0, primera: false) {
                    estado.abrir(ASeccion(clave: "difusion"))
                }
            }
            .tarjeta()
        }
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private func canal(_ icono: String, _ tono: Tono, _ t: String, _ d: String, cuenta: Int, primera: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                IconoTono(icono: icono, tono: tono, tam: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                    Text(d).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer()
                if cuenta > 0 { InsigniaRoja(n: cuenta) }
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cuando(_ x: FilaBandeja) -> String {
        guard let f = x.cuando else { return "" }
        let cal = Formato.calendario
        if cal.isDateInToday(f) {
            return Date().timeIntervalSince(f) < 6 * 3600 ? Formato.hace(f).replacingOccurrences(of: "hace ", with: "") : Formato.horaDe(f)
        }
        if cal.isDateInYesterday(f) { return x.fuera ? "ayer \(Formato.horaDe(f))" : "ayer" }
        return Formato.dia(f)
    }

    @ViewBuilder
    private func avatar(_ x: FilaBandeja) -> some View {
        Group {
            if x.conversacion?.sinNombre == true {
                Text("+54").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.azulTinta)
                    .frame(width: 48, height: 48).background(C.azulFondo, in: Circle())
            } else {
                Text(Formato.iniciales(x.nombre)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                    .frame(width: 48, height: 48).background(C.hundida, in: Circle())
            }
        }
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
    }

    /// Lo de abajo de la fila, como la web (FilaConversacion): número nuevo, más de 24 h, sin dueño, la
    /// propiedad con las iniciales de quien la tiene, o «de Martín».
    @ViewBuilder
    private func meta(_ x: FilaBandeja) -> some View {
        if let c = x.conversacion {
            if c.sinNombre {
                Text("número nuevo · crear contacto").estilo(.footnote).foregroundStyle(C.azulTinta)
            } else if c.fuera && c.esperando == true {
                Label("más de 24 h · plantilla", systemImage: "clock").font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
                    .foregroundStyle(C.avisoTinta).padding(.horizontal, 8).frame(height: 22).background(C.avisoFondo, in: .rect(cornerRadius: 6))
            } else if c.agenteId == nil {
                Text("sin dueño" + (c.propiedadTitulo.map { " · \($0)" } ?? "")).estilo(.footnote).foregroundStyle(C.avisoTinta).lineLimit(1)
            } else if let p = c.propiedadTitulo {
                HStack(spacing: 6) {
                    if let a = c.agenteNombre { mini(a) }
                    etiqueta(p, C.hundida, C.texto2)
                }
            } else if let a = c.agenteNombre {
                HStack(spacing: 6) { mini(a); Text("de \(Charla.primerNombre(a))").estilo(.footnote).foregroundStyle(C.texto2) }
            }
        } else {
            HStack(spacing: 6) {
                if let p = x.propiedad { etiqueta(p, C.hundida, C.texto2) }
                if x.sinDueno { etiqueta("Sin dueño", C.azulFondo, C.azulTinta) }
            }
        }
    }

    private func mini(_ n: String) -> some View {
        Text(Formato.iniciales(n)).font(Estilo(tamano: 10, peso: .bold, relativo: .caption2).font).foregroundStyle(C.avisoTinta)
            .frame(width: 20, height: 20).background(C.avisoFondo, in: Circle())
    }

    private func fila(_ x: FilaBandeja, primera: Bool) -> some View {
        let c = x.conversacion
        let espera = c?.esperando ?? x.nuevo
        let colorHora: Color = espera ? (x.fuera ? C.error : C.accion) : C.texto3
        let previa = c.map { ($0.esperando == true ? "" : "Vos: ") + ($0.ultimoTexto ?? "") } ?? x.texto
        let sinLeer = c?.noLeidos ?? (x.nuevo ? 1 : 0)
        return HStack(alignment: .center, spacing: 8) {
            Button { estado.abrir(x.ir) } label: {
                HStack(alignment: .top, spacing: 12) {
                    avatar(x)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(x.nombre).font(Estilo(tamano: 16, peso: espera ? .bold : .medium, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                            Spacer()
                            Text(cuando(x)).estilo(.footnote).foregroundStyle(colorHora)
                        }
                        HStack(spacing: 8) {
                            Text(previa).estilo(.texto14).foregroundStyle(C.texto2).lineLimit(1)
                            Spacer()
                            if sinLeer > 0 {
                                if c != nil { InsigniaRoja(n: sinLeer) } else { Circle().fill(C.accion).frame(width: 10, height: 10) }
                            }
                        }
                        meta(x).padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if let c, c.agenteId == nil, estado.escribe {
                Button("Tomar") { Task { await tomarConversacion(c) } }
                    .buttonStyle(BotonTonal())
                    .accessibilityLabel("Tomar la conversación con \(x.nombre)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(espera ? 1 : 0.82)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contextMenu {
            if let c, c.agenteId == nil, estado.escribe {
                Button { Task { await tomarConversacion(c) } } label: { Label("Tomar", systemImage: "person.crop.circle.badge.checkmark") }
            }
            if x.canal == "web", x.sinDueno, estado.escribe, let id = x.contactoId {
                Button { Task { await tomarConsulta(id) } } label: { Label("Tomarla yo", systemImage: "person.crop.circle.badge.checkmark") }
            }
        }
    }

    /// Tomar una sin dueño: queda de la persona al toque; si falla, vuelve y avisa con «Reintentar».
    private func tomarConversacion(_ c: Conversacion) async {
        struct Cuerpo: Encodable { var agenteId: String? }
        tomadas.insert(c.id)
        do {
            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(c.id)", Cuerpo(agenteId: estado.usuario?.id))
            Haptico.exito()
            estado.avisar("Tomaste la conversación con \(c.quien)") {
                Task {
                    do {
                        try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(c.id)", JSONLibre.objeto(["agenteId": .nulo]))
                        tomadas.remove(c.id)
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            estado.version += 1
        } catch {
            tomadas.remove(c.id)
            estado.avisarReintentar(Estado.texto(error, si: "No se guardó")) { Task { await tomarConversacion(c) } }
        }
    }

    private func tomarConsulta(_ contacto: String) async {
        struct C: Encodable { var agenteId: String? }
        do {
            try await estado.api.hacer("POST", "/v1/consultas/\(contacto)/asignar", C(agenteId: estado.usuario?.id))
            estado.avisar("La consulta es tuya")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func etiqueta(_ t: String, _ f: Color, _ c: Color) -> some View {
        Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(c).lineLimit(1)
            .padding(.horizontal, 8).frame(height: 22).background(f, in: .rect(cornerRadius: 6))
    }

    private func cargar() async {
        numero = try? await estado.api.get("/v1/whatsapp/numero")
        cuentas = try? await estado.api.get("/v1/whatsapp/conversaciones/cuentas")
        do {
            var query: [URLQueryItem] = [.init(name: "limite", value: "60")] + elegida.query
            if let t = q.nonEmpty { query.append(.init(name: "q", value: String(t.prefix(120)))) }
            conversaciones = try await estado.api.get("/v1/whatsapp/conversaciones", query: query)
            error = nil
        } catch let e as ErrorApi {
            // Sin WhatsApp conectado la bandeja igual muestra Mercado Libre y la web.
            if conversaciones == nil { if numero?.conectado == false { conversaciones = [] } else { error = e } }
        } catch {}
        let preguntas: [PreguntaML] = (try? await estado.api.get("/v1/mercadolibre/preguntas", query: [.init(name: "limite", value: "50")])) ?? []
        let paginaWeb: PaginaAvisos? = try? await estado.api.get("/v1/avisos", query: [.init(name: "vista", value: "para_hacer"), .init(name: "tipo", value: "consulta"), .init(name: "limite", value: "30")])
        let web = paginaWeb?.avisos ?? []
        var o: [FilaBandeja] = preguntas.map { p in
            FilaBandeja(id: "ml" + p.id, canal: "ml", nombre: p.compradorApodo ?? "Mercado Libre", texto: p.texto ?? "", cuando: p.creadaEn, propiedad: p.propiedad,
                        nuevo: p.estado == "sin_responder" || p.estado == "UNANSWERED", mio: true, sinDueno: false, fuera: false, ir: APreguntaML(id: p.id))
        }
        o += web.map { a in
            FilaBandeja(id: "web" + a.id, canal: "web", nombre: a.titulo ?? "Consulta desde tu web", texto: a.cuerpo ?? "", cuando: a.creadoEn, propiedad: nil,
                        nuevo: !a.estaHecho, mio: false, sinDueno: true, fuera: false,
                        ir: a.url.flatMap { Ruta(texto: $0)?.destino } ?? AnyHashable(AAvisos()),
                        contactoId: a.url.flatMap { Ruta(texto: $0)?.destino as? AFichaContacto }?.id)
        }
        otras = o
        if numero?.conectado == true, plantillas.isEmpty { plantillas = (try? await estado.api.get("/v1/whatsapp/plantillas")) ?? [] }
        ml = try? await estado.api.get("/v1/mercadolibre")
        await Insignias.compartidas.refrescar(estado)
    }
}

/// El número caído en Meta (desconectado, restringido o limitado), con el motivo, cuándo y la salida
/// para el dueño (web: lib/mensajes/NumeroCaido.svelte).
struct NumeroCaido: View {
    @Environment(Estado.self) private var estado
    var numero: NumeroWA

    private var cuando: String {
        guard let f = numero.estadoEn else { return "" }
        let cal = Formato.calendario
        if cal.isDateInToday(f) { return "a las \(Formato.horaDe(f))" }
        if cal.isDateInYesterday(f) { return "ayer a las \(Formato.horaDe(f))" }
        return "el \(Formato.fechaLarga(f))"
    }

    private var pieza: (icono: String, titulo: String, texto: String, boton: String, oro: Bool) {
        switch numero.estado {
        case "restringido":
            return ("nosign", "Meta restringió el WhatsApp\(cuando.isEmpty ? "" : " " + cuando)",
                    "Lo que mandes no sale hasta que Meta lo resuelva; lo que te escriban entra igual.", "Revisar", false)
        case "limitado":
            let desde = cuando.isEmpty ? "" : " desde " + (cuando.hasPrefix("a las") ? "las" + cuando.dropFirst(5) : cuando)
            return ("gauge.with.dots.needle.33percent", "WhatsApp está limitado\(desde)",
                    "Por ahora salen menos mensajes por día. Contestá a tiempo y sin repetir plantillas para que vuelva a la normalidad.", "Ver el número", true)
        default:
            return ("link", "WhatsApp se desconectó\(cuando.isEmpty ? "" : " " + cuando)",
                    "Los mensajes que lleguen mientras tanto no se pierden: entran cuando reconectes.", "Reconectar", false)
        }
    }

    var body: some View {
        let p = pieza
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: p.icono).font(.system(size: 20, weight: .semibold)).foregroundStyle(p.oro ? C.avisoTinta : C.errorTinta)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.titulo).estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(Formato.sinViudas((numero.estadoMotivo.map { "\($0) " } ?? "") + p.texto)).estilo(.texto14).foregroundStyle(C.texto2)
                if estado.esDuenio {
                    Button(p.boton) { estado.abrir(ASeccion(clave: "integraciones")) }.buttonStyle(BotonTonal()).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(p.oro ? C.avisoFondo : C.errorFondo, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Sin WhatsApp conectado (web: lib/mensajes/SinWhatsApp.svelte): la conversación fantasma y la salida.
struct SinWhatsApp: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hola, ¿sigue disponible el 3 amb?").estilo(.texto14).foregroundStyle(C.texto2)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(C.hundida, in: .rect(cornerRadius: 14))
                Text("vinculada a la propiedad").estilo(.footnote).foregroundStyle(C.texto3)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .accessibilityHidden(true)
            Text("Las consultas van a entrar acá, ordenadas por propiedad").estilo(.headline).foregroundStyle(C.texto)
            Text(Formato.sinViudas("El número sigue andando en tu teléfono. El equipo lo comparte acá.")).estilo(.subhead).foregroundStyle(C.texto2)
            if estado.esDuenio {
                Button { estado.abrir(ASeccion(clave: "integraciones")) } label: {
                    HStack(spacing: 8) { Image("LogoWhatsApp").resizable().frame(width: 18, height: 18); Text("Conectar WhatsApp") }
                }
                .buttonStyle(BotonPrincipal())
            }
        }
        .padding(20).tarjeta()
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
            .overlay {
                if q.count >= 2 && res.isEmpty {
                    EstadoVacio(icono: "person.crop.circle.badge.questionmark", titulo: "No encontramos «\(q)»", texto: "Probá con el nombre o el teléfono.")
                } else if q.count < 2 {
                    EstadoVacio(icono: "magnifyingglass", titulo: "¿A quién le escribís?", texto: "Buscá el contacto por nombre o teléfono.")
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

/// Un mensaje de WhatsApp (whatsapp.Mensaje).
struct MensajeWA: Codable, Identifiable, Hashable {
    struct PlantillaUsada: Codable, Hashable { var nombre: String?; var parametros: [String]? }
    var id: String
    var conversacionId: String?
    var direccion: String
    var tipo: String?
    var texto: String?
    var plantilla: PlantillaUsada?
    var mediaTipo: String?
    var archivoId: String?
    var archivoUrl: String?
    var estado: String?
    var error: String?
    var autorId: String?
    var ocurrioEn: Date
    var saliente: Bool { direccion == "saliente" || direccion == "out" }
    /// Mandado desde acá y todavía sin respuesta de la API.
    var local: Bool { id.hasPrefix("tmp-") }
}

/// Una plantilla aprobada en Meta, con cuántas veces se mandó.
struct PlantillaWA: Codable, Identifiable, Hashable {
    var nombre: String
    var idioma: String?
    var categoria: String?
    var cuerpo: String?
    var parametros: Int?
    var usos: Int?
    var id: String { nombre }
}

struct RespuestaGuardada: Codable, Identifiable, Hashable {
    var id: String
    var titulo: String
    var texto: String
    var usos: Int?
}

/// Elegir una propiedad de la cartera (vincular un chat, una visita, un contrato): las últimas
/// tocadas y, al escribir, la búsqueda del servidor (calle, barrio o código).
struct ElegirPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var alElegir: (Propiedad) -> Void
    @State private var q = ""
    @State private var props: [Propiedad] = []
    @State private var encontradas: [Resultado] = []
    @State private var cargando = true

    var body: some View {
        NavigationStack {
            List {
                if q.count >= 2 {
                    ForEach(encontradas) { r in
                        Button { Task { await elegir(r) } } label: {
                            VStack(alignment: .leading) { Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto); if let s = r.subtitulo { Text(s).estilo(.footnote).foregroundStyle(C.texto2) } }
                        }
                    }
                } else {
                    ForEach(props) { p in
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
                }
            }
            .overlay {
                if q.count >= 2 && encontradas.isEmpty && !cargando {
                    EstadoVacio(icono: "magnifyingglass", titulo: "No encontramos nada con «\(q)».")
                } else if q.count < 2 && props.isEmpty && !cargando {
                    EstadoVacio(icono: "building.2", titulo: "Todavía no hay propiedades", texto: "Cargá la primera y la vinculás acá.",
                                accion: ("Cargar propiedad", { cerrar(); estado.abrir(AAltaPropiedad()) }))
                }
            }
            .searchable(text: $q, prompt: "Calle, barrio o código…")
            .navigationTitle("Elegí la propiedad").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .task {
                props = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "200"), .init(name: "orden", value: "actualizada")])) ?? []
                cargando = false
            }
            .task(id: q) {
                guard q.count >= 2 else { encontradas = []; return }
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                cargando = true
                let r: [Resultado] = (try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "propiedad"), .init(name: "q", value: q)])) ?? []
                encontradas = r.filter { $0.tipo == "propiedad" }
                cargando = false
            }
        }
    }

    private func elegir(_ r: Resultado) async {
        do {
            let p: Propiedad = try await estado.api.get("/v1/propiedades/\(r.id)")
            alElegir(p)
            cerrar()
        } catch { estado.avisar(error) }
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
                    .buttonStyle(Presionable())
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
