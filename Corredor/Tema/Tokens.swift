import SwiftUI
import UIKit

// Los tokens del handoff (docs/handoff/design_handoff_corredor_iphone · 09 «Tokens SwiftUI»), claro y oscuro.

extension UIColor {
    convenience init(hex: UInt32, alfa: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alfa)
    }
}

extension Color {
    init(hex: UInt32, alfa: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alfa: alfa))
    }

    /// Un color que cambia con el modo oscuro.
    static func tema(_ claro: UInt32, _ oscuro: UInt32, alfa: CGFloat = 1, alfaOscuro: CGFloat? = nil) -> Color {
        Color(uiColor: .tema(claro, oscuro, alfa: alfa, alfaOscuro: alfaOscuro))
    }
}

extension UIColor {
    static func tema(_ claro: UInt32, _ oscuro: UInt32, alfa: CGFloat = 1, alfaOscuro: CGFloat? = nil) -> UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: oscuro, alfa: alfaOscuro ?? alfa) : UIColor(hex: claro, alfa: alfa)
        }
    }
}

/// Colores del handoff de Corredor (09 · «Tokens SwiftUI»): Fondo, Superficie, Tinta, Línea, Acción
/// (verde; oro en oscuro) y los estados. Los nombres de Tu Local Web se mantienen para las piezas
/// compartidas (Piezas, Estados, FilaDeslizable).
enum C {
    static let fondo = Color.tema(0xF3EFE6, 0x111314)
    static let elevado = Color.tema(0xFFFDF8, 0x1B1E20)
    static let superficie = Color.tema(0xFFFDF8, 0x1B1E20)
    static let hundida = Color.tema(0xE9E5DB, 0x25292C)
    static let texto = Color.tema(0x18201D, 0xEEF0F1)
    static let texto2 = Color.tema(0x4D5853, 0xA8AEB2)
    static let texto3 = Color.tema(0x68716C, 0x8B9195)
    static let chevron = Color.tema(0xA9B1AC, 0x50585D)
    /// Acción: verde en claro, oro en oscuro.
    static let accion = Color.tema(0x16443B, 0xF2BB57)
    static let sobreAccion = Color.tema(0xFFFFFF, 0x1A1405)
    static let verde800 = Color(hex: 0x0F3530)
    static let verde700 = Color(hex: 0x16443B)
    static let oro = Color(hex: 0xF2BB57)
    static let oroTinta = Color.tema(0x7A5200, 0xF2BB57)
    static let acento = accion
    static let primarioTexto = Color.tema(0x16443B, 0xF2BB57)
    static let primarioTinta = Color.tema(0x16443B, 0xF7CB73)
    static let crema = Color.tema(0xFBEDCC, 0xF2BB57, alfaOscuro: 0.18)
    static let crema2 = Color.tema(0xF7F3EA, 0x25292C)
    static let pista = Color.tema(0xE9E5DB, 0x25292C)
    static let pistaMeta = Color.tema(0xE9E5DB, 0x25292C)
    static let ok = Color.tema(0x1E5749, 0x9FD6C2)
    static let okFondo = Color.tema(0xE4EEE9, 0x9FD6C2, alfaOscuro: 0.16)
    static let okTinta = Color.tema(0x16443B, 0x9FD6C2)
    static let aviso = Color.tema(0xC48A1C, 0xF2BB57)
    static let avisoFondo = Color.tema(0xFBEDCC, 0xF2BB57, alfaOscuro: 0.16)
    static let avisoTinta = Color.tema(0x7A5200, 0xF2BB57)
    static let bannerTinta = Color.tema(0x7A5200, 0xF2BB57)
    static let azulFondo = Color.tema(0xE7EFF9, 0x9CC2EF, alfaOscuro: 0.16)
    static let azulTinta = Color.tema(0x1F4F8A, 0x9CC2EF)
    static let violetaFondo = Color.tema(0xF1EAF9, 0xC9A8EF, alfaOscuro: 0.16)
    static let violetaTinta = Color.tema(0x5B3A8C, 0xC9A8EF)
    static let error = Color.tema(0xB42318, 0xF29B92)
    static let errorFondo = Color.tema(0xFBE4E1, 0xF29B92, alfaOscuro: 0.16)
    static let errorTinta = Color.tema(0xB42318, 0xF29B92)
    static let neutroFondo = Color.tema(0xE9E5DB, 0xEEF0F1, alfaOscuro: 0.08)
    static let neutroTinta = Color.tema(0x4D5853, 0xA8AEB2)
    static let apagadoFondo = Color.tema(0xEFEBE2, 0xEEF0F1, alfaOscuro: 0.06)
    static let linea = Color.tema(0xE3DDCF, 0x2E3336)
    static let linea2 = Color.tema(0xD5CEBE, 0x32413B)
    static let anillo = Color.tema(0x0F3530, 0xE8EFE9, alfa: 0.06, alfaOscuro: 0.08)
    static let segmentado = Color.tema(0x0F3530, 0xE8EFE9, alfa: 0.07, alfaOscuro: 0.07)
    static let segmentoElegido = Color.tema(0xFFFDF8, 0x26332E)
    static let velo = Color(hex: 0x0B2622, alfa: 0.45)
    static let rayado1 = Color.tema(0xEDE7DA, 0x1F2C27)
    static let rayado2 = Color.tema(0xF5F0E6, 0x16211D)
    static let esqueleto1 = Color.tema(0xE9E5DB, 0x1F2C27)
    static let esqueleto2 = Color.tema(0xF1EDE4, 0x16211D)
    static let canalWeb = Color.tema(0x16443B, 0x9FD6C2)
    static let canalML = Color(hex: 0xE9AD44)
    static let canalWhatsApp = Color(hex: 0x25D366)
    static let canalLocal = Color.tema(0x4D5853, 0xA9B8B1)
    /// El botón principal: acción lisa (el handoff no usa gradiente).
    static let primario = LinearGradient(colors: [accion, accion], startPoint: .top, endPoint: .bottom)
    static let sombraPrimario = Color(hex: 0x16443B, alfa: 0.5)
    /// Sombras teñidas de verde (e1, e2, e3).
    static let sombra = Color(hex: 0x16443B)
}

/// Pesos de Geist incluidos en el bundle (UIAppFonts).
enum Peso {
    case regular, medium, semibold, bold, extrabold

    var nombre: String {
        switch self {
        case .regular: return "Geist-Regular"
        case .medium, .semibold: return "Geist-SemiBold"
        case .bold: return "Geist-Bold"
        case .extrabold: return "Geist-ExtraBold"
        }
    }

    var ui: UIFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .extrabold: return .heavy
        }
    }
}

/// Un estilo de texto del handoff: tamaño, peso, tracking (en em) y el estilo de Dynamic Type al que
/// escala.
struct Estilo {
    var tamano: CGFloat
    var peso: Peso
    var tracking: CGFloat = 0
    var relativo: Font.TextStyle

    var font: Font { .custom(peso.nombre, size: tamano, relativeTo: relativo) }

    static let montoHeroe = Estilo(tamano: 46, peso: .bold, tracking: -0.035, relativo: .largeTitle)
    static let montoCobro = Estilo(tamano: 52, peso: .bold, tracking: -0.035, relativo: .largeTitle)
    static let montoPantalla = Estilo(tamano: 40, peso: .bold, tracking: -0.03, relativo: .largeTitle)
    static let tituloGrande = Estilo(tamano: 34, peso: .extrabold, tracking: -0.035, relativo: .largeTitle)
    static let titulo = Estilo(tamano: 28, peso: .bold, tracking: -0.03, relativo: .title)
    static let titulo3 = Estilo(tamano: 20, peso: .bold, tracking: -0.02, relativo: .title3)
    static let caption = Estilo(tamano: 12, peso: .bold, tracking: 0.02, relativo: .caption)
    static let saludo = Estilo(tamano: 32, peso: .bold, tracking: -0.025, relativo: .title)
    static let tituloPaso = Estilo(tamano: 30, peso: .bold, tracking: -0.025, relativo: .title)
    static let tituloBloqueo = Estilo(tamano: 28, peso: .bold, tracking: -0.02, relativo: .title)
    static let montoMeta = Estilo(tamano: 28, peso: .bold, tracking: -0.025, relativo: .title)
    static let tituloHoja = Estilo(tamano: 24, peso: .bold, tracking: -0.02, relativo: .title2)
    static let tituloHojaChico = Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2)
    static let tituloSeccion = Estilo(tamano: 21, peso: .bold, tracking: -0.02, relativo: .title3)
    static let indicador = Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title3)
    static let nombreTienda = Estilo(tamano: 18, peso: .bold, relativo: .headline)
    static let total = Estilo(tamano: 18, peso: .bold, relativo: .headline)
    static let headline = Estilo(tamano: 17, peso: .semibold, relativo: .headline)
    static let body = Estilo(tamano: 17, peso: .regular, relativo: .body)
    static let fila = Estilo(tamano: 16, peso: .semibold, relativo: .body)
    static let body16 = Estilo(tamano: 16, peso: .regular, relativo: .body)
    static let tarjetaTincho = Estilo(tamano: 16, peso: .medium, relativo: .body)
    static let subhead = Estilo(tamano: 15, peso: .regular, relativo: .subheadline)
    static let subheadFuerte = Estilo(tamano: 15, peso: .semibold, relativo: .subheadline)
    static let filaLista = Estilo(tamano: 15, peso: .semibold, relativo: .subheadline)
    static let label = Estilo(tamano: 14, peso: .semibold, relativo: .footnote)
    static let texto14 = Estilo(tamano: 14, peso: .regular, relativo: .footnote)
    static let footnote = Estilo(tamano: 13, peso: .regular, relativo: .footnote)
    static let footnoteFuerte = Estilo(tamano: 13, peso: .semibold, relativo: .footnote)
    static let chip = Estilo(tamano: 12, peso: .semibold, relativo: .caption)
    static let etiqueta = Estilo(tamano: 11, peso: .bold, relativo: .caption2)
    static let tab = Estilo(tamano: 10, peso: .semibold, relativo: .caption2)
}

extension View {
    /// Aplica un estilo del handoff (fuente, tracking).
    func estilo(_ e: Estilo) -> some View {
        font(e.font).tracking(e.tamano * e.tracking)
    }
}

extension Text {
    /// Para concatenar Text con estilos distintos.
    func estiloTexto(_ e: Estilo) -> Text {
        font(e.font).tracking(e.tamano * e.tracking)
    }
}

/// Medidas del handoff.
enum M {
    /// Margen horizontal: 20 (16 en SE, 24 en Pro Max).
    static func margen(_ ancho: CGFloat) -> CGFloat {
        ancho <= 375 ? 16 : (ancho >= 428 ? 24 : 20)
    }
    static let tabBar: CGFloat = 49
    /// Radios continuos: control, tarjeta, destacada y hoja.
    static let rControl: CGFloat = 12
    static let rTarjeta: CGFloat = 18
    static let rDestacada: CGFloat = 22
    static let rHoja: CGFloat = 30
}

extension View {
    /// e1: radio 2, y 1, 7 %.
    func sombraE1() -> some View { shadow(color: C.sombra.opacity(0.07), radius: 1, y: 1) }
    /// e2: la de las tarjetas.
    func sombraE2() -> some View {
        shadow(color: C.sombra.opacity(0.07), radius: 1, y: 1).shadow(color: C.sombra.opacity(0.32), radius: 11, y: 10)
    }
    /// e3: la de lo que flota (hojas, el botón de MIRA).
    func sombraE3() -> some View { shadow(color: C.verde800.opacity(0.8), radius: 20, y: 22) }
    /// Una tarjeta del handoff: superficie, radio 18 continuo y e2.
    func tarjeta(_ radio: CGFloat = M.rTarjeta) -> some View {
        background(C.superficie, in: .rect(cornerRadius: radio, style: .continuous)).sombraE2()
    }
}

/// El ancho de la pantalla para los márgenes del handoff (SE / estándar / Pro Max).
private struct AnchoPantallaKey: EnvironmentKey {
    static let defaultValue: CGFloat = 393
}

extension EnvironmentValues {
    var anchoPantalla: CGFloat {
        get { self[AnchoPantallaKey.self] }
        set { self[AnchoPantallaKey.self] = newValue }
    }
    var margen: CGFloat { M.margen(anchoPantalla) }
}

/// UIKit: la barra de navegación nativa (pantallas de detalle) con la tipografía y los colores del
/// handoff: back con chevron y el título del padre en `primary-text`, título 17/600.
enum Apariencia {
    @MainActor
    static func aplicar() {
        let a = UINavigationBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = .tema(0xF3EFE6, 0x0E1714)
        a.shadowColor = .clear
        let titulo = UIFont(name: Peso.semibold.nombre, size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        a.titleTextAttributes = [.font: titulo, .foregroundColor: UIColor.tema(0x18201D, 0xE8EFE9)]
        let grande = UIFont(name: Peso.bold.nombre, size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        a.largeTitleTextAttributes = [.font: grande, .kern: -0.85, .foregroundColor: UIColor.tema(0x18201D, 0xE8EFE9)]
        let boton = UIBarButtonItemAppearance()
        let fuenteBoton = UIFont(name: Peso.regular.nombre, size: 17) ?? .systemFont(ofSize: 17)
        boton.normal.titleTextAttributes = [.font: fuenteBoton, .foregroundColor: UIColor.tema(0x16443B, 0xF2BB57)]
        a.buttonAppearance = boton
        a.backButtonAppearance = boton
        UINavigationBar.appearance().standardAppearance = a
        UINavigationBar.appearance().scrollEdgeAppearance = a
        UINavigationBar.appearance().compactAppearance = a
        UINavigationBar.appearance().tintColor = .tema(0x16443B, 0xF2BB57)
        UIRefreshControl.appearance().tintColor = .tema(0x68716C, 0x8A9A93)
    }
}
