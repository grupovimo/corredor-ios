import SwiftUI

/// 3F Mandar la ficha (web: la hoja «Mandar {calle}»): a la persona que vino de su ficha, a los que
/// buscan algo así (con «coincide 87 %» o «Se la mandaste hace 2 d»), a cualquier otro contacto, o a
/// los tres primeros de una («Mandar a 3», uno detrás de otro). Cada envío queda anotado, con deshacer.
/// Además: copiar el link, la hoja del sistema, la ficha A4 y la tarjeta para la visita.
struct HojaCompartir: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: Propiedad
    var web: String?
    var interesados: [Interesado] = []
    /// La persona para la que se abrió (el «Mandar» de la ficha de un contacto).
    var destinatario: Contacto? = nil
    @State private var lista: [Interesado] = []
    @State private var q = ""
    @State private var encontrados: [Contacto] = []
    @State private var mandadas: [String: Date] = [:]
    /// «Mandar a 3»: los que faltan, de a uno (WhatsApp abre de a una conversación).
    @State private var enCola: [Interesado] = []
    @State private var previo: ArchivoPrevio?

    private var link: String { "\(web ?? "")/propiedades/\(propiedad.slug ?? propiedad.id)" }
    private var calle: String { (propiedad.direccion ?? propiedad.nombre).components(separatedBy: ",").first ?? propiedad.nombre }
    private func enviada(_ i: Interesado) -> Date? { mandadas[i.contactoId] ?? i.enviadaEn }
    private var sinMandar: [Interesado] { lista.filter { enviada($0) == nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cabecera
                if let d = destinatario {
                    tarjeta { filaContacto(d.nombre, mandadas[d.id].map { "Se la mandaste \(Formato.hace($0))" } ?? (d.telefono ?? "sin teléfono"), primera: true) { mandar(d.nombre, d.telefono, d.id) } }
                }
                if let siguiente = enCola.first {
                    Button { mandarSiguiente() } label: { Label("Seguí con \(siguiente.nombre.components(separatedBy: " ").first ?? siguiente.nombre) (\(enCola.count) más)", systemImage: "arrow.right.circle.fill") }
                        .buttonStyle(BotonPrincipal())
                }
                if !lista.isEmpty {
                    Text("BUSCAN ALGO ASÍ").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2)
                    tarjeta {
                        ForEach(Array(lista.prefix(5).enumerated()), id: \.element.id) { i, c in
                            let det = enviada(c).map { "Se la mandaste \(Formato.hace($0))" }
                                ?? "\(c.telefono ?? "sin teléfono") · coincide \(Formato.porcentaje(((c.puntaje ?? 0) * 100).rounded()))"
                            filaContacto(c.nombre, det, primera: i == 0) { mandar(c.nombre, c.telefono, c.contactoId) }
                        }
                    }
                }
                Buscador(placeholder: "Buscar otro contacto", texto: $q)
                if !encontrados.isEmpty {
                    tarjeta {
                        ForEach(Array(encontrados.enumerated()), id: \.element.id) { i, c in
                            filaContacto(c.nombre, mandadas[c.id].map { "Se la mandaste \(Formato.hace($0))" } ?? (c.telefono ?? "sin teléfono"), primera: i == 0) {
                                mandar(c.nombre, c.telefono, c.id)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { copiar() } label: { Label("Copiar link", systemImage: "link") }.buttonStyle(BotonHundido())
                    if sinMandar.count > 1 {
                        Button { mandarATodos() } label: { Label("Mandar a \(min(3, sinMandar.count))", systemImage: "square.and.arrow.up") }.buttonStyle(BotonHundido())
                    }
                }
                apps
                VStack(spacing: 0) {
                    Button {
                        Task { if let u = await FichaImpresa.a4(propiedad, api: estado.api) { previo = ArchivoPrevio(url: u) } }
                    } label: { filaHoja("Imprimir ficha A4", "printer") }
                    Rectangle().fill(C.linea).frame(height: 0.5)
                    Button {
                        cerrar()
                        estado.abrir(ATarjetaPropiedad(id: propiedad.id))
                    } label: { filaHoja("Tarjeta para dejar en la visita", "rectangle.portrait.on.rectangle.portrait") }
                }
                .background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
        }
        .background(C.hundida.ignoresSafeArea())
        .vistaPrevia($previo)
        .task {
            lista = interesados
            if lista.isEmpty {
                lista = (try? await estado.api.get("/v1/propiedades/\(propiedad.id)/interesados", query: [.init(name: "sinVisita", value: "si"), .init(name: "limite", value: "20")])) ?? []
            }
        }
        .task(id: q) {
            guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { encontrados = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            encontrados = ((try? await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "6"), .init(name: "q", value: q)])) as [Contacto]?) ?? []
        }
    }

    private var cabecera: some View {
        HStack(spacing: 10) {
            Foto(url: propiedad.miniatura).frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text("Mandar \(calle)").estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1)
                Text("Le llega por WhatsApp con el link de tu web.").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
            }
            Spacer()
            Button { cerrar() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(C.texto2)
                    .frame(width: 32, height: 32).background(C.superficie, in: Circle())
            }
            .accessibilityLabel("Cerrar")
        }
    }

    private var apps: some View {
        HStack(spacing: 0) {
            if let u = URL(string: link) {
                ShareLink(item: u, subject: Text(propiedad.nombre), message: Text(texto)) { botonApp("square.and.arrow.up", "Más", Color(hex: 0x8E8E93)) }
                Button { Afuera.whatsapp(nil, texto: texto + "\n" + link) } label: { botonApp(nil, "WhatsApp", Color(hex: 0x25D366)) }
                Button {
                    if let m = URL(string: "mailto:?subject=\(propiedad.nombre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(link)") { UIApplication.shared.open(m) }
                } label: { botonApp("envelope.fill", "Mail", Color(hex: 0x1D7CF2)) }
            }
            Spacer()
        }
    }

    private var texto: String { "\(propiedad.nombre) · \(propiedad.precioTexto)\n\(propiedad.resumen)" }

    private func tarjeta<V: View>(@ViewBuilder _ c: () -> V) -> some View {
        VStack(spacing: 0) { c() }.background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func filaContacto(_ nombre: String, _ detalle: String, primera: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                AvatarIniciales(nombre: nombre, tam: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    Text(detalle).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer()
                Image(systemName: "bubble.left.fill").foregroundStyle(C.okTinta)
            }
            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func copiar() {
        UIPasteboard.general.string = link
        estado.avisar("Link copiado. Pegalo donde quieras mandarlo.")
    }

    /// WhatsApp con el link, y el envío anotado (con deshacer, por si no se llegó a mandar).
    private func mandar(_ nombre: String, _ telefono: String?, _ contactoId: String?) {
        let primero = nombre.components(separatedBy: " ").first ?? nombre
        Afuera.whatsapp(telefono, texto: "Hola \(primero), te paso esta propiedad que te puede interesar: \(propiedad.direccion ?? propiedad.nombre) · \(propiedad.precioTexto)\n\(link)")
        guard let contactoId else { return }
        Task { await anotar(contactoId, primero) }
    }

    private func anotar(_ contactoId: String, _ primero: String) async {
        struct Cuerpo: Encodable { var contactoId: String; var canal = "whatsapp" }
        struct Envio: Decodable { var id: String; var enviadaEn: Date? }
        do {
            let e: Envio = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad.id)/envios", Cuerpo(contactoId: contactoId))
            mandadas[contactoId] = e.enviadaEn ?? Date()
            estado.version += 1
            estado.avisar("Anotamos que se la mandaste a \(primero)") {
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad.id)/envios/\(e.id)")
                        mandadas[contactoId] = nil
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch let e as ErrorApi where e.sinConexion {
            // Sin señal, el envío se anota cuando vuelva (el WhatsApp igual salió).
            _ = try? await estado.cola.enviar("POST", "/v1/propiedades/\(propiedad.id)/envios", Cuerpo(contactoId: contactoId), etiqueta: "Ficha a \(primero)")
        } catch {
            // Si no se anota, el WhatsApp igual salió.
        }
    }

    private func mandarATodos() {
        enCola = Array(sinMandar.prefix(3))
        mandarSiguiente()
    }

    private func mandarSiguiente() {
        guard let c = enCola.first else { return }
        enCola.removeFirst()
        mandar(c.nombre, c.telefono, c.contactoId)
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

/// 9C·err El error de un portal, explicado y con el arreglo: si falta la superficie o el precio, se
/// carga ahí y «Guardar y volver a publicar»; si son las fotos, «Sumar fotos»; si no, «Editar la ficha».
struct HojaArreglar: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: Propiedad
    var pub: PublicacionPortal
    /// Los otros lugares donde está publicada (se actualizan también).
    var otros: [String]
    @State private var valor = ""
    @State private var guardando = false

    private var campo: String? {
        let e = (pub.error ?? "").lowercased()
        if e.range(of: "superficie|area|surface", options: .regularExpression) != nil { return "superficie" }
        if e.range(of: "precio|price", options: .regularExpression) != nil { return "precio" }
        if e.range(of: "foto|picture|imagen", options: .regularExpression) != nil { return "fotos" }
        return nil
    }

    private var partes: (String, String) {
        let e = pub.error ?? ""
        if let r = e.range(of: ". ") { return (String(e[..<r.lowerBound]) + ".", String(e[r.upperBound...])) }
        return (e, "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                IconoTono(icono: "exclamationmark.triangle", tono: .rojo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pub.nombre) no la publicó").estilo(.tituloHojaChico).foregroundStyle(C.texto)
                    Text("\(propiedad.direccion ?? propiedad.nombre)\(pub.actualizadoEn.map { " · \(Formato.hace($0))" } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            (Text(partes.0).bold() + Text(" " + partes.1)
                + Text(campo == "superficie" && propiedad.cubierta != nil ? " Tenés cargados \(Formato.numero(Int(propiedad.cubierta ?? 0))) m² cubiertos." : ""))
                .estilo(.subhead).foregroundStyle(C.texto)
            switch campo {
            case "superficie":
                Campo(label: "Superficie total") {
                    TextField(propiedad.cubierta.map { String(Int(($0 * 1.08).rounded())) } ?? "50", text: $valor).keyboardType(.decimalPad)
                    Text("m²").foregroundStyle(C.texto2)
                }
            case "precio":
                Campo(label: "Precio") { TextField("", text: $valor).keyboardType(.numberPad) }
            case "fotos":
                Button { cerrar(); estado.abrir(AEditarEnPaso(id: propiedad.id, paso: "fotos")) } label: { Label("Sumar fotos", systemImage: "camera") }.buttonStyle(BotonHundido())
            default:
                Button { cerrar(); estado.abrir(AAltaPropiedad(editar: propiedad.id)) } label: { Label("Editar la ficha", systemImage: "pencil") }.buttonStyle(BotonHundido())
            }
            if !otros.isEmpty { Text("También se actualiza en \(Cartera.lista(otros)).").estilo(.footnote).foregroundStyle(C.texto2) }
            Spacer(minLength: 0)
            Button(guardando ? "Guardando…" : (campo == "superficie" || campo == "precio" ? "Guardar y volver a publicar" : "Volver a publicar")) {
                Task { await arreglar() }
            }
            .buttonStyle(BotonPrincipal()).disabled(guardando)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func arreglar() async {
        guardando = true
        defer { guardando = false }
        do {
            if campo == "superficie" || campo == "precio" {
                let n = Double(valor.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
                guard n > 0 else {
                    estado.avisar(campo == "superficie" ? "Poné la superficie total en m²." : "Poné el precio.", ok: false)
                    return
                }
                var p: Propiedad = try await estado.api.get("/v1/propiedades/\(propiedad.id)")
                if campo == "superficie" { p.superficie = n } else { p.precio = n }
                try await estado.api.hacer("PUT", "/v1/propiedades/\(p.id)", p)
            }
            try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad.id)/publicaciones/\(pub.portal)")
            estado.version += 1
            cerrar()
            estado.avisar("Guardada y mandada de nuevo")
        } catch { estado.avisar(error) }
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
        .onAppear { PantallasMostradas.cuenta += 1 }
        .task {
            if let p: Propiedad = try? await estado.api.get("/v1/propiedades/\(id)") { fotos = p.fotosUrl ?? [] }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
