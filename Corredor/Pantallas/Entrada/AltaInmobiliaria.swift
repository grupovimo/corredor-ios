import SwiftUI

/// El alta de la inmobiliaria, paso por paso (los mismos que el panel web; los da la API): logo,
/// colores y frase, portada, contacto, datos legales, qué hacen y dónde, el arranque y «Así quedó tu
/// web». Obligatorios: el logo y el WhatsApp (sin ellos no se entra). Lo demás tiene «Más tarde» y
/// queda en el porcentaje. Cada paso guarda al seguir: si se cierra, se retoma en el mismo lugar. La
/// marca va al borrador de la web y se publica en el último paso.
struct AltaInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    /// El paso en el que abre (nil: el primero que falta).
    var inicial: String?

    @State private var alta: Alta?
    @State private var paso = ""
    @State private var marca: [String: JSONLibre] = [:]
    @State private var en: String?
    @State private var legales: [String: String] = [:]
    @State private var rubros: Set<String> = []
    @State private var zonas: [String] = []
    @State private var zonaNueva = ""
    @State private var sugeridos: [UInt32] = []
    @State private var guardando = false
    @State private var reescribiendo = false
    @State private var previa: URL?
    @State private var recarga = 0
    @State private var error: ErrorApi?

    private static let rubrosTodos = [("ventas", "Ventas", "tag"), ("alquileres", "Alquileres", "key"), ("temporada", "Temporada", "beach.umbrella"),
                                      ("emprendimientos", "Emprendimientos", "building"), ("consorcios", "Consorcios", "building.columns")]
    /// Los colores de siempre (después de los del logo).
    private static let principales: [UInt32] = [0x16443B, 0x1E3A5F, 0x7C2D12, 0x4A2C5A, 0x1F5A2A, 0xB45309]
    private static let acentos: [UInt32] = [0xF2BB57, 0xE9DCC3, 0x7FC4AD, 0xF28B7D]
    private static let legalesCampos = [("cuit", "CUIT", "30-71234567-1"), ("matricula", "Matrícula", "CUCICBA 1234"), ("colegio", "Colegio", "Opcional"),
                                        ("corredorResponsable", "Corredor responsable", "Opcional"), ("razonSocial", "Razón social", "Opcional")]

    private var pasos: [Alta.Paso] { alta?.pasos.filter { $0.clave != "nombre" } ?? [] }
    private var indice: Int { pasos.firstIndex { $0.clave == paso } ?? 0 }
    private var actual: Alta.Paso? { pasos.first { $0.clave == paso } }
    /// Lo mínimo para entrar (el logo y el WhatsApp), con lo cargado acá aunque la API no lo sepa todavía.
    private var minimoListo: Bool { !marca.texto("logoUrl").isEmpty && !marca.texto("whatsapp").isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if let a = actual {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            progreso
                            VStack(alignment: .leading, spacing: 6) {
                                Text(a.obligatorio ? "OBLIGATORIO" : "PASO \(indice + 1) DE \(pasos.count)")
                                    .font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.8).foregroundStyle(C.oroTinta)
                                Text(a.titulo).estilo(.tituloPaso).foregroundStyle(C.texto).accessibilityAddTraits(.isHeader)
                                Text(Formato.sinViudas(a.texto)).estilo(.subhead).foregroundStyle(C.texto2)
                            }
                            contenido(a.clave)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) { botones(a) }
                } else if let error {
                    EstadoError(que: "el alta", error: error) { Task { await cargar() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(FondoApp())
            .toolbar {
                if minimoListo || alta?.minimoListo == true {
                    ToolbarItem(placement: .cancellationAction) { Button("Ir al inicio") { cerrar() } }
                }
            }
        }
        .interactiveDismissDisabled(!(minimoListo || alta?.minimoListo == true))
        .task { await cargar() }
    }

    // MARK: Partes

    private var progreso: some View {
        HStack(spacing: 4) {
            ForEach(Array(pasos.enumerated()), id: \.element.id) { i, p in
                Capsule().fill(i == indice ? C.oro : p.hecho ? C.accion : C.linea).frame(height: 4)
            }
            Text("\(alta?.completo ?? 0)%").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).monospacedDigit()
                .foregroundStyle(C.texto2).padding(.leading, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paso \(indice + 1) de \(pasos.count). Tu inmobiliaria al \(alta?.completo ?? 0) por ciento")
    }

    @ViewBuilder
    private func contenido(_ clave: String) -> some View {
        switch clave {
        case "logo":
            SubirImagenMarca(titulo: "Subí tu logo", url: marca["logoUrl"]?.texto) { u, colores in
                marca["logoUrl"] = .texto(u)
                sugeridos = colores
                // Su color más fuerte queda elegido (se cambia en el paso que sigue).
                if marca.texto("colorPrimario").isEmpty, let c = colores.first { marca["colorPrimario"] = .texto(c.hexColor) }
                Task { await guardarMarca() }
            }
        case "marca":
            VStack(alignment: .leading, spacing: 22) {
                ElegirColor(titulo: "Color principal", sugeridos: sugeridos + Self.principales, hex: campo("colorPrimario"))
                ElegirColor(titulo: "Color de acento", sugeridos: Self.acentos + Array(sugeridos.dropFirst()), hex: campo("colorSecundario"))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frase de la portada").estilo(.filaLista).foregroundStyle(C.texto)
                    TextField("Tu próximo hogar en Palermo", text: campo("frase"), axis: .vertical).lineLimit(2...3)
                        .campoCorredor()
                    Button { Task { await frasePorIA() } } label: {
                        Label(reescribiendo ? "Escribiendo…" : "Escribila con IA", systemImage: "sparkles")
                    }
                    .buttonStyle(BotonSecundario())
                    .disabled(reescribiendo)
                }
            }
        case "portada":
            SubirImagenMarca(titulo: "Subí la foto de portada", url: marca["portadaUrl"]?.texto, ancha: true) { u, _ in
                marca["portadaUrl"] = .texto(u)
                Task { await guardarMarca() }
            }
        case "contacto":
            VStack(alignment: .leading, spacing: 14) {
                campoTexto("WhatsApp", "11 5555 0000", campo("whatsapp"), teclado: .phonePad)
                campoTexto("Teléfono", "Opcional", campo("telefono"), teclado: .phonePad)
                campoTexto("Mail", "Opcional", campo("email"), teclado: .emailAddress)
                campoTexto("Dirección", "Opcional", campo("direccion"))
                campoTexto("Horario", "Lunes a viernes de 10 a 18", campo("horario"))
            }
        case "legales":
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.legalesCampos, id: \.0) { k, n, p in
                    campoTexto(n, p, Binding(get: { legales[k] ?? "" }, set: { legales[k] = $0 }),
                               teclado: k == "cuit" ? .numbersAndPunctuation : .default)
                }
                Text(Formato.sinViudas("Van en el pie de tu web y en los recibos. En CABA y Provincia, la matrícula es obligatoria."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
        case "rubros":
            VStack(alignment: .leading, spacing: 18) {
                FlujoChips(items: Self.rubrosTodos.map { ($0.0, $0.1, $0.2) }, elegidos: $rubros)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dónde trabajan").estilo(.filaLista).foregroundStyle(C.texto)
                    if !zonas.isEmpty {
                        FlujoChips(items: zonas.map { ($0, $0, "xmark") }, elegidos: .constant(Set(zonas))) { z in zonas.removeAll { $0 == z } }
                    }
                    TextField("Palermo, Belgrano, Pilar…", text: $zonaNueva).campoCorredor()
                        .submitLabel(.done)
                        .onSubmit(sumarZona)
                }
                Text(Formato.sinViudas("Así la app te muestra sólo lo que usás. Lo cambiás cuando quieras."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
        case "arranque":
            VStack(spacing: 10) {
                tarjetaArranque("viewfinder", "Sacale una foto al cartel", "MIRA carga la propiedad sola.") { estado.miraAbierta = true }
                tarjetaArranque("house", "Cargá una propiedad", "Fotos, precio y listo.") { estado.abrir(AAltaPropiedad()) }
                tarjetaArranque("square.and.arrow.down", "Traé tu Excel", "Tu cartera de otro sistema.") { estado.abrir(ASeccion(clave: "importar")) }
                tarjetaArranque("person.badge.plus", "Invitá a tu equipo", "Cada agente con su cartera.") { estado.abrir(ASeccion(clave: "equipo")) }
                tarjetaArranque("bubble.left.and.bubble.right", "Conectá WhatsApp", "Las consultas en una bandeja.") { estado.abrir(ASeccion(clave: "integraciones")) }
                Text("Lo que no hagas ahora queda en tu Inicio.").estilo(.footnote).foregroundStyle(C.texto2)
            }
        case "publicar":
            VStack(spacing: 12) {
                MarcoPrevia(url: previa, recarga: recarga, alto: 480) { _ in }
                if let w = estado.inmobiliaria.map({ "\($0.slug).\(Api.web().host ?? "corredor.com.ar")" }) {
                    HStack {
                        Image(systemName: "globe").foregroundStyle(C.accion)
                        Text(w).estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1)
                        Spacer()
                        Button("Copiar") { UIPasteboard.general.string = "https://\(w)"; estado.avisar("Link copiado") }
                            .font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                    }
                    .padding(14).tarjeta()
                }
            }
            .task { previa = try? await BorradorWeb.urlPrevia(estado.api, slug: estado.inmobiliaria?.slug ?? "") }
        default:
            EmptyView()
        }
    }

    private func botones(_ a: Alta.Paso) -> some View {
        VStack(spacing: 4) {
            if a.clave == "publicar" {
                Button { Task { await terminar() } } label: {
                    Label(guardando ? "Publicando…" : "Publicar mi web", systemImage: "paperplane.fill")
                }
                .buttonStyle(BotonPrincipal())
                .disabled(guardando)
            } else {
                Button { Task { await seguir(a) } } label: {
                    Label(guardando ? "Guardando…" : "Seguir", systemImage: "arrow.right").labelStyle(TextoIcono())
                }
                .buttonStyle(BotonPrincipal())
                .disabled(guardando)
                if !a.obligatorio { Button("Más tarde") { ir(siguiente) }.buttonStyle(BotonTexto(alto: 44, color: C.texto2)) }
            }
            if indice > 0 { Button("Atrás") { ir(pasos[indice - 1].clave) }.buttonStyle(BotonTexto(alto: 40, color: C.texto2)) }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private func campoTexto(_ etiqueta: String, _ ejemplo: String, _ valor: Binding<String>, teclado: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(etiqueta).estilo(.label).foregroundStyle(C.texto)
            TextField(ejemplo, text: valor).keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .sentences)
                .campoCorredor()
        }
    }

    private func tarjetaArranque(_ icono: String, _ titulo: String, _ texto: String, _ hacer: @escaping () -> Void) -> some View {
        Button {
            // Se hace ahí mismo: el alta se cierra y vuelve desde «Completar». Lo que abre (MIRA es otra
            // pantalla completa) espera a que termine de cerrarse.
            cerrar()
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                hacer()
            }
        } label: {
            HStack(spacing: 12) {
                IconoTono(icono: icono, tono: .verde, tam: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).estilo(.filaLista).foregroundStyle(C.texto)
                    Text(texto).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.texto3)
            }
            .padding(14).contentShape(Rectangle()).tarjeta()
        }
        .buttonStyle(Presionable())
    }

    private func campo(_ k: String) -> Binding<String> {
        Binding(get: { marca.texto(k) }, set: { marca.poner(k, $0) })
    }

    private var siguiente: String? { indice + 1 < pasos.count ? pasos[indice + 1].clave : nil }

    private func ir(_ clave: String?) {
        guard let clave else { return }
        withAnimation(.easeInOut(duration: 0.2)) { paso = clave }
    }

    private func sumarZona() {
        let z = zonaNueva.trimmingCharacters(in: .whitespaces)
        if !z.isEmpty, !zonas.contains(z) { zonas.append(z) }
        zonaNueva = ""
    }

    // MARK: Datos

    private func cargar() async {
        error = nil
        do {
            struct E: Decodable { var alta: Alta }
            struct I: Decodable {
                struct P: Decodable { var rubros: [String]?; var zonas: [String]? }
                var legales: [String: String?]?
                var perfil: P?
            }
            let e: E = try await estado.api.get("/v1/panel/estructura")
            let b = try await BorradorWeb.leer(estado.api)
            let i: I = try await estado.api.get("/v1/inmobiliaria")
            alta = e.alta
            marca = b.marca
            en = b.en
            legales = (i.legales ?? [:]).compactMapValues { $0 }
            rubros = Set(i.perfil?.rubros ?? [])
            zonas = i.perfil?.zonas ?? []
            if paso.isEmpty {
                let ps = e.alta.pasos.filter { $0.clave != "nombre" }
                paso = ps.first { $0.clave == inicial }?.clave ?? ps.first { !$0.hecho }?.clave ?? ps.last?.clave ?? ""
            }
        } catch let e as ErrorApi { error = e } catch { self.error = .desconocido }
    }

    /// El porcentaje y los pasos hechos, al día con la API.
    private func refrescarAlta() async {
        struct E: Decodable { var alta: Alta }
        if let e: E = try? await estado.api.get("/v1/panel/estructura") { alta = e.alta }
    }

    @discardableResult
    private func guardarMarca() async -> Bool {
        do {
            let b = try await BorradorWeb.guardar(estado.api, marca: marca, si: en)
            en = b.en
            recarga += 1
            return true
        } catch let e as ErrorApi where e.codigo == "borrador_cambiado" {
            estado.avisar("Tu web se cambió desde otro lado. Trajimos lo último.", ok: false)
            if let b = try? await BorradorWeb.leer(estado.api) { marca = b.marca; en = b.en }
            return false
        } catch {
            estado.avisar(error)
            return false
        }
    }

    private func seguir(_ a: Alta.Paso) async {
        if a.clave == "logo", marca.texto("logoUrl").isEmpty { return estado.avisar("Subí tu logo para seguir.", ok: false) }
        if a.clave == "contacto", marca.texto("whatsapp").isEmpty { return estado.avisar("Poné tu WhatsApp para seguir: ahí te escriben desde la web.", ok: false) }
        guardando = true
        defer { guardando = false }
        var ok = true
        switch a.clave {
        case "logo", "marca", "portada", "contacto":
            ok = await guardarMarca()
        case "legales":
            struct C: Encodable { var legales: [String: String] }
            do { try await estado.api.hacer("PATCH", "/v1/inmobiliaria", C(legales: legales)) } catch { estado.avisar(error); ok = false }
        case "rubros":
            sumarZona()
            struct P: Encodable { var rubros: [String]; var zonas: [String] }
            struct C: Encodable { var perfil: P }
            do { try await estado.api.hacer("PATCH", "/v1/inmobiliaria", C(perfil: P(rubros: Array(rubros).sorted(), zonas: zonas))) } catch { estado.avisar(error); ok = false }
        default:
            break
        }
        guard ok else { return }
        await refrescarAlta()
        ir(siguiente)
    }

    private func frasePorIA() async {
        reescribiendo = true
        defer { reescribiendo = false }
        struct C: Encodable { var campo = "frase"; var texto: String }
        struct R: Decodable { var texto: String }
        let base = marca.texto("frase").isEmpty ? "Propiedades en \(zonas.isEmpty ? "tu zona" : zonas.joined(separator: ", ")) con \(estado.inmobiliaria?.nombre ?? "nosotros")" : marca.texto("frase")
        do {
            let r: R = try await estado.api.enviar("POST", "/v1/web/reescribir", C(texto: base))
            marca["frase"] = .texto(r.texto)
        } catch { estado.avisar(error) }
    }

    /// «Publicar mi web»: publica el borrador (si hay) y da el alta por terminada.
    private func terminar() async {
        guardando = true
        defer { guardando = false }
        do {
            let b = try await BorradorWeb.leer(estado.api)
            if b.hayBorrador { try await BorradorWeb.publicar(estado.api) }
            struct C: Encodable { var altaTerminada = true }
            try await estado.api.hacer("PATCH", "/v1/inmobiliaria", C())
            await estado.cargarEstructura()
            Haptico.exito()
            estado.avisar("¡Tu web está publicada!")
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// Chips que se eligen tocándolos (rubros) o se quitan (zonas), en filas que bajan solas.
struct FlujoChips: View {
    var items: [(String, String, String)]
    @Binding var elegidos: Set<String>
    /// Con esto, tocar quita (el ícono es la cruz) en vez de elegir.
    var alQuitar: ((String) -> Void)? = nil

    var body: some View {
        FlujoFilas(espacio: 8) {
            ForEach(items, id: \.0) { clave, texto, icono in
                let on = alQuitar == nil && elegidos.contains(clave)
                Button {
                    Haptico.seleccion()
                    if let alQuitar { alQuitar(clave) } else if on { elegidos.remove(clave) } else { elegidos.insert(clave) }
                } label: {
                    Label(texto, systemImage: icono).estilo(.subheadFuerte)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(on ? C.sobreAccion : C.texto)
                        .background(on ? C.accion : C.superficie, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? .clear : C.linea2))
                }
                .buttonStyle(Presionable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Acomoda las vistas en filas: cuando no entran, bajan a la siguiente.
struct FlujoFilas: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, fila: CGFloat = 0, maximo: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += fila + espacio; fila = 0 }
            x += t.width + espacio
            fila = max(fila, t.height)
            maximo = max(maximo, x - espacio)
        }
        return CGSize(width: min(maximo, ancho), height: y + fila)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, fila: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += fila + espacio; fila = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            fila = max(fila, t.height)
        }
    }
}

/// «Seguir →»: el texto y el ícono después.
struct TextoIcono: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}
