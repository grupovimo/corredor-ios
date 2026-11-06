import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Perfil: firma y sesiones

/// La firma en mensajes y las sesiones abiertas (lo mismo que en Mi perfil, para el acceso directo
/// de «Más»): la firma con la sugerida, su hoja con «Deshacer», y cerrar las sesiones de otros aparatos.
struct FirmaYSesiones: View {
    @Environment(Estado.self) private var estado
    @State private var firma: FirmaPerfil?
    @State private var error: ErrorApi?
    @State private var editando = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let f = firma {
                    Button { editando = true } label: {
                        HStack(spacing: 12) {
                            Text("Firma en mensajes").estilo(.body16).foregroundStyle(C.texto)
                            Spacer(minLength: 8)
                            Text(f.activa ? (f.texto?.nonEmpty ?? "Sin firma") : "Sin firma").estilo(.texto14)
                                .foregroundStyle(f.activa ? C.texto2 : C.texto3).lineLimit(1)
                            Chevron()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .tarjeta()
                } else if let error {
                    EstadoError(que: "tu firma", error: error) { Task { await cargar() } }
                } else {
                    EsqueletoFilas(filas: 2)
                }
                ListaSesiones()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(FondoApp())
        .pantallaApilada("Firma y sesiones")
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editando) {
            if let f = firma { HojaFirmaMensajes(firma: f) { firma = $0 }.hojaTLW([.medium, .large]) }
        }
    }

    private func cargar() async {
        do {
            firma = try await estado.api.get("/v1/perfil/firma")
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }
}
