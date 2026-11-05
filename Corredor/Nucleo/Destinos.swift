import Foundation

// Los destinos de navegación de toda la app. Viven acá (y no en cada área) para que cualquier pantalla
// pueda abrir la ficha de otra: el Inicio abre una propiedad, un chat abre el contacto. Cada área
// registra la vista de sus destinos en su propio `.destinos<Área>()` (Pantallas/<Área>/), y
// Principal los junta todos en `.destinos()`.

/// 3D Ficha de una propiedad.
struct AFichaPropiedad: Hashable { var id: String }
/// 3E Galería de fotos de una propiedad, desde la foto `indice`.
struct AGaleria: Hashable { var id: String; var indice = 0 }
/// 4A Alta rápida de una propiedad (o seguir un borrador).
struct AAltaPropiedad: Hashable { var borrador: String? = nil }
/// 5I Lo captado con MIRA (la cola y los borradores).
struct ACaptadas: Hashable {}
/// 6B Un chat de WhatsApp.
struct AChat: Hashable { var id: String }
/// 6D Una pregunta de Mercado Libre.
struct APreguntaML: Hashable { var id: String }
/// 7A Agenda en un día (yyyy-MM-dd); nil es hoy.
struct AAgendaDia: Hashable { var dia: String? = nil }
/// Una cita de la agenda.
struct ACita: Hashable { var id: String }
/// 8A Contactos.
struct AContactos: Hashable {}
/// 8B Ficha de un contacto.
struct AFichaContacto: Hashable { var id: String }
/// 9A Tablero de operaciones.
struct AOperaciones: Hashable {}
/// 9C Ficha de una operación.
struct AFichaOperacion: Hashable { var id: String }
/// 10A Por cobrar.
struct ACobranzas: Hashable {}
/// Los contratos (la lista) y la ficha de uno.
struct AContratos: Hashable {}
struct AFichaContrato: Hashable { var id: String }
/// 10D Recibo de un cobro.
struct ARecibo: Hashable { var contrato: String; var cobro: String }
/// Rendición al propietario.
struct ARendicion: Hashable { var contrato: String; var id: String }
/// 11A Recorrida de inventario y 11B firmas.
struct AInventario: Hashable { var id: String }
struct AFirmas: Hashable { var id: String }
/// 12A Avisos y 12B su configuración.
struct AAvisos: Hashable {}
struct AConfigAvisos: Hashable {}
/// 13A Perfil.
struct APerfil: Hashable {}
/// 2C Búsqueda global.
struct ABuscar: Hashable { var texto = "" }
/// Lo que el handoff no dibuja y el panel sí tiene (configuración, equipo, consorcios, Mi web,
/// informe, emprendimientos, temporada…): una sección por `clave`, con un `id` opcional.
struct ASeccion: Hashable { var clave: String; var id: String? = nil }

/// Las cinco pestañas. La quinta es «Más» (todo lo demás, por áreas); la agenda se abre desde el
/// Inicio y desde «Más» (decisión del 5/11: con todo el panel en la app, no entraba en el handoff).
enum Pestana: String, CaseIterable, Hashable {
    case inicio, propiedades, mira, mensajes, mas
}

/// Adónde lleva un push, un widget, Spotlight, un atajo o un link `corredor://`: la pestaña y lo que
/// se apila encima.
struct Ruta: Equatable {
    var pestana: Pestana
    var destino: AnyHashable?

    static func == (a: Ruta, b: Ruta) -> Bool { a.pestana == b.pestana && a.destino == b.destino }

    /// `propiedad/123` (el `ruta` del push) o `corredor://propiedad/123`. También acepta rutas del
    /// panel web (`/propiedades/123`, `/mensajes/abc`), que son las que manda la API en los avisos.
    init?(texto: String) {
        var t = texto
        if let u = URL(string: texto), u.scheme == "corredor" {
            t = ([u.host ?? ""] + u.pathComponents.filter { $0 != "/" }).joined(separator: "/")
        } else if let u = URL(string: texto), u.scheme == "https" {
            t = u.path
        }
        let p = t.split(separator: "/").map(String.init)
        guard let a = p.first else { return nil }
        let id = p.count > 1 ? p[1] : nil
        switch a {
        case "inicio": self.init(.inicio)
        case "propiedad", "propiedades":
            self.init(.propiedades, id.map { $0 == "nueva" ? AnyHashable(AAltaPropiedad()) : AnyHashable(AFichaPropiedad(id: $0)) })
        case "mira": self.init(.mira, id == "captadas" ? AnyHashable(ACaptadas()) : nil)
        case "chat", "mensajes", "whatsapp": self.init(.mensajes, id.map { AnyHashable(AChat(id: $0)) })
        case "ml", "mercadolibre": self.init(.mensajes, id.map { AnyHashable(APreguntaML(id: $0)) })
        case "agenda": self.init(.inicio, id.map { AnyHashable(ACita(id: $0)) } ?? AnyHashable(AAgendaDia()))
        case "mas": self.init(.mas)
        case "contacto", "contactos": self.init(.inicio, id.map { AnyHashable(AFichaContacto(id: $0)) } ?? AnyHashable(AContactos()))
        case "operacion", "operaciones": self.init(.inicio, id.map { AnyHashable(AFichaOperacion(id: $0)) } ?? AnyHashable(AOperaciones()))
        case "cobranzas": self.init(.inicio, ACobranzas())
        case "contrato", "contratos": self.init(.inicio, id.map { AnyHashable(AFichaContrato(id: $0)) } ?? AnyHashable(AContratos()))
        case "inventario", "inventarios": self.init(.inicio, id.map { AnyHashable(AInventario(id: $0)) })
        case "avisos": self.init(.inicio, AAvisos())
        case "perfil": self.init(.inicio, APerfil())
        case "buscar": self.init(.inicio, ABuscar())
        default: self.init(.inicio, ASeccion(clave: a, id: id))
        }
    }

    init(_ pestana: Pestana, _ destino: AnyHashable? = nil) {
        self.pestana = pestana
        self.destino = destino
    }
}
