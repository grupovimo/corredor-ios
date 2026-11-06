import Foundation
import Observation
import QuickLook
import SwiftUI

// Lo que la bandeja arma con los datos de la ficha y con lo que escribió el cliente, igual que la
// web (lib/mensajes/modelo.ts): las respuestas sugeridas, el día que propone para la visita, los
// turnos libres del agente, las plantillas con sus datos y las respuestas guardadas con «/».

enum Charla {
    static func primerNombre(_ n: String?) -> String {
        (n ?? "").trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
    }

    private static let dias = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    /// «sáb 14 · 11:00» (en la hora de Buenos Aires).
    static func diaHora(_ d: Date) -> String {
        let c = Formato.calendario.dateComponents([.weekday, .day, .hour, .minute], from: d)
        let h = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return "\(dias[(c.weekday ?? 1) - 1]) \(c.day ?? 0) · \(h)"
    }

    /// Un instante a partir del día de `base` y la hora en Buenos Aires.
    private static func a(_ base: Date, hora: Int, minuto: Int) -> Date? {
        var c = Formato.calendario.dateComponents([.year, .month, .day], from: base)
        c.hour = hora
        c.minute = minuto
        return Formato.calendario.date(from: c)
    }

    private static func coincide(_ patron: String, _ t: String) -> Bool {
        t.range(of: patron, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// El día y la hora que propone el cliente («¿Puede ser el sábado a las 11?», «mañana 17:30», «el
    /// jueves 5 de la tarde»): siempre en el futuro, o nil si no dice día y hora.
    static func fechaPropuesta(_ texto: String, ahora: Date = Date()) -> Date? {
        let t = texto.lowercased()
        let cal = Formato.calendario
        let hoySem = cal.component(.weekday, from: ahora) - 1
        var suma: Int?
        if coincide(#"\bpasado mañana\b"#, t) { suma = 2 }
        else if coincide(#"(?<!de la )(?<!por la )\bmañana\b"#, t) { suma = 1 }
        else if coincide(#"\bhoy\b"#, t) { suma = 0 }
        else {
            let nombres: [(String, Int)] = [(#"\bdomingo\b"#, 0), (#"\blunes\b"#, 1), (#"\bmartes\b"#, 2), (#"\bmi[eé]rcoles\b"#, 3),
                                            (#"\bjueves\b"#, 4), (#"\bviernes\b"#, 5), (#"\bs[aá]bado\b|\bs[aá]b\b"#, 6)]
            for (re, d) in nombres where coincide(re, t) {
                let s = (d - hoySem + 7) % 7
                suma = s == 0 ? 7 : s
                break
            }
        }
        guard let suma else { return nil }
        let patron = #"(?:a las|tipo|las|a la)\s*(\d{1,2})(?:[:.](\d{2}))?|\b(\d{1,2})[:.](\d{2})\b|\b(\d{1,2})\s*(?:hs|h)\b|\b(\d{1,2})\s*de la (?:tarde|mañana|noche)"#
        guard let re = try? NSRegularExpression(pattern: patron),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func grupo(_ i: Int) -> Int? {
            guard let r = Range(m.range(at: i), in: t) else { return nil }
            return Int(t[r])
        }
        guard var hora = grupo(1) ?? grupo(3) ?? grupo(5) ?? grupo(6) else { return nil }
        let minuto = grupo(2) ?? grupo(4) ?? 0
        if hora > 23 || minuto > 59 { return nil }
        if coincide("de la tarde|de la noche", t) && hora < 12 { hora += 12 }
        else if hora >= 1 && hora <= 7 && !coincide("de la mañana", t) { hora += 12 } // «a las 5» es a la tarde
        guard let base = cal.date(byAdding: .day, value: suma, to: ahora), let f = a(base, hora: hora, minuto: minuto) else { return nil }
        return f > ahora ? f : nil
    }

    /// Los próximos turnos libres del agente para una visita («Martín tiene libre»): de lunes a viernes
    /// a las 11, 16 y 17; los sábados a las 10, 11 y 12; sin pisar su agenda y con 2 h de aviso.
    static func turnosLibres(_ ocupado: [Cita], ahora: Date = Date(), cuantos: Int = 3) -> [Date] {
        let cal = Formato.calendario
        var out: [Date] = []
        for d in 0..<10 where out.count < cuantos {
            guard let dia = cal.date(byAdding: .day, value: d, to: ahora) else { continue }
            let sem = cal.component(.weekday, from: dia) - 1
            if sem == 0 { continue }
            for h in sem == 6 ? [10, 11, 12] : [11, 16, 17] {
                guard let ini = a(dia, hora: h, minuto: 0) else { continue }
                if ini < ahora.addingTimeInterval(2 * 3600) { continue }
                let fin = ini.addingTimeInterval(3600)
                let pisa = ocupado.contains { $0.empiezaEn < fin && $0.terminaEn > ini }
                if !pisa { out.append(ini) }
                if out.count >= cuantos { break }
            }
        }
        return out
    }

    /// «Proponer visita»: «Valeria, ¿te queda bien el vie 13 a las 16:00 o el sáb 14 a las 11:00 para verlo?».
    static func textoPropuesta(_ nombre: String, _ turnos: [Date]) -> String? {
        guard !turnos.isEmpty else { return nil }
        let t = turnos.prefix(2).map { d -> String in
            let p = diaHora(d).components(separatedBy: " · ")
            return "el \(p[0]) a las \(p.count > 1 ? p[1] : "")"
        }
        return "\(nombre.isEmpty ? "¿" : "\(nombre), ¿")te queda bien \(t.joined(separator: " o ")) para verlo?"
    }

    /// «USD 172.000 · 3 amb · 74 m²».
    static func resumenFicha(_ p: Propiedad) -> String {
        [p.precio.flatMap { p.precioOculto == true ? nil : Formato.plata($0, p.moneda ?? "USD") },
         p.ambientes.flatMap { $0 > 0 ? "\($0) amb" : nil },
         p.superficie.flatMap { $0 > 0 ? "\(Formato.numero(Int($0))) m²" : nil }].compactMap { $0 }.joined(separator: " · ")
    }

    /// «Sigue disponible + precio»: sólo con lo cargado en la ficha y si está disponible.
    static func sugerenciaDisponible(_ nombre: String, _ p: Propiedad) -> String? {
        guard (p.estado ?? "disponible") == "disponible" else { return nil }
        let datos = [p.ambientes.flatMap { $0 > 0 ? "\($0) amb" : nil }, p.superficie.flatMap { $0 > 0 ? "\(Formato.numero(Int($0))) m²" : nil }].compactMap { $0 }
        var precio = p.precio.flatMap { p.precioOculto == true || $0 == 0 ? nil : Formato.plata($0, p.moneda ?? "USD") } ?? ""
        if !precio.isEmpty, let e = p.expensas, e > 0 { precio += " con expensas de \(Formato.plata(e, "ARS"))" }
        let partes = (datos + [precio]).filter { !$0.isEmpty }.joined(separator: ", ")
        let hola = nombre.isEmpty ? "¡Hola! Sí, sigue" : "Hola \(nombre), ¡sí! Sigue"
        return "\(hola) disponible\(partes.isEmpty ? "" : ": " + partes). ¿Querés verlo esta semana?"
    }

    /// «Mandar la ficha»: el link público de la propiedad en la web de la inmobiliaria.
    static func textoFicha(_ nombre: String, _ p: Propiedad, web: String?) -> String? {
        guard let web = web?.nonEmpty else { return nil }
        let link = "\(web)/propiedades/\(p.slug?.nonEmpty ?? p.numero.map(String.init) ?? p.id)"
        return "\(nombre.isEmpty ? "" : "Hola \(nombre), ")te paso la ficha de \(p.nombre): \(link)"
    }

    /// El texto de una plantilla con sus datos puestos ({{1}}, {{2}}…).
    static func completar(_ cuerpo: String, _ ps: [String]) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\{\{(\d+)\}\}"#) else { return cuerpo }
        var out = cuerpo
        for m in re.matches(in: cuerpo, range: NSRange(cuerpo.startIndex..., in: cuerpo)).reversed() {
            guard let r = Range(m.range, in: cuerpo), let rn = Range(m.range(at: 1), in: cuerpo), let n = Int(cuerpo[rn]) else { continue }
            let v = n >= 1 && n <= ps.count ? ps[n - 1] : ""
            if !v.isEmpty, let ro = Range(m.range, in: out) { out.replaceSubrange(ro, with: v) }
            _ = r
        }
        return out
    }

    private static func normal(_ x: String) -> String { x.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

    /// Las respuestas guardadas que coinciden con lo escrito después de la «/» (título o texto, sin acentos).
    static func filtrar(_ rs: [RespuestaGuardada], _ q: String) -> [RespuestaGuardada] {
        let b = normal(q.trimmingCharacters(in: .whitespaces))
        guard !b.isEmpty else { return rs }
        return rs.filter { normal($0.titulo).contains(b) || normal($0.texto).contains(b) }
    }

    /// El texto de una respuesta guardada con {nombre} cambiado por el primer nombre del contacto.
    static func completarRespuesta(_ texto: String, _ nombre: String) -> String {
        var t = texto.replacingOccurrences(of: #"\s*\{nombre\}"#, with: nombre.isEmpty ? "" : " " + nombre, options: .regularExpression)
        while t.first?.isWhitespace == true { t.removeFirst() }
        return t
    }

    /// «retomar_consulta» → «Retomar consulta».
    static func nombrePlantilla(_ n: String) -> String {
        let t = n.replacingOccurrences(of: "_", with: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// El diseño dice «Interesada»: el género sale del nombre y, si no se sabe, «Interesado».
    static func esElla(_ n: String) -> Bool {
        let ellas: Set<String> = ["rocío", "belén", "inés", "abril", "raquel", "isabel", "pilar", "luz", "sol", "mercedes", "dolores", "carmen", "ruth", "noemí", "ivonne"]
        return n.lowercased().hasSuffix("a") || ellas.contains(n.lowercased())
    }

    /// «Interesada · llegó por Zonaprop · sin dueño».
    static func subtitulo(tipo: String?, origen: String?, primero: String, sinDueno: Bool) -> String {
        var quien: String?
        if tipo == "comprador" || tipo == "inquilino" { quien = esElla(primero) ? "Interesada" : "Interesado" }
        else if let t = tipo?.nonEmpty { quien = t.prefix(1).uppercased() + t.dropFirst() }
        let llego = origen?.nonEmpty.map { "llegó por \($0 == "web" ? "la web" : $0.prefix(1).uppercased() + $0.dropFirst())" }
        return [quien, llego, sinDueno ? "sin dueño" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Estado {
    /// El aviso de error con «Reintentar» (como el de la web): dura 6 s.
    func avisarReintentar(_ texto: String, _ reintentar: @escaping () -> Void) {
        let a = Aviso(texto: texto, ok: false, accion: ("Reintentar", reintentar))
        aviso = a
        Task {
            try? await Task.sleep(for: .seconds(6))
            if aviso?.id == a.id { aviso = nil }
        }
    }

    /// El texto de un error de la API, para el aviso o la hoja.
    static func texto(_ e: Error, si otro: String = "Algo salió mal. Probá de nuevo.") -> String {
        if let e = e as? ErrorApi { return e.detalle.isEmpty ? e.titulo : e.detalle }
        return otro
    }
}

// MARK: - Archivos con la sesión

/// Lo bajado de /v1/archivos/{id}/contenido (necesita la sesión: AsyncImage no la manda).
@MainActor
enum ArchivosSesion {
    private static var cache: [String: Data] = [:]

    static func datos(_ id: String, api: Api) async throws -> Data {
        if let d = cache[id] { return d }
        let d = try await api.pedir("GET", "/v1/archivos/\(id)/contenido")
        if d.count < 8_000_000 { cache[id] = d }
        return d
    }

    /// Lo deja en un archivo temporal con su nombre, para la vista previa (compartir, imprimir).
    static func archivo(_ id: String, nombre: String, api: Api) async throws -> URL {
        let d = try await datos(id, api: api)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(nombre)
        try d.write(to: u)
        return u
    }
}

/// Una foto de /v1/archivos con la sesión de la app.
struct ImagenArchivo: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var imagen: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let imagen { Image(uiImage: imagen).resizable().scaledToFill() } else { C.hundida }
            }
            .clipped()
            .task(id: id) {
                if let d = try? await ArchivosSesion.datos(id, api: estado.api) { imagen = UIImage(data: d) }
            }
    }
}
