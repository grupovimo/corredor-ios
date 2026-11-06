import SwiftUI

/// El alta rápida de la agenda (la hoja del celular de la web, lib/crm/AltaRapida.svelte): Visita,
/// Tarea o Recordatorio; «visita Gorriti 5530 con Inés el sábado a las 11» escrito o dictado, lo
/// entendido marcado en colores (verde la propiedad, azul la persona, oro el cuándo), quién la hace
/// (el agente del contacto o de la propiedad) y el aviso si ya tiene algo a esa hora.
struct AltaRapidaCita: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    /// Lo que viene elegido de antes (la ficha de un contacto, una operación, un día y una hora).
    var propiedadPrevia: Propiedad? = nil
    var contactoPrevio: String? = nil
    var operacion: String? = nil
    var diaPrevio: String? = nil
    var horaPrevia: String? = nil
    var clasePrevia = "visita"
    /// Pasar al formulario campo por campo.
    var alFormulario: () -> Void

    @State private var texto = ""
    @State private var clase = "visita"
    @State private var props: [Entender.Opcion] = []
    @State private var contactos: [Entender.Opcion] = []
    @State private var equipo: [Miembro] = []
    @State private var citasDelDia: [Cita] = []
    @State private var elAgente: String?
    @State private var guardando = false
    @State private var dictado = Dictado()
    @State private var base = ""

    private var tipoForzado: String { clase == "visita" ? "visita" : "otro" }
    private var e: Entender.Entendido { Entender.entender(texto, propiedades: props, contactos: contactos, tipo: tipoForzado) }
    private var contacto: Entender.Opcion? { e.contacto ?? contactoPrevio.flatMap { id in contactos.first { $0.id == id } } }
    private var propiedad: Entender.Opcion? {
        e.propiedad ?? propiedadPrevia.map { Entender.Opcion(id: $0.id, titulo: $0.nombre, agenteId: $0.agenteId, barrio: $0.barrio) }
    }
    private var dia: String? { e.dia ?? diaPrevio }
    private var hora: String? { e.hora ?? horaPrevia }
    private var yo: String { estado.usuario?.id ?? "" }
    private var agente: String { elAgente ?? contacto?.agenteId ?? propiedad?.agenteId ?? yo }

    private func nombreDe(_ id: String?) -> String {
        if id == yo { return "Vos" }
        return Charla.primerNombre(equipo.first { $0.usuarioId == id }?.completo)
    }

    private var fin: String? {
        guard let hora else { return nil }
        let p = hora.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        let t = p[0] * 60 + p[1] + e.duracionMin
        return String(format: "%02d:%02d", (t / 60) % 24, t % 60)
    }

    private var cuando: String {
        guard let dia else { return "" }
        let hoy = Formato.diaISO(Date())
        let d: String
        if dia == hoy { d = "hoy" } else if dia == Entender.sumar(hoy, 1) { d = "mañana" }
        else if let f = Fecha.dia(dia) { d = "\(AgendaRaiz.nombreDia(f).prefix(3)) \(Calendar.current.component(.day, from: f))" } else { d = dia }
        return [d, hora.flatMap { h in fin.map { "\(h) a \($0)" } }].compactMap { $0 }.joined(separator: " · ")
    }

    /// ¿Quien la hace ya tiene algo a esa hora?
    private var choque: Cita? {
        guard let dia, let hora, let ini = Entender.instante(dia, hora) else { return nil }
        let f = ini.addingTimeInterval(Double(e.duracionMin * 60))
        return citasDelDia.first { $0.agenteId == agente && $0.estado != "cancelada" && $0.empiezaEn < f && $0.terminaEn > ini }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Text("Agendar").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Segmentado(opciones: [("visita", "Visita"), ("tarea", "Tarea"), ("recordatorio", "Recordatorio")], elegido: $clase)
            campo
            filas
            Button("Elegir campo por campo") { alFormulario() }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button {
                    if dictado.grabando { dictado.parar() } else { base = texto; dictado.empezar(base: texto) }
                } label: {
                    Image(systemName: "mic.fill").font(.system(size: 24)).foregroundStyle(dictado.grabando ? .white : C.accion)
                        .frame(width: 52, height: 52).background(dictado.grabando ? C.error : C.hundida, in: Circle())
                }
                .accessibilityLabel(dictado.grabando ? "Parar el dictado" : "Dictar")
                Button(guardando ? "Agendando…" : "Agendar") { Task { await agendar() } }
                    .buttonStyle(BotonPrincipal()).disabled(guardando)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .onAppear { clase = clasePrevia }
        .task { await cargarOpciones() }
        .task(id: dia ?? "") { await cargarDia() }
        .onChange(of: dictado.texto) { _, t in if dictado.grabando { texto = [base, t].filter { !$0.isEmpty }.joined(separator: " ") } }
        .onDisappear { dictado.parar() }
    }

    /// El texto con lo entendido pintado, y el campo para escribir.
    private var campo: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("visita Gorriti 5530 con Inés el sábado a las 11", text: $texto, axis: .vertical)
                .lineLimit(2...4).estilo(.body).campoCorredor()
                .accessibilityLabel("Qué, con quién y cuándo")
            if !texto.isEmpty { marcado.estilo(.subhead).accessibilityHidden(true) }
        }
    }

    private var marcado: Text {
        e.partes.reduce(Text("")) { acc, p in
            switch p.clase {
            case .prop?: return acc + Text(p.t).bold().foregroundColor(C.okTinta)
            case .persona?: return acc + Text(p.t).bold().foregroundColor(C.azulTinta)
            case .cuando?: return acc + Text(p.t).bold().foregroundColor(C.avisoTinta)
            case nil: return acc + Text(p.t).foregroundColor(C.texto2)
            }
        }
    }

    private var filas: some View {
        VStack(spacing: 0) {
            fila("house", propiedad.map { [$0.titulo, $0.barrio].compactMap { $0 }.joined(separator: " · ") } ?? "Sin propiedad", primera: true)
            HStack(spacing: 12) {
                Image(systemName: "person").foregroundStyle(C.accion).frame(width: 22)
                Text(contacto?.titulo ?? "Sin contacto").estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                if contacto != nil && clase == "visita" { Text("le mandamos confirmación").estilo(.footnote).foregroundStyle(C.texto3) }
            }
            .padding(.horizontal, 14).frame(minHeight: 46)
            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            fila("clock", cuando.isEmpty ? "Decí el día y la hora" : Formato.mayuscula(cuando) + (agente == yo ? "" : " · \(nombreDe(agente))"), primera: false)
            if let c = choque {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(C.avisoTinta)
                    Text("\(nombreDe(agente)) tiene otra \(c.propiedadTitulo.map { "cosa a esa hora en \(String($0.split(separator: ",").first ?? ""))" } ?? "cosa a esa hora").\(agente != yo ? " ¿La hacés vos?" : "")")
                        .estilo(.footnote).foregroundStyle(C.texto)
                    Spacer()
                    if agente != yo { Button("Sí") { elAgente = yo }.buttonStyle(BotonTonal()) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(C.avisoFondo)
            }
        }
        .background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private func fila(_ i: String, _ t: String, primera: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: i).foregroundStyle(C.accion).frame(width: 22)
            Text(t).estilo(.body16).foregroundStyle(C.texto).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cargarOpciones() async {
        struct P: Decodable { var id: String; var titulo: String?; var direccion: String?; var estado: String?; var agenteId: String?; var barrio: String? }
        struct Ct: Decodable { var id: String; var nombre: String; var agenteId: String? }
        let ps: [P] = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "200"), .init(name: "orden", value: "actualizada")])) ?? []
        props = ps.filter { $0.estado != "suspendida" }.map { Entender.Opcion(id: $0.id, titulo: $0.titulo ?? $0.direccion ?? "", agenteId: $0.agenteId, barrio: $0.barrio) }
        let cs: [Ct] = (try? await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "200")])) ?? []
        contactos = cs.map { Entender.Opcion(id: $0.id, titulo: $0.nombre, agenteId: $0.agenteId, barrio: nil) }
        equipo = (try? await estado.api.get("/v1/equipo")) ?? []
    }

    private func cargarDia() async {
        guard let dia else { citasDelDia = []; return }
        citasDelDia = (try? await estado.api.get("/v1/agenda", query: [.init(name: "desde", value: dia), .init(name: "hasta", value: dia), .init(name: "limite", value: "500")])) ?? []
    }

    private func agendar() async {
        dictado.parar()
        guard !texto.trimmingCharacters(in: .whitespaces).isEmpty || propiedad != nil, let dia, let hora, let empieza = Entender.instante(dia, hora) else {
            estado.avisar(dia == nil ? "Decí qué día (por ejemplo, «el sábado a las 11»)." : "Decí a qué hora (por ejemplo, «a las 11»).", ok: false)
            return
        }
        let tipo = tipoForzado
        let nombres = ["visita": "Visita", "tasacion": "Tasación", "firma": "Firma", "llamado": "Llamar", "otro": ""]
        var titulo = propiedad.map { "\(nombres[tipo] ?? "") \(String($0.titulo.split(separator: ",").first ?? ""))".trimmingCharacters(in: .whitespaces) } ?? e.titulo
        if titulo.isEmpty { titulo = "Visita" }
        if clase == "recordatorio" { titulo = "Recordatorio: \(titulo)" }
        struct Cuerpo: Encodable {
            var tipo: String; var titulo: String; var empiezaEn: Date; var duracionMin: Int
            var propiedadId: String?; var contactoId: String?; var operacionId: String?; var agenteId: String?; var recordar: Bool
        }
        struct Creada: Decodable { var id: String }
        guardando = true
        defer { guardando = false }
        do {
            let c: Creada = try await estado.api.enviar("POST", "/v1/agenda", Cuerpo(tipo: tipo, titulo: String(titulo.prefix(160)), empiezaEn: empieza, duracionMin: e.duracionMin,
                                                                                propiedadId: propiedad?.id, contactoId: contacto?.id, operacionId: operacion,
                                                                                agenteId: agente.isEmpty ? nil : agente, recordar: tipo == "visita" && contacto != nil))
            let texto = "Agendada · \(cuando)"
            estado.avisar(texto) {
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/agenda/\(c.id)")
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            Haptico.exito()
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// «Licencias y ausencias» desde la agenda: quién falta y hasta cuándo. Cada uno carga la suya; la
/// dueña, la de cualquiera. Quitar es al toque, con «Deshacer».
struct LicenciasAgenda: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var licencias: [Licencia]?
    @State private var quitadas: Set<String> = []
    @State private var equipo: [Miembro] = []
    @State private var quien = ""
    @State private var tipo = "licencia"
    @State private var desde = Date()
    @State private var hasta = Date()
    @State private var error: String?
    @State private var guardando = false

    static let tipos = [("licencia", "Licencia"), ("vacaciones", "Vacaciones"), ("enfermedad", "Enfermedad"), ("tramite", "Trámite")]
    static let nombre = ["licencia": "De licencia", "vacaciones": "De vacaciones", "enfermedad": "Por enfermedad", "tramite": "Trámite"]

    private var yo: String { estado.usuario?.id ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Grabber().frame(maxWidth: .infinity)
                Label("Licencias y ausencias", systemImage: "beach.umbrella").estilo(.tituloHojaChico).foregroundStyle(C.texto)
                Text(Formato.sinViudas("Quién falta y hasta cuándo. El Inicio lo muestra en «El equipo hoy».")).estilo(.subhead).foregroundStyle(C.texto2)
                lista
                if estado.escribe { alta }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .task { await cargar() }
    }

    @ViewBuilder
    private var lista: some View {
        let visibles = (licencias ?? []).filter { !quitadas.contains($0.id) }
        if licencias == nil {
            EsqueletoFilas(filas: 2, miniatura: 36)
        } else if !visibles.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(visibles.enumerated()), id: \.element.id) { i, l in
                    HStack(spacing: 12) {
                        AvatarIniciales(nombre: l.usuarioNombre ?? "", tam: 36, fondo: C.errorFondo, tinta: C.errorTinta)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.usuarioId == yo ? "Vos" : (l.usuarioNombre ?? "")).estilo(.filaLista).foregroundStyle(C.texto)
                            Text("\(Self.nombre[l.tipo ?? ""] ?? "De licencia") · \(l.desde == l.hasta ? "el \(Self.corta(l.desde))" : "del \(Self.corta(l.desde)) al \(Self.corta(l.hasta))")")
                                .estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        if estado.esDuenio || l.usuarioId == yo {
                            Button("Quitar") { Task { await quitar(l) } }.buttonStyle(BotonTonal())
                        }
                    }
                    .padding(.horizontal, 12).frame(minHeight: 56)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(14)
        }
    }

    private var alta: some View {
        VStack(alignment: .leading, spacing: 12) {
            if estado.esDuenio {
                Etiquetado("Quién") {
                    Picker("Quién", selection: $quien) {
                        ForEach(equipo.filter { $0.rol != "lector" || $0.usuarioId == yo }) { p in
                            Text(p.usuarioId == yo ? "\(p.completo) (vos)" : p.completo).tag(p.usuarioId)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Etiquetado("Qué") { Segmentado(opciones: Self.tipos, elegido: $tipo) }
            HStack(spacing: 12) {
                Etiquetado("Desde") { DatePicker("Desde", selection: $desde, displayedComponents: .date).labelsHidden() }
                Etiquetado("Hasta") { DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date).labelsHidden() }
            }
            if let error { MensajeError(texto: error) }
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button(guardando ? "Cargando…" : "Cargar") { Task { await guardar() } }.buttonStyle(BotonPrincipal()).disabled(guardando)
            }
        }
    }

    static func corta(_ d: String) -> String { Fecha.dia(d).map { Formato.dia($0) } ?? d }

    private func cargar() async {
        let hoy = Formato.diaISO(Date())
        let l: [Licencia] = (try? await estado.api.get("/v1/licencias")) ?? []
        licencias = l.filter { $0.hasta >= hoy }
        equipo = (try? await estado.api.get("/v1/equipo")) ?? []
        if quien.isEmpty { quien = yo }
    }

    private struct Cuerpo: Encodable { var usuarioId: String; var tipo: String; var desde: String; var hasta: String; var nota: String? }

    private func guardar() async {
        let d = Formato.diaISO(desde), h = Formato.diaISO(hasta)
        guard h >= d else { error = "La vuelta tiene que ser después de la salida."; return }
        guardando = true
        defer { guardando = false }
        do {
            let l: Licencia = try await estado.api.enviar("POST", "/v1/licencias", Cuerpo(usuarioId: estado.esDuenio ? quien : yo, tipo: tipo, desde: d, hasta: h))
            let quienTexto = l.usuarioId == yo ? "Quedaste" : "\(Charla.primerNombre(l.usuarioNombre)) queda"
            estado.avisar("\(quienTexto) \((Self.nombre[l.tipo ?? ""] ?? "de licencia").lowercased()) hasta el \(Self.corta(l.hasta))") {
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)")
                        estado.version += 1
                    } catch { estado.avisar("No se guardó", ok: false) }
                }
            }
            estado.version += 1
            cerrar()
        } catch { self.error = Estado.texto(error) }
    }

    private func quitar(_ l: Licencia) async {
        quitadas.insert(l.id)
        do {
            try await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)")
            estado.avisar("Quitaste la licencia de \(l.usuarioId == yo ? "vos" : Charla.primerNombre(l.usuarioNombre))") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/licencias", Cuerpo(usuarioId: l.usuarioId, tipo: l.tipo ?? "licencia", desde: l.desde, hasta: l.hasta, nota: l.nota))
                        quitadas.remove(l.id)
                        await cargar()
                        estado.version += 1
                    } catch { estado.avisar("No se guardó", ok: false) }
                }
            }
            estado.version += 1
        } catch {
            quitadas.remove(l.id)
            estado.avisarReintentar("No se guardó") { Task { await quitar(l) } }
        }
    }
}
