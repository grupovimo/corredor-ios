import Foundation

// Los modelos de la API de Corredor (api/internal/dominio/*). Casi todo es opcional: un campo nuevo o
// que falta no rompe la pantalla. Los nombres siguen el JSON de la API.

/// GET /v1/panel: los números, la agenda de hoy, las sugerencias y los objetivos.
struct Panel: Codable {
    struct Numeros: Codable {
        var propiedadesDisponibles: Int?
        var propiedadesReservadas: Int?
        var propiedadesNuevasMes: Int?
        var contactos: Int?
        var contactosNuevosMes: Int?
        var operacionesAbiertas: Int?
        var cerradasMes: Int?
        var cerradasMesAnterior: Int?
        var citasHoy: Int?
        var alquileresVigentes: Int?
        var rendicionesListas: Int?
    }
    var numeros: Numeros?
    var agendaHoy: [Cita]?
    var sugerencias: [Sugerencia]?
    var objetivos: [Objetivo]?
}

/// Una cita de la agenda (visita, tasación, firma, llamada…).
struct Cita: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var estado: String?
    var titulo: String?
    var empiezaEn: Date
    var duracionMin: Int?
    var propiedadId: String?
    var contactoId: String?
    var operacionId: String?
    var lugar: String?
    var notas: String?
    var recordar: Bool?
    var agenteId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var agenteNombre: String?
    /// Cuándo se le mandó el recordatorio por WhatsApp («confirmada»).
    var recordadoEn: Date?
    var creadaEn: Date?

    /// Lo que se ve: la propiedad, el lugar o el título.
    var donde: String { propiedadTitulo ?? lugar ?? titulo ?? "Cita" }
    var terminaEn: Date { empiezaEn.addingTimeInterval(Double((duracionMin ?? 60) * 60)) }

    static let tipos: [(String, String, String)] = [
        ("visita", "Visita", "house"), ("tasacion", "Tasación", "ruler"), ("firma", "Firma", "signature"),
        ("llamado", "Llamado", "phone"), ("otro", "Tarea", "checklist"),
    ]
    var icono: String { Cita.tipos.first { $0.0 == tipo }?.2 ?? "calendar" }
    var tipoTexto: String { Cita.tipos.first { $0.0 == tipo }?.1 ?? "Cita" }
}

/// «Encontramos por vos»: lo que el sistema propone hacer.
struct Sugerencia: Codable, Identifiable, Hashable {
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
    var agenteId: String?
}

/// Un objetivo del mes (operaciones, captaciones…) con su avance.
struct Objetivo: Codable, Identifiable, Hashable {
    var id: String
    var agenteId: String?
    var metrica: String?
    var meta: Double?
    var desde: String?
    var hasta: String?
    var agenteNombre: String?
    var avance: Double?
    var porcentaje: Double?

    /// Las métricas que registra la API (objetivos.Registrar).
    static let metricas: [String: (String, String)] = [
        "operaciones_cerradas": ("operación cerrada", "operaciones cerradas"), "propiedades_captadas": ("captación", "captaciones"),
        "visitas_hechas": ("visita", "visitas"), "contactos_nuevos": ("contacto nuevo", "contactos nuevos"),
        "contratos_firmados": ("contrato firmado", "contratos firmados"), "honorarios_usd": ("dólar de honorarios", "dólares de honorarios"),
        "honorarios_ars": ("peso de honorarios", "pesos de honorarios"),
    ]
}

/// GET /v1/contratos/deudas: quién debe y cuánto (la misma regla en toda la app).
struct Deuda: Codable, Identifiable, Hashable {
    struct Mes: Codable, Hashable {
        var periodo: String?
        var monto: Double?
        var esperado: Double?
        var vence: String?
    }
    var contratoId: String
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var agenteId: String?
    var moneda: String?
    var punitorioDiario: Double?
    var meses: [Mes]?
    var total: Double?
    var estimado: Bool?
    var id: String { contratoId }
}

/// Una conversación de WhatsApp.
struct Conversacion: Codable, Identifiable, Hashable {
    var id: String
    var waId: String?
    var nombre: String?
    var contactoId: String?
    var contactoNombre: String?
    var operacionId: String?
    var propiedadId: String?
    var propiedadTitulo: String?
    var agenteId: String?
    var agenteNombre: String?
    var noLeidos: Int?
    var ultimoTexto: String?
    var ultimoMensajeEn: Date?
    var ultimoEntranteEn: Date?
    var enVentana: Bool?
    /// Lo último es del otro lado: nadie le contestó todavía.
    var esperando: Bool?
    var archivada: Bool?
    /// Se vinculó sola por el código del aviso que trajo un mensaje.
    var propiedadPorCodigo: Bool?
    var creadaEn: Date?

    /// Como la web (lib/mensajes/modelo.ts `nombreDe`): el contacto, el nombre de WhatsApp o el número.
    var quien: String { contactoNombre ?? nombre?.nonEmpty ?? Conversacion.telefono(waId ?? "") }
    /// Sin contacto ni nombre: «número nuevo · crear contacto».
    var sinNombre: Bool { contactoNombre == nil && nombre?.nonEmpty == nil }
    /// Fuera de la ventana de 24 h (y ya escribió alguna vez).
    var fuera: Bool { enVentana != true && ultimoEntranteEn != nil }

    /// «11 3392-0071» para un número de Buenos Aires sin nombre; si no, «+<número>».
    static func telefono(_ wa: String) -> String {
        for patron in [#"^549(11)(\d{4})(\d{4})$"#, #"^54(11)(\d{4})(\d{4})$"#] {
            if let r = try? NSRegularExpression(pattern: patron),
               let m = r.firstMatch(in: wa, range: NSRange(wa.startIndex..., in: wa)), m.numberOfRanges == 4,
               let a = Range(m.range(at: 1), in: wa), let b = Range(m.range(at: 2), in: wa), let c = Range(m.range(at: 3), in: wa) {
                return "\(wa[a]) \(wa[b])-\(wa[c])"
            }
        }
        return wa.isEmpty ? "Sin nombre" : "+" + wa
    }

    /// Lo que queda de la ventana de 24 h: «23 h 48 min» (nil si está cerrada).
    func ventanaRestante(_ ahora: Date = Date()) -> String? {
        guard let u = ultimoEntranteEn else { return nil }
        let resta = u.addingTimeInterval(86_400).timeIntervalSince(ahora)
        guard resta > 0 else { return nil }
        let h = Int(resta) / 3600, m = (Int(resta) % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}

/// GET /v1/whatsapp/conversaciones/cuentas: cada vista de la bandeja con su número.
struct CuentasBandeja: Codable, Hashable {
    var esperando: Int?
    var mias: Int?
    var sinDueno: Int?
    var fueraDeVentana: Int?
    var noLeidas: Int?
    var todas: Int?
}

/// GET /v1/whatsapp/numero: el número conectado y su estado en Meta (conectado, desconectado,
/// restringido, limitado), por qué y desde cuándo.
struct NumeroWA: Codable, Hashable {
    var conectado: Bool
    var telefono: String?
    var estado: String?
    var estadoMotivo: String?
    var estadoEn: Date?
    /// Conectado en Corredor y caído en Meta: hay que avisar.
    var caido: Bool { conectado && (estado?.nonEmpty.map { $0 != "conectado" } ?? false) }
}

/// Una pregunta de Mercado Libre.
struct PreguntaML: Codable, Identifiable, Hashable {
    var id: String
    var preguntaId: Int64?
    var itemId: String?
    var propiedadId: String?
    var propiedad: String?
    var texto: String?
    var respuesta: String?
    var estado: String?
    var creadaEn: Date?
    var respondidaEn: Date?
    var compradorApodo: String?
}

/// GET /v1/panel/guia: los primeros pasos y lo que la persona ya hizo.
struct Guia: Codable {
    struct Pasos: Codable {
        var datos: Bool?
        var propiedad: Bool?
        var web: Bool?
        var whatsapp: Bool?
        var equipo: Bool?
        var avisos: Bool?
        var portales: Bool?
    }
    var tourVisto: Bool?
    var pasosOcultos: Bool?
    var pasos: Pasos?
    var contratos: Int?
    var propiedades: Int?
    var contactos: Int?
}

/// Una persona del equipo (GET /v1/equipo).
struct Miembro: Codable, Identifiable, Hashable {
    var usuarioId: String
    var email: String?
    var nombre: String?
    var apellido: String?
    var foto: String?
    var rol: String?
    var desde: String?
    var propiedades: Int?
    var barrios: [String]?
    var avisosPush: Bool?
    var telefono: String?
    var id: String { usuarioId }
    var completo: String { [nombre, apellido].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").nonEmpty ?? email ?? "Sin nombre" }
}

/// Una licencia o ausencia del equipo.
struct Licencia: Codable, Identifiable, Hashable {
    var id: String
    var usuarioId: String
    var usuarioNombre: String?
    var tipo: String?
    var desde: String
    var hasta: String
    var nota: String?
}

/// Un aviso del centro de avisos (GET /v1/avisos).
struct AvisoCentro: Codable, Identifiable, Hashable {
    /// Un botón del aviso (avisos.Accion). Con `ruta`, llama a la API con `metodo` (POST si falta) y
    /// `cuerpo`; con `entrada` "texto", primero pide el texto y manda {"texto": …}. Sin ruta, abre `url`.
    struct Accion: Codable, Hashable {
        var accion: String?
        var titulo: String?
        var metodo: String?
        var ruta: String?
        var cuerpo: JSONLibre?
        var url: String?
        var entrada: String?
    }
    var id: String
    var tipo: String?
    var titulo: String?
    var cuerpo: String?
    var url: String?
    /// Lo que el aviso sabe de lo que pasó (la sugerencia de respuesta, la propiedad, el monto…).
    var datos: JSONLibre?
    /// Quién lo provocó (el que movió la operación) y quién lo tiene que resolver.
    var actorId: String?
    var actorNombre: String?
    var responsableId: String?
    var responsableNombre: String?
    /// Pide algo (responder, cobrar): al hacerlo queda hecho, no sólo leído.
    var accionable: Bool?
    var hecho: Bool?
    var leido: Bool?
    var leidoEn: Date?
    var hechoEn: Date?
    var creadoEn: Date?
    var acciones: [Accion]?

    var estaHecho: Bool { hecho == true || hechoEn != nil }
    var estaLeido: Bool { leido == true || leidoEn != nil }
}

/// GET /v1/avisos: una página, el cursor de la siguiente y los contadores.
struct PaginaAvisos: Codable {
    var avisos: [AvisoCentro]
    var siguiente: String?
    var noLeidos: Int?
    var paraHacer: Int?
}

/// El resultado de la búsqueda global (GET /v1/buscar).
struct Resultado: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String
    var titulo: String
    var subtitulo: String?
}

extension String {
    /// nil si está vacío (o sólo espacios).
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

/// Un JSON cualquiera, para los campos libres (marca, datos de un evento).
enum JSONLibre: Codable, Hashable {
    case texto(String), numero(Double), bool(Bool), objeto([String: JSONLibre]), lista([JSONLibre]), nulo

    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .nulo }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .numero(n) }
        else if let s = try? c.decode(String.self) { self = .texto(s) }
        else if let l = try? c.decode([JSONLibre].self) { self = .lista(l) }
        else { self = .objeto(try c.decode([String: JSONLibre].self)) }
    }

    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .texto(let s): try c.encode(s)
        case .numero(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .objeto(let o): try c.encode(o)
        case .lista(let l): try c.encode(l)
        case .nulo: try c.encodeNil()
        }
    }

    var texto: String? { if case .texto(let s) = self { return s }; return nil }
    subscript(_ k: String) -> JSONLibre? { if case .objeto(let o) = self { return o[k] }; return nil }
}
