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

    /// Lo que se ve: la propiedad, el lugar o el título.
    var donde: String { propiedadTitulo ?? lugar ?? titulo ?? "Cita" }
    var terminaEn: Date { empiezaEn.addingTimeInterval(Double((duracionMin ?? 60) * 60)) }

    static let tipos: [(String, String, String)] = [
        ("visita", "Visita", "house"), ("tasacion", "Tasación", "ruler"), ("firma", "Firma", "signature"),
        ("llamada", "Llamada", "phone"), ("reunion", "Reunión", "person.2"), ("otro", "Otro", "calendar"),
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

    static let metricas: [String: (String, String)] = [
        "operaciones": ("operación", "operaciones"), "captaciones": ("captación", "captaciones"),
        "visitas": ("visita", "visitas"), "tasaciones": ("tasación", "tasaciones"), "contactos": ("contacto", "contactos"),
        "facturacion": ("peso", "pesos"),
    ]
}

/// GET /v1/contratos/deudas: quién debe y cuánto (la misma regla en toda la app).
struct Deuda: Codable, Identifiable, Hashable {
    struct Mes: Codable, Hashable {
        var periodo: String?
        var monto: Double?
        var esperado: Double?
        var vencio: String?
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

    var quien: String { contactoNombre ?? nombre ?? waId.map { "+\($0)" } ?? "Sin nombre" }
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
    struct Accion: Codable, Hashable {
        var accion: String?
        var titulo: String?
        var metodo: String?
        var ruta: String?
        var url: String?
        var entrada: String?
    }
    var id: String
    var tipo: String?
    var titulo: String?
    var cuerpo: String?
    var url: String?
    var leidoEn: Date?
    var hechoEn: Date?
    var creadoEn: Date?
    var acciones: [Accion]?
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
