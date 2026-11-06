import AuthenticationServices
import SwiftUI

/// La papelera (30 días): restaurar lo borrado.
struct Papelera: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        ListaGenerica(titulo: "Papelera", ruta: "/v1/papelera", icono: "trash", vacio: "La papelera está vacía.") { x in
            guard let ent = x["entidad"]?.texto, let id = x["id"]?.texto else { return [] }
            return [("Restaurar", {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/papelera/\(ent)/\(id)/restaurar")
                        estado.version += 1
                        estado.avisar("Restaurado")
                    } catch { estado.avisar(error) }
                }
            })]
        }
    }
}
