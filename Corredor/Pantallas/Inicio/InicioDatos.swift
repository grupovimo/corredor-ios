import Foundation
import SwiftUI

// Lo que trae el Inicio y las cuentas puras que hace con eso, como el panel web
// (routes/panel/(app)/+page.server.ts, lib/inicio/modelo.ts y lib/inicio/guia.ts): lo urgente en su
// orden, el ritmo de cada objetivo, los primeros pasos, el próximo paso y las acciones rápidas.

// MARK: - Modelos (con la forma de la API)

/// GET /v1/panel/guia completo (api/internal/dominio/panel/guia.go): los pasos, los usos y el alta.
struct GuiaInicio: Codable {
    struct Usos: Codable {
        var captar: Int?
        var propiedad: Int?
        var contacto: Int?
        var visita: Int?
        var cobro: Int?
    }
    var tourVisto: Bool?
    var pasosOcultos: Bool?
    var pasos: Guia.Pasos?
    var usos: Usos?
    var contratos: Int?
    var propiedades: Int?
    var contactos: Int?
    var alta: Alta?
}

/// Una sugerencia de GET /v1/panel (sugerencias.Sugerencia), con el consorcio y el agente.
struct SugerenciaInicio: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var estado: String?
    var accion: String?
    var destacado: String?
    var motivo: String?
    var operacionId: String?
    var contactoId: String?
    var propiedadId: String?
    var contratoId: String?
    var consorcioId: String?
    var agenteId: String?

    /// El botón según el tipo (accionSugerencia del panel): el texto y a dónde lleva.
    var boton: (String, AnyHashable?) {
        switch tipo {
        case "coincidencia": return ("Mandarle la ficha", contactoId.map { AnyHashable(AFichaContacto(id: $0)) } ?? AnyHashable(AContactos()))
        case "contacto_frio": return ("Escribirle", contactoId.map { AnyHashable(AFichaContacto(id: $0)) } ?? AnyHashable(AContactos()))
        case "operacion_estancada", "seguimiento_cierre":
            return ("Ver la operación", operacionId.map { AnyHashable(AFichaOperacion(id: $0)) } ?? AnyHashable(AOperaciones()))
        case "ajuste_alquiler": return ("Avisar al inquilino", contratoId.map { AnyHashable(AFichaContrato(id: $0)) } ?? AnyHashable(AContratos()))
        case "contrato_por_vencer": return ("Ver el contrato", contratoId.map { AnyHashable(AFichaContrato(id: $0)) } ?? AnyHashable(AContratos()))
        case "unidad_morosa", "servicio_por_vencer":
            return ("Ver el consorcio", consorcioId.map { AnyHashable(ASeccion(clave: "consorcio", id: $0)) } ?? AnyHashable(ASeccion(clave: "consorcios")))
        default: return ("Ver", nil)
        }
    }

    /// «{accion} {destacado}. {motivo}.»
    var frase: String {
        let partes = [[accion, destacado].compactMap { $0?.nonEmpty }.joined(separator: " "), motivo?.nonEmpty].compactMap { $0?.nonEmpty }
        return partes.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
    }
}

/// Lo de GET /v1/panel que el modelo común no lee: la primera rendición lista y las sugerencias completas.
struct PanelInicio: Decodable {
    struct Rendicion: Decodable, Hashable { var id: String; var contratoId: String }
    struct Numeros: Decodable { var primeraRendicion: Rendicion? }
    var numeros: Numeros?
    var sugerencias: [SugerenciaInicio]?
}

/// Un aviso de consulta web (GET /v1/avisos?vista=para_hacer&tipo=consulta; avisos.Aviso).
struct AvisoConsulta: Decodable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var titulo: String?
    var cuerpo: String?
    var url: String?
    var datos: JSONLibre?
    var responsableId: String?
    var responsableNombre: String?
    var creadoEn: Date?

    var contactoId: String? { datos?["contactoId"]?.texto?.nonEmpty }
    var propiedad: String? { datos?["propiedad"]?.texto?.nonEmpty }
}

struct ListaAvisosConsulta: Decodable { var avisos: [AvisoConsulta] }

/// Una reserva que vence (GET /v1/reservas?vencen=2; reservas.Reserva).
struct ReservaInicio: Decodable, Identifiable, Hashable {
    var id: String
    var propiedadId: String?
    var propiedadTitulo: String?
    var contactoNombre: String?
    var interesadoNombre: String?
    var sena: Double?
    var senaMoneda: String?
    var venceEl: String?
    var notas: String?
}

/// El número de WhatsApp (GET /v1/whatsapp/numero): si se cayó en Meta, el Inicio lo avisa.
struct NumeroWhatsApp: Decodable, Hashable {
    var conectado: Bool?
    var estado: String?
    var estadoMotivo: String?
    var estadoEn: Date?
    /// Conectado en Corredor y caído en Meta.
    var caido: Bool { conectado == true && (estado ?? "conectado") != "conectado" }
}

/// GET /v1/clima (204 si la inmobiliaria no tiene dónde ubicarse).
struct Clima: Decodable, Hashable {
    var zona: String
    var temperatura: Int
    var codigo: Int?
}

/// Una deuda de GET /v1/contratos/deudas (contratos.Deuda), con el vencimiento de cada mes.
struct DeudaInicio: Decodable, Identifiable, Hashable {
    struct Mes: Decodable, Hashable { var periodo: String?; var vence: String?; var esperado: Double? }
    var contratoId: String
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var agenteId: String?
    var moneda: String?
    var meses: [Mes]?
    var total: Double?
    var id: String { contratoId }
}

/// Un alquiler del mes (cobrado, pendiente o atrasado), con la deuda o con la fila de Cobranzas.
struct CobranzaInicio: Hashable {
    var contratoId: String
    var propiedadTitulo: String?
    var contactoNombre: String?
    var agenteId: String?
    var monto: Double
    var moneda: String
    var vence: String
    var estado: String
    /// Lo del mes más viejo que se debe (lo que propone «Registrar cobro»).
    var montoMes: Double? = nil
}

/// Una persona en «El equipo hoy».
struct PersonaHoy: Identifiable, Hashable {
    var id: String
    var nombre: String
    var foto: String?
    var telefono: String?
    var citas: [(String, Int)]
    var sinResponder: Int
    var desde: Date?
    var licencia: (tipo: String, vuelve: String)?

    static func == (a: PersonaHoy, b: PersonaHoy) -> Bool { a.id == b.id && a.sinResponder == b.sinResponder }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// La próxima visita con lo de la propiedad y el contacto.
struct ProximaVisita: Hashable {
    var cita: Cita
    var foto: String?
    var fotos: Int
    var direccion: String?
    var operacion: String?
    var precio: Double?
    var moneda: String?
    var telefono: String?
}

/// Una fila de lo urgente (lib/inicio/modelo.ts · Urgente), en la versión del celular.
struct Urgente: Identifiable, Hashable {
    enum Tipo: Int { case cobro, consulta, reserva, pregunta, whatsapp }
    var id: String
    var tipo: Tipo
    var icono: String
    var tono: Tono
    var titulo: String
    var detalle: String
    var detalleTono: Tono?
    var ir: AnyHashable?
    var agenteId: String?
    /// Cobro: el contrato, el mes que se debe y el monto (para «Recordar» y «Registrar cobro»).
    var cobranza: CobranzaInicio?
    /// Consulta sin dueño: el contacto para «Asignar» o «Tomarla».
    var consultaContacto: String?

    static func == (a: Urgente, b: Urgente) -> Bool { a.id == b.id && a.titulo == b.titulo && a.detalle == b.detalle && a.consultaContacto == b.consultaContacto }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Un objetivo con su ritmo (modelo.ts · ritmo).
struct RitmoInicio: Identifiable, Hashable {
    var id: String
    var nombre: String
    var avance: Double
    var meta: Double
    var ancho: Double
    var raya: Double
    var adelante: Bool
    var falta: Int
    var moneda: String?
}

/// Un paso de «Primeros pasos» (guia.ts · Paso).
struct PasoInicio: Identifiable, Hashable {
    var clave: String
    var texto: String
    var boton: String
    var hecho: Bool
    var id: String { clave }
}

/// El próximo paso útil cuando no hay nada urgente (guia.ts · Proximo).
struct ProximoInicio: Identifiable, Hashable {
    var clave: String
    var icono: String
    var titulo: String
    var detalle: String
    var boton: String
    var secundario: String?
    var id: String { clave }
}

/// Una acción rápida (guia.ts · AccionRapida).
struct AccionInicio: Identifiable, Hashable {
    var clave: String
    var texto: String
    var icono: String
    var id: String { clave }
}

/// Lo que trae el Inicio (todo de una, para pintar una sola vez).
struct DatosInicio {
    var panel: Panel?
    var panelExtra: PanelInicio?
    var guia: GuiaInicio?
    var conversaciones: [Conversacion] = []
    var preguntas: [PreguntaML] = []
    var consultas: [AvisoConsulta] = []
    var reservas: [ReservaInicio] = []
    var deudas: [DeudaInicio]?
    var cobranzas: MesCobranzas?
    var agenda: [Cita] = []
    var equipo: [Miembro] = []
    var licencias: [Licencia] = []
    var numero: NumeroWhatsApp?
    var clima: Clima?
    var avisos = 0
    /// La inmobiliaria con su marca (logo, portada, web): el Inicio es de ella, no genérico.
    var inmo: Inmobiliaria?
    /// Las propiedades recién movidas, para «Tu cartera».
    var props: [Propiedad] = []
    var proxima: ProximaVisita?
    /// Los bloques que no llegaron (7C «Error parcial»): «mensajes», «agenda», «cobranzas».
    var fallo: Set<String> = []
    /// Cuándo se trajo (sin señal: «Actualizado a las…»).
    var actualizado = Date()
    var sinRed = false
}

// MARK: - Las cuentas del Inicio

enum CuentasInicio {
    /// De noche (desde las 20) el Inicio mira a mañana.
    static func deNoche(_ ahora: Date = Date()) -> Bool {
        let h = Formato.calendario.component(.hour, from: ahora)
        return h >= 20 || h < 5
    }

    /// «Buen día» hasta las 13, «Buenas tardes» hasta las 20, después «Buenas noches».
    static func saludo(_ ahora: Date = Date()) -> String {
        let h = Formato.calendario.component(.hour, from: ahora)
        if h >= 5 && h < 13 { return "Buen día" }
        if h >= 13 && h < 20 { return "Buenas tardes" }
        return "Buenas noches"
    }

    static let palabras = ["Ninguna", "Una", "Dos", "Tres", "Cuatro", "Cinco", "Seis", "Siete", "Ocho", "Nueve", "Diez"]

    /// «Cuatro cosas no esperan.»
    static func cosasQueNoEsperan(_ n: Int) -> String {
        if n == 1 { return "Una cosa no espera." }
        return "\(n < palabras.count ? palabras[n] : String(n)) cosas no esperan."
    }

    /// «Quedaron tres cosas para mañana.»
    static func cosasParaManana(_ n: Int) -> String {
        if n == 1 { return "Quedó una cosa para mañana." }
        return "Quedaron \((n < palabras.count ? palabras[n] : String(n)).lowercased()) cosas para mañana."
    }

    /// Los días de lunes a viernes que quedan en el mes, contando hoy.
    static func diasHabilesRestantes(_ ahora: Date = Date()) -> Int {
        let c = Formato.calendario
        guard let rango = c.range(of: .day, in: .month, for: ahora) else { return 0 }
        let hoy = c.component(.day, from: ahora)
        var n = 0
        for d in hoy...rango.upperBound - 1 {
            var x = c.dateComponents([.year, .month], from: ahora)
            x.day = d
            if let f = c.date(from: x) {
                let s = c.component(.weekday, from: f)
                if s != 1 && s != 7 { n += 1 }
            }
        }
        return n
    }

    /// «Jueves 12».
    static func diaCorto(_ ahora: Date = Date()) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "es_AR")
        d.timeZone = Formato.calendario.timeZone
        d.dateFormat = "EEEE d"
        return Formato.mayuscula(d.string(from: ahora))
    }

    /// «9:30» (sin el cero de adelante).
    static func horaCorta(_ f: Date) -> String {
        let h = Formato.horaDe(f)
        return h.hasPrefix("0") ? String(h.dropFirst()) : h
    }

    /// Días entre dos fechas (por día calendario).
    static func diasEntre(_ a: Date, _ b: Date) -> Int {
        let c = Formato.calendario
        return c.dateComponents([.day], from: c.startOfDay(for: a), to: c.startOfDay(for: b)).day ?? 0
    }

    /// «en 25 min», «hace 2 h», «recién» (la `relativa` del panel).
    static func relativa(_ f: Date, _ ahora: Date = Date()) -> String {
        let s = f.timeIntervalSince(ahora)
        if s > 0 {
            let m = Int((s / 60).rounded(.up))
            if m < 60 { return "en \(m)\u{2009}min" }
            let h = m / 60
            if h < 24 { return "en \(h)\u{2009}h" }
            return "en \(Formato.cantidad(h / 24, "día", "días"))"
        }
        return Formato.hace(f, ahora: ahora)
    }

    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// «venció hace 2 días» / «venció ayer» / «vence hoy».
    static func vencio(_ vence: String, _ ahora: Date = Date()) -> String {
        guard let f = Fecha.dia(vence) else { return "" }
        let d = diasEntre(f, ahora)
        if d <= 0 { return "vence hoy" }
        if d == 1 { return "venció ayer" }
        return "venció hace\u{00A0}\(d)\u{00A0}días"
    }

    /// «vence mañana», «vence hoy», «vence el jueves 12».
    static func vence(_ fecha: String, _ ahora: Date = Date()) -> String {
        guard let f = Fecha.dia(fecha) else { return "" }
        let d = diasEntre(ahora, f)
        if d <= 0 { return "vence hoy" }
        if d == 1 { return "vence mañana" }
        let x = DateFormatter()
        x.locale = Locale(identifier: "es_AR")
        x.dateFormat = "EEEE d"
        return "vence el " + x.string(from: f)
    }

    /// «el jueves 12» (sin el mes).
    static func elDia(_ fecha: String) -> String {
        guard let f = Fecha.dia(fecha) else { return fecha }
        let x = DateFormatter()
        x.locale = Locale(identifier: "es_AR")
        x.dateFormat = "EEEE d"
        return x.string(from: f)
    }

    /// El día que vuelve quien está de licencia: el siguiente al último, salteando el fin de semana.
    static func vuelveDe(_ hasta: String) -> String {
        guard var d = Fecha.dia(hasta) else { return hasta }
        let c = Formato.calendario
        repeat {
            d = c.date(byAdding: .day, value: 1, to: d) ?? d
        } while [1, 7].contains(c.component(.weekday, from: d))
        return Formato.diaISO(d)
    }

    // MARK: Lo urgente

    static func cobroUrgente(_ c: CobranzaInicio, _ ahora: Date = Date()) -> Urgente {
        let quien = c.contactoNombre ?? "El inquilino"
        let cuando = vencio(c.vence, ahora)
        return Urgente(id: "cobro:" + c.contratoId, tipo: .cobro, icono: "dollarsign.circle", tono: .rojo,
                       titulo: "\(quien) no pagó", detalle: "\(Formato.mayuscula(cuando)) · \(Formato.plata(c.monto, c.moneda))", detalleTono: .rojo,
                       ir: AFichaContrato(id: c.contratoId), agenteId: c.agenteId, cobranza: c)
    }

    static func consultaUrgente(_ a: AvisoConsulta, _ ahora: Date = Date()) -> Urgente {
        let libre = a.responsableId == nil
        let cuando = a.creadoEn.map { relativa($0, ahora) } ?? ""
        let detalle = [a.propiedad, cuando.nonEmpty].compactMap { $0 }.joined(separator: " · ")
        let ir: AnyHashable? = a.url.flatMap { Ruta(texto: $0)?.destino } ?? a.contactoId.map { AnyHashable(AFichaContacto(id: $0)) }
        return Urgente(id: "consulta:" + a.id, tipo: .consulta, icono: "globe", tono: .azul,
                       titulo: libre ? "Consulta sin dueño" : (a.titulo ?? "Consulta"),
                       detalle: libre ? detalle : [detalle.nonEmpty, a.responsableNombre].compactMap { $0 }.joined(separator: " · "),
                       ir: ir, agenteId: a.responsableId, consultaContacto: libre ? a.contactoId : nil)
    }

    static func reservaUrgente(_ r: ReservaInicio, _ ahora: Date = Date()) -> Urgente {
        let cuando = r.venceEl.map { vence($0, ahora) } ?? ""
        let sena = r.sena.flatMap { $0 > 0 ? Formato.plata($0, r.senaMoneda ?? "ARS") : nil }
        return Urgente(id: "reserva:" + r.id, tipo: .reserva, icono: "bookmark", tono: .oro,
                       titulo: "Reserva \(r.propiedadTitulo ?? "")",
                       detalle: [Formato.mayuscula(cuando).nonEmpty, sena].compactMap { $0 }.joined(separator: " · "), detalleTono: .oro,
                       ir: AReserva(id: r.id))
    }

    static func preguntaUrgente(_ q: PreguntaML, _ ahora: Date = Date()) -> Urgente {
        let cuando = q.creadaEn.map { relativa($0, ahora) } ?? ""
        return Urgente(id: "pregunta:" + q.id, tipo: .pregunta, icono: "storefront", tono: .oro,
                       titulo: "Pregunta en Mercado Libre",
                       detalle: [q.propiedad?.nonEmpty, cuando.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                       ir: APreguntaML(id: q.id))
    }

    static func whatsappUrgente(_ c: Conversacion, _ ahora: Date = Date()) -> Urgente {
        let cuando = (c.ultimoEntranteEn ?? c.ultimoMensajeEn).map { relativa($0, ahora) } ?? ""
        let texto = c.ultimoTexto?.nonEmpty.map { "«\($0.trimmingCharacters(in: .whitespacesAndNewlines))»" }
        return Urgente(id: "whatsapp:" + c.id, tipo: .whatsapp, icono: "bubble.left", tono: .verde,
                       titulo: c.quien, detalle: [texto, cuando.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                       ir: AChat(id: c.id), agenteId: c.agenteId)
    }

    /// Cobros, consultas, reservas, preguntas, WhatsApp; adentro, en el orden de la API (lo más viejo primero).
    static func ordenar(_ us: [Urgente]) -> [Urgente] {
        us.enumerated().sorted { a, b in
            a.element.tipo.rawValue != b.element.tipo.rawValue ? a.element.tipo.rawValue < b.element.tipo.rawValue : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Objetivos

    static let nombresMetricas: [String: String] = [
        "operaciones_cerradas": "Cierres", "propiedades_captadas": "Captaciones", "contratos_firmados": "Contratos",
        "visitas_hechas": "Visitas", "contactos_nuevos": "Contactos nuevos", "honorarios_usd": "Honorarios", "honorarios_ars": "Honorarios",
    ]
    static let ordenMetricas = ["operaciones_cerradas", "propiedades_captadas", "visitas_hechas", "contactos_nuevos", "contratos_firmados", "honorarios_usd", "honorarios_ars"]

    static func ordenMetrica(_ m: String?) -> Int { ordenMetricas.firstIndex(of: m ?? "") ?? ordenMetricas.count }

    static func ritmo(_ o: Objetivo, _ ahora: Date = Date()) -> RitmoInicio {
        let meta = o.meta ?? 0, avance = o.avance ?? 0
        let desde = o.desde.flatMap(Fecha.dia) ?? ahora, hasta = o.hasta.flatMap(Fecha.dia) ?? ahora
        let total = diasEntre(desde, hasta) + 1
        let pasados = min(total, max(0, diasEntre(desde, ahora) + 1))
        let esperado = total > 0 ? meta * Double(pasados) / Double(total) : meta
        let adelante = avance >= esperado
        let moneda: String? = o.metrica == "honorarios_usd" ? "USD" : o.metrica == "honorarios_ars" ? "ARS" : nil
        return RitmoInicio(id: o.id, nombre: nombresMetricas[o.metrica ?? ""] ?? (o.metrica ?? ""), avance: avance, meta: meta,
                     ancho: min(100, meta > 0 ? avance / meta * 100 : 0), raya: min(100, Double(pasados) / Double(max(1, total)) * 100),
                     adelante: adelante, falta: adelante ? 0 : max(1, Int((esperado - avance).rounded(.up))), moneda: moneda)
    }

    // MARK: Guía

    static let pasosAltaEnInicio = ["logo", "marca", "portada", "contacto", "legales", "rubros"]

    /// «Primeros pasos»: la dueña o el dueño ve todos; un agente, los suyos (la propiedad, su web y los avisos).
    static func primerosPasos(_ g: GuiaInicio, duenio: Bool) -> [PasoInicio] {
        let p = g.pasos
        var todos: [(PasoInicio, Bool)] = [
            (PasoInicio(clave: "propiedad", texto: "Cargá tu primera propiedad", boton: "Cargar", hecho: p?.propiedad ?? false), false),
            (PasoInicio(clave: "web", texto: "Mirá tu web", boton: "Abrir", hecho: p?.web ?? false), false),
        ]
        if let alta = g.alta {
            for x in alta.pasos where pasosAltaEnInicio.contains(x.clave) {
                todos.append((PasoInicio(clave: x.clave, texto: x.titulo, boton: "Completar", hecho: x.hecho), true))
            }
        } else {
            todos.append((PasoInicio(clave: "datos", texto: "Subí el logo de la inmobiliaria", boton: "Subir", hecho: p?.datos ?? false), true))
        }
        todos.append((PasoInicio(clave: "whatsapp", texto: "Conectá WhatsApp", boton: "Conectar", hecho: p?.whatsapp ?? false), true))
        todos.append((PasoInicio(clave: "equipo", texto: "Invitá a alguien del equipo", boton: "Invitar", hecho: p?.equipo ?? false), true))
        todos.append((PasoInicio(clave: "avisos", texto: "Activá los avisos", boton: "Activar", hecho: p?.avisos ?? false), false))
        todos.append((PasoInicio(clave: "portales", texto: "Publicá en los portales", boton: "Conectar", hecho: p?.portales ?? false), true))
        return todos.filter { duenio || !$0.1 }.map(\.0)
    }

    /// El próximo paso útil cuando «Para hacer» no tiene nada. Nunca vuelve vacío (hasta tres).
    static func proximosPasos(_ g: GuiaInicio?, duenio: Bool, pasosVisibles: Bool, libres: Int) -> [ProximoInicio] {
        guard let g else { return [ProximoInicio(clave: "nueva", icono: "house", titulo: "Cargá una propiedad", detalle: "Con foto, precio y dirección", boton: "Cargar")] }
        var out: [ProximoInicio] = []
        let props = g.propiedades ?? 0, contactos = g.contactos ?? 0
        if libres > 0 {
            out.append(ProximoInicio(clave: "libres", icono: "tray", titulo: "Tomá una consulta sin dueño", detalle: libres == 1 ? "Hay 1 esperando" : "Hay \(libres) esperando", boton: "Ver"))
        }
        if props == 0 {
            out.append(ProximoInicio(clave: "propiedad", icono: "house", titulo: "Cargá tu primera propiedad", detalle: "Con una foto del cartel alcanza", boton: "Captar",
                                     secundario: duenio ? "Importar de Excel" : nil))
        } else if props < 10 {
            out.append(ProximoInicio(clave: "mas", icono: "house", titulo: "Sumá más propiedades", detalle: props == 1 ? "Tenés 1 en la cartera" : "Tenés \(props) en la cartera", boton: "Cargar"))
        }
        if contactos == 0 {
            out.append(ProximoInicio(clave: "contacto", icono: "person.badge.plus", titulo: "Cargá tu primer contacto", detalle: "Un interesado o un propietario", boton: "Cargar",
                                     secundario: duenio ? "Importar de Excel" : nil))
        }
        if duenio && !pasosVisibles {
            if let a = g.alta, a.completo < 100 {
                out.append(ProximoInicio(clave: "alta", icono: "paintpalette", titulo: "Tu inmobiliaria al \(a.completo)%", detalle: "Logo, colores, portada y contacto", boton: "Completar"))
            }
            if g.pasos?.whatsapp == false { out.append(ProximoInicio(clave: "whatsapp", icono: "bubble.left.and.bubble.right", titulo: "Conectá WhatsApp", detalle: "Las consultas entran ordenadas", boton: "Conectar")) }
            if g.pasos?.equipo == false { out.append(ProximoInicio(clave: "equipo", icono: "person.2", titulo: "Invitá a tu equipo", detalle: "Cada agente, desde su celular", boton: "Invitar")) }
            if g.pasos?.portales == false { out.append(ProximoInicio(clave: "portales", icono: "storefront", titulo: "Publicá en portales", detalle: "Mercado Libre, Zonaprop y Argenprop", boton: "Conectar")) }
            if g.alta == nil, g.pasos?.datos == false { out.append(ProximoInicio(clave: "datos", icono: "paintpalette", titulo: "Completá tu web", detalle: "Logo, colores y portada", boton: "Completar")) }
        }
        if props > 0 && contactos > 0 {
            out.append(ProximoInicio(clave: "visita", icono: "calendar", titulo: "Agendá una visita", detalle: "Con recordatorio por WhatsApp", boton: "Agendar"))
        }
        if out.isEmpty { out.append(ProximoInicio(clave: "cartera", icono: "building.2", titulo: "Repasá tu cartera", detalle: "Precios, fotos y estados", boton: "Ver")) }
        return Array(out.prefix(3))
    }

    /// Las acciones rápidas: arriba lo que falta (sin cartera: captar y cargar), después lo que más usa.
    /// «Registrar cobro» sólo con contratos; la web, al final.
    static func accionesRapidas(_ g: GuiaInicio?, web: Bool) -> [AccionInicio] {
        let base: [(String, String, String)] = [("captar", "Captar con MIRA", "viewfinder"), ("propiedad", "Cargar propiedad", "house" ),
                                                ("contacto", "Nuevo contacto", "person.badge.plus"), ("visita", "Agendar visita", "calendar.badge.plus"),
                                                ("cobro", "Registrar cobro", "dollarsign.circle")]
        let u = g?.usos
        func usado(_ c: String) -> Int {
            switch c {
            case "captar": return u?.captar ?? 0
            case "propiedad": return u?.propiedad ?? 0
            case "contacto": return u?.contacto ?? 0
            case "visita": return u?.visita ?? 0
            case "cobro": return u?.cobro ?? 0
            default: return 0
            }
        }
        func peso(_ c: String) -> Int {
            var p = usado(c)
            let props = g?.propiedades ?? -1, contactos = g?.contactos ?? -1
            if props == 0 && c == "captar" { p += 2000 }
            if props == 0 && c == "propiedad" { p += 1999 }
            if props > 0 && contactos == 0 && c == "contacto" { p += 1000 }
            return p
        }
        let elegidas = base.enumerated()
            .filter { $0.element.0 != "cobro" || (g?.contratos ?? 0) > 0 }
            .map { (i: $0.offset, x: $0.element, p: peso($0.element.0)) }
            .sorted { $0.p != $1.p ? $0.p > $1.p : $0.i < $1.i }
        var out = elegidas.map { AccionInicio(clave: $0.x.0, texto: $0.x.1, icono: $0.x.2) }
        if web { out.append(AccionInicio(clave: "web", texto: "Ver mi web", icono: "globe")) }
        return out
    }
}

// MARK: - Traer el Inicio

extension CuentasInicio {
    /// Todo en paralelo (un grupo de tareas: nada de `async let`); cada bloque puede fallar solo. Sólo el
    /// panel es obligatorio: si no llega, sale el error (o lo guardado).
    @MainActor
    static func traer(_ estado: Estado) async throws -> DatosInicio {
        let api = estado.api
        let duenio = estado.esDuenio
        let ahora = Date()
        let hoy = Formato.diaISO(ahora)
        let manana = Formato.diaISO(ahora.addingTimeInterval(86400))
        func q(_ pares: [(String, String)]) -> [URLQueryItem] { pares.map { URLQueryItem(name: $0.0, value: $0.1) } }
        var pedidos: [(String, String, [URLQueryItem])] = [
            ("panel", "/v1/panel", []),
            ("guia", "/v1/panel/guia", []),
            ("agenda", "/v1/agenda", q([("desde", hoy), ("hasta", manana), ("limite", "200")])),
            ("cobranzas", "/v1/cobranzas", []),
            ("reservas", "/v1/reservas", q([("vencen", "2"), ("limite", "10")])),
            ("conversaciones", "/v1/whatsapp/conversaciones", q([("noLeidas", "si"), ("limite", "20")])),
            ("preguntas", "/v1/mercadolibre/preguntas", q([("estado", "sin_responder"), ("limite", "10")])),
            ("consultas", "/v1/avisos", q([("vista", "para_hacer"), ("tipo", "consulta"), ("limite", "20")])),
            ("numero", "/v1/whatsapp/numero", []),
            ("clima", "/v1/clima", []),
            ("deudas", "/v1/contratos/deudas", []),
            ("inmo", "/v1/inmobiliaria", []),
            ("props", "/v1/propiedades", q([("orden", "actualizada"), ("limite", "10")])),
            ("contador", "/v1/avisos/contador", []),
        ]
        if duenio {
            pedidos.append(("equipo", "/v1/equipo", []))
            pedidos.append(("licencias", "/v1/licencias", q([("desde", hoy), ("hasta", hoy)])))
        }
        var r: [String: Result<Data, Error>] = [:]
        await withTaskGroup(of: (String, Result<Data, Error>).self) { g in
            for (clave, ruta, query) in pedidos {
                g.addTask {
                    do { return (clave, .success(try await api.pedir("GET", ruta, query: query))) } catch { return (clave, .failure(error)) }
                }
            }
            for await (clave, x) in g { r[clave] = x }
        }
        func leer<T: Decodable>(_ clave: String, _ tipo: T.Type) -> T? {
            guard case .success(let d)? = r[clave], !d.isEmpty else { return nil }
            return try? Api.decodificador.decode(T.self, from: d)
        }
        func fallo(_ clave: String) -> Bool {
            if case .failure? = r[clave] { return true }
            return false
        }
        var d = DatosInicio()
        switch r["panel"] {
        case .failure(let e)?: throw e
        case .success(let x)?:
            d.panel = try? Api.decodificador.decode(Panel.self, from: x)
            d.panelExtra = try? Api.decodificador.decode(PanelInicio.self, from: x)
        case nil: break
        }
        d.guia = leer("guia", GuiaInicio.self)
        d.agenda = leer("agenda", [Cita].self) ?? []
        d.cobranzas = leer("cobranzas", MesCobranzas.self)
        d.reservas = leer("reservas", [ReservaInicio].self) ?? []
        d.conversaciones = leer("conversaciones", [Conversacion].self) ?? []
        d.preguntas = leer("preguntas", [PreguntaML].self) ?? []
        d.consultas = leer("consultas", ListaAvisosConsulta.self)?.avisos ?? []
        d.numero = leer("numero", NumeroWhatsApp.self)
        d.clima = leer("clima", Clima.self)
        d.deudas = leer("deudas", [DeudaInicio].self)
        d.inmo = leer("inmo", Inmobiliaria.self)
        d.props = leer("props", [Propiedad].self) ?? []
        d.equipo = leer("equipo", [Miembro].self) ?? []
        d.licencias = leer("licencias", [Licencia].self) ?? []
        struct Contador: Decodable { var noLeidos: Int?; var paraHacer: Int? }
        if let c = leer("contador", Contador.self) { d.avisos = c.noLeidos ?? 0 }
        if fallo("conversaciones") { d.fallo.insert("mensajes") }
        if fallo("agenda") { d.fallo.insert("agenda") }
        if fallo("cobranzas") { d.fallo.insert("cobranzas") }
        d.actualizado = ahora
        d.proxima = await proximaVisita(d, estado: estado, ahora: ahora)
        return d
    }

    /// La próxima visita (la que sigue hoy; de noche, la primera de mañana), con la foto, la operación,
    /// el precio y el teléfono del contacto. La dueña ve la suya.
    @MainActor
    static func proximaVisita(_ d: DatosInicio, estado: Estado, ahora: Date) async -> ProximaVisita? {
        let yo = estado.usuario?.id
        let c = Formato.calendario
        let mias = d.agenda.filter { $0.estado == "pendiente" && $0.tipo == "visita" && (!estado.esDuenio || $0.agenteId == yo) }
            .sorted { $0.empiezaEn < $1.empiezaEn }
        let cita: Cita?
        if deNoche(ahora) {
            cita = mias.first { !c.isDate($0.empiezaEn, inSameDayAs: ahora) && $0.empiezaEn > ahora }
        } else {
            cita = mias.first { c.isDate($0.empiezaEn, inSameDayAs: ahora) && $0.empiezaEn.addingTimeInterval(15 * 60) > ahora }
        }
        guard let cita else { return nil }
        struct P: Decodable { var fotosUrl: [String]?; var direccion: String?; var barrio: String?; var ciudad: String?; var operacion: String?; var precio: Double?; var moneda: String? }
        struct Ct: Decodable { var telefono: String? }
        var p: P?
        var t: Ct?
        if let id = cita.propiedadId { p = try? await estado.api.get("/v1/propiedades/\(id)") }
        if let id = cita.contactoId { t = try? await estado.api.get("/v1/contactos/\(id)") }
        let partes: [String] = [p?.direccion, p?.barrio, p?.ciudad].compactMap { x in x?.nonEmpty }
        let dir: String? = partes.isEmpty ? cita.lugar : partes.joined(separator: ", ")
        return ProximaVisita(cita: cita, foto: p?.fotosUrl?.first, fotos: p?.fotosUrl?.count ?? 0, direccion: dir,
                             operacion: p?.operacion, precio: p?.precio, moneda: p?.moneda, telefono: t?.telefono)
    }
}
