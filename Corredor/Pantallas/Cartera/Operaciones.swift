import SwiftUI

/// 9A–9B Tablero de operaciones, como el del panel (18C): las cuatro columnas como pestañas con su
/// cuenta y su total, el filtro por agente y por tipo, «N abiertas · USD X en juego», la nota de cada
/// tarjeta, «Pasar a …» (o deslizar a la derecha), mantener apretado para «Mover a…», la seña al llegar
/// a Reserva, «Se cayó» con su motivo, el aviso si otro la movió antes y las caídas con «Reabrir».
struct Operaciones: View {
    @Environment(Estado.self) private var estado
    @State private var columna = 0
    @State private var caidasVista = false
    @State private var agente = ""
    @State private var tipo = ""
    @State private var ops: [Operacion]?
    @State private var caidas: [Operacion] = []
    @State private var equipo: [Miembro] = []
    @State private var error: ErrorApi?
    @State private var nueva = false
    @State private var cayendo: Operacion?
    @State private var pideSena: String?
    @State private var senaValor = ""
    @State private var conflicto: Conflicto?
    @State private var sinPermiso: Operacion?

    struct Conflicto { var prop: String; var quien: String?; var hasta: String?; var mio: String; var id: String }

    private var puedeMover: Bool { estado.escribe }
    private var visibles: [Operacion] {
        (ops ?? []).filter { agente.isEmpty || (agente == "libre" ? $0.agenteId == nil : $0.agenteId == agente) }
    }
    private var abiertas: [Operacion] { visibles.filter { $0.etapa != "cierre" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if ops != nil {
                    Text("\(Formato.numero(abiertas.count)) abiertas · \(Formato.plataCorta(Operacion.enJuego(abiertas), "USD")) en juego")
                        .estilo(.subhead).foregroundStyle(C.texto2).padding(.horizontal, 16)
                }
                filtros
                if let c = conflicto { avisoConflicto(c).padding(.horizontal, 16) }
                contenido
                if ops?.isEmpty == false { esteMes.padding(.horizontal, 16) }
            }
            .padding(.top, 8).padding(.bottom, 30)
        }
        .refreshable { await cargar() }
        .pantallaApilada(estado.rol == "agente" ? "Mis operaciones" : "Operaciones")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if puedeMover { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva operación") } }
        .task(id: "\(estado.version)-\(tipo)") { await cargar() }
        .sheet(isPresented: $nueva) { NuevaOperacion() }
        .sheet(item: $cayendo) { o in
            SeCayo(propiedad: String(o.nombre.split(separator: ",").first ?? ""), contacto: o.contactoNombre) { m in Task { await caer(o, m) } }
                .hojaTLW([.medium, .large])
        }
        .sheet(item: $sinPermiso) { o in hojaSinPermiso(o).hojaTLW([.medium]) }
    }

    // MARK: Filtros y pestañas

    private var filtros: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipAgente("", "Todos")
                    ForEach(equipo.filter { m in m.rol != "duenio" || (ops ?? []).contains { $0.agenteId == m.usuarioId } }) { p in
                        chipAgente(p.usuarioId, p.completo)
                    }
                    Rectangle().fill(C.linea2).frame(width: 1, height: 22).padding(.horizontal, 4)
                    ForEach([("", "Todo"), ("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporario")], id: \.0) { v, t in
                        ChipFiltro(texto: t, activo: tipo == v) { tipo = v }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Operacion.columnas.enumerated()), id: \.offset) { i, c in
                        let cards = visibles.filter { c.etapas.contains($0.etapa) }
                        ChipFiltro(texto: "\(c.texto) \(cards.count)", activo: columna == i && !caidasVista) { columna = i; caidasVista = false }
                    }
                    ChipFiltro(texto: "Caídas", activo: caidasVista) { caidasVista = true }
                }
                .padding(.horizontal, 16).padding(.vertical, 2)
            }
        }
    }

    private func chipAgente(_ id: String, _ nombre: String) -> some View {
        Button { Haptico.seleccion(); agente = id } label: {
            HStack(spacing: 6) {
                if id.isEmpty { Text("∗").font(Estilo.footnoteFuerte.font) } else {
                    Text(Formato.iniciales(nombre)).font(Estilo(tamano: 10, peso: .bold, relativo: .caption2).font).foregroundStyle(C.texto)
                        .frame(width: 22, height: 22).background(C.hundida, in: Circle())
                }
                Text(id.isEmpty ? nombre : Charla.primerNombre(nombre))
            }
            .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
            .foregroundStyle(agente == id ? C.sobreAccion : C.texto)
            .padding(.horizontal, 12).frame(height: 36)
            .background(agente == id ? C.accion : C.superficie, in: Capsule())
        }
        .buttonStyle(Presionable())
        .accessibilityAddTraits(agente == id ? .isSelected : [])
    }

    @ViewBuilder
    private var contenido: some View {
        if let ops {
            if caidasVista {
                listaCaidas.padding(.horizontal, 16)
            } else if ops.isEmpty && agente.isEmpty && tipo.isEmpty {
                EstadoVacio(icono: "rectangle.split.3x1", titulo: "Una operación nace cuando alguien pide visita", texto: "O la creás vos.",
                            accion: puedeMover ? ("Nueva operación", { nueva = true }) : nil,
                            secundaria: ("Ver contactos", { estado.abrir(AContactos()) }))
                    .padding(.top, 30)
            } else {
                let c = Operacion.columnas[columna]
                let cards = visibles.filter { c.etapas.contains($0.etapa) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(cards.count) · \(Formato.plataCorta(Operacion.enJuego(cards), "USD"))").estilo(.footnote).foregroundStyle(C.texto2)
                    if cards.isEmpty {
                        Text("Nada en \(c.texto).").estilo(.subhead).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(28)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    ForEach(cards) { o in tarjeta(o) }
                    if puedeMover && !cards.isEmpty {
                        Text("Mantené apretada una operación para moverla, o deslizala a la derecha para pasarla.").estilo(.footnote).foregroundStyle(C.texto3)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 16)
            }
        } else if let error {
            EstadoError(que: "las operaciones", error: error) { Task { await cargar() } }.padding(.top, 30)
        } else {
            EsqueletoFilas(filas: 3, miniatura: 56).padding(.horizontal, 16)
        }
    }

    // MARK: Tarjeta

    private func tarjeta(_ o: Operacion) -> some View {
        let col = Operacion.columna(o.etapa)
        let nota = o.nota()
        let derecha: [AccionFila] = []
        let izquierda: [AccionFila] = puedeMover && col < 3
            ? [AccionFila(texto: "Pasar", simbolo: "arrow.right", color: C.verde700) { Task { await mover(o, a: col + 1) } }] : []
        return VStack(spacing: 0) {
            FilaDeslizable(izquierda: izquierda, derecha: derecha) {
                Button { estado.abrir(AFichaOperacion(id: o.id)) } label: { cuerpoTarjeta(o, nota: nota) }
                    .buttonStyle(Presionable())
            }
            if pideSena == o.id { pedirSena(o) }
            if puedeMover {
                HStack(spacing: 0) {
                    if col < 3 {
                        Button { Task { await mover(o, a: col + 1) } } label: {
                            Label("Pasar a \(Operacion.columnas[col + 1].texto)", systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 46)
                        }
                    } else {
                        Text("Cerrada").frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(C.okTinta)
                    }
                    Rectangle().fill(C.linea).frame(width: 0.5)
                    Menu { menuItems(o) } label: { Image(systemName: "ellipsis").frame(width: 56, height: 46).foregroundStyle(C.texto2) }
                        .accessibilityLabel("Más de \(o.nombre)")
                }
                .font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font).foregroundStyle(C.accion)
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
        .tarjeta()
        .contextMenu { if puedeMover { menuItems(o) } }
    }

    private func cuerpoTarjeta(_ o: Operacion, nota: (String, Bool)) -> some View {
        HStack(spacing: 12) {
            Foto(url: urlFotoPropiedad(o.propiedadFotoId, api: estado.api.base, inmobiliaria: estado.sesion?.inmobiliariaId))
                .frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(o.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                if let t = o.tipoTexto.nonEmpty { Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto3) }
                Text([o.contactoNombre, (o.valor ?? 0) > 0 ? Formato.plata(o.valor ?? 0, o.moneda ?? "USD") : nil].compactMap { $0 }.joined(separator: " · "))
                    .estilo(.texto14).foregroundStyle(C.texto2).lineLimit(1)
                Text(nota.0).font(Estilo(tamano: 12, peso: nota.1 ? .bold : .regular, relativo: .caption).font).foregroundStyle(nota.1 ? C.avisoTinta : C.texto3)
            }
            Spacer()
            if let a = o.agenteNombre {
                Text(Formato.iniciales(a)).font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(C.texto)
                    .frame(width: 28, height: 28).background(C.hundida, in: Circle())
            } else {
                Circle().strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 28, height: 28).accessibilityLabel("Sin agente")
            }
        }
        .padding(12).contentShape(Rectangle())
    }

    /// «¿Cuánto dejó de seña?» en la misma tarjeta, al pasar a Reserva.
    private func pedirSena(_ o: Operacion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("¿Cuánto dejó de seña?").estilo(.subheadFuerte).foregroundStyle(C.avisoTinta)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(o.moneda ?? "USD").estilo(.label).foregroundStyle(C.texto2)
                    TextField(o.moneda == "ARS" ? "300.000" : "3.000", text: $senaValor).keyboardType(.numberPad).estilo(.body16)
                }
                .padding(.horizontal, 12).frame(height: 44).background(C.superficie, in: .rect(cornerRadius: 12))
                Button("Listo") { Task { await guardarSena(o) } }.buttonStyle(BotonTonal(alto: 44))
            }
            Button("Después") { pideSena = nil }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto2)
        }
        .padding(12).background(C.avisoFondo)
    }

    @ViewBuilder
    private func menuItems(_ o: Operacion) -> some View {
        let col = Operacion.columna(o.etapa)
        Button { estado.abrir(AFichaOperacion(id: o.id)) } label: { Label("Abrir", systemImage: "arrow.up.right") }
        Menu {
            ForEach(Array(Operacion.columnas.enumerated()).filter { $0.offset != col }, id: \.offset) { i, c in
                Button(i == 0 ? "Volver a Nueva" : (i < col ? "Volver a \(c.texto)" : c.texto)) { Task { await mover(o, a: i) } }
            }
        } label: { Label("Mover \(String(o.nombre.split(separator: ",").first ?? "")) a…", systemImage: "arrow.left.arrow.right") }
        Divider()
        Button(role: .destructive) { cayendo = o } label: { Label("Se cayó", systemImage: "heart.slash") }
    }

    private func avisoConflicto(_ c: Conflicto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconoTono(icono: "arrow.triangle.2.circlepath", tono: .azul, tam: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(c.quien.map { Charla.primerNombre($0) } ?? "Alguien") la movió\(c.hasta.map { " a \($0)" } ?? "") hace un segundo").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(Formato.sinViudas("Tu cambio a \(c.mio) no se aplicó. Quedó lo de \(c.quien != nil ? "esa persona" : "la otra persona").")).estilo(.footnote).foregroundStyle(C.texto2)
                Button("Ver qué cambió") { estado.abrir(AFichaOperacion(id: c.id)) }.buttonStyle(BotonTonal()).padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button { conflicto = nil } label: { Image(systemName: "xmark").foregroundStyle(C.texto3) }.accessibilityLabel("Cerrar")
        }
        .padding(12).background(C.azulFondo, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func hojaSinPermiso(_ o: Operacion) -> some View {
        let quien = o.agenteNombre.map { Charla.primerNombre($0) }
        return VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("\(o.nombre) es una operación de \(quien ?? "otra persona")", systemImage: "lock").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Podés verla y comentar. Para moverla de etapa, pedíselo a \(quien ?? "quien la lleva") o a la dueña de la inmobiliaria.")).estilo(.body16).foregroundStyle(C.texto2)
            Spacer(minLength: 0)
            Button("Comentar") { sinPermiso = nil; estado.abrir(AFichaOperacion(id: o.id)) }.buttonStyle(BotonPrincipal())
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var listaCaidas: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Se cayeron", cuenta: "\(Formato.numero(caidas.count)) en total")
            VStack(spacing: 0) {
                ForEach(Array(caidas.enumerated()), id: \.element.id) { i, o in
                    HStack(spacing: 12) {
                        Button { estado.abrir(AFichaOperacion(id: o.id)) } label: {
                            HStack(spacing: 12) {
                                IconoTono(icono: "heart.slash", tono: .rojo, tam: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(o.nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                    Text([o.caidaEn.map { Formato.dia($0) }, o.caidaMotivo, o.contactoNombre].compactMap { $0 }.joined(separator: " · "))
                                        .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        if puedeMover { Button("Reabrir") { Task { await reabrir(o) } }.buttonStyle(BotonTonal()) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
                if caidas.isEmpty { Text("No se cayó ninguna.").estilo(.subhead).foregroundStyle(C.texto3).padding(20) }
            }
            .tarjeta()
        }
    }

    /// «Por agente» y «Este mes» (el panel de sección de la web).
    private var esteMes: some View {
        let cal = Formato.calendario
        let todas = ops ?? []
        let cerradas = todas.filter { $0.etapa == "cierre" && ($0.actualizadoEn.map { cal.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false) }
        let honorarios = cerradas.reduce(0.0) { n, o in
            (o.moneda ?? "USD") == "USD" ? n + (o.valor ?? 0) * ((o.honorariosComprador ?? 0) + (o.honorariosVendedor ?? 0)) / 100 : n
        }
        let caidasMes = caidas.filter { $0.caidaEn.map { cal.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false }
        let motivos = Dictionary(grouping: caidasMes.compactMap(\.caidaMotivo), by: { $0 }).mapValues(\.count)
        let comun = motivos.max { $0.value < $1.value }
        let conOps = equipo.filter { p in todas.contains { $0.agenteId == p.usuarioId } }
        return VStack(alignment: .leading, spacing: 8) {
            if !conOps.isEmpty {
                TituloBloque(texto: "Por agente")
                VStack(spacing: 0) {
                    ForEach(Array(conOps.enumerated()), id: \.element.id) { i, p in
                        let n = todas.filter { $0.agenteId == p.usuarioId && $0.etapa != "cierre" }.count
                        Button { agente = p.usuarioId } label: {
                            HStack {
                                Text(p.completo).estilo(.filaLista).foregroundStyle(C.texto)
                                Spacer()
                                Text(Formato.cantidad(n, "abierta", "abiertas")).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
            TituloBloque(texto: "Este mes")
            VStack(spacing: 0) {
                HStack {
                    Label("Cerradas", systemImage: "hands.sparkles").estilo(.filaLista).foregroundStyle(C.texto)
                    Spacer()
                    if honorarios > 0 { Text("\(Formato.plataCorta(honorarios, "USD")) honorarios").estilo(.footnote).foregroundStyle(C.okTinta) }
                    Text(Formato.numero(cerradas.count)).estilo(.filaLista).foregroundStyle(C.texto)
                }
                .padding(.horizontal, 14).frame(minHeight: 46)
                Button { caidasVista = true } label: {
                    HStack {
                        Label("Caídas", systemImage: "heart.slash").estilo(.filaLista).foregroundStyle(C.errorTinta)
                        Spacer()
                        if let comun { Text("\(Formato.numero(comun.value)) por \(comun.key.lowercased())").estilo(.footnote).foregroundStyle(C.texto2) }
                        Text(Formato.numero(caidasMes.count)).estilo(.filaLista).foregroundStyle(C.texto)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 46).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
            .tarjeta()
        }
    }

    // MARK: Acciones

    private func reemplazar(_ o: Operacion) {
        if let i = ops?.firstIndex(where: { $0.id == o.id }) { ops?[i] = o }
    }

    /// Mover a otra columna (con la etapa que vio la persona, para que la API sepa si otro la movió).
    private func mover(_ o: Operacion, a col: Int, deshaciendo: Bool = false) async {
        guard puedeMover else { sinPermiso = o; return }
        let destino = Operacion.columnas[col]
        let antes = o.etapa
        var nueva = o
        nueva.etapa = destino.clave
        reemplazar(nueva)
        Haptico.impacto()
        if destino.clave == "reserva" && o.sena == nil && !deshaciendo { pideSena = o.id; senaValor = "" } else if pideSena == o.id { pideSena = nil }
        struct Cuerpo: Encodable { var etapa: String; var desde: String }
        do {
            let r: Operacion = try await estado.api.enviar("POST", "/v1/operaciones/\(o.id)/mover", Cuerpo(etapa: destino.clave, desde: antes))
            reemplazar(r)
            if deshaciendo { estado.avisar("Listo, volvió a su etapa"); return }
            if destino.clave == "cierre" && o.propiedadOperacion == "alquiler" {
                estado.sugerir("\(o.nombre) llegó al cierre", "Hacer contrato", AFichaOperacion(id: o.id))
            } else {
                estado.avisar("\(o.nombre) pasó a \(destino.texto)") {
                    Task { await mover(r, a: Operacion.columna(antes), deshaciendo: true) }
                }
            }
            estado.version += 1
        } catch let e as ErrorApi {
            reemplazar(o)
            if pideSena == o.id { pideSena = nil }
            if e.codigo == "movida" {
                let h: [EventoOperacion] = (try? await estado.api.get("/v1/operaciones/\(o.id)/historial")) ?? []
                let ultimo = h.sorted { $0.creadoEn > $1.creadoEn }.first { $0.tipo == "etapa" }
                let hasta = ultimo?.datos?["hasta"]?.texto.map { Operacion.textoColumna($0) }
                conflicto = Conflicto(prop: o.nombre, quien: ultimo?.autorNombre, hasta: hasta, mio: destino.texto, id: o.id)
                await cargar()
            } else if e.estado == 403 {
                sinPermiso = o
            } else {
                estado.avisarReintentar(e.detalle.isEmpty ? "No se movió" : e.detalle) { Task { await mover(o, a: col) } }
            }
        } catch { reemplazar(o) }
    }

    private func guardarSena(_ o: Operacion) async {
        pideSena = nil
        guard let v = Double(senaValor.filter(\.isNumber)), v > 0 else { return }
        do {
            try await estado.api.hacer("PATCH", "/v1/operaciones/\(o.id)", JSONLibre.objeto(["sena": .numero(v), "senaMoneda": .texto(o.moneda ?? "USD")]))
            estado.avisar("Seña \(Formato.plata(v, o.moneda ?? "USD")) cargada")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func caer(_ o: Operacion, _ motivo: String) async {
        struct Cuerpo: Encodable { var motivo: String }
        ops?.removeAll { $0.id == o.id }
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/caer", Cuerpo(motivo: motivo))
            estado.avisar("\(o.nombre) se cayó · \(motivo.lowercased())") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/reabrir")
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            estado.version += 1
        } catch {
            estado.avisar(error)
            await cargar()
        }
    }

    private func reabrir(_ o: Operacion) async {
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(o.id)/reabrir")
            estado.avisar("\(o.nombre) volvió al tablero")
            caidasVista = false
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// El tablero no trae las caídas: van aparte con ?caidas=si.
    private func cargar() async {
        var q: [URLQueryItem] = []
        if !tipo.isEmpty { q.append(.init(name: "operacion", value: tipo)) }
        do {
            ops = try await estado.api.get("/v1/operaciones", query: q + [.init(name: "limite", value: "500")])
            error = nil
        } catch let e as ErrorApi { if ops == nil { error = e } } catch {}
        caidas = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "caidas", value: "si"), .init(name: "limite", value: "100")])) ?? caidas
        if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
    }
}

/// «¿Por qué se cayó Gorriti 5530?»: el motivo de un toque (o escrito) y qué pasa después.
struct SeCayo: View {
    @Environment(\.dismiss) private var cerrar
    var propiedad: String
    var contacto: String?
    var alElegir: (String) -> Void
    @State private var elegido = ""
    @State private var otro = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("¿Por qué se cayó \(propiedad)?", systemImage: "heart.slash").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            FlowLayout(espacio: 8) {
                ForEach(Operacion.motivos, id: \.self) { m in
                    Button { elegido = m; otro = "" } label: {
                        Text(m).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(elegido == m ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(elegido == m ? C.accion : C.superficie, in: Capsule())
                            .overlay(Capsule().strokeBorder(elegido == m ? Color.clear : C.linea2))
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(elegido == m ? .isSelected : [])
                }
            }
            Etiquetado("Otro motivo") { TextField("", text: $otro).campoCorredor() }
            Text(Formato.sinViudas("\(contacto.map { "\($0) queda" } ?? "El interesado queda") como interesado y le seguimos mandando lo que le encaje. El motivo alimenta el informe del mes."))
                .estilo(.footnote).foregroundStyle(C.texto2)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button("Se cayó") {
                    let m = otro.trimmingCharacters(in: .whitespaces).nonEmpty ?? elegido
                    guard !m.isEmpty else { return }
                    cerrar()
                    alElegir(m)
                }
                .buttonStyle(BotonDestructivo())
                .disabled(elegido.isEmpty && otro.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

/// Una operación nueva: propiedad, interesado, lo que ofrece y quién la lleva (puede venir con el
/// contacto o la propiedad ya elegidos).
struct NuevaOperacion: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var contacto: Resultado? = nil
    var propiedad: Propiedad? = nil
    @State private var prop: Propiedad?
    @State private var con: Resultado?
    @State private var valor: Double?
    @State private var moneda = "USD"
    @State private var lleva = ""
    @State private var titulo = ""
    @State private var equipo: [Miembro] = []
    @State private var elegirP = false
    @State private var elegirC = false
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Button { elegirP = true } label: { LabeledContent("Propiedad", value: prop?.nombre ?? "Elegí") }
                Button { elegirC = true } label: { LabeledContent("Interesado", value: con?.titulo ?? "Elegí") }
                Section("Ofrece") {
                    Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("Valor", value: $valor, format: .number).keyboardType(.numberPad)
                }
                Picker("La lleva", selection: $lleva) {
                    Text("Sin agente").tag("")
                    ForEach(equipo.filter { $0.rol != "lector" }) { Text($0.completo).tag($0.usuarioId) }
                }
                TextField("Título (si no, «\(tituloArmado)»)", text: $titulo)
            }
            .navigationTitle("Nueva operación").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { Task { await crear() } }.disabled((prop == nil && con == nil) || guardando)
                }
            }
            .sheet(isPresented: $elegirP) { ElegirPropiedad { prop = $0; moneda = $0.moneda ?? moneda; if valor == nil { valor = $0.precio } } }
            .sheet(isPresented: $elegirC) { ElegirContacto { con = $0 } }
        }
        .onAppear {
            if con == nil { con = contacto }
            if prop == nil, let propiedad { prop = propiedad; moneda = propiedad.moneda ?? moneda }
            if lleva.isEmpty { lleva = estado.usuario?.id ?? "" }
        }
        .task { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
    }

    /// «Mendoza 2350 → Valeria».
    private var tituloArmado: String {
        [prop.map { String($0.nombre.split(separator: ",").first ?? "") }, con.map { Charla.primerNombre($0.titulo) }].compactMap { $0?.nonEmpty }.joined(separator: " → ").nonEmpty ?? "Operación nueva"
    }

    private func crear() async {
        struct Cuerpo: Encodable { var titulo: String; var etapa = "nuevo"; var valor: Double; var moneda: String; var contactoId: String?; var propiedadId: String?; var agenteId: String? }
        guardando = true
        defer { guardando = false }
        do {
            try await estado.cola.enviar("POST", "/v1/operaciones", Cuerpo(titulo: String((titulo.nonEmpty ?? tituloArmado).prefix(120)), valor: valor ?? prop?.precio ?? 0, moneda: moneda,
                                                                         contactoId: con?.id, propiedadId: prop?.id, agenteId: lleva.nonEmpty), etiqueta: "Operación nueva")
            estado.avisar("Operación creada")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
