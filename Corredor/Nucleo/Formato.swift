import Foundation

/// Montos, porcentajes y fechas como los escribe el handoff: `$ 184.350` (espacio fino que no corta
/// el renglón, punto de miles, coma decimal), `12,4 %`, «hoy, 14:32», «jueves 30 de octubre».
enum Formato {
    /// Espacio fino sin corte (U+202F): entre `$` y el número, y antes de `%`.
    static let fino = "\u{202F}"

    static let argentina = Locale(identifier: "es_AR")
    static let zona = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

    private static let miles: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    /// Un número entero con punto de miles: 1.234.567.
    static func numero(_ n: Int) -> String {
        miles.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Pesos enteros (la API manda pesos sin centavos): `$ 24.020`, `−$ 2.400`.
    static func pesos(_ n: Int) -> String {
        n < 0 ? "−$\(fino)\(numero(-n))" : "$\(fino)\(numero(n))"
    }

    static func pesos(_ n: Double) -> String { pesos(Int(n.rounded())) }

    /// Un porcentaje con un decimal si hace falta: `12,4 %`, `73 %`.
    static func porcentaje(_ p: Double) -> String {
        "\(decimal.string(from: NSNumber(value: p)) ?? String(p))\(fino)%"
    }

    private static func formateador(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = argentina
        f.timeZone = zona
        f.dateFormat = patron
        return f
    }

    private static let hora = formateador("H:mm")
    private static let diaLargo = formateador("EEEE d 'de' MMMM")
    private static let diaCorto = formateador("d 'de' MMM")
    private static let mes = formateador("MMMM")
    private static let diaMesAnio = formateador("d 'de' MMMM 'de' yyyy")

    static var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        c.locale = argentina
        return c
    }

    /// «14:32».
    static func horaDe(_ f: Date) -> String { hora.string(from: f) }

    /// «jueves 30 de octubre».
    static func fechaLarga(_ f: Date) -> String { diaLargo.string(from: f) }

    /// «octubre».
    static func mesDe(_ f: Date) -> String { mes.string(from: f) }

    /// «hoy», «ayer», o «28 de oct.».
    static func dia(_ f: Date, ahora: Date = Date()) -> String {
        let c = calendario
        if c.isDate(f, inSameDayAs: ahora) { return "hoy" }
        if let ayer = c.date(byAdding: .day, value: -1, to: ahora), c.isDate(f, inSameDayAs: ayer) { return "ayer" }
        return diaCorto.string(from: f)
    }

    /// Título de sección por día: «Hoy», «Ayer», «Martes 28 de octubre».
    static func seccion(_ f: Date, ahora: Date = Date()) -> String {
        let c = calendario
        if c.isDate(f, inSameDayAs: ahora) { return "Hoy" }
        if let ayer = c.date(byAdding: .day, value: -1, to: ahora), c.isDate(f, inSameDayAs: ayer) { return "Ayer" }
        return mayuscula(diaLargo.string(from: f))
    }

    /// «hoy, 14:32».
    static func cuando(_ f: Date, ahora: Date = Date()) -> String {
        "\(dia(f, ahora: ahora)), \(horaDe(f))"
    }

    /// «hace 3 h», «hace 12 min», «hace 2 días».
    static func hace(_ f: Date, ahora: Date = Date()) -> String {
        let s = max(0, Int(ahora.timeIntervalSince(f)))
        if s < 60 { return "recién" }
        if s < 3600 { return "hace \(s / 60)\(fino)min" }
        if s < 86400 { return "hace \(s / 3600)\(fino)h" }
        let d = s / 86400
        return d == 1 ? "hace 1 día" : "hace \(d) días"
    }

    static func mayuscula(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Iniciales para los avatares: «Almacén Lumbre» → «AL».
    static func iniciales(_ nombre: String) -> String {
        let p = nombre.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { $0.first?.isLetter == true }
        let s = p.prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return s.isEmpty ? "TL" : s.uppercased()
    }

    /// «1 producto», «5 productos».
    static func cantidad(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(numero(n)) \(n == 1 ? singular : plural)"
    }

    /// Une palabras cortas a la siguiente con un espacio duro, para que no queden solas al final de
    /// un renglón («a», «de», «y», «el»…): sin renglones viudos ni cortes raros.
    static func sinViudas(_ s: String) -> String {
        let cortas: Set<String> = ["a", "al", "y", "o", "u", "e", "de", "del", "el", "la", "los", "las", "en", "un", "una",
                                   "con", "por", "que", "se", "tu", "te", "su", "lo", "mi", "es", "no", "ya", "si", "ni"]
        let palabras = s.components(separatedBy: " ")
        guard palabras.count > 2 else { return s }
        var r = ""
        for (i, w) in palabras.enumerated() {
            r += w
            if i == palabras.count - 1 { break }
            // La última palabra va pegada a la anteúltima: nunca queda sola en el renglón final.
            let pegar = cortas.contains(w.lowercased()) || i == palabras.count - 2
            r += pegar ? "\u{00A0}" : " "
        }
        return r
    }
}

enum Fecha {
    private static let conFraccion: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let sinFraccion: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let soloDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Formato.zona
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// RFC 3339 con o sin fracción (Go manda nanosegundos), o una fecha sola.
    static func iso(_ s: String) -> Date? {
        if let f = conFraccion.date(from: s) { return f }
        if let f = sinFraccion.date(from: s) { return f }
        // Go puede mandar 9 decimales: ISO8601DateFormatter acepta hasta 3.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let corto = s.replacingCharacters(in: r, with: String(s[r].prefix(4)))
            if let f = conFraccion.date(from: corto) { return f }
        }
        return soloDia.date(from: s)
    }
}
