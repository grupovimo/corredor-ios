import SwiftUI

/// Algo de la papelera (GET /v1/papelera; transversal.Borrado).
struct BorradoAPI: Codable, Identifiable, Hashable {
    var entidad: String
    var id: String
    var titulo: String
    var detalle: String?
    var borradoEn: Date
    /// Quién lo mandó a la papelera (de la auditoría).
    var borradoPor: String?
    var clave: String { entidad + id }
}

/// La papelera: lo que se borra queda 30 días. Recuperarlo lo deja como estaba (sólo quien escribe);
/// el dueño también lo puede borrar del todo (menos cobros y liquidaciones, que son historial).
struct Papelera: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var lista: [BorradoAPI]?
    @State private var error: ErrorApi?
    @State private var ocultos: Set<String> = []
    @State private var borrando: BorradoAPI?

    /// El ícono, el nombre y adónde lleva cada tipo.
    static let entidades: [String: (String, String)] = [
        "propiedad": ("house", "Propiedad"), "contacto": ("person", "Contacto"), "operacion": ("rectangle.split.3x1", "Operación"),
        "cita": ("calendar", "Cita"), "emprendimiento": ("building", "Emprendimiento"), "consorcio": ("building.columns", "Consorcio"),
        "unidad": ("door.left.hand.closed", "Unidad"), "contrato": ("doc.text", "Contrato"), "documento": ("doc", "Documento"),
        "reserva_temporada": ("beach.umbrella", "Reserva de temporada"),
    ]

    private var visibles: [BorradoAPI] { (lista ?? []).filter { !ocultos.contains($0.clave) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(Formato.sinViudas("Lo que se borra queda 30 días. Recuperarlo lo deja como estaba, con todo lo que tenía."))
                    .estilo(.subhead).foregroundStyle(C.texto2)
                if lista != nil {
                    if visibles.isEmpty {
                        EstadoVacio(icono: "trash", titulo: "La papelera está vacía",
                                    texto: "Lo que borres en los próximos días aparece acá y lo podés recuperar durante 30 días.",
                                    accion: ("Volver", { cerrar() }))
                            .padding(.top, 30)
                    } else {
                        HStack {
                            Text(visibles.count == 1 ? "1 cosa" : "\(visibles.count) cosas").estilo(.subheadFuerte).foregroundStyle(C.texto)
                            Spacer()
                            Text("se vacía a los 30 días").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(visibles.enumerated()), id: \.element.clave) { i, b in fila(b, primera: i == 0) }
                        }
                        .tarjeta()
                    }
                } else if let error {
                    EstadoError(que: "la papelera", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Papelera")
        .task(id: estado.version) { await cargar() }
        .confirmationDialog("¿Borrás del todo \(borrando?.titulo ?? "")?", isPresented: Binding(get: { borrando != nil }, set: { if !$0 { borrando = nil } }), titleVisibility: .visible) {
            Button("Borrar del todo", role: .destructive) { if let b = borrando { Task { await borrarDelTodo(b) } } }
            Button("No", role: .cancel) { borrando = nil }
        } message: { Text("Sale de la papelera y no se puede recuperar.") }
    }

    private func detalle(_ b: BorradoAPI) -> String {
        let pasaron = diasCalendario(b.borradoEn, Date())
        let quedan = 30 - pasaron
        return [b.detalle, b.borradoPor?.components(separatedBy: " ").first, pasaron == 0 ? "hoy" : Formato.hace(b.borradoEn), quedan <= 27 ? "quedan \(max(quedan, 0))" : nil]
            .compactMap { $0?.nonEmpty }.joined(separator: " · ")
    }

    private func fila(_ b: BorradoAPI, primera: Bool) -> some View {
        let e = Self.entidades[b.entidad] ?? ("trash", b.entidad)
        return HStack(spacing: 12) {
            IconoTono(icono: e.0, tono: .neutro, tam: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                Text("\(e.1) · \(detalle(b))").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
            }
            Spacer()
            if estado.esDuenio, !["cobro", "liquidacion"].contains(b.entidad) {
                Button { borrando = b } label: { Image(systemName: "trash.slash").foregroundStyle(C.error).frame(width: 36, height: 36) }
                    .accessibilityLabel("Borrar del todo \(b.titulo)")
            }
            if estado.escribe {
                Button("Recuperar") { Task { await recuperar(b) } }.buttonStyle(BotonTonal(alto: 32))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func destino(_ b: BorradoAPI) -> AnyHashable? {
        switch b.entidad {
        case "propiedad": return AFichaPropiedad(id: b.id)
        case "contacto": return AFichaContacto(id: b.id)
        case "operacion": return AFichaOperacion(id: b.id)
        case "cita": return ACita(id: b.id)
        case "emprendimiento": return ASeccion(clave: "emprendimiento", id: b.id)
        case "consorcio": return ASeccion(clave: "consorcio", id: b.id)
        case "contrato": return AFichaContrato(id: b.id)
        case "reserva_temporada": return AReservaTemporada(id: b.id)
        default: return nil
        }
    }

    private func recuperar(_ b: BorradoAPI) async {
        ocultos.insert(b.clave)
        do {
            try await estado.api.hacer("POST", "/v1/papelera/\(b.entidad)/\(b.id)/restaurar")
            estado.version += 1
            if let d = destino(b) { estado.sugerir("Recuperaste \(b.titulo)", "Ver", d) } else { estado.avisar("Recuperaste \(b.titulo)") }
        } catch {
            ocultos.remove(b.clave)
            estado.sugerir("No se recuperó · \((error as? ErrorApi)?.detalle ?? "probá de nuevo")", "Reintentar") { Task { await recuperar(b) } }
        }
    }

    private func borrarDelTodo(_ b: BorradoAPI) async {
        borrando = nil
        do {
            try await estado.api.hacer("DELETE", "/v1/papelera/\(b.entidad)/\(b.id)")
            ocultos.insert(b.clave)
            estado.avisar("\(b.titulo) se borró del todo")
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            lista = try await estado.api.get("/v1/papelera")
            ocultos = []
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }
}
