import AuthenticationServices
import SwiftUI

/// Respuestas guardadas de WhatsApp: cargar, corregir y borrar.
struct RespuestasGuardadas: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [RespuestaGuardada] = []
    @State private var editando: RespuestaGuardada?
    @State private var nueva = false

    var body: some View {
        List {
            if lista.isEmpty { Text("Lo que escribís siempre: requisitos, horarios, cómo llegar.").foregroundStyle(C.texto2) }
            ForEach(lista) { r in
                Button { editando = r } label: {
                    VStack(alignment: .leading, spacing: 2) { Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto); Text(r.texto).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2) }
                }
                .swipeActions { Button("Borrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/respuestas-guardadas/\(r.id)"); await cargar() } catch { estado.avisar(error) } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Respuestas guardadas")
        .toolbar { if estado.escribe { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva") } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { r in EditorTexto(titulo: r.titulo, texto: r.texto) { t, x in Task { await guardar(r.id, t, x) } } }
        .sheet(isPresented: $nueva) { EditorTexto(titulo: "", texto: "") { t, x in Task { await guardar(nil, t, x) } } }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/respuestas-guardadas")) ?? [] }

    private func guardar(_ id: String?, _ t: String, _ x: String) async {
        struct Cuerpo: Encodable { var titulo: String; var texto: String }
        do {
            if let id { try await estado.api.hacer("PUT", "/v1/respuestas-guardadas/\(id)", Cuerpo(titulo: t, texto: x)) }
            else { try await estado.api.hacer("POST", "/v1/respuestas-guardadas", Cuerpo(titulo: t, texto: x)) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}
