import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Perfil: firma y sesiones

/// La firma de los mails que salen a tu nombre y las sesiones abiertas (cerrar las de otros aparatos).
struct FirmaYSesiones: View {
    @Environment(Estado.self) private var estado
    @State private var firma = ""
    @State private var activa = false
    @State private var sesiones: [SesionAbierta] = []
    struct SesionAbierta: Codable, Identifiable { var id: String; var agente: String?; var ip: String?; var vistoEn: Date?; var actual: Bool? }

    var body: some View {
        Form {
            Section(header: Text("Firma de tus mails"), footer: Text("Sale al pie de las fichas y los mails que mandás desde Corredor.")) {
                Toggle("Usar firma", isOn: $activa)
                TextField("Martín Ríos · Luna Propiedades · 11 4823-1190", text: $firma, axis: .vertical).lineLimit(2...6)
                Button("Guardar la firma") {
                    Task {
                        struct C: Encodable { var activa: Bool; var texto: String? }
                        do { try await estado.api.hacer("PUT", "/v1/perfil/firma", C(activa: activa, texto: firma.nonEmpty)); estado.avisar("Firma guardada") } catch { estado.avisar(error) }
                    }
                }
            }
            Section("Sesiones abiertas") {
                ForEach(sesiones) { x in
                    VStack(alignment: .leading) {
                        Text((x.agente ?? "Aparato") + (x.actual == true ? " · este" : "")).estilo(.filaLista).lineLimit(1)
                        Text([x.ip, x.vistoEn.map { "visto \(Formato.hace($0))" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions {
                        if x.actual != true { Button("Cerrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/auth/sesiones/\(x.id)"); await cargar() } catch { estado.avisar(error) } } } }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Firma y sesiones")
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        struct F: Decodable { var activa: Bool?; var texto: String? }
        if let f: F = try? await estado.api.get("/v1/perfil/firma") { activa = f.activa ?? false; firma = f.texto ?? "" }
        sesiones = (try? await estado.api.get("/v1/auth/sesiones")) ?? []
    }
}
