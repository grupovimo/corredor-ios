import Foundation

/// Una propiedad (GET /v1/propiedades, /v1/propiedades/{id}).
struct Propiedad: Codable, Identifiable, Hashable {
    var id: String
    var numero: Int?
    var titulo: String?
    var slug: String?
    var descripcion: String?
    var tipo: String?
    var operacion: String?
    var estado: String?
    var precio: Double?
    var moneda: String?
    var periodo: String?
    var expensas: Double?
    var precioOculto: Bool?
    var direccion: String?
    var barrio: String?
    var ciudad: String?
    var lat: Double?
    var lng: Double?
    var ambientes: Int?
    var dormitorios: Int?
    var banos: Int?
    var cocheras: Int?
    var superficie: Double?
    var cubierta: Double?
    var antiguedad: Int?
    var aptoCredito: Bool?
    var tambienTemporario: Bool?
    var comodidades: [String]?
    var caracteristicas: [String]?
    var servicios: [String]?
    var fotos: [String]?
    var video: String?
    var destacada: Bool?
    var publicada: Bool?
    var agenteId: String?
    var propietarioId: String?
    var emprendimientoId: String?
    var fotosUrl: [String]?
    /// La ficha libre (notas internas, datos de MIRA).
    var ficha: JSONLibre?
    var creadaEn: Date?
    var actualizadoEn: Date?

    var nombre: String { titulo?.nonEmpty ?? direccion ?? "Propiedad" }
    /// Captada con MIRA (lo que la web muestra en «Captadas»).
    var deMira: Bool { ficha?["notasInternas"]?.texto?.hasPrefix("Captada con MIRA") == true }
    var portada: URL? { fotosUrl?.first.flatMap { URL(string: $0) } }
    var miniatura: URL? { fotosUrl?.first.flatMap { URL(string: $0 + ($0.contains("?") ? "&" : "?") + "tam=chica") } }

    static let operaciones = [("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporada")]
    static let tipos = [("departamento", "Departamento"), ("casa", "Casa"), ("ph", "PH"), ("terreno", "Lote"), ("local", "Local"),
                        ("oficina", "Oficina"), ("cochera", "Cochera"), ("galpon", "Galpón"), ("campo", "Campo")]
    static let estados = [("disponible", "Disponible"), ("reservada", "Reservada"), ("vendida", "Vendida"), ("alquilada", "Alquilada"),
                          ("pausada", "Pausada"), ("borrador", "Borrador")]

    var operacionTexto: String { Propiedad.operaciones.first { $0.0 == operacion }?.1.lowercased() ?? (operacion ?? "") }
    var tipoTexto: String { Propiedad.tipos.first { $0.0 == tipo }?.1 ?? (tipo?.capitalized ?? "") }

    /// «USD 172.000», «ARS 611.800 / mes», «USD 180 / noche».
    var precioTexto: String {
        guard let precio, precioOculto != true else { return "Consultar precio" }
        let p = Formato.plata(precio, moneda ?? "USD")
        switch operacion {
        case "alquiler": return p + " / mes"
        case "temporario": return p + (periodo == "semana" ? " / semana" : periodo == "mes" ? " / mes" : " / noche")
        default: return p
        }
    }

    /// «Belgrano · venta · 3 amb · 74 m²».
    var resumen: String {
        [barrio ?? ciudad, operacionTexto.nonEmpty, tipo == "ph" ? "PH" : nil, ambientes.map { "\($0) amb" },
         superficie.map { "\(Formato.numero(Int($0))) m²" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Lo que pasa con una propiedad (GET /v1/propiedades/senales): portales, error, interesados, visita.
struct Senal: Codable, Hashable {
    struct ErrorPortal: Codable, Hashable { var portal: String?; var error: String?; var en: Date? }
    struct Reservada: Codable, Hashable { var id: String?; var venceEl: String?; var sena: Double?; var senaMoneda: String?; var interesado: String? }
    var propiedadId: String
    var codigo: String?
    var portales: [String: String]?
    var error: ErrorPortal?
    var interesados: Int?
    var ultimaConsulta: Date?
    var sinResponder: Int?
    var proximaVisita: Date?
    var proximaVisitaCon: String?
    var reserva: Reservada?
    var vistasSemana: Int?
    var precioAnterior: Double?
    var precioCambio: Date?
    var cargadaPor: String?

    var publicadaEn: Int { (portales ?? [:]).values.filter { $0 == "publicada" || $0 == "activa" }.count }
}

/// Un interesado en una propiedad (GET /v1/propiedades/{id}/interesados).
struct Interesado: Codable, Identifiable, Hashable {
    var contactoId: String
    var nombre: String
    var telefono: String?
    var email: String?
    var agenteId: String?
    var puntaje: Double?
    var visito: Bool?
    var enviadaEn: Date?
    var id: String { contactoId }
}

/// Una publicación en un portal (GET /v1/propiedades/{id}/publicaciones).
struct PublicacionPortal: Codable, Identifiable, Hashable {
    var id: String
    var portal: String
    var estado: String
    var url: String?
    var error: String?
    var visitas: Int?
    var visitasSemana: Int?
    var consultas: Int?

    static let nombres = ["web": "Tu web", "mercadolibre": "Mercado Libre", "zonaprop": "Zonaprop", "argenprop": "Argenprop",
                          "properati": "Properati", "inmuebles24": "Inmuebles24"]
    var nombre: String { PublicacionPortal.nombres[portal] ?? portal.capitalized }
}

/// La inmobiliaria (GET /v1/inmobiliaria): la web pública para armar los links de las fichas.
struct Inmobiliaria: Codable, Hashable {
    var id: String
    var slug: String?
    var nombre: String?
    var web: String?
    var dominio: String?
    var cbu: String?
    var zonaHoraria: String?
}
