import Foundation
import StoreKit

/// La suscripción de la inmobiliaria (GET /v1/suscripcion): tres planes, mensual o anual, 14 días
/// gratis y sólo lectura al vencer. En el iPhone se paga con el App Store (StoreKit 2); en la web, con
/// Mercado Pago. La API une las dos.
struct Suscripcion: Decodable, Equatable {
    struct Plan: Decodable, Equatable, Identifiable {
        var id: String
        var nombre: String
        var resumen: String
        var agentes: Int
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
    var agentes: Agentes
    var planes: [Plan]
    var mercadoPago: Bool
    var cobros: [Cobro]

    var planActual: Plan? { planes.first { $0.id == plan } }

    /// «Prueba gratis · 9 días», «Plan Profesional · anual», «Sólo lectura».
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
        guard escuchando == nil else { return }
        escuchando = Task { [weak self] in
            for await r in Transaction.unfinished { _ = try? await self?.procesar(r) }
            for await r in Transaction.updates { _ = try? await self?.procesar(r) }
        }
    }

    enum Resultado { case listo(Suscripcion), cancelada, pendiente }

    func comprar(_ producto: Product, inmobiliaria: String) async throws -> Resultado {
        var opciones: Set<Product.PurchaseOption> = []
        if let u = UUID(uuidString: inmobiliaria) { opciones.insert(.appAccountToken(u)) }
        switch try await producto.purchase(options: opciones) {
        case .success(let r):
            guard let s = try await procesar(r) else { return .pendiente }
            return .listo(s)
        case .pending: return .pendiente
        case .userCancelled: return .cancelada
        @unknown default: return .cancelada
        }
    }

    /// «Restaurar compras»: vuelve a mandar a la API lo que el App Store tiene vigente.
    func restaurar() async throws -> Suscripcion? {
        try await AppStore.sync()
        var ultima: Suscripcion?
        for await r in Transaction.currentEntitlements {
            if let s = try? await procesar(r) { ultima = s }
        }
        return ultima
    }

    @discardableResult
    private func procesar(_ r: VerificationResult<Transaction>) async throws -> Suscripcion? {
        guard case .verified(let t) = r else { return nil }
        guard let api else { return nil }
        struct Cuerpo: Encodable { var transaccion: String }
        let s: Suscripcion = try await api.enviar("POST", "/v1/suscripcion/apple", Cuerpo(transaccion: r.jwsRepresentation))
        await t.finish()
        return s
    }
}
