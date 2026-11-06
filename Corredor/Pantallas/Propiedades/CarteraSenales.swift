import Foundation
import SwiftUI

// Lo que dice cada fila de la cartera (web: lib/propiedades/cartera.ts): la nota del precio, la
// columna de interesados, la línea de atención y el orden «por lo que necesita atención».

/// GET /v1/propiedades/resumen: las cuentas de las vistas de la cartera (sin las unidades de los
/// emprendimientos).
struct ResumenCartera: Codable, Equatable {
    struct Barrio: Codable, Equatable, Hashable { var barrio: String; var cantidad: Int }
    var total = 0
    var venta = 0
    var alquiler = 0
    var temporario = 0
    var conError = 0
    var sinPublicar = 0
    var sinVistas = 0
    var sinAgente = 0
    var mias = 0
    var destacadas = 0
    var borradores = 0
    var barrios: [Barrio] = []
}

/// Los cuatro lugares donde se publica, en el orden de la cartera (web: PORTALES).
enum PortalesCartera {
    static let todos: [(clave: String, sigla: String, nombre: String)] = [
        ("web", "W", "Tu web"), ("mercadolibre", "ML", "Mercado Libre"), ("zonaprop", "ZP", "Zonaprop"), ("argenprop", "AP", "Argenprop"),
    ]

    /// ok · err · off de cada portal, para las siglas de la fila.
    static func estado(_ p: Propiedad, _ s: Senal?, _ portal: String) -> String {
        if portal == "web" { return p.publicada == true ? "ok" : "off" }
        let e = s?.portales?[portal]
        return e == "publicada" ? "ok" : e == "error" ? "err" : "off"
    }
}

/// Las cuentas de días como la web (`diasEntre`): días de calendario de `a` a `b`, en la hora de Argentina.
func diasCalendario(_ a: Date, _ b: Date) -> Int {
    let c = Formato.calendario
    return c.dateComponents([.day], from: c.startOfDay(for: a), to: c.startOfDay(for: b)).day ?? 0
}

extension Senal {
    /// «hoy 17:30», «mañana 10:00», «13/11 18:00».
    static func cuando(_ f: Date, ahora: Date = Date()) -> String {
        let d = diasCalendario(ahora, f)
        if d == 0 { return "hoy \(Formato.horaDe(f))" }
        if d == 1 { return "mañana \(Formato.horaDe(f))" }
        let c = Formato.calendario.dateComponents([.day, .month], from: f)
        return String(format: "%02d/%02d ", c.day ?? 0, c.month ?? 0) + Formato.horaDe(f)
    }

    /// La reserva vence a las 12 del día `venceEl`.
    var venceReserva: Date? { reserva?.venceEl.flatMap { Fecha.dia($0) } }
}

enum Cartera {
    /// Lo que le falta a un borrador para publicarse.
    static func faltantes(_ p: Propiedad) -> [String] {
        var f: [String] = []
        if (p.fotos ?? []).isEmpty { f.append("fotos") }
        if p.superficie == nil, p.tipo != "lote" { f.append("superficie") }
        if (p.descripcion ?? "").isEmpty { f.append("descripción") }
        if p.precio == nil { f.append("precio") }
        return f
    }

    /// «fotos», «fotos y precio», «fotos, precio y descripción».
    static func lista(_ xs: [String]) -> String {
        xs.count < 2 ? (xs.first ?? "") : xs.dropLast().joined(separator: ", ") + " y " + (xs.last ?? "")
    }

    static func nombrePortal(_ k: String?) -> String { PublicacionPortal.nombres[k ?? ""] ?? (k ?? "un portal") }

    /// La nota debajo del precio: «Zonaprop la rechazó», «falta fotos y precio», «seña USD 5.000»…
    static func notaPrecio(_ p: Propiedad, _ s: Senal?, ahora: Date = Date()) -> (String, Tono) {
        if let e = s?.error { return ("\(nombrePortal(e.portal)) la rechazó", .rojo) }
        if p.esBorrador {
            let f = faltantes(p)
            return (f.isEmpty ? "lista para publicar" : "falta \(lista(Array(f.prefix(2))))", .oro)
        }
        if let sena = s?.reserva?.sena { return ("seña \(Formato.plata(sena, s?.reserva?.senaMoneda ?? "USD"))", .neutro) }
        if let antes = s?.precioAnterior, let ahoraP = p.precio, let cambio = s?.precioCambio, antes > ahoraP {
            let pct = Int(((antes - ahoraP) / antes * 100).rounded())
            let d = diasCalendario(cambio, ahora)
            return ("bajó \(pct)\(Formato.fino)% \(d < 1 ? "hoy" : "hace \(d) d")", .verde)
        }
        if p.operacion == "alquiler" {
            return (["por mes", p.expensas.map { "exp. \(Formato.numero(Int($0)))" }].compactMap { $0 }.joined(separator: " · "), .neutro)
        }
        return ("", .neutro)
    }

    /// La columna Interesados: «7 · visita hoy 17:30», «11 · 2 sin responder», «reserva vence mañana».
    static func interesados(_ s: Senal?, ahora: Date = Date()) -> (String, Bool) {
        guard let s else { return ("—", false) }
        if let v = s.venceReserva {
            let d = diasCalendario(ahora, v)
            return (d <= 0 ? "reserva vence hoy" : d == 1 ? "reserva vence mañana" : "reserva vence en \(d) días", d <= 1)
        }
        let n = s.interesados ?? 0
        if n == 0 { return (s.proximaVisita.map { "visita \(Senal.cuando($0, ahora: ahora))" } ?? "—", s.proximaVisita != nil) }
        var cola = ""
        var urgente = false
        if let v = s.proximaVisita {
            cola = "visita \(Senal.cuando(v, ahora: ahora))"
            urgente = diasCalendario(ahora, v) <= 1
        } else if let r = s.sinResponder, r > 0 {
            cola = "\(r) sin responder"
            urgente = true
        } else if let u = s.ultimaConsulta {
            let d = diasCalendario(u, ahora)
            cola = d == 0 ? "última hoy" : d == 1 ? "última ayer" : "última hace \(d) d"
        }
        return ([String(n), cola].filter { !$0.isEmpty }.joined(separator: " · "), urgente)
    }

    /// La línea de atención de la tarjeta (o nil si no hay nada que hacer).
    static func atencion(_ p: Propiedad, _ s: Senal?, ahora: Date = Date()) -> (String, Tono, String?)? {
        if let e = s?.error { return ("\(nombrePortal(e.portal)) la rechazó", .rojo, "exclamationmark.circle.fill") }
        if p.esBorrador {
            let f = faltantes(p)
            return (f.isEmpty ? "Borrador · lista para publicar" : "Borrador · faltan \(lista(Array(f.prefix(2))))", .oro, nil)
        }
        if let v = s?.proximaVisita, diasCalendario(ahora, v) <= 1 { return ("Visita \(Senal.cuando(v, ahora: ahora))", .oro, nil) }
        if let r = s?.sinResponder, r > 0 { return ("\(r) \(r == 1 ? "consulta" : "consultas") sin responder", .oro, nil) }
        if s?.venceReserva != nil {
            let t = interesados(s, ahora: ahora).0
            return (t.prefix(1).uppercased() + t.dropFirst(), .oro, nil)
        }
        if let n = s?.interesados, n > 0 { return ("\(n) \(n == 1 ? "interesado" : "interesados")", .neutro, nil) }
        return nil
    }

    /// Mientras más alto, más arriba: error, borrador, visita o reserva cerca, consultas sin responder.
    static func prioridad(_ p: Propiedad, _ s: Senal?, ahora: Date = Date()) -> Int {
        var n = 0
        if s?.error != nil { n += 100 }
        if p.esBorrador { n += 60 }
        if let v = s?.proximaVisita, diasCalendario(ahora, v) <= 1 { n += 50 }
        if let v = s?.venceReserva, diasCalendario(ahora, v) <= 2 { n += 45 }
        if let r = s?.sinResponder, r > 0 { n += 40 }
        if let i = s?.interesados, i > 0 { n += min(20, i * 2) }
        if p.estado == "vendida" || p.estado == "alquilada" { n -= 30 }
        return n
    }

    /// El estado de la cartera (web: estadoDe): Disponible, Borrador, Reservada, Vendida, Alquilada, Suspendida.
    static func estado(_ p: Propiedad) -> (String, Tono) {
        if p.esBorrador { return ("Borrador", .neutro) }
        switch p.estado ?? "disponible" {
        case "reservada": return ("Reservada", .oro)
        case "vendida": return ("Vendida", .neutro)
        case "alquilada": return ("Alquilada", .neutro)
        case "suspendida": return ("Suspendida", .neutro)
        default: return ("Disponible", .verde)
        }
    }
}

/// Los filtros de la cartera: lo que va tal cual a GET /v1/propiedades (como la URL de la web).
struct FiltrosCartera: Codable, Equatable, Hashable {
    var q = ""
    var operacion: [String] = []
    var tipo: [String] = []
    var estado: [String] = []
    var barrio: [String] = []
    /// Un id del equipo, «yo» (Mías) o «libre» (Sin agente).
    var agente: String?
    /// «no»: borradores (disponible y sin publicar).
    var publicada: String?
    /// «error»: con error en un portal.
    var portal: String?
    /// «30»: sin visitas hace 30 días.
    var sinVistas: String?
    var precioDesde: String?
    var precioHasta: String?
    var destacada = false

    var vacio: Bool { self == FiltrosCartera() }

    var query: [URLQueryItem] {
        var q: [URLQueryItem] = []
        func y(_ k: String, _ v: String?) { if let v, !v.isEmpty { q.append(URLQueryItem(name: k, value: v)) } }
        y("q", self.q.trimmingCharacters(in: .whitespaces))
        y("operacion", operacion.joined(separator: ","))
        y("tipo", tipo.joined(separator: ","))
        y("estado", estado.joined(separator: ","))
        y("barrio", barrio.joined(separator: ","))
        y("agente", agente)
        y("publicada", publicada)
        y("portal", portal)
        y("sinVistas", sinVistas)
        y("precioDesde", precioDesde)
        y("precioHasta", precioHasta)
        if destacada { y("destacada", "si") }
        return q
    }

    static func alternar(_ xs: inout [String], _ v: String) {
        if let i = xs.firstIndex(of: v) { xs.remove(at: i) } else { xs.append(v) }
    }
}

/// Una vista guardada de la cartera («Belgrano en venta»), en el aparato: la API no las guarda.
struct VistaGuardada: Codable, Equatable, Identifiable {
    var nombre: String
    var filtros: FiltrosCartera
    var id: String { nombre }

    static let clave = "corredor-cartera-vistas"

    static func todas() -> [VistaGuardada] {
        guard let d = UserDefaults.standard.data(forKey: clave) else { return [] }
        do { return try JSONDecoder().decode([VistaGuardada].self, from: d) } catch { return [] }
    }

    static func guardar(_ vs: [VistaGuardada]) {
        do { UserDefaults.standard.set(try JSONEncoder().encode(vs), forKey: clave) } catch {}
    }
}
