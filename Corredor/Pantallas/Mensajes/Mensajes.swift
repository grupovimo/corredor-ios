import SwiftUI

/// La raíz de la pestaña (se completa en esta carpeta).
struct MensajesRaiz: View {
    var body: some View { Pendiente(titulo: "Mensajes") }
}

extension View {
    /// Los destinos de Mensajes (ver Nucleo/Destinos.swift).
    func destinosMensajes() -> some View {
        self
            .navigationDestination(for: AChat.self) { _ in Pendiente(titulo: "Chat") }
            .navigationDestination(for: APreguntaML.self) { _ in Pendiente(titulo: "Mercado Libre") }
    }
}
