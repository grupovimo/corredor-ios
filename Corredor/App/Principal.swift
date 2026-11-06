import SwiftUI

/// La app adentro (handoff · Navegación): cinco destinos (Inicio · Propiedades · MIRA · Mensajes ·
/// Agenda). MIRA es el botón oro elevado del centro y abre la cámara a pantalla completa. Cada pestaña
/// tiene su NavigationStack; Contactos, Operaciones, Cobranzas, Actas, Avisos y Perfil se apilan desde
/// Inicio. La barra es la del handoff (fondo `bar` con desenfoque, ícono 27, texto 10/600).
struct Principal: View {
    @Environment(Estado.self) private var estado
    @Environment(\.scenePhase) private var escena

    var body: some View {
        @Bindable var estado = estado
        // Las cuatro pilas, una encima de otra (sólo se ve la elegida y cada una guarda su estado). No es un
        // TabView: el de iOS no le pasa a sus pantallas el lugar que ocupa la barra propia y lo último
        // de cada lista quedaba tapado. Así, safeAreaInset llega a todas, también a las apiladas.
        ZStack {
            ForEach([Pestana.inicio, .propiedades, .mensajes, .mas], id: \.self) { p in
                let visible = estado.pestana == p
                pestana(p)
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .accessibilityHidden(!visible)
            }
        }
        // Al cambiar de pestaña, un fundido corto en vez de un salto.
        .animation(.easeInOut(duration: 0.18), value: estado.pestana)
        // El abanico del botón del medio, sobre el contenido y por encima de la barra.
        .overlay { if estado.accionesAbiertas { AccionesRapidas().transition(.opacity) } }
        .safeAreaInset(edge: .bottom, spacing: 0) { BarraPestanas() }
        // Por si el lugar de la barra no llega a alguna pantalla (pasó con el TabView y con las pilas): todo
        // lo que se desplaza —en cualquier pestaña y en lo apilado— deja libre el alto de la barra al final.
        .contentMargins(.bottom, 96, for: .scrollContent)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $estado.hojaRapida) { h in
            switch h {
            case .contacto: EditarContacto()
            case .visita: NuevaCita(dia: Date()).presentationDetents([.large])
            case .contrato: AltaContrato()
            }
        }
        .fullScreenCover(isPresented: $estado.miraAbierta) {
            MiraRaiz().environment(estado).environment(estado.cola)
        }
        // El alta de la inmobiliaria: la primera vez (sin logo ni WhatsApp no se entra) y desde «Completar».
        .fullScreenCover(item: $estado.altaAbierta) { p in
            AltaInmobiliaria(inicial: p.clave).environment(estado).environment(estado.cola)
        }
        .fullScreenCover(isPresented: $estado.bienvenidaAbierta, onDismiss: { estado.mostrarRecorrido = true }) {
            Bienvenida().environment(estado).environment(estado.cola)
        }
        .overlay(alignment: .bottom) {
            if let a = estado.aviso {
                VistaAviso(aviso: a) { estado.aviso = nil }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .animation(.spring(duration: 0.3), value: estado.aviso)
        .overlay { if estado.mostrarRecorrido { Recorrido(visible: $estado.mostrarRecorrido).zIndex(10) } }
        .task {
            // La primera vez (en cualquier aparato): quien se suma a un equipo pasa antes por su bienvenida
            // (al cerrarla sigue el recorrido); el dueño, directo al recorrido (el alta va aparte).
            if !ModoPrueba.activo, estado.usuario?.tourVisto != true, let g: Guia = try? await estado.api.get("/v1/panel/guia"), g.tourVisto != true {
                if estado.esDuenio { estado.mostrarRecorrido = true } else { estado.bienvenidaAbierta = true }
            }
        }
        // La suscripción (avisos de prueba y sólo lectura), al día con el tiempo real.
        .task(id: estado.version) { await estado.cargarSuscripcion() }
        // Las insignias de la barra y de «Más»: con cada cambio, al volver y cada minuto.
        .task(id: estado.version) { await Insignias.compartidas.refrescar(estado) }
        .task(id: "\(escena == .active)-insignias") {
            while escena == .active && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await Insignias.compartidas.refrescar(estado)
            }
        }
        // En vivo (App/Vivo.swift) con la app adelante; se corta al ir al fondo y vuelve al volver.
        .task(id: "\(escena == .active)-\(estado.sesion?.inmobiliariaId ?? "")") {
            if escena == .active { await estado.escucharEnVivo() }
        }
    }

    private func pestana(_ p: Pestana) -> some View {
        NavigationStack(path: estado.pila(p)) {
            Group {
                switch p {
                case .inicio: InicioRaiz()
                case .propiedades: PropiedadesRaiz()
                case .mensajes: MensajesRaiz()
                default: MasRaiz()
                }
            }
            .destinos()
        }
    }
}

/// La barra de pestañas del handoff, con el botón de MIRA (58, degradé oro, aro del color de fondo).
struct BarraPestanas: View {
    @Environment(Estado.self) private var estado

    private let items: [(Pestana, String, String, String)] = [
        (.inicio, "Inicio", "house", "house.fill"),
        (.propiedades, "Propiedades", "building.2", "building.2.fill"),
        (.mira, "MIRA", "", ""),
        (.mensajes, "Mensajes", "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill"),
        (.mas, "Más", "square.grid.2x2", "square.grid.2x2.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { p, nombre, icono, lleno in
                Button {
                    if p == .mira {
                        Haptico.impacto()
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { estado.accionesAbiertas.toggle() }
                    } else if estado.pestana == p {
                        estado.accionesAbiertas = false
                        // Tocar la pestaña activa vuelve al principio.
                        estado.pilas[p] = NavigationPath()
                    } else {
                        Haptico.seleccion()
                        estado.accionesAbiertas = false
                        estado.pestana = p
                    }
                } label: {
                    if p == .mira {
                        VStack(spacing: 2) {
                            BotonMira(abierto: estado.accionesAbiertas)
                            Text("Crear").estilo(.tab)
                        }
                        .foregroundStyle(C.texto3)
                    } else {
                        let activa = estado.pestana == p
                        VStack(spacing: 2) {
                            Image(systemName: activa ? lleno : icono)
                                .font(.system(size: 22, weight: .medium))
                                .frame(height: 27)
                                .overlay(alignment: .topTrailing) {
                                    if let n = insignia(p), n > 0 {
                                        Text(n > 99 ? "99+" : "\(n)")
                                            .font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .frame(minWidth: 18, minHeight: 18)
                                            .background(Color(hex: 0xE5484D), in: Capsule())
                                            .offset(x: 14, y: -4)
                                    }
                                }
                            Text(nombre).estilo(.tab)
                        }
                        .foregroundStyle(activa ? C.accion : C.texto3)
                    }
                }
                .buttonStyle(Presionable())
                .frame(maxWidth: .infinity, minHeight: 50)
                .accessibilityLabel(p == .mira ? (estado.accionesAbiertas ? "Cerrar las acciones rápidas" : "Acciones rápidas: captar, cargar, cobrar, editar la web") : nombre)
                .accessibilityAddTraits(estado.pestana == p ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.tema(0xFAF8F2, 0x111314, alfa: 0.94, alfaOscuro: 0.92).opacity(0.7))
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Mensajes: la bandeja (WhatsApp sin leer y preguntas de Mercado Libre); Más: los cobros atrasados.
    private func insignia(_ p: Pestana) -> Int? {
        switch p {
        case .mensajes: return estado.sinLeer
        case .mas: return Insignias.compartidas.cobranzas
        default: return nil
        }
    }
}

/// El botón oro de MIRA: 58, degradé #f7cb73 → #f2bb57 → #e9ad44, aro de 4 del fondo y el visor de
/// cuatro esquinas en verde 0f3530.
struct BotonMira: View {
    var tam: CGFloat = 58
    /// Con el abanico abierto, el «+» gira a «×».
    var abierto = false
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(stops: [.init(color: Color(hex: 0xF7CB73), location: 0),
                                             .init(color: Color(hex: 0xF2BB57), location: 0.55),
                                             .init(color: Color(hex: 0xE9AD44), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1).blendMode(.overlay))
                .padding(-4)
                .background(Circle().fill(C.fondo).padding(-4))
            Image(systemName: "plus").font(.system(size: 26, weight: .bold)).foregroundStyle(C.verde800)
                .rotationEffect(.degrees(abierto ? 45 : 0))
        }
        .frame(width: tam, height: tam)
        .shadow(color: Color(hex: 0x7A5200, alfa: 0.7), radius: 11, y: 12)
        .padding(.top, -18)
    }
}

/// Las cuatro esquinas del visor de MIRA (3 de grosor, radio 3).
struct Visor: View {
    var color: Color = C.verde800
    var grosor: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            let l = g.size.width / 3
            Path { p in
                let w = g.size.width, h = g.size.height
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// 1D «Corredor está bloqueada»: tapa todo hasta identificarse con Face ID.
struct Bloqueo: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        ZStack {
            FondoVerde(patron: 0.08)
            VStack(spacing: 18) {
                Image("IconoRedondo").resizable().scaledToFit().frame(width: 84)
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 20)
                Text("Corredor está bloqueada").font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font).foregroundStyle(.white)
                Text("Para cuidar los datos de tus clientes.").estilo(.subhead).foregroundStyle(Color(hex: 0xCFE0D8))
                Button {
                    Task { await estado.desbloquear() }
                } label: {
                    Image(systemName: "faceid").font(.system(size: 50, weight: .light)).foregroundStyle(C.oro)
                        .frame(width: 96, height: 96)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.2)))
                }
                .padding(.top, 24)
                .accessibilityLabel("Desbloquear con Face ID")
                Text("Tocá para usar Face ID").estilo(.subheadFuerte).foregroundStyle(.white)
            }
        }
        .task { await estado.desbloquear() }
    }
}

extension View {
    /// Todos los destinos de la app (cada área registra los suyos en Pantallas/<Área>/).
    func destinos() -> some View {
        self
            .destinosInicio()
            .destinosPropiedades()
            .destinosMira()
            .destinosMensajes()
            .destinosAgenda()
            .destinosCartera()
            .destinosCobranzas()
            .destinosSecciones()
    }
}

/// Las hojas de alta que abre una acción rápida.
enum HojaRapida: String, Identifiable {
    case contacto, visita, contrato
    var id: String { rawValue }
}

/// El abanico del botón del medio: círculos en arco con las acciones rápidas (MIRA es una más). Llega a
/// cosas que no están a mano en las pestañas, como editar la web. Las acciones las da la API (las
/// mismas que el panel, sin las de rubros que la inmobiliaria no usa).
struct AccionesRapidas: View {
    @Environment(Estado.self) private var estado
    @State private var visible = false

    private struct Accion: Identifiable {
        var icono: String
        var nombre: String
        var destacada = false
        var hacer: () -> Void
        var id: String { nombre }
    }

    /// Qué hace cada clave de la API.
    private func accion(_ clave: String, _ nombre: String) -> Accion? {
        let e = estado
        func ir(_ d: AnyHashable) -> () -> Void { { e.abrir(d) } }
        let icono = Lugares.rapidas[clave] ?? "circle"
        switch clave {
        case "captar": return Accion(icono: icono, nombre: nombre, destacada: true) { e.miraAbierta = true }
        case "propiedad": return Accion(icono: icono, nombre: nombre, hacer: ir(AAltaPropiedad()))
        case "contacto": return Accion(icono: icono, nombre: nombre) { e.hojaRapida = .contacto }
        case "visita": return Accion(icono: icono, nombre: nombre) { e.hojaRapida = .visita }
        case "contrato": return Accion(icono: icono, nombre: nombre) { e.hojaRapida = .contrato }
        case "cobrar": return Accion(icono: icono, nombre: nombre, hacer: ir(ACobranzas()))
        case "web": return Accion(icono: icono, nombre: nombre, hacer: ir(ASeccion(clave: "web")))
        case "buscar": return Accion(icono: icono, nombre: nombre, hacer: ir(ABuscar()))
        case "agenda": return Accion(icono: icono, nombre: nombre, hacer: ir(AAgendaDia()))
        case "avisos": return Accion(icono: icono, nombre: nombre, hacer: ir(AAvisos()))
        default: return nil
        }
    }

    private var acciones: [Accion] {
        let e = estado
        // Las de la API; sin ella todavía, las de siempre según el rol.
        var rapidas: [(String, String)]
        if let r = e.estructura?.rapidas {
            rapidas = r.map { ($0.clave, $0.nombre) }
        } else if e.escribe {
            rapidas = [("captar", "Captar"), ("propiedad", "Propiedad"), ("contacto", "Contacto"), ("visita", "Visita"), ("contrato", "Contrato"), ("cobrar", "Cobrar")]
            if e.esDuenio { rapidas.append(("web", "Mi web")) }
        } else {
            rapidas = [("buscar", "Buscar"), ("agenda", "Agenda"), ("avisos", "Avisos")]
        }
        return rapidas.compactMap { accion($0.0, $0.1) }
    }

    /// Dónde va cada acción (el centro de su círculo con el nombre), sobre el botón del medio. `alto` es
    /// lo que queda arriba de la barra. Hasta cuatro, en arco de 160° a 20° (no de 180° a 0°: en las
    /// puntas el nombre caía debajo de la barra y no se leía). Con más no entran en un arco sin
    /// pisarse a 375: van en dos filas apenas curvas (la de abajo con la mitad más uno).
    static func posiciones(cantidad n: Int, ancho: CGFloat, alto: CGFloat) -> [CGPoint] {
        guard n > 0 else { return [] }
        let base = alto - 20 - tamanoAccion.height / 2
        if n <= 4 {
            let radio = min(ancho / 2 - tamanoAccion.width / 2 - 12, 140)
            let centro = CGPoint(x: ancho / 2, y: base + radio * 0.34)
            return (0..<n).map { i in
                let t = n > 1 ? Double(i) / Double(n - 1) : 0.5
                let angulo = (160 - 140 * t) * .pi / 180
                return CGPoint(x: centro.x + cos(angulo) * radio, y: centro.y - sin(angulo) * radio)
            }
        }
        let abajo = (n + 1) / 2
        let paso = min((ancho - 24) / CGFloat(abajo), 88)
        func fila(_ cuantos: Int, _ y: CGFloat) -> [CGPoint] {
            (0..<cuantos).map { i in
                let x = ancho / 2 + (CGFloat(i) - CGFloat(cuantos - 1) / 2) * paso
                // Apenas curva: las del medio un poco más arriba.
                let d = abs(x - ancho / 2) / max(ancho / 2, 1)
                return CGPoint(x: x, y: y - 12 * (1 - d * d))
            }
        }
        return fila(n - abajo, base - tamanoAccion.height - 18) + fila(abajo, base)
    }

    /// El tamaño de cada acción: el círculo de 56 y el nombre abajo (para las pruebas de que entra).
    static let tamanoAccion = CGSize(width: 76, height: 56 + 6 + 16)

    var body: some View {
        let lista = acciones
        GeometryReader { g in
            ZStack {
                Rectangle().fill(.black.opacity(0.45)).background(.ultraThinMaterial.opacity(0.6))
                    .ignoresSafeArea()
                    .onTapGesture { cerrar() }
                    .accessibilityLabel("Cerrar las acciones rápidas")
                    .accessibilityAddTraits(.isButton)
                let puntos = Self.posiciones(cantidad: lista.count, ancho: g.size.width, alto: g.size.height)
                let origen = CGPoint(x: g.size.width / 2, y: g.size.height + 6)
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, a in
                    Button {
                        Haptico.seleccion()
                        cerrar()
                        a.hacer()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: a.icono).font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(a.destacada ? C.verde800 : C.accion)
                                .frame(width: 56, height: 56)
                                .background(a.destacada ? AnyShapeStyle(C.oro) : AnyShapeStyle(C.superficie), in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                            Text(a.nombre).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(.white)
                                .lineLimit(1).fixedSize()
                                .shadow(color: .black.opacity(0.5), radius: 3)
                        }
                    }
                    .buttonStyle(Presionable())
                    .scaleEffect(visible ? 1 : 0.3)
                    .opacity(visible ? 1 : 0)
                    .position(visible ? puntos[i] : origen)
                    .animation(.spring(duration: 0.4, bounce: 0.35).delay(Double(i) * 0.025), value: visible)
                }
            }
        }
        .onAppear { visible = true }
    }

    private func cerrar() {
        withAnimation(.easeOut(duration: 0.2)) { estado.accionesAbiertas = false }
    }
}
