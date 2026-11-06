import Foundation

// Los destinos de navegación de toda la app. Viven acá (y no en cada área) para que cualquier pantalla
// pueda abrir la ficha de otra: el Inicio abre una propiedad, un chat abre el contacto. Cada área
// registra la vista de sus destinos en su propio `.destinos<Área>()` (Pantallas/<Área>/), y
// Principal los junta todos en `.destinos()`.

/// 3D Ficha de una propiedad.
struct AFichaPropiedad: Hashable { var id: String }
/// 3E Galería de fotos de una propiedad, desde la foto `indice`.
struct AGaleria: Hashable { var id: String; var indice = 0 }
/// 4A Alta rápida de una propiedad. `editar`: el id de una propiedad; `borrador`: el id de uno de
/// /v1/borradores para seguirlo (el de la web, el de otro aparato o el que dejó MIRA).
struct AAltaPropiedad: Hashable { var editar: String? = nil; var borrador: String? = nil }
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
struct AAvisos: Hashable { var aviso: String? = nil; var responder: String? = nil }
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
    /// `/propiedades/nueva?borrador=<id>` sigue ese borrador.
    init?(texto: String) {
        let items = URLComponents(string: texto)?.queryItems ?? []
        func param(_ n: String) -> String? { items.first { $0.name == n }?.value?.nonEmpty }
        let borrador = param("borrador")
        var t = texto
        if let q = t.firstIndex(of: "?") { t = String(t[..<q]) }
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
            if id == "nueva" {
                self.init(.propiedades, AAltaPropiedad(borrador: borrador))
            } else if let id, param("arreglar") != nil {
                // `?arreglar=<portal>`: la ficha con la hoja de «Arreglar» abierta.
                self.init(.propiedades, AArreglarPropiedad(id: id))
            } else if let id, p.count > 2, p[2] == "editar", let paso = param("paso") {
                // `/propiedades/<id>/editar?paso=fotos`: el alta en ese paso.
                self.init(.propiedades, AEditarEnPaso(id: id, paso: paso))
            } else if let id, param("compartir") == "whatsapp" {
                // `?compartir=whatsapp&contacto=<id>`: la ficha con la hoja de mandar abierta.
                self.init(.propiedades, AMandarPropiedad(id: id, contacto: param("contacto")))
            } else {
                self.init(.propiedades, id.map { AnyHashable(AFichaPropiedad(id: $0)) })
            }
        case "mira": self.init(.mira, id == "captadas" ? AnyHashable(ACaptadas()) : nil)
        case "chat", "mensajes", "whatsapp": self.init(.mensajes, id.map { AnyHashable(AChat(id: $0)) })
        case "ml", "mercadolibre":
            // `/mercadolibre/preguntas?pregunta=<id>` (los avisos) o `ml/<id>` (el push).
            if id == "preguntas" || id == nil {
                self.init(.mensajes, param("pregunta").map { AnyHashable(APreguntaML(id: $0)) } ?? AnyHashable(AMercadoLibre()))
            } else {
                self.init(.mensajes, id.map { AnyHashable(APreguntaML(id: $0)) })
            }
        case "agenda": self.init(.inicio, id.map { AnyHashable(ACita(id: $0)) } ?? AnyHashable(AAgendaDia()))
        case "mas": self.init(.mas)
        case "contacto", "contactos": self.init(.inicio, id.map { AnyHashable(AFichaContacto(id: $0)) } ?? AnyHashable(AContactos()))
        case "operacion", "operaciones": self.init(.inicio, id.map { AnyHashable(AFichaOperacion(id: $0)) } ?? AnyHashable(AOperaciones()))
        case "cobranzas":
            // `/cobranzas?registrar=1&contrato=<id>`: la hoja de «Registrar cobro» abierta.
            if param("registrar") == "1" { self.init(.inicio, ARegistrarCobro(contrato: param("contrato"))) } else { self.init(.inicio, ACobranzas()) }
        case "contrato", "contratos":
            if id == "nuevo" {
                self.init(.inicio, AAltaContrato(borrador: borrador, renovar: param("renovar")))
            } else if let id, let mes = param("recordar") {
                // `/contratos/<id>?recordar=AAAA-MM`: el recordatorio de ese mes.
                self.init(.inicio, ARecordarMes(contrato: id, periodo: mes))
            } else if let id {
                self.init(.inicio, AFichaContrato(id: id))
            } else if param("vista") != nil || param("indice") != nil {
                self.init(.inicio, AContratosFiltro(vista: param("vista"), indice: param("indice")))
            } else {
                self.init(.inicio, AContratos())
            }
        case "rendicion", "rendiciones":
            // `/rendiciones/<id>?contrato=<c>` (y `&vista=1`, como la ve el propietario).
            if let id, let c = param("contrato") {
                self.init(.inicio, param("vista") == "1" ? AnyHashable(ARendicionVista(contrato: c, id: id)) : AnyHashable(ARendicion(contrato: c, id: id)))
            } else {
                self.init(.mas, ASeccion(clave: "rendiciones"))
            }
        case "inventario", "inventarios":
            // `/inventarios/<prop>/actas/<acta>` (las firmas), `/inventarios/<prop>/devolucion`,
            // `/inventarios/<prop>?tipo=entrega|devolucion` (la recorrida en ese modo) o la recorrida.
            if let id, p.count > 3, p[2] == "actas" {
                self.init(.inicio, AFirmas(id: "\(id)/\(p[3])"))
            } else if let id, p.count > 2, p[2] == "devolucion" {
                self.init(.inicio, ADevolucion(id: id))
            } else if let id, let tipo = param("tipo") {
                self.init(.inicio, ARecorrida(id: id, tipo: tipo))
            } else if let id {
                self.init(.inicio, AInventario(id: id))
            } else {
                self.init(.mas, ASeccion(clave: "inventarios"))
            }
        case "avisos":
            // `/avisos?aviso=<id>&responder=<accion>`: ese aviso (y su respuesta) en vez de la lista.
            self.init(.inicio, AAvisos(aviso: param("aviso"), responder: param("responder")))
        case "perfil": self.init(.inicio, APerfil())
        case "buscar": self.init(.inicio, ABuscar(texto: param("q") ?? ""))
        case "reserva", "reservas": self.init(.mas, id.map { AnyHashable(AReserva(id: $0)) } ?? AnyHashable(ASeccion(clave: "reservas")))
        case "temporada":
            if id == "reservas", p.count > 2 { self.init(.mas, AReservaTemporada(id: p[2])) } else { self.init(.mas, ASeccion(clave: "temporada")) }
        // Configuración: cada sección por su nombre (`/configuracion/equipo`, `/configuracion/ia`…).
        case "configuracion":
            let sub = id.flatMap { ["equipo", "integraciones", "ia", "proveedores", "respuestas"].contains($0) ? $0 : nil }
            self.init(.mas, ASeccion(clave: sub ?? "configuracion"))
        // `/invitacion/<token>`: la invitación para ver antes de aceptar.
        case "invitacion": self.init(.mas, ASeccion(clave: id == nil ? "invitaciones" : "invitacion", id: id))
        // `/conectar-ia/autorizar?solicitud=<id>`: el permiso que pide el asistente.
        case "conectar-ia":
            if let s = param("solicitud") { self.init(.mas, ASeccion(clave: "autorizar-ia", id: s)) } else { self.init(.mas, ASeccion(clave: "ia")) }
        // Rutas del panel con id (los avisos traen las de la web): la ficha, no la lista.
        case "consorcios", "consorcio":
            // `/consorcios/<id>/liquidar`, `/consorcios/<id>/trabajos/<t>` y `/consorcios/<id>/<pestaña>`.
            if let id, p.count > 2 {
                if p[2] == "liquidar" {
                    self.init(.mas, ALiquidarConsorcio(consorcio: id, periodo: param("periodo")))
                } else if p[2] == "trabajos", p.count > 3 {
                    self.init(.mas, ATrabajoConsorcio(consorcio: id, id: p[3]))
                } else {
                    var pedido: String?
                    if param("vista") == "deudores" { pedido = "deben" }
                    else if let u = param("unidad") { pedido = "unidad:\(u)" }
                    else if param("nueva") == "1" || param("nuevo") == "1" { pedido = "nueva" }
                    else if let r = param("recibo") { pedido = "recibo:\(r)" }
                    else if param("liquidar") == "1" { pedido = "liquidar" }
                    self.init(.mas, AFichaConsorcioEn(id: id, pestana: p[2], pedido: pedido))
                }
            } else {
                self.init(.mas, ASeccion(clave: id == nil ? "consorcios" : "consorcio", id: id))
            }
        // `/revision?ids=a,b`: sólo esos borradores.
        case "revision": self.init(.mas, param("ids").map { AnyHashable(ARevisionIds(ids: $0)) } ?? AnyHashable(ASeccion(clave: "revision")))
        // `/importar?id=<vista previa>`: retomarla.
        case "importar": self.init(.mas, ASeccion(clave: "importar", id: param("id")))
        case "emprendimientos", "emprendimiento": self.init(.mas, ASeccion(clave: id == nil ? "emprendimientos" : "emprendimiento", id: id))
        default: self.init(.mas, ASeccion(clave: a, id: id))
        }
    }

    init(_ pestana: Pestana, _ destino: AnyHashable? = nil) {
        self.pestana = pestana
        self.destino = destino
    }
}
