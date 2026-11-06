import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Portales (difusión)

/// `GET /v1/publicaciones/resumen`: un renglón por portal y lo que falta difundir.
struct ResumenPublicaciones: Codable {
    struct Portal: Codable, Hashable {
        var portal: String
        var activos: Int?
        var pausados: Int?
        var conError: Int?
        var pendientes: Int?
        var visitas: Int?
        var visitasSemana: Int?
        var visitasSemanaAnterior: Int?
        var feed: String?
        var leidoEn: Date?
    }
    var portales: [Portal]?
    /// Las disponibles que se pueden difundir y, de ellas, las que faltan en algún portal (ids).
    var difundibles: Int?
    var faltan: [String]?
    var reservadas: Int?
    var webVisitasSemana: Int?
    var webVisitasSemanaAnterior: Int?

    var publicadas: Int { (portales ?? []).reduce(0) { $0 + ($1.activos ?? 0) } }
    var conError: Int { (portales ?? []).reduce(0) { $0 + ($1.conError ?? 0) } }
}

struct PublicacionLista: Codable, Identifiable, Hashable {
    var id: String
    var propiedadId: String
    var propiedad: String?
    var portal: String
    var estado: String
    var url: String?
    var error: String?
    var visitas: Int?
    var visitasSemana: Int?
    var consultas: Int?
    var publicadaEn: Date?
}

/// 32b Difusión a portales: «¿mi cartera está donde tiene que estar?». Una tarjeta por portal:
/// Zonaprop y Argenprop por feed (el link se copia una vez), Mercado Libre con su cuenta y los
/// errores, y la web. «Publicar las N que faltan» manda en lote a los portales por feed, con deshacer.
/// Abajo, todas las publicaciones con pausar y republicar.
struct Portales: View {
    @Environment(Estado.self) private var estado
    @State private var r: ResumenPublicaciones?
    @State private var pubs: [PublicacionLista]?
    @State private var ml: ConexionML?
    @State private var error: ErrorApi?
    @State private var portal = "todos"
    @State private var publicando = false

    private var faltan: Int { r?.faltan?.count ?? 0 }
    private var erroresML: [PublicacionLista] { (pubs ?? []).filter { $0.portal == "mercadolibre" && $0.estado == "error" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Formato.cantidad(r.difundibles ?? 0, "propiedad para difundir", "propiedades para difundir"))\((r.reservadas ?? 0) > 0 ? " · las reservadas siguen publicadas, marcadas" : "")")
                            .estilo(.subhead).foregroundStyle(C.texto2)
                    }
                    if faltan > 0, estado.escribe {
                        Button { Task { await publicarFaltan() } } label: {
                            Label(publicando ? "Publicando…" : "Publicar \(faltan == 1 ? "la que falta" : "las \(faltan) que faltan")", systemImage: "megaphone")
                        }
                        .buttonStyle(BotonPrincipal()).disabled(publicando)
                    }
                    ForEach(["zonaprop", "argenprop"], id: \.self) { k in tarjetaFeed(k, r) }
                    tarjetaML(r)
                    tarjetaWeb(r)
                    if let v = r.portales?.first(where: { $0.portal == "mercadolibre" })?.visitas, v > 0 {
                        Text("\(Formato.numero(v)) visitas a las publicaciones de Mercado Libre.").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                } else if let error {
                    EstadoError(que: "la difusión", error: error) { Task { await cargar() } }.padding(.top, 30)
                }
                TituloBloque(texto: "Publicaciones").padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("todos", "Todos"), ("error", "Con error"), ("mercadolibre", "Mercado Libre"), ("zonaprop", "Zonaprop"), ("argenprop", "Argenprop")], id: \.0) { k, n in
                            ChipFiltro(texto: n, activo: portal == k) { portal = k }
                        }
                    }
                }
                lista
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Difusión a portales")
        .task(id: estado.version) { await cargar() }
    }

    private func encabezadoPortal(_ logo: String, _ nombre: String, _ detalle: String, _ chip: String, _ tono: Tono) -> some View {
        HStack(spacing: 12) {
            LogoPortal(portal: logo).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(nombre).estilo(.filaLista).foregroundStyle(C.texto)
                Text(detalle).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            Text(chip).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
        }
    }

    private func tarjetaFeed(_ k: String, _ r: ResumenPublicaciones) -> some View {
        let p = r.portales?.first { $0.portal == k }
        let nombre = k == "zonaprop" ? "Zonaprop" : "Argenprop"
        let leido = p?.leidoEn
        return VStack(alignment: .leading, spacing: 10) {
            encabezadoPortal(k, nombre, leido.map { "\(Formato.cantidad(p?.activos ?? 0, "aviso activo", "avisos activos")) · leído \(Formato.hace($0))" } ?? "Todavía no leyó el feed",
                             leido != nil ? "Al día" : "Sin conectar", leido != nil ? .verde : .oro)
            if let feed = p?.feed {
                HStack(spacing: 8) {
                    Text(feed.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").components(separatedBy: "?clave=").first ?? feed)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(C.texto2).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Copiar") { UIPasteboard.general.string = feed; estado.avisar("Copiado") }.buttonStyle(BotonTonal(alto: 30))
                    ShareLink(item: feed) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir el link del feed")
                }
                .padding(10).background(C.hundida, in: .rect(cornerRadius: 10))
                Text(leido != nil ? "Pegalo una vez en tu cuenta de \(nombre); lo leen solos cada pocas horas." : "Paso que falta: pegarlo en \(nombre) › Mi cuenta › Integraciones.")
                    .estilo(.footnote).foregroundStyle(leido != nil ? C.texto2 : C.avisoTinta)
            } else {
                Text("El link del feed lo copia la dueña o el dueño de la inmobiliaria (lleva una clave).").estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        .padding(14).tarjeta()
    }

    private func tarjetaML(_ r: ResumenPublicaciones) -> some View {
        let p = r.portales?.first { $0.portal == "mercadolibre" }
        let conectada = ml?.conectada == true
        let det = conectada ? "\(Formato.cantidad(p?.activos ?? 0, "aviso activo", "avisos activos"))\(erroresML.isEmpty ? "" : " · \(erroresML.count) con error")" : "Sin cuenta conectada"
        return VStack(alignment: .leading, spacing: 10) {
            Button { estado.abrir(AMercadoLibre()) } label: {
                encabezadoPortal("mercadolibre", "Mercado Libre", det, !erroresML.isEmpty ? "Revisar" : conectada ? "Al día" : "Sin conectar",
                                 !erroresML.isEmpty ? .rojo : conectada ? .verde : .oro)
            }
            .buttonStyle(Presionable())
            if !erroresML.isEmpty {
                ForEach(erroresML.prefix(3)) { x in
                    Button { estado.abrir(AMercadoLibre()) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(C.errorTinta)
                            Text("\((x.propiedad ?? "").components(separatedBy: ",").first ?? ""): falta \(ArregloML.de(x.error).falta)").estilo(.footnote).foregroundStyle(C.texto).lineLimit(1)
                            Spacer()
                            Text("Arreglar").estilo(.footnoteFuerte).foregroundStyle(C.errorTinta)
                        }
                    }
                    .buttonStyle(Presionable())
                }
            } else if !conectada {
                Text("Se conecta con el usuario de la inmobiliaria y cada propiedad se publica desde su ficha.").estilo(.footnote).foregroundStyle(C.texto2)
                Button("Conectar Mercado Libre") { estado.abrir(AMercadoLibre()) }.buttonStyle(BotonTonal())
            } else {
                Text("Cada propiedad se publica desde su ficha; las preguntas llegan a la Bandeja.").estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        .padding(14).tarjeta()
    }

    private func tarjetaWeb(_ r: ResumenPublicaciones) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            encabezadoPortal("web", "Tu web",
                             "\(Formato.cantidad(r.difundibles ?? 0, "publicada", "publicadas"))\((r.webVisitasSemana ?? 0) > 0 ? " · \(Formato.cantidad(r.webVisitasSemana ?? 0, "visita esta semana", "visitas esta semana"))" : "")",
                             "Al día", .verde)
            Text("Todo lo disponible sale solo en tu web. Los borradores no.").estilo(.subhead).foregroundStyle(C.texto2)
            if let v = r.webVisitasSemana, let antes = r.webVisitasSemanaAnterior, antes > 0, let x = ArregloML.variacion(v, antes) {
                Text("\(x.0) contra la semana anterior").estilo(.footnoteFuerte).foregroundStyle(x.1 ? C.okTinta : C.errorTinta)
            }
        }
        .padding(14).tarjeta()
    }

    @ViewBuilder
    private var lista: some View {
        if let pubs {
            let l = pubs.filter { portal == "todos" || (portal == "error" ? $0.estado == "error" : $0.portal == portal) }
            if l.isEmpty {
                EstadoVacio(icono: "megaphone", titulo: "Todavía no publicaste en portales",
                            texto: "Conectá Mercado Libre y los portales, y publicás desde la ficha de cada propiedad sin cargar dos veces.",
                            accion: estado.esDuenio ? ("Conectar", { estado.abrir(ASeccion(clave: "integraciones")) }) : nil,
                            secundaria: ("Ver la cartera", { estado.pestana = .propiedades }))
                    .padding(.top, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(l.enumerated()), id: \.element.id) { i, p in fila(p, primera: i == 0) }
                }
                .tarjeta()
            }
        } else { EsqueletoFilas(filas: 6) }
    }

    private func fila(_ p: PublicacionLista, primera: Bool) -> some View {
        let (t, tono) = ArregloML.estados[p.estado] ?? (p.estado.capitalized, .neutro)
        return HStack(spacing: 12) {
            LogoPortal(portal: p.portal)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.propiedad ?? "Propiedad").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                Text(p.error ?? [t, p.visitasSemana.map { "\($0) visitas esta semana" }, p.consultas.map { Formato.cantidad($0, "consulta", "consultas") }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .estilo(.footnote).foregroundStyle(p.estado == "error" ? C.errorTinta : tono == .neutro ? C.texto2 : tono.tinta).lineLimit(2)
            }
            Spacer()
            Menu {
                Button { estado.abrir(AFichaPropiedad(id: p.propiedadId)) } label: { Label("Ver la propiedad", systemImage: "house") }
                if let u = p.url.flatMap(URL.init(string:)) { Link(destination: u) { Label("Ver en el portal", systemImage: "safari") } }
                if estado.escribe {
                    if p.estado == "publicada" {
                        Button { Task { await accion(p, "pausar") } } label: { Label("Pausar", systemImage: "pause.circle") }
                        Button(role: .destructive) { Task { await accion(p, "sacar") } } label: { Label("Sacar del portal", systemImage: "xmark.circle") }
                    } else if p.estado == "error" {
                        Button { estado.abrir(AArreglarPropiedad(id: p.propiedadId)) } label: { Label("Arreglar", systemImage: "wrench") }
                        Button { Task { await accion(p, "publicar") } } label: { Label("Reintentar", systemImage: "arrow.clockwise") }
                    } else {
                        Button { Task { await accion(p, "publicar") } } label: { Label("Publicar", systemImage: "arrow.up.circle") }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion) }.accessibilityLabel("Más acciones")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cargar() async {
        do {
            r = try await estado.api.get("/v1/publicaciones/resumen")
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
        ml = try? await estado.api.get("/v1/mercadolibre")
        pubs = (try? await estado.api.get("/v1/publicaciones", query: [.init(name: "limite", value: "500")])) ?? pubs ?? []
    }

    /// Publicar en lote en Zonaprop y Argenprop (los portales por feed), con deshacer.
    private func publicarFaltan() async {
        let ids = r?.faltan ?? []
        guard !ids.isEmpty else { return }
        publicando = true
        defer { publicando = false }
        let (hechas, fallas) = await lote(ids, deshacer: false)
        estado.version += 1
        guard hechas > 0 else {
            estado.sugerir(fallas.first ?? "No se publicó", "Reintentar") { Task { await publicarFaltan() } }
            return
        }
        estado.avisar("\(Formato.cantidad(ids.count, "propiedad", "propiedades")) en Zonaprop y Argenprop\(fallas.isEmpty ? "" : " · algunas no")") {
            Task {
                _ = await lote(ids, deshacer: true)
                estado.version += 1
            }
        }
    }

    private func lote(_ ids: [String], deshacer: Bool) async -> (Int, [String]) {
        var hechas = 0
        var fallas: [String] = []
        for id in ids.prefix(500) {
            for portal in ["zonaprop", "argenprop"] {
                do {
                    try await estado.api.hacer(deshacer ? "DELETE" : "POST", "/v1/propiedades/\(id)/publicaciones/\(portal)")
                    hechas += 1
                } catch let e as ErrorApi {
                    if !fallas.contains(e.detalle) { fallas.append(e.detalle) }
                } catch {}
            }
        }
        return (hechas, fallas)
    }

    private func accion(_ p: PublicacionLista, _ que: String) async {
        let ruta = "/v1/propiedades/\(p.propiedadId)/publicaciones/\(p.portal)"
        do {
            switch que {
            case "pausar":
                try await estado.api.hacer("POST", ruta + "/pausar")
                estado.avisar("Pausada") { Task { do { try await estado.api.hacer("POST", ruta); estado.version += 1 } catch { estado.avisar(error) } } }
            case "sacar":
                try await estado.api.hacer("DELETE", ruta)
                estado.avisar("Sacada de \(PublicacionPortal.nombres[p.portal] ?? p.portal)") { Task { do { try await estado.api.hacer("POST", ruta); estado.version += 1 } catch { estado.avisar(error) } } }
            default:
                try await estado.api.hacer("POST", ruta)
                estado.avisar("Publicando")
            }
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}
