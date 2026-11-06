import Foundation

/// El alta rápida de la agenda, como la web (lib/crm/entender.ts): «visita Gorriti 5530 con Inés
/// Robledo el sábado a las 11» se entiende como lo dirías. Saca el tipo, la propiedad (de la
/// cartera), la persona (de los contactos), el día y la hora, y marca qué entendió de cada cosa.
/// Todo en la hora de Buenos Aires.
enum Entender {
    enum Clase: Hashable { case prop, persona, cuando }
    struct Parte: Hashable { var t: String; var clase: Clase? }
    struct Opcion: Hashable, Identifiable { var id: String; var titulo: String; var agenteId: String?; var barrio: String? }

    struct Entendido {
        var tipo: String
        var propiedad: Opcion?
        var contacto: Opcion?
        /// yyyy-MM-dd, o nil si no dijo el día.
        var dia: String?
        /// HH:mm, o nil si no dijo la hora.
        var hora: String?
        var duracionMin: Int
        /// Lo que queda como título si no hay propiedad.
        var titulo: String
        var partes: [Parte]
    }

    private static let dias = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    static let duracion: [String: Int] = ["visita": 45, "tasacion": 60, "firma": 60, "llamado": 15, "otro": 30]

    /// Minúsculas sin acentos, con la misma cantidad de letras que el original.
    static func plano(_ s: String) -> String {
        String(s.map { c -> Character in
            let f = String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            return f.first ?? c
        })
    }

    private struct Tramo { var desde: Int; var hasta: Int; var clase: Clase }
    private struct Hallazgo { var desde: Int; var hasta: Int; var grupos: [String?] }

    /// Las coincidencias de `patron` en `p`, con posiciones en letras (no en UTF-16).
    private static func todas(_ patron: String, _ p: String, desde: Int = 0) -> [Hallazgo] {
        guard let re = try? NSRegularExpression(pattern: patron) else { return [] }
        let arranque = p.index(p.startIndex, offsetBy: min(desde, p.count))
        let ns = NSRange(arranque..., in: p)
        return re.matches(in: p, range: ns).compactMap { m in
            guard let r = Range(m.range, in: p) else { return nil }
            let a = p.distance(from: p.startIndex, to: r.lowerBound)
            let b = p.distance(from: p.startIndex, to: r.upperBound)
            let g: [String?] = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: p).map { String(p[$0]) } }
            return Hallazgo(desde: a, hasta: b, grupos: g)
        }
    }

    private static func primera(_ patron: String, _ p: String, desde: Int = 0) -> Hallazgo? { todas(patron, p, desde: desde).first }
    private static func hay(_ patron: String, _ t: String) -> Bool { t.range(of: patron, options: .regularExpression) != nil }
    private static func escapar(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    private static func hoyEnBA(_ ahora: Date) -> (dia: String, dow: Int) {
        let c = Formato.calendario
        return (Formato.diaISO(ahora), c.component(.weekday, from: ahora) - 1)
    }

    static func sumar(_ dia: String, _ n: Int) -> String {
        guard let d = Fecha.dia(dia), let x = Calendar.current.date(byAdding: .day, value: n, to: d) else { return dia }
        return Formato.diaISO(x)
    }

    private static func letras(_ s: String, _ a: Int, _ b: Int) -> String {
        let l = Array(s)
        let x = max(0, min(a, l.count)), y = max(x, min(b, l.count))
        return String(l[x..<y])
    }

    static func entender(_ texto: String, ahora: Date = Date(), propiedades: [Opcion] = [], contactos: [Opcion] = [], tipo forzado: String? = nil) -> Entendido {
        let p = plano(texto)
        var tramos: [Tramo] = []
        func libre(_ a: Int, _ b: Int) -> Bool { !tramos.contains { a < $0.hasta && b > $0.desde } }

        // El tipo, por la primera palabra.
        var tipo = forzado ?? "otro"
        let inicio = String(p.drop { $0.isWhitespace })
        for (re, t) in [("^(visita|visitar|mostrar)\\b", "visita"), ("^(tasacion|tasar)\\b", "tasacion"), ("^(firma|firmar)\\b", "firma"), ("^(llamar|llamado|llamada)\\b", "llamado")]
            where hay(re, inicio) { tipo = t }
        if forzado == nil && tipo == "otro", let m = primera("\\b(visita|tasacion|firma)\\b", p), let t = m.grupos[1] { tipo = t }

        // El cuándo: día y hora, juntos o por separado.
        let (hoy, dow) = hoyEnBA(ahora)
        var dia: String?
        var hora: String?
        let reDia = "\\b(?:(?:el|este|esta|el proximo|la proxima|proximo|proxima)\\s+)?(hoy|pasado manana|manana|domingo|lunes|martes|miercoles|jueves|viernes|sabado)\\b|\\b(?:el\\s+)?(\\d{1,2})(?:/(\\d{1,2})|\\s+de\\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre))\\b"
        if let md = primera(reDia, p) {
            if let w = md.grupos[1] {
                if w == "hoy" { dia = hoy }
                else if w == "manana" { dia = sumar(hoy, 1) }
                else if w == "pasado manana" { dia = sumar(hoy, 2) }
                else if let objetivo = dias.firstIndex(of: w) {
                    var n = (objetivo - dow + 7) % 7
                    if n == 0 || hay("proxim", md.grupos[0] ?? "") { n = n == 0 ? 7 : n }
                    dia = sumar(hoy, n)
                }
            } else if let ds = md.grupos[2], let d = Int(ds) {
                let m = md.grupos[3].flatMap { Int($0) } ?? ((md.grupos[4].flatMap { meses.firstIndex(of: $0) } ?? -1) + 1)
                var anio = Int(hoy.prefix(4)) ?? 2026
                let cand = String(format: "%04d-%02d-%02d", anio, m, d)
                if cand < hoy { anio += 1 }
                if (1...12).contains(m) && (1...31).contains(d) { dia = String(format: "%04d-%02d-%02d", anio, m, d) }
            }
            if dia != nil { tramos.append(Tramo(desde: md.desde, hasta: md.hasta, clase: .cuando)) }
        }
        let reHora = "\\b(?:a\\s+las?\\s+|a\\s+la\\s+)?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(?:hs?\\b|horas\\b)?(\\s+de\\s+la\\s+(?:manana|tarde|noche))?|\\bal\\s+mediodia\\b"
        for mh in todas(reHora, p) {
            let a = mh.desde, b = mh.hasta
            let todo = mh.grupos[0] ?? ""
            let sinLas = todo.replacingOccurrences(of: "^a\\s+las?\\s+", with: "", options: .regularExpression)
            let conLas = hay("^a\\s+la", todo) || sinLas.contains("h") || mh.grupos[2] != nil || mh.grupos[3] != nil
            if todo.contains("mediodia") { hora = "12:00" }
            else if !conLas || !libre(a, b) || hay("\\d/|\\d\\s+de\\s+[a-z]", letras(p, a, b + 4)) { continue }
            else {
                guard var h = mh.grupos[1].flatMap({ Int($0) }) else { continue }
                let mi = mh.grupos[2].flatMap { Int($0) } ?? 0
                if let t = mh.grupos[3], hay("tarde|noche", t), h < 12 { h += 12 }
                // «a las 5» en una inmobiliaria es a la tarde: de 1 a 7 sin aclarar, se pasa a la tarde.
                if mh.grupos[3] == nil && h >= 1 && h <= 7 { h += 12 }
                if h > 23 || mi > 59 { continue }
                hora = String(format: "%02d:%02d", h, mi)
            }
            // El tramo del cuándo abarca día y hora si están pegados («sábado a las 11»).
            let recorte = String(todo.drop { $0.isWhitespace })
            let a2 = a + (todo.count - recorte.count)
            if let i = tramos.firstIndex(where: { $0.clase == .cuando }) {
                let entre = letras(p, tramos[i].hasta, a2)
                if entre.allSatisfy(\.isWhitespace) || a2 - tramos[i].hasta <= 1 { tramos[i].hasta = b }
                else { tramos.append(Tramo(desde: a2, hasta: b, clase: .cuando)) }
            } else { tramos.append(Tramo(desde: a2, hasta: b, clase: .cuando)) }
            break
        }

        // La propiedad: el título hasta la coma («Gorriti 5530»), o la calle sola si es una sola.
        var propiedad: Opcion?
        let props = propiedades.map { ($0, plano(String($0.titulo.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces))) }
        for (x, clave) in props.sorted(by: { $0.1.count > $1.1.count }) where clave.count >= 4 {
            if let r = p.range(of: clave) {
                let i = p.distance(from: p.startIndex, to: r.lowerBound)
                if libre(i, i + clave.count) {
                    propiedad = x
                    tramos.append(Tramo(desde: i, hasta: i + clave.count, clase: .prop))
                    break
                }
            }
        }
        if propiedad == nil {
            var calles: [String: [Opcion]] = [:]
            var orden: [String] = []
            for (x, clave) in props {
                let calle = clave.replacingOccurrences(of: "\\s*\\d.*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if calle.count >= 4 {
                    if calles[calle] == nil { orden.append(calle) }
                    calles[calle, default: []].append(x)
                }
            }
            for calle in orden {
                if let xs = calles[calle], xs.count == 1, let m = primera("\\b\(escapar(calle))\\b", p), libre(m.desde, m.desde + calle.count) {
                    propiedad = xs[0]
                    tramos.append(Tramo(desde: m.desde, hasta: m.desde + calle.count, clase: .prop))
                    break
                }
            }
        }

        // La persona: «con Inés Robledo», «a Inés», o el nombre en cualquier lado.
        let cs = contactos.map { ($0, plano($0.titulo)) }
        func buscarNombre(_ desde: Int) -> (Opcion, Int, Int)? {
            let resto = letras(p, desde, p.count)
            for (x, n) in cs.sorted(by: { $0.1.count > $1.1.count }) where !n.isEmpty {
                if let r = resto.range(of: n) {
                    let i = desde + resto.distance(from: resto.startIndex, to: r.lowerBound)
                    if libre(i, i + n.count) { return (x, i, n.count) }
                }
            }
            var primeros: [String: [Opcion]] = [:]
            var orden: [String] = []
            for (x, n) in cs {
                let pn = String(n.split(separator: " ").first ?? "")
                if pn.count >= 3 {
                    if primeros[pn] == nil { orden.append(pn) }
                    primeros[pn, default: []].append(x)
                }
            }
            for pn in orden {
                if let xs = primeros[pn], xs.count == 1, let m = primera("\\b\(escapar(pn))\\b", resto) {
                    let i = desde + m.desde
                    if libre(i, i + pn.count) { return (xs[0], i, pn.count) }
                }
            }
            return nil
        }
        var contacto: Opcion?
        let con = primera("\\b(con|a|al dueno de|para)\\s+", p)
        if let h = (con.flatMap { buscarNombre($0.hasta) }) ?? buscarNombre(0) {
            contacto = h.0
            tramos.append(Tramo(desde: h.1, hasta: h.1 + h.2, clase: .persona))
        }

        // Las partes para pintar.
        tramos.sort { $0.desde < $1.desde }
        var partes: [Parte] = []
        var i = 0
        for t in tramos {
            if t.desde > i { partes.append(Parte(t: letras(texto, i, t.desde), clase: nil)) }
            partes.append(Parte(t: letras(texto, t.desde, t.hasta), clase: t.clase))
            i = t.hasta
        }
        if i < texto.count { partes.append(Parte(t: letras(texto, i, texto.count), clase: nil)) }

        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return Entendido(tipo: tipo, propiedad: propiedad, contacto: contacto, dia: dia, hora: hora, duracionMin: duracion[tipo] ?? 30,
                         titulo: limpio.prefix(1).uppercased() + limpio.dropFirst(), partes: partes)
    }

    /// «2026-11-14» + «11:00» → el instante en Buenos Aires (siempre −03:00).
    static func instante(_ dia: String, _ hora: String) -> Date? { Fecha.iso("\(dia)T\(hora):00-03:00") }
}
