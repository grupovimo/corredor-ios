import SwiftUI

// MARK: - Lo que contesta la API (dominio/asistente; web lib/asistente/charla.ts)

/// GET /v1/asistente: si hay IA para esta persona (la función IA del plan) y qué preguntar para arrancar.
struct EstadoAsistente: Codable, Hashable {
    var ia: Bool
    var aviso: String?
    var sugerencias: [String]?
}

/// Un resultado con su página del panel (`/contratos/<id>`, `/cobranzas?registrar=1&contrato=<id>`…).
struct ItemAsistente: Codable, Hashable {
    var tipo: String
    var id: String
    var titulo: String
    var subtitulo: String?
    var ruta: String
}

/// Algo que el asistente propone escribir: no existe hasta que la persona lo confirma (va tal cual a
/// POST /v1/asistente/confirmar).
struct PropuestaAsistente: Codable, Hashable {
    var herramienta: String
    var titulo: String
    var para: String?
    var texto: String?
    var args: [String: JSONLibre]
}

/// POST /v1/asistente.
struct RespuestaAsistente: Codable, Hashable {
    var texto: String
    /// motor: reglas propias, sin IA · ia · cache: la misma pregunta hace un rato · sin_ia
    var origen: String
    var resultados: [ItemAsistente]?
    var propuestas: [PropuestaAsistente]?
    /// Por qué no contestó la IA (tope, plan, no respondió).
    var aviso: String?
}

/// Un turno en pantalla. Las respuestas llevan sus propuestas con su estado (y a dónde ir después de confirmar).
struct TurnoAsistente: Identifiable {
    enum Rol { case persona, asistente, error }
    enum EstadoPropuesta { case pendiente, confirmando, hecha, descartada }
    struct Propuesta: Identifiable {
        var p: PropuestaAsistente
        var estado: EstadoPropuesta = .pendiente
        var ir: AnyHashable?
        /// La Idempotency-Key: el doble toque no la crea dos veces.
        var envio = UUID().uuidString
        var id: String { envio }
    }

    var id: Int
    var rol: Rol
    var texto: String
    /// Lo que se preguntó (para «Probar de nuevo» en un error).
    var pregunta = ""
    var respuesta: RespuestaAsistente?
    var propuestas: [Propuesta] = []
}

// MARK: - Pantalla

/// El asistente (panel web /asistente): se pregunta como se diría («¿qué contratos ajustan este mes?»).
/// Contesta primero el motor de Corredor (al instante, sin IA) y, si hace falta y el plan la trae, la IA
/// con lo que el rol deja ver. Lo que propone escribir queda como propuesta: se crea sólo al tocar
/// «Confirmar» y va a los borradores para revisar (no se manda nada). La charla vive en la pantalla: el
/// servidor no la guarda; cada pregunta lleva los últimos turnos.
struct Asistente: View {
    @Environment(Estado.self) private var estado
    /// Con algo escrito: desde la búsqueda arranca preguntando eso; desde un link de afuera
    /// (`/asistente?q=`) sólo lo deja escrito, para que nadie gaste la IA con un link.
    var pregunta = ""
    var enviar = true
    @State private var info: EstadoAsistente?
    @State private var turnos: [TurnoAsistente] = []
    @State private var texto = ""
    @State private var pensando = false
    @State private var proximo = 0
    @State private var arranco = false
    @FocusState private var foco: Bool

    /// Los mismos topes que la API (ia.MaxTurnos y ia.MaxLargoTurno).
    static let maxTurnos = 8
    static let maxLargo = 600

    /// Mientras no llega la API, las que contesta el motor sin IA (dominio/asistente · SugerenciasMotor):
    /// nunca se ofrece algo que termine en «no lo puedo contestar».
    static let sugerenciasBase = [
        "¿Qué contratos ajustan este mes?", "¿Quiénes deben el alquiler?", "¿Qué tengo hoy?", "Contratos por vencer",
        "Borradores para revisar",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { lector in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        cabeza
                        if turnos.isEmpty { arranque }
                        ForEach(turnos) { t in turno(t) }
                        if pensando {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Buscando en Corredor…").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            .padding(.horizontal, 4)
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                // La respuesta se lee desde arriba: con un turno del asistente se va a su comienzo; con la
                // pregunta o «Buscando…», al final.
                .onChange(of: turnos.count) { _, _ in
                    withAnimation {
                        if let t = turnos.last, t.rol != .persona { lector.scrollTo(t.id, anchor: .top) } else { lector.scrollTo("fin", anchor: .bottom) }
                    }
                }
                .onChange(of: pensando) { _, p in if p { withAnimation { lector.scrollTo("fin", anchor: .bottom) } } }
            }
            entrada
        }
        .pantallaApilada("Asistente")
        .task {
            guard !arranco else { return }
            arranco = true
            // En paralelo y sin atar a la vista: si se cambia de pestaña mientras contesta, la respuesta
            // igual llega (una Task estructurada se cancelaba y dejaba la pregunta sin respuesta).
            Task { if info == nil { info = try? await estado.api.get("/v1/asistente") } }
            if let q = pregunta.nonEmpty {
                if enviar { Task { await preguntar(q) } } else { texto = q }
            }
        }
    }

    // MARK: Piezas

    private var cabeza: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Formato.sinViudas("Preguntá como lo dirías. Lo que propongo escribir lo confirmás vos."))
                .estilo(.subhead).foregroundStyle(C.texto2)
            if let i = info, !i.ia, let a = i.aviso?.nonEmpty {
                Label { Text(Formato.sinViudas(a)) } icon: { Image(systemName: "info.circle") }
                    .estilo(.footnote).foregroundStyle(C.avisoTinta)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(C.avisoFondo, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Para empezar: las sugerencias de la API, de a una por fila. Debajo de una respuesta sin IA
    /// vuelven como «Probá con» (tocables, en vez de una lista escrita).
    private var arranque: some View { sugerencias("PARA EMPEZAR") }

    private func sugerencias(_ titulo: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                let ss = info?.sugerencias?.nonEmptyLista ?? Self.sugerenciasBase
                ForEach(Array(ss.enumerated()), id: \.element) { i, s in
                    Button { Task { await preguntar(s) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(C.accion).frame(width: 24)
                            Text(Formato.sinViudas(s)).estilo(.filaLista).foregroundStyle(C.texto).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Chevron()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .disabled(pensando)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
        }
    }

    @ViewBuilder
    private func turno(_ t: TurnoAsistente) -> some View {
        switch t.rol {
        case .persona:
            HStack {
                Spacer(minLength: 60)
                Text(t.texto).estilo(.body16).foregroundStyle(C.texto)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.tema(0xDCEBE3, 0x1F3B33),
                                in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
            }
        case .error:
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(Formato.sinViudas(t.texto)) } icon: { Image(systemName: "exclamationmark.icloud") }
                    .estilo(.footnote).foregroundStyle(C.errorTinta)
                Button("Probar de nuevo") { Task { await preguntar(t.pregunta) } }
                    .font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(minHeight: 44)
                    .disabled(pensando)
            }
            .padding(.horizontal, 4)
        case .asistente:
            if let r = t.respuesta { respuesta(t, r) }
        }
    }

    private func respuesta(_ t: TurnoAsistente, _ r: RespuestaAsistente) -> some View {
        let o = Self.origen(r, hayIA: info?.ia ?? true)
        let pendientes = t.propuestas.filter { $0.estado == .pendiente }.count
        return VStack(alignment: .leading, spacing: 10) {
            if r.texto.nonEmpty != nil {
                Text(Self.sinViudasPorLinea(r.texto)).estilo(.body16).foregroundStyle(C.texto).textSelection(.enabled)
                    .padding(.horizontal, 4)
            }
            if let rs = r.resultados, !rs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rs.enumerated()), id: \.offset) { i, it in
                        Button { abrir(it) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Formato.sinViudas(it.titulo)).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
                                    if let s = it.subtitulo?.nonEmpty { Text(Formato.sinViudas(s)).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2) }
                                }
                                Spacer(minLength: 0)
                                Chevron()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta(16)
            }
            ForEach(t.propuestas) { p in
                if p.estado != .descartada { tarjeta(t, p) }
            }
            if pendientes > 1 && estado.escribe {
                Button("Confirmar las \(pendientes)") { Task { await confirmarTodas(t.id) } }.buttonStyle(BotonHundido())
            }
            // texto2: el pie dice por qué no contestó la IA, es información (texto3 no llega a AA).
            Label { Text(Formato.sinViudas(o.1)) } icon: { Image(systemName: o.0) }
                .estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
            if r.origen == "sin_ia", r.resultados?.isEmpty ?? true, t.id == turnos.last?.id {
                sugerencias("PROBÁ CON").padding(.top, 4)
            }
        }
    }

    /// La propuesta como en «Borradores de tu IA»: qué es, para quién, el texto y Confirmar / Descartar.
    private func tarjeta(_ t: TurnoAsistente, _ p: TurnoAsistente.Propuesta) -> some View {
        let a = Self.queHace(p.p)
        let burbuja = p.p.herramienta == "mensajes_crear_borrador" && p.p.args["canal"]?.texto != "email"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconoTono(icono: a.icono, tono: a.tono, tam: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Formato.sinViudas(a.titulo)).estilo(.filaLista).foregroundStyle(C.texto)
                    Text(Formato.sinViudas(p.estado == .hecha ? "Quedó para revisar: todavía no se mandó nada" : "Propuesta: no se crea hasta que la confirmes"))
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            if let x = p.p.texto?.nonEmpty {
                Text(Self.sinViudasPorLinea(x)).estilo(.texto14).foregroundStyle(C.texto)
                    .padding(burbuja ? 12 : 0)
                    .background(burbuja ? C.okFondo : .clear, in: .rect(cornerRadius: 14, style: .continuous))
            }
            if p.estado == .hecha {
                if let ir = p.ir { Button("Ver para revisar") { estado.abrir(ir) }.buttonStyle(BotonHundido()) }
            } else if estado.escribe {
                HStack(spacing: 8) {
                    Button(p.estado == .confirmando ? "Guardando…" : "Confirmar") { Task { await confirmar(t.id, p.id) } }
                        .buttonStyle(BotonAccion()).disabled(p.estado == .confirmando)
                    Button("Descartar") { descartar(t.id, p.id) }.buttonStyle(BotonTexto(alto: 44))
                }
            }
        }
        .padding(14).tarjeta()
    }

    private var entrada: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("¿Qué contratos ajustan este mes?", text: $texto, axis: .vertical).estilo(.body16).lineLimit(1...6)
                .focused($foco)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(C.superficie, in: .rect(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(C.linea2, lineWidth: 0.5))
                .accessibilityLabel("Tu pregunta")
            Button { mandar() } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(C.sobreAccion)
                    .frame(width: 36, height: 36).background(C.accion, in: Circle())
                    .frame(width: 40, height: 40)
            }
            .disabled(pensando || texto.nonEmpty == nil)
            .opacity(pensando || texto.nonEmpty == nil ? 0.5 : 1)
            .accessibilityLabel("Preguntar")
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Acciones

    private func mandar() {
        let q = texto
        Task { await preguntar(q) }
    }

    private func preguntar(_ q: String) async {
        let q = String(q.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !q.isEmpty, !pensando else { return }
        struct Cuerpo: Encodable {
            struct T: Encodable { var rol: String; var texto: String }
            var pregunta: String
            var historial: [T]
        }
        let previos = Self.historial(turnos).map { Cuerpo.T(rol: $0.rol, texto: $0.texto) }
        turnos.append(TurnoAsistente(id: siguiente(), rol: .persona, texto: q))
        texto = ""
        pensando = true
        defer { pensando = false }
        do {
            let r: RespuestaAsistente = try await estado.api.enviar("POST", "/v1/asistente", Cuerpo(pregunta: q, historial: previos))
            turnos.append(TurnoAsistente(id: siguiente(), rol: .asistente, texto: r.texto, respuesta: r,
                                         propuestas: (r.propuestas ?? []).map { TurnoAsistente.Propuesta(p: $0) }))
        } catch is CancellationError {
            return
        } catch let e as ErrorApi where e.estado == 402 {
            // Sin plan: lleva a «Ver planes», no a un «Probar de nuevo» que va a fallar siempre.
            estado.avisar(e)
        } catch {
            let e = error as? ErrorApi
            let m = e == nil || e?.sinConexion == true ? "No pude contestar. Revisá la señal y probá de nuevo." : (e?.detalle.nonEmpty ?? e?.titulo ?? "")
            turnos.append(TurnoAsistente(id: siguiente(), rol: .error, texto: m, pregunta: q))
        }
    }

    private func siguiente() -> Int {
        proximo += 1
        return proximo
    }

    /// Confirmar: POST /v1/asistente/confirmar. Deja el borrador para revisar (nada se manda) y el aviso lleva ahí.
    private func confirmar(_ turno: Int, _ id: String) async {
        guard let ti = turnos.firstIndex(where: { $0.id == turno }), let pi = turnos[ti].propuestas.firstIndex(where: { $0.id == id }),
              turnos[ti].propuestas[pi].estado == .pendiente else { return }
        let p = turnos[ti].propuestas[pi]
        turnos[ti].propuestas[pi].estado = .confirmando
        struct Cuerpo: Encodable { var herramienta: String; var args: [String: JSONLibre] }
        struct Hecho: Decodable { var resumen: String?; var datos: JSONLibre? }
        do {
            let h: Hecho = try await estado.api.enviar("POST", "/v1/asistente/confirmar", Cuerpo(herramienta: p.p.herramienta, args: p.p.args), envio: p.envio)
            let ir = Self.despues(p.p, h.datos)
            if let ti = turnos.firstIndex(where: { $0.id == turno }), let pi = turnos[ti].propuestas.firstIndex(where: { $0.id == id }) {
                turnos[ti].propuestas[pi].estado = .hecha
                turnos[ti].propuestas[pi].ir = ir
            }
            Haptico.exito()
            estado.sugerir(Self.queHace(p.p).listo, "Ver", ir)
            estado.version += 1
        } catch {
            if let ti = turnos.firstIndex(where: { $0.id == turno }), let pi = turnos[ti].propuestas.firstIndex(where: { $0.id == id }) {
                turnos[ti].propuestas[pi].estado = .pendiente
            }
            estado.avisar(error)
        }
    }

    private func confirmarTodas(_ turno: Int) async {
        guard let t = turnos.first(where: { $0.id == turno }) else { return }
        for p in t.propuestas where p.estado == .pendiente { await confirmar(turno, p.id) }
    }

    /// Descartar no va a la API (la propuesta no existe todavía): sólo se saca, con «Deshacer».
    private func descartar(_ turno: Int, _ id: String) {
        func poner(_ e: TurnoAsistente.EstadoPropuesta) {
            if let ti = turnos.firstIndex(where: { $0.id == turno }), let pi = turnos[ti].propuestas.firstIndex(where: { $0.id == id }) {
                turnos[ti].propuestas[pi].estado = e
            }
        }
        poner(.descartada)
        estado.avisar("Propuesta descartada") { poner(.pendiente) }
    }

    /// Un resultado abre su pantalla de la app (las rutas son las del panel).
    private func abrir(_ it: ItemAsistente) {
        if let d = Ruta(texto: it.ruta)?.destino { estado.abrir(d) }
    }

    // MARK: Cuentas (charla.ts)

    /// El historial para la API: los últimos turnos de texto, recortados; los errores no cuentan.
    static func historial(_ turnos: [TurnoAsistente]) -> [(rol: String, texto: String)] {
        var out: [(rol: String, texto: String)] = []
        for t in turnos {
            switch t.rol {
            case .persona: out.append((rol: "persona", texto: String(t.texto.prefix(maxLargo))))
            case .asistente: if t.texto.nonEmpty != nil { out.append((rol: "asistente", texto: String(t.texto.prefix(maxLargo)))) }
            case .error: break
            }
        }
        return Array(out.suffix(maxTurnos))
    }

    struct QueHace { var icono: String; var tono: Tono; var titulo: String; var listo: String }

    /// Qué hace la propuesta, en criollo (los íconos de «Borradores de tu IA»).
    static func queHace(_ p: PropuestaAsistente) -> QueHace {
        let para = p.para?.nonEmpty.map { " para \($0)" } ?? ""
        switch p.herramienta {
        case "mensajes_crear_borrador":
            return p.args["canal"]?.texto == "email"
                ? QueHace(icono: "envelope", tono: .azul, titulo: "Mail\(para)", listo: "Quedó el mail para revisar")
                : QueHace(icono: "bubble.left", tono: .verde, titulo: "WhatsApp\(para)", listo: "Quedó el mensaje para revisar")
        case "propiedad_borrador_descripcion":
            return QueHace(icono: "doc.text", tono: .oro, titulo: "Descripción\(para)", listo: "Quedó la descripción para revisar")
        case "notas_crear_borrador":
            return QueHace(icono: "note.text", tono: .neutro, titulo: "Nota\(para)", listo: "Quedó la nota para revisar")
        case "propiedad_crear_borrador":
            return QueHace(icono: "house", tono: .oro, titulo: "Propiedad nueva en borrador", listo: "Quedó en los borradores de propiedades")
        default:
            return QueHace(icono: "square.and.pencil", tono: .neutro, titulo: p.titulo, listo: "Listo")
        }
    }

    /// A dónde ir después de confirmar: el borrador del alta, o ese borrador en «Borradores de tu IA».
    static func despues(_ p: PropuestaAsistente, _ datos: JSONLibre?) -> AnyHashable {
        let id = datos?["id"]?.texto?.nonEmpty
        if p.herramienta == "propiedad_crear_borrador" { return AnyHashable(AAltaPropiedad(borrador: id)) }
        if let id { return AnyHashable(ARevisionIds(ids: id)) }
        return AnyHashable(ASeccion(clave: "revision"))
    }

    /// De dónde salió la respuesta: el ícono y el texto de abajo. Si el plan no trae IA, la cabeza ya lo
    /// dice: el pie queda en «Sin IA». Con IA en el plan (un tope, un corte), el pie dice el motivo.
    static func origen(_ r: RespuestaAsistente, hayIA: Bool = true) -> (String, String) {
        switch r.origen {
        case "motor": return ("bolt", "Con los datos de Corredor")
        case "sin_ia": return ("info.circle", hayIA ? (r.aviso?.nonEmpty ?? "Sin IA") : "Sin IA")
        default: return ("sparkles", "Con IA · puede equivocarse")
        }
    }

    /// Sin palabras solas en el último renglón de cada párrafo (sinViudas sólo mira el final).
    static func sinViudasPorLinea(_ t: String) -> String {
        t.components(separatedBy: "\n").map { Formato.sinViudas($0) }.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    var nonEmptyLista: [String]? { isEmpty ? nil : self }
}
