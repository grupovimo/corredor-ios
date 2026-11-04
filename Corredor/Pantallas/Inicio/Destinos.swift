import SwiftUI

extension View {
    /// Los destinos del Inicio: búsqueda, avisos, su configuración y el perfil.
    func destinosInicio() -> some View {
        self
            .navigationDestination(for: ABuscar.self) { b in Buscar(texto: b.texto) }
            .navigationDestination(for: AAvisos.self) { _ in Avisos() }
            .navigationDestination(for: AConfigAvisos.self) { _ in ConfigAvisos() }
            .navigationDestination(for: APerfil.self) { _ in Perfil() }
    }
}
