import MapKit
import SwiftUI
import TipKit

extension View {
    /// Los destinos de Propiedades: ficha, galería y alta.
    func destinosPropiedades() -> some View {
        self
            .navigationDestination(for: AFichaPropiedad.self) { f in FichaPropiedad(id: f.id) }
            .navigationDestination(for: AGaleria.self) { g in Galeria(id: g.id, indice: g.indice) }
            .navigationDestination(for: AAltaPropiedad.self) { a in AltaPropiedad(editar: a.editar, borrador: a.borrador) }
    }
}

/// 3A–3C Propiedades: la cartera en lista (deslizar para mandar o despublicar) o en mapa, con filtros.
/// Despublicar es lo de la web: sale del sitio y queda sin publicar (borrador), sin perder lo cargado.
struct PropiedadesRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var vista = 0
    @State private var filtro = "todas"
    @State private var props: [Propiedad]?
    @State private var senales: [String: Senal] = [:]
    @State private var error: ErrorApi?
    @State private var web: String?
    @State private var compartir: Propiedad?

    private static let filtros = [("todas", "Todas"), ("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporada"),
                                  ("mias", "Mías"), ("borrador", "Borradores"), ("error", "Con error")]

    var body: some View {
        Group {
            if vista == 1, let lista = filtradas, !lista.isEmpty {
                // El mapa no va dentro del scroll: ocupa todo el alto que queda (hasta la barra de pestañas).
                VStack(alignment: .leading, spacing: 12) {
                    encabezado
                    MapaCartera(props: lista, senales: senales) { compartir = $0 }
                        .padding(.horizontal, 16).padding(.bottom, 12)
                        .frame(maxHeight: .infinity)
                }
            } else {
                listado
            }
        }
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
        .sheet(item: $compartir) { p in HojaCompartir(propiedad: p, web: web).presentationDetents([.medium, .large]) }
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 12) {
            CabeceraPestana(titulo: "Propiedades",
                            acciones: estado.escribe ? [AccionCabecera(icono: "plus.circle", etiqueta: "Nueva propiedad") { estado.abrir(AAltaPropiedad()) }] : [],
                            busca: "Calle, barrio o dueño") { estado.abrir(ABuscar()) }
            Segmentado(opciones: [(0, "Lista"), (1, "Mapa")], elegido: $vista).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.filtros, id: \.0) { k, n in
                        ChipFiltro(texto: n, activo: filtro == k) { filtro = k }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 2)
            }
        }
    }

    private var listado: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                encabezado
                if let lista = filtradas {
                    if lista.isEmpty {
                        EstadoVacio(icono: "building.2", titulo: props?.isEmpty == true ? "Cargá tu primera propiedad" : "Ninguna con ese filtro",
                                    texto: props?.isEmpty == true ? "Con fotos y dirección, en un minuto. O fotografiá un cartel con MIRA." : nil,
                                    accion: estado.escribe && props?.isEmpty == true ? ("Cargar propiedad", { estado.abrir(AAltaPropiedad()) }) : nil,
                                    secundaria: estado.escribe && props?.isEmpty == true ? ("Captar con MIRA", { estado.miraAbierta = true }) : nil)
                            .padding(.top, 30)
                    } else if vista == 0 {
                        VStack(spacing: 10) {
                            TipView(ConsejoMandar()).tipBackground(C.superficie)
                            ForEach(lista) { p in fila(p) }
                            Text("Tocá el logo de WhatsApp para mandarla; mantené apretada una fila para más")
                                .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .padding(.horizontal, 16)
                    }
                } else if let error {
                    EstadoError(que: "la cartera", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else {
                    EsqueletoFilas(filas: 5, miniatura: 92).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable { await cargar() }
    }

    private var filtradas: [Propiedad]? {
        props?.filter { p in
            switch filtro {
            case "todas": return true
            case "mias": return p.agenteId == estado.usuario?.id
            case "borrador": return p.esBorrador
            case "error": return senales[p.id]?.error != nil
            default: return p.operacion == filtro || (filtro == "temporario" && p.tambienTemporario == true)
            }
        }
    }

    private func fila(_ p: Propiedad) -> some View {
        let (chip, tono) = Self.chip(p, senales[p.id])
        return FilaDeslizable(derecha: estado.escribe ? [
            AccionFila(texto: p.publicada == false ? "Publicar" : "Despublicar", simbolo: p.publicada == false ? "arrow.up.circle" : "eye.slash", color: Color(hex: 0x8E8E93)) { publicar(p) },
            AccionFila(texto: "Mandar", simbolo: "square.and.arrow.up", color: Color(hex: 0x25D366)) { compartir = p },
        ] : [AccionFila(texto: "Mandar", simbolo: "square.and.arrow.up", color: Color(hex: 0x25D366)) { compartir = p }], anchoAccion: 75) {
            Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                HStack(spacing: 12) {
                    Foto(url: p.miniatura).frame(width: 92, height: 92).clipShape(.rect(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.precioTexto).font(Estilo(tamano: 17, peso: .bold, tracking: -0.01, relativo: .headline).font).foregroundStyle(C.texto)
                        Text(p.nombre).font(Estilo(tamano: 15, peso: .medium, relativo: .subheadline).font).foregroundStyle(C.texto).lineLimit(1)
                        Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                        Spacer(minLength: 4)
                        Text(chip).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                            .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                            .lineLimit(1)
                            .padding(.trailing, 44)
                    }
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(C.superficie)
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            // Encima de la fila (no dentro de su botón, donde el toque se lo quedaría la fila).
            .overlay(alignment: .bottomTrailing) { BotonMandar { compartir = p }.padding(10) }
        }
        .clipShape(.rect(cornerRadius: M.rTarjeta, style: .continuous))
        .sombraE2()
        .contextMenu {
            Button { compartir = p } label: { Label("Mandar la ficha", systemImage: "square.and.arrow.up") }
            if estado.escribe {
                Button { estado.abrir(AAltaPropiedad(editar: p.id)) } label: { Label("Editar", systemImage: "pencil") }
                Button { publicar(p) } label: { Label(p.publicada == false ? "Publicar" : "Despublicar", systemImage: p.publicada == false ? "arrow.up.circle" : "eye.slash") }
            }
        }
    }

    /// El chip de estado de cada fila (3A): lo más importante que le pasa a la propiedad.
    static func chip(_ p: Propiedad, _ s: Senal?) -> (String, Tono) {
        if let e = s?.error { return ("Error en \(PublicacionPortal.nombres[e.portal ?? ""] ?? "un portal")", .rojo) }
        if p.esBorrador { return ("Borrador", .oro) }
        if p.estado == "suspendida" { return ("Suspendida", .neutro) }
        if p.estado == "alquilada" { return ("Alquilada", .azul) }
        if p.estado == "vendida" { return ("Vendida", .azul) }
        if p.estado == "reservada" || s?.reserva != nil { return ("Reservada", .violeta) }
        if let v = s?.proximaVisita, Calendar.current.isDateInToday(v) { return ("Visita hoy \(Formato.horaDe(v))", .oro) }
        if let n = s?.sinResponder, n > 0 { return (Formato.cantidad(n, "consulta sin responder", "consultas sin responder"), .oro) }
        if let n = s?.publicadaEn, n > 0 { return ("Publicada en \(n + (p.publicada == true ? 1 : 0))", .verde) }
        return (p.publicada == true ? "Publicada" : "Sin publicar", p.publicada == true ? .verde : .neutro)
    }

    /// Publicar o despublicar en la web (como el panel): despublicada queda como borrador.
    private func publicar(_ p: Propiedad) {
        let nuevo = p.publicada == false
        Task {
            struct Cuerpo: Encodable { var publicada: Bool }
            do {
                try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: nuevo), etiqueta: "\(nuevo ? "Publicar" : "Despublicar") \(p.nombre)")
                estado.version += 1
                estado.avisar(nuevo ? "Publicada en tu web" : "Despublicada: quedó como borrador") {
                    Task {
                        do {
                            try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: !nuevo))
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            } catch { estado.avisar(error) }
        }
    }

    private func cargar() async {
        do {
            let l: [Propiedad] = try await estado.api.todas("/v1/propiedades", query: [.init(name: "orden", value: "actualizada")])
            props = l
            error = nil
            Spotlight.indexar(propiedades: l)
            Guardado.guardar(l, clave: "propiedades")
            // Las señales no tiran la cartera: si no vienen, la lista se ve igual.
            senales = (try? await Senal.de(l.map(\.id), api: estado.api)) ?? senales
            if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        } catch let e as ErrorApi {
            if props == nil { props = Guardado.leer([Propiedad].self, clave: "propiedades")?.0 }
            if props == nil { error = e }
        } catch {}
    }
}

/// Un chip de filtro (36 de alto, cápsula; el activo en Acción).
struct ChipFiltro: View {
    var texto: String
    var activo: Bool
    var hacer: () -> Void
    var body: some View {
        Button(action: { Haptico.seleccion(); hacer() }) {
            Text(texto).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                .foregroundStyle(activo ? C.sobreAccion : C.texto)
                .padding(.horizontal, 14).frame(height: 36)
                .background(activo ? C.accion : C.superficie, in: Capsule())
                .shadow(color: activo ? .clear : C.sombra.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(Presionable())
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

/// Una foto de la API con su lugar mientras carga.
struct Foto: View {
    var url: URL?
    var body: some View {
        // Dentro de un Color.clear: la foto llena el lugar que le den y se recorta ahí, sin estirar a
        // quien la contiene (una foto suelta con scaledToFill desbordaba la pantalla).
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { f in
                    switch f {
                    case .success(let i): i.resizable().scaledToFill()
                    default: ZStack { C.hundida; Image(systemName: "photo").foregroundStyle(C.texto3) }
                    }
                }
            }
            .clipped()
        .accessibilityHidden(true)
    }
}

/// 3C El mapa de la cartera: a nivel barrio, apagado y sin lugares de interés (como el handoff), con
/// los precios como pines y la tarjeta de la elegida abajo. Ocupa todo el alto disponible.
struct MapaCartera: View {
    @Environment(Estado.self) private var estado
    var props: [Propiedad]
    var senales: [String: Senal]
    var compartir: (Propiedad) -> Void = { _ in }
    @State private var elegida: String?
    @State private var posicion: MapCameraPosition = .userLocation(fallback: .automatic)

    private var conLugar: [Propiedad] { props.filter { $0.lat != nil && $0.lng != nil } }

    var body: some View {
        let lugares = conLugar
        ZStack(alignment: .bottom) {
            Map(position: $posicion, selection: $elegida) {
                ForEach(lugares) { p in
                    Annotation(p.nombre, coordinate: CLLocationCoordinate2D(latitude: p.lat ?? 0, longitude: p.lng ?? 0)) {
                        Text(Self.corto(p)).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                            .foregroundStyle(elegida == p.id ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(elegida == p.id ? C.accion : C.superficie, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                    }
                    .annotationTitles(.hidden)
                    .tag(p.id)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .animation(.snappy, value: elegida)

            if let p = lugares.first(where: { $0.id == elegida }) {
                tarjeta(p).padding(10).transition(.move(edge: .bottom).combined(with: .opacity))
            } else if lugares.isEmpty {
                Text(Formato.sinViudas("Ninguna tiene ubicación todavía. Se ubican solas con la dirección."))
                    .estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous)).padding(16)
            }
        }
        .overlay(alignment: .topLeading) {
            let sin = props.count - lugares.count
            if sin > 0, !lugares.isEmpty {
                Text("\(sin) sin ubicar").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2)
                    .padding(.horizontal, 10).frame(height: 26).background(C.superficie, in: Capsule()).sombraE1().padding(10)
            }
        }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE2()
        .onAppear { encuadrar() }
        .onChange(of: props.map(\.id)) { _, _ in elegida = nil; encuadrar() }
    }

    /// Todas las propiedades a la vista, con margen, y nunca más cerca que unas 12 cuadras.
    private func encuadrar() {
        let ps = conLugar.compactMap { p -> CLLocationCoordinate2D? in
            guard let a = p.lat, let o = p.lng else { return nil }
            return CLLocationCoordinate2D(latitude: a, longitude: o)
        }
        guard let primera = ps.first else { posicion = .userLocation(fallback: .automatic); return }
        var minLat = primera.latitude, maxLat = primera.latitude, minLng = primera.longitude, maxLng = primera.longitude
        for c in ps {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let centro = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.012), longitudeDelta: max((maxLng - minLng) * 1.3, 0.012))
        posicion = .region(MKCoordinateRegion(center: centro, span: span))
    }

    private func tarjeta(_ p: Propiedad) -> some View {
        HStack(spacing: 12) {
            Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                HStack(spacing: 12) {
                    Foto(url: p.miniatura).frame(width: 76, height: 76).clipShape(.rect(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.precioTexto).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                        Text(p.nombre).estilo(.subhead).foregroundStyle(C.texto).lineLimit(1)
                        Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            BotonMandar { compartir(p) }
        }
        .padding(10)
        .background(C.superficie, in: .rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
    }

    /// «USD 172 k», «ARS 612 k».
    static func corto(_ p: Propiedad) -> String {
        guard let n = p.precio, p.precioOculto != true else { return "Consultar" }
        let m = p.moneda ?? "USD"
        if n >= 1_000_000 { return "\(m) \(String(format: "%.1f", n / 1_000_000).replacingOccurrences(of: ".", with: ",")) M" }
        if n >= 1000 { return "\(m) \(Int(n / 1000)) k" }
        return "\(m) \(Int(n))"
    }
}

/// Mandar la ficha: el logo de WhatsApp en un círculo de 36 pt, visible en cada fila y en la tarjeta del mapa
/// (deslizar y mantener apretado siguen andando, pero no se descubren solos).
struct BotonMandar: View {
    var mandar: () -> Void
    var body: some View {
        Button(action: mandar) {
            Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(Color(hex: 0x25D366).opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(Presionable())
        .accessibilityLabel("Mandar la ficha")
    }
}
