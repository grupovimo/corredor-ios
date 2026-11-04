import SwiftUI

extension View {
    /// Los destinos de Cartera (ver Nucleo/Destinos.swift).
    func destinosCartera() -> some View {
        self
            .navigationDestination(for: AContactos.self) { _ in Pendiente(titulo: "Contactos") }
            .navigationDestination(for: AFichaContacto.self) { _ in Pendiente(titulo: "Contacto") }
            .navigationDestination(for: AOperaciones.self) { _ in Pendiente(titulo: "Operaciones") }
            .navigationDestination(for: AFichaOperacion.self) { _ in Pendiente(titulo: "Operación") }
    }
}
