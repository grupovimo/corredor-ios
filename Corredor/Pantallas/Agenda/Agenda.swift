import SwiftUI

/// La raíz de la pestaña (se completa en esta carpeta).
struct AgendaRaiz: View {
    var body: some View { Pendiente(titulo: "Agenda") }
}

extension View {
    /// Los destinos de Agenda (ver Nucleo/Destinos.swift).
    func destinosAgenda() -> some View {
        self
            .navigationDestination(for: AAgendaDia.self) { _ in Pendiente(titulo: "Agenda") }
            .navigationDestination(for: ACita.self) { _ in Pendiente(titulo: "Cita") }
    }
}
