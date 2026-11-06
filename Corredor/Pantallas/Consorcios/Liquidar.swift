import SwiftUI
import UniformTypeIdentifiers

// MARK: - Liquidar expensas

/// Liquidar expensas: 1 Gastos → 2 Prorrateo → 3 Emitir → Listo. Emitir es lo único que se confirma
/// (no se deshace); cargar, corregir o sacar un gasto pasa al toque, con deshacer.
struct LiquidarConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var consorcio: String
    /// «AAAA-MM» pedido; nil es el que toca.
    var pedido: String?
    @State private var fijo: String?
    @State private var c: ConsorcioAPI?
    @State private var periodo = ""
    @State private var ficha: PeriodoAPI?
    @State private var prorrateo: ProrrateoExpensas?
    @State private var anterior: (periodo: String, total: Double, gastos: [GastoExpensas])?
    @State private var unidades: [UnidadAPI] = []
    @State private var deudores: [DeudorAPI] = []
    @State private var proveedores: [ProveedorConsorcio] = []
    @State private var reglamento: ReglamentoConsorcio.R?
    @State private var error: ErrorApi?
    @State private var cargado = false
    @State private var enProrrateo = false
    @State private var emitiendo = false
    @State private var listo: Emision?
    @State private var sacados: Set<String> = []
    @State private var gasto: EdicionGasto?
    @State private var desdeFactura = false
    @State private var subiendo = false
    @State private var todas = false
    @State private var abriendo = false
    @State private var previo: ArchivoPrevio?

    /// Lo que salió al emitir: los mails encolados (nil: no salieron) y los WhatsApp.
    struct Emision { var encolados: Int; var sinEmail: [String]?; var whatsapp: ConsorcioWhatsApp.EnvioPeriodo? }
    struct EdicionGasto: Identifiable { var g: GastoExpensas?; var comprobante: Archivo?; var id: String { g?.id ?? comprobante?.id ?? "nuevo" } }

    private var mes: String { Cons.nombreMes(periodo) }
    private var liquidado: Bool { ficha.map { $0.estado != "borrador" } ?? false }
    private var paso: Int { listo != nil || liquidado ? 4 : emitiendo ? 3 : enProrrateo ? 2 : 1 }
    private var gastos: [GastoExpensas] { (ficha?.gastos ?? []).filter { !sacados.contains($0.id) } }
    private var total: Double { gastos.reduce(0) { $0 + $1.monto } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c, cargado {
                    cabecera(c)
                    if ficha == nil { vacio } else if paso == 4 { hecho(c) } else if paso == 1 || (paso == 3 && !enProrrateo) { pasoGastos } else { pasoProrrateo(c) }
                } else if let error {
                    EstadoError(que: "la liquidación", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 6) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada(periodo.isEmpty ? "Liquidar" : "Expensas de \(mes)")
        .task(id: estado.version) { await cargar() }
        .sheet(item: $gasto) { e in
            if let f = ficha {
                HojaGastoConsorcio(consorcio: consorcio, periodo: f.id, gasto: e.g, comprobante: e.comprobante, proveedores: proveedores, columnas: c?.columnas ?? []) { g in sacar(g) }
            }
        }
        .sheet(isPresented: $emitiendo) { if let c, let f = ficha { hojaEmitir(c, f) } }
        .elegirArchivoConsorcio($desdeFactura) { a in if let x = a.first { Task { await factura(x) } } }
        .vistaPrevia($previo)
    }

    // MARK: Cabecera y pasos

    private func cabecera(_ c: ConsorcioAPI) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(c.nombre) · \(Cons.plural(c.metricas?.unidades ?? unidades.count, "unidad", "unidades"))").estilo(.footnote).foregroundStyle(C.texto2)
            if ficha != nil {
                HStack(spacing: 6) {
                    ForEach([("Gastos", 1), ("Prorrateo", 2), ("Emitir", 3)], id: \.1) { t, n in
                        let on = paso == n
                        let hecho = paso > n
                        HStack(spacing: 4) {
                            Text(hecho ? "✓" : "\(n)").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font)
                                .frame(width: 20, height: 20).background(on || hecho ? C.accion : C.hundida, in: Circle())
                                .foregroundStyle(on || hecho ? C.sobreAccion : C.texto2)
                            Text(t).font(Estilo.footnoteFuerte.font).foregroundStyle(on ? C.texto : C.texto2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var vacio: some View {
        // Con el tipo explícito: la tupla con un ternario adentro tiraba abajo al compilador (6.2).
        let texto: String = abriendo ? "Abriendo…" : "Abrir \(mes)"
        let abrirMes: () -> Void = { Task { await abrir() } }
        let accion: (String, () -> Void)? = estado.escribe ? (texto, abrirMes) : nil
        return EstadoVacio(icono: "doc.text", titulo: "Empezá la liquidación de \(mes)",
                           texto: "Abrí el período y cargá los gastos del mes: sueldos, servicios, abonos y arreglos. Después ves cómo se reparte entre las unidades antes de emitir.",
                           accion: accion)
    }

    // MARK: 1 · Gastos

    @ViewBuilder private var pasoGastos: some View {
        let sinComprobante = gastos.filter { $0.documentoId == nil }
        BloqueConsorcio(titulo: "Gastos del período · \(gastos.count)") {
            if gastos.isEmpty { VacioConsorcio(texto: "Todavía no hay gastos en \(mes). Cargá el primero o sumá la foto de la factura.") }
            ForEach(Array(gastos.enumerated()), id: \.element.id) { i, g in filaGasto(g, primero: i == 0) }
            if estado.escribe {
                RenglonConsorcio {
                    Button { gasto = EdicionGasto() } label: { Label("Cargar un gasto", systemImage: "plus") }
                    Spacer()
                    Button { desdeFactura = true } label: { Label(subiendo ? "Subiendo…" : "Desde la factura", systemImage: "doc.viewfinder") }.disabled(subiendo)
                }
                .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).buttonStyle(.borderless)
            }
            RenglonConsorcio {
                Text("Total del período").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Text(Formato.plata(total)).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.texto)
            }
        }
        if !sinComprobante.isEmpty {
            let nombres = sinComprobante.prefix(3).map { $0.descripcion.lowercased().replacingOccurrences(of: "^arreglo", with: "el arreglo", options: .regularExpression) }.joined(separator: ", ")
            Label {
                (Text(sinComprobante.count == 1 ? "1 gasto sin comprobante" : "\(sinComprobante.count) gastos sin comprobante").bold()
                 + Text(": \(nombres). Podés liquidar igual; queda marcado en la liquidación."))
            } icon: { Image(systemName: "doc.text") }
            .estilo(.texto14).foregroundStyle(C.avisoTinta).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(C.avisoFondo, in: .rect(cornerRadius: 14))
        }
        if let a = anterior { contra(a) }
        Button("Ver el prorrateo") { enProrrateo = true }.buttonStyle(BotonAccion()).disabled(gastos.isEmpty)
    }

    private func filaGasto(_ g: GastoExpensas, primero: Bool) -> some View {
        Button { if estado.escribe { gasto = EdicionGasto(g: g) } } label: {
            RenglonConsorcio(primero: primero) {
                IconoTono(icono: g.documentoId != nil ? Cons.iconoGasto(g) : "exclamationmark.triangle", tono: g.documentoId != nil ? .neutro : .oro)
                DosLineasConsorcio(titulo: g.descripcion, detalle: [g.proveedor, g.documentoId != nil ? "con\u{00A0}comprobante" : "sin\u{00A0}comprobante"].compactMap { $0 }.joined(separator: " · "))
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Cons.cifra(g.monto)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto)
                    Text(Cons.rubroGasto(g)).estilo(.footnote).foregroundStyle(C.texto3)
                }
            }
        }
        .buttonStyle(Presionable())
        .contextMenu {
            if estado.escribe {
                Button("Corregir", systemImage: "pencil") { gasto = EdicionGasto(g: g) }
                Button("Sacar", systemImage: "trash", role: .destructive) { sacar(g) }
            }
        }
    }

    /// «Contra octubre»: el total y los dos gastos que más subieron (o que son nuevos).
    private func contra(_ a: (periodo: String, total: Double, gastos: [GastoExpensas])) -> some View {
        let clave: (String) -> String = { $0.lowercased().components(separatedBy: "·")[0].trimmingCharacters(in: .whitespaces) }
        var antes: [String: Double] = [:]
        for g in a.gastos { antes[clave(g.descripcion), default: 0] += g.monto }
        var ahora: [String: Double] = [:]
        for g in gastos { ahora[clave(g.descripcion), default: 0] += g.monto }
        let subas = ahora.map { ($0.key, $0.value - (antes[$0.key] ?? 0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
        let v = Cons.variacion(total, a.total)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Contra \(Cons.nombreMes(a.periodo))").estilo(.subheadFuerte).foregroundStyle(C.texto)
            HStack { Text(Cons.NombreMes(a.periodo)).foregroundStyle(C.texto2); Spacer(); Text(Formato.plata(a.total)).foregroundStyle(C.texto2) }.estilo(.texto14)
            HStack { Text(Cons.NombreMes(periodo)).foregroundStyle(C.texto); Spacer(); Text(Formato.plata(total)).bold().foregroundStyle(C.texto) }.estilo(.texto14)
            if !v.isEmpty {
                Text(v + (subas.isEmpty ? "" : " · \(subas.joined(separator: " y "))")).font(Estilo.footnoteFuerte.font)
                    .foregroundStyle(total < a.total ? C.okTinta : C.avisoTinta)
            }
        }
        .padding(14).tarjeta()
    }

    // MARK: 2 · Prorrateo

    private struct FilaP: Identifiable { var id: String; var u: String; var p: String; var c: Double; var o: Double; var s: Double; var t: Double }

    private func filas(_ c: ConsorcioAPI) -> [FilaP] {
        let general = c.general
        let deuda = Dictionary(deudores.map { ($0.unidadId, $0.total) }, uniquingKeysWith: { a, _ in a })
        let reparto = Dictionary((prorrateo?.unidades ?? []).map { ($0.unidadId, $0.total) }, uniquingKeysWith: { a, _ in a })
        return unidades.sorted { Cons.porUnidad($0.etiqueta, $1.etiqueta) }.map { u in
            let o = reparto[u.id] ?? 0
            let s = deuda[u.id] ?? 0
            return FilaP(id: u.id, u: u.etiqueta, p: u.propietario ?? "Sin propietario", c: general.map { u.coeficientes?[$0.id] ?? 0 } ?? 0, o: o, s: s, t: o + s)
        }
    }

    @ViewBuilder private func pasoProrrateo(_ c: ConsorcioAPI) -> some View {
        let fs = filas(c)
        let visibles = todas ? fs : Array(fs.prefix(10))
        let suma = c.general.map { Cons.sumaCoeficientes(unidades, $0.id) } ?? 0
        BloqueConsorcio(titulo: "Prorrateo") {
            ForEach(Array(visibles.enumerated()), id: \.element.id) { i, f in
                RenglonConsorcio(primero: i == 0) {
                    Text(f.u).font(Estilo.filaLista.font).foregroundStyle(C.texto).frame(minWidth: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.p).estilo(.texto14).foregroundStyle(C.texto).lineLimit(1)
                        Text("Coef. \(Cons.coeficiente(f.c)) · Ordinarias \(Cons.cifra(f.o)) · Saldo ant. \(f.s > 0 ? Cons.cifra(f.s) : "—")")
                            .estilo(.footnote).foregroundStyle(f.s > 0 ? C.errorTinta : C.texto2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Cons.cifra(f.t)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto)
                }
            }
            RenglonConsorcio {
                if fs.count > 10 && !todas {
                    Button("… y \(Cons.plural(fs.count - 10, "unidad más", "unidades más"))") { todas = true }.font(Estilo.footnoteFuerte.font).buttonStyle(.borderless)
                    Text("·").foregroundStyle(C.texto3)
                }
                Text("coeficientes suman \(Cons.coeficiente(suma))").estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        revisar(c, fs, suma)
        HStack(spacing: 8) {
            Button("Volver a gastos") { enProrrateo = false }.buttonStyle(BotonHundido())
            if estado.escribe { Button("Liquidar \(mes)") { emitiendo = true }.buttonStyle(BotonAccion()) }
        }
    }

    private func item(_ ok: Bool, _ t: Text, oro: Bool = false) -> some View {
        Label { t } icon: { Image(systemName: ok ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(ok ? C.okTinta : oro ? C.avisoTinta : C.errorTinta) }
            .estilo(.texto14).foregroundStyle(C.texto)
    }

    @ViewBuilder private func revisar(_ c: ConsorcioAPI, _ fs: [FilaP], _ suma: Double) -> some View {
        let conDeuda = fs.filter { $0.s > 0 }.count
        let vence = Cons.vencimiento(periodo, c.diaVencimiento)
        let vence2 = Cons.vencimiento(periodo, c.diaSegundoVencimiento)
        VStack(alignment: .leading, spacing: 10) {
            Text("Qué revisar").estilo(.subheadFuerte).foregroundStyle(C.texto)
            if conDeuda > 0 {
                item(false, Text("\(Cons.plural(conDeuda, "unidad con deuda", "unidades con deuda")): se suma con interés del \(Cons.coma(c.interesMensual ?? 0))\u{00A0}% mensual."))
            } else {
                item(true, Text("Nadie debe meses anteriores."))
            }
            if abs(suma - 100) >= 0.005 {
                item(false, Text("Los coeficientes suman \(Cons.coeficiente(suma)): revisalos en Unidades."))
            } else if let r = reglamento, r.guardadoEn != nil, r.sinCambios == true {
                item(true, Text("Coeficientes del reglamento: sin\u{00A0}cambios."))
            } else if let r = reglamento, r.guardadoEn != nil {
                let unidadesCambio = Set((r.cambios ?? []).compactMap(\.unidad))
                let n = unidadesCambio.count
                VStack(alignment: .leading, spacing: 6) {
                    item(false, Text(n == 1 ? "Cambió el coeficiente de \(unidadesCambio.first ?? "")" : "Cambiaron los coeficientes de \(n) unidades") + Text(" desde el reglamento: revisalos en Unidades o tomalos como los\u{00A0}nuevos."))
                    if estado.escribe { Button("Tomalos como los nuevos") { Task { await guardarReglamento() } }.font(Estilo.footnoteFuerte.font) }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    item(true, Text("Los coeficientes suman 100\u{00A0}%. Guardalos como los del reglamento para que te avisemos si\u{00A0}cambian."))
                    if estado.escribe { Button("Guardalos como los del reglamento") { Task { await guardarReglamento() } }.font(Estilo.footnoteFuerte.font) }
                }
            }
            if let v = vence {
                item(true, Text("Vencimiento: \(Cons.diaBarraMes(v))\(vence2.map { " · 2.º vto \(Cons.diaBarraMes($0)) con recargo" } ?? "")."))
            } else {
                item(false, Text("Sin día de vencimiento: cargalo en los datos del consorcio."), oro: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
    }

    // MARK: 3 · Emitir

    private func hojaEmitir(_ c: ConsorcioAPI, _ f: PeriodoAPI) -> some View {
        HojaEmitirExpensas(mes: mes, mesSiguiente: Cons.nombreMes(Cons.mesSiguiente(periodo)), unidades: unidades, total: prorrateo?.total ?? total,
                   vence: Cons.vencimiento(periodo, c.diaVencimiento)) { await emitir(f) }
    }

    // MARK: 4 · Listo

    private func textoEnvio(_ l: Emision?) -> String {
        let conMail = unidades.filter { $0.propietarioEmail != nil }.count
        let sinContacto = unidades.filter { $0.propietarioEmail == nil && $0.propietarioTelefono == nil }.count
        let n = l?.encolados ?? conMail
        let imp = l?.sinEmail?.count ?? sinContacto
        if let l, l.sinEmail == nil { return "Quedó liquidado. Los mails no salieron: mandalos desde Expensas cuando vuelva la señal." }
        let wa = l?.whatsapp?.enviadas ?? 0
        let partes = [n > 0 ? "\(Cons.plural(n, "liquidación enviada", "liquidaciones enviadas")) por mail" : nil,
                      wa > 0 ? "\(wa) por WhatsApp" : nil,
                      imp > 0 ? (imp == 1 ? "1 lista" : "\(imp) listas") + " para imprimir" : nil].compactMap { $0 }
        let sinNumero = l?.whatsapp?.sinWhatsApp == true ? " Para mandarlas también por WhatsApp, conectá el número de la inmobiliaria." : ""
        return "\(Cons.lista(partes)). Cada propietario tiene su link con el detalle y los comprobantes.\(sinNumero)"
    }

    private func hecho(_ c: ConsorcioAPI) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(C.okTinta)
            Text("\(Cons.NombreMes(periodo)) liquidado").estilo(.titulo3).foregroundStyle(C.texto)
            Text(textoEnvio(listo)).estilo(.texto14).foregroundStyle(C.texto2).multilineTextAlignment(.center)
            ProgressView(value: 1).tint(C.accion)
            Button { Task { await imprimir() } } label: { Label("Imprimir para la cartelera", systemImage: "printer") }.buttonStyle(BotonHundido())
            Button("Volver al consorcio") { cerrar() }.buttonStyle(BotonAccion())
        }
        .padding(18).frame(maxWidth: .infinity).tarjeta()
    }

    // MARK: Acciones

    private func cargar() async {
        let b = "/v1/consorcios/\(consorcio)"
        do {
            let x: ConsorcioAPI = try await estado.api.get(b)
            let ps: [PeriodoAPI] = try await estado.api.get("\(b)/periodos", query: [.init(name: "limite", value: "24")])
            unidades = (try? await estado.api.get("\(b)/unidades")) ?? []
            deudores = (try? await estado.api.get("\(b)/deudores")) ?? []
            proveedores = (try? await ProveedoresConsorcio.todos(estado.api)) ?? []
            reglamento = try? await estado.api.get("\(b)/reglamento")
            let p = fijo ?? pedido
            let elegido: (String, PeriodoAPI?)
            if let p, p.range(of: "^\\d{4}-\\d{2}$", options: .regularExpression) != nil { elegido = (p, ps.first { $0.periodo == p }) } else {
                let a = Cons.aLiquidar(ps)
                elegido = (a.periodo, a.borrador)
            }
            periodo = elegido.0
            if let actual = elegido.1 {
                ficha = try await estado.api.get("\(b)/periodos/\(actual.id)")
                if actual.estado == "borrador" {
                    prorrateo = try? await estado.api.get("\(b)/periodos/\(actual.id)/prorrateo")
                } else { prorrateo = nil }
            } else {
                ficha = nil
                prorrateo = nil
            }
            if let a = Cons.anterior(ps, periodo) {
                let fa: PeriodoAPI? = try? await estado.api.get("\(b)/periodos/\(a.id)")
                anterior = (a.periodo, a.total ?? 0, fa?.gastos ?? [])
            } else { anterior = nil }
            sacados = []
            c = x
            cargado = true
            error = nil
        } catch let e as ErrorApi {
            if !cargado { error = e }
        } catch {}
    }

    private func abrir() async {
        abriendo = true
        defer { abriendo = false }
        struct P: Encodable { var periodo: String }
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(consorcio)/periodos", P(periodo: periodo))
            fijo = periodo
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// Sacar un gasto: se esconde al toque y el «Deshacer» lo vuelve a cargar igual.
    private func sacar(_ g: GastoExpensas) {
        guard let f = ficha else { return }
        sacados.insert(g.id)
        let api = estado.api
        let base = "/v1/consorcios/\(consorcio)/periodos/\(f.id)/gastos"
        Task {
            do {
                try await api.hacer("DELETE", "\(base)/\(g.id)")
                estado.avisar("Sacaste «\(g.descripcion)»") {
                    Task {
                        do {
                            try await api.hacer("POST", base, HojaGastoConsorcio.Datos(descripcion: g.descripcion, tipo: g.tipo ?? "ordinaria", monto: g.monto, columnaId: g.columnaId,
                                                                               proveedorId: g.proveedorId, documentoId: g.documentoId, fecha: g.fecha))
                        } catch { estado.avisar(error) }
                        estado.version += 1
                    }
                }
                estado.version += 1
            } catch {
                sacados.remove(g.id)
                estado.avisar(error)
            }
        }
    }

    /// La foto o el PDF de una factura: se sube y se abre la hoja con el comprobante puesto.
    private func factura(_ x: (Data, String, String)) async {
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(x.0, nombre: x.1, tipo: x.2, uso: "documento")
            gasto = EdicionGasto(g: nil, comprobante: a)
        } catch { estado.avisar(error) }
    }

    private func guardarReglamento() async {
        do {
            reglamento = try await estado.api.enviar("PUT", "/v1/consorcios/\(consorcio)/reglamento", [String: String]())
            estado.avisar("Guardamos los coeficientes del reglamento")
        } catch { estado.avisar(error) }
    }

    /// Liquida el período (todo o nada, en la API) y manda los recibos por mail y por WhatsApp.
    private func emitir(_ f: PeriodoAPI) async -> Bool {
        let base = "/v1/consorcios/\(consorcio)/periodos/\(f.id)"
        do {
            try await estado.api.hacer("POST", "\(base)/liquidar")
        } catch {
            let t = (error as? ErrorApi)?.detalle ?? "Probá de nuevo."
            estado.sugerir("No se emitió · \(t)", "Reintentar") { Task { _ = await emitir(f) } }
            return false
        }
        // Ya está liquidado: si el envío falla, se reintenta desde Expensas (no se vuelve a liquidar).
        let envio: EnvioMailExpensas? = try? await estado.api.enviar("POST", "\(base)/enviar", [String: String]())
        let wa = try? await ConsorcioWhatsApp.liquidaciones(estado.api, consorcio: consorcio, periodo: f.id)
        Haptico.exito()
        listo = Emision(encolados: envio?.encolados ?? 0, sinEmail: envio.map { $0.sinEmail ?? [] }, whatsapp: wa)
        emitiendo = false
        fijo = periodo
        estado.version += 1
        return true
    }

    private func imprimir() async {
        guard let f = ficha else { return }
        do {
            let u = try await Documentos.expensas(consorcio: consorcio, periodo: f.id, unidad: nil, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

/// «Vas a emitir <mes>»: todo lo que sale y a quién, el tilde «Revisé…» y «Emitir y mandar».
struct HojaEmitirExpensas: View {
    @Environment(\.dismiss) private var cerrar
    var mes: String
    var mesSiguiente: String
    var unidades: [UnidadAPI]
    var total: Double
    var vence: String?
    var emitir: () async -> Bool
    @State private var revisado = false
    @State private var mandando = false

    var body: some View {
        let conContacto = unidades.filter { $0.propietarioEmail != nil || $0.propietarioTelefono != nil }.count
        let sin = unidades.filter { $0.propietarioEmail == nil && $0.propietarioTelefono == nil }.sorted { Cons.porUnidad($0.etiqueta, $1.etiqueta) }.map(\.etiqueta)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Esto no se deshace: si hay un error, se corrige con una nota de crédito en \(mesSiguiente).").estilo(.texto14).foregroundStyle(C.texto2)
                    VStack(spacing: 0) {
                        RenglonConsorcio(primero: true) {
                            Text("\(Cons.plural(unidades.count, "liquidación", "liquidaciones"))\(vence.map { " · vence el \(Cons.diaBarraMes($0))" } ?? "")").estilo(.texto14).foregroundStyle(C.texto2)
                            Spacer()
                            Text(Formato.plata(total)).font(Estilo.filaLista.font).foregroundStyle(C.texto)
                        }
                        RenglonConsorcio {
                            Text("Se mandan por WhatsApp y mail").estilo(.texto14).foregroundStyle(C.texto2)
                            Spacer()
                            Text(Cons.plural(conContacto, "propietario", "propietarios")).font(Estilo.filaLista.font).foregroundStyle(C.texto)
                        }
                        if !sin.isEmpty {
                            RenglonConsorcio {
                                Text("Sin contacto · van impresas").estilo(.texto14).foregroundStyle(C.avisoTinta)
                                Spacer()
                                Text("\(sin.count) (\(Cons.lista(sin)))").font(Estilo.filaLista.font).foregroundStyle(C.avisoTinta).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .tarjeta()
                    Toggle("Revisé los gastos y el prorrateo", isOn: $revisado).estilo(.subheadFuerte).tint(C.accion)
                    HStack(spacing: 8) {
                        Button("Revisar de nuevo") { cerrar() }.buttonStyle(BotonHundido())
                        Button {
                            Task {
                                mandando = true
                                _ = await emitir()
                                mandando = false
                            }
                        } label: { Text(mandando ? "Emitiendo…" : "Emitir y mandar") }
                        .buttonStyle(BotonAccion()).disabled(!revisado || mandando)
                    }
                }
                .padding(16)
            }
            .background(C.elevado)
            .navigationTitle("Vas a emitir \(mes)").navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(mandando)
        .hojaTLW([.large])
    }
}

/// Cargar o corregir un gasto del período: de qué es, monto, fecha, proveedor (o uno nuevo con rubro),
/// tipo, columna y el comprobante (foto o PDF). Sin comprobante se puede liquidar igual.
struct HojaGastoConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var consorcio: String
    var periodo: String
    var gasto: GastoExpensas?
    var comprobante: Archivo?
    var proveedores: [ProveedorConsorcio]
    var columnas: [ColumnaAPI]
    var alSacar: (GastoExpensas) -> Void
    @State private var descripcion = ""
    @State private var monto: Double?
    @State private var fecha = Date()
    @State private var proveedor = ""
    @State private var nuevoProveedor = ""
    @State private var rubro = ""
    @State private var tipo = "ordinaria"
    @State private var columna = ""
    @State private var documento: (id: String, nombre: String)?
    @State private var elegir = false
    @State private var subiendo = false
    @State private var guardando = false
    @State private var listo = false
    @State private var previo: ArchivoPrevio?

    struct Datos: Encodable {
        var descripcion: String; var tipo: String; var monto: Double; var columnaId: String?; var proveedorId: String?; var documentoId: String?; var fecha: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CampoConsorcio(etiqueta: "De qué es") { TextField("Abono del ascensor, factura de luz…", text: $descripcion) }
                    CampoConsorcio(etiqueta: "Monto") { TextField("Monto", value: $monto, format: .number).keyboardType(.decimalPad) }
                    DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                }
                Section {
                    Picker("Proveedor", selection: $proveedor) {
                        Text("Sin proveedor").tag("")
                        ForEach(proveedores) { Text($0.conRubro).tag($0.id) }
                        Text("Otro (escribilo)…").tag("otro")
                    }
                    if proveedor == "otro" {
                        CampoConsorcio(etiqueta: "Nombre del proveedor") { TextField("", text: $nuevoProveedor) }
                        CampoConsorcio(etiqueta: "Rubro (opcional)") { TextField("Plomería", text: $rubro) }
                    }
                    Picker("Tipo", selection: $tipo) {
                        Text("Ordinaria (todos los meses)").tag("ordinaria")
                        Text("Extraordinaria (obra, arreglo grande)").tag("extraordinaria")
                    }
                    if columnas.count > 1 {
                        Picker("Columna", selection: $columna) {
                            Text("General").tag("")
                            ForEach(columnas.filter { $0.porDefecto != true }) { Text($0.nombre).tag($0.id) }
                        }
                    }
                }
                Section("Comprobante (opcional)") {
                    if let d = documento {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(C.okTinta)
                            Text(d.nombre).estilo(.subheadFuerte).lineLimit(1)
                            Spacer()
                            Button("Ver") { Task { await ver(d.id) } }.buttonStyle(.borderless)
                            Button("Cambiar") { documento = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        Button { elegir = true } label: { Label(subiendo ? "Subiendo…" : "Sumar la factura · foto o PDF", systemImage: "doc.badge.plus") }.disabled(subiendo)
                        Text("Sin comprobante se puede liquidar igual: queda marcado en la liquidación.").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
                if let gasto {
                    Section { Button("Sacar este gasto", role: .destructive) { cerrar(); alSacar(gasto) } }
                }
            }
            .navigationTitle(gasto == nil ? "Cargar un gasto" : "Corregir el gasto").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(!valido || guardando) }
            }
        }
        .onAppear {
            guard !listo else { return }
            listo = true
            if let g = gasto {
                descripcion = g.descripcion
                monto = g.monto
                fecha = g.fecha.flatMap(Fecha.dia) ?? Date()
                proveedor = g.proveedorId ?? ""
                tipo = g.tipo ?? "ordinaria"
                columna = g.columnaId ?? ""
                if let d = g.documentoId { documento = (d, "Comprobante") }
            }
            if let a = comprobante { documento = (a.id, a.nombre ?? "Comprobante") }
        }
        .elegirArchivoConsorcio($elegir) { a in if let x = a.first { Task { await subir(x) } } }
        .vistaPrevia($previo)
    }

    private var valido: Bool {
        !descripcion.trimmingCharacters(in: .whitespaces).isEmpty && descripcion.count <= 200 && (monto ?? 0) > 0
            && (proveedor != "otro" || !nuevoProveedor.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func subir(_ x: (Data, String, String)) async {
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(x.0, nombre: x.1, tipo: x.2, uso: "documento")
            documento = (a.id, a.nombre ?? x.1)
        } catch { estado.avisar(error) }
    }

    private func ver(_ id: String) async {
        do {
            let u = try await Documentos.archivoConsorcio(id, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        do {
            var pid: String? = proveedor.isEmpty ? nil : proveedor
            if proveedor == "otro" {
                let p = try await ProveedoresConsorcio.crear(estado.api, .init(nombre: nuevoProveedor.trimmingCharacters(in: .whitespaces), rubro: rubro.nonEmpty))
                pid = p.id
                proveedor = p.id
            }
            let d = Datos(descripcion: descripcion.trimmingCharacters(in: .whitespaces), tipo: tipo, monto: Cons.redondo(monto ?? 0), columnaId: columna.nonEmpty,
                          proveedorId: pid, documentoId: documento?.id, fecha: Formato.diaISO(fecha))
            let base = "/v1/consorcios/\(consorcio)/periodos/\(periodo)/gastos"
            if let g = gasto {
                try await estado.api.hacer("PUT", "\(base)/\(g.id)", d)
                estado.avisar("Gasto corregido")
            } else {
                try await estado.api.hacer("POST", base, d)
                estado.avisar("Gasto cargado")
            }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
