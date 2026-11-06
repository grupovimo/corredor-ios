import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Reservas

/// Las reservas de venta y alquiler abiertas: la seña, hasta cuándo vale, y cerrarla (concretada o caída).
struct Reservas: View {
    @Environment(Estado.self) private var estado
    var ruta = "/v1/reservas"
    var body: some View {
        ListaGenerica(titulo: "Reservas", ruta: ruta, icono: "hand.raised", vacio: "No hay reservas abiertas.") { x in
            guard let id = x["id"]?.texto, estado.escribe else { return [] }
            struct C: Encodable { var resultado: String; var motivo: String?; var cerradaEl: String }
            return [
                ("Se concretó", { Task { do { try await estado.api.hacer("POST", "/v1/reservas/\(id)/cerrar", C(resultado: "concretada", cerradaEl: Formato.diaISO(Date()))); estado.version += 1; estado.avisar("Reserva concretada") } catch { estado.avisar(error) } } }),
                ("Se cayó", { Task { do { try await estado.api.hacer("POST", "/v1/reservas/\(id)/cerrar", C(resultado: "caida", cerradaEl: Formato.diaISO(Date()))); estado.version += 1; estado.avisar("Reserva caída") } catch { estado.avisar(error) } } }),
            ]
        }
    }
}
