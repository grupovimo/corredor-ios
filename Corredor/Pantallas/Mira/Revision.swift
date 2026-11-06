import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Revisión (lo que armó la IA)

struct BorradorIA: Codable, Identifiable, Hashable {
    var id: String
    var estado: String?
    var tipo: String?
    var canal: String?
    var asunto: String?
    var texto: String?
    var motivo: String?
    var contactoId: String?
    var propiedadId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var deLaIA: Bool?
    var creadoEn: Date?
}

/// Revisión: mensajes, descripciones y notas que armó la IA (o vos) y esperan que alguien los mire. Se
/// corrigen, se usan (WhatsApp, mail, la descripción de la ficha, una nota) o se descartan.
struct RevisionIA: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [BorradorIA]?
    @State private var editando: BorradorIA?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty { EstadoVacio(icono: "checkmark.shield", titulo: "Nada para revisar", texto: "Lo que tu IA arme (mensajes, descripciones, notas) llega acá antes de usarse.").padding(.top, 40) }
                    ForEach(lista) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(Self.tipo(b), systemImage: b.deLaIA == true ? "sparkles" : "doc.text").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font)
                                    .foregroundStyle(b.deLaIA == true ? C.violetaTinta : C.texto2)
                                Spacer()
                                if let f = b.creadoEn { Text(Formato.hace(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                            }
                            Text([b.contactoNombre, b.propiedadTitulo].compactMap { $0 }.joined(separator: " · ")).estilo(.filaLista).foregroundStyle(C.texto)
                            if let a = b.asunto { Text(a).estilo(.subheadFuerte).foregroundStyle(C.texto) }
                            Text(b.texto ?? "").estilo(.texto14).foregroundStyle(C.texto2).lineLimit(6)
                            if estado.escribe {
                                HStack(spacing: 8) {
                                    Button(Self.usar(b)) { Task { await usar(b) } }.buttonStyle(BotonAccion())
                                    Button("Corregir") { editando = b }.buttonStyle(BotonHundido())
                                    Button { Task { await descartar(b) } } label: { Image(systemName: "trash") }.buttonStyle(BotonHundido()).frame(width: 56)
                                        .accessibilityLabel("Descartar")
                                }
                            }
                        }
                        .padding(14).tarjeta()
                    }
                } else { EsqueletoFilas(filas: 4) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Revisión")
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { b in
            EditorTexto(titulo: b.asunto ?? Self.tipo(b), texto: b.texto ?? "") { _, t in
                Task {
                    struct C: Encodable { var texto: String }
                    do { try await estado.api.hacer("PATCH", "/v1/revision/\(b.id)", C(texto: t)); await cargar() } catch { estado.avisar(error) }
                }
            }
        }
    }

    static func tipo(_ b: BorradorIA) -> String {
        switch b.tipo {
        case "descripcion": return "Descripción para la ficha"
        case "nota": return "Nota"
        default: return b.canal == "email" ? "Mail" : "Mensaje de WhatsApp"
        }
    }

    static func usar(_ b: BorradorIA) -> String {
        switch b.tipo {
        case "descripcion": return "Ponerla en la ficha"
        case "nota": return "Guardar la nota"
        default: return b.canal == "email" ? "Mandar el mail" : "Mandar por WhatsApp"
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/revision")) ?? lista ?? [] }

    /// Usarlo: lo hace (abre WhatsApp o mail, pega la descripción, guarda la nota) y lo marca usado.
    private func usar(_ b: BorradorIA) async {
        let t = b.texto ?? ""
        do {
            switch b.tipo {
            case "descripcion":
                if let p = b.propiedadId {
                    struct C: Encodable { var descripcion: String }
                    try await estado.api.hacer("PATCH", "/v1/propiedades/\(p)", C(descripcion: t))
                }
            case "nota":
                if let c = b.contactoId {
                    struct N: Encodable { var tipo = "nota"; var texto: String }
                    try await estado.api.hacer("POST", "/v1/contactos/\(c)/notas", N(texto: t))
                }
            default:
                struct Ct: Decodable { var telefono: String?; var email: String? }
                let c: Ct? = b.contactoId == nil ? nil : try? await estado.api.get("/v1/contactos/\(b.contactoId!)")
                if b.canal == "email" {
                    var u = URLComponents(string: "mailto:\(c?.email ?? "")")!
                    u.queryItems = [.init(name: "subject", value: b.asunto ?? ""), .init(name: "body", value: t)]
                    if let x = u.url { await UIApplication.shared.open(x) }
                } else {
                    Afuera.whatsapp(c?.telefono, texto: t)
                }
            }
            try await estado.api.hacer("POST", "/v1/revision/\(b.id)/usado")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func descartar(_ b: BorradorIA) async {
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            try? await estado.api.hacer("DELETE", "/v1/revision/\(b.id)")
            estado.version += 1
        }
        lista?.removeAll { $0.id == b.id }
        estado.avisar("Descartado") { tarea.cancel(); Task { await cargar() } }
    }
}
