import SwiftUI

/// La raíz de la pestaña (se completa en esta carpeta).
struct PropiedadesRaiz: View {
    var body: some View { Pendiente(titulo: "Propiedades") }
}

extension View {
    /// Los destinos de Propiedades (ver Nucleo/Destinos.swift).
    func destinosPropiedades() -> some View {
        self
            .navigationDestination(for: AFichaPropiedad.self) { _ in Pendiente(titulo: "Ficha") }
            .navigationDestination(for: AGaleria.self) { _ in Pendiente(titulo: "Galería") }
            .navigationDestination(for: AAltaPropiedad.self) { _ in Pendiente(titulo: "Alta") }
    }
}
