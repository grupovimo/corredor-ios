import SwiftUI
import UIKit

/// Las cuentas de los índices, como la web (lib/contratos/indices.ts).
enum CuentasIndices {
    struct Punto: Codable, Hashable { var periodo: String; var valor: Double }

    /// El último valor publicado hasta esa fecha.
    static func valorEn(_ serie: [Punto], _ fecha: String) -> Punto? {
        var v: Punto?
        for p in serie { if p.periodo > fecha { break }; v = p }
        return v
    }

    /// El factor desde el primer día de un mes (yyyy-MM) hasta el último dato.
    static func factorDesde(_ codigo: String, _ serie: [Punto], _ mes: String) -> Double? {
        guard !serie.isEmpty else { return nil }
        if codigo == "ipc" {
            // Los meses posteriores al de partida (el aumento del mes de partida ya está en el alquiler).
            return serie.filter { String($0.periodo.prefix(7)) > mes }.reduce(1) { $0 * (1 + $1.valor / 100) }
        }
        guard let base = valorEn(serie, mes + "-01"), base.valor > 0, let u = serie.last else { return nil }
        return u.valor / base.valor
    }

    private static func restarMeses(_ fecha: String, _ n: Int) -> String {
        guard let d = Fecha.dia(fecha), let x = Calendar.current.date(byAdding: .month, value: -n, to: d) else { return fecha }
        return Formato.diaISO(x)
    }

    /// La variación de los últimos `meses` (ICL y UVA: punta a punta; IPC: acumulada).
    static func variacion(_ codigo: String, _ serie: [Punto], _ meses: Int) -> Double? {
        guard let u = serie.last else { return nil }
        if codigo == "ipc" {
            let ult = serie.suffix(meses)
            return ult.count < meses ? nil : ult.reduce(1) { $0 * (1 + $1.valor / 100) } - 1
        }
        guard let b = valorEn(serie, restarMeses(u.periodo, meses)), b.valor > 0 else { return nil }
        return u.valor / b.valor - 1
    }

    /// Un valor por mes (el último del mes anterior o el último dato), los últimos `n` meses.
    static func mensuales(_ codigo: String, _ serie: [Punto], _ n: Int) -> [Double] {
        if codigo == "ipc" { return serie.suffix(n).map(\.valor) }
        guard let u = serie.last?.periodo, let du = Fecha.dia(u) else { return [] }
        var out: [Double] = []
        let cal = Calendar.current
        for k in stride(from: n - 1, through: 0, by: -1) {
            var f = u
            if k > 0, let ini = cal.date(from: cal.dateComponents([.year, .month], from: du)),
               let fin = cal.date(byAdding: DateComponents(month: -k + 1, day: -1), to: ini) { f = Formato.diaISO(fin) }
            if let v = valorEn(serie, f) { out.append(v.valor) }
        }
        return out
    }
}

/// Los índices de ajuste, como la página del panel (25E): ICL, IPC y UVA con su valor en su forma, la
/// fuente, cuándo se actualizó, la variación y los últimos 6 meses; el aviso si el IPC del mes pasado
/// todavía no salió; y la calculadora de alquiler con «copiar para WhatsApp».
struct Indices: View {
    @Environment(Estado.self) private var estado
    @State private var estados: [Ind]?
    @State private var series: [String: [CuentasIndices.Punto]] = [:]
    @State private var ajustanConIPC = 0
    @State private var error: ErrorApi?
    @State private var alquiler = "600.000"
    @State private var desde = ""
    @State private var indice = "icl"

    struct Ind: Codable, Identifiable { var codigo: String; var ultimoPeriodo: String?; var ultimoValor: Double?; var actualizadoEn: Date?; var id: String { codigo } }

    private static let fuente = ["icl": "BCRA · diario", "ipc": "INDEC · mensual", "uva": "BCRA · diario"]
    private var hoy: String { Formato.diaISO(Date()) }

    private static func dec(_ n: Double, _ d: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    private static func pct(_ n: Double) -> String { "\(n > 0 ? "+" : "")\(dec(n * 100, 1))\(Formato.fino)%" }
    private static func nombreMes(_ m: String) -> String { Int(m.dropFirst(5).prefix(2)).map { Ritmo.meses[max(0, min(11, $0 - 1))] } ?? m }
    private static func etiquetaMes(_ m: String) -> String { "\(Formato.mayuscula(nombreMes(m))) \(m.prefix(4))" }

    /// Los últimos 24 meses (sin el actual), del más nuevo al más viejo.
    private var meses: [String] {
        guard let d = Fecha.dia(hoy) else { return [] }
        return (1...24).compactMap { k in Calendar.current.date(byAdding: .month, value: -k, to: d).map { String(Formato.diaISO($0).prefix(7)) } }
    }

    private var mesPasado: String { meses.first.map { $0 + "-01" } ?? hoy }
    private var ipcDemorado: Bool { (estados?.first { $0.codigo == "ipc" }?.ultimoPeriodo).map { $0 < mesPasado } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Formato.sinViudas("Sólo consulta. Cada índice dice su fuente y cuándo se actualizó.")).estilo(.subhead).foregroundStyle(C.texto2)
                if let estados {
                    if ipcDemorado { avisoIPC }
                    ForEach(["icl", "ipc", "uva"], id: \.self) { c in tarjeta(c, estados.first { $0.codigo == c }) }
                    calculadora
                } else if let error {
                    EstadoError(que: "los índices", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 3) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Índices")
        .task(id: estado.version) { await cargar() }
    }

    private var avisoIPC: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hourglass").font(.system(size: 20)).foregroundStyle(C.avisoTinta)
            VStack(alignment: .leading, spacing: 2) {
                Text("El IPC de \(Self.nombreMes(mesPasado)) todavía no salió").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(Formato.sinViudas((ajustanConIPC > 0 ? "\(ajustanConIPC == 1 ? "1 contrato ajusta" : "\(ajustanConIPC) contratos ajustan") con ese dato. " : "")
                                       + "Mostramos un estimado con el último valor y te avisamos cuando lo publique el INDEC."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        .padding(14).background(C.avisoFondo, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func actualizado(_ f: Date?) -> String {
        guard let f else { return "Sin datos todavía" }
        return Formato.calendario.isDateInToday(f) ? "Actualizado hoy \(Formato.horaDe(f))" : "Actualizado el \(Formato.dia(f))"
    }

    @ViewBuilder
    private func tarjeta(_ c: String, _ e: Ind?) -> some View {
        let serie = series[c] ?? []
        let barras = CuentasIndices.mensuales(c, serie, 6)
        let maximo = max(barras.max() ?? 0.0001, 0.0001)
        let minimo = c == "ipc" ? 0 : (barras.min() ?? 0) * 0.9
        let v6 = CuentasIndices.variacion(c, serie, 6)
        let v12 = CuentasIndices.variacion(c, serie, 12)
        let valor: String = e?.ultimoValor.map { c == "ipc" ? "\(Self.dec($0, 1))\(Formato.fino)%" : c == "uva" ? "$\(Formato.fino)\(Self.dec($0))" : Self.dec($0) } ?? "—"
        let detalle: String = c == "ipc"
            ? (e?.ultimoPeriodo.map { "\(Formato.mayuscula(Self.nombreMes($0)))\(v12.map { " · \(Self.dec($0 * 100, 1))\(Formato.fino)% interanual" } ?? "")" } ?? "")
            : (v6.map { "\(Self.pct($0)) en 6 meses" } ?? "")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(c.uppercased()).estilo(.headline).foregroundStyle(C.texto)
                Spacer()
                Text(Self.fuente[c] ?? "").estilo(.footnote).foregroundStyle(C.texto3)
            }
            Text(valor).estilo(.montoMeta).foregroundStyle(C.texto)
            if !detalle.isEmpty { Text(detalle).font(Estilo(tamano: 14, peso: c == "ipc" ? .regular : .semibold, relativo: .footnote).font).foregroundStyle(c == "ipc" ? C.texto2 : C.okTinta) }
            if barras.isEmpty {
                Text("Sin datos todavía").estilo(.footnote).foregroundStyle(C.texto3)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(barras.enumerated()), id: \.offset) { i, b in
                        RoundedRectangle(cornerRadius: 4).fill(C.verde700.opacity([0.18, 0.18, 0.3, 0.45, 0.65, 1][max(0, 6 - barras.count + i)]))
                            .frame(height: max(6, CGFloat((b - minimo) / max(maximo - minimo, 0.0001)) * 48))
                    }
                }
                .frame(height: 48, alignment: .bottom)
                .accessibilityHidden(true)
            }
            Text(actualizado(e?.actualizadoEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
        }
        .padding(16).tarjeta()
    }

    private var monto: Double? { Double(alquiler.filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil } }
    private var factor: Double? { desde.isEmpty ? nil : CuentasIndices.factorDesde(indice, series[indice] ?? [], desde) }
    private var resultado: Double? { if let m = monto, let f = factor { return (m * f).rounded() }; return nil }

    private var calculadora: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Calculadora de alquiler", systemImage: "function").estilo(.headline).foregroundStyle(.white)
            Etiquetado("Alquiler") {
                HStack(spacing: 6) {
                    Text("ARS").estilo(.label).foregroundStyle(C.texto2)
                    TextField("", text: $alquiler).keyboardType(.numberPad).estilo(.body16).foregroundStyle(C.texto)
                        .onChange(of: alquiler) { _, v in
                            let n = v.filter(\.isNumber)
                            let t = n.isEmpty ? "" : Formato.numero(Int(n) ?? 0)
                            if t != v { alquiler = t }
                        }
                        .accessibilityLabel("Alquiler en pesos")
                }
                .padding(.horizontal, 12).frame(height: 44).background(C.superficie, in: .rect(cornerRadius: 12))
            }
            .foregroundStyle(.white)
            HStack(spacing: 10) {
                Etiquetado("Desde") {
                    Picker("Desde", selection: $desde) { ForEach(meses, id: \.self) { Text(Self.etiquetaMes($0)).tag($0) } }
                        .pickerStyle(.menu).tint(C.texto).frame(maxWidth: .infinity, minHeight: 44).background(C.superficie, in: .rect(cornerRadius: 12))
                }
                Etiquetado("Índice") {
                    Picker("Índice", selection: $indice) { Text("ICL").tag("icl"); Text("IPC").tag("ipc"); Text("UVA").tag("uva") }
                        .pickerStyle(.menu).tint(C.texto).frame(maxWidth: .infinity, minHeight: 44).background(C.superficie, in: .rect(cornerRadius: 12))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hoy sería").estilo(.footnote).foregroundStyle(.white.opacity(0.8))
                Text(resultado.map { Formato.plata($0, "ARS") } ?? "—").estilo(.montoMeta).foregroundStyle(C.oro)
                if let r = resultado, let f = factor, let m = monto {
                    Button("\(Self.pct(f - 1)) · copiar para WhatsApp") {
                        UIPasteboard.general.string = "Un alquiler de \(Formato.plata(m, "ARS")) desde \(Self.etiquetaMes(desde)), ajustado por \(indice.uppercased()), hoy sería \(Formato.plata(r, "ARS")) (\(Self.pct(f - 1)))."
                        estado.avisar("Copiado. Pegalo en WhatsApp.")
                    }
                    .buttonStyle(BotonTonal())
                } else {
                    Text("Falta el dato del índice para ese mes").estilo(.footnote).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(C.verde700, in: .rect(cornerRadius: 20, style: .continuous))
        .onAppear { if desde.isEmpty { desde = meses.count > 5 ? meses[5] : (meses.first ?? "") } }
    }

    private func cargar() async {
        do {
            estados = try await estado.api.get("/v1/indices")
            error = nil
        } catch let e as ErrorApi { if estados == nil { error = e }; return } catch { return }
        guard let d = Fecha.dia(hoy), let ini = Calendar.current.date(byAdding: .month, value: -25, to: d) else { return }
        var cal = Calendar.current.dateComponents([.year, .month], from: ini)
        cal.day = 1
        let desdeSerie = Formato.diaISO(Calendar.current.date(from: cal) ?? ini)
        var s: [String: [CuentasIndices.Punto]] = [:]
        for c in ["icl", "ipc", "uva"] {
            s[c] = (try? await estado.api.get("/v1/indices/\(c)", query: [.init(name: "desde", value: desdeSerie)])) ?? []
        }
        series = s
        struct Evento: Decodable { var contratoId: String; var tipo: String; var contrato: JSONLibre? }
        let ev: [Evento] = (try? await estado.api.get("/v1/contratos/vencimientos", query: [.init(name: "dias", value: "60")])) ?? []
        ajustanConIPC = Set(ev.filter { $0.tipo == "ajuste" && $0.contrato?["ajusteIndice"]?.texto == "ipc" }.map(\.contratoId)).count
    }
}
