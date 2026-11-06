import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// GET /v1/informe/mensual (panel.Mensual): el mes, el anterior, las cuentas de cada uno, la serie de
/// honorarios, el equipo, las caídas y las rendiciones.
struct InformeMensualAPI: Codable {
    struct Cuentas: Codable {
        var consultas: Int?; var visitas: Int?; var reservas: Int?; var cierres: Int?; var captaciones: Int?; var caidas: Int?
        var honorarios: [String: Double]?
    }
    struct Punto: Codable { var mes: String; var monto: Double }
    struct Agente: Codable, Identifiable {
        var id: String; var nombre: String; var rol: String?; var captadas: Int?; var visitas: Int?; var cierres: Int?; var honorarios: [String: Double]?
    }
    struct Caida: Codable { var motivo: String; var cantidad: Int }
    struct Rendiciones: Codable { var cantidad: Int?; var emitidas: Int?; var neto: [String: Double]?; var comision: [String: Double]?; var pendientes: Int? }
    var mes: String
    var anterior: String
    var actual: Cuentas
    var mesAnterior: Cuentas
    var inmobiliaria: String?
    var serie: [Punto]?
    var moneda: String?
    var equipo: [Agente]?
    var caidas: [Caida]?
    var rendiciones: Rendiciones?
}

/// Lo de cobranzas que usa el informe (GET /v1/cobranzas?mes=).
struct CobranzasInforme: Codable {
    struct Fila: Codable { var monto: Double?; var estado: String?; var comision: Double? }
    var cobradas: [Fila]?
    var pendientes: [Fila]?
    var totalCobrado: [String: Double]?
    var totalPendiente: [String: Double]?
    var totalComision: [String: Double]?
}

/// Los datos del informe ya juntados (lo que arma la página de impresión de la web).
struct DatosInforme {
    var m: InformeMensualAPI
    var cobrado: Double
    var pendiente: Double
    var atrasados: Int
    var comision: Double
    var comisionAnterior: Double
    var comisionPorcentaje: Double?
    var ajustan: Int
    var suba: Double?
    var vencen: Int
    var limite: String
    var qr: UIImage?
}

/// Las frases del informe, como la web (lib/impresos/informe.ts): salen de los números.
enum TextosInforme {
    static func nombreMes(_ m: String) -> String { Int(m.dropFirst(5).prefix(2)).map { Ritmo.meses[max(0, min(11, $0 - 1))] } ?? m }

    static func siguiente(_ m: String) -> String {
        let p = m.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2 else { return m }
        return p[1] == 12 ? String(format: "%04d-01", p[0] + 1) : String(format: "%04d-%02d", p[0], p[1] + 1)
    }

    static func anterior(_ m: String) -> String {
        let p = m.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2 else { return m }
        return p[1] == 1 ? String(format: "%04d-12", p[0] - 1) : String(format: "%04d-%02d", p[0], p[1] - 1)
    }

    private static func dec(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// 11200 → «11,2 k»; 34870000 → «34,9 M».
    static func corto(_ n: Double) -> String {
        if abs(n) >= 1e6 { return "\(dec(n / 1e6)) M" }
        if abs(n) >= 1e3 { return "\(dec(n / 1e3)) k" }
        return dec(n)
    }

    static func kBarra(_ n: Double) -> String { n >= 1e3 ? "\(dec(n / 1e3))k" : dec(n) }

    /// «+2», «−8 %», o nil si no hay con qué comparar.
    static func diferencia(_ actual: Double, _ antes: Double, porcentaje: Bool) -> (String, Bool)? {
        if porcentaje {
            guard antes != 0 else { return nil }
            let p = Int(((actual - antes) / antes * 100).rounded())
            return ("\(p > 0 ? "+" : p < 0 ? "−" : "±")\(abs(p))\(Formato.fino)%", p >= 0)
        }
        let d = Int(actual - antes)
        return ("\(d > 0 ? "+" : d < 0 ? "−" : "±")\(abs(d))", d >= 0)
    }

    static func fraseDelMes(_ m: InformeMensualAPI) -> String {
        let a = m.actual, b = m.mesAnterior
        let ac = a.cierres ?? 0, bc = b.cierres ?? 0
        let serie = m.serie ?? []
        let mejor = serie.count > 1 && ac > 0 && (serie.last?.monto ?? 0) >= (serie.map(\.monto).max() ?? 0)
        let cierres = mejor ? "El mejor mes del semestre en honorarios"
            : ac > bc ? "Más cierres que en \(nombreMes(m.anterior))"
            : ac < bc ? "Menos cierres que en \(nombreMes(m.anterior))"
            : ac > 0 ? "Los mismos cierres que en \(nombreMes(m.anterior))" : "Un mes sin cierres"
        let aca = a.captaciones ?? 0, bca = b.captaciones ?? 0
        let capta = aca < bca ? "con las captaciones atrás del ritmo" : aca > bca ? "y con más captaciones" : aca > 0 ? "y las captaciones al mismo ritmo" : "y sin captaciones nuevas"
        return "\(cierres), \(capta)."
    }

    static func tituloResumen(_ m: InformeMensualAPI) -> String {
        let ac = m.actual.cierres ?? 0, bc = m.mesAnterior.cierres ?? 0
        if ac > bc && (m.actual.consultas ?? 0) < (m.mesAnterior.consultas ?? 0) { return "Más cierres con menos consultas: convirtieron mejor." }
        if ac > bc { return "Más cierres que en \(nombreMes(m.anterior))." }
        if ac < bc { return "Menos cierres que en \(nombreMes(m.anterior)): \(ac) contra \(bc)." }
        return ac > 0 ? "\(ac) cierres, como en \(nombreMes(m.anterior))." : "Un mes sin cierres."
    }

    static func tituloEquipo(_ m: InformeMensualAPI) -> String {
        let total = m.actual.cierres ?? 0
        let eq = m.equipo ?? []
        guard let p = eq.first, (p.cierres ?? 0) > 0 else {
            return eq.isEmpty ? "Sin movimiento del equipo este mes." : "Nadie cerró este mes: el equipo, en visitas y captaciones."
        }
        let nombre = Charla.primerNombre(p.nombre)
        let pc = p.cierres ?? 0
        let parte = pc * 2 >= total && total > 1 ? "cerró la mitad" : pc == total ? "hizo todos los cierres" : "encabezó los cierres"
        if eq.count > 1, (eq[1].cierres ?? 0) > 0 { return "\(nombre) \(parte); \(Charla.primerNombre(eq[1].nombre)) lo siguió." }
        return "\(nombre) \(parte)."
    }

    static func motivo(_ m: String) -> String {
        let t = m.trimmingCharacters(in: .whitespaces)
        return t.lowercased() == "precio" ? "por precio" : t.prefix(1).lowercased() + t.dropFirst()
    }

    static func qr(_ texto: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(texto.utf8)
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Arma el informe mensual de 4 páginas (A4) como la ruta de impresión de la web: portada, «Cómo nos
/// fue», «Quién empujó» y «Cuánta plata entró», con el QR al informe en Corredor.
@MainActor
enum InformeMensualPDF {
    static func juntar(_ api: Api, mes: String?) async throws -> DatosInforme {
        let m: InformeMensualAPI = try await api.get("/v1/informe/mensual", query: mes.map { [.init(name: "mes", value: $0)] } ?? [])
        let cob: CobranzasInforme? = try? await api.get("/v1/cobranzas", query: [.init(name: "mes", value: m.mes)])
        let cobAntes: CobranzasInforme? = try? await api.get("/v1/cobranzas", query: [.init(name: "mes", value: m.anterior)])
        struct Evento: Decodable { var contratoId: String; var tipo: String; var fecha: String; var monto: Double? }
        let eventos: [Evento] = (try? await api.get("/v1/contratos/vencimientos", query: [.init(name: "dias", value: "120")])) ?? []
        let prox = TextosInforme.siguiente(m.mes)
        let ajustes = eventos.filter { $0.tipo == "ajuste" && $0.fecha.hasPrefix(prox) && ($0.monto ?? 0) > 0 }
        struct Ajuste: Decodable { var vigente: Double? }
        var subas: [Double] = []
        for e in ajustes.prefix(30) {
            if let a: Ajuste = try? await api.get("/v1/contratos/\(e.contratoId)/ajuste"), let v = a.vigente, v > 0, let n = e.monto { subas.append((n - v) / v) }
        }
        let limite = TextosInforme.siguiente(TextosInforme.siguiente(TextosInforme.siguiente(prox)))
        let vencen = eventos.filter { $0.tipo == "vencimiento" && String($0.fecha.prefix(7)) < limite }.count
        let conComision = cob?.cobradas?.first { $0.comision != nil && ($0.monto ?? 0) > 0 }
        return DatosInforme(m: m, cobrado: cob?.totalCobrado?["ARS"] ?? 0, pendiente: cob?.totalPendiente?["ARS"] ?? 0,
                            atrasados: (cob?.pendientes ?? []).filter { $0.estado == "atrasado" }.count,
                            comision: cob?.totalComision?["ARS"] ?? 0, comisionAnterior: cobAntes?.totalComision?["ARS"] ?? 0,
                            comisionPorcentaje: conComision.map { (($0.comision ?? 0) / ($0.monto ?? 1) * 1000).rounded() / 10 },
                            ajustan: ajustes.count, suba: subas.isEmpty ? nil : subas.reduce(0, +) / Double(subas.count) * 100,
                            vencen: vencen, limite: limite, qr: TextosInforme.qr("\(Api.web().absoluteString)/informe?mes=\(m.mes)"))
    }

    static func pdf(_ d: DatosInforme) -> URL? {
        let tam = CGSize(width: 595, height: 842)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Informe de \(TextosInforme.nombreMes(d.m.mes)) \(d.m.mes.prefix(4)).pdf")
        var caja = CGRect(origin: .zero, size: tam)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { return nil }
        let paginas: [AnyView] = [AnyView(PortadaInforme(d: d)), AnyView(ResumenInforme(d: d)), AnyView(EquipoInforme(d: d)), AnyView(PlataInforme(d: d))]
        for p in paginas {
            let r = ImageRenderer(content: p.frame(width: tam.width, height: tam.height).background(Color.white).environment(\.colorScheme, .light))
            r.proposedSize = ProposedViewSize(tam)
            r.render { _, dibujar in
                ctx.beginPDFPage(nil)
                dibujar(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }
}

// MARK: - Las páginas

private let verde = Color(hex: 0x16443B)
private let tinta = Color(hex: 0x18201D)
private let gris = Color(hex: 0x6B6457)
private let lineaA4 = Color(hex: 0xE3DDCF)
private let oroA4 = Color(hex: 0xF2BB57)

private func mesAnio(_ d: DatosInforme) -> String { "\(TextosInforme.nombreMes(d.m.mes)) \(d.m.mes.prefix(4))".uppercased() }

private struct CabezaInforme: View {
    var d: DatosInforme
    var n: Int
    var kicker: String
    var titulo: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Corredor").font(.system(size: 14, weight: .heavy)).foregroundStyle(verde)
                Spacer()
                Text("\(d.m.inmobiliaria ?? "") · \(mesAnio(d)) · \(n)/4".uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(gris)
            }
            Rectangle().fill(lineaA4).frame(height: 1)
            Text(kicker).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(gris).padding(.top, 8)
            Text(titulo).font(.system(size: 22, weight: .bold)).foregroundStyle(tinta).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func porcentajeCobrado(_ d: DatosInforme) -> Int {
    let total = d.cobrado + d.pendiente
    return total > 0 ? Int((d.cobrado / total * 100).rounded()) : 0
}

private struct PortadaInforme: View {
    var d: DatosInforme
    var body: some View {
        let a = d.m.actual, b = d.m.mesAnterior
        let moneda = d.m.moneda ?? "USD"
        let hon = a.honorarios?[moneda] ?? 0
        let dC = TextosInforme.diferencia(Double(a.cierres ?? 0), Double(b.cierres ?? 0), porcentaje: false)
        let dH = TextosInforme.diferencia(hon, b.honorarios?[moneda] ?? 0, porcentaje: true)
        let total = d.cobrado + d.pendiente
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Corredor").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Text("INFORME MENSUAL").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Text(mesAnio(d)).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(oroA4)
            Text(d.m.inmobiliaria ?? "").font(.system(size: 34, weight: .bold)).foregroundStyle(.white).padding(.top, 6)
            Text(TextosInforme.fraseDelMes(d.m)).font(.system(size: 22, weight: .regular, design: .serif)).italic().foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Spacer()
            HStack(spacing: 12) {
                cuadro("Cierres", "\(a.cierres ?? 0)", dC.map { "\($0.0) vs \(TextosInforme.nombreMes(d.m.anterior))" }, oro: false)
                cuadro("Honorarios", "\(moneda) \(TextosInforme.corto(hon))", dH?.0, oro: false)
                cuadro("Cobrado", "\(porcentajeCobrado(d))\(Formato.fino)%", "ARS \(TextosInforme.corto(d.cobrado)) de \(TextosInforme.corto(total))", oro: true)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(verde)
    }

    private func cuadro(_ t: String, _ v: String, _ det: String?, oro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(oro ? tinta.opacity(0.7) : .white.opacity(0.7))
            Text(v).font(.system(size: 24, weight: .bold)).foregroundStyle(oro ? tinta : .white).lineLimit(1).minimumScaleFactor(0.6)
            if let det { Text(det).font(.system(size: 9)).foregroundStyle(oro ? tinta.opacity(0.7) : .white.opacity(0.75)) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(oro ? oroA4 : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ResumenInforme: View {
    var d: DatosInforme
    var body: some View {
        let a = d.m.actual, b = d.m.mesAnterior
        let cuadros: [(String, Int, (String, Bool)?, Bool)] = [
            ("Consultas", a.consultas ?? 0, TextosInforme.diferencia(Double(a.consultas ?? 0), Double(b.consultas ?? 0), porcentaje: true), false),
            ("Visitas", a.visitas ?? 0, TextosInforme.diferencia(Double(a.visitas ?? 0), Double(b.visitas ?? 0), porcentaje: true), false),
            ("Reservas", a.reservas ?? 0, TextosInforme.diferencia(Double(a.reservas ?? 0), Double(b.reservas ?? 0), porcentaje: false), false),
            ("Cierres", a.cierres ?? 0, TextosInforme.diferencia(Double(a.cierres ?? 0), Double(b.cierres ?? 0), porcentaje: false), true),
        ]
        let embudo: [(String, Int, UInt32)] = [("Consultas", a.consultas ?? 0, 0xD6E2DC), ("Visitas", a.visitas ?? 0, 0x8FB0A3),
                                                ("Reservas", a.reservas ?? 0, 0x3F7A6A), ("Cierres", a.cierres ?? 0, 0x16443B)]
        let tope = Double(max(1, embudo.map(\.1).max() ?? 1))
        let serie = d.m.serie ?? []
        let topeSerie = max(1, serie.map(\.monto).max() ?? 1)
        let anterior = TextosInforme.nombreMes(d.m.anterior)
        let consejo: String? = {
            let ac = a.captaciones ?? 0, bc = b.captaciones ?? 0
            if ac < bc && bc > 0 { return "las captaciones vienen \(Int(((1 - Double(ac) / Double(bc)) * 100).rounded()))\(Formato.fino)% atrás de \(anterior)." }
            if (a.caidas ?? 0) > 0, let c = d.m.caidas?.first {
                return "\(Formato.cantidad(c.cantidad, "operación se cayó", "operaciones se cayeron")) \(TextosInforme.motivo(c.motivo))."
            }
            return nil
        }()
        VStack(alignment: .leading, spacing: 18) {
            CabezaInforme(d: d, n: 2, kicker: "01 · CÓMO NOS FUE", titulo: TextosInforme.tituloResumen(d.m))
            HStack(spacing: 10) {
                ForEach(Array(cuadros.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.3 ? .white.opacity(0.8) : gris)
                        Text(Formato.numero(c.1)).font(.system(size: 24, weight: .bold)).foregroundStyle(c.3 ? .white : tinta)
                        if let x = c.2 { Text(x.0).font(.system(size: 10, weight: .bold)).foregroundStyle(c.3 ? oroA4 : (x.1 ? Color(hex: 0x2F7A4F) : Color(hex: 0xB33A3A))) }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(c.3 ? verde : Color(hex: 0xF5F1E8), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Embudo de \(TextosInforme.nombreMes(d.m.mes))").font(.system(size: 12, weight: .bold)).foregroundStyle(tinta)
                ForEach(Array(embudo.enumerated()), id: \.offset) { i, e in
                    HStack(spacing: 10) {
                        Text(e.0).font(.system(size: 10)).foregroundStyle(gris).frame(width: 64, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: e.2))
                                .frame(width: i == 0 ? g.size.width : max(e.1 > 0 ? g.size.width * 0.02 : 0, g.size.width * CGFloat(Double(e.1) / tope)))
                        }
                        .frame(height: 16)
                        Text(Formato.numero(e.1)).font(.system(size: 11, weight: .bold)).foregroundStyle(tinta).frame(width: 40, alignment: .trailing)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Honorarios de los últimos 6 meses · \(d.m.moneda ?? "USD")").font(.system(size: 12, weight: .bold)).foregroundStyle(tinta)
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(serie.enumerated()), id: \.offset) { i, s in
                        VStack(spacing: 4) {
                            Text(TextosInforme.kBarra(s.monto)).font(.system(size: 9, weight: i == serie.count - 1 ? .bold : .regular)).foregroundStyle(tinta)
                            RoundedRectangle(cornerRadius: 4).fill(i == serie.count - 1 ? verde : Color(hex: 0xC9D8D1))
                                .frame(height: max(2, CGFloat(s.monto / topeSerie) * 110))
                            Text(String(TextosInforme.nombreMes(s.mes).prefix(3))).font(.system(size: 9, weight: i == serie.count - 1 ? .bold : .regular)).foregroundStyle(gris)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 150, alignment: .bottom)
            }
            if let consejo {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Color(hex: 0x7A5200))
                    (Text("Para \(TextosInforme.nombreMes(TextosInforme.siguiente(d.m.mes))):").bold() + Text(" \(consejo)")).font(.system(size: 11)).foregroundStyle(tinta)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xFBEFD5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct EquipoInforme: View {
    var d: DatosInforme
    var body: some View {
        let moneda = d.m.moneda ?? "USD"
        let eq = d.m.equipo ?? []
        let caidas = Array((d.m.caidas ?? []).prefix(3))
        let totalCaidas = (d.m.caidas ?? []).reduce(0) { $0 + $1.cantidad }
        VStack(alignment: .leading, spacing: 18) {
            CabezaInforme(d: d, n: 3, kicker: "02 · QUIÉN EMPUJÓ", titulo: TextosInforme.tituloEquipo(d.m))
            VStack(spacing: 0) {
                fila("Agente", "Captó", "Visitas", "Cierres", "Honorarios", encabezado: true, par: false)
                ForEach(Array(eq.enumerated()), id: \.element.id) { i, x in
                    fila(x.nombre, "\(x.captadas ?? 0)", "\(x.visitas ?? 0)", "\(x.cierres ?? 0)",
                         (x.honorarios?[moneda]).map { $0 > 0 ? Formato.plata($0, moneda) : "—" } ?? "—", encabezado: false, par: i % 2 == 1)
                }
                fila("Equipo", "\(eq.reduce(0) { $0 + ($1.captadas ?? 0) })", "\(eq.reduce(0) { $0 + ($1.visitas ?? 0) })", "\(eq.reduce(0) { $0 + ($1.cierres ?? 0) })",
                     Formato.plata(eq.reduce(0) { $0 + ($1.honorarios?[moneda] ?? 0) }, moneda), encabezado: true, par: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lineaA4))
            VStack(alignment: .leading, spacing: 8) {
                Text("Operaciones que se cayeron · \(totalCaidas)").font(.system(size: 12, weight: .bold)).foregroundStyle(tinta)
                if caidas.isEmpty {
                    Text("Ninguna operación se cayó en \(TextosInforme.nombreMes(d.m.mes)).").font(.system(size: 11)).foregroundStyle(gris)
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(caidas.enumerated()), id: \.offset) { i, c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(c.cantidad)").font(.system(size: 24, weight: .bold)).foregroundStyle(i == 0 ? Color(hex: 0xB33A3A) : tinta)
                                Text(TextosInforme.motivo(c.motivo)).font(.system(size: 10)).foregroundStyle(gris)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == 0 ? Color(hex: 0xFBE3E3) : Color(hex: 0xF5F1E8), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fila(_ a: String, _ b: String, _ c: String, _ dd: String, _ e: String, encabezado: Bool, par: Bool) -> some View {
        HStack {
            Text(a).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(width: 50, alignment: .trailing)
            Text(c).frame(width: 50, alignment: .trailing)
            Text(dd).frame(width: 50, alignment: .trailing)
            Text(e).frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 11, weight: encabezado ? .bold : .regular))
        .foregroundStyle(encabezado ? gris : tinta)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(par ? Color(hex: 0xF8F5EE) : (encabezado ? Color(hex: 0xF5F1E8) : Color.white))
    }
}

private struct PlataInforme: View {
    var d: DatosInforme
    var body: some View {
        let pct = porcentajeCobrado(d)
        let anterior = TextosInforme.nombreMes(d.m.anterior)
        let r = d.m.rendiciones
        let dCom = TextosInforme.diferencia(d.comision, d.comisionAnterior, porcentaje: true)
        let proximo = TextosInforme.nombreMes(TextosInforme.siguiente(d.m.mes))
        let titulo = "Se cobró el \(pct)\(Formato.fino)%." + (d.atrasados > 0 ? " Quedan \(Formato.cantidad(d.atrasados, "inquilino atrasado", "inquilinos atrasados"))." : " Nadie quedó atrasado.")
        VStack(alignment: .leading, spacing: 18) {
            CabezaInforme(d: d, n: 4, kicker: "03 · CUÁNTA PLATA ENTRÓ", titulo: titulo)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xF2D6D6))
                    RoundedRectangle(cornerRadius: 8).fill(verde).frame(width: g.size.width * CGFloat(pct) / 100)
                }
            }
            .frame(height: 22)
            HStack(spacing: 18) {
                (Text(Formato.plata(d.cobrado, "ARS")).bold() + Text(" cobrado")).foregroundStyle(tinta)
                if d.pendiente > 0 { (Text(Formato.plata(d.pendiente, "ARS")).bold() + Text(" pendiente")).foregroundStyle(Color(hex: 0xB33A3A)) }
            }
            .font(.system(size: 11))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rendido a propietarios").font(.system(size: 10, weight: .semibold)).foregroundStyle(gris)
                    Text(Formato.plata(r?.neto?["ARS"] ?? 0, "ARS")).font(.system(size: 18, weight: .bold)).foregroundStyle(tinta)
                    Text(Formato.cantidad(r?.emitidas ?? 0, "rendición emitida", "rendiciones emitidas") + ((r?.pendientes ?? 0) > 0 ? " · \(r?.pendientes ?? 0) sin emitir" : ""))
                        .font(.system(size: 9)).foregroundStyle(gris)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xF5F1E8), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Administración\(d.comisionPorcentaje.map { " (\(Formato.porcentaje($0)))" } ?? "")").font(.system(size: 10, weight: .semibold)).foregroundStyle(gris)
                    Text(Formato.plata(d.comision, "ARS")).font(.system(size: 18, weight: .bold)).foregroundStyle(tinta)
                    if let x = dCom { Text("\(x.0) vs \(anterior)").font(.system(size: 9, weight: .bold)).foregroundStyle(x.1 ? Color(hex: 0x2F7A4F) : Color(hex: 0xB33A3A)) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xF5F1E8), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Contratos en \(proximo)").font(.system(size: 12, weight: .bold)).foregroundStyle(tinta)
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Color(hex: 0x7A5200))
                    (Text(d.ajustan > 0 ? Formato.cantidad(d.ajustan, "ajusta", "ajustan") : "Ninguno ajusta").bold()
                        + Text(d.suba.map { " · el alquiler promedio sube \(Formato.porcentaje(($0 * 10).rounded() / 10))" } ?? "")).font(.system(size: 11)).foregroundStyle(tinta)
                }
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(gris)
                    (Text(d.vencen > 0 ? Formato.cantidad(d.vencen, "vence", "vencen") : "Ninguno vence").bold()
                        + Text(" antes de \(TextosInforme.nombreMes(d.limite))\(d.vencen > 0 ? " · preguntar si renuevan" : "")")).font(.system(size: 11)).foregroundStyle(tinta)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if let q = d.qr { Image(uiImage: q).interpolation(.none).resizable().frame(width: 56, height: 56) }
                Text("Escaneá para abrir el informe interactivo en Corredor, con el detalle de cada número.").font(.system(size: 10)).foregroundStyle(gris)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
