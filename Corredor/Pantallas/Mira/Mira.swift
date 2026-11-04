import SwiftUI

/// La raíz de la pestaña (se completa en esta carpeta).
struct MiraRaiz: View {
    var body: some View { Pendiente(titulo: "Mira") }
}

extension View {
    /// Los destinos de Mira (ver Nucleo/Destinos.swift).
    func destinosMira() -> some View {
        self
            .navigationDestination(for: ACaptadas.self) { _ in Pendiente(titulo: "Captadas") }
    }
}
