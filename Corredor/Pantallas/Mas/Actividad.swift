import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Actividad

struct EntradaActividad: Codable, Identifiable, Hashable {
    /// En la API es un número (la auditoría), y sirve para seguir bajando con `antesDe`.
    var id: Int64
    var actorTipo: String?
    var actorNombre: String?
    var accion: String?
    var entidad: String?
    var entidadId: String?
    var entidadTitulo: String?
    var creadoEn: Date?
}

/// Actividad: quién hizo qué y cuándo (también la IA), con el filtro por persona y lo que se tocó.
struct Actividad: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [EntradaActividad]?
    @State private var quien = ""
    /// Si la última página vino llena, hay más para atrás.
    @State private var hayMas = false
    @State private var bajando = false
    private static let pagina = 200

    var body: some View {
        List {
            if let lista, lista.isEmpty {
                EstadoVacio(icono: "clock.arrow.circlepath", titulo: "Todavía no hay movimientos",
                            texto: "Acá vas a ver quién cargó, cambió o borró algo, y cuándo.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if let lista {
                let personas = Array(Set(lista.compactMap(\.actorNombre))).sorted()
                if personas.count > 1 {
                    Picker("Quién", selection: $quien) { Text("Todos").tag(""); ForEach(personas, id: \.self) { Text($0).tag($0) } }
                }
                ForEach(lista.filter { quien.isEmpty || $0.actorNombre == quien }) { a in
                    Button { abrir(a) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            IconoTono(icono: a.actorTipo == "ia" ? "sparkles" : Self.icono(a.accion), tono: a.actorTipo == "ia" ? .violeta : .verde, tam: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.actorNombre ?? (a.actorTipo == "ia" ? "Tu IA" : "Alguien")) \(Self.verbo(a.accion)) \(Self.cosa(a.entidad))").estilo(.subhead).foregroundStyle(C.texto)
                                if let t = a.entidadTitulo { Text(t).estilo(.filaLista).foregroundStyle(C.texto) }
                                if let f = a.creadoEn { Text(Formato.cuando(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                            }
                        }
                    }
                }
                if hayMas {
                    Button { Task { await masViejos() } } label: {
                        HStack { Spacer(); Text(bajando ? "Cargando…" : "Ver más"); Spacer() }
                    }
                    .disabled(bajando)
                }
            } else { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Actividad")
        .refreshable { await cargar() }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        if let l: [EntradaActividad] = try? await estado.api.get("/v1/actividad", query: [.init(name: "limite", value: "\(Self.pagina)")]) {
            lista = l
            hayMas = l.count == Self.pagina
        } else if lista == nil { lista = [] }
    }

    /// La página siguiente: lo anterior al último que se ve (`antesDe`, sin saltos aunque entren nuevos).
    private func masViejos() async {
        guard let ultimo = lista?.last?.id else { return }
        bajando = true
        defer { bajando = false }
        do {
            let l: [EntradaActividad] = try await estado.api.get("/v1/actividad", query: [.init(name: "limite", value: "\(Self.pagina)"), .init(name: "antesDe", value: "\(ultimo)")])
            lista = (lista ?? []) + l
            hayMas = l.count == Self.pagina
        } catch { estado.avisar(error) }
    }

    private func abrir(_ a: EntradaActividad) {
        guard let id = a.entidadId else { return }
        switch a.entidad {
        case "propiedad": estado.abrir(AFichaPropiedad(id: id))
        case "contacto": estado.abrir(AFichaContacto(id: id))
        case "operacion": estado.abrir(AFichaOperacion(id: id))
        case "contrato": estado.abrir(AFichaContrato(id: id))
        case "cita": estado.abrir(ACita(id: id))
        default: break
        }
    }

    static func verbo(_ a: String?) -> String {
        ["crear": "cargó", "editar": "cambió", "borrar": "borró", "restaurar": "restauró", "mover": "movió", "compartir": "compartió", "emitir": "emitió", "cobrar": "cobró"][a ?? ""] ?? (a ?? "tocó")
    }

    static func cosa(_ e: String?) -> String {
        ["propiedad": "una propiedad", "contacto": "un contacto", "operacion": "una operación", "contrato": "un contrato", "cobro": "un cobro", "cita": "una cita",
         "rendicion": "una rendición", "respuesta_guardada": "una respuesta guardada"][e ?? ""] ?? (e ?? "")
    }

    static func icono(_ a: String?) -> String {
        ["crear": "plus", "editar": "pencil", "borrar": "trash", "mover": "arrow.right", "compartir": "square.and.arrow.up", "cobrar": "dollarsign"][a ?? ""] ?? "clock"
    }
}
