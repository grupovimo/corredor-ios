import SafariServices
import SwiftUI

/// Los links de corredor.com.ar (el panel) que abren la app. Qué paths los declara `enlaces.json` de la web
/// (crm-inmobiliaria, web/src/lib; copia en CorredorTests); la pantalla de cada uno la elige `Ruta(texto:)`. Lo que
/// la app no tiene, o es sólo de la web (impresos, exportes, legales), se abre en la web dentro de la app: nunca
/// «No encontramos esta sección».
enum Vinculos {
    static let base = URL(string: "https://corredor.com.ar")!

    /// Las secciones que dibuja `Seccion` (Secciones.swift), además de las que Ruta abre con su propia pantalla.
    static let secciones: Set<String> = [
        "mas", "plan", "suscripcion", "configuracion", "inmobiliaria", "equipo", "integraciones", "whatsapp",
        "mercadolibre", "respuestas", "proveedores", "objetivos", "inventarios", "actas", "rendiciones", "papelera",
        "actividad", "revision", "informe", "indices", "vistas", "tarifas", "web", "plantillas", "editor", "difusion",
        "emprendimientos", "emprendimiento", "temporada", "reservas", "consorcios", "consorcio", "importar", "ia",
        "firma", "invitacion", "invitaciones", "empezar",
    ]

    /// Lo que vive sólo en la web aunque esté en el panel: impresos, planillas, archivos, endpoints, legales, la
    /// rendición del propietario y las vueltas de OAuth y de Mercado Pago (los «web» de enlaces.json y más).
    static func soloWeb(_ camino: String) -> Bool {
        let p = camino.split(separator: "/").map(String.init)
        guard let a = p.first else { return true }
        if ["privacidad", "terminos", "og", "rendicion", "plan", "integraciones", "archivos", "exportar", "guia"].contains(a) { return true }
        if let u = p.last, ["ficha", "tarjeta", "imprimir", "excel", "hacer", "accion", "marcar", "lista", "publicar", "sugerencia"].contains(u), p.count > 1 { return true }
        return p.contains("api") || p.contains("imprimir") || p.contains("excel") || (a == "contratos" && p.contains("documentos"))
    }

    /// La web dentro de la app, como una sección de Más.
    static func web(_ u: URL) -> Ruta { Ruta(.mas, ASeccion(clave: "en-la-web", id: u.absoluteString)) }
}

extension Ruta {
    /// Cómo se escribe la ruta en `enlaces.json` («inicio:ACita», «mas:ASeccion/consorcios», «web-en-app»).
    var clave: String {
        guard let d = destino?.base else { return pestana.rawValue }
        if let s = d as? ASeccion { return s.clave == "en-la-web" ? "web-en-app" : "\(pestana.rawValue):ASeccion/\(s.clave)" }
        return "\(pestana.rawValue):\(String(describing: type(of: d)))"
    }
}

/// La web del panel dentro de la app (un link que la app no tiene).
struct NavegadorWeb: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}
