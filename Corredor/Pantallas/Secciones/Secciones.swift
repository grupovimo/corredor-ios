import SwiftUI

extension View {
    /// Los destinos de Secciones (ver Nucleo/Destinos.swift).
    func destinosSecciones() -> some View {
        self
            .navigationDestination(for: ASeccion.self) { _ in Pendiente(titulo: "Sección") }
    }
}
