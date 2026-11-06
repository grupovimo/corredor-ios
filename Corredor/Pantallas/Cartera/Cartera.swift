import Contacts
import ContactsUI
import SwiftUI

extension View {
    /// Los destinos de Contactos y Operaciones.
    func destinosCartera() -> some View {
        self
            .navigationDestination(for: AContactos.self) { _ in Contactos() }
            .navigationDestination(for: AFichaContacto.self) { c in FichaContacto(id: c.id) }
            .navigationDestination(for: AOperaciones.self) { _ in Operaciones() }
            .navigationDestination(for: AFichaOperacion.self) { o in FichaOperacion(id: o.id) }
    }
}

/// Un contacto (GET /v1/contactos, contactos.Contacto; la lista suma contactos.EnLista).
struct Contacto: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var telefono: String?
    var email: String?
    var tipo: String?
    var origen: String?
    var notas: String?
    var agenteId: String?
    var buscaOperacion: String?
    var buscaTipo: String?
    var buscaMoneda: String?
    var buscaDesde: Double?
    var buscaHasta: Double?
    var buscaAmbientes: Int?
    var buscaBarrios: [String]?
    /// Lo que pide además («Con balcón», «Apto crédito»): una lista, como los chips de la web.
    var buscaDetalles: [String]?
    var etiquetas: [String]?
    var creadoEn: Date?
    var actualizadoEn: Date?
    // De la lista (contactos.EnLista): lo último que pasó y lo pendiente.
    var actividadEn: Date?
    var esperaDesde: Date?
    var proximaCitaEn: Date?
    var proximaCitaTitulo: String?
    var propiedad: String?
    /// Meses de alquiler vencidos sin cobrar (AAAA-MM), del más viejo al más nuevo.
    var debe: [String]?

    static let tipos = [("comprador", "Comprador"), ("vendedor", "Vendedor"), ("inquilino", "Inquilino"), ("propietario", "Propietario"), ("garante", "Garante")]
    var tipoTexto: String { Contacto.tipos.first { $0.0 == tipo }?.1 ?? "Contacto" }

    /// Lo que busca, en chips: «3 ambientes», «Palermo o Belgrano», «USD 150 a 180 mil».
    var busca: [String] {
        var b: [String] = []
        if let o = buscaOperacion { b.append(o == "alquiler" ? "Alquilar" : o == "venta" ? "Comprar" : o.capitalized) }
        if let t = buscaTipo { b.append(Propiedad.tipos.first { $0.0 == t }?.1 ?? t) }
        if let a = buscaAmbientes { b.append("\(a) ambientes") }
        if let l = buscaBarrios, !l.isEmpty { b.append(l.count == 1 ? l[0] : l.dropLast().joined(separator: ", ") + " o " + l.last!) }
        let m = buscaMoneda ?? "USD"
        switch (buscaDesde, buscaHasta) {
        case let (d?, h?): b.append("\(m) \(Formato.numero(Int(d))) a \(Formato.numero(Int(h)))")
        case let (nil, h?): b.append("Hasta \(Formato.plata(h, m))")
        case let (d?, nil): b.append("Desde \(Formato.plata(d, m))")
        default: break
        }
        b += (buscaDetalles ?? []).compactMap(\.nonEmpty)
        return b
    }
}

/// Cómo se nombra a cada persona y cómo se resume lo que busca (web: lib/crm/contactos.ts y filas.ts).
enum TextosContacto {
    /// El rol, con formas que no marcan el género: «Persona interesada», «Parte inquilina».
    static func rol(_ tipo: String?) -> String {
        ["comprador": "Persona interesada", "vendedor": "Parte vendedora", "inquilino": "Parte inquilina",
         "propietario": "Parte propietaria", "garante": "Garante"][tipo ?? ""] ?? "Contacto"
    }

    /// Las listas del filtro, con sus tipos de la API.
    static let listas: [(clave: String, texto: String, tipos: [String])] = [
        ("", "Todos", []), ("interesados", "Interesados", ["comprador"]), ("propietarios", "Propietarios", ["propietario", "vendedor"]),
        ("inquilinos", "Inquilinos", ["inquilino"]), ("garantes", "Garantes", ["garante"]),
    ]

    /// Los tipos para elegir (alta y edición), como la web.
    static let tiposElegir: [(String, String)] = [("comprador", "Interesado"), ("propietario", "Propietario"), ("vendedor", "Vendedor"),
                                                  ("inquilino", "Inquilino"), ("garante", "Garante")]

    private static let tipoProp: [String: String] = ["departamento": "depto", "casa": "casa", "ph": "PH", "duplex": "dúplex", "local": "local",
                                                     "oficina": "oficina", "lote": "lote", "galpon": "galpón", "cochera": "cochera"]
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    private static func unir(_ xs: [String]) -> String { xs.count <= 1 ? xs.joined() : xs.dropLast().joined(separator: ", ") + " o " + xs.last! }

    private static func presupuesto(_ c: Contacto) -> String {
        let m = c.buscaMoneda ?? "USD"
        switch (c.buscaDesde, c.buscaHasta) {
        case let (d?, h?): return "de \(Formato.plata(d, m)) a \(Formato.numero(Int(h)))"
        case let (nil, h?): return "hasta \(Formato.plata(h, m))"
        case let (d?, nil): return "desde \(Formato.plata(d, m))"
        default: return ""
        }
    }

    /// «Comprar 3 ambientes en Belgrano o Núñez, hasta USD 180.000». Vacío si no cargaron nada.
    static func buscaLarga(_ c: Contacto) -> String {
        let verbo = c.buscaOperacion == "venta" ? "Comprar" : c.buscaOperacion == "alquiler" ? "Alquilar" : c.buscaOperacion == "temporario" ? "Alquilar por temporada" : ""
        let que = c.buscaAmbientes.map { "\($0) ambientes" } ?? c.buscaTipo.map { tipoProp[$0] ?? $0 } ?? ""
        let barrios = c.buscaBarrios ?? []
        let donde = barrios.isEmpty ? "" : "en \(unir(barrios))"
        let plata = presupuesto(c)
        let cuerpo = [verbo, que, donde].filter { !$0.isEmpty }.joined(separator: " ")
        if cuerpo.isEmpty && plata.isEmpty { return "" }
        let t = cuerpo.isEmpty ? plata : (plata.isEmpty ? cuerpo : "\(cuerpo), \(plata)")
        return Formato.mayuscula(t)
    }

    /// Corta, para una fila: «3 amb Belgrano hasta USD 180.000».
    static func buscaCorta(_ c: Contacto) -> String {
        var p: [String] = []
        if c.buscaOperacion == "alquiler" { p.append("Alquiler") }
        if c.buscaOperacion == "temporario" { p.append("Temporario") }
        if let a = c.buscaAmbientes { p.append("\(a) amb") } else if let t = c.buscaTipo { p.append(tipoProp[t] ?? t) }
        if let b = c.buscaBarrios, !b.isEmpty { p.append(b.prefix(2).joined(separator: " o ")) }
        let plata = presupuesto(c)
        if !plata.isEmpty { p.append(plata) }
        return p.joined(separator: " ")
    }

    /// «debe noviembre», «debe octubre y noviembre», «debe 3 meses»; nil si está al día.
    static func deuda(_ c: Contacto) -> String? {
        let xs = c.debe ?? []
        guard !xs.isEmpty else { return nil }
        let nombre = { (m: String) -> String in Int(m.dropFirst(5).prefix(2)).flatMap { $0 >= 1 && $0 <= 12 ? meses[$0 - 1] : nil } ?? m }
        if xs.count == 1 { return "debe \(nombre(xs[0]))" }
        if xs.count == 2 { return "debe \(nombre(xs[0])) y \(nombre(xs[1]))" }
        return "debe \(xs.count) meses"
    }

    /// «Mendoza 2350 · escribió por WhatsApp», «3 amb Belgrano hasta USD 180.000», «Llegó por Zonaprop».
    static func detalle(_ c: Contacto) -> String {
        let busca = buscaCorta(c)
        if let d = deuda(c) { return c.propiedad.map { "\($0) · \(d)" } ?? Formato.mayuscula(d) }
        if c.esperaDesde != nil { return c.propiedad.map { "\($0) · escribió por WhatsApp" } ?? "Escribió por WhatsApp" }
        if ["propietario", "vendedor", "inquilino"].contains(c.tipo ?? ""), let p = c.propiedad { return p }
        if !busca.isEmpty { return busca }
        if let p = c.propiedad { return p }
        return c.origen.map { "Llegó por \($0)" } ?? ""
    }

    /// El «cuándo»: si espera respuesta, hace cuánto (oro); si tiene algo hoy o mañana, eso (verde
    /// «visita 17:30»); si no, la última vez que pasó algo.
    static func cuando(_ c: Contacto, ahora: Date = Date()) -> (String, Tono?) {
        let cal = Formato.calendario
        if let e = c.esperaDesde { return (Formato.hace(e, ahora: ahora).replacingOccurrences(of: "hace ", with: ""), .oro) }
        if let p = c.proximaCitaEn {
            let visita = (c.proximaCitaTitulo ?? "").lowercased().hasPrefix("visita")
            if cal.isDate(p, inSameDayAs: ahora) { return ("\(visita ? "visita" : "hoy") \(Formato.horaDe(p))", .verde) }
            if let m = cal.date(byAdding: .day, value: 1, to: ahora), cal.isDate(p, inSameDayAs: m) { return ("mañana \(Formato.horaDe(p))", nil) }
        }
        guard let a = c.actividadEn ?? c.actualizadoEn ?? c.creadoEn else { return ("", nil) }
        if cal.isDate(a, inSameDayAs: ahora) { return ("hoy", nil) }
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: ahora)).day ?? 0
        if dias == 1 { return ("ayer", nil) }
        if dias > 1 && dias < 7 { return ("hace \(dias) d", nil) }
        return (Formato.hace(a, ahora: ahora), nil)
    }
}

struct NotaContacto: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var texto: String
    var ocurrioEn: Date
    var autorId: String?
}

/// Una propiedad que le puede interesar a un contacto (GET /v1/contactos/{id}/propiedades): las que
/// ya mira (con operación o visita) y las de la cartera que coinciden con lo que busca.
struct PropiedadDeContacto: Codable, Identifiable, Hashable {
    var propiedadId: String
    var titulo: String?
    var direccion: String?
    var barrio: String?
    var precio: Double?
    var moneda: String?
    var fotoId: String?
    /// La etapa de su operación (nuevo… cierre), «visita» si sólo tiene una visita, «nueva» si es una coincidencia.
    var estado: String?
    var visitaEn: Date?
    var operacionId: String?
    var puntaje: Double?
    var enviadaEn: Date?
    var reservaVenceEl: String?
    var id: String { propiedadId }

    var nombre: String { titulo?.nonEmpty ?? direccion ?? "Propiedad" }
    var precioTexto: String { precio.map { Formato.plata($0, moneda ?? "USD") } ?? "Consultar precio" }
    /// Lo que pasa con esa propiedad para la persona, como la web: «Visita hoy 17:30», «Reservó ·
    /// vence en 2 días», «Cerrando», «Nueva · no se la mandaste», «Ya la visitó», «En charla».
    var estadoTexto: (String, Tono?) {
        let cal = Formato.calendario
        if let v = visitaEn {
            let cuando = cal.isDateInToday(v) ? "hoy" : cal.isDateInTomorrow(v) ? "mañana" : Formato.dia(v)
            return ("Visita \(cuando) \(Formato.horaDe(v))", .verde)
        }
        switch estado {
        case "reserva": return (Operacion.venceSena(reservaVenceEl).map { "Reservó · \($0.0)" } ?? "Reservó", .oro)
        case "cierre": return ("Cerrando", .verde)
        case "nueva", nil: return (enviadaEn.map { "Se la mandaste \(Formato.hace($0))" } ?? "Nueva · no se la mandaste", nil)
        case "visita": return ("Ya la visitó", nil)
        default: return ("En charla", nil)
        }
    }
    /// La miniatura: las fotos de las propiedades son públicas (/publico/archivos/{inmobiliaria}/{id}).
    func miniatura(_ api: URL, inmobiliaria: String?) -> URL? {
        guard let fotoId, let inmobiliaria else { return nil }
        return URL(string: api.appendingPathComponent("/publico/archivos/\(inmobiliaria)/\(fotoId)").absoluteString + "?tam=chica")
    }
}

/// La agenda del iPhone para elegir un contacto.
struct SelectorAgenda: UIViewControllerRepresentable {
    var alElegir: (CNContact) -> Void
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let c = CNContactPickerViewController()
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(alElegir) }
    final class Coordinador: NSObject, CNContactPickerDelegate {
        let alElegir: (CNContact) -> Void
        init(_ a: @escaping (CNContact) -> Void) { alElegir = a }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { alElegir(contact) }
    }
}

/// La agenda del iPhone para elegir varios contactos de una vez («Importar del celular»).
struct SelectorAgendaVarios: UIViewControllerRepresentable {
    var alElegir: ([CNContact]) -> Void
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let c = CNContactPickerViewController()
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(alElegir) }
    final class Coordinador: NSObject, CNContactPickerDelegate {
        let alElegir: ([CNContact]) -> Void
        init(_ a: @escaping ([CNContact]) -> Void) { alElegir = a }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { alElegir(contacts) }
    }
}

// MARK: - 9 Operaciones

/// Una operación del tablero (operaciones.Operacion).
struct Operacion: Codable, Identifiable, Hashable {
    /// Un paso tildado de la lista del cierre: cuándo y quién.
    struct Tildado: Codable, Hashable { var en: Date?; var por: String? }
    /// Una cita de la operación (la próxima o la última).
    struct CitaOp: Codable, Hashable { var tipo: String?; var titulo: String?; var empiezaEn: Date?; var estado: String? }
    /// La reserva formal de la propiedad hecha desde la operación.
    struct Reserva: Codable, Hashable { var id: String?; var venceEl: String?; var recibo: String? }
    /// Un paso de «Para pasar a Cierre», con el texto que le pone el panel.
    struct Paso: Hashable {
        var clave: String; var texto: String; var hecho: Bool; var auto = false; var detalle: String? = nil
        /// «Llamar a Jorge» en la aceptación del propietario.
        var llamar: (texto: String, telefono: String)? = nil
        static func == (a: Paso, b: Paso) -> Bool { a.clave == b.clave && a.hecho == b.hecho && a.texto == b.texto && a.detalle == b.detalle }
        func hash(into h: inout Hasher) { h.combine(clave); h.combine(hecho) }
    }
    var id: String
    var titulo: String?
    var etapa: String
    var valor: Double?
    var moneda: String?
    var contactoId: String?
    var propiedadId: String?
    var agenteId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var agenteNombre: String?
    var creadaEn: Date?
    var actualizadoEn: Date?
    var orden: Double?
    var sena: Double?
    var senaMoneda: String?
    var senaVenceEl: String?
    var caidaEn: Date?
    var caidaMotivo: String?
    var honorariosComprador: Double?
    var honorariosVendedor: Double?
    var comisionAgente: Double?
    /// Lo tildado para el cierre: clave del paso (dominio, credito, aceptacion, boleto, garantia,
    /// documentacion, firma) → cuándo y quién.
    var checklist: [String: Tildado]?
    /// Los ids de los archivos adjuntos (GET /v1/archivos/{id} da el nombre).
    var adjuntos: [String]?
    var propiedadOperacion: String?
    var propiedadBarrio: String?
    var propiedadPrecio: Double?
    var propiedadMoneda: String?
    var propiedadFotoId: String?
    var contactoTelefono: String?
    var senaRecibo: String?
    var propietarioId: String?
    var propietarioNombre: String?
    var propietarioTelefono: String?
    var proximaCita: CitaOp?
    var ultimaCita: CitaOp?
    var reserva: Reserva?

    static let etapas = [("nuevo", "Nuevo"), ("contactado", "Contactado"), ("visita", "Visita"), ("reserva", "Reserva"), ("cierre", "Cierre")]
    static func etapaTexto(_ e: String) -> String { etapas.first { $0.0 == e }?.1 ?? e.capitalized }
    var siguiente: String? { Operacion.etapas.firstIndex { $0.0 == etapa }.flatMap { $0 + 1 < Operacion.etapas.count ? Operacion.etapas[$0 + 1].0 : nil } }

    /// Las cuatro columnas del tablero de la web: «Nueva» junta nuevo y contactado.
    static let columnas: [(clave: String, texto: String, etapas: [String], tono: Tono)] = [
        ("nuevo", "Nueva", ["nuevo", "contactado"], .azul), ("visita", "Visita", ["visita"], .verde),
        ("reserva", "Reserva", ["reserva"], .oro), ("cierre", "Cierre", ["cierre"], .neutro),
    ]
    static func columna(_ etapa: String) -> Int { max(0, columnas.firstIndex { $0.etapas.contains(etapa) } ?? 0) }
    static func textoColumna(_ etapa: String) -> String { columnas[columna(etapa)].texto }
    /// Los motivos de «Se cayó».
    static let motivos = ["Precio", "Eligió otra", "No le dieron el crédito", "Dejó de responder", "El dueño la bajó"]

    var nombre: String { propiedadTitulo ?? titulo ?? "Operación" }
    /// «Venta · Belgrano».
    var tipoTexto: String {
        [["venta": "Venta", "alquiler": "Alquiler", "temporario": "Temporario"][propiedadOperacion ?? ""], propiedadBarrio].compactMap { $0 }.joined(separator: " · ")
    }

    /// Cuándo vence la reserva: «vence en 7 días», «vence mañana», «vence hoy», «venció» (con alerta desde el día anterior).
    static func venceSena(_ f: String?, ahora: Date = Date()) -> (String, Bool)? {
        guard let f, let d = Fecha.dia(f) else { return nil }
        let cal = Formato.calendario
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: ahora), to: cal.startOfDay(for: d)).day ?? 0
        if n < 0 { return ("venció", true) }
        if n == 0 { return ("vence hoy", true) }
        if n == 1 { return ("vence mañana", true) }
        return ("vence en \(n) días", false)
    }

    /// La nota de la tarjeta: lo próximo agendado, la seña, lo último que pasó o hace cuánto que entró.
    /// El Bool es la alerta (va en oro).
    func nota(_ ahora: Date = Date()) -> (String, Bool) {
        let cal = Formato.calendario
        let citas = ["visita": "visita", "firma": "firma", "tasacion": "tasación", "llamado": "llamado", "otro": ""]
        if let p = proximaCita, let en = p.empiezaEn {
            let que = (citas[p.tipo ?? ""] ?? "").nonEmpty ?? "agenda"
            if cal.isDate(en, inSameDayAs: ahora) { return ("\(que) hoy \(Formato.horaDe(en))", true) }
            if let m = cal.date(byAdding: .day, value: 1, to: ahora), cal.isDate(en, inSameDayAs: m) { return ("\(que) mañana \(Formato.horaDe(en))", false) }
        }
        if etapa == "reserva" {
            let vence = Operacion.venceSena(reserva?.venceEl ?? senaVenceEl, ahora: ahora)
            if let s = sena { return ("seña \(Formato.plata(s, senaMoneda ?? moneda ?? "USD"))\(vence.map { " · \($0.0)" } ?? "")", vence?.1 ?? false) }
            return ("seña pendiente", true)
        }
        if let u = ultimaCita, u.tipo == "visita", let en = u.empiezaEn, cal.isDate(en, inSameDayAs: ahora) { return ("visitó hoy", false) }
        if let p = proximaCita, let en = p.empiezaEn { return ("\((citas[p.tipo ?? ""] ?? "").nonEmpty ?? "agenda") \(Formato.hace(en))", false) }
        if etapa == "nuevo" || etapa == "contactado", let c = creadaEn {
            if ahora.timeIntervalSince(c) < 86_400 { return ("entró \(Formato.hace(c))", etapa == "nuevo") }
            if etapa == "contactado" { return ("contactado", false) }
        }
        return ("sin movimiento \(actualizadoEn.map { Formato.hace($0) } ?? "")", false)
    }

    /// «Para pasar a Cierre» según sea venta o alquiler (los mismos pasos y textos que el panel,
    /// lib/crm/etapas.ts). La seña se tilda sola al cargarla; lo demás, a mano.
    func pasosCierre(etiquetas etiquetasContacto: [String]) -> [Paso] {
        let hecho = { (k: String) in checklist?[k] != nil }
        let banco = etiquetasContacto.first { $0.range(of: "banco", options: .caseInsensitive) != nil }?
            .replacingOccurrences(of: "^pre-?aprobad[oa]\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        let recibo = reserva?.recibo ?? senaRecibo
        let sena = Paso(clave: "sena", texto: self.sena.map { "Seña \(Formato.plata($0, senaMoneda ?? moneda ?? "USD")) recibida" } ?? "Seña recibida",
                        hecho: self.sena != nil, auto: true, detalle: self.sena != nil ? recibo.map { "recibo \($0)" } : nil)
        let tel = propietarioTelefono?.filter { $0.isNumber || $0 == "+" }
        let dueno = propietarioNombre.map { Charla.primerNombre($0) }
        var aceptacion = Paso(clave: "aceptacion", texto: "Aceptación del propietario", hecho: hecho("aceptacion"))
        if let tel, !tel.isEmpty { aceptacion.llamar = (dueno.map { "Llamar a \($0)" } ?? "Llamar al dueño", tel) }
        var l: [Paso] = propiedadOperacion == "alquiler" || propiedadOperacion == "temporario"
            ? [sena, Paso(clave: "garantia", texto: "Garantía aprobada", hecho: hecho("garantia")),
               Paso(clave: "documentacion", texto: "Documentación del inquilino", hecho: hecho("documentacion")), aceptacion,
               Paso(clave: "firma", texto: "Fecha de firma del contrato", hecho: hecho("firma"))]
            : [sena, Paso(clave: "dominio", texto: "Informe de dominio", hecho: hecho("dominio")),
               Paso(clave: "credito", texto: banco.map { "Pre-aprobación del crédito (\($0))" } ?? "Pre-aprobación del crédito", hecho: hecho("credito")), aceptacion,
               Paso(clave: "boleto", texto: "Fecha de boleto y escribana", hecho: hecho("boleto"))]
        if !l[l.count - 1].hecho && !aceptacion.hecho { l[l.count - 1].detalle = "después de la aceptación" }
        return l
    }

    /// Para el código que ya usaba `pasos` sin las etiquetas del contacto.
    var pasos: [Paso] { pasosCierre(etiquetas: []) }

    /// Lo que suma en dólares (los alquileres en pesos no entran en el «en juego»).
    static func enJuego(_ ops: [Operacion]) -> Double { ops.filter { ($0.moneda ?? "USD") == "USD" }.reduce(0) { $0 + ($1.valor ?? 0) } }
}

/// Un evento del historial de una operación (GET /v1/operaciones/{id}/historial).
struct EventoOperacion: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String
    var texto: String?
    var datos: JSONLibre?
    var autorId: String?
    var autorNombre: String?
    var creadoEn: Date

    private func dato(_ k: String) -> String? {
        switch datos?[k] {
        case .texto(let s)?: return s
        case .numero(let n)?: return String(n)
        default: return nil
        }
    }

    /// Lo que se lee, como en el panel: «Pasó a Visita · Sofía», «La lleva Sofía», «Se cayó · Precio».
    func frase(nombres: [String: String]) -> String {
        let quien = autorNombre.map { " · \(Charla.primerNombre($0))" } ?? ""
        switch tipo {
        case "alta": return "Entró en \(Operacion.textoColumna(dato("etapa") ?? "nuevo"))"
        case "etapa": return "Pasó a \(Operacion.textoColumna(dato("hasta") ?? ""))\(quien)"
        case "nota": return (texto ?? "") + quien
        case "asignacion":
            guard let h = dato("hasta") else { return "Quedó sin agente" }
            return "La lleva \(nombres[h].map { Charla.primerNombre($0) } ?? "otra persona")"
        case "caida": return "Se cayó · \(dato("motivo") ?? "")"
        case "reabierta": return "Volvió al tablero"
        case "sena":
            if case .numero(let n)? = datos?["monto"] { return "Dejó seña de \(Formato.plata(n, dato("moneda") ?? "USD"))" }
            return "Dejó seña"
        default: return texto ?? tipo
        }
    }

    var descripcion: String { frase(nombres: [:]) }
}

/// El texto antes del ícono («Pasar a boleto →»).
struct TextoDespues: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

/// La foto de una propiedad por su id (las fotos son públicas: /publico/archivos/{inmobiliaria}/{id}).
func urlFotoPropiedad(_ fotoId: String?, api: URL, inmobiliaria: String?) -> URL? {
    guard let fotoId, let inmobiliaria else { return nil }
    return URL(string: api.appendingPathComponent("/publico/archivos/\(inmobiliaria)/\(fotoId)").absoluteString + "?tam=chica")
}
