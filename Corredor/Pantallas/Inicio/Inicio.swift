import SwiftUI

/// La raíz de la pestaña (se completa en esta carpeta).
struct InicioRaiz: View {
    var body: some View { Pendiente(titulo: "Inicio") }
}

extension View {
    /// Los destinos de Inicio (ver Nucleo/Destinos.swift).
    func destinosInicio() -> some View {
        self
            .navigationDestination(for: ABuscar.self) { _ in Pendiente(titulo: "Buscar") }
            .navigationDestination(for: AAvisos.self) { _ in Pendiente(titulo: "Avisos") }
            .navigationDestination(for: AConfigAvisos.self) { _ in Pendiente(titulo: "Configurar avisos") }
            .navigationDestination(for: APerfil.self) { _ in Pendiente(titulo: "Perfil") }
    }
}
