import AuthenticationServices
import SwiftUI

/// El informe: visitas, consultas por origen, embudo, cierres, honorarios; y exportar a Excel.
struct Informe: View {
    @Environment(Estado.self) private var estado
    @State private var dias = 30
    @State private var inf: JSONLibre?
    @State private var exportando: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Segmentado(opciones: [(7, "7 días"), (30, "30 días"), (90, "90 días")], elegido: $dias)
                if let i = inf {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Visitas", valor: Self.num(i["totalVistas"]))
                        Cifra(etiqueta: "Contactos", valor: Self.num(i["totalContactos"]))
                        Cifra(etiqueta: "Cerradas", valor: Self.num(i["cerradas"]))
                    }
                    if case .lista(let o)? = i["origenes"], !o.isEmpty {
                        GraficoOrigenes(origenes: o.map { ($0["origen"]?.texto ?? "Otro", Self.valor($0["cantidad"])) })
                    }
                    if case .lista(let e)? = i["embudo"], !e.isEmpty {
                        GraficoBarras(titulo: "Embudo de operaciones", detalle: "Cuántas hay en cada etapa",
                                      filas: e.map { (Operacion.etapaTexto($0["etapa"]?.texto ?? ""), Self.valor($0["cantidad"])) }, color: Color(hex: 0x2F9E6F))
                    }
                    GraficoVisitasSemanas()
                    if case .lista(let m)? = i["masVistas"], !m.isEmpty {
                        GraficoBarras(titulo: "Las más vistas", detalle: "Visitas a la ficha en tu web y los portales",
                                      filas: m.prefix(6).map { (String(($0["titulo"]?.texto ?? "—").prefix(22)), Self.valor($0["vistas"])) })
                    }
                }
                Button {
                    Task {
                        if let j: JSONLibre = try? await estado.api.get("/v1/informe/mensual"),
                           let u = await Documentos.generico(titulo: "Informe de \(Formato.mesDe(Date()))", subtitulo: estado.inmobiliaria?.nombre, json: j, api: estado.api, nombre: "Informe \(Formato.mesDe(Date()))") {
                            exportando = u
                        }
                    }
                } label: { Label("El informe del mes en PDF", systemImage: "printer") }
                .buttonStyle(BotonHundido())
                VStack(alignment: .leading, spacing: 8) {
                    TituloBloque(texto: "Exportar a Excel")
                    VStack(spacing: 0) {
                        ForEach([("propiedades", "Propiedades"), ("contactos", "Contactos"), ("operaciones", "Operaciones"), ("contratos", "Contratos"), ("cobros", "Cobros"),
                                 ("agenda", "Agenda"), ("reservas", "Reservas"), ("temporada", "Temporada"), ("emprendimientos", "Emprendimientos")], id: \.0) { r, n in
                            Button { Task { await exportar(r) } } label: {
                                HStack { Label(n, systemImage: "tablecells"); Spacer(); Image(systemName: "square.and.arrow.down") }
                                    .estilo(.body16).foregroundStyle(C.texto).padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                        }
                    }
                    .tarjeta()
                }
            }
            .padding(16)
        }
        .pantallaApilada("Informe")
        .task(id: dias) { inf = try? await estado.api.get("/v1/informe", query: [.init(name: "dias", value: "\(dias)")]) }
        .sheet(item: Binding(get: { exportando.map { URLHoja(url: $0) } }, set: { exportando = $0?.url })) { x in ShareLink(item: x.url) { Label("Compartir \(x.url.lastPathComponent)", systemImage: "square.and.arrow.up") }.padding(40).presentationDetents([.height(160)]) }
    }

    static func num(_ v: JSONLibre?) -> String {
        if case .numero(let n)? = v { return Formato.numero(Int(n)) }
        return "—"
    }

    static func valor(_ v: JSONLibre?) -> Double {
        if case .numero(let n)? = v { return n }
        return 0
    }

    private func exportar(_ r: String) async {
        do {
            // Sin ?formato=xlsx la API manda un CSV.
            let d = try await estado.api.pedir("GET", "/v1/exportar/\(r)", query: [.init(name: "formato", value: "xlsx")])
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(r)-\(Formato.diaISO(Date())).xlsx")
            try d.write(to: u)
            exportando = u
        } catch { estado.avisar(error) }
    }
}
