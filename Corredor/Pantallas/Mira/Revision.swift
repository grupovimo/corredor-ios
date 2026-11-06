import SwiftUI

// MARK: - Revisión (lo que armó la IA)

/// Un borrador de la IA (GET /v1/revision; dominio/revision).
struct BorradorIA: Codable, Identifiable, Hashable {
    var id: String
    /// pendiente · usado · descartado
    var estado: String?
    /// mensaje · descripcion · nota
    var tipo: String?
    var canal: String?
    var asunto: String?
    var texto: String?
    var motivo: String?
    var contactoId: String?
    var propiedadId: String?
    var operacionId: String?
    var contratoId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var deLaIA: Bool?
    var creadoEn: Date?
    var resueltoEn: Date?
}

/// Los borradores que mandó la IA (el link `/revision?ids=…`): esos, incluidos los ya resueltos.
struct ARevisionIds: Hashable { var ids: String }

/// Borradores de tu IA: lo que armó «Corredor en tu IA» (mensajes, descripciones, notas) espera acá a
/// que una persona lo mire, lo corrija y lo use, o lo descarte. La IA no manda ni publica.
struct RevisionIA: View {
    @Environment(Estado.self) private var estado
    /// Los ids del link de la IA (los muestra aunque ya estén resueltos).
    var ids: String? = nil
    @State private var lista: [BorradorIA]?
    @State private var pendientesTodos: [BorradorIA] = []
    @State private var error: ErrorApi?
    @State private var editando: BorradorIA?
    @State private var ocultos: Set<String> = []
    @State private var usados: Set<String> = []
    @State private var ocupados: Set<String> = []

    private var visibles: [BorradorIA] { (lista ?? []).filter { !ocultos.contains($0.id) } }
    private var pendientes: [BorradorIA] { visibles.filter { $0.estado == "pendiente" && !usados.contains($0.id) } }
    private var resueltos: [BorradorIA] { visibles.filter { $0.estado != "pendiente" || usados.contains($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(Formato.sinViudas("La IA no manda ni publica: deja acá lo que armó. Miralo, corregilo y usalo, o descartalo."))
                    .estilo(.subhead).foregroundStyle(C.texto2)
                if lista != nil {
                    cuentas
                    if pendientes.isEmpty {
                        EstadoVacio(icono: "checkmark.shield", titulo: "No hay borradores esperando",
                                    texto: "Cuando le pidas a tu IA que arme un mensaje, una descripción o una nota, aparece acá para que lo revises antes de usarlo.",
                                    accion: ("Conectar tu IA", { estado.abrir(ASeccion(clave: "ia")) }))
                            .padding(.top, 20)
                    }
                    ForEach(pendientes) { b in tarjeta(b) }
                    if !resueltos.isEmpty {
                        TituloBloque(texto: "Ya resueltos").padding(.top, 8)
                        VStack(spacing: 0) {
                            ForEach(Array(resueltos.enumerated()), id: \.element.id) { i, b in
                                let a = Self.aspecto(b)
                                HStack(spacing: 12) {
                                    IconoTono(icono: a.icono, tono: a.tono, tam: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(a.titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                        Text("\(b.estado == "descartado" ? "Descartado" : "Usado")\((b.resueltoEn ?? (usados.contains(b.id) ? Date() : nil)).map { " · \(Formato.hace($0))" } ?? "")")
                                            .estilo(.footnote).foregroundStyle(C.texto2)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14).frame(minHeight: 52)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                            }
                        }
                        .tarjeta()
                    }
                } else if let error {
                    EstadoError(que: "los borradores", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 4) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Borradores de tu IA")
        .toolbar { if ids != nil { Button("Ver todos") { estado.abrir(ASeccion(clave: "revision")) } } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { b in
            CorregirBorrador(b: b) { asunto, texto in Task { await guardar(b, asunto: asunto, texto: texto) } }
        }
    }

    private var cuentas: some View {
        let c = { (t: String) in pendientesTodos.filter { $0.tipo == t }.count }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(pendientesTodos.isEmpty ? "Al día" : "\(pendientesTodos.count) esperan")").estilo(.footnoteFuerte).foregroundStyle(C.texto)
                Text("· Mensajes \(c("mensaje")) · Descripciones \(c("descripcion")) · Notas \(c("nota"))").estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
    }

    struct Aspecto { var icono: String; var tono: Tono; var titulo: String; var usar: String }

    static func aspecto(_ b: BorradorIA) -> Aspecto {
        switch b.tipo {
        case "descripcion": return Aspecto(icono: "doc.text", tono: .oro, titulo: "Descripción de \(b.propiedadTitulo ?? "una propiedad")", usar: "Usar en la ficha")
        case "nota": return Aspecto(icono: "note.text", tono: .neutro, titulo: "Nota sobre \(b.contactoNombre ?? b.propiedadTitulo ?? "una operación")", usar: "Guardar como nota")
        default:
            return b.canal == "email"
                ? Aspecto(icono: "envelope", tono: .azul, titulo: "Mail para \(b.contactoNombre ?? "un contacto")", usar: "Abrir en el mail")
                : Aspecto(icono: "bubble.left", tono: .verde, titulo: "WhatsApp para \(b.contactoNombre ?? "un contacto")", usar: "Mandar por WhatsApp")
        }
    }

    private func tarjeta(_ b: BorradorIA) -> some View {
        let a = Self.aspecto(b)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconoTono(icono: a.icono, tono: a.tono, tam: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                    Text("\(b.motivo.map { "\($0) · " } ?? "")\(b.deLaIA == true ? "armado por tu IA" : "armado en Corredor")\(b.creadoEn.map { " · \(Formato.hace($0))" } ?? "")")
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            if let s = b.asunto { (Text("Asunto: ").foregroundColor(C.texto2) + Text(s)).estilo(.subheadFuerte).foregroundStyle(C.texto) }
            Text(b.texto ?? "").estilo(.texto14).foregroundStyle(C.texto)
                .padding(b.tipo == "mensaje" && b.canal != "email" ? 12 : 0)
                .background(b.tipo == "mensaje" && b.canal != "email" ? C.okFondo : .clear, in: .rect(cornerRadius: 14, style: .continuous))
            if estado.escribe {
                HStack(spacing: 8) {
                    Button(ocupados.contains(b.id) ? "Usando…" : a.usar) { Task { await usar(b) } }.buttonStyle(BotonAccion()).disabled(ocupados.contains(b.id))
                    Button("Corregir") { editando = b }.buttonStyle(BotonHundido())
                    Button("Descartar") { descartar(b) }.buttonStyle(BotonTexto())
                }
            }
        }
        .padding(14).tarjeta()
    }

    private func cargar() async {
        do {
            var q: [URLQueryItem] = [.init(name: "limite", value: "100"), .init(name: "estado", value: ids == nil ? "pendiente" : "todos")]
            if let ids { q.append(.init(name: "ids", value: ids)) }
            lista = try await estado.api.get("/v1/revision", query: q)
            error = nil
            pendientesTodos = (try? await estado.api.get("/v1/revision", query: [.init(name: "limite", value: "200")])) ?? []
        } catch let e as ErrorApi { error = e } catch {}
    }

    private func guardar(_ b: BorradorIA, asunto: String?, texto: String) async {
        struct C: Encodable { var texto: String; var asunto: String? }
        do {
            try await estado.api.hacer("PATCH", "/v1/revision/\(b.id)", C(texto: texto, asunto: b.canal == "email" ? asunto : nil))
            if let i = lista?.firstIndex(where: { $0.id == b.id }) { lista?[i].texto = texto; if b.canal == "email" { lista?[i].asunto = asunto } }
            estado.avisar("Borrador corregido")
        } catch { estado.avisar(error) }
    }

    /// Usarlo como la web: el WhatsApp sale por la conversación de Corredor (queda en Mensajes); la
    /// descripción va a la ficha; la nota, al contacto o a la operación; el mail se abre en el correo.
    private func usar(_ b: BorradorIA) async {
        let t = b.texto ?? ""
        if b.canal == "email" {
            var mail: String?
            if let c = b.contactoId { mail = (try? await estado.api.get("/v1/contactos/\(c)") as Contacto)?.email }
            var u = URLComponents(string: "mailto:\(mail ?? "")")!
            u.queryItems = [.init(name: "subject", value: b.asunto ?? ""), .init(name: "body", value: t)]
            if let x = u.url { await UIApplication.shared.open(x, options: [:], completionHandler: nil) }
            usados.insert(b.id)
            do { try await estado.api.hacer("POST", "/v1/revision/\(b.id)/usado") } catch { estado.avisar(error) }
            estado.avisar("Se abrió el mail. Quedó como usado.") { usados.remove(b.id) }
            return
        }
        ocupados.insert(b.id)
        defer { ocupados.remove(b.id) }
        var ir: AnyHashable?
        do {
            switch b.tipo {
            case "descripcion":
                guard let pid = b.propiedadId else { estado.avisar("El borrador no dice de qué propiedad es.", ok: false); return }
                var p: Propiedad = try await estado.api.get("/v1/propiedades/\(pid)")
                p.descripcion = t
                try await estado.api.hacer("PUT", "/v1/propiedades/\(pid)", p)
                ir = AFichaPropiedad(id: pid)
            case "nota":
                struct N: Encodable { var tipo = "nota"; var texto: String }
                struct O: Encodable { var texto: String }
                if let c = b.contactoId {
                    try await estado.api.hacer("POST", "/v1/contactos/\(c)/notas", N(texto: t))
                    ir = AFichaContacto(id: c)
                } else if let o = b.operacionId {
                    try await estado.api.hacer("POST", "/v1/operaciones/\(o)/notas", O(texto: t))
                    ir = AFichaOperacion(id: o)
                } else { estado.avisar("La nota no dice de quién es.", ok: false); return }
            default:
                guard let c = b.contactoId else { estado.avisar("El borrador no dice a quién mandarlo.", ok: false); return }
                struct Conv: Encodable { var contactoId: String }
                struct Creada: Decodable { var id: String }
                struct M: Encodable { var texto: String }
                let conv: Creada = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Conv(contactoId: c))
                ir = AChat(id: conv.id)
                do {
                    try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(conv.id)/mensajes", M(texto: t))
                } catch let e as ErrorApi where e.codigo == "fuera_de_ventana" {
                    // Fuera de las 24 h sólo sale una plantilla: se abre la conversación para elegirla.
                    estado.sugerir("Pasaron más de 24 h: hay que retomar con una plantilla", "Abrir la conversación", AChat(id: conv.id))
                    return
                }
            }
            try await estado.api.hacer("POST", "/v1/revision/\(b.id)/usado")
            usados.insert(b.id)
            let listo = b.tipo == "descripcion" ? "Quedó en la ficha" : b.tipo == "nota" ? "Quedó como nota" : "Mandado a \(b.contactoNombre ?? "el contacto")"
            if let ir { estado.sugerir(listo, "Ver", ir) } else { estado.avisar(listo) }
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// Descartar espera los segundos del aviso (Deshacer) antes de mandarse.
    private func descartar(_ b: BorradorIA) {
        ocultos.insert(b.id)
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            do {
                try await estado.api.hacer("DELETE", "/v1/revision/\(b.id)")
                estado.version += 1
            } catch {
                ocultos.remove(b.id)
                estado.avisar("No se descartó", ok: false)
            }
        }
        estado.avisar("Borrador descartado") { tarea.cancel(); ocultos.remove(b.id) }
    }
}

/// Corregir el borrador: el asunto (si es un mail) y el texto.
struct CorregirBorrador: View {
    @Environment(\.dismiss) private var cerrar
    var b: BorradorIA
    var guardar: (String?, String) -> Void
    @State private var asunto = ""
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(RevisionIA.aspecto(b).titulo).estilo(.footnote).foregroundStyle(C.texto2) }
                if b.canal == "email" { Section("Asunto") { TextField("Asunto", text: $asunto) } }
                Section("Texto") { TextField("Texto", text: $texto, axis: .vertical).lineLimit(6...16) }
            }
            .navigationTitle("Corregir el borrador").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar(asunto.nonEmpty, texto); cerrar() }.disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { asunto = b.asunto ?? ""; texto = b.texto ?? "" }
        }
    }
}
