import SwiftUI

extension View {
    /// Los destinos del Inicio: búsqueda, avisos, su configuración y el perfil.
    func destinosInicio() -> some View {
        self
            .navigationDestination(for: ABuscar.self) { b in BuscarTodo(texto: b.texto) }
            .navigationDestination(for: AAvisos.self) { a in
                // Un aviso puntual (`/avisos?aviso=<id>&responder=<acción>`): arriba y con su hoja.
                let _ = a.aviso.map { Avisos.foco = ($0, a.responder) }
                Avisos()
            }
            .navigationDestination(for: AConfigAvisos.self) { _ in ConfigAvisos() }
            .navigationDestination(for: APerfil.self) { _ in MiPerfil() }
    }
}
