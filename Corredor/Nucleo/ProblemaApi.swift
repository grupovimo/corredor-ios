import Foundation

/// El problem+json de la API cuando rechaza un pedido: el título, el detalle y el error de cada campo
/// (`issues`, con el camino del campo y el mensaje), para mostrarlo debajo de él como la web.
struct ProblemaApi: Decodable {
    struct Campo: Decodable { var path: String?; var message: String? }
    var code: String?
    var title: String?
    var detail: String?
    var issues: [Campo]?
}
