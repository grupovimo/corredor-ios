import SwiftUI
import UIKit

/// GET /v1/informe?dias= (panel.Informe).
struct InformeAPI: Codable {
    struct Vista: Codable, Hashable { var propiedadId: String; var titulo: String?; var vistas: Int? }
    struct Origen: Codable, Hashable { var origen: String?; var cantidad: Int? }
    struct Etapa: Codable, Hashable { var etapa: String; var cantidad: Int? }
    struct Monto: Codable, Hashable { var moneda: String; var monto: Double }
    var dias: Int?
    var masVistas: [Vista]?
    var totalVistas: Int?
    var origenes: [Origen]?
    var totalContactos: Int?
    var embudo: [Etapa]?
    var cerradas: Int?
    var diasPromedioCierre: Int?
    var honorarios: [Monto]?
    var caidas: Int?
    var motivoCaida: String?
}

/// Informe y exportar, como la página del panel (45): el mes que va («4 cierres · USD 11.200 en
/// honorarios · 92 % cobrado · 3 operaciones caídas por precio»), el embudo con cuánto tarda en
/// cerrar, de dónde llegan, lo más visto en la web, el informe mensual de 4 páginas (de cualquier mes,
/// en PDF o para imprimir) y cada listado a Excel.
struct Informe: View {
    @Environment(Estado.self) private var estado
    @State private var inf: InformeAPI?
    @State private var cobrado: Int?
    @State private var error: ErrorApi?
    @State private var exportando: URL?
    @State private var previo: ArchivoPrevio?
    @State private var mesInforme = ""
    @State private var armando = false

    private var hoy: String { Formato.diaISO(Date()) }
    private var mes: String { TextosInforme.nombreMes(hoy) }

    /// Los meses que se pueden pedir: el pasado (el que llega el día 1) y los 11 anteriores, y el que va.
    private var meses: [String] {
        let actual = String(hoy.prefix(7))
        var l = [actual]
        var m = actual
        for _ in 0..<12 { m = TextosInforme.anterior(m); l.append(m) }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cómo viene el mes y cada listado para bajar a Excel.").estilo(.subhead).foregroundStyle(C.texto2)
                if let i = inf {
                    destacado(i)
                    embudo(i)
                    origenes(i)
                    masVistas(i)
                } else if let error {
                    EstadoError(que: "el informe", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 4) }
                informeMensual
                exportar
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Informe y exportar")
        .task(id: estado.version) { await cargar() }
        .onAppear { if mesInforme.isEmpty { mesInforme = meses.count > 1 ? meses[1] : "" } }
        .vistaPrevia($previo)
        .sheet(item: Binding(get: { exportando.map { URLHoja(url: $0) } }, set: { exportando = $0?.url })) { x in
            ShareLink(item: x.url) { Label("Compartir \(x.url.lastPathComponent)", systemImage: "square.and.arrow.up") }.padding(40).presentationDetents([.height(160)])
        }
    }

    /// «4 cierres · USD 11.200 en honorarios · 92 % cobrado · 3 operaciones caídas por precio».
    private func resumen(_ i: InformeAPI) -> String {
        var p = [Formato.cantidad(i.cerradas ?? 0, "cierre", "cierres")]
        if let h = i.honorarios, !h.isEmpty { p.append(h.map { Formato.plata($0.monto, $0.moneda) }.joined(separator: " + ") + " en honorarios") }
        if let c = cobrado { p.append("\(c)\(Formato.fino)% cobrado") }
        if let c = i.caidas, c > 0 {
            p.append(Formato.cantidad(c, "operación caída", "operaciones caídas") + (i.motivoCaida.map { " por \($0.lowercased())" } ?? ""))
        }
        return p.joined(separator: " · ") + "."
    }

    private func destacado(_ i: InformeAPI) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Informe de \(mes)").estilo(.headline).foregroundStyle(.white)
            Text(resumen(i)).estilo(.body16).foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 10) {
                Button("Ver informe") { Task { await verInforme(String(hoy.prefix(7)), imprimir: false) } }.buttonStyle(BotonTonal(alto: 40))
                Button { Task { await exportarExcel("operaciones") } } label: { Label("Excel", systemImage: "arrow.down.circle") }
                    .font(Estilo.footnoteFuerte.font).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 40).overlay(Capsule().strokeBorder(.white.opacity(0.6)))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(C.verde700, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func embudo(_ i: InformeAPI) -> some View {
        GraficoBarras(titulo: "Embudo", detalle: i.diasPromedioCierre.map { "cierra en \(Formato.cantidad($0, "día", "días"))" },
                      filas: (i.embudo ?? []).map { (Operacion.etapaTexto($0.etapa), Double($0.cantidad ?? 0)) }, color: Color(hex: 0x2F9E6F))
    }

    @ViewBuilder
    private func origenes(_ i: InformeAPI) -> some View {
        let o = (i.origenes ?? []).map { ($0.origen ?? "Otro", Double($0.cantidad ?? 0)) }
        if o.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("De dónde llegan").estilo(.headline).foregroundStyle(C.texto)
                Text(Formato.cantidad(i.totalContactos ?? 0, "contacto nuevo", "contactos nuevos")).estilo(.footnote).foregroundStyle(C.texto2)
                Text("Este mes todavía no entraron contactos.").estilo(.subhead).foregroundStyle(C.texto3).padding(.top, 6)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        } else {
            GraficoOrigenes(origenes: o)
        }
    }

    private func masVistas(_ i: InformeAPI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Lo más visto en tu web", cuenta: Formato.cantidad(i.totalVistas ?? 0, "visita", "visitas"))
            VStack(spacing: 0) {
                let l = Array((i.masVistas ?? []).prefix(5))
                ForEach(Array(l.enumerated()), id: \.element.propiedadId) { k, v in
                    Button { estado.abrir(AFichaPropiedad(id: v.propiedadId)) } label: {
                        HStack {
                            Text(v.titulo ?? "Propiedad").estilo(.body16).foregroundStyle(C.texto).lineLimit(1)
                            Spacer()
                            Text(Formato.numero(v.vistas ?? 0)).estilo(.filaLista).foregroundStyle(C.texto)
                            Chevron()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if k > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
                if l.isEmpty {
                    Text(Formato.sinViudas("Cuando entren visitas a tu web, acá ves qué propiedades miran más.")).estilo(.subhead).foregroundStyle(C.texto3).padding(16)
                }
            }
            .tarjeta()
        }
    }

    /// El informe mensual de 4 páginas: de qué mes (sin elegir, el pasado), en PDF o para imprimir.
    private var informeMensual: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Informe mensual")
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mes", selection: $mesInforme) {
                    ForEach(meses, id: \.self) { m in Text("\(Formato.mayuscula(TextosInforme.nombreMes(m))) \(m.prefix(4))").tag(m) }
                }
                .pickerStyle(.menu).tint(C.accion)
                HStack(spacing: 10) {
                    Button { Task { await verInforme(mesInforme, imprimir: false) } } label: { Label(armando ? "Armando…" : "PDF", systemImage: "doc.richtext") }
                        .buttonStyle(BotonHundido()).disabled(armando)
                    Button { Task { await verInforme(mesInforme, imprimir: true) } } label: { Label("Imprimir", systemImage: "printer") }
                        .buttonStyle(BotonHundido()).disabled(armando)
                }
            }
            .padding(14).tarjeta()
        }
    }

    private var exportar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Exportar a Excel")
            VStack(spacing: 0) {
                ForEach([("propiedades", "Cartera", "building.2"), ("contactos", "Contactos", "person.2"), ("operaciones", "Operaciones", "rectangle.split.3x1"),
                         ("agenda", "Agenda del último año", "calendar"), ("contratos", "Contratos", "doc.text"), ("cobros", "Cobranzas", "dollarsign.circle"),
                         ("reservas", "Reservas", "bookmark"), ("emprendimientos", "Emprendimientos", "building"), ("temporada", "Temporada", "beach.umbrella")], id: \.0) { r, n, i in
                    Button { Task { await exportarExcel(r) } } label: {
                        HStack { Label(n, systemImage: i); Spacer(); Image(systemName: "tablecells").foregroundStyle(Color(hex: 0x1D6F42)) }
                            .estilo(.body16).foregroundStyle(C.texto).padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
            }
            .tarjeta()
        }
    }

    /// Un número del JSON libre («—» si no hay); lo usan otras pantallas (Mi web).
    static func num(_ v: JSONLibre?) -> String {
        if case .numero(let n)? = v { return Formato.numero(Int(n)) }
        return "—"
    }

    static func valor(_ v: JSONLibre?) -> Double {
        if case .numero(let n)? = v { return n }
        return 0
    }

    private func cargar() async {
        let dia = Int(hoy.suffix(2)) ?? 30
        do {
            inf = try await estado.api.get("/v1/informe", query: [.init(name: "dias", value: "\(max(1, dia))")])
            error = nil
        } catch let e as ErrorApi { if inf == nil { error = e } } catch {}
        struct Cob: Decodable { var cobradas: [JSONLibre]?; var pendientes: [JSONLibre]? }
        if let c: Cob = try? await estado.api.get("/v1/cobranzas") {
            let total = (c.cobradas?.count ?? 0) + (c.pendientes?.count ?? 0)
            cobrado = total > 0 ? Int((Double(c.cobradas?.count ?? 0) / Double(total) * 100).rounded()) : nil
        }
    }

    private func verInforme(_ m: String, imprimir: Bool) async {
        armando = true
        defer { armando = false }
        do {
            let d = try await InformeMensualPDF.juntar(estado.api, mes: m.isEmpty ? nil : m)
            guard let u = InformeMensualPDF.pdf(d) else { estado.avisar("No pudimos armar el informe.", ok: false); return }
            if imprimir {
                let c = UIPrintInteractionController.shared
                let info = UIPrintInfo(dictionary: nil)
                info.jobName = u.deletingPathExtension().lastPathComponent
                info.outputType = .general
                c.printInfo = info
                c.printingItem = u
                c.present(animated: true)
            } else {
                previo = ArchivoPrevio(url: u)
            }
        } catch { estado.avisar(error) }
    }

    private func exportarExcel(_ r: String) async {
        do {
            // Sin ?formato=xlsx la API manda un CSV.
            let d = try await estado.api.pedir("GET", "/v1/exportar/\(r)", query: [.init(name: "formato", value: "xlsx")])
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(r)-\(Formato.diaISO(Date())).xlsx")
            try d.write(to: u)
            exportando = u
        } catch { estado.avisar(error) }
    }
}
