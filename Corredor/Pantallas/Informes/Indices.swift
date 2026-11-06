import AuthenticationServices
import SwiftUI

/// Los índices de ajuste (ICL, IPC, UVA): el último valor y cuándo se actualizó.
struct Indices: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Ind] = []
    struct Ind: Codable, Identifiable { var codigo: String; var ultimoPeriodo: String?; var ultimoValor: Double?; var actualizadoEn: Date?; var id: String { codigo } }

    var body: some View {
        List(lista) { i in
            HStack {
                VStack(alignment: .leading) {
                    Text(i.codigo.uppercased()).estilo(.filaLista)
                    Text(i.ultimoPeriodo.map { "Último: \($0)" } ?? "").estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer()
                Text(i.ultimoValor.map { String(format: "%.4f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—").fontWeight(.semibold)
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Índices")
        .task(id: estado.version) { lista = (try? await estado.api.get("/v1/indices")) ?? [] }
    }
}
