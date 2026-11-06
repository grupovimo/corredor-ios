import AuthenticationServices
import SwiftUI

/// Respuestas guardadas: los textos que se mandan con un toque desde un chat de WhatsApp. Se usan en
/// Mensajes; acá se cargan, se corrigen y se borran (con cuántas veces se usó cada una).
struct RespuestasGuardadas: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Respuesta]?
    @State private var error: ErrorApi?
    @State private var editando: Respuesta?

    /// `GET /v1/respuestas-guardadas`, con los usos.
    struct Respuesta: Codable, Identifiable, Hashable { var id: String; var titulo: String; var texto: String; var usos: Int? }

    static func usos(_ r: Respuesta) -> String { (r.usos ?? 0) > 0 ? Formato.cantidad(r.usos ?? 0, "uso", "usos") : "sin usar" }

    var body: some View {
        Group {
            if let lista {
                if lista.isEmpty { vacio } else { listado(lista) }
            } else if let error {
                EstadoError(que: "las respuestas guardadas", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 5).padding(16).frame(maxHeight: .infinity, alignment: .top) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoApp())
        .pantallaApilada("Respuestas guardadas")
        .toolbar { if estado.escribe { Button { editando = Respuesta(id: "", titulo: "", texto: "") } label: { Label("Nueva", systemImage: "plus") } } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { r in FormRespuesta(r: r) { await cargar() } }
    }

    private var vacio: some View {
        let accion: (String, () -> Void)? = estado.escribe ? ("Guardar la primera", { editando = Respuesta(id: "", titulo: "", texto: "") }) : nil
        return VStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach([("Requisitos para alquilar", "12 usos"), ("Horario de visitas", "7 usos")], id: \.0) { t, d in
                    HStack { Text(t).estilo(.filaLista); Spacer(); Text(d).estilo(.footnote) }.foregroundStyle(C.texto3).padding(14)
                }
            }
            .tarjeta().opacity(0.5).padding(.horizontal, 16)
            EstadoVacio(icono: "text.bubble", titulo: "Todavía no guardaste respuestas", texto: "Lo que escribís siempre: requisitos, horarios, cómo llegar.", accion: accion)
        }
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func listado(_ l: [Respuesta]) -> some View {
        List {
            Section {
                Text("Las mandás con un toque desde cualquier chat de WhatsApp.").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .listRowBackground(Color.clear)
            ForEach(l) { r in
                Button { editando = r } label: {
                    HStack(alignment: .top, spacing: 12) {
                        IconoFila(icono: "text.bubble", color: C.okTinta)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                            Text(r.texto).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text(Self.usos(r)).estilo(.footnote).foregroundStyle(C.texto3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver «\(r.titulo)»")
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await cargar() }
    }

    private func cargar() async {
        do {
            lista = try await estado.api.get("/v1/respuestas-guardadas")
            error = nil
        } catch let e as ErrorApi { if lista == nil { error = e } } catch {}
    }
}

/// La hoja de una respuesta: nombre (60) y texto (1000), con el error de cada campo; cierra recién
/// cuando se guardó. El lector la ve bloqueada; borrar se confirma.
struct FormRespuesta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var r: RespuestasGuardadas.Respuesta
    var alGuardar: () async -> Void
    @State private var campos: [String: String] = [:]
    @State private var guardando = false
    @State private var confirmar: Confirmacion?

    private var nueva: Bool { r.id.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !nueva { Section { Text(RespuestasGuardadas.usos(r)).estilo(.footnote).foregroundStyle(C.texto2) } }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Nombre", text: $r.titulo, prompt: Text("Requisitos para alquilar"))
                            .onChange(of: r.titulo) { _, v in if v.count > 60 { r.titulo = String(v.prefix(60)) } }
                        ErrorDeCampo(texto: campos["titulo"])
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Texto", text: $r.texto, axis: .vertical).lineLimit(6...14)
                            .onChange(of: r.texto) { _, v in if v.count > 1000 { r.texto = String(v.prefix(1000)) } }
                        Text("\(r.texto.count)/1000").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity, alignment: .trailing)
                        ErrorDeCampo(texto: campos["texto"])
                    }
                }
                .disabled(!estado.escribe)
                if !nueva, estado.escribe {
                    Section {
                        Button("Borrar", role: .destructive) {
                            confirmar = Confirmacion(titulo: "¿Borrás «\(r.titulo)»?", texto: "Deja de aparecer en los chats. Lo que ya mandaste queda.", boton: "Borrar") { Task { await borrar() } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle(nueva ? "Respuesta nueva" : r.titulo).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                if estado.escribe {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await guardar() } } label: { if guardando { ProgressView() } else { Text("Guardar") } }
                            .disabled(guardando || r.titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmacion($confirmar)
        }
    }

    private func guardar() async {
        campos = [:]
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var titulo: String; var texto: String }
        let c = Cuerpo(titulo: r.titulo.trimmingCharacters(in: .whitespacesAndNewlines), texto: r.texto.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            if nueva { try await estado.api.pedirConCampos("POST", "/v1/respuestas-guardadas", c, envio: UUID().uuidString) }
            else { try await estado.api.pedirConCampos("PUT", "/v1/respuestas-guardadas/\(r.id)", c) }
            estado.avisar(nueva ? "Respuesta lista para usar" : "Respuesta guardada")
            await alGuardar()
            cerrar()
        } catch { campos = estado.camposDe(error) }
    }

    private func borrar() async {
        do {
            try await estado.api.hacer("DELETE", "/v1/respuestas-guardadas/\(r.id)")
            estado.avisar("Borraste «\(r.titulo)»")
            await alGuardar()
            cerrar()
        } catch { estado.avisar(error) }
    }
}
