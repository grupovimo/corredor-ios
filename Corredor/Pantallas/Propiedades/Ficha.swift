import SwiftUI

/// 3D Ficha de una propiedad: foto grande (toca para la galería), precio, datos, interesados, dónde
/// está publicada y la barra «Agendar · Mandar por WhatsApp». Además, todo lo del panel: editar, estado,
/// publicar o pausar en cada portal, reservas, tarifas de temporada, actas, vistas y borrar.
struct FichaPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State private var p: Propiedad?
    @State private var interesados: [Interesado] = []
    @State private var pubs: [PublicacionPortal] = []
    @State private var senal: Senal?
    @State private var web: String?
    @State private var error: ErrorApi?
    @State private var compartir = false
    @State private var agendar = false
    @State private var reservar = false
    @State private var portalEnUso: String?

    var body: some View {
        Group {
            if let p { contenido(p) } else if let error {
                EstadoError(que: "la propiedad", error: error) { Task { await cargar() } }.frame(maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $compartir) { if let p { HojaCompartir(propiedad: p, web: web, interesados: interesados).presentationDetents([.medium, .large]) } }
        .sheet(isPresented: $agendar) { if let p { NuevaCita(propiedad: p).presentationDetents([.large]) } }
        .sheet(isPresented: $reservar) { if let p { NuevaReserva(propiedad: p).presentationDetents([.medium, .large]) } }
        .userActivity("ar.com.corredor.app.propiedad", isActive: p != nil) { a in
            a.title = p?.nombre
            a.userInfo = ["id": id]
            a.isEligibleForSearch = true
            a.isEligibleForPrediction = true
        }
    }

    private func contenido(_ p: Propiedad) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { estado.abrir(AGaleria(id: p.id)) } label: {
                    Foto(url: p.portada).frame(height: 380).frame(maxWidth: .infinity)
                        .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                                        .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.35), location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .bottomTrailing) {
                            if let n = p.fotosUrl?.count, n > 0 {
                                Label("1 / \(n)", systemImage: "photo.on.rectangle").font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 26)
                                    .background(.black.opacity(0.55), in: Capsule()).padding(.trailing, 16).padding(.bottom, 34)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver las fotos")

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        let (chip, tono) = PropiedadesRaiz.chip(p, senal)
                        Text(chip).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                            .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                        Text(p.precioTexto).font(Estilo(tamano: 30, peso: .extrabold, tracking: -0.03, relativo: .title).font).foregroundStyle(C.texto)
                        Text([p.direccion ?? p.nombre, p.barrio].compactMap { $0 }.joined(separator: " · ")).estilo(.body16).foregroundStyle(C.texto2)
                        if let e = p.expensas, e > 0 { Text("Expensas \(Formato.plata(e, "ARS"))").estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(datos(p), id: \.1) { icono, texto in
                            VStack(spacing: 4) {
                                Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.accion)
                                Text(texto).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 66).tarjeta(14)
                        }
                    }
                    if let d = p.descripcion?.nonEmpty {
                        Text(d).estilo(.body16).foregroundStyle(C.texto).lineLimit(8)
                    }
                    if !interesados.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            TituloBloque(texto: "Interesados", cuenta: "\(interesados.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(interesados.prefix(6).enumerated()), id: \.element.id) { i, x in
                                    Button { estado.abrir(AFichaContacto(id: x.contactoId)) } label: {
                                        HStack(spacing: 12) {
                                            let tono: Tono = x.visito == true ? .oro : (x.enviadaEn != nil ? .neutro : .azul)
                                            Text(Formato.iniciales(x.nombre)).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                                                .foregroundStyle(tono.tinta).frame(width: 36, height: 36).background(tono.fondo, in: Circle())
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(x.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                                Text(x.visito == true ? "Ya la visitó" : x.enviadaEn.map { "Le mandaste la ficha \(Formato.hace($0))" } ?? "Le encaja por lo que busca")
                                                    .estilo(.footnote).foregroundStyle(C.texto2)
                                            }
                                            Spacer()
                                            Chevron()
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: "Dónde está publicada")
                        VStack(spacing: 0) {
                            filaPortal("web", "Tu web", web.map { "\($0.replacingOccurrences(of: "https://", with: ""))/propiedades/\(p.slug ?? "")" } ?? "",
                                       publicada: p.publicada == true, primera: true)
                            ForEach(["mercadolibre", "zonaprop", "argenprop"], id: \.self) { portal in
                                let x = pubs.first { $0.portal == portal }
                                filaPortal(portal, PublicacionPortal.nombres[portal] ?? portal, detallePortal(x), publicada: x?.estado == "publicada" || x?.estado == "activa",
                                           error: x?.error, primera: false)
                            }
                        }
                        .tarjeta()
                    }
                    if estado.escribe { acciones(p) }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 120)
                .background(FondoApp().clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)))
                .padding(.top, -22)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { botonesArriba }
        .overlay(alignment: .bottom) { barra(p) }
        .refreshable { await cargar() }
    }

    private var botonesArriba: some View {
        HStack {
            circulo("chevron.left", "Volver") { cerrar() }
            Spacer()
            circulo(p?.destacada == true ? "star.fill" : "star", "Destacada") { destacar() }
            circulo("square.and.arrow.up", "Compartir") { compartir = true }
        }
        .padding(.horizontal, 16)
    }

    private func circulo(_ icono: String, _ etiqueta: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: icono).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.ultraThinMaterial.opacity(0.9), in: Circle())
                .background(Color(white: 0.08, opacity: 0.45), in: Circle())
        }
        .accessibilityLabel(etiqueta)
    }

    private func barra(_ p: Propiedad) -> some View {
        HStack(spacing: 10) {
            Button { agendar = true } label: {
                Label("Agendar", systemImage: "calendar").font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                    .frame(width: 120, height: 52).background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
            }
            Button { compartir = true } label: {
                HStack(spacing: 8) {
                    Image("LogoWhatsApp").renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20)
                    Text("Mandar por WhatsApp").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font)
                }
                .foregroundStyle(Color(hex: 0x0B3D1F))
                .frame(maxWidth: .infinity, minHeight: 52).background(Color(hex: 0x25D366), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    private func datos(_ p: Propiedad) -> [(String, String)] {
        var d: [(String, String)] = []
        if let a = p.ambientes { d.append(("bed.double", "\(a) amb")) }
        if let s = p.superficie { d.append(("ruler", "\(Formato.numero(Int(s))) m²")) }
        if let b = p.banos { d.append(("shower", Formato.cantidad(b, "baño", "baños"))) }
        if let c = p.cocheras, c > 0 { d.append(("car", Formato.cantidad(c, "cochera", "cocheras"))) }
        if p.aptoCredito == true { d.append(("checkmark.seal", "Apto crédito")) }
        for c in (p.comodidades ?? []).prefix(max(0, 4 - d.count)) { d.append(("sparkles", c.capitalized)) }
        return Array(d.prefix(8))
    }

    private func detallePortal(_ x: PublicacionPortal?) -> String {
        guard let x else { return "Sin publicar" }
        if let e = x.error { return e }
        switch x.estado {
        case "publicada", "activa": return [x.visitasSemana.map { "\($0) visitas esta semana" }, x.consultas.map { Formato.cantidad($0, "consulta", "consultas") }].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Publicada"
        case "pausada": return "Pausada"
        case "pendiente": return "Publicando…"
        default: return x.estado.capitalized
        }
    }

    private func filaPortal(_ portal: String, _ nombre: String, _ detalle: String, publicada: Bool, error: String? = nil, primera: Bool) -> some View {
        HStack(spacing: 12) {
            LogoPortal(portal: portal).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(nombre).estilo(.filaLista).foregroundStyle(C.texto)
                Text(detalle).estilo(.footnote).foregroundStyle(error != nil ? C.errorTinta : C.texto2).lineLimit(2)
            }
            Spacer()
            if portalEnUso == portal { ProgressView() }
            else if publicada { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0x2F9E6F)) }
            else if error != nil { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 22)).foregroundStyle(C.error) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contentShape(Rectangle())
        .contextMenu {
            if estado.escribe {
                if publicada {
                    Button { Task { await portalAccion(portal, pausar: true) } } label: { Label("Pausar en \(nombre)", systemImage: "pause.circle") }
                } else {
                    Button { Task { await portalAccion(portal, pausar: false) } } label: { Label("Publicar en \(nombre)", systemImage: "arrow.up.circle") }
                }
            }
        }
        .onTapGesture {
            guard estado.escribe else { return }
            Task { await portalAccion(portal, pausar: publicada) }
        }
    }

    @ViewBuilder
    private func acciones(_ p: Propiedad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Más")
            VStack(spacing: 0) {
                filaAccion("pencil", "Editar la propiedad") { estado.abrir(AAltaPropiedad(borrador: p.id)) }
                filaAccion("arrow.triangle.2.circlepath", "Cambiar el estado") { cambiarEstado = true }
                if p.operacion == "venta" || p.operacion == "alquiler" { filaAccion("hand.raised", "Tomar una reserva") { reservar = true } }
                if p.operacion == "temporario" || p.tambienTemporario == true { filaAccion("calendar.badge.clock", "Tarifas y disponibilidad") { estado.abrir(ASeccion(clave: "tarifas", id: p.id)) } }
                filaAccion("checklist", "Inventario y actas") { estado.abrir(ASeccion(clave: "actas", id: p.id)) }
                filaAccion("chart.bar", "Vistas y consultas") { estado.abrir(ASeccion(clave: "vistas", id: p.id)) }
                filaAccion("paperplane", "A quién se la mandaste") { estado.abrir(ASeccion(clave: "envios", id: p.id)) }
                filaAccion("waveform", "Recorridas dictadas") { estado.abrir(ASeccion(clave: "grabaciones", id: p.id)) }
                filaAccion("hand.raised", "Reservas") { estado.abrir(ASeccion(clave: "reservas-propiedad", id: p.id)) }
                filaAccion("plus.square.on.square", "Duplicar") { Task { await duplicar(p) } }
                if estado.esDuenio { filaAccion("trash", "Mandar a la papelera", rojo: true) { Task { await borrar(p) } } }
            }
            .tarjeta()
        }
        .confirmationDialog("Estado de la propiedad", isPresented: $cambiarEstado) {
            ForEach(Propiedad.estados, id: \.0) { k, n in
                Button(n) { Task { await ponerEstado(p, k) } }
            }
        }
    }

    @State private var cambiarEstado = false

    private func filaAccion(_ icono: String, _ texto: String, rojo: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 19)).foregroundStyle(rojo ? C.error : C.accion).frame(width: 24)
                Text(texto).estilo(.body16).foregroundStyle(rojo ? C.error : C.texto)
                Spacer()
                if !rojo { Chevron() }
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    // MARK: Acciones

    private func cargar() async {
        do {
            p = try await estado.api.get("/v1/propiedades/\(id)")
            error = nil
            interesados = (try? await estado.api.get("/v1/propiedades/\(id)/interesados")) ?? []
            pubs = (try? await estado.api.get("/v1/propiedades/\(id)/publicaciones")) ?? []
            let s: [Senal] = (try? await estado.api.get("/v1/propiedades/senales")) ?? []
            senal = s.first { $0.propiedadId == id }
            if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        } catch let e as ErrorApi { error = e } catch {}
    }

    private func destacar() {
        guard let p, estado.escribe else { return }
        struct Cuerpo: Encodable { var destacada: Bool }
        let nueva = !(p.destacada ?? false)
        self.p?.destacada = nueva
        Haptico.seleccion()
        Task { try? await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(destacada: nueva), etiqueta: "Destacar \(p.nombre)") }
    }

    private func ponerEstado(_ p: Propiedad, _ nuevo: String) async {
        struct Cuerpo: Encodable { var estado: String }
        let antes = p.estado ?? "disponible"
        do {
            try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: nuevo), etiqueta: "Estado de \(p.nombre)")
            estado.version += 1
            estado.avisar("Quedó \(Propiedad.estados.first { $0.0 == nuevo }?.1.lowercased() ?? nuevo)") {
                Task { try? await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: antes)); estado.version += 1 }
            }
        } catch { estado.avisar(error) }
    }

    private func portalAccion(_ portal: String, pausar: Bool) async {
        guard let p else { return }
        portalEnUso = portal
        defer { portalEnUso = nil }
        do {
            if portal == "web" {
                struct Cuerpo: Encodable { var publicada: Bool }
                try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: !pausar))
            } else if pausar {
                try await estado.api.hacer("POST", "/v1/propiedades/\(p.id)/publicaciones/\(portal)/pausar")
            } else {
                try await estado.api.hacer("POST", "/v1/propiedades/\(p.id)/publicaciones/\(portal)")
            }
            estado.avisar(pausar ? "Pausada en \(PublicacionPortal.nombres[portal] ?? portal)" : "Publicando en \(PublicacionPortal.nombres[portal] ?? portal)")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func duplicar(_ p: Propiedad) async {
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/propiedades/\(p.id)/duplicar", [String: String]())
            estado.abrir(AAltaPropiedad(borrador: n.id))
        } catch { estado.avisar(error) }
    }

    private func borrar(_ p: Propiedad) async {
        // Deshacer en vez de confirmar: se borra a los 5 s.
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            try? await estado.api.hacer("DELETE", "/v1/propiedades/\(p.id)")
            estado.version += 1
        }
        cerrar()
        estado.avisar("\(p.nombre) va a la papelera") { tarea.cancel() }
    }
}

/// El logo de un portal (la rr para la web).
struct LogoPortal: View {
    var portal: String
    var body: some View {
        Group {
            switch portal {
            case "web": Image("IconoRedondo").resizable().scaledToFit()
            case "mercadolibre": Image("LogoMercadoLibre").resizable().scaledToFit().padding(3)
            default: Text(String(portal.prefix(1)).uppercased()).font(Estilo.headline.font).foregroundStyle(C.verde700)
            }
        }
        .frame(width: 32, height: 32)
        .background(.white, in: .rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
    }
}

/// 3E Galería: fotos a pantalla completa, deslizables, con la tira de miniaturas.
struct Galeria: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State var indice: Int
    @State private var fotos: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { cerrar() } label: { Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Cerrar")
                Spacer()
                Text(fotos.isEmpty ? "" : "\(indice + 1) de \(fotos.count)").font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font)
                Spacer()
                if let u = fotos[safe: indice].flatMap(URL.init(string:)) {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up").font(.system(size: 19)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Compartir")
                } else { Color.clear.frame(width: 44, height: 44) }
            }
            .foregroundStyle(.white).padding(.horizontal, 8)
            TabView(selection: $indice) {
                ForEach(Array(fotos.enumerated()), id: \.offset) { i, f in
                    AsyncImage(url: URL(string: f)) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            ScrollViewReader { lector in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(fotos.enumerated()), id: \.offset) { i, f in
                            AsyncImage(url: URL(string: f + (f.contains("?") ? "&" : "?") + "tam=chica")) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                                .frame(width: 60, height: 52).clipShape(.rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(i == indice ? .white : .clear, lineWidth: 2))
                                .opacity(i == indice ? 1 : 0.55)
                                .id(i)
                                .onTapGesture { withAnimation { indice = i } }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: indice) { _, n in withAnimation { lector.scrollTo(n, anchor: .center) } }
            }
            .padding(.bottom, 40).padding(.top, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .task {
            if let p: Propiedad = try? await estado.api.get("/v1/propiedades/\(id)") { fotos = p.fotosUrl ?? [] }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 3F Compartir la ficha: a un interesado por WhatsApp (queda registrado el envío), el link, la hoja
/// del sistema o la ficha A4.
struct HojaCompartir: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: Propiedad
    var web: String?
    var interesados: [Interesado] = []
    @State private var lista: [Interesado] = []
    @State private var previo: ArchivoPrevio?

    private var link: URL? {
        guard let web, let slug = propiedad.slug else { return nil }
        return URL(string: "\(web)/propiedades/\(slug)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Foto(url: propiedad.miniatura).frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(propiedad.nombre) · \(propiedad.precioTexto)").estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1)
                    Text(link?.absoluteString.replacingOccurrences(of: "https://", with: "") ?? "").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer()
                Button { cerrar() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(C.texto2)
                        .frame(width: 32, height: 32).background(C.superficie, in: Circle())
                }
                .accessibilityLabel("Cerrar")
            }
            if !lista.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(lista.prefix(8)) { x in
                            Button { mandar(a: x) } label: {
                                VStack(spacing: 6) {
                                    Text(Formato.iniciales(x.nombre)).font(Estilo(tamano: 18, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                                        .frame(width: 60, height: 60).background(C.superficie, in: Circle())
                                        .overlay(alignment: .bottomTrailing) {
                                            Image("LogoWhatsApp").resizable().frame(width: 22, height: 22).background(.white, in: Circle()).offset(x: 2, y: 2)
                                        }
                                    Text(x.nombre.split(separator: " ").first.map(String.init) ?? x.nombre)
                                        .font(Estilo(tamano: 12, peso: .medium, relativo: .caption).font).foregroundStyle(C.texto).lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                if let link {
                    ShareLink(item: link, subject: Text(propiedad.nombre), message: Text(texto)) {
                        botonApp("square.and.arrow.up", "Más", Color(hex: 0x8E8E93))
                    }
                    Button { Afuera.whatsapp(nil, texto: texto + "\n" + link.absoluteString) } label: { botonApp(nil, "WhatsApp", Color(hex: 0x25D366)) }
                    Button { if let u = URL(string: "mailto:?subject=\(propiedad.nombre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(link.absoluteString)") { UIApplication.shared.open(u) } } label: {
                        botonApp("envelope.fill", "Mail", Color(hex: 0x1D7CF2))
                    }
                }
                Spacer()
            }
            VStack(spacing: 0) {
                Button {
                    UIPasteboard.general.url = link
                    estado.avisar("Link copiado")
                    cerrar()
                } label: { filaHoja("Copiar link de la ficha", "doc.on.doc") }
                Rectangle().fill(C.linea).frame(height: 0.5)
                Button {
                    Task { if let u = await Documentos.ficha(propiedad, api: estado.api) { previo = ArchivoPrevio(url: u) } }
                } label: { filaHoja("Imprimir ficha A4", "printer") }
            }
            .background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 20)
        .background(C.hundida.ignoresSafeArea())
        .vistaPrevia($previo)
        .task {
            lista = interesados
            if lista.isEmpty { lista = (try? await estado.api.get("/v1/propiedades/\(propiedad.id)/interesados")) ?? [] }
        }
    }

    private var texto: String { "\(propiedad.nombre) · \(propiedad.precioTexto)\n\(propiedad.resumen)" }

    /// Mandar la ficha a un interesado: WhatsApp con el link y el envío anotado en su ficha.
    private func mandar(a x: Interesado) {
        let nombre = x.nombre.split(separator: " ").first.map(String.init) ?? ""
        Afuera.whatsapp(x.telefono, texto: "Hola \(nombre), te paso \(propiedad.nombre): \(link?.absoluteString ?? "")")
        Task {
            struct Cuerpo: Encodable { var contactoId: String; var canal = "whatsapp" }
            try? await estado.cola.enviar("POST", "/v1/propiedades/\(propiedad.id)/envios", Cuerpo(contactoId: x.contactoId), etiqueta: "Ficha a \(x.nombre)")
            estado.version += 1
        }
        cerrar()
    }

    private func botonApp(_ icono: String?, _ texto: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Group {
                if let icono { Image(systemName: icono).font(.system(size: 26)).foregroundStyle(.white) }
                else { Image("LogoWhatsApp").renderingMode(.template).resizable().scaledToFit().frame(width: 34).foregroundStyle(.white) }
            }
            .frame(width: 60, height: 60).background(color, in: .rect(cornerRadius: 15, style: .continuous))
            Text(texto).font(Estilo(tamano: 12, peso: .medium, relativo: .caption).font).foregroundStyle(C.texto)
        }
        .frame(width: 72)
    }

    private func filaHoja(_ t: String, _ icono: String) -> some View {
        HStack {
            Text(t).estilo(.body16).foregroundStyle(C.texto)
            Spacer()
            Image(systemName: icono).foregroundStyle(C.texto)
        }
        .padding(.horizontal, 14).frame(height: 48).contentShape(Rectangle())
    }
}
