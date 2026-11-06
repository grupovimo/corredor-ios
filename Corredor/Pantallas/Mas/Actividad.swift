import SwiftUI

// MARK: - Actividad

/// Un registro de la auditoría (GET /v1/actividad, transversal.Registro).
struct EntradaActividad: Codable, Identifiable, Hashable {
    /// En la API es un número (la auditoría), y sirve para seguir bajando con `antesDe`.
    var id: Int64
    var actorTipo: String?
    var actorId: String?
    var actorNombre: String?
    var accion: String?
    var entidad: String?
    var entidadId: String?
    var antes: JSONLibre?
    var despues: JSONLibre?
    var entidadTitulo: String?
    var creadoEn: Date?
}

/// Lo que hizo la IA de una persona (GET /v1/ia/registro, mcp.Accion).
struct AccionIA: Codable, Identifiable, Hashable {
    var id: Int64
    var usuarioId: String?
    var personaNombre: String?
    var cliente: String?
    var resultado: String?
    var detalle: String?
    var entidad: String?
    var entidadId: String?
    var creadoEn: Date?
}

/// Cada registro dicho en criollo, como la web (lib/configuracion/actividad.ts): «Martín registró el
/// cobro de Lucía Méndez · ARS 816.700», «Sofía pasó Mendoza 2350 a Visita».
enum TextosActividad {
    static let articulo: [String: String] = [
        "propiedad": "la propiedad", "contacto": "el contacto", "operacion": "la operación", "cita": "la cita", "contrato": "el contrato",
        "cobro": "el cobro", "rendicion": "la rendición", "emprendimiento": "el emprendimiento", "consorcio": "el consorcio", "unidad": "la unidad",
        "reserva": "la reserva", "reserva_temporada": "la reserva de temporada", "tarifa_temporada": "la tarifa de temporada", "objetivo": "un objetivo",
        "documento": "un documento", "acta": "el acta", "inventario": "el inventario", "inventario_item": "un ítem del inventario",
        "inmobiliaria": "los datos de la inmobiliaria", "ia_ajustes": "los ajustes de Corredor en tu IA", "ia_conexion": "su asistente de IA",
        "publicacion": "una publicación", "pregunta_ml": "una pregunta de Mercado Libre", "borrador": "un borrador", "importacion": "una importación",
        "periodo_expensas": "las expensas", "recibo_sueldo": "un recibo de sueldo", "link_consorcio": "un link del consorcio",
        "conversacion_whatsapp": "una conversación de WhatsApp", "whatsapp": "WhatsApp", "mercadolibre": "Mercado Libre",
    ]
    static let verbo: [String: String] = [
        "crear": "cargó", "editar": "editó", "borrar": "borró", "borrar_definitivo": "borró del todo", "restaurar": "recuperó", "duplicar": "duplicó",
        "publicar": "publicó", "despublicar": "sacó de la web", "compartir": "compartió", "dejar_de_compartir": "dejó de compartir", "conectar": "conectó",
        "desconectar": "desconectó", "firmar": "firmó", "liquidar": "liquidó", "importar": "importó", "responder": "respondió", "reabrir": "reabrió",
        "soltar": "dejó sin agente", "estado": "cambió el estado de", "cambiar_estado": "cambió el estado de", "descobrar": "anuló el cobro de",
    ]
    static let etapa = ["nuevo": "Nuevo", "contactado": "Contactado", "visita": "Visita", "reserva": "Reserva", "cierre": "Cierre"]
    static let rol = ["duenio": "dueño", "agente": "agente", "lector": "lector"]

    /// El nombre de pila de quien lo hizo, o «Corredor» / «Alguien desde la web».
    static func quien(_ r: EntradaActividad) -> String {
        if r.actorTipo == "sistema" || r.actorNombre?.nonEmpty == nil { return r.actorTipo == "publico" ? "Alguien desde la web" : "Corredor" }
        return Charla.primerNombre(r.actorNombre)
    }

    private static func txt(_ v: JSONLibre?) -> String? { v?.texto?.trimmingCharacters(in: .whitespaces).nonEmpty }
    private static func num(_ v: JSONLibre?) -> Double? { if case .numero(let n)? = v { return n }; return nil }

    /// Lo que hizo, sin el sujeto: «pasó Mendoza 2350 a Visita».
    static func frase(_ r: EntradaActividad) -> String {
        let d = r.despues, a = r.antes
        let accion = r.accion ?? "", entidad = r.entidad ?? ""
        let titulo = r.entidadTitulo?.nonEmpty ?? txt(d?["titulo"]) ?? txt(d?["nombre"]) ?? txt(a?["titulo"]) ?? txt(a?["nombre"])
        let que = titulo ?? articulo[entidad] ?? entidad.replacingOccurrences(of: "_", with: " ")
        if accion.hasPrefix("ia.") { return "usó su IA: \(accion.dropFirst(3).replacingOccurrences(of: "_", with: " "))" }
        switch "\(accion):\(entidad)" {
        case "mover:operacion":
            let e = txt(d?["etapa"]) ?? ""
            return "pasó \(que) a \(etapa[e] ?? e)"
        case "caer:operacion":
            return "dio por caída \(que)\(txt(d?["motivo"]).map { " · \($0.lowercased())" } ?? "")"
        case "cobrar:contrato":
            return "registró el cobro de \(que)\(num(d?["monto"]).map { " · " + Formato.plata($0, txt(d?["moneda"]) ?? "ARS") } ?? "")"
        case "editar:propiedad":
            if let p0 = num(a?["precio"]), let p1 = num(d?["precio"]), p0 != p1 { return "cambió el precio de \(que): \(Formato.numero(Int(p0))) → \(Formato.numero(Int(p1)))" }
        case "crear:contacto": return "cargó a \(que)"
        case "crear:operacion": return "abrió la operación \(que)"
        case "crear:cita": return "agendó \(que)"
        case "invitar:invitacion":
            let r0 = txt(d?["rol"]) ?? ""
            return "invitó a \(txt(d?["email"]) ?? "alguien") como \(rol[r0] ?? r0)"
        case "cambiar_rol:miembro":
            let r0 = txt(d?["rol"]) ?? ""
            return "cambió el rol de alguien del equipo a \(rol[r0] ?? r0)"
        case "sacar:miembro": return "sacó a alguien del equipo"
        case "verificar_dominio:inmobiliaria": return "verificó el dominio \(txt(d?["dominio"]) ?? "")".trimmingCharacters(in: .whitespaces)
        case "regenerar_clave_feed:inmobiliaria": return "generó otra clave para los feeds de los portales"
        case "enviar_plantilla:conversacion_whatsapp": return "mandó una plantilla por WhatsApp"
        default: break
        }
        let v = verbo[accion] ?? accion.replacingOccurrences(of: "_", with: " ")
        if let titulo, articulo[entidad] != nil { return "\(v) \(titulo)" }
        return "\(v) \(que)"
    }
}

/// Actividad, como la del panel (47): quién hizo qué y cuándo, mezclado por hora con lo que hizo la
/// IA de cada persona; Todo · Personas · La IA; por persona (el dueño); por día; y «Ver más».
struct Actividad: View {
    @Environment(Estado.self) private var estado
    @State private var registros: [EntradaActividad]?
    @State private var ia: [AccionIA] = []
    @State private var equipo: [Miembro] = []
    /// «ia» abre filtrado en lo que hizo la IA («Ver todo» del Inicio).
    var filtro: String? = nil
    @State private var de = "todo"
    @State private var persona = ""
    @State private var error: ErrorApi?
    @State private var hayMas = false
    @State private var bajando = false
    private static let pagina = 50

    private enum Linea: Identifiable {
        case persona(EntradaActividad), ia(AccionIA)
        var id: String { switch self { case .persona(let r): return "p\(r.id)"; case .ia(let a): return "i\(a.id)" } }
        var en: Date { switch self { case .persona(let r): return r.creadoEn ?? .distantPast; case .ia(let a): return a.creadoEn ?? .distantPast } }
    }

    /// Mezcladas por hora. Con la actividad de personas paginando, la IA entra sólo en la misma ventana.
    private var lineas: [Linea] {
        let rs = registros ?? []
        let piso = de == "todo" && hayMas ? rs.last?.creadoEn : nil
        let l: [Linea] = rs.map { .persona($0) } + ia.filter { a in piso.map { (a.creadoEn ?? .distantPast) >= $0 } ?? true }.map { .ia($0) }
        return l.sorted { $0.en > $1.en }
    }

    private var grupos: [(String, [Linea])] {
        var g: [(String, [Linea])] = []
        let cal = Formato.calendario
        for l in lineas {
            let t = cal.isDateInToday(l.en) ? "Hoy" : cal.isDateInYesterday(l.en) ? "Ayer" : Formato.dia(l.en)
            if g.last?.0 == t { g[g.count - 1].1.append(l) } else { g.append((t, [l])) }
        }
        return g
    }

    var body: some View {
        contenido.onAppear { if let filtro, de == "todo" { de = filtro } }
    }

    private var contenido: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(estado.rol == "agente" ? "Lo que hiciste vos y tu IA, lo último primero." : "Quién hizo qué y cuándo. También lo que hizo la IA de cada persona.")
                    .estilo(.subhead).foregroundStyle(C.texto2)
                Segmentado(opciones: [("todo", "Todo"), ("personas", "Personas"), ("ia", "La IA")], elegido: $de)
                if estado.rol != "agente" && equipo.count > 1 {
                    Picker("Persona", selection: $persona) {
                        Text("Todo el equipo").tag("")
                        ForEach(equipo) { Text($0.completo).tag($0.usuarioId) }
                    }
                    .pickerStyle(.menu).tint(C.accion)
                }
                contenido
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Actividad")
        .task(id: "\(estado.version)-\(de)-\(persona)") { await cargar() }
    }

    @ViewBuilder
    private var contenido: some View {
        if registros != nil {
            if lineas.isEmpty {
                EstadoVacio(icono: de == "ia" ? "sparkles" : "clock.arrow.circlepath",
                            titulo: de == "ia" ? "La IA todavía no hizo nada" : "Todavía no hay actividad",
                            texto: de == "ia" ? "Cuando alguien conecte su asistente, cada cosa que haga queda acá." : "Cada cambio del equipo aparece acá con quién lo hizo y cuándo.",
                            accion: de != "todo" || !persona.isEmpty ? ("Ver todo", { de = "todo"; persona = "" }) : nil)
                    .padding(.top, 30)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grupos, id: \.0) { titulo, ls in
                        Text(titulo).estilo(.label).foregroundStyle(C.texto2).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                        ForEach(ls) { l in linea(l) }
                    }
                    if hayMas {
                        Button(bajando ? "Cargando…" : "Ver más") { Task { await masViejos() } }
                            .buttonStyle(BotonTexto()).disabled(bajando)
                    }
                }
                .tarjeta()
            }
        } else if let error {
            EstadoError(que: "la actividad", error: error) { Task { await cargar() } }
        } else { EsqueletoFilas(filas: 6) }
    }

    @ViewBuilder
    private func linea(_ l: Linea) -> some View {
        switch l {
        case .persona(let r):
            Button { abrir(r.entidad, r.entidadId) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(r.creadoEn.map { Formato.horaDe($0) } ?? "").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3).frame(width: 40, alignment: .leading)
                    (Text(TextosActividad.quien(r)).bold() + Text(" " + TextosActividad.frase(r))).estilo(.subhead).foregroundStyle(C.texto)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
        case .ia(let a):
            Button { abrir(a.entidad, a.entidadId) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(a.creadoEn.map { Formato.horaDe($0) } ?? "").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3).frame(width: 40, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label("IA", systemImage: "sparkles").font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font)
                            .foregroundStyle(a.resultado == "ok" ? C.violetaTinta : C.errorTinta)
                            .padding(.horizontal, 6).frame(height: 20).background(a.resultado == "ok" ? C.violetaFondo : C.errorFondo, in: Capsule())
                        (Text(a.detalle ?? "") + Text(" · ") + Text(Charla.primerNombre(a.personaNombre).nonEmpty ?? "Alguien").bold())
                            .estilo(.subhead).foregroundStyle(a.resultado == "ok" ? C.texto : C.errorTinta)
                            .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
        }
    }

    private func pedirRegistros(antesDe: Int64?) async throws -> [EntradaActividad] {
        var q: [URLQueryItem] = [.init(name: "limite", value: "\(Self.pagina)")]
        if !persona.isEmpty { q.append(.init(name: "actor", value: persona)) }
        if let antesDe { q.append(.init(name: "antesDe", value: "\(antesDe)")) }
        return try await estado.api.get("/v1/actividad", query: q)
    }

    private func pedirIA(antesDe: Int64?) async -> [AccionIA] {
        var q: [URLQueryItem] = [.init(name: "limite", value: "\(Self.pagina)")]
        if !persona.isEmpty { q.append(.init(name: "persona", value: persona)) }
        if let antesDe { q.append(.init(name: "antesDe", value: "\(antesDe)")) }
        return (try? await estado.api.get("/v1/ia/registro", query: q)) ?? []
    }

    private func cargar() async {
        do {
            var rs: [EntradaActividad] = []
            if de != "ia" { rs = try await pedirRegistros(antesDe: nil) }
            registros = rs
            var x: [AccionIA] = []
            if de != "personas" { x = await pedirIA(antesDe: nil) }
            ia = x
            hayMas = de == "ia" ? ia.count == Self.pagina : rs.count == Self.pagina
            error = nil
        } catch let e as ErrorApi { if registros == nil { error = e } } catch {}
        if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
    }

    /// La página siguiente: lo anterior al último que se ve (`antesDe`, sin saltos aunque entren nuevos).
    private func masViejos() async {
        bajando = true
        defer { bajando = false }
        do {
            if de == "ia" {
                guard let u = ia.last?.id else { return }
                let l = await pedirIA(antesDe: u)
                ia += l
                hayMas = l.count == Self.pagina
            } else {
                guard let u = registros?.last?.id else { return }
                let l = try await pedirRegistros(antesDe: u)
                registros = (registros ?? []) + l
                if de == "todo", let iu = ia.last?.id {
                    let mas = await pedirIA(antesDe: iu)
                    ia += mas
                }
                hayMas = l.count == Self.pagina
            }
        } catch { estado.avisar(error) }
    }

    private func abrir(_ entidad: String?, _ id: String?) {
        guard let id else { return }
        switch entidad {
        case "propiedad": estado.abrir(AFichaPropiedad(id: id))
        case "contacto": estado.abrir(AFichaContacto(id: id))
        case "operacion": estado.abrir(AFichaOperacion(id: id))
        case "contrato": estado.abrir(AFichaContrato(id: id))
        case "cita": estado.abrir(ACita(id: id))
        default: break
        }
    }
}
