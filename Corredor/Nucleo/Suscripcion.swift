import Foundation
import StoreKit

/// La suscripción de la inmobiliaria (GET /v1/suscripcion): tres planes (Agente, Inmobiliaria y Equipo),
/// mensual o anual (diez meses), 14 días gratis con el plan Inmobiliaria y sólo lectura al vencer. Los
/// topes (personas, propiedades activas, contratos, MIRA) los aplica la API: acá se muestran. En el iPhone se paga con el App Store (StoreKit 2); en la web, con
/// Mercado Pago. La API une las dos.
struct Suscripcion: Decodable, Equatable {
    struct Plan: Decodable, Equatable, Identifiable {
        var id: String
        var nombre: String
        var resumen: String
        var agentes: Int
        /// Lo que cuesta cada persona más (nil o 0: el plan no suma personas). No se compra en la tienda.
        var personaExtraMes: Double?
        /// Topes del plan (0: sin tope). Opcionales: una API vieja no los manda.
        var propiedades: Int?
        var contratos: Int?
        var mira: Int?
        var precioMes: Double
        var precioAnio: Double
        var incluye: [String]
        var destacado: Bool
        var appleMes: String
        var appleAnio: String

        func producto(_ ciclo: String) -> String { ciclo == "anio" ? appleAnio : appleMes }
        func precio(_ ciclo: String) -> Double { ciclo == "anio" ? precioAnio : precioMes }
    }

    struct Agentes: Decodable, Equatable {
        var usados: Int
        var cupo: Int?
    }

    /// Lo usado de un recurso con tope (tope nil: sin tope).
    struct Uso: Decodable, Equatable {
        var usados: Int
        var tope: Int?
    }

    struct Topes: Decodable, Equatable {
        var propiedades: Uso
        var contratos: Uso
        var mira: Uso
    }

    struct Cobro: Decodable, Equatable, Identifiable {
        var id: String
        var medio: String
        var detalle: String
        var importe: Double?
        var moneda: String?
        var creadoEn: Date
    }

    /// prueba | activa | baja | vencida
    var estado: String
    var plan: String?
    var ciclo: String
    var medio: String?
    var pruebaHasta: Date
    var pagadoHasta: Date?
    var vigenteHasta: Date
    var diasRestantes: Int
    var renueva: Bool
    var proximoCobro: Date?
    var importe: Double?
    var moneda: String?
    var esperando: String?
    var soloLectura: Bool
    var enPrueba: Bool
    /// Cuándo se borran los datos si no elige un plan (sólo vencida y con la purga prendida; si no, nil).
    var borraEn: Date?
    var agentes: Agentes
    /// El plan que rige hoy (en la prueba, Inmobiliaria) y lo usado de cada tope.
    var planVigente: String?
    var personasExtra: Int?
    var topes: Topes?
    var planes: [Plan]
    var mercadoPago: Bool
    var cobros: [Cobro]

    var planActual: Plan? { planes.first { $0.id == plan } }
    var planQueRige: Plan? { planes.first { $0.id == (planVigente ?? plan) } }

    /// Lo que pasa el tope si se elige `p`: personas, propiedades activas y contratos que quedan en sólo
    /// lectura (nada se borra).
    func deMas(_ p: Plan) -> (personas: Int, propiedades: Int, contratos: Int) {
        func de(_ u: Uso?, _ t: Int?) -> Int { guard let u, let t, t > 0 else { return 0 }; return max(0, u.usados - t) }
        let extras = (p.personaExtraMes ?? 0) > 0 ? (personasExtra ?? 0) : 0
        return (max(0, agentes.usados - p.agentes - extras), de(topes?.propiedades, p.propiedades), de(topes?.contratos, p.contratos))
    }

    /// «Prueba gratis · 9 días», «Plan Inmobiliaria · anual», «Sólo lectura».
    var nombreEstado: String {
        switch estado {
        case "prueba": return diasRestantes == 1 ? "Prueba gratis · último día" : "Prueba gratis · \(diasRestantes) días"
        case "activa": return "Plan \(planActual?.nombre ?? "") · \(ciclo == "anio" ? "anual" : "mensual")"
        case "baja": return "Plan \(planActual?.nombre ?? "") · sin renovar"
        default: return "Sólo lectura"
        }
    }

    /// Hay que avisarle arriba (Inicio, Más): la última semana de prueba, sin renovar o vencida.
    var pideAtencion: Bool {
        estado == "vencida" || (estado == "prueba" && diasRestantes <= 7) || (estado == "baja" && diasRestantes <= 7)
    }

    /// Se paga con Mercado Pago desde la web (no se puede cambiar desde el iPhone).
    var conMercadoPago: Bool { medio == "mercadopago" && renueva && !soloLectura }

    /// Se renueva con un medio que no es Apple (Mercado Pago, Google Play u otro): desde el iPhone no se
    /// compra, porque Apple cobraría y la API rechazaría la compra sin reintegro. Se administra ahí.
    var pagaAfuera: Bool { renueva && !soloLectura && medio.map { !$0.isEmpty && $0 != "apple" } == true }

    /// Con qué se paga, dicho como en la cabecera de «Tu plan».
    var comoSePaga: String {
        switch medio {
        case "apple": return "Se paga con el App Store, desde el iPhone."
        case "mercadopago": return "Se debita solo con Mercado Pago."
        case "google": return "Se paga con Google Play, desde Android."
        default: return "Se administra donde lo contrataste."
        }
    }
}

/// El App Store: los productos de los planes, la compra (con la inmobiliaria como appAccountToken) y las
/// transacciones que llegan solas (renovaciones, compras desde otro dispositivo, Ask to Buy). Cada una se
/// le manda firmada a la API y recién ahí se termina.
@MainActor @Observable
final class Tienda {
    static let compartida = Tienda()

    private(set) var productos: [String: Product] = [:]
    private(set) var cargando = false
    private var escuchando: Task<Void, Never>?
    /// Quién recibe las transacciones (la API de la sesión) y de qué inmobiliaria son.
    var api: Api?
    /// Sólo el dueño paga el plan: con otro rol, la API rechaza la compra (403) y la transacción quedaría
    /// sin terminar dando vueltas. Se pone al entrar a cada inmobiliaria.
    var esDuenio = false

    func cargar(_ ids: [String]) async {
        guard !ids.isEmpty, productos.isEmpty || !Set(ids).isSubset(of: Set(productos.keys)) else { return }
        cargando = true
        defer { cargando = false }
        if let ps = try? await Product.products(for: ids) {
            for p in ps { productos[p.id] = p }
        }
    }

    /// Escucha las transacciones que no vienen de una compra hecha acá (y las que quedaron sin terminar).
    func escuchar() {
        guard escuchando == nil, esDuenio else { return }
        escuchando = Task { [weak self] in
            for await r in Transaction.unfinished where self?.esDuenio == true { _ = try? await self?.procesar(r) }
            for await r in Transaction.updates where self?.esDuenio == true { _ = try? await self?.procesar(r) }
        }
    }

    /// `listo`: la API ya la registró; la suscripción se vuelve a pedir (GET /v1/suscripcion).
    enum Resultado { case listo, cancelada, pendiente }

    func comprar(_ producto: Product, inmobiliaria: String) async throws -> Resultado {
        var opciones: Set<Product.PurchaseOption> = []
        if let u = UUID(uuidString: inmobiliaria) { opciones.insert(.appAccountToken(u)) }
        switch try await producto.purchase(options: opciones) {
        case .success(let r):
            return try await procesar(r) ? .listo : .pendiente
        case .pending: return .pendiente
        case .userCancelled: return .cancelada
        @unknown default: return .cancelada
        }
    }

    /// «Restaurar compras»: vuelve a mandar a la API lo que el App Store tiene vigente. `true` si la API
    /// registró alguna (la suscripción se vuelve a pedir después).
    func restaurar() async throws -> Bool {
        try await AppStore.sync()
        var alguna = false
        for await r in Transaction.currentEntitlements {
            if (try? await procesar(r)) == true { alguna = true }
        }
        return alguna
    }

    /// Manda la transacción firmada a la API y, si la registró, la termina. Lo que devuelve la API no se
    /// lee acá: que no se entienda la respuesta no puede dejar la transacción sin terminar.
    @discardableResult
    private func procesar(_ r: VerificationResult<Transaction>) async throws -> Bool {
        guard case .verified(let t) = r else { return false }
        guard let api else { return false }
        struct Cuerpo: Encodable { var transaccion: String }
        _ = try await api.pedir("POST", "/v1/suscripcion/apple", cuerpo: Api.codificador.encode(Cuerpo(transaccion: r.jwsRepresentation)))
        await t.finish()
        return true
    }
}
