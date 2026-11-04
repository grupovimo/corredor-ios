import SwiftUI

extension View {
    /// Los destinos de Cobranzas (ver Nucleo/Destinos.swift).
    func destinosCobranzas() -> some View {
        self
            .navigationDestination(for: ACobranzas.self) { _ in Pendiente(titulo: "Cobranzas") }
            .navigationDestination(for: AContratos.self) { _ in Pendiente(titulo: "Contratos") }
            .navigationDestination(for: AFichaContrato.self) { _ in Pendiente(titulo: "Contrato") }
            .navigationDestination(for: ARecibo.self) { _ in Pendiente(titulo: "Recibo") }
            .navigationDestination(for: ARendicion.self) { _ in Pendiente(titulo: "Rendición") }
            .navigationDestination(for: AInventario.self) { _ in Pendiente(titulo: "Inventario") }
            .navigationDestination(for: AFirmas.self) { _ in Pendiente(titulo: "Firmas") }
    }
}
