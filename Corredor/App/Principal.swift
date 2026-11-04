import SwiftUI

/// La app adentro (handoff · Navegación): cinco destinos (Inicio · Propiedades · MIRA · Mensajes ·
/// Agenda). MIRA es el botón oro elevado del centro y abre la cámara a pantalla completa. Cada pestaña
/// tiene su NavigationStack; Contactos, Operaciones, Cobranzas, Actas, Avisos y Perfil se apilan desde
/// Inicio. La barra es la del handoff (fondo `bar` con desenfoque, ícono 27, texto 10/600).
struct Principal: View {
    @Environment(Estado.self) private var estado
    @State private var recorrido = false

    var body: some View {
        @Bindable var estado = estado
        TabView(selection: $estado.pestana) {
            pestana(.inicio) { InicioRaiz() }
            pestana(.propiedades) { PropiedadesRaiz() }
            Color.clear.tag(Pestana.mira).toolbar(.hidden, for: .tabBar)
            pestana(.mensajes) { MensajesRaiz() }
            pestana(.agenda) { AgendaRaiz() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BarraPestanas() }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $estado.miraAbierta) {
            MiraRaiz().environment(estado).environment(estado.cola)
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
        .overlay { if recorrido { Recorrido(visible: $recorrido).zIndex(10) } }
        .task {
            // La primera vez (en cualquier aparato), el recorrido.
            if estado.usuario?.tourVisto != true, let g: Guia = try? await estado.api.get("/v1/panel/guia"), g.tourVisto != true { recorrido = true }
        }
    }

    private func pestana<V: View>(_ p: Pestana, @ViewBuilder _ raiz: () -> V) -> some View {
        NavigationStack(path: estado.pila(p)) {
            raiz().destinos()
        }
        .tag(p)
        .toolbar(.hidden, for: .tabBar)
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
        (.agenda, "Agenda", "calendar", "calendar"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { p, nombre, icono, lleno in
                Button {
                    if p == .mira {
                        Haptico.impacto()
                        estado.miraAbierta = true
                    } else if estado.pestana == p {
                        // Tocar la pestaña activa vuelve al principio.
                        estado.pilas[p] = NavigationPath()
                    } else {
                        Haptico.seleccion()
                        estado.pestana = p
                    }
                } label: {
                    if p == .mira {
                        VStack(spacing: 2) {
                            BotonMira()
                            Text("MIRA").estilo(.tab)
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
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 50)
                .accessibilityLabel(p == .mira ? "MIRA: fotografiar un cartel" : nombre)
                .accessibilityAddTraits(estado.pestana == p ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.tema(0xFAF8F2, 0x0E1714, alfa: 0.94, alfaOscuro: 0.92).opacity(0.7))
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func insignia(_ p: Pestana) -> Int? {
        p == .mensajes ? estado.sinLeer : nil
    }
}

/// El botón oro de MIRA: 58, degradé #f7cb73 → #f2bb57 → #e9ad44, aro de 4 del fondo y el visor de
/// cuatro esquinas en verde 0f3530.
struct BotonMira: View {
    var tam: CGFloat = 58
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
            Visor().frame(width: 24, height: 24)
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
