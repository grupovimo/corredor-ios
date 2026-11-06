import SwiftUI

/// Un contrato (GET /v1/contratos).
struct ContratoAPI: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var estado: String?
    var propiedadId: String?
    var contactoId: String?
    var propietarioId: String?
    var agenteId: String?
    var inicio: String?
    var fin: String?
    var monto: Double?
    var moneda: String?
    var ajusteMeses: Int?
    var ajusteIndice: String?
    var ajustePorcentaje: Double?
    var comision: Double?
    var deposito: Double?
    var diaVencimiento: Int?
    var garanteNombre: String?
    var garanteTelefono: String?
    var garanteNotas: String?
    var notas: String?
    var honorarios: Double?
    var punitorioDiario: Double?
    var propiedadTitulo: String?
    var contactoNombre: String?
    var propietarioNombre: String?

    var ajusteTexto: String {
        guard let i = ajusteIndice, let m = ajusteMeses else { return "Sin ajuste" }
        return i == "fijo" ? "\(Formato.numero(Int(ajustePorcentaje ?? 0))) % cada \(m) meses" : "\(i.uppercased()) cada \(m) meses"
    }

    /// «ICL · 6 m», «Fijo 12 % · 4 m», «Sin ajuste» (la etiqueta de la lista).
    var etiquetaIndice: String {
        guard let m = ajusteMeses, m > 0 else { return "Sin ajuste" }
        let i = ajusteIndice.flatMap { TextosCobro.nombreIndice[$0] } ?? "Ajuste"
        let pct = ajusteIndice == "fijo" && (ajustePorcentaje ?? 0) > 0 ? " \(TextosCobro.numero(ajustePorcentaje ?? 0)) %" : ""
        return "\(i)\(pct) · \(m) m"
    }

    /// «ICL cada 6 meses», «12 % fijo cada 4 meses».
    var indiceCada: String { TextosCobro.indiceCada(indice: ajusteIndice, meses: ajusteMeses, porcentaje: ajustePorcentaje) }
}

/// Un ajuste o un vencimiento próximo (GET /v1/contratos/vencimientos?dias=90).
struct EventoContrato: Codable, Hashable {
    var contratoId: String
    var tipo: String
    var fecha: String
    var dias: Int
    var monto: Double?
    var moneda: String?
    /// A quién ya se le avisó este ajuste (inquilino, propietario).
    var avisados: [String]?
}

/// Contratos (21E): ordenados por lo próximo (una deuda, un ajuste, un vencimiento), con el alquiler de
/// hoy (el del mes, ya ajustado) y el botón para lo que haya que hacer: Cobrar, Avisar o Preguntar.
struct Contratos: View {
    @Environment(Estado.self) private var estado
    /// `ajustan`, `vencen` o `todos` (también los que terminaron); nil: vigentes y los que deben.
    var vista: String? = nil
    var indice: String? = nil
    @State private var todos: [ContratoAPI]?
    @State private var deudas: [String: DeudaContrato] = [:]
    @State private var actual: [String: Double] = [:]
    @State private var ajustes: [String: EventoContrato] = [:]
    @State private var vencimientos: [String: EventoContrato] = [:]
    @State private var filtro = "vigentes"
    @State private var nuevo = false
    @State private var leerPDF = false
    @State private var cobrando: ACobrar?
    @State private var mensaje: PedidoMensaje?
    @State private var error: ErrorApi?
    @State private var listo = false

    enum Proximo {
        case debe(periodo: String, vence: String, monto: Double, meses: Int, total: Double)
        case ajuste(fecha: String, dias: Int, monto: Double?, avisado: Bool)
        case vence(fecha: String, dias: Int)
        case aldia(ajuste: String?)
        case terminado
    }

    struct Fila: Identifiable {
        var k: ContratoAPI
        var proximo: Proximo
        var orden: Double
        var actual: Double
        var id: String { k.id }
    }

    private var hoy: String { Formato.diaISO(Date()) }

    private var filas: [Fila] {
        (todos ?? []).map { c in
            let aj = ajustes[c.id]
            let ve = vencimientos[c.id]
            let p: Proximo
            let orden: Double
            if let d = deudas[c.id], let viejo = d.meses.first {
                p = .debe(periodo: viejo.periodo, vence: viejo.vence ?? viejo.periodo, monto: viejo.esperado ?? 0, meses: d.meses.count, total: d.total ?? 0)
                orden = -1000 - Double(d.meses.count)
            } else if c.estado != "vigente" && c.estado != nil {
                p = .terminado
                orden = 10_000
            } else if let aj, aj.dias <= 30 {
                p = .ajuste(fecha: aj.fecha, dias: aj.dias, monto: aj.monto, avisado: aj.avisados?.contains("inquilino") == true)
                orden = Double(aj.dias)
            } else if let ve {
                p = .vence(fecha: ve.fecha, dias: ve.dias)
                orden = Double(ve.dias)
            } else {
                let f = c.tipo == "alquiler" ? Self.proximaFechaAjuste(c, hoy: hoy) : nil
                p = .aldia(ajuste: f)
                orden = 1000 + (f.map { Double(Cobranzas.diasEntre(hoy, $0)) } ?? 500)
            }
            return Fila(k: c, proximo: p, orden: orden, actual: actual[c.id] ?? c.monto ?? 0)
        }
        .sorted { $0.orden != $1.orden ? $0.orden < $1.orden : ($0.k.propiedadTitulo ?? "") < ($1.k.propiedadTitulo ?? "") }
    }

    private func deber(_ f: Fila) -> Bool { if case .debe = f.proximo { return true }; return false }
    private func ajusta(_ f: Fila) -> Bool { if case .ajuste = f.proximo { return true }; return false }

    private var lista: [Fila] {
        var l = filas.filter { $0.k.estado == "vigente" || $0.k.estado == nil || deber($0) || filtro == "todos" }
        switch filtro {
        case "ajustan": l = l.filter(ajusta)
        case "vencen": l = l.filter { vencimientos[$0.id] != nil }
        case "icl", "ipc", "uva", "fijo": l = l.filter { $0.k.ajusteIndice == filtro }
        default: break
        }
        return l
    }

    private var vigentes: [ContratoAPI] { (todos ?? []).filter { $0.estado == "vigente" } }
    private var ajustan30: Int { vigentes.filter { (ajustes[$0.id]?.dias ?? 99) <= 30 }.count }
    private var avisados30: Int { vigentes.filter { ajustes[$0.id].map { $0.dias <= 30 && $0.avisados?.contains("inquilino") == true } ?? false }.count }
    private var vencen90: Int { vigentes.filter { vencimientos[$0.id] != nil }.count }
    private var mensual: String {
        var m: [String: Double] = [:]
        for f in filas where f.k.estado == "vigente" && f.k.tipo == "alquiler" { m[f.k.moneda ?? "ARS", default: 0] += f.actual }
        return m.keys.sorted().map { mon in
            let v = m[mon] ?? 0
            return v >= 1_000_000 ? "\(mon) \(TextosCobro.numero((v / 100_000).rounded() / 10)) millones" : Formato.plata(v, mon)
        }.joined(separator: " + ")
    }

    private var nombreFiltro: String? {
        switch filtro {
        case "ajustan": return "Ajustan en 30 días"
        case "vencen": return "Vencen en 90 días"
        case "icl", "ipc", "uva": return filtro.uppercased()
        case "fijo": return "Aumento fijo"
        case "todos": return "Todos"
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let todos {
                    if todos.isEmpty {
                        EstadoVacio(icono: "doc.text", titulo: "Todavía no hay contratos",
                                    texto: "Corredor calcula cada ajuste y arma los\u{00A0}cobros.",
                                    accion: estado.escribe ? ("Cargar contrato", { leerPDF = false; nuevo = true }) : nil,
                                    secundaria: estado.escribe ? ("Subir el PDF y que lo lea", { leerPDF = true; nuevo = true }) : nil).padding(.top, 30)
                    } else {
                        tarjetas
                        chips
                        if let nombreFiltro {
                            HStack {
                                (Text("Mostrando: ") + Text(nombreFiltro).bold()).estilo(.footnote).foregroundStyle(C.texto2)
                                Spacer()
                                Button("Ver todos") { filtro = "vigentes" }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                            }
                            .padding(.horizontal, 4)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(lista.enumerated()), id: \.element.id) { i, f in fila(f, primera: i == 0) }
                            if lista.isEmpty {
                                HStack {
                                    Text("No hay contratos con ese filtro.").estilo(.texto14).foregroundStyle(C.texto3)
                                    Button("Ver todos") { filtro = "vigentes" }.font(Estilo.subheadFuerte.font)
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .tarjeta()
                        panelSeccion
                    }
                } else if let error {
                    EstadoError(que: "los contratos", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Contratos de alquiler")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if estado.escribe {
                Menu {
                    Button { leerPDF = false; nuevo = true } label: { Label("Nuevo contrato", systemImage: "square.and.pencil") }
                    Button { leerPDF = true; nuevo = true } label: { Label("Subir el PDF y que lo lea", systemImage: "doc.viewfinder") }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo contrato")
            }
        }
        .onAppear {
            guard !listo else { return }
            listo = true
            if let indice { filtro = indice } else if let vista { filtro = vista }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { AltaContrato(leer: leerPDF) }
        .sheet(item: $cobrando) { c in HojaCobro(item: c) }
        .hojaMensaje($mensaje)
    }

    // MARK: Tarjetas de arriba

    private var tarjetas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                tarjeta(icono: "chart.line.uptrend.xyaxis", etiqueta: "Ajustan en 30 días", valor: Formato.cantidad(ajustan30, "contrato", "contratos"), sub: subAjustan, oro: true) { filtro = "ajustan" }
                tarjeta(icono: "calendar.badge.exclamationmark", etiqueta: "Vencen en 90 días", valor: Formato.cantidad(vencen90, "contrato", "contratos"),
                        sub: Text(vencen90 > 0 ? "Preguntale a cada parte si renueva" : "Ninguno por ahora"), oro: false) { filtro = "vencen" }
                tarjeta(icono: "doc.text", etiqueta: "Vigentes", valor: Formato.numero(vigentes.count), sub: Text(mensual.isEmpty ? "Sin alquileres" : "\(mensual) por mes"), oro: false, hacer: nil)
            }
        }
    }

    private var subAjustan: Text {
        if ajustan30 == 0 { return Text("Ninguno en el mes") }
        if avisados30 >= ajustan30 { return Text(ajustan30 == 1 ? "Ya avisado" : "Todos ya avisados") }
        let resto = ajustan30 - avisados30
        if avisados30 > 0 {
            return Text("\(avisados30) ya \(avisados30 == 1 ? "avisado" : "avisados") · ") + Text("avisar a \(resto == 1 ? "el otro" : "los otros \(resto)")").bold().foregroundColor(C.okTinta)
        }
        return Text("Avisales antes · ") + Text("avisar a \(ajustan30 == 1 ? "ese" : "los \(ajustan30)")").bold().foregroundColor(C.okTinta)
    }

    private func tarjeta(icono: String, etiqueta: String, valor: String, sub: Text, oro: Bool, hacer: (() -> Void)?) -> some View {
        Button { hacer?() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(etiqueta, systemImage: icono).estilo(.footnoteFuerte).foregroundStyle(oro ? C.oroTinta : C.texto2)
                Text(valor).estilo(.titulo3).foregroundStyle(C.texto)
                sub.estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(14).frame(width: 220, alignment: .leading).frame(minHeight: 110, alignment: .topLeading)
            .background(oro ? C.avisoFondo : C.superficie, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(Presionable()).disabled(hacer == nil)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([("vigentes", "Vigentes"), ("ajustan", "Ajustan en 30 días"), ("vencen", "Vencen en 90 días"), ("icl", "ICL"), ("ipc", "IPC"), ("uva", "UVA"), ("fijo", "Fijo"), ("todos", "Todos")], id: \.0) { c in
                    Button { filtro = c.0 } label: {
                        Text(c.1).estilo(.footnoteFuerte).foregroundStyle(filtro == c.0 ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 12).frame(height: 32).background(filtro == c.0 ? C.accion : C.hundida, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(filtro == c.0 ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Fila

    struct Prox { var texto: String; var icono: String; var color: Color; var cta: String? }

    private func prox(_ f: Fila) -> Prox {
        switch f.proximo {
        case let .debe(periodo, vence, _, meses, _):
            let d = max(0, Cobranzas.diasEntre(vence, hoy))
            let que = meses > 1 ? "\(meses)\u{00A0}meses" : TextosCobro.nombreMes(periodo)
            return Prox(texto: "Debe \(que) · \(d == 1 ? "1 día" : "\(d) días")", icono: "exclamationmark.circle", color: C.errorTinta, cta: "Cobrar")
        case let .ajuste(fecha, _, monto, avisado):
            let dia = Fecha.dia(fecha).map { Self.diaMes($0) } ?? fecha
            return Prox(texto: "Ajusta el \(dia)\(monto.map { "\u{00A0}→ \(Formato.plata($0, f.k.moneda ?? "ARS"))" } ?? "")",
                        icono: avisado ? "checkmark.circle" : "chart.line.uptrend.xyaxis", color: C.oroTinta, cta: avisado ? nil : "Avisar")
        case let .vence(fecha, _):
            return Prox(texto: "Vence el \(TextosCobro.fechaCortita(fecha)) · ¿renueva?", icono: "calendar.badge.exclamationmark", color: C.oroTinta, cta: "Preguntar")
        case let .aldia(ajuste):
            return Prox(texto: ajuste.map { "Al día · ajusta en \(TextosCobro.nombreMes($0))" } ?? "Al día", icono: "checkmark.circle.fill", color: C.okTinta, cta: nil)
        case .terminado:
            return Prox(texto: f.k.estado == "rescindido" ? "Rescindido" : "Terminó", icono: "clock.arrow.circlepath", color: C.texto3, cta: nil)
        }
    }

    private func fila(_ f: Fila, primera: Bool) -> some View {
        let p = prox(f)
        let k = f.k
        return HStack(spacing: 10) {
            Button { estado.abrir(AFichaContrato(id: k.id)) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(k.propiedadTitulo ?? "Sin propiedad").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    Text([k.contactoNombre ?? "Sin inquilino", k.propietarioNombre.map { "prop. \($0)" }].compactMap { $0 }.joined(separator: "\u{00A0}· "))
                        .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    Text("\(Formato.plata(f.actual, k.moneda ?? "ARS")) · \(k.tipo == "venta" ? "Venta" : k.etiquetaIndice)")
                        .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    Label(p.texto, systemImage: p.icono).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(p.color).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if let cta = p.cta, estado.escribe {
                Button(cta) { hacer(f) }
                    .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                    .padding(.horizontal, 12).frame(height: 34).background(C.hundida, in: Capsule())
                    .buttonStyle(Presionable())
            } else {
                Chevron()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    /// Cobrar (desde el mes más viejo), Avisar el ajuste o Preguntar si renueva.
    private func hacer(_ f: Fila) {
        let k = f.k
        let n = TextosCobro.primerNombre(k.contactoNombre)
        let moneda = k.moneda ?? "ARS"
        let propiedad = k.propiedadTitulo ?? "Sin propiedad"
        switch f.proximo {
        case let .debe(periodo, vence, monto, _, _):
            cobrando = ACobrar(contratoId: k.id, contactoId: k.contactoId, nombre: k.contactoNombre, propiedad: propiedad, periodo: periodo,
                               esperado: monto, moneda: moneda, vence: vence, punitorioDiario: k.punitorioDiario)
        case let .ajuste(fecha, _, monto, _):
            let hasta = monto ?? f.actual
            mensaje = PedidoMensaje(
                titulo: "Avisarle a \(n.isEmpty ? "el inquilino" : n)", descripcion: "\(propiedad) · ajusta el \(TextosCobro.fechaCortita(fecha))",
                contactoId: k.contactoId, nombre: k.contactoNombre,
                texto: TextosCobro.ajuste(nombre: k.contactoNombre, indice: k.ajusteIndice ?? "", fecha: fecha, desde: f.actual, hasta: hasta, moneda: moneda),
                para: "ajuste", parametros: [n, TextosCobro.fechaCortita(fecha), Formato.plata(f.actual, moneda), Formato.plata(hasta, moneda)],
                alEnviar: { Task { await anotarAviso(k.id) } })
        case let .vence(fecha, _):
            let f2 = TextosCobro.fechaCortita(fecha, anio: true)
            mensaje = PedidoMensaje(
                titulo: "Preguntarle a \(n.isEmpty ? "el inquilino" : n)", descripcion: "\(propiedad) · vence el \(f2)",
                contactoId: k.contactoId, nombre: k.contactoNombre,
                texto: "\(TextosCobro.hola(k.contactoNombre)) El contrato de \(propiedad) vence el \(f2). ¿Te interesa renovarlo? Avisanos y lo vemos.",
                para: "recordatorio", parametros: [n, propiedad, f2])
        default: break
        }
    }

    /// El aviso del ajuste salió: queda anotado («4 ya avisados»).
    private func anotarAviso(_ id: String) async {
        struct Cuerpo: Encodable { var parte = "inquilino" }
        do {
            try await estado.api.hacer("POST", "/v1/contratos/\(id)/ajuste/avisos", Cuerpo())
            estado.version += 1
        } catch {
            estado.sugerir("El mensaje salió, pero no quedó anotado el aviso.", "Reintentar") { Task { await anotarAviso(id) } }
        }
    }

    // MARK: Panel de la sección

    @ViewBuilder private var panelSeccion: some View {
        let indices = ["icl", "ipc", "uva", "fijo"].filter { i in i != "fijo" || cuenta(i) > 0 }
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Por índice")
            VStack(spacing: 0) {
                ForEach(Array(indices.enumerated()), id: \.element) { n, i in
                    filaPanel(i == "fijo" ? "Aumento fijo" : i.uppercased(), cada(i), "percent", "\(cuenta(i))", primera: n == 0) { filtro = i }
                }
            }
            .tarjeta()
            TituloBloque(texto: "Renovaciones")
            filaPanel("Este trimestre", "preguntá a las partes", "arrow.triangle.2.circlepath", "\(vencen90)", primera: true) { filtro = "vencen" }.tarjeta()
            TituloBloque(texto: "Consultas")
            filaPanel("Índices", "ICL, IPC y UVA", "chart.xyaxis.line", nil, primera: true) { estado.abrir(ASeccion(clave: "indices")) }.tarjeta()
        }
        .padding(.top, 8)
    }

    private func cuenta(_ i: String) -> Int { vigentes.filter { $0.ajusteIndice == i }.count }
    private func cada(_ i: String) -> String {
        let ms = Array(Set(vigentes.filter { $0.ajusteIndice == i }.compactMap(\.ajusteMeses))).filter { $0 > 0 }.sorted()
        return ms.isEmpty ? "" : "cada \(ms.map(String.init).joined(separator: " o ")) meses"
    }

    private func filaPanel(_ t: String, _ d: String, _ icono: String, _ n: String?, primera: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 10) {
                Image(systemName: icono).foregroundStyle(C.texto2).frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                    if !d.isEmpty { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                }
                Spacer()
                if let n { Text(n).estilo(.subheadFuerte).foregroundStyle(C.texto) }
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Datos

    /// «12 nov».
    static func diaMes(_ f: Date) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "es_AR")
        d.dateFormat = "d MMM"
        return d.string(from: f).replacingOccurrences(of: ".", with: "")
    }

    /// La próxima fecha de ajuste según la periodicidad (sin monto: para «ajusta en marzo»).
    static func proximaFechaAjuste(_ c: ContratoAPI, hoy: String) -> String? {
        guard let cada = c.ajusteMeses, cada > 0, let ini = c.inicio.flatMap(Fecha.dia) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let dia = cal.component(.day, from: ini)
        for k in 1..<400 {
            guard let primero = cal.date(byAdding: .month, value: k * cada, to: cal.date(from: cal.dateComponents([.year, .month], from: ini)) ?? ini),
                  let rango = cal.range(of: .day, in: .month, for: primero) else { return nil }
            var comp = cal.dateComponents([.year, .month], from: primero)
            comp.day = min(dia, rango.count)
            comp.hour = 12
            guard let f = cal.date(from: comp) else { return nil }
            let s = Formato.diaISO(f)
            if let fin = c.fin, s > fin { return nil }
            if s > hoy { return s }
        }
        return nil
    }

    private func cargar() async {
        do {
            let l: [ContratoAPI] = try await estado.api.todas("/v1/contratos")
            let d: [DeudaContrato] = (try? await estado.api.get("/v1/contratos/deudas")) ?? []
            deudas = Dictionary(d.filter { !$0.meses.isEmpty }.map { ($0.contratoId, $0) }, uniquingKeysWith: { a, _ in a })
            if let m: MesCobranzas = try? await estado.api.get("/v1/cobranzas") {
                actual = Dictionary((m.pendientes + m.cobradas).map { ($0.contratoId, $0.monto) }, uniquingKeysWith: { a, _ in a })
            }
            let evs: [EventoContrato] = (try? await estado.api.get("/v1/contratos/vencimientos", query: [.init(name: "dias", value: "90")])) ?? []
            var a: [String: EventoContrato] = [:]
            var v: [String: EventoContrato] = [:]
            for e in evs {
                if e.tipo == "ajuste" { if a[e.contratoId] == nil { a[e.contratoId] = e } } else if v[e.contratoId] == nil { v[e.contratoId] = e }
            }
            ajustes = a
            vencimientos = v
            todos = l
            error = nil
        } catch let e as ErrorApi { if todos == nil { error = e } } catch {}
    }
}
