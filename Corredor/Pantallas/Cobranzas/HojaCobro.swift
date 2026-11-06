import SwiftUI

/// El link público de cada recibo: se pide una sola vez por cobro (uno nuevo invalida el anterior).
@MainActor
enum LinksRecibo {
    private static var links: [String: String] = [:]

    static func de(_ api: Api, contrato: String, cobro: String) async throws -> String {
        if let u = links[cobro] { return u }
        struct L: Decodable { var url: String }
        let l: L = try await api.enviar("POST", "/v1/contratos/\(contrato)/cobros/\(cobro)/compartir", [String: String]())
        links[cobro] = l.url
        return l.url
    }
}

/// «Registrar un cobro y mandar el recibo» (prototipo P). Dos pasos en la misma hoja:
/// 1. el cobro: el desglose del recibo (el alquiler del contrato, las expensas que se escriben, los
///    punitorios por los días de atraso según la cláusula, que se pueden sacar, y otros conceptos), el
///    total (se toca para poner lo que pagó si pagó una parte), el medio y «Registrar ARS …»;
/// 2. el recibo listo, con el sello PAGADO, y el mensaje para mandarlo por WhatsApp con el link.
/// Registrar no pregunta nada: la fila se va y queda «Deshacer». Con `item.cobro` abre directo el
/// paso 2 (el «Mandar recibo» de un cobro que ya estaba).
struct HojaCobro: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var item: ACobrar
    var ocultar: ((String) -> Void)? = nil
    var mostrar: ((String) -> Void)? = nil

    struct Otro: Identifiable { let id = UUID(); var concepto = ""; var monto: Double? }

    @State private var medio = "transferencia"
    @State private var total: Double?
    @State private var editando = false
    @State private var expensas: Double?
    @State private var conPunitorios = true
    @State private var otros: [Otro] = []
    @State private var fecha = Date()
    @State private var cobro: Cobro?
    @State private var registradoEn: Date?
    @State private var url: String?
    @State private var texto = ""
    @State private var enviado = false
    @State private var inmo: Inmobiliaria?
    @FocusState private var enTotal: Bool

    private var hoy: String { Formato.diaISO(Date()) }
    private var diasAtraso: Int { item.vence < hoy ? max(0, Cobranzas.diasEntre(item.vence, hoy)) : 0 }
    private var punitorios: Double {
        guard let p = item.punitorioDiario, p > 0, diasAtraso > 0 else { return 0 }
        return (item.esperado * p * Double(diasAtraso) / 100).rounded()
    }
    private var textoDias: String { diasAtraso == 1 ? "1 día" : "\(diasAtraso) días" }
    private var conceptos: [Cobro.Concepto] {
        var cs = [Cobro.Concepto(concepto: "Alquiler", monto: item.esperado)]
        if let e = expensas, e > 0 { cs.append(.init(concepto: "Expensas ordinarias", monto: e)) }
        if punitorios > 0 && conPunitorios { cs.append(.init(concepto: "Punitorios \(textoDias)", monto: punitorios)) }
        for o in otros { if let m = o.monto, m > 0, !o.concepto.trimmingCharacters(in: .whitespaces).isEmpty { cs.append(.init(concepto: o.concepto.trimmingCharacters(in: .whitespaces), monto: m)) } }
        return cs
    }
    private var suma: Double { conceptos.reduce(0) { $0 + $1.monto } }
    private var monto: Double { total ?? suma }
    private var parcial: Bool { total != nil && total!.rounded() != suma.rounded() }
    private var mes: String { TextosCobro.nombreMes(item.periodo) }
    private var n: String { TextosCobro.primerNombre(item.nombre) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let cobro { reciboListo(cobro) } else { pasoCobro }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(C.superficie)
            .navigationTitle(cobro == nil ? "Cobro de \(item.nombre ?? "")" : "Recibo listo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(cobro == nil ? "Cancelar" : "Cerrar") { cerrar() } } }
        }
        .presentationDetents([.large])
        .task {
            inmo = await Documentos.inmobiliaria(estado.api)
            if let c = item.cobro {
                cobro = c
                registradoEn = Date()
                await prepararLink(c)
            }
        }
    }

    // MARK: 1. El cobro

    @ViewBuilder private var pasoCobro: some View {
        Text("\(Formato.mayuscula(mes)) · \(item.propiedad ?? "")").estilo(.texto14).foregroundStyle(C.texto2)
        VStack(spacing: 0) {
            renglon { Text("Alquiler"); Spacer(); Text(Formato.numero(Int(item.esperado.rounded()))).fontWeight(.semibold) }
            renglon {
                Text("Expensas ordinarias")
                Spacer()
                TextField("Sumar", value: $expensas, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                    .accessibilityLabel("Expensas ordinarias")
            }
            if punitorios > 0 {
                Button { conPunitorios.toggle() } label: {
                    HStack {
                        Image(systemName: conPunitorios ? "checkmark.square.fill" : "square").foregroundStyle(conPunitorios ? C.accion : C.texto3)
                        Text("Punitorios · \(textoDias) al \(TextosCobro.numero(item.punitorioDiario ?? 0))\u{00A0}%").foregroundStyle(conPunitorios ? C.texto : C.texto3)
                        Spacer()
                        Text(Formato.numero(Int(punitorios))).fontWeight(.semibold).foregroundStyle(conPunitorios ? C.texto : C.texto3).strikethrough(!conPunitorios)
                    }
                    .estilo(.subhead).padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                .accessibilityAddTraits(conPunitorios ? .isSelected : [])
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
            ForEach($otros) { $o in
                renglon {
                    TextField("Concepto", text: $o.concepto).onChange(of: o.concepto) { _, t in if t.count > 80 { o.concepto = String(t.prefix(80)) } }
                    TextField("0", value: $o.monto, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                        .accessibilityLabel("Monto de \(o.concepto.isEmpty ? "el concepto" : o.concepto)")
                    Button { otros.removeAll { $0.id == o.id } } label: { Image(systemName: "xmark").foregroundStyle(C.texto3) }.accessibilityLabel("Sacar el concepto")
                }
            }
            Button { otros.append(Otro()) } label: {
                Label("Otro concepto", systemImage: "plus").estilo(.subheadFuerte).foregroundStyle(C.accion)
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(Presionable()).disabled(otros.count >= 9)
            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            filaTotal
        }
        .background(C.hundida.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        Segmentado(opciones: [("transferencia", "Transferencia"), ("efectivo", "Efectivo"), ("mercadopago", "Mercado Pago")], elegido: $medio)
        HStack {
            Text("Pagó el").foregroundStyle(C.texto2)
            Spacer()
            DatePicker("", selection: $fecha, in: ...Date(), displayedComponents: .date).labelsHidden()
        }
        .estilo(.subhead).padding(.horizontal, 4)
        Button { registrar() } label: {
            Label("Registrar \(Formato.plata(monto, item.moneda))", systemImage: "dollarsign.circle")
        }
        .buttonStyle(BotonPrincipal()).disabled(monto <= 0)
        Text("¿Pagó una parte? Tocá el total y escribí lo que\u{00A0}pagó.").estilo(.footnote).foregroundStyle(C.texto2).frame(maxWidth: .infinity)
    }

    private func renglon<V: View>(@ViewBuilder _ c: () -> V) -> some View {
        HStack { c() }
            .estilo(.subhead).foregroundStyle(C.texto)
            .padding(.horizontal, 14).frame(minHeight: 48)
            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    @ViewBuilder private var filaTotal: some View {
        HStack {
            Text(parcial ? "Pagó" : "Total").bold()
            Spacer()
            if editando {
                Text(item.moneda).foregroundStyle(C.texto2)
                TextField("", value: $total, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 160)
                    .focused($enTotal).accessibilityLabel("Lo que pagó")
            } else {
                Button { total = total ?? suma; editando = true; enTotal = true } label: {
                    Text(Formato.plata(monto, item.moneda)).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.texto)
                }
                .accessibilityLabel("Cambiar el total: \(Formato.plata(monto, item.moneda))")
            }
        }
        .estilo(.headline).foregroundStyle(C.texto)
        .padding(.horizontal, 14).frame(minHeight: 56)
        .overlay(alignment: .top) { Rectangle().fill(C.linea2).frame(height: 1) }
    }

    private func registrar() {
        guard monto > 0 else { return }
        let desglose = parcial || conceptos.count < 2 ? [] : conceptos
        let soloMonto: Double? = parcial || (conceptos.count < 2 && total != nil) ? monto : nil
        registradoEn = Date()
        // Paso 2 al toque; el cobro llega por detrás.
        cobro = Cobro(id: "", periodo: item.periodo, monto: monto, moneda: item.moneda, medio: medio, compartido: false, conceptos: desglose)
        let pagado = Formato.diaISO(fecha) == hoy ? nil : Formato.diaISO(fecha)
        let id = "\(item.contratoId)|\(item.periodo.prefix(7))"
        Cobrar.registrar(estado, item, monto: soloMonto, medio: medio, conceptos: desglose, pagadoEl: pagado,
                         ocultar: { ocultar?(id) },
                         mostrar: { mostrar?(id); cerrar() },
                         alListo: { c in
                             cobro = c
                             Task { await prepararLink(c) }
                         })
    }

    private func prepararLink(_ c: Cobro) async {
        guard !c.id.isEmpty else { return }
        do {
            let u = try await LinksRecibo.de(estado.api, contrato: item.contratoId, cobro: c.id)
            url = u
            texto = TextosCobro.recibo(nombre: item.nombre, periodo: c.periodo, url: u)
        } catch {
            estado.avisar("No pudimos armar el link del recibo. Probá de nuevo.", ok: false)
        }
    }

    // MARK: 2. El recibo

    @ViewBuilder private func reciboListo(_ c: Cobro) -> some View {
        ReciboPapel(cobro: c, nombre: item.nombre, propiedad: item.propiedad, inmobiliaria: inmo?.nombre ?? "", cuando: registradoEn)
        if let url {
            MensajeWhatsApp(contactoId: item.contactoId, telefono: item.telefono, nombre: item.nombre, texto: $texto, para: "recibo",
                            parametros: [n, TextosCobro.nombreMes(c.periodo), Formato.plata(c.monto, c.moneda), url],
                            listo: "Quedó en la ficha de \(n) y del contrato.", enviado: $enviado, alListo: { estado.version += 1; cerrar() }) {
                HStack(spacing: 8) {
                    Button("Copiar link") {
                        UIPasteboard.general.string = url
                        estado.avisar("Link copiado. Pegalo donde quieras mandarlo.")
                    }
                    .buttonStyle(BotonHundido())
                    if let u = URL(string: url + "?imprimir=1") { Link("PDF", destination: u).buttonStyle(BotonHundido()) }
                }
            }
        } else {
            HStack(spacing: 8) { ProgressView(); Text("Armando el link del recibo…").estilo(.footnote).foregroundStyle(C.texto2) }
        }
    }
}

/// El recibo en papel: membrete, «Recibí de X», el importe, «Alquiler y expensas de <mes> ·
/// propiedad · medio», el sello PAGADO y cuándo.
struct ReciboPapel: View {
    var cobro: Cobro
    var nombre: String?
    var propiedad: String?
    var inmobiliaria: String
    var cuando: Date?

    private var concepto: String {
        let conExpensas = (cobro.conceptos ?? []).contains { $0.concepto.lowercased().hasPrefix("expensas") }
        var t = "\(conExpensas ? "Alquiler y expensas" : "Alquiler") de \(TextosCobro.nombreMes(cobro.periodo)) · \(propiedad ?? "")"
        if let m = cobro.medio { t += "\u{00A0}· \(ReciboVista.medioNombre(m).lowercased())" }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(inmobiliaria.prefix(1)).uppercased()).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                    .foregroundStyle(Color(hex: 0xE9DCC3)).frame(width: 36, height: 36).background(Color(hex: 0x1E3A5F), in: Circle())
                Text(inmobiliaria).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(Color(hex: 0x1E3A5F))
                Spacer()
                if let n = cobro.numero { Text(String(format: "0001-%05d", n)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(Color(hex: 0x6B6457)) }
            }
            Rectangle().fill(Color(hex: 0xE3DDCF)).frame(height: 1)
            Text("Recibí de \(nombre ?? "")").estilo(.footnote).foregroundStyle(Color(hex: 0x6B6457))
            Text(Formato.plata(cobro.monto, cobro.moneda)).font(Estilo(tamano: 30, peso: .bold, tracking: -0.03, relativo: .largeTitle).font)
            Text(Formato.sinViudas(concepto)).estilo(.texto14).foregroundStyle(Color(hex: 0x4D5853))
            if let l = cobro.conceptos, l.count > 1 {
                VStack(spacing: 4) {
                    ForEach(l, id: \.self) { x in HStack { Text(x.concepto); Spacer(); Text(Formato.plata(x.monto, cobro.moneda)) }.estilo(.footnote) }
                }
            }
            HStack {
                Text(cuando.map { "\(Self.dia($0)) · \(Formato.horaDe($0))" } ?? cobro.pagadoEl.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "")
                    .font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(Color(hex: 0x6B6457))
                Spacer()
                Text("PAGADO").font(Estilo(tamano: 15, peso: .extrabold, relativo: .subheadline).font).tracking(2).foregroundStyle(Color(hex: 0x2F9E6F))
                    .padding(.horizontal, 10).padding(.vertical, 4).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x2F9E6F), lineWidth: 2))
                    .rotationEffect(.degrees(-6)).accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color(hex: 0x18201D))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFAF8F3), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: 0xE3DDCF)))
    }

    /// «jueves 12/11».
    static func dia(_ f: Date) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "es_AR")
        d.dateFormat = "EEEE dd/MM"
        return d.string(from: f)
    }
}

// MARK: - 10D Recibo

/// 10D El recibo de un cobro ya registrado (desde avisos, la ficha o lo cobrado): el papel, el
/// mensaje para mandarlo por WhatsApp con el link, «Copiar link» y «PDF».
struct ReciboVista: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var contrato: String
    var cobro: String
    var enHoja = false
    @State private var c: Cobro?
    @State private var k: ContratoAPI?
    @State private var inmo: Inmobiliaria?
    @State private var url: String?
    @State private var texto = ""
    @State private var enviado = false
    @State private var previo: ArchivoPrevio?
    @State private var noEsta = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c {
                    ReciboPapel(cobro: c, nombre: k?.contactoNombre, propiedad: k?.propiedadTitulo, inmobiliaria: inmo?.nombre ?? "", cuando: nil)
                    if let url {
                        MensajeWhatsApp(contactoId: k?.contactoId, telefono: nil, nombre: k?.contactoNombre, texto: $texto, para: "recibo",
                                        parametros: [TextosCobro.primerNombre(k?.contactoNombre), TextosCobro.nombreMes(c.periodo), Formato.plata(c.monto, c.moneda), url],
                                        listo: "Quedó en la ficha de \(TextosCobro.primerNombre(k?.contactoNombre)) y del contrato.", enviado: $enviado,
                                        alListo: { estado.version += 1; if enHoja { cerrar() } else { enviado = false } }) {
                            HStack(spacing: 8) {
                                Button("Copiar link") {
                                    UIPasteboard.general.string = url
                                    estado.avisar("Link copiado. Pegalo donde quieras mandarlo.")
                                }
                                .buttonStyle(BotonHundido())
                                if let u = URL(string: url + "?imprimir=1") { Link("PDF", destination: u).buttonStyle(BotonHundido()) }
                            }
                        }
                    } else if estado.escribe {
                        Button { Task { await armarLink(c) } } label: { Label("Mandar por WhatsApp", systemImage: "bubble.left.fill") }.buttonStyle(BotonPrincipal())
                    }
                    Button { Task { if let u = await Documentos.recibo(c, contrato: k, api: estado.api) { previo = ArchivoPrevio(url: u) } } } label: {
                        Label("Imprimir en el teléfono", systemImage: "printer")
                    }
                    .buttonStyle(BotonTexto())
                } else if noEsta {
                    EstadoVacio(icono: "doc.text", titulo: "Ese recibo ya no está", texto: "El cobro se deshizo o se borró.",
                                accion: ("Ver el contrato", { estado.abrir(AFichaContrato(id: contrato)) }))
                } else { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
            }
            .padding(16)
        }
        .background(C.superficie)
        .navigationTitle("Recibo listo").navigationBarTitleDisplayMode(.inline)
        .onAppear { PantallasMostradas.cuenta += 1 }
        .vistaPrevia($previo)
        .toolbar { if enHoja { Button("Listo") { cerrar() } } }
        .task {
            let l: [MesContrato] = (try? await estado.api.get("/v1/contratos/\(contrato)/cobros")) ?? []
            c = l.compactMap(\.cobro).first { $0.id == cobro }
            noEsta = c == nil
            k = try? await estado.api.get("/v1/contratos/\(contrato)")
            inmo = await Documentos.inmobiliaria(estado.api)
        }
    }

    /// El link se pide una sola vez por cobro (uno nuevo invalida el anterior).
    private func armarLink(_ c: Cobro) async {
        do {
            let u = try await LinksRecibo.de(estado.api, contrato: contrato, cobro: c.id)
            url = u
            texto = TextosCobro.recibo(nombre: k?.contactoNombre, periodo: c.periodo, url: u)
        } catch { estado.avisar(error) }
    }

    static func medioNombre(_ m: String) -> String {
        ["transferencia": "Transferencia", "efectivo": "Efectivo", "mercadopago": "Mercado Pago"][m] ?? m
    }

    static func medioTexto(_ m: String) -> String {
        ["transferencia": "transferencia", "efectivo": "efectivo", "mercadopago": "Mercado Pago"][m] ?? m
    }

    static func mes(_ p: String) -> String {
        guard let d = Fecha.dia(String(p.prefix(7)) + "-01") else { return p }
        return "\(Formato.mesDe(d)) \(Calendar.current.component(.year, from: d))"
    }
}
