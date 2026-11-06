import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Reglamento del consorcio

/// Los coeficientes del reglamento: si los de hoy cambiaron desde que se guardaron, cuáles; y
/// «Guardar los de hoy como reglamento».
struct ReglamentoConsorcio: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    @State private var r: R?

    struct R: Codable {
        struct Cambio: Codable, Hashable { var unidad: String?; var columna: String?; var reglamento: Double?; var hoy: Double? }
        var guardadoEn: Date?
        var sinCambios: Bool?
        var cambios: [Cambio]?
    }

    var body: some View {
        List {
            if let r {
                Section {
                    if r.guardadoEn == nil {
                        Text("Todavía no guardaste los coeficientes del reglamento.").foregroundStyle(C.texto2)
                    } else if r.sinCambios == true {
                        Label("Coeficientes del reglamento: sin cambios", systemImage: "checkmark.seal").foregroundStyle(C.okTinta)
                    } else {
                        Label("Hay coeficientes distintos a los del reglamento", systemImage: "exclamationmark.triangle").foregroundStyle(C.avisoTinta)
                    }
                    if let g = r.guardadoEn { Text("Guardado \(Formato.cuando(g))").estilo(.footnote).foregroundStyle(C.texto3) }
                }
                if let c = r.cambios, !c.isEmpty {
                    Section("Cambios") {
                        ForEach(c, id: \.self) { x in
                            LabeledContent("\(x.unidad ?? "") · \(x.columna ?? "")", value: "\(Self.num(x.reglamento)) → \(Self.num(x.hoy))")
                        }
                    }
                }
                if estado.esDuenio {
                    Section { Button("Guardar los de hoy como reglamento") { Task { do { try await estado.api.hacer("PUT", "/v1/consorcios/\(consorcio)/reglamento"); await cargar(); estado.avisar("Reglamento guardado") } catch { estado.avisar(error) } } } }
                }
            } else { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Reglamento")
        .task(id: estado.version) { await cargar() }
    }

    static func num(_ n: Double?) -> String { n.map { String(format: "%.4f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—" }
    private func cargar() async { r = try? await estado.api.get("/v1/consorcios/\(consorcio)/reglamento") }
}
