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

/// Portales: qué está publicado dónde, lo que tiene error y lo que falta difundir; pausar y republicar.
struct Portales: View {
    @Environment(Estado.self) private var estado
    @State private var r: ResumenPublicaciones?
    @State private var pubs: [PublicacionLista]?
    @State private var portal = "todos"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Publicadas", valor: "\(r.publicadas)")
                        Cifra(etiqueta: "Sin publicar", valor: "\(r.faltan?.count ?? 0)")
                        Cifra(etiqueta: "Con error", valor: "\(r.conError)")
                    }
                    if let v = r.webVisitasSemana {
                        let antes = r.webVisitasSemanaAnterior ?? 0
                        TarjetaAvance(titulo: "Visitas a tu web", cifra: "\(Formato.numero(v)) esta semana",
                                      avance: antes > 0 ? min(1, Double(v) / Double(max(v, antes))) : 1,
                                      pie: antes > 0 ? (v >= antes ? "▲ \(Int((Double(v - antes) / Double(antes) * 100).rounded())) % contra la anterior" : "▼ \(Int((Double(antes - v) / Double(antes) * 100).rounded())) % contra la anterior") : "La primera semana con datos")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("todos", "Todos"), ("error", "Con error"), ("mercadolibre", "Mercado Libre"), ("zonaprop", "Zonaprop"), ("argenprop", "Argenprop")], id: \.0) { k, n in
                            ChipFiltro(texto: n, activo: portal == k) { portal = k }
                        }
                    }
                }
                if let pubs {
                    let l = pubs.filter { portal == "todos" || (portal == "error" ? $0.error != nil : $0.portal == portal) }
                    if l.isEmpty {
                        EstadoVacio(icono: "megaphone", titulo: "Todavía no publicaste en portales",
                                    texto: "Conectá Mercado Libre y los portales, y publicás desde la ficha de cada propiedad sin cargar dos veces.",
                                    accion: estado.esDuenio ? ("Conectar", { estado.abrir(ASeccion(clave: "integraciones")) }) : nil,
                                    secundaria: ("Ver la cartera", { estado.pestana = .propiedades }))
                            .padding(.top, 30)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, p in
                            HStack(spacing: 12) {
                                LogoPortal(portal: p.portal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.propiedad ?? "Propiedad").estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(p.error ?? [PublicacionPortal.nombres[p.portal] ?? p.portal, p.visitasSemana.map { "\($0) visitas" }, p.consultas.map { Formato.cantidad($0, "consulta", "consultas") }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .estilo(.footnote).foregroundStyle(p.error != nil ? C.errorTinta : C.texto2).lineLimit(2)
                                }
                                Spacer()
                                if estado.escribe {
                                    Menu {
                                        Button { estado.abrir(AFichaPropiedad(id: p.propiedadId)) } label: { Label("Ver la propiedad", systemImage: "house") }
                                        if let u = p.url.flatMap(URL.init(string:)) { Link(destination: u) { Label("Ver en el portal", systemImage: "safari") } }
                                        if p.estado == "publicada" || p.estado == "activa" {
                                            Button { Task { await accion(p, pausar: true) } } label: { Label("Pausar", systemImage: "pause.circle") }
                                        } else {
                                            Button { Task { await accion(p, pausar: false) } } label: { Label(p.error != nil ? "Reintentar" : "Publicar", systemImage: "arrow.up.circle") }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion) }.accessibilityLabel("Más acciones")
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                } else { EsqueletoFilas(filas: 6) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Portales")
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        r = try? await estado.api.get("/v1/publicaciones/resumen")
        pubs = (try? await estado.api.todas("/v1/publicaciones", query: [])) ?? pubs ?? []
    }

    private func accion(_ p: PublicacionLista, pausar: Bool) async {
        do {
            try await estado.api.hacer("POST", "/v1/propiedades/\(p.propiedadId)/publicaciones/\(p.portal)\(pausar ? "/pausar" : "")")
            estado.avisar(pausar ? "Pausada" : "Publicando")
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}
