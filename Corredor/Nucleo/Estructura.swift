import Foundation
import SwiftUI

/// GET /v1/panel/estructura: «Mi inmobiliaria» y «Herramientas», las acciones rápidas del botón del
/// medio, el alta (pasos y porcentaje) y la marca publicada. La arma la API, igual para la app y para
/// el panel web; acá sólo se sabe el ícono y a dónde lleva cada clave (las claves, en
/// docs/estructura-claves.json de crm-inmobiliaria; las prueba EstructuraTests).
struct Estructura: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable { var clave: String; var nombre: String; var palabras: [String]; var id: String { clave } }
    struct Grupo: Codable, Equatable { var titulo: String; var items: [Item] }
    struct Parte: Codable, Equatable, Identifiable { var clave: String; var titulo: String; var grupos: [Grupo]; var id: String { clave } }
    struct Rapida: Codable, Equatable, Identifiable { var clave: String; var nombre: String; var id: String { clave } }
    struct Marca: Codable, Equatable { var logoUrl: String?; var colorPrimario: String?; var colorSecundario: String? }

    var partes: [Parte]
    var rapidas: [Rapida]
    var alta: Alta
    var rubros: [String]
    var escondido: Bool
    var marca: Marca?

    var logo: URL? { marca?.logoUrl.flatMap(URL.init(string:)) }
}

/// El alta de la inmobiliaria: los pasos del asistente (los mismos que el panel), el porcentaje, lo
/// que falta y si ya tiene lo mínimo (logo y WhatsApp) para entrar.
struct Alta: Codable, Equatable {
    struct Paso: Codable, Equatable, Identifiable {
        var clave: String
        var titulo: String
        var texto: String
        var obligatorio: Bool
        var peso: Int
        var hecho: Bool
        var id: String { clave }
    }
    var pasos: [Paso]
    var completo: Int
    var faltan: [String]
    var minimoListo: Bool
    var terminada: Bool
}

/// Ícono y destino de cada clave de la estructura (lo único que la app sabe de cada sección).
enum Lugares {
    static let secciones: [String: (String, AnyHashable)] = [
        "web": ("globe", AnyHashable(ASeccion(clave: "web"))),
        "configuracion": ("storefront", AnyHashable(ASeccion(clave: "configuracion"))),
        "equipo": ("person.3", AnyHashable(ASeccion(clave: "equipo"))),
        "plan": ("crown", AnyHashable(ASeccion(clave: "plan"))),
        "integraciones": ("puzzlepiece.extension", AnyHashable(ASeccion(clave: "integraciones"))),
        "ia": ("sparkles", AnyHashable(ASeccion(clave: "ia"))),
        "papelera": ("trash", AnyHashable(ASeccion(clave: "papelera"))),
        "agenda": ("calendar", AnyHashable(AAgendaDia())),
        "avisos": ("bell", AnyHashable(AAvisos())),
        "buscar": ("magnifyingglass", AnyHashable(ABuscar())),
        "contactos": ("person.2", AnyHashable(AContactos())),
        "operaciones": ("rectangle.split.3x1", AnyHashable(AOperaciones())),
        "reservas": ("hand.raised", AnyHashable(ASeccion(clave: "reservas"))),
        "emprendimientos": ("building", AnyHashable(ASeccion(clave: "emprendimientos"))),
        "temporada": ("beach.umbrella", AnyHashable(ASeccion(clave: "temporada"))),
        "cobranzas": ("dollarsign.circle", AnyHashable(ACobranzas())),
        "contratos": ("doc.text", AnyHashable(AContratos())),
        "rendiciones": ("doc.plaintext", AnyHashable(ASeccion(clave: "rendiciones"))),
        "inventarios": ("checklist", AnyHashable(ASeccion(clave: "inventarios"))),
        "indices": ("chart.line.uptrend.xyaxis", AnyHashable(ASeccion(clave: "indices"))),
        "consorcios": ("building.columns", AnyHashable(ASeccion(clave: "consorcios"))),
        "proveedores": ("wrench.and.screwdriver", AnyHashable(ASeccion(clave: "proveedores"))),
        "difusion": ("megaphone", AnyHashable(ASeccion(clave: "difusion"))),
        "respuestas": ("quote.bubble", AnyHashable(ASeccion(clave: "respuestas"))),
        "importar": ("square.and.arrow.down", AnyHashable(ASeccion(clave: "importar"))),
        "objetivos": ("flag", AnyHashable(ASeccion(clave: "objetivos"))),
        "informe": ("chart.bar", AnyHashable(ASeccion(clave: "informe"))),
        "revision": ("checkmark.shield", AnyHashable(ASeccion(clave: "revision"))),
        "actividad": ("clock.arrow.circlepath", AnyHashable(ASeccion(clave: "actividad"))),
    ]

    /// Las acciones del botón del medio: el ícono (las abre `AccionesRapidas`).
    static let rapidas: [String: String] = [
        "captar": "viewfinder", "propiedad": "house", "contacto": "person.badge.plus", "visita": "calendar.badge.plus",
        "contrato": "doc.badge.plus", "cobrar": "dollarsign.circle", "web": "paintbrush",
        "buscar": "magnifyingglass", "agenda": "calendar", "avisos": "bell",
    ]
}

/// Abre el alta (el asistente) en un paso: desde el Inicio, «Más» o la primera vez.
struct PasoAlta: Identifiable, Equatable { var clave: String?; var id: String { clave ?? "-" } }

extension Estado {
    /// Pide la estructura (con «Mostrar todas las secciones», sin esconder por rubros) y pone el acento.
    func cargarEstructura() async {
        guard sesion?.inmobiliariaId != nil else { return }
        let todas = UserDefaults.standard.bool(forKey: "todasLasSecciones")
        guard let e: Estructura = try? await api.get("/v1/panel/estructura", query: todas ? [URLQueryItem(name: "todas", value: "1")] : []) else { return }
        estructura = e
        Guardado.guardar(e, clave: "estructura")
        ponerAcento(Acento.de(primario: e.marca?.colorPrimario, secundario: e.marca?.colorSecundario))
        Spotlight.indexarSecciones(duenio: esDuenio)
        // Una inmobiliaria nueva sin lo mínimo (logo y WhatsApp): el dueño sigue el alta antes que nada.
        if esDuenio, !e.alta.terminada, !e.alta.minimoListo, altaAbierta == nil { altaAbierta = PasoAlta(clave: nil) }
    }

    /// Cambia el acento; si cambió, repinta la app entera (los colores dinámicos lo leen al pintarse).
    func ponerAcento(_ a: Acento?) {
        guard a != Acento.actual else { return }
        Acento.actual = a
        marcaVersion += 1
    }
}
