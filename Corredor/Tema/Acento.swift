import SwiftUI
import UIKit

/// El acento de la marca (la misma regla que el panel: web/src/lib/ui/acento.ts y
/// docs/marca-acento.md en crm-inmobiliaria; los casos de prueba, en AcentoTests). La inmobiliaria ve
/// su color en los botones, los links y lo elegido; fondos y textos siguen siendo los de Corredor.
///
/// - Claro: el color principal, oscurecido (mezcla con negro, de a 8 %) hasta que el blanco encima
///   pase AA (4.5:1).
/// - Oscuro: el de acento (o el principal), aclarado (mezcla con blanco, de a 8 %) hasta pasar AA
///   contra la superficie oscura (#1b1e20) y con la tinta oscura encima (#1a1405).
/// - Sin color o sin llegar en 24 pasos: nil (quedan el verde y el oro de Corredor).
struct Acento: Equatable {
    var claro: UInt32
    var claroHondo: UInt32
    var oscuro: UInt32
    var oscuroHondo: UInt32

    typealias Rgb = (Double, Double, Double)

    static func rgb(_ texto: String?) -> Rgb? {
        guard var h = texto?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, h.allSatisfy(\.isHexDigit), let n = UInt32(h, radix: 16) else { return nil }
        return (Double((n >> 16) & 0xFF), Double((n >> 8) & 0xFF), Double(n & 0xFF))
    }

    /// Redondea cada canal (como `hexDe` del panel: Math.round, que para positivos es lo mismo).
    static func hex(_ c: Rgb) -> UInt32 {
        func r(_ v: Double) -> UInt32 { UInt32(max(0, min(255, v)).rounded(.toNearestOrAwayFromZero)) }
        return (r(c.0) << 16) | (r(c.1) << 8) | r(c.2)
    }

    static func rgb(_ n: UInt32) -> Rgb { (Double((n >> 16) & 0xFF), Double((n >> 8) & 0xFF), Double(n & 0xFF)) }

    static func luminancia(_ c: Rgb) -> Double {
        func l(_ v: Double) -> Double { let s = v / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * l(c.0) + 0.7152 * l(c.1) + 0.0722 * l(c.2)
    }

    static func contraste(_ a: UInt32, _ b: UInt32) -> Double {
        let x = luminancia(rgb(a)), y = luminancia(rgb(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Mezcla `a` con `b` (t: cuánto de `b`) y redondea, como el panel.
    static func mezclar(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let x = rgb(a), y = rgb(b)
        return hex((x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t))
    }

    private static let blanco: UInt32 = 0xFFFFFF, negro: UInt32 = 0x000000
    private static let superficieOscura: UInt32 = 0x1B1E20, tintaOscura: UInt32 = 0x1A1405
    private static let paso = 0.08, pasos = 24

    static func paraClaro(_ c: UInt32) -> UInt32? {
        var x = c
        var i = 0
        while i < pasos, contraste(x, blanco) < 4.5 { x = mezclar(x, negro, paso); i += 1 }
        return contraste(x, blanco) >= 4.5 ? x : nil
    }

    static func paraOscuro(_ c: UInt32) -> UInt32? {
        func pasa(_ y: UInt32) -> Bool { contraste(y, superficieOscura) >= 4.5 && contraste(y, tintaOscura) >= 4.5 }
        var x = c
        var i = 0
        while i < pasos, !pasa(x) { x = mezclar(x, blanco, paso); i += 1 }
        return pasa(x) ? x : nil
    }

    /// El acento de una marca, o nil para dejar el de Corredor.
    static func de(primario: String?, secundario: String?) -> Acento? {
        guard let p = rgb(primario).map(hex), let claro = paraClaro(p),
              let oscuro = paraOscuro(rgb(secundario).map(hex) ?? p) else { return nil }
        return Acento(claro: claro, claroHondo: mezclar(claro, negro, 0.12), oscuro: oscuro, oscuroHondo: mezclar(oscuro, negro, 0.08))
    }

    /// El de la inmobiliaria abierta (lo pone `Estado` con la marca publicada; nil: el de Corredor).
    /// Los colores dinámicos de `C` lo leen al pintarse.
    nonisolated(unsafe) static var actual: Acento?
}

extension UIColor {
    /// La acción de la app: el acento de la inmobiliaria, o el verde (claro) y el oro (oscuro) de Corredor.
    static let accion = UIColor { t in
        let oscuro = t.userInterfaceStyle == .dark
        if let a = Acento.actual { return UIColor(hex: oscuro ? a.oscuro : a.claro) }
        return UIColor(hex: oscuro ? 0xF2BB57 : 0x16443B)
    }
}
