import SwiftUI

/// Una fila de «Para hacer ahora»: ícono en su tono, qué es, de dónde viene y la acción.
struct Pendiente2A: Identifiable {
    var id: String
    var icono: String
    var tono: Tono
    var titulo: String
    var detalle: String
    var accion: String
    var ir: AnyHashable?
    var hacer: (() -> Void)? = nil
}

/// Lo que trae el Inicio (todo de una, para pintar una sola vez).
struct DatosInicio {
    var panel: Panel?
    var guia: Guia?
    var conversaciones: [Conversacion] = []
    var preguntas: [PreguntaML] = []
    var deudas: [Deuda] = []
    var equipo: [Miembro] = []
    var licencias: [Licencia] = []
    var avisos = 0
    var cobradoMes: Double?
    var esperadoMes: Double?
}

/// 2A Inicio del agente y 2B de la dueña (handoff · «Hoy»): la próxima visita, para hacer ahora,
/// «Encontramos por vos», el objetivo del mes y los accesos. Nunca queda vacío: sin nada urgente
/// muestra los primeros pasos y las acciones rápidas.
struct InicioRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var datos: DatosInicio?
    @State private var error: ErrorApi?
    @State private var aprobadas: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CabeceraPestana(
                    sobre: estado.esDuenio ? "\(estado.inmobiliaria?.nombre ?? "") · \(Formato.diaCompleto(Date()).split(separator: " ").prefix(2).joined(separator: " "))" : Formato.diaCompleto(Date()),
                    titulo: "Hoy",
                    acciones: [
                        AccionCabecera(icono: "magnifyingglass", etiqueta: "Buscar") { estado.abrir(ABuscar()) },
                        AccionCabecera(icono: "bell", etiqueta: "Avisos", insignia: estado.avisosPendientes) { estado.abrir(AAvisos()) },
                    ],
                    avatar: true)
                Accesos(cobrar: datos?.deudas.count ?? 0).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
                if !estado.cola.cambios.isEmpty { ColaVisible().padding(.horizontal, 16).padding(.bottom, 12) }
                Group {
                    if let datos {
                        if estado.esDuenio { duena(datos) } else { agente(datos) }
                    } else if let error {
                        EstadoError(que: "tu día", error: error) { Task { await cargar() } }.padding(.top, 40)
                    } else {
                        EsqueletoFilas(filas: 5).padding(.horizontal, 16)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.bottom, 32)
        }
        .refreshable { await cargar() }
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
    }

    // MARK: 2A Agente

    @ViewBuilder
    private func agente(_ d: DatosInicio) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if let c = proximaVisita(d) { TarjetaProximaVisita(cita: c) }
            let hoy = paraHacer(d)
            if !hoy.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    TituloBloque(texto: "Para hacer ahora", cuenta: "\(hoy.count)")
                    ListaPendientes(filas: hoy)
                }
            }
            if let s = d.panel?.sugerencias?.first(where: { $0.estado != "descartada" }) { TarjetaSugerencia(s: s) }
            if let o = d.panel?.objetivos?.first(where: { $0.agenteId == estado.usuario?.id || $0.agenteId == nil }) { TarjetaObjetivo(o: o) }
            if hoy.isEmpty, let g = d.guia { PrimerosPasos(guia: g) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 2B Dueña

    @ViewBuilder
    private func duena(_ d: DatosInicio) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Cifra(etiqueta: "Cobrado del mes", valor: d.cobradoMes.map { Formato.plataCorta($0) } ?? "—")
                Cifra(etiqueta: "Consultas", valor: "\(d.conversaciones.count + d.preguntas.count) sin responder")
                Cifra(etiqueta: "Visitas", valor: "\(d.panel?.numeros?.citasHoy ?? 0) hoy")
            }
            let aprob = paraAprobar(d).filter { !aprobadas.contains($0.id) }
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Para aprobar")
                if aprob.isEmpty {
                    Label("No queda nada para aprobar.", systemImage: "checkmark.circle")
                        .estilo(.subheadFuerte).foregroundStyle(C.okTinta)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(C.okFondo, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
                } else {
                    ForEach(aprob) { x in
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.titulo).font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                                Text(x.detalle).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            HStack(spacing: 8) {
                                Button(x.accion) { x.hacer?() }.buttonStyle(BotonAccion())
                                if let ir = x.ir {
                                    Button("Ver detalle") { estado.abrir(ir) }.buttonStyle(BotonHundido())
                                }
                            }
                        }
                        .padding(14).tarjeta()
                    }
                }
            }
            let hoy = paraHacer(d)
            if !hoy.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    TituloBloque(texto: "Para hacer ahora", cuenta: "\(hoy.count)")
                    ListaPendientes(filas: hoy)
                }
            }
            if !d.equipo.isEmpty { EquipoAhora(equipo: d.equipo, licencias: d.licencias, citas: d.panel?.agendaHoy ?? []) }
            if let e = d.esperadoMes, e > 0 {
                let cobrado = d.cobradoMes ?? 0
                let falta = max(0, e - cobrado)
                TarjetaAvance(titulo: "Cobranza de \(Formato.mesDe(Date()))", cifra: "\(Int((cobrado / e * 100).rounded())) %",
                              avance: cobrado / e, color: Color(hex: 0x2F9E6F),
                              pie: falta > 0 ? "Faltan \(Formato.plata(falta)) de \(Formato.cantidad(d.deudas.count, "inquilino", "inquilinos"))" : "Cobraste todo el mes")
                    .onTapGesture { estado.abrir(ACobranzas()) }
            }
            if hoy.isEmpty, let g = d.guia { PrimerosPasos(guia: g) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Datos

    private func cargar() async {
        do {
            var d = DatosInicio()
            let api = estado.api
            d.panel = try await api.get("/v1/panel")
            d.guia = try? await api.get("/v1/panel/guia")
            d.conversaciones = (try? await api.get("/v1/whatsapp/conversaciones", query: [.init(name: "noLeidas", value: "si"), .init(name: "limite", value: "20")])) ?? []
            d.preguntas = (try? await api.get("/v1/mercadolibre/preguntas", query: [.init(name: "estado", value: "sin_responder"), .init(name: "limite", value: "10")])) ?? []
            d.deudas = (try? await api.get("/v1/contratos/deudas")) ?? []
            struct Contador: Decodable { var noLeidos: Int?; var paraHacer: Int? }
            if let c: Contador = try? await api.get("/v1/avisos/contador") { d.avisos = (c.noLeidos ?? 0); estado.avisosPendientes = d.avisos }
            if estado.esDuenio {
                d.equipo = (try? await api.get("/v1/equipo")) ?? []
                let hoy = Formato.diaISO(Date())
                d.licencias = (try? await api.get("/v1/licencias", query: [.init(name: "desde", value: hoy), .init(name: "hasta", value: hoy)])) ?? []
                struct Mes: Decodable { var totalCobrado: [String: Double]?; var totalPendiente: [String: Double]? }
                if let r: Mes = try? await api.get("/v1/cobranzas") {
                    d.cobradoMes = r.totalCobrado?["ARS"] ?? 0
                    d.esperadoMes = (r.totalCobrado?["ARS"] ?? 0) + (r.totalPendiente?["ARS"] ?? 0)
                }
            }
            estado.sinLeer = d.conversaciones.reduce(0) { $0 + ($1.noLeidos ?? 0) }
            datos = d
            ActividadVisita.actualizar(proximaVisita(d))
            error = nil
            Guardado.guardar(d.panel, clave: "panel")
        } catch let e as ErrorApi {
            if datos == nil, let p = Guardado.leer(Panel.self, clave: "panel")?.0 { datos = DatosInicio(panel: p) }
            if datos == nil { error = e }
        } catch {}
    }

    private func proximaVisita(_ d: DatosInicio) -> Cita? {
        (d.panel?.agendaHoy ?? [])
            .filter { $0.terminaEn > Date() && $0.estado != "cancelada" && ($0.agenteId == nil || $0.agenteId == estado.usuario?.id || !estado.esDuenio) }
            .sorted { $0.empiezaEn < $1.empiezaEn }.first
    }

    private func paraHacer(_ d: DatosInicio) -> [Pendiente2A] {
        var f: [Pendiente2A] = []
        for c in d.conversaciones.prefix(3) {
            f.append(Pendiente2A(id: "wa" + c.id, icono: "bubble.left", tono: .verde,
                                 titulo: c.propiedadTitulo.map { "\(c.quien) preguntó por \($0)" } ?? "\(c.quien) te escribió",
                                 detalle: "WhatsApp · \(c.ultimoMensajeEn.map { Formato.hace($0) } ?? "")", accion: "Responder", ir: AChat(id: c.id)))
        }
        for p in d.preguntas.prefix(2) {
            f.append(Pendiente2A(id: "ml" + p.id, icono: "storefront", tono: .oro,
                                 titulo: "\(p.texto ?? "Pregunta")\(p.propiedad.map { " · \($0)" } ?? "")",
                                 detalle: "Mercado Libre · \(p.creadaEn.map { Formato.hace($0) } ?? "")", accion: "Responder", ir: APreguntaML(id: p.id)))
        }
        for x in d.deudas.filter({ estado.esDuenio || $0.agenteId == nil || $0.agenteId == estado.usuario?.id }).prefix(2) {
            let dias = x.meses?.first?.vencio.flatMap(Fecha.dia).map { max(0, Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0) }
            f.append(Pendiente2A(id: "co" + x.contratoId, icono: "dollarsign.circle", tono: .rojo,
                                 titulo: "\(x.contactoNombre ?? x.propiedadTitulo ?? "Cobro") · \(Formato.plata(x.total ?? 0, x.moneda ?? "ARS"))",
                                 detalle: dias.map { $0 > 0 ? "Cobro vencido hace \(Formato.cantidad($0, "día", "días"))" : "Vence hoy" } ?? "Cobro pendiente",
                                 accion: "Cobrar", ir: AFichaContrato(id: x.contratoId)))
        }
        if let n = d.panel?.numeros?.rendicionesListas, n > 0, estado.esDuenio {
            f.append(Pendiente2A(id: "rend", icono: "doc.text", tono: .azul, titulo: Formato.cantidad(n, "rendición lista para mandar", "rendiciones listas para mandar"),
                                 detalle: "Revisalas y emitilas", accion: "Revisar", ir: AContratos()))
        }
        return f
    }

    private func paraAprobar(_ d: DatosInicio) -> [Pendiente2A] {
        var f: [Pendiente2A] = []
        for s in (d.panel?.sugerencias ?? []).filter({ $0.estado != "descartada" && $0.estado != "aplicada" }).prefix(3) {
            f.append(Pendiente2A(id: s.id, icono: "checkmark", tono: .verde, titulo: s.destacado ?? s.accion ?? "Para aprobar", detalle: s.motivo ?? "",
                                 accion: "Aprobar", ir: s.operacionId.map { AnyHashable(AFichaOperacion(id: $0)) }
                                     ?? s.propiedadId.map { AnyHashable(AFichaPropiedad(id: $0)) }
                                     ?? s.contactoId.map { AnyHashable(AFichaContacto(id: $0)) }) {
                // Deshacer en vez de confirmar: se aplica a los 5 s si no se arrepiente.
                aprobadas.insert(s.id)
                let tarea = Task {
                    try? await Task.sleep(for: .seconds(5))
                    if Task.isCancelled { return }
                    try? await estado.api.hacer("POST", "/v1/sugerencias/\(s.id)/aplicar")
                    estado.version += 1
                }
                estado.avisar("Aprobado · ya le avisamos") {
                    tarea.cancel()
                    aprobadas.remove(s.id)
                }
            })
        }
        return f
    }
}

// MARK: - Piezas del Inicio

/// La tarjeta verde de la próxima visita (rayado, grano, rr de marca de agua, Cómo llegar y Estoy llegando).
struct TarjetaProximaVisita: View {
    @Environment(Estado.self) private var estado
    var cita: Cita

    var body: some View {
        let min = Int(cita.empiezaEn.timeIntervalSinceNow / 60)
        VStack(alignment: .leading, spacing: 4) {
            Label(min > 0 ? "Próxima visita · en \(min < 60 ? "\(min) min" : Formato.horaDe(cita.empiezaEn))" : "Visita en curso", systemImage: "clock")
                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.oro)
            Text(cita.donde).font(Estilo(tamano: 24, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(.white)
                .padding(.top, 4)
            Text("\(Formato.horaDe(cita.empiezaEn))\(cita.contactoNombre.map { " · con \($0)" } ?? "")")
                .estilo(.subhead).foregroundStyle(Color(hex: 0xCFE0D8))
            HStack(spacing: 8) {
                Button { Afuera.mapas(cita.lugar ?? cita.propiedadTitulo ?? "") } label: {
                    Label("Cómo llegar", systemImage: "location.fill")
                        .font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                        .foregroundStyle(Color(hex: 0x1A1405))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(LinearGradient(stops: [.init(color: Color(hex: 0xF7CB73), location: 0), .init(color: Color(hex: 0xF2BB57), location: 0.55),
                                                           .init(color: Color(hex: 0xE9AD44), location: 1)], startPoint: .top, endPoint: .bottom),
                                    in: .rect(cornerRadius: 13, style: .continuous))
                }
                Button { llegando() } label: {
                    HStack(spacing: 6) {
                        Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 18, height: 18)
                        Text("Estoy llegando").font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.22)))
                }
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { FondoTarjetaVerde() }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE3()
        .onTapGesture { estado.abrir(ACita(id: cita.id)) }
    }

    private func llegando() {
        guard let id = cita.contactoId else { return estado.avisar("La visita no tiene un contacto cargado.", ok: false) }
        Task {
            struct C: Decodable { var nombre: String?; var telefono: String? }
            let c: C? = try? await estado.api.get("/v1/contactos/\(id)")
            let nombre = c?.nombre?.split(separator: " ").first.map(String.init) ?? ""
            Afuera.whatsapp(c?.telefono, texto: "Hola \(nombre), estoy llegando a \(cita.donde).")
        }
    }
}

/// El fondo de las tarjetas verdes destacadas: 0f3530, dos rayados finos, grano y la rr de marca de agua.
struct FondoTarjetaVerde: View {
    var body: some View {
        ZStack {
            C.verde800
            Canvas { ctx, size in
                for (angulo, paso, alfa) in [(28.0, 36.0, 0.14), (118.0, 50.0, 0.1)] {
                    var p = Path()
                    let r = Angle(degrees: angulo).radians
                    let largo = size.width + size.height
                    var x = -largo
                    while x < largo {
                        p.move(to: CGPoint(x: x, y: -20))
                        p.addLine(to: CGPoint(x: x + cos(r) * largo * 2, y: -20 + sin(r) * largo * 2))
                        x += paso
                    }
                    ctx.stroke(p, with: .color(Color(hex: 0x7FC4AD, alfa: alfa)), lineWidth: 2)
                }
            }
            Image("GranoClaro").resizable(resizingMode: .tile)
            Image("Simbolo").resizable().scaledToFit().frame(width: 130)
                .colorMultiply(.black).colorInvert().opacity(0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 16, y: 30)
        }
        .accessibilityHidden(true)
    }
}

/// La lista de «Para hacer ahora»: la primera acción en Acción, las demás en hundido.
struct ListaPendientes: View {
    @Environment(Estado.self) private var estado
    var filas: [Pendiente2A]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.element.id) { i, r in
                HStack(spacing: 12) {
                    IconoTono(icono: r.icono, tono: r.tono)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
                        Text(r.detalle).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if let h = r.hacer { h() } else if let ir = r.ir { estado.abrir(ir) }
                    } label: {
                        Text(r.accion).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(i == 0 ? C.sobreAccion : C.accion)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(i == 0 ? C.accion : C.hundida, in: Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
                .frame(minHeight: 66)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                .contentShape(Rectangle())
                .onTapGesture { if let ir = r.ir { estado.abrir(ir) } }
            }
        }
        .tarjeta()
    }
}

/// «Encontramos por vos»: la sugerencia del día en oro, con su acción.
struct TarjetaSugerencia: View {
    @Environment(Estado.self) private var estado
    var s: Sugerencia
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Encontramos por vos", systemImage: "sparkles")
                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
            Text(Formato.sinViudas(s.destacado ?? s.motivo ?? "")).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                .foregroundStyle(C.texto)
            Button {
                if let p = s.propiedadId { estado.abrir(AFichaPropiedad(id: p)) } else if let c = s.contactoId { estado.abrir(AFichaContacto(id: c)) }
                else if let o = s.operacionId { estado.abrir(AFichaOperacion(id: o)) } else if let c = s.contratoId { estado.abrir(AFichaContrato(id: c)) }
            } label: {
                Label(s.accion ?? "Ver", systemImage: "paperplane").font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font)
                    .foregroundStyle(C.sobreAccion).padding(.horizontal, 16).frame(height: 44)
                    .background(C.accion, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.avisoFondo, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
    }
}

/// «Objetivo de noviembre · 3 de 5» con la barra oro.
struct TarjetaObjetivo: View {
    var o: Objetivo
    var body: some View {
        let meta = o.meta ?? 0
        let avance = o.avance ?? 0
        let falta = max(0, meta - avance)
        let palabras = Objetivo.metricas[o.metrica ?? ""] ?? ("operación cerrada", "operaciones cerradas")
        let dias = o.hasta.flatMap(Fecha.dia).map { max(0, Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0) } ?? 0
        TarjetaAvance(titulo: "Objetivo de \(Formato.mesDe(Date()))", cifra: "\(Formato.numero(Int(avance))) de \(Formato.numero(Int(meta)))",
                      avance: meta > 0 ? avance / meta : 0,
                      degrade: [Color(hex: 0xE9AD44), Color(hex: 0xF2BB57)],
                      pie: falta > 0 ? "Te faltan \(Formato.cantidad(Int(falta), palabras.0, palabras.1)) · quedan \(Formato.cantidad(dias, "día", "días"))" : "¡Llegaste al objetivo!")
    }
}

/// Una tarjeta con título, cifra a la derecha, barra de 10 y un pie.
struct TarjetaAvance: View {
    var titulo: String
    var cifra: String
    var avance: Double
    var color: Color = C.accion
    var degrade: [Color]? = nil
    var pie: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                Spacer()
                Text(cifra).estilo(.subheadFuerte).foregroundStyle(C.texto)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.hundida)
                    Capsule().fill(degrade.map { AnyShapeStyle(LinearGradient(colors: $0, startPoint: .leading, endPoint: .trailing)) } ?? AnyShapeStyle(color))
                        .frame(width: g.size.width * min(1, max(0, avance)))
                }
            }
            .frame(height: 10)
            Text(pie).estilo(.footnote).foregroundStyle(C.texto2)
        }
        .padding(16)
        .tarjeta()
        .accessibilityElement(children: .combine)
    }
}

/// Una cifra de la dueña: etiqueta 12/600 y valor 16/700.
struct Cifra: View {
    var etiqueta: String
    var valor: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etiqueta).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2)
            Text(valor).font(Estilo(tamano: 16, peso: .bold, tracking: -0.01, relativo: .headline).font).foregroundStyle(C.texto)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta(16)
    }
}

/// Los accesos rápidos, arriba del Inicio: la agenda (ya no es pestaña) y lo que más se usa. Todo lo
/// demás está en la pestaña «Más».
struct Accesos: View {
    @Environment(Estado.self) private var estado
    var cobrar = 0
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            boton("calendar", "Agenda", AAgendaDia())
            boton("person.2", "Contactos", AContactos())
            boton("rectangle.split.3x1", "Operaciones", AOperaciones())
            boton("dollarsign.circle", "Cobranzas", ACobranzas(), insignia: cobrar)
            boton("doc.text", "Contratos", AContratos())
        }
    }

    private func boton(_ icono: String, _ texto: String, _ destino: AnyHashable, insignia: Int = 0) -> some View {
        Button { estado.abrir(destino) } label: {
            VStack(spacing: 6) {
                Image(systemName: icono).font(.system(size: 21, weight: .medium)).foregroundStyle(C.accion)
                    .frame(width: 52, height: 52)
                    .background(C.superficie, in: .rect(cornerRadius: 16, style: .continuous))
                    .sombraE1()
                    .overlay(alignment: .topTrailing) { if insignia > 0 { InsigniaRoja(n: insignia).offset(x: 6, y: -6) } }
                Text(texto).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(insignia > 0 ? "\(texto), \(insignia) para cobrar" : texto)
    }
}

/// «El equipo, ahora»: cada persona con dónde está (su próxima cita o su licencia) y WhatsApp.
struct EquipoAhora: View {
    var equipo: [Miembro]
    var licencias: [Licencia]
    var citas: [Cita]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "El equipo, ahora")
            VStack(spacing: 0) {
                ForEach(Array(equipo.enumerated()), id: \.element.id) { i, m in
                    let (texto, color) = estadoDe(m)
                    HStack(spacing: 12) {
                        Text(Formato.iniciales(m.completo)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font)
                            .foregroundStyle(C.texto)
                            .frame(width: 40, height: 40).background(C.hundida, in: Circle())
                            .overlay(alignment: .bottomTrailing) {
                                Circle().fill(color).frame(width: 12, height: 12).overlay(Circle().stroke(C.superficie, lineWidth: 2))
                            }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.completo).estilo(.filaLista).foregroundStyle(C.texto)
                            Text(texto).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if m.telefono != nil {
                            Button { Afuera.whatsapp(m.telefono) } label: {
                                Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("WhatsApp con \(m.nombre ?? "")")
                        }
                    }
                    .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
                    .frame(minHeight: 60)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    private func estadoDe(_ m: Miembro) -> (String, Color) {
        if let l = licencias.first(where: { $0.usuarioId == m.usuarioId }) {
            let vuelve = Fecha.dia(l.hasta).map { Formato.diaCompleto($0.addingTimeInterval(86400)) } ?? ""
            return ("De \(l.tipo == "vacaciones" ? "vacaciones" : "licencia") · vuelve el \(vuelve)", C.linea2)
        }
        let suyas = citas.filter { $0.agenteId == m.usuarioId }.sorted { $0.empiezaEn < $1.empiezaEn }
        if let ahora = suyas.first(where: { $0.empiezaEn <= Date() && $0.terminaEn > Date() }) {
            return ("En \(ahora.tipoTexto.lowercased()) · \(ahora.donde)", C.oro)
        }
        if let sig = suyas.first(where: { $0.empiezaEn > Date() }) {
            return ("\(sig.tipoTexto) a las \(Formato.horaDe(sig.empiezaEn)) · \(sig.donde)", Color(hex: 0x2F9E6F))
        }
        return ("Sin actividad hoy", C.linea2)
    }
}

/// «Primeros pasos» (lo que todavía no hizo), para que el Inicio nunca quede vacío.
struct PrimerosPasos: View {
    @Environment(Estado.self) private var estado
    var guia: Guia
    var body: some View {
        let p = guia.pasos
        let pasos: [(Bool, String, String, AnyHashable)] = [
            (p?.propiedad ?? false, "house", "Cargá tu primera propiedad", AAltaPropiedad()),
            (p?.datos ?? false, "paintpalette", "Poné tu logo y tus colores", ASeccion(clave: "web")),
            (p?.whatsapp ?? false, "bubble.left.and.bubble.right", "Conectá tu WhatsApp", ASeccion(clave: "integraciones")),
            (p?.equipo ?? false, "person.badge.plus", "Sumá a tu equipo", ASeccion(clave: "equipo")),
            (p?.portales ?? false, "storefront", "Publicá en Mercado Libre y portales", ASeccion(clave: "integraciones")),
            (p?.web ?? false, "globe", "Mirá tu web", ASeccion(clave: "web")),
        ]
        let faltan = pasos.filter { !$0.0 }
        if !faltan.isEmpty && guia.pasosOcultos != true {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Primeros pasos", cuenta: "\(pasos.count - faltan.count) de \(pasos.count)")
                ListaPendientes(filas: faltan.prefix(4).enumerated().map { i, x in
                    Pendiente2A(id: x.2, icono: x.1, tono: .verde, titulo: x.2, detalle: i == 0 ? "Lo que sigue" : "Cuando quieras", accion: "Hacer", ir: x.3)
                })
            }
        } else if estado.escribe {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Acciones rápidas")
                ListaPendientes(filas: [
                    Pendiente2A(id: "mira", icono: "viewfinder", tono: .oro, titulo: "Captá un cartel con MIRA", detalle: "Fotografiá sólo el cartel", accion: "Abrir", ir: nil) { estado.miraAbierta = true },
                    Pendiente2A(id: "alta", icono: "house", tono: .verde, titulo: "Cargá una propiedad", detalle: "En un minuto, con fotos", accion: "Cargar", ir: AAltaPropiedad()),
                    Pendiente2A(id: "visita", icono: "calendar.badge.plus", tono: .azul, titulo: "Agendá una visita", detalle: "Le avisamos al cliente", accion: "Agendar", ir: AAgendaDia()),
                ])
            }
        }
    }
}

/// «2 cambios en cola»: lo cargado sin señal que todavía no subió.
struct ColaVisible: View {
    @Environment(Cola.self) private var cola
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: cola.subiendo ? "arrow.triangle.2.circlepath" : "icloud.slash").foregroundStyle(C.avisoTinta)
            VStack(alignment: .leading, spacing: 0) {
                Text(Formato.cantidad(cola.cambios.count, "cambio en cola", "cambios en cola")).estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(cola.cambios.first { $0.error != nil }?.error ?? "Se suben solos cuando vuelva la señal.").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            Button("Subir") { cola.subir() }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
        }
        .padding(12)
        .background(C.avisoFondo, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Botón lleno de Acción (44, radio 12) y su par hundido, de las tarjetas para aprobar.
struct BotonAccion: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font)
            .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 44)
            .background(C.accion, in: .rect(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct BotonHundido: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font)
            .foregroundStyle(C.texto).frame(maxWidth: .infinity, minHeight: 44)
            .background(C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
