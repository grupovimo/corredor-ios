import SwiftUI
import TipKit
import UserNotifications

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

/// 2A Inicio del agente y 2B de la dueña (handoff · «Hoy»; panel web 01 · 7E, 7C): lo urgente con su
/// acción ahí mismo, «Tu día», la agenda de hoy, las sugerencias, cómo viene el mes, las cobranzas, el
/// equipo y «Tu web». La dueña elige «Yo» o «Equipo». De noche mira a mañana. Nunca queda vacío: sin
/// nada urgente propone el próximo paso, y las acciones rápidas están siempre.
struct InicioRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var datos: DatosInicio?
    @State private var error: ErrorApi?
    @State private var eligiendoQueCargar = false
    @State private var franja = false
    @State private var cargando: Cargar?
    /// «Yo» o «Equipo» (la dueña o el dueño).
    @AppStorage("inicioVista") private var vista = "equipo"
    // Lo optimista, antes de que vuelva la API: consultas asignadas, sugerencias resueltas, citas
    // tildadas, pasos hechos y los primeros pasos ocultos.
    @State private var asignadas: [String: String] = [:]
    @State private var ocultas: Set<String> = []
    @State private var tildadas: [String: Bool] = [:]
    @State private var marcados: Set<String> = []
    @State private var pasosOcultos: Bool?
    /// Lo que entró desde la última vez (se resalta).
    @State private var nuevas: Set<String> = []

    /// Lo que se puede cargar desde el «+» del Inicio (lo mismo que en cada sección, juntado).
    enum Cargar: String, Identifiable { case contacto, visita, operacion, contrato; var id: String { rawValue } }

    private var yo: String? { estado.usuario?.id }
    private var noche: Bool { CuentasInicio.deNoche() }
    private var equipoVista: Bool { estado.esDuenio && vista == "equipo" }
    private var nombre: String { estado.usuario?.nombre.split(separator: " ").first.map(String.init) ?? "" }

    /// La vista «Yo» de la dueña deja sólo lo suyo; el agente ve todo lo que le da la API.
    private func deQuien(_ agente: String?) -> Bool { equipoVista || !estado.esDuenio || agente == yo }

    var body: some View {
        // La franja de la hora va en un ZStack que respeta la parte de arriba (el ScrollView la ignora para
        // que la portada llegue hasta arriba): así su fondo cubre la hora cuando la portada ya pasó.
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PortadaInicio(inmo: datos?.inmo, saludo: saludo, resumen: resumen, clima: datos?.clima, noche: noche) { eligiendoQueCargar = true }
                        .padding(.bottom, 6)
                        .background(GeometryReader { g in Color.clear.preference(key: AlturaPortada.self, value: g.frame(in: .global).minY) })
                    Group {
                        if estado.escribe { TipView(ConsejoCargar()) }
                        TipView(ConsejoMas())
                    }
                    .tipBackground(C.superficie)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    if !estado.cola.cambios.isEmpty { ColaVisible().padding(.horizontal, 16).padding(.bottom, 12) }
                    AvisoPlan().padding(.horizontal, 16).padding(.bottom, 12)
                    contenido
                        .padding(.top, 6)
                        .animation(.easeOut(duration: 0.35), value: datos != nil)
                }
                .padding(.bottom, 32)
            }
            .refreshable { await cargar() }
            .ignoresSafeArea(edges: .top)
            // Cuando la portada sale de la pantalla aparece la franja de la hora, para que lo que sube no se
            // monte sobre la hora y la batería.
            .onPreferenceChange(AlturaPortada.self) { y in
                let ver = y < -200
                if ver != franja { withAnimation(.easeOut(duration: 0.15)) { franja = ver } }
            }
            if franja {
                Color.clear.frame(height: 0)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                    .transition(.opacity)
            }
        }
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: estado.version) { await cargar() }
        .onChange(of: vista) { _, _ in nuevas = [] }
        .confirmationDialog("Cargar", isPresented: $eligiendoQueCargar, titleVisibility: .visible) {
            Button("Propiedad") { estado.abrir(AAltaPropiedad()) }
            Button("Captar un cartel con MIRA") { estado.miraAbierta = true }
            Button("Contacto") { cargando = .contacto }
            Button("Visita") { cargando = .visita }
            Button("Operación") { cargando = .operacion }
            Button("Contrato de alquiler") { cargando = .contrato }
            Button("Cobro") { estado.abrir(ARegistrarCobro()) }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $cargando) { c in
            switch c {
            case .contacto: EditarContacto()
            case .visita: NuevaCita(dia: Date()).presentationDetents([.large])
            case .operacion: NuevaOperacion()
            case .contrato: AltaContrato()
            }
        }
    }

    @ViewBuilder
    private var contenido: some View {
        if let datos {
            Group { if estado.esDuenio { duena(datos) } else { agente(datos) } }
                .transition(.opacity.combined(with: .offset(y: 16)))
        } else if let error {
            EstadoError(que: "tu día", error: error) { Task { await cargar() } }.padding(.top, 40)
        } else {
            EsqueletoFilas(filas: 5).padding(.horizontal, 16)
        }
    }

    // MARK: Saludo

    /// «Buen día, Nahuel» (la dueña, o de noche); el agente de día, «Hola, Martín».
    private var saludo: String {
        let s = estado.esDuenio || noche ? CuentasInicio.saludo() : "Hola"
        return nombre.isEmpty ? s : "\(s), \(nombre)"
    }

    /// «4 cosas no esperan», «Jueves 12 · 2 visitas y 3 mensajes esperando», «Falta tu primera propiedad»…
    private var resumen: String {
        guard let d = datos else { return " " }
        if d.sinRed { return "Actualizado a las \(Formato.horaDe(d.actualizado))" }
        if d.guia?.propiedades == 0 { return "Falta tu primera propiedad" }
        let urgentes = self.urgentes(d)
        if estado.esDuenio {
            guard !urgentes.isEmpty else { return "Hoy no hay nada urgente" }
            return urgentes.count == 1 ? "1 cosa no espera" : "\(urgentes.count) cosas no esperan"
        }
        if noche {
            if let c = citas(d).filter({ !Formato.calendario.isDateInToday($0.empiezaEn) }).first {
                return "Mañana arrancás a las \(CuentasInicio.horaCorta(c.empiezaEn))"
            }
            return "Mañana no tenés nada agendado"
        }
        let visitas = deHoy(d).filter { $0.tipo == "visita" && $0.estado == "pendiente" }.count
        let esperan = charlas(d).count + consultas(d).count
        return "\(CuentasInicio.diaCorto()) · \(Formato.cantidad(visitas, "visita", "visitas"))"
            + (esperan > 0 ? " y \(Formato.cantidad(esperan, "mensaje esperando", "mensajes esperando"))" : "")
    }

    // MARK: 2B Dueña

    @ViewBuilder
    private func duena(_ d: DatosInicio) -> some View {
        let urgentes = self.urgentes(d)
        let sugerencias = self.sugerencias(d)
        let nadaUrgente = urgentes.isEmpty && sugerencias.isEmpty && d.numero?.caido != true
        VStack(alignment: .leading, spacing: 22) {
            Segmentado(opciones: [("yo", "Yo"), ("equipo", "Equipo")], elegido: $vista).accessibilityLabel("Ver")
            if let p = d.proxima { TarjetaProximaVisita(p: p, noche: noche) }
            if estado.escribe || d.inmo?.web != nil { AccionesInicio(acciones: acciones(d), hacer: hacerAccion) }
            if let n = d.numero, n.caido { NumeroCaidoInicio(numero: n) }
            if !urgentes.isEmpty { bloqueUrgentes(d, urgentes) }
            if d.fallo.contains("mensajes") { errorMensajes }
            if !sugerencias.isEmpty { SugerenciasInicio(sugerencias: sugerencias, aplicar: aplicar, descartar: descartar) }
            if nadaUrgente { ProximoPasoInicio(proximos: proximos(d), noche: noche, hacer: hacerProximo) }
            agendaBloque(d)
            if let w = d.inmo?.web { CompartirWebInicio(web: w, nombre: d.inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "", alAbrir: vioLaWeb) }
            pasosBloque(d)
            if d.guia?.propiedades != 0 || !ritmos(d).isEmpty { ComoVieneInicio(ritmos: ritmos(d), cerradas: d.panel?.numeros?.cerradasMes ?? 0) }
            cobranzasBloque(d)
            if equipoVista && !noche {
                let personas = equipoHoy(d)
                if !personas.isEmpty { EquipoHoyInicio(personas: personas) }
            }
            if !d.props.isEmpty { CarteraVisual(props: d.props, total: d.panel?.numeros?.propiedadesDisponibles ?? 0) }
            EsteMes(n: d.panel?.numeros, objetivo: nil)
            TodoCorredor()
            if d.sinRed { notaSinRed }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 2A Agente

    @ViewBuilder
    private func agente(_ d: DatosInicio) -> some View {
        let urgentes = self.urgentes(d)
        let dia = tuDia(d)
        let sugerencias = self.sugerencias(d)
        VStack(alignment: .leading, spacing: 22) {
            if let p = d.proxima { TarjetaProximaVisita(p: p, noche: noche) }
            if estado.escribe || d.inmo?.web != nil { AccionesInicio(acciones: acciones(d), hacer: hacerAccion) }
            if let n = d.numero, n.caido { NumeroCaidoInicio(numero: n) }
            if d.fallo.contains("mensajes") { errorMensajes } else if !urgentes.isEmpty { bloqueUrgentes(d, urgentes) }
            if !dia.isEmpty {
                TuDiaInicio(titulo: noche ? "Quedó pendiente de hoy" : "Tu día", citas: dia,
                            hechas: Set(dia.filter { tildadas[$0.id] ?? ($0.estado == "hecha") }.map(\.id)), tildar: tildar)
            }
            if d.proxima == nil && urgentes.isEmpty && dia.isEmpty { ProximoPasoInicio(proximos: proximos(d), noche: noche, hacer: hacerProximo) }
            pasosBloque(d)
            if !sugerencias.isEmpty { SugerenciasInicio(sugerencias: sugerencias, aplicar: aplicar, descartar: descartar) }
            agendaBloque(d)
            if let w = d.inmo?.web { CompartirWebInicio(web: w, nombre: d.inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "", alAbrir: vioLaWeb) }
            if d.guia?.propiedades != 0 || !ritmos(d).isEmpty { ComoVieneInicio(ritmos: ritmos(d), cerradas: d.panel?.numeros?.cerradasMes ?? 0) }
            cobranzasBloque(d)
            if !d.props.isEmpty { CarteraVisual(props: d.props, total: d.panel?.numeros?.propiedadesDisponibles ?? 0) }
            TodoCorredor()
            if d.sinRed { notaSinRed }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Bloques

    private func bloqueUrgentes(_ d: DatosInicio, _ urgentes: [Urgente]) -> some View {
        UrgentesInicio(urgentes: urgentes, titulo: noche ? "Para mañana" : "Lo urgente", nuevas: nuevas,
                       personas: estado.esDuenio ? asignables(d) : nil, asignar: asignar, cobrar: cobrar, recordar: recordar)
    }

    private var errorMensajes: some View {
        ErrorBloque(titulo: "No pudimos traer tus mensajes", texto: "WhatsApp no respondió. Es sólo esta vista.",
                    salida: ("Abrir Mensajes", { estado.pestana = .mensajes })) { Task { await cargar() } }
    }

    @ViewBuilder
    private func agendaBloque(_ d: DatosInicio) -> some View {
        if d.fallo.contains("agenda") {
            ErrorBloque(titulo: "No pudimos traer la agenda", salida: ("Abrir Agenda", { estado.abrir(AAgendaDia()) })) { Task { await cargar() } }
        } else {
            let lista = noche ? citas(d).filter { !Formato.calendario.isDateInToday($0.empiezaEn) } : deHoy(d)
            if !lista.isEmpty {
                let titulo = noche ? (equipoVista ? "Mañana en la agenda del equipo" : "Mañana en tu agenda")
                    : (equipoVista ? "Hoy en la agenda del equipo" : "Hoy en tu agenda")
                AgendaHoyInicio(titulo: titulo, citas: lista)
            }
        }
    }

    @ViewBuilder
    private func pasosBloque(_ d: DatosInicio) -> some View {
        if let g = d.guia {
            let pasos = CuentasInicio.primerosPasos(g, duenio: estado.esDuenio).map { p -> PasoInicio in
                var x = p
                x.hecho = x.hecho || marcados.contains(x.clave)
                return x
            }
            if !(pasosOcultos ?? g.pasosOcultos ?? false) && !pasos.isEmpty {
                PrimerosPasos(pasos: pasos, hacer: hacerPaso, ocultar: ocultarPasos)
            }
        }
    }

    @ViewBuilder
    private func cobranzasBloque(_ d: DatosInicio) -> some View {
        let cm = cobranzasMes(d)
        let cobradas = cm.0, pendientes = cm.1
        if !cobradas.isEmpty || !pendientes.isEmpty {
            let n = d.panel?.numeros?.rendicionesListas ?? 0
            CobranzasMesInicio(cobradas: cobradas, pendientes: pendientes,
                               rendiciones: estado.esDuenio ? (n, d.panelExtra?.numeros?.primeraRendicion) : nil)
        } else if estado.esDuenio && !d.fallo.contains("cobranzas") {
            // Todavía sin alquileres: que se sepa que la cobranza también se lleva desde acá.
            Button { estado.abrir(AContratos()) } label: {
                HStack(spacing: 12) {
                    IconoTono(icono: "dollarsign.circle", tono: .verde, tam: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cobrá los alquileres desde acá").estilo(.filaLista).foregroundStyle(C.texto)
                        Text(Formato.sinViudas("Cargá un contrato: te avisamos quién debe, mandás el recibo y le rendís al dueño."))
                            .estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Chevron()
                }
                .padding(14).tarjeta()
            }
            .buttonStyle(Presionable())
        }
    }

    private var notaSinRed: some View {
        Text(Formato.sinViudas("Llamar y WhatsApp siguen andando: abren el teléfono, no necesitan Corredor."))
            .estilo(.footnote).foregroundStyle(C.texto2).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
    }

    // MARK: Cuentas sobre los datos

    private func citas(_ d: DatosInicio) -> [Cita] {
        d.agenda.filter { $0.estado != "cancelada" && deQuien($0.agenteId) }.sorted { $0.empiezaEn < $1.empiezaEn }
    }

    private func deHoy(_ d: DatosInicio) -> [Cita] { citas(d).filter { Formato.calendario.isDateInToday($0.empiezaEn) } }

    private func tuDia(_ d: DatosInicio) -> [Cita] {
        deHoy(d).filter { $0.id != d.proxima?.cita.id && (noche || $0.estado == "pendiente" || tildadas[$0.id] != nil) }
    }

    private func consultas(_ d: DatosInicio) -> [AvisoConsulta] {
        d.consultas.filter { !estado.esDuenio || equipoVista || $0.responsableId == yo }.map { a in
            var x = a
            if let c = a.contactoId, let n = asignadas[c] {
                x.responsableId = "asignada"
                x.responsableNombre = n
            }
            return x
        }
    }

    private func charlas(_ d: DatosInicio) -> [Conversacion] { d.conversaciones.filter { deQuien($0.agenteId) } }

    private func fila(_ f: FilaCobranza) -> CobranzaInicio {
        CobranzaInicio(contratoId: f.contratoId, propiedadTitulo: f.propiedadTitulo, contactoNombre: f.contactoNombre, agenteId: f.agenteId,
                       monto: f.monto, moneda: f.moneda, vence: f.vence ?? Formato.diaISO(Date()), estado: f.estado ?? "pendiente")
    }

    /// Cada alquiler que debe, una vez: desde el mes más viejo, con el total (la regla de la API).
    private func deben(_ d: DatosInicio) -> [CobranzaInicio]? {
        d.deudas.map { l in
            l.map { x in
                CobranzaInicio(contratoId: x.contratoId, propiedadTitulo: x.propiedadTitulo, contactoNombre: x.contactoNombre, agenteId: x.agenteId,
                               monto: x.total ?? 0, moneda: x.moneda ?? "ARS", vence: x.meses?.first?.vence ?? Formato.diaISO(Date()),
                               estado: "atrasado", montoMes: x.meses?.first?.esperado)
            }
        }
    }

    private func urgentes(_ d: DatosInicio) -> [Urgente] {
        let pend = (d.cobranzas?.pendientes ?? []).map(fila)
        let atrasadas = (deben(d) ?? pend.filter { $0.estado == "atrasado" }).filter { deQuien($0.agenteId) }
        var us: [Urgente] = atrasadas.map { CuentasInicio.cobroUrgente($0) }
        us += consultas(d).map { CuentasInicio.consultaUrgente($0) }
        if !(estado.esDuenio && !equipoVista) {
            us += d.reservas.map { CuentasInicio.reservaUrgente($0) }
            us += d.preguntas.map { CuentasInicio.preguntaUrgente($0) }
        }
        if !(estado.esDuenio && equipoVista) { us += charlas(d).map { CuentasInicio.whatsappUrgente($0) } }
        return CuentasInicio.ordenar(us)
    }

    private func cobranzasMes(_ d: DatosInicio) -> ([CobranzaInicio], [CobranzaInicio]) {
        guard let c = d.cobranzas else { return ([], []) }
        let cobradas = c.cobradas.map(fila).filter { deQuien($0.agenteId) }
        var pendientes = c.pendientes.map(fila)
        if let deben = deben(d) { pendientes = pendientes.filter { $0.estado != "atrasado" } + deben }
        return (cobradas, pendientes.filter { deQuien($0.agenteId) })
    }

    private func sugerencias(_ d: DatosInicio) -> [SugerenciaInicio] {
        (d.panelExtra?.sugerencias ?? []).filter { deQuien($0.agenteId) && !ocultas.contains($0.id) && $0.estado != "descartada" && $0.estado != "aplicada" }
    }

    private func ritmos(_ d: DatosInicio) -> [RitmoInicio] {
        (d.panel?.objetivos ?? [])
            .filter { estado.esDuenio && equipoVista ? $0.agenteId == nil : $0.agenteId == yo }
            .sorted { CuentasInicio.ordenMetrica($0.metrica) < CuentasInicio.ordenMetrica($1.metrica) }
            .map { CuentasInicio.ritmo($0) }
    }

    private func deLicencia(_ d: DatosInicio, _ id: String) -> Licencia? {
        let hoy = Formato.diaISO(Date())
        return d.licencias.first { $0.usuarioId == id && $0.desde <= hoy && $0.hasta >= hoy }
    }

    /// A quién se le puede dar una consulta: agentes y dueños que no están de licencia hoy.
    private func asignables(_ d: DatosInicio) -> [(String, String)] {
        d.equipo.filter { $0.rol != "lector" && deLicencia(d, $0.usuarioId) == nil }.map { ($0.usuarioId, $0.completo) }
    }

    /// El equipo hoy: cada persona (menos quien mira y los lectores) con sus citas y lo que tiene sin responder.
    private func equipoHoy(_ d: DatosInicio) -> [PersonaHoy] {
        let hoy = d.agenda.filter { $0.estado == "pendiente" && Formato.calendario.isDateInToday($0.empiezaEn) }
        return d.equipo.filter { $0.usuarioId != yo && $0.rol != "lector" }.map { m in
            let suyas = hoy.filter { $0.agenteId == m.usuarioId }
            var porTipo: [(String, Int)] = []
            for c in suyas {
                let t = c.tipo ?? "otro"
                if let i = porTipo.firstIndex(where: { $0.0 == t }) { porTipo[i].1 += 1 } else { porTipo.append((t, 1)) }
            }
            let sin = d.conversaciones.filter { $0.agenteId == m.usuarioId }
            let desde = sin.compactMap { $0.ultimoEntranteEn ?? $0.ultimoMensajeEn }.min()
            let lic = deLicencia(d, m.usuarioId).map { (tipo: $0.tipo ?? "licencia", vuelve: CuentasInicio.vuelveDe($0.hasta)) }
            return PersonaHoy(id: m.usuarioId, nombre: m.completo, foto: m.foto, telefono: m.telefono, citas: porTipo,
                              sinResponder: sin.count, desde: desde, licencia: lic)
        }
    }

    private func pasosVisibles(_ d: DatosInicio) -> Bool {
        guard let g = d.guia else { return false }
        return !(pasosOcultos ?? g.pasosOcultos ?? false) && !CuentasInicio.primerosPasos(g, duenio: estado.esDuenio).isEmpty
    }

    private func proximos(_ d: DatosInicio) -> [ProximoInicio] {
        CuentasInicio.proximosPasos(d.guia, duenio: estado.esDuenio, pasosVisibles: pasosVisibles(d),
                                    libres: consultas(d).filter { $0.responsableId == nil }.count)
    }

    private func acciones(_ d: DatosInicio) -> [AccionInicio] {
        let todas = CuentasInicio.accionesRapidas(d.guia, web: d.inmo?.web != nil)
        return estado.escribe ? todas : todas.filter { $0.clave == "web" }
    }

    // MARK: Acciones

    private func hacerAccion(_ clave: String) {
        switch clave {
        case "captar": estado.miraAbierta = true
        case "propiedad": estado.abrir(AAltaPropiedad())
        case "contacto": cargando = .contacto
        case "visita": cargando = .visita
        case "cobro": estado.abrir(ARegistrarCobro())
        case "web": abrirWeb()
        default: break
        }
    }

    private func abrirWeb() {
        vioLaWeb()
        if let w = datos?.inmo?.web, let u = URL(string: w) { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
    }

    /// «Mirá tu web» queda hecho al abrirla desde el Inicio.
    private func vioLaWeb() {
        guard datos?.guia?.pasos?.web != true, !marcados.contains("web") else { return }
        marcados.insert("web")
        struct C: Encodable { var webVista = true }
        Task {
            do { try await estado.api.hacer("PATCH", "/v1/panel/guia", C()) } catch { marcados.remove("web") }
        }
    }

    private func hacerPaso(_ p: PasoInicio) {
        switch p.clave {
        case "propiedad": estado.miraAbierta = true
        case "web": abrirWeb()
        case "datos": estado.abrir(ASeccion(clave: "web"))
        case "whatsapp", "portales": estado.abrir(ASeccion(clave: "integraciones"))
        case "equipo": estado.abrir(ASeccion(clave: "equipo"))
        case "avisos": Task { await activarAvisos() }
        default: estado.altaAbierta = PasoAlta(clave: p.clave)
        }
    }

    /// «Activá los avisos»: pide el permiso ahí mismo; si estaba negado, lleva a Ajustes.
    private func activarAvisos() async {
        let c = UNUserNotificationCenter.current()
        if await c.notificationSettings().authorizationStatus == .denied {
            if let u = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(u, options: [:], completionHandler: nil) }
            return
        }
        await estado.pedirPermisoPush()
        let s = await c.notificationSettings().authorizationStatus
        if s == .authorized || s == .provisional || s == .ephemeral {
            marcados.insert("avisos")
            estado.avisar("Listo: te van a llegar los avisos")
        }
    }

    /// «Ocultar» (o se ocultan solos al completarlos): se guarda en la API, con «Deshacer».
    private func ocultarPasos(_ completo: Bool) {
        struct C: Encodable { var pasosOcultos: Bool }
        pasosOcultos = true
        Task {
            do {
                try await estado.api.hacer("PATCH", "/v1/panel/guia", C(pasosOcultos: true))
            } catch {
                pasosOcultos = false
                if !completo { estado.avisar(error) }
                return
            }
            if completo { return }
            estado.avisar("Ocultaste los primeros pasos") {
                pasosOcultos = false
                Task {
                    do { try await estado.api.hacer("PATCH", "/v1/panel/guia", C(pasosOcultos: false)) } catch {
                        pasosOcultos = true
                        estado.avisar(error)
                    }
                }
            }
        }
    }

    private func hacerProximo(_ clave: String) {
        switch clave {
        case "libres": estado.abrir(AContactos())
        case "propiedad": estado.miraAbierta = true
        case "nueva", "mas": estado.abrir(AAltaPropiedad())
        case "contacto": cargando = .contacto
        case "importar": estado.abrir(ASeccion(clave: "importar"))
        case "alta": estado.altaAbierta = PasoAlta(clave: datos?.guia?.alta?.faltan.first)
        case "whatsapp", "portales": estado.abrir(ASeccion(clave: "integraciones"))
        case "equipo": estado.abrir(ASeccion(clave: "equipo"))
        case "datos": estado.abrir(ASeccion(clave: "web"))
        case "visita": cargando = .visita
        default: estado.pestana = .propiedades
        }
    }

    /// «Asignar» (la dueña elige a quién) o «Tomarla» (el agente): al toque, con «Deshacer» que la devuelve.
    private func asignar(_ u: Urgente, _ a: (String, String)?) {
        guard let contacto = u.consultaContacto, let yo else { return }
        let quien = a ?? (yo, estado.usuario?.completo ?? "")
        let propia = quien.0 == yo
        struct C: Encodable { var agenteId: String? }
        struct R: Decodable { var antesId: String? }
        asignadas[contacto] = propia ? "tuya" : quien.1
        Task {
            let r: R
            do {
                r = try await estado.api.enviar("POST", "/v1/consultas/\(contacto)/asignar", C(agenteId: quien.0))
            } catch {
                asignadas[contacto] = nil
                estado.avisar(error)
                return
            }
            estado.avisar(propia ? "La consulta es tuya" : "Le pasaste la consulta a \(quien.1)") {
                asignadas[contacto] = nil
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/consultas/\(contacto)/asignar", C(agenteId: r.antesId))
                        estado.version += 1
                    } catch {
                        asignadas[contacto] = propia ? "tuya" : quien.1
                        estado.avisar(error)
                    }
                }
            }
        }
    }

    /// Tildar una cita de «Tu día» (la marca hecha; «Deshacer» la vuelve a pendiente).
    private func tildar(_ c: Cita, _ si: Bool) {
        struct C: Encodable { var estado: String }
        tildadas[c.id] = si
        Task {
            do {
                try await estado.api.hacer("PATCH", "/v1/agenda/\(c.id)", C(estado: si ? "hecha" : "pendiente"))
            } catch {
                tildadas[c.id] = !si
                estado.avisar(error)
                return
            }
            if si { estado.avisar("Listo: \(c.titulo ?? c.donde)") { tildar(c, false) } }
        }
    }

    /// El botón de una sugerencia: la aplica y lleva a la cosa.
    private func aplicar(_ s: SugerenciaInicio) {
        ocultas.insert(s.id)
        Task {
            do { try await estado.api.hacer("POST", "/v1/sugerencias/\(s.id)/aplicar") } catch let e as ErrorApi where e.estado == 409 {
                // Ya la resolvió otra persona: da lo mismo.
            } catch {
                ocultas.remove(s.id)
                estado.avisar(error)
            }
        }
        if let ir = s.boton.1 { estado.abrir(ir) }
    }

    /// La cruz: el descarte sale cuando vence el «Deshacer» (6 s), así deshacer no vuelve atrás en la API.
    private func descartar(_ s: SugerenciaInicio) {
        ocultas.insert(s.id)
        let t = Task {
            try? await Task.sleep(for: .seconds(6))
            if Task.isCancelled { return }
            do { try await estado.api.hacer("POST", "/v1/sugerencias/\(s.id)/descartar") } catch let e as ErrorApi where e.estado == 409 {
            } catch {
                ocultas.remove(s.id)
                estado.avisar(error)
            }
        }
        estado.avisar("Descartaste la sugerencia") {
            t.cancel()
            ocultas.remove(s.id)
        }
    }

    /// «Registrar cobro» (la hoja de Cobranzas con ese contrato, como `/cobranzas?registrar=1&contrato=`).
    private func cobrar(_ c: CobranzaInicio) { estado.abrir(ARegistrarCobro(contrato: c.contratoId)) }

    /// «Recordar»: la ficha del contrato con el recordatorio del mes que se debe (`?recordar=AAAA-MM`).
    private func recordar(_ c: CobranzaInicio) { estado.abrir(ARecordarMes(contrato: c.contratoId, periodo: String(c.vence.prefix(7)))) }

    // MARK: Datos

    private func ids(_ d: DatosInicio) -> Set<String> { Set(urgentes(d).map(\.id)) }

    private func cargar() async {
        do {
            let d = try await CuentasInicio.traer(estado)
            if let antes = datos { nuevas = ids(d).subtracting(ids(antes)) }
            datos = d
            asignadas = [:]
            tildadas = [:]
            pasosOcultos = nil
            error = nil
            estado.avisosPendientes = d.avisos
            ActividadVisita.actualizar(d.proxima?.cita)
            Guardado.guardar(d.panel, clave: "panel")
        } catch let e as ErrorApi {
            if datos == nil, let p = Guardado.leer(Panel.self, clave: "panel") {
                datos = DatosInicio(panel: p.0, actualizado: p.1, sinRed: e.sinConexion)
            } else if e.sinConexion {
                datos?.sinRed = true
            }
            if datos == nil { error = e }
        } catch {}
    }
}

// MARK: - Piezas del Inicio

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
                    .buttonStyle(Presionable())
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

/// Una tarjeta con título, cifra a la derecha, barra de 10 y un pie.
struct TarjetaAvance: View {
    var titulo: String
    var cifra: String
    var avance: Double
    /// La barra crece desde cero al aparecer.
    @State private var visto = false
    var color: Color = C.accion
    var degrade: [Color]? = nil
    var pie: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                Spacer()
                Text(cifra).estilo(.subheadFuerte).foregroundStyle(C.texto)
                    .contentTransition(.numericText()).animation(.snappy, value: cifra)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.hundida)
                    Capsule().fill(degrade.map { AnyShapeStyle(LinearGradient(colors: $0, startPoint: .leading, endPoint: .trailing)) } ?? AnyShapeStyle(color))
                        .frame(width: g.size.width * (visto ? min(1, max(0, avance)) : 0))
                }
            }
            .frame(height: 10)
            Text(pie).estilo(.footnote).foregroundStyle(C.texto2)
        }
        .padding(16)
        .tarjeta()
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.1).delay(0.15)) { visto = true } }
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
                .contentTransition(.numericText()).animation(.snappy, value: valor)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta(16)
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

// MARK: - Propuesta A («Mi inmobiliaria», 5/11): la marca primero

/// La portada del Inicio: la foto de portada de su web (o el color de su marca) de punta a punta, con el
/// logo, el nombre, los botones, el saludo y el resumen del día encima.
struct PortadaInicio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.colorScheme) private var esquema
    @AppStorage("tema") private var tema = "sistema"
    var inmo: Inmobiliaria?
    var saludo: String
    var resumen: String
    /// «BELGRANO 22°» al lado de la fecha (GET /v1/clima) y, de noche, la hora.
    var clima: Clima? = nil
    var noche = false
    var cargar: () -> Void

    private var fecha: String {
        var t = Formato.mayuscula(Formato.diaCompleto(Date()))
        if let c = clima { t += " · \(c.zona.uppercased()) \(c.temperatura)°" }
        if noche { t += " · \(Formato.horaDe(Date()))" }
        return t
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let p = inmo?.portadaUrl {
                    Foto(url: p)
                } else {
                    let c = inmo?.colorPrimario ?? C.verde700
                    LinearGradient(colors: [c.opacity(0.95), C.verde800], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 320)
            .overlay(LinearGradient(colors: [.black.opacity(0.25), .clear, C.fondo.opacity(0.92), C.fondo],
                                    startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if let l = inmo?.logoUrl {
                        AsyncImage(url: l) { $0.resizable().scaledToFit() } placeholder: { Color.white.opacity(0.3) }
                            .frame(width: 40, height: 40).background(.white)
                            .clipShape(.rect(cornerRadius: 11, style: .continuous))
                    } else {
                        Text(Formato.iniciales(inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "C"))
                            .font(Estilo(tamano: 15, peso: .bold, relativo: .headline).font).foregroundStyle(C.verde700)
                            .frame(width: 40, height: 40).background(Color(hex: 0xFFFDF8), in: .rect(cornerRadius: 11, style: .continuous))
                    }
                    Text((inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "").uppercased())
                        .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    Spacer(minLength: 4)
                    if estado.escribe { boton("plus", "Cargar", cargar) }
                    // Claro / oscuro en un toque (también arriba de «Más», con «Automático»).
                    boton(esquema == .dark ? "sun.max" : "moon", esquema == .dark ? "Pasar a modo claro" : "Pasar a modo oscuro") {
                        Haptico.seleccion()
                        tema = esquema == .dark ? "claro" : "oscuro"
                    }
                    boton("magnifyingglass", "Buscar") { estado.abrir(ABuscar()) }
                    boton("bell", "Avisos", insignia: estado.avisosPendientes) { estado.abrir(AAvisos()) }
                }
                Spacer(minLength: 0)
                Text(fecha).estilo(.subhead).foregroundStyle(C.texto2)
                Text(saludo).font(Estilo(tamano: 32, peso: .extrabold, tracking: -0.03, relativo: .largeTitle).font)
                    .foregroundStyle(C.texto).lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(resumen).estilo(.subhead).foregroundStyle(C.texto2).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 62).padding(.bottom, 14)
            .frame(height: 320, alignment: .topLeading)
        }
        .frame(height: 320)
        .clipped()
    }

    private func boton(_ icono: String, _ etiqueta: String, insignia: Int = 0, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: icono).font(.system(size: 18, weight: .semibold)).foregroundStyle(C.oro)
                .frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
                .overlay(alignment: .topTrailing) { if insignia > 0 { InsigniaRoja(n: insignia).offset(x: 4, y: -4) } }
        }
        .accessibilityLabel(etiqueta)
    }
}

/// «Tu cartera»: las propiedades recién movidas, con foto, para mandarlas o abrirlas.
struct CarteraVisual: View {
    @Environment(Estado.self) private var estado
    var props: [Propiedad]
    var total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TituloBloque(texto: "Tu cartera")
                Spacer()
                Button(total > 0 ? "Ver las \(total)" : "Ver todas") { estado.pestana = .propiedades }
                    .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(props.prefix(10)) { p in
                        Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Foto(url: p.miniatura).frame(width: 156, height: 112).clipShape(.rect(cornerRadius: 16, style: .continuous))
                                Text(p.precioTexto).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto).padding(.top, 4)
                                Text(p.nombre).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                            }
                            .frame(width: 156, alignment: .leading)
                        }
                        .buttonStyle(Presionable())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }
}

/// «Este mes»: lo que se movió, con el objetivo si hay uno.
struct EsteMes: View {
    @Environment(Estado.self) private var estado
    var n: Panel.Numeros?
    var objetivo: Objetivo?

    var body: some View {
        Button { estado.abrir(ASeccion(clave: "informe")) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Este mes").estilo(.subheadFuerte).foregroundStyle(C.texto2)
                    Spacer()
                    Text("Ver informe").font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                    cifra("\(n?.contactosNuevosMes ?? 0)", "consultas nuevas")
                    cifra("\(n?.cerradasMes ?? 0)", variacion(n?.cerradasMes, n?.cerradasMesAnterior))
                    cifra("\(n?.operacionesAbiertas ?? 0)", "operaciones abiertas")
                    cifra("\(n?.propiedadesNuevasMes ?? 0)", "propiedades nuevas")
                }
                if let o = objetivo, let meta = o.meta, meta > 0 {
                    let av = o.avance ?? 0
                    Text("Objetivo: \(Formato.numero(Int(meta))) · vas \(Formato.numero(Int(av))) (\(Int((av / meta * 100).rounded())) %)").estilo(.footnote).foregroundStyle(C.texto2)
                    GeometryReader { g in
                        Capsule().fill(C.pista).overlay(alignment: .leading) { Capsule().fill(C.oro).frame(width: g.size.width * min(1, av / meta)) }
                    }
                    .frame(height: 8)
                }
            }
            .padding(16).tarjeta()
        }
        .buttonStyle(Presionable())
    }

    private func variacion(_ a: Int?, _ b: Int?) -> String {
        guard let a, let b, b > 0 else { return "cerradas" }
        let d = a - b
        return d == 0 ? "cerradas · igual que el mes pasado" : "cerradas · \(d > 0 ? "+" : "")\(d) vs. el mes pasado"
    }

    private func cifra(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(Estilo(tamano: 24, peso: .extrabold, relativo: .title2).font).foregroundStyle(C.texto)
                .contentTransition(.numericText()).animation(.snappy, value: v)
            Text(t).estilo(.footnote).foregroundStyle(C.texto3).lineLimit(2)
        }
    }
}

/// «Todo Corredor»: las áreas principales a un toque (el resto, en «Más»).
struct TodoCorredor: View {
    @Environment(Estado.self) private var estado
    private var areas: [(String, String, AnyHashable)] {
        var a: [(String, String, AnyHashable)] = [("calendar", "Agenda", AAgendaDia()), ("person.2", "Contactos", AContactos()),
                                                  ("rectangle.split.3x1", "Operaciones", AOperaciones()), ("dollarsign.circle", "Cobranzas", ACobranzas()),
                                                  ("doc.text", "Contratos", AContratos())]
        if estado.esDuenio {
            a += [("building.columns", "Consorcios", ASeccion(clave: "consorcios")), ("globe", "Mi web", ASeccion(clave: "web")), ("chart.bar", "Informe", ASeccion(clave: "informe"))]
        } else {
            a += [("checklist", "Actas", ASeccion(clave: "inventarios")), ("flag", "Objetivos", ASeccion(clave: "objetivos")), ("square.grid.2x2", "Más", ASeccion(clave: "mas"))]
        }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TituloBloque(texto: "Todo Corredor")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                ForEach(areas, id: \.1) { icono, nombre, destino in
                    Button { estado.abrir(destino) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: icono).font(.system(size: 21, weight: .medium)).foregroundStyle(C.accion)
                                .frame(width: 58, height: 58).background(C.superficie, in: .rect(cornerRadius: 17, style: .continuous))
                                .sombraE1()
                            Text(nombre).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(Presionable())
                }
            }
        }
    }
}

/// Dónde está la portada del Inicio (para mostrar la franja de la hora cuando ya pasó).
struct AlturaPortada: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
