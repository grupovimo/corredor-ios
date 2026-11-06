import SwiftUI
import TipKit

// Consejos de una sola vez (TipKit): lo que la app hace y no se descubre solo. Cada uno aparece en su
// pantalla, una vez, y TipKit los espacia para no amontonar. «Ver el recorrido de nuevo» (Más) los vuelve
// a mostrar.

enum Consejos {
    static func configurar() {
        if ModoPrueba.activo { Tips.hideAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
    }

    /// Los vuelve a mostrar todos (con el recorrido).
    static func reiniciar() {
        try? Tips.resetDatastore()
        configurar()
    }
}

/// Lista de propiedades: el logo de WhatsApp manda la ficha.
struct ConsejoMandar: Tip {
    var title: Text { Text("Mandala en un toque") }
    var message: Text? { Text("Tocá el logo de WhatsApp para mandar la ficha. Mantené apretada una fila para editarla o pausarla.") }
    var image: Image? { Image(systemName: "paperplane") }
}

/// Inicio: el «+» carga cualquier cosa.
struct ConsejoCargar: Tip {
    var title: Text { Text("Cargá cualquier cosa desde acá") }
    var message: Text? { Text("Propiedades, contactos, visitas, operaciones y contratos, sin buscar la sección.") }
    var image: Image? { Image(systemName: "plus.circle") }
}

/// Más: todo lo que no está en las pestañas.
struct ConsejoMas: Tip {
    var title: Text { Text("Todo lo demás está en «Más»") }
    var message: Text? { Text("Mi inmobiliaria (tu web, tus datos, tu equipo, tu plan) y las herramientas: cobros, contratos, consorcios.") }
    var image: Image? { Image(systemName: "square.grid.2x2") }
}

/// Ficha del contrato: cobrar y mandar el recibo.
struct ConsejoCobrar: Tip {
    var title: Text { Text("Cobrá y mandá el recibo") }
    var message: Text? { Text("Registrá el cobro y el recibo sale solo, listo para WhatsApp. Después le rendís al dueño.") }
    var image: Image? { Image(systemName: "dollarsign.circle") }
}

/// Documentos: escanear con la cámara.
struct ConsejoEscanear: Tip {
    var title: Text { Text("Escaneá el contrato firmado") }
    var message: Text? { Text("Con la cámara: lo recortamos, lo pasamos a PDF y queda guardado acá.") }
    var image: Image? { Image(systemName: "doc.viewfinder") }
}

/// Perfil: Siri y el widget.
struct ConsejoSiri: Tip {
    var title: Text { Text("Pedíselo a Siri") }
    var message: Text? { Text("«Captar con MIRA en Corredor», «Qué tengo hoy en Corredor». Y sumá el widget a tu pantalla de inicio.") }
    var image: Image? { Image(systemName: "mic") }
}
