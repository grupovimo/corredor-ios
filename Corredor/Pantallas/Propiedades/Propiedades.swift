import MapKit
import SwiftUI

extension View {
    /// Los destinos de Propiedades: ficha, galería y alta.
    func destinosPropiedades() -> some View {
        self
            .navigationDestination(for: AFichaPropiedad.self) { f in FichaPropiedad(id: f.id) }
            .navigationDestination(for: AGaleria.self) { g in Galeria(id: g.id, indice: g.indice) }
            .navigationDestination(for: AAltaPropiedad.self) { a in AltaPropiedad(editar: a.borrador) }
    }
}

/// 3A–3C Propiedades: la cartera en lista (deslizar para mandar o pausar) o en mapa, con filtros.
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
        ScrollView {
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
                if let lista = filtradas {
                    if lista.isEmpty {
                        EstadoVacio(icono: "building.2", titulo: props?.isEmpty == true ? "Cargá tu primera propiedad" : "Ninguna con ese filtro",
                                    texto: props?.isEmpty == true ? "Con fotos y dirección, en un minuto. O fotografiá un cartel con MIRA." : nil,
                                    accion: estado.escribe && props?.isEmpty == true ? ("Cargar propiedad", { estado.abrir(AAltaPropiedad()) }) : nil,
                                    secundaria: estado.escribe && props?.isEmpty == true ? ("Captar con MIRA", { estado.miraAbierta = true }) : nil)
                            .padding(.top, 30)
                    } else if vista == 0 {
                        VStack(spacing: 10) {
                            ForEach(lista) { p in fila(p) }
                            Text("Deslizá una fila a la izquierda para mandarla o pausarla")
                                .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .padding(.horizontal, 16)
                    } else {
                        MapaCartera(props: lista, senales: senales).padding(.horizontal, 16)
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
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
        .sheet(item: $compartir) { p in HojaCompartir(propiedad: p, web: web).presentationDetents([.medium, .large]) }
    }

    private var filtradas: [Propiedad]? {
        props?.filter { p in
            switch filtro {
            case "todas": return true
            case "mias": return p.agenteId == estado.usuario?.id
            case "borrador": return p.estado == "borrador"
            case "error": return senales[p.id]?.error != nil
            default: return p.operacion == filtro || (filtro == "temporario" && p.tambienTemporario == true)
            }
        }
    }

    private func fila(_ p: Propiedad) -> some View {
        let (chip, tono) = Self.chip(p, senales[p.id])
        return FilaDeslizable(derecha: estado.escribe ? [
            AccionFila(texto: p.estado == "pausada" ? "Activar" : "Pausar", simbolo: p.estado == "pausada" ? "play.circle" : "pause.circle", color: Color(hex: 0x8E8E93)) { pausar(p) },
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
                    }
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(C.superficie)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .clipShape(.rect(cornerRadius: M.rTarjeta, style: .continuous))
        .sombraE2()
        .contextMenu {
            Button { compartir = p } label: { Label("Mandar la ficha", systemImage: "square.and.arrow.up") }
            if estado.escribe {
                Button { estado.abrir(AAltaPropiedad(borrador: p.id)) } label: { Label("Editar", systemImage: "pencil") }
                Button { pausar(p) } label: { Label(p.estado == "pausada" ? "Activar" : "Pausar", systemImage: "pause.circle") }
            }
        }
    }

    /// El chip de estado de cada fila (3A): lo más importante que le pasa a la propiedad.
    static func chip(_ p: Propiedad, _ s: Senal?) -> (String, Tono) {
        if let e = s?.error { return ("Error en \(PublicacionPortal.nombres[e.portal ?? ""] ?? "un portal")", .rojo) }
        if p.estado == "borrador" { return ("Borrador", .oro) }
        if p.estado == "pausada" { return ("Pausada", .neutro) }
        if p.estado == "alquilada" { return ("Alquilada", .azul) }
        if p.estado == "vendida" { return ("Vendida", .azul) }
        if p.estado == "reservada" || s?.reserva != nil { return ("Reservada", .violeta) }
        if let v = s?.proximaVisita, Calendar.current.isDateInToday(v) { return ("Visita hoy \(Formato.horaDe(v))", .oro) }
        if let n = s?.sinResponder, n > 0 { return (Formato.cantidad(n, "consulta sin responder", "consultas sin responder"), .oro) }
        if let n = s?.publicadaEn, n > 0 { return ("Publicada en \(n + (p.publicada == true ? 1 : 0))", .verde) }
        return (p.publicada == true ? "Publicada" : "Sin publicar", p.publicada == true ? .verde : .neutro)
    }

    private func pausar(_ p: Propiedad) {
        let nuevo = p.estado == "pausada" ? "disponible" : "pausada"
        let antes = p.estado ?? "disponible"
        Task {
            struct Cuerpo: Encodable { var estado: String }
            do {
                try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: nuevo), etiqueta: "\(nuevo == "pausada" ? "Pausar" : "Activar") \(p.nombre)")
                estado.version += 1
                estado.avisar(nuevo == "pausada" ? "Publicación pausada" : "Publicación activa") {
                    Task {
                        try? await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: antes))
                        estado.version += 1
                    }
                }
            } catch { estado.avisar(error) }
        }
    }

    private func cargar() async {
        do {
            let l: [Propiedad] = try await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "500"), .init(name: "orden", value: "actualizada")])
            props = l
            error = nil
            Guardado.guardar(l, clave: "propiedades")
            let s: [Senal] = (try? await estado.api.get("/v1/propiedades/senales")) ?? []
            senales = Dictionary(s.map { ($0.propiedadId, $0) }, uniquingKeysWith: { a, _ in a })
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
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

/// Una foto de la API con su lugar mientras carga.
struct Foto: View {
    var url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { f in
            switch f {
            case .success(let i): i.resizable().scaledToFill()
            default: ZStack { C.hundida; Image(systemName: "photo").foregroundStyle(C.texto3) }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// 3C El mapa de la cartera: pines con el precio y la tarjeta de la elegida abajo.
struct MapaCartera: View {
    @Environment(Estado.self) private var estado
    var props: [Propiedad]
    var senales: [String: Senal]
    @State private var elegida: String?

    var body: some View {
        let conLugar = props.filter { $0.lat != nil && $0.lng != nil }
        ZStack(alignment: .bottom) {
            Map(selection: $elegida) {
                ForEach(conLugar) { p in
                    Annotation(p.nombre, coordinate: CLLocationCoordinate2D(latitude: p.lat!, longitude: p.lng!)) {
                        Text(Self.corto(p)).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                            .foregroundStyle(elegida == p.id ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(elegida == p.id ? C.accion : C.superficie, in: Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 7, y: 6)
                            .onTapGesture { elegida = p.id }
                    }
                    .annotationTitles(.hidden)
                    .tag(p.id)
                }
                UserAnnotation()
            }
            .mapControls { MapUserLocationButton() }
            if let p = conLugar.first(where: { $0.id == elegida }) ?? conLugar.first {
                Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                    HStack(spacing: 12) {
                        Foto(url: p.miniatura).frame(width: 76, height: 76).clipShape(.rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.precioTexto).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                            Text(p.nombre).estilo(.subhead).foregroundStyle(C.texto)
                            Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(C.superficie, in: .rect(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 15, y: 16)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            if conLugar.isEmpty {
                Text("Ninguna tiene ubicación todavía. Se ubican solas con la dirección.")
                    .estilo(.footnote).foregroundStyle(C.texto2).padding(12)
                    .background(C.superficie, in: Capsule()).padding(.bottom, 20)
            }
        }
        .frame(height: 560)
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE2()
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
