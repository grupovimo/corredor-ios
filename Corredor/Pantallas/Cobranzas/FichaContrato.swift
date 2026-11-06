import Charts
import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers

/// GET /v1/contratos/{id}/ajuste: el alquiler de hoy (`vigente`), el próximo ajuste, el cronograma y a
/// quién ya se le avisó (parte → cuándo).
struct AjusteContrato: Codable, Hashable {
    struct Proximo: Codable, Hashable { var fecha: String; var monto: Double? }
    struct Paso: Codable, Hashable { var fecha: String; var monto: Double?; var factor: Double?; var futuro: Bool?; var estimado: Bool? }
    var indice: String?
    var base: Double?
    var vigente: Double?
    var vigenteEstimado: Bool?
    var ultimoAjuste: String?
    var proximo: Proximo?
    var cronograma: [Paso]?
    var faltanDatos: Bool?
    var indiceUltimoPeriodo: String?
    var avisos: [String: Date]?
}

/// Un documento del contrato (GET /v1/documentos?contrato=).
struct DocumentoContrato: Codable, Identifiable, Hashable {
    var id: String
    var archivoId: String?
    var nombre: String
    var tipo: String?
    var bytes: Int?
    var creadoEn: Date?
}

/// La ficha de un contrato (22E): el plazo, el próximo ajuste calculado y explicado, el historial de
/// ajustes, los cobros de los últimos meses (con recordar, cobrar, rendir y el recibo), las partes,
/// las condiciones y los documentos.
struct FichaContrato: View {
    @Environment(Estado.self) private var estado
    var id: String
    /// «AAAA-MM»: abre el recordatorio de ese mes (el centro de avisos manda acá).
    var recordar: String? = nil
    @State private var k: ContratoAPI?
    @State private var meses: [MesContrato] = []
    @State private var rendiciones: [RendicionAPI] = []
    @State private var ajuste: AjusteContrato?
    @State private var serie: [Punto] = []
    @State private var documentos: [DocumentoContrato] = []
    @State private var sacados: Set<String> = []
    @State private var inquilino: Persona?
    @State private var propietario: Persona?
    @State private var cobrando: ACobrar?
    @State private var mensaje: PedidoMensaje?
    @State private var previo: ArchivoPrevio?
    @State private var renovando = false
    @State private var error: ErrorApi?
    @State private var recordado = false
    @State private var rindiendo: String?
    @State private var subiendo = false
    @State private var eligiendoArchivo = false
    @State private var foto: PhotosPickerItem?

    struct Persona: Codable, Hashable { var id: String; var nombre: String?; var telefono: String? }
    struct Punto: Codable, Hashable { var periodo: String; var valor: Double }

    private var hoy: String { Formato.diaISO(Date()) }
    private var moneda: String { k?.moneda ?? "ARS" }
    private var ultimos: [MesContrato] { Array(meses.suffix(6).reversed()) }
    private var debe: [MesContrato] { meses.filter { $0.estado == "atrasado" } }
    private var nInq: String { TextosCobro.primerNombre(inquilino?.nombre ?? k?.contactoNombre) }
    private var nProp: String { TextosCobro.primerNombre(propietario?.nombre ?? k?.propietarioNombre) }

    var body: some View {
        ScrollView {
            if let k {
                VStack(alignment: .leading, spacing: 16) {
                    if estado.escribe { TipView(ConsejoCobrar()).tipBackground(C.superficie) }
                    cabecera(k)
                    if let a = ajuste, let p = a.proximo { tarjetaAjuste(k, a, p) }
                    if let a = ajuste, !(a.cronograma ?? []).isEmpty { historial(k, a) }
                    if k.tipo == "alquiler" { bloqueCobros(k) }
                    partes(k)
                    condiciones(k)
                    bloqueDocumentos
                    if k.tipo != "venta" && !rendiciones.isEmpty { bloqueRendiciones }
                    otrasAcciones(k)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else if let error {
                EstadoError(que: "el contrato", error: error) { Task { await cargar() } }.padding(.top, 40)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("Contrato")
        .sheet(isPresented: $renovando) { AltaContrato(renovar: id) }
        .vistaPrevia($previo)
        .task(id: estado.version) { await cargar() }
        .sheet(item: $cobrando) { c in HojaCobro(item: c) }
        .hojaMensaje($mensaje)
        .fileImporter(isPresented: $eligiendoArchivo, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { r in
            if case .success(let us) = r { Task { for u in us { await subirArchivo(u) } } }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) {
                    await subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "Foto \(Formato.diaISO(Date())).jpg", tipo: "image/jpeg")
                }
                foto = nil
            }
        }
    }

    // MARK: Cabecera

    private func plazo(_ k: ContratoAPI) -> String {
        let ini = k.inicio ?? ""
        let fmt: (String) -> String = { "\(TextosCobro.fechaCortita($0))/\($0.prefix(4))" }
        var p = [k.tipo == "alquiler" ? "Alquiler" : "Venta"]
        if let fin = k.fin {
            p.append("\(AltaContrato.mesesEntre(ini, fin)) meses")
            p.append("del \(fmt(ini)) al \(fmt(fin))")
        } else {
            p.append("desde el \(fmt(ini))")
        }
        return p.joined(separator: " · ")
    }

    private func cabecera(_ k: ContratoAPI) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plazo(k)).estilo(.footnote).foregroundStyle(C.texto2)
                Text(k.propiedadTitulo ?? "Contrato sin propiedad").estilo(.titulo).foregroundStyle(C.texto)
            }
            if estado.escribe {
                HStack(spacing: 8) {
                    if k.tipo == "alquiler" {
                        Button { cobrar(nil) } label: { Label("Registrar cobro", systemImage: "dollarsign.circle") }.buttonStyle(BotonHundido())
                    }
                    Button { renovando = true } label: { Label("Renovar", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(BotonHundido())
                }
            }
        }
    }

    // MARK: Próximo ajuste

    private func tarjetaAjuste(_ k: ContratoAPI, _ a: AjusteContrato, _ p: AjusteContrato.Proximo) -> some View {
        let dias = Cobranzas.diasEntre(hoy, p.fecha)
        let cuando = dias <= 0 ? "hoy" : dias == 1 ? "mañana" : "en \(dias) días"
        let vigente = a.vigente ?? k.monto ?? 0
        let sube = (p.monto ?? 0) > 0 && vigente > 0 ? (p.monto! / vigente - 1) : 0
        return VStack(alignment: .leading, spacing: 12) {
            Label("Próximo ajuste · \(cuando) · \(Fecha.dia(p.fecha).map { Formato.diaCompleto($0) } ?? p.fecha)", systemImage: "chart.line.uptrend.xyaxis")
                .estilo(.footnoteFuerte).foregroundStyle(C.oro)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoy").estilo(.caption).foregroundStyle(Color(hex: 0xCFE0D8))
                    Text(Formato.plata(vigente, moneda)).estilo(.subheadFuerte).foregroundStyle(.white)
                }
                Image(systemName: "arrow.right").font(.system(size: 20, weight: .bold)).foregroundStyle(C.oro)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desde \(TextosCobro.nombreMes(p.fecha))").estilo(.caption).foregroundStyle(Color(hex: 0xCFE0D8))
                    Text(p.monto.map { Formato.plata($0, moneda) } ?? "a calcular").estilo(.titulo3).foregroundStyle(C.oro)
                }
                Spacer()
                if p.monto != nil { Text("+\(Self.dec(sube * 100, 1))\u{00A0}%").estilo(.subheadFuerte).foregroundStyle(.white) }
            }
            explicacion(k, a, p)
            if estado.escribe, p.monto != nil {
                VStack(spacing: 8) {
                    if k.contactoId != nil {
                        Button { avisarAjuste("inquilino") } label: { Label("Avisarle a \(nInq.isEmpty ? "el inquilino" : nInq)", systemImage: "bubble.left.fill") }
                            .buttonStyle(BotonPrincipal())
                    }
                    if k.propietarioId != nil {
                        Button { avisarAjuste("propietario") } label: { Text("Avisar a \(nProp.isEmpty ? "el propietario" : nProp)") }
                            .font(Estilo.subheadFuerte.font).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.5)))
                    }
                }
            }
            avisados
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ZStack { C.verde800; Image("GranoClaro").resizable(resizingMode: .tile) } }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
    }

    /// «Cómo se calcula.» (ICL y UVA: el coeficiente del día; IPC: la inflación acumulada; fijo).
    @ViewBuilder private func explicacion(_ k: ContratoAPI, _ a: AjusteContrato, _ p: AjusteContrato.Proximo) -> some View {
        let vigente = a.vigente ?? k.monto ?? 0
        if let m = p.monto, vigente > 0, let indice = k.ajusteIndice {
            let desde = a.ultimoAjuste ?? k.inicio ?? ""
            let factor = m / vigente
            let nombre = TextosCobro.nombreIndice[indice] ?? ""
            let cuenta = "\(Formato.plata(vigente, moneda)) × \(Self.dec(factor, 3))."
            VStack(alignment: .leading, spacing: 6) {
                if indice == "fijo" {
                    (Text("Cómo se calcula. ").bold() + Text("Aumento fijo del \(TextosCobro.numero(k.ajustePorcentaje ?? 0))\u{00A0}% \(k.indiceCada.components(separatedBy: "fijo ").last ?? ""). \(cuenta)"))
                } else if indice == "ipc" {
                    (Text("Cómo se calcula. ").bold() + Text("IPC acumulado de \(TextosCobro.nombreMes(desde)) a \(TextosCobro.nombreMes(p.fecha)) = \(Self.dec(factor, 3)). \(cuenta)"))
                    if (a.cronograma ?? []).last?.estimado == true { notaEstimado(indice) }
                } else if let v0 = Self.valorEn(serie, desde), let v1 = Self.valorEn(serie, p.fecha) {
                    let estimado = v1.periodo < p.fecha
                    (Text("Cómo se calcula. ").bold() + Text("\(nombre) del \(TextosCobro.fechaCortita(p.fecha)) (\(estimado ? "estimado " : "")\(Self.dec(v1.valor))) dividido el \(nombre) del \(TextosCobro.fechaCortita(desde)) (\(Self.dec(v0.valor))) = \(Self.dec(factor, 3)). \(cuenta)"))
                    if estimado { notaEstimado(indice) }
                }
            }
            .estilo(.footnote).foregroundStyle(Color(hex: 0xE8EFE9))
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        } else if a.faltanDatos == true {
            Text("Todavía no salió el dato del índice para calcularlo. Te avisamos cuando se publique.").estilo(.footnote).foregroundStyle(Color(hex: 0xE8EFE9))
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        }
    }

    private func notaEstimado(_ indice: String) -> some View {
        Text("El valor final se confirma cuando \(indice == "ipc" ? "el INDEC publique el IPC del mes" : "el BCRA publique el índice del día"); si cambia, te\u{00A0}avisamos.")
            .foregroundStyle(Color(hex: 0xCFE0D8))
    }

    @ViewBuilder private var avisados: some View {
        let av = ajuste?.avisos ?? [:]
        let ya: [String] = [av["inquilino"].map { "\(nInq.isEmpty ? "El inquilino" : nInq) el \(Self.cortita($0))" },
                            av["propietario"].map { "\(nProp.isEmpty ? "el propietario" : nProp) el \(Self.cortita($0))" }].compactMap { $0 }
        if !ya.isEmpty {
            Label(Formato.mayuscula(ya.joined(separator: " y ")) + " ya \(ya.count == 2 ? "saben" : "sabe") del\u{00A0}ajuste.", systemImage: "checkmark.circle")
                .estilo(.footnote).foregroundStyle(Color(hex: 0x9FD6C2))
        }
    }

    // MARK: Historial de ajustes

    struct Barra: Identifiable {
        var fecha: String
        var monto: Double
        var futuro: Bool
        var hoy: Bool
        var opacidad: Double
        var id: String { fecha }
        var etiqueta: String { FichaContrato.mesBarra(fecha) + (hoy ? " · hoy" : futuro ? " · estimado" : "") }
    }

    private func barras(_ k: ContratoAPI, _ a: AjusteContrato) -> [Barra] {
        var pasos: [(String, Double?, Bool)] = [(k.inicio ?? "", a.base ?? k.monto, false)]
        pasos += (a.cronograma ?? []).map { ($0.fecha, $0.monto, $0.futuro == true) }
        let ultimos = Array(pasos.filter { $0.1 != nil }.suffix(6))
        let vigente = ultimos.lastIndex { !$0.2 } ?? -1
        let tonos: [Double] = [0.18, 0.3, 0.45, 0.62, 0.8, 1]
        return ultimos.enumerated().map { i, p in
            let t = tonos.count - ultimos.count + i
            return Barra(fecha: p.0, monto: p.1 ?? 0, futuro: p.2, hoy: i == vigente, opacidad: t >= 0 && t < tonos.count ? tonos[t] : tonos[0])
        }
    }

    private func historial(_ k: ContratoAPI, _ a: AjusteContrato) -> some View {
        let bs = barras(k, a)
        let desdeInicio = (a.base ?? 0) > 0 ? ((a.vigente ?? 0) / (a.base ?? 1) - 1) * 100 : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TituloBloque(texto: "Historial de ajustes · \(k.indiceCada)")
                Spacer()
                Text("\(desdeInicio >= 0 ? "+" : "")\(Int(desdeInicio.rounded()))\u{00A0}% desde el inicio").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Chart(bs) { b in
                BarMark(x: .value("Mes", b.etiqueta), y: .value("Monto", b.monto))
                    .foregroundStyle(b.futuro ? C.oro : C.accion.opacity(b.opacidad))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text(Formato.numero(Int(b.monto.rounded()))).font(Estilo(tamano: 10, peso: .semibold, relativo: .caption2).font).foregroundStyle(b.futuro ? C.oroTinta : C.texto2)
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(Estilo(tamano: 10, peso: .regular, relativo: .caption2).font) }
            }
            .frame(height: 170)
            .padding(14)
            .tarjeta()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Cobros mes a mes

    private func bloqueCobros(_ k: ContratoAPI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloBloque(texto: "Cobros")
                Spacer()
                Button("Ver cobranzas") { estado.abrir(ACobranzas()) }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
            }
            VStack(spacing: 0) {
                ForEach(Array(ultimos.enumerated()), id: \.element.periodo) { i, m in filaMes(k, m, primera: i == 0) }
                if ultimos.isEmpty { Text("Todavía no hay cobros.").estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .tarjeta()
        }
    }

    private static let estadoRendicion = ["pendiente": "para revisar", "liquidada": "emitida", "pagada": "transferida"]

    private func detalleMes(_ k: ContratoAPI, _ m: MesContrato, _ r: RendicionAPI?) -> String {
        if let c = m.cobro {
            return "Pagó el \(TextosCobro.fechaCortita(c.pagadoEl ?? ""))" + (r.map { "\u{00A0}· rendición \(Self.estadoRendicion[$0.estado ?? ""] ?? "")" } ?? "")
        }
        switch m.estado {
        case "atrasado": return "Venció el \(TextosCobro.fechaCortita(m.vence ?? ""))"
        case "sin_registro": return k.estado == "rescindido" ? "Sin cobro registrado" : "Sin cobro registrado · de antes de\u{00A0}Corredor"
        default: return "Vence el \(TextosCobro.fechaCortita(m.vence ?? ""))"
        }
    }

    private func filaMes(_ k: ContratoAPI, _ m: MesContrato, primera: Bool) -> some View {
        let r = rendiciones.first { $0.periodo.prefix(7) == m.periodo.prefix(7) }
        let (icono, color): (String, Color) = {
            switch m.estado {
            case "cobrado": return ("checkmark.circle.fill", Color(hex: 0x2F9E6F))
            case "atrasado": return ("exclamationmark.circle", C.error)
            case "sin_registro": return ("clock.arrow.circlepath", C.texto2)
            default: return ("clock", C.oroTinta)
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: icono).font(.system(size: 20)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(Formato.mayuscula(TextosCobro.nombreMes(m.periodo))).estilo(.filaLista).foregroundStyle(C.texto)
                Text(detalleMes(k, m, r)).estilo(.footnote).foregroundStyle(m.estado == "atrasado" ? C.errorTinta : C.texto2).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(Formato.numero(Int((m.cobro?.monto ?? m.esperado ?? 0).rounded()))).estilo(.subheadFuerte).foregroundStyle(C.texto)
            accionesMes(k, m, r)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    @ViewBuilder private func accionesMes(_ k: ContratoAPI, _ m: MesContrato, _ r: RendicionAPI?) -> some View {
        if let c = m.cobro {
            Menu {
                if let r {
                    Button { estado.abrir(ARendicion(contrato: id, id: r.id)) } label: { Label("Rendición", systemImage: "doc.plaintext") }
                } else if estado.escribe {
                    Button { Task { await rendir(m.periodo) } } label: { Label("Rendir", systemImage: "doc.plaintext") }
                }
                if c.compartido == true {
                    Button { estado.abrir(ARecibo(contrato: id, cobro: c.id)) } label: { Label("Recibo enviado", systemImage: "checkmark.circle") }
                } else {
                    Button { cobrando = aCobrar(m, cobro: c) } label: { Label("Recibo", systemImage: "doc.text") }
                }
            } label: {
                HStack(spacing: 4) {
                    if rindiendo == m.periodo { ProgressView() }
                    if c.compartido == true { Image(systemName: "checkmark.circle").foregroundStyle(C.azulTinta).accessibilityLabel("Recibo enviado") }
                    Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(C.texto2)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Recibo y rendición de \(TextosCobro.nombreMes(m.periodo))")
        } else if estado.escribe {
            HStack(spacing: 2) {
                if k.contactoId != nil && m.estado != "sin_registro" {
                    Button { recordarMes(String(m.periodo.prefix(7))) } label: { Image(systemName: "bubble.left").font(.system(size: 18)).foregroundStyle(C.texto2).frame(width: 40, height: 44) }
                        .accessibilityLabel("Recordar por WhatsApp")
                }
                Button("Cobrado") { cobrar(m) }
                    .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                    .padding(.horizontal, 10).frame(height: 32).background(C.hundida, in: Capsule())
                    .buttonStyle(Presionable())
            }
        }
    }

    // MARK: Partes

    private func partes(_ k: ContratoAPI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Partes")
            VStack(spacing: 0) {
                if let n = k.contactoNombre {
                    let que = debe.isEmpty ? "" : "\u{00A0}· debe \(debe.count > 1 ? "\(debe.count) meses" : TextosCobro.nombreMes(debe.last?.periodo ?? ""))"
                    parte(n, (k.tipo == "venta" ? "Comprador" : "Inquilino") + que, rojo: !debe.isEmpty, primera: true, contacto: k.contactoId) {
                        if let c = k.contactoId { chat(c, telefono: inquilino?.telefono) }
                    }
                }
                if let n = k.propietarioNombre {
                    let ult = rendiciones.first.map { "\u{00A0}· última rendición, \(TextosCobro.nombreMes($0.periodo))" } ?? ""
                    parte(n, "Propietario" + ult, rojo: false, primera: k.contactoNombre == nil, contacto: k.propietarioId) {
                        if let c = k.propietarioId { chat(c, telefono: propietario?.telefono) }
                    }
                }
                if let n = k.garanteNombre {
                    parte(n, "Garante" + (k.garanteNotas.map { "\u{00A0}· \($0)" } ?? ""), rojo: false, primera: k.contactoNombre == nil && k.propietarioNombre == nil,
                          contacto: nil, icono: k.garanteTelefono == nil ? nil : "phone") { Afuera.llamar(k.garanteTelefono) }
                }
                if k.contactoNombre == nil && k.propietarioNombre == nil && k.garanteNombre == nil {
                    Text("Este contrato todavía no tiene partes cargadas.").estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tarjeta()
        }
    }

    private func parte(_ nombre: String, _ detalle: String, rojo: Bool, primera: Bool, contacto: String?, icono: String? = "bubble.left", _ accion: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button { if let contacto { estado.abrir(AFichaContacto(id: contacto)) } } label: {
                HStack(spacing: 10) {
                    AvatarIniciales(nombre: nombre, tam: 36, fondo: rojo ? C.errorFondo : C.crema, tinta: rojo ? C.errorTinta : C.primarioTexto)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nombre).estilo(.filaLista).foregroundStyle(C.texto)
                        Text(detalle).estilo(.footnote).foregroundStyle(rojo ? C.errorTinta : C.texto2).fontWeight(rojo ? .semibold : .regular).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable()).disabled(contacto == nil)
            if let icono {
                Button(action: accion) { Image(systemName: icono).font(.system(size: 18)).foregroundStyle(C.accion).frame(width: 44, height: 44) }
                    .accessibilityLabel(icono == "phone" ? "Llamar a \(nombre)" : "WhatsApp con \(nombre)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    /// El chat de WhatsApp con la parte (en la bandeja de Corredor; sin número conectado, el teléfono).
    private func chat(_ contacto: String, telefono: String?) {
        Task {
            struct Cuerpo: Encodable { var contactoId: String }
            struct Conv: Decodable { var id: String }
            do {
                let x: Conv = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: contacto))
                estado.abrir(AChat(id: x.id))
            } catch {
                if let telefono { Afuera.whatsapp(telefono) } else { estado.avisar(error) }
            }
        }
    }

    // MARK: Condiciones

    private func condiciones(_ k: ContratoAPI) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Condiciones")
            VStack(spacing: 0) {
                if k.tipo == "alquiler" {
                    dato("Vence el pago", "día \(k.diaVencimiento ?? 1) de cada mes", primera: true)
                    if let p = k.punitorioDiario, p > 0 { dato("Punitorios", "\(TextosCobro.numero(p))\u{00A0}% diario") }
                    dato("Ajuste", k.indiceCada)
                }
                dato(k.tipo == "alquiler" ? "Alquiler inicial" : "Monto", k.monto.map { Formato.plata($0, moneda) } ?? "—", primera: k.tipo != "alquiler")
                if let d = k.deposito, d > 0 {
                    let meses = (k.monto ?? 0) > 0 ? "\u{00A0}(\(TextosCobro.numero((d / (k.monto ?? 1) * 10).rounded() / 10))\u{00A0}\(d == k.monto ? "mes" : "meses"))" : ""
                    dato("Depósito", Formato.plata(d, moneda) + meses)
                }
                if let h = k.honorarios, h > 0 { dato("Honorarios", "\(TextosCobro.numero(h))\u{00A0}% del total del\u{00A0}contrato") }
                if let c = k.comision, c > 0 { dato(k.tipo == "alquiler" ? "Administración" : "Comisión", "\(TextosCobro.numero(c))\u{00A0}%\(k.tipo == "alquiler" ? " de lo cobrado" : "")") }
                if let n = k.notas?.nonEmpty { dato("Notas", n) }
            }
            .tarjeta()
        }
    }

    private func dato(_ l: String, _ v: String, primera: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l).foregroundStyle(C.texto2)
            Spacer()
            Text(v).fontWeight(.semibold).foregroundStyle(C.texto).multilineTextAlignment(.trailing)
        }
        .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Documentos

    private var bloqueDocumentos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloBloque(texto: "Documentos")
                Spacer()
                if estado.escribe {
                    Menu {
                        Button { eligiendoArchivo = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                        PhotosPicker(selection: $foto, matching: .images) { Label("Una foto", systemImage: "photo") }
                    } label: { Label("Subir", systemImage: "plus") }.font(Estilo.subheadFuerte.font)
                }
            }
            VStack(spacing: 0) {
                let visibles = documentos.filter { !sacados.contains($0.id) }
                ForEach(Array(visibles.enumerated()), id: \.element.id) { i, d in filaDocumento(d, primera: i == 0) }
                if subiendo { HStack { ProgressView(); Text("Subiendo…").estilo(.footnote).foregroundStyle(C.texto2) }.padding(14) }
                if visibles.isEmpty && !subiendo {
                    Text(estado.escribe ? "Tocá «Subir» para sumar el contrato firmado, el acta o el DNI." : "Sin documentos.").estilo(.texto14).foregroundStyle(C.texto3)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tarjeta()
        }
    }

    private func filaDocumento(_ d: DocumentoContrato, primera: Bool) -> some View {
        HStack(spacing: 12) {
            Button { Task { await abrir(d) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: d.tipo?.contains("pdf") == true ? "doc.richtext" : "photo").foregroundStyle(C.azulTinta).frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                        Text([d.creadoEn.map { Formato.cuando($0) }, d.bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }].compactMap { $0 }.joined(separator: " · "))
                            .estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if estado.escribe {
                Menu {
                    Button { Task { await abrir(d) } } label: { Label("Abrir", systemImage: "arrow.up.right.square") }
                    Button(role: .destructive) { sacar(d) } label: { Label("Sacar", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(C.texto2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Opciones de \(d.nombre)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func abrir(_ d: DocumentoContrato) async {
        guard let a = d.archivoId else { return }
        do {
            let datos = try await estado.api.pedir("GET", "/v1/archivos/\(a)/contenido")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(d.nombre)
            try datos.write(to: u)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    /// Sacar un documento (a la papelera); «Deshacer» lo vuelve a sumar con el mismo archivo.
    private func sacar(_ d: DocumentoContrato) {
        sacados.insert(d.id)
        let pedido = Task<Bool, Never> {
            do { try await estado.api.hacer("DELETE", "/v1/documentos/\(d.id)"); return true } catch {
                sacados.remove(d.id)
                estado.avisar("No se sacó · \((error as? ErrorApi)?.detalle ?? "")", ok: false)
                return false
            }
        }
        estado.avisar("Sacaste «\(d.nombre)»") {
            Task {
                guard await pedido.value, let a = d.archivoId else { return }
                struct C: Encodable { var archivoId: String; var contratoId: String; var nombre: String }
                do { try await estado.api.hacer("POST", "/v1/documentos", C(archivoId: a, contratoId: id, nombre: d.nombre)) } catch { estado.avisar(error) }
                sacados.remove(d.id)
                estado.version += 1
            }
        }
    }

    private func subirArchivo(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u) else { estado.avisar("No se pudo leer el archivo.", ok: false); return }
        await subir(d, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
    }

    private func subir(_ datos: Data, nombre: String, tipo: String) async {
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            struct C: Encodable { var archivoId: String; var contratoId: String; var nombre: String }
            try await estado.api.hacer("POST", "/v1/documentos", C(archivoId: a.id, contratoId: id, nombre: a.nombre ?? nombre))
            estado.version += 1
        } catch { estado.avisar("No se guardó el documento · \((error as? ErrorApi)?.detalle ?? "")", ok: false) }
    }

    // MARK: Rendiciones y lo demás

    private var bloqueRendiciones: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Rendiciones al propietario")
            VStack(spacing: 0) {
                ForEach(Array(rendiciones.enumerated()), id: \.element.id) { i, r in
                    Button { estado.abrir(ARendicion(contrato: id, id: r.id)) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(Formato.mayuscula(ReciboVista.mes(r.periodo))).estilo(.filaLista).foregroundStyle(C.texto)
                                Text(RendicionAPI.estadoTexto(r.estado)).estilo(.footnote).foregroundStyle(r.estado == "pendiente" ? C.avisoTinta : C.texto2)
                            }
                            Spacer()
                            Text(Formato.plata(r.neto ?? 0, r.moneda ?? "ARS")).fontWeight(.semibold).foregroundStyle(C.texto)
                            Chevron()
                        }
                        .estilo(.body16).padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    private func otrasAcciones(_ k: ContratoAPI) -> some View {
        VStack(spacing: 8) {
            if let p = k.propiedadId { Button("Inventario y actas") { estado.abrir(AInventario(id: p)) }.buttonStyle(BotonHundido()) }
            Button("Ver o imprimir el contrato") { Task { if let u = await Documentos.contrato(k, api: estado.api) { previo = ArchivoPrevio(url: u) } } }
                .buttonStyle(BotonHundido())
            if estado.escribe && k.estado != "rescindido" {
                Button("Rescindir") { Task { await rescindir() } }.buttonStyle(BotonTexto(color: C.error))
            }
        }
    }

    // MARK: Acciones

    private func aCobrar(_ m: MesContrato, cobro: Cobro? = nil) -> ACobrar {
        ACobrar(contratoId: id, contactoId: k?.contactoId, nombre: k?.contactoNombre, telefono: inquilino?.telefono, propiedad: k?.propiedadTitulo,
                periodo: m.periodo, esperado: m.cobro?.monto ?? m.esperado ?? 0, moneda: moneda, vence: m.vence ?? m.periodo,
                punitorioDiario: k?.punitorioDiario, cobro: cobro)
    }

    /// Sin mes: la deuda más vieja o el próximo mes pendiente; si no hay nada, «Está todo cobrado».
    private func cobrar(_ m: MesContrato?) {
        guard let mes = m ?? debe.first ?? ultimos.reversed().first(where: { $0.estado == "pendiente" }) else {
            estado.avisar("Está todo cobrado hasta este mes.")
            return
        }
        cobrando = aCobrar(mes)
    }

    private func avisarAjuste(_ parte: String) {
        guard let k, let a = ajuste, let p = a.proximo, let nuevo = p.monto else { return }
        let persona = parte == "inquilino" ? inquilino : propietario
        let nombre = persona?.nombre ?? (parte == "inquilino" ? k.contactoNombre : k.propietarioNombre)
        let n = TextosCobro.primerNombre(nombre)
        let vigente = a.vigente ?? k.monto ?? 0
        mensaje = PedidoMensaje(
            titulo: "Avisarle a \(n.isEmpty ? (parte == "inquilino" ? "el inquilino" : "el propietario") : n)",
            descripcion: "\(k.propiedadTitulo ?? "") · ajusta el \(TextosCobro.fechaCortita(p.fecha))",
            contactoId: persona?.id ?? (parte == "inquilino" ? k.contactoId : k.propietarioId), telefono: persona?.telefono, nombre: nombre,
            texto: TextosCobro.ajuste(nombre: nombre, indice: k.ajusteIndice ?? "", fecha: p.fecha, desde: vigente, hasta: nuevo, moneda: moneda),
            para: "ajuste", parametros: [n, TextosCobro.fechaCortita(p.fecha), Formato.plata(vigente, moneda), Formato.plata(nuevo, moneda)],
            alEnviar: { Task { await anotarAviso(parte) } })
    }

    /// El mensaje salió: queda anotado a quién se le avisó (POST …/ajuste/avisos {parte}).
    private func anotarAviso(_ parte: String) async {
        let antes = ajuste?.avisos
        ajuste?.avisos = (ajuste?.avisos ?? [:]).merging([parte: Date()]) { _, b in b }
        struct Cuerpo: Encodable { var parte: String }
        do {
            try await estado.api.hacer("POST", "/v1/contratos/\(id)/ajuste/avisos", Cuerpo(parte: parte))
        } catch {
            ajuste?.avisos = antes
            estado.sugerir("El mensaje salió, pero no quedó anotado el aviso.", "Reintentar") { Task { await anotarAviso(parte) } }
        }
    }

    private func recordarMes(_ periodo: String) {
        guard let k else { return }
        let m = meses.first { $0.periodo.hasPrefix(periodo) }
        let importe = m?.esperado ?? ajuste?.vigente ?? k.monto ?? 0
        let vence = m?.vence ?? "\(periodo)-\(String(format: "%02d", k.diaVencimiento ?? 1))"
        mensaje = PedidoMensaje(
            titulo: "Recordarle a \(nInq.isEmpty ? "el inquilino" : nInq)",
            descripcion: "\(Formato.mayuscula(TextosCobro.nombreMes(periodo))) · \(k.propiedadTitulo ?? "") · \(Formato.plata(importe, moneda))",
            contactoId: k.contactoId, telefono: inquilino?.telefono, nombre: k.contactoNombre,
            texto: TextosCobro.recordatorio(nombre: k.contactoNombre, periodo: periodo + "-01", importe: importe, moneda: moneda, vence: vence, hoy: hoy),
            para: "recordatorio", parametros: [nInq, TextosCobro.nombreMes(periodo), Formato.plata(importe, moneda), TextosCobro.fechaCortita(vence)],
            listo: "Quedó en la ficha de \(nInq) y en la bandeja.")
    }

    /// Preparar la rendición de un mes cobrado y abrirla para revisarla.
    private func rendir(_ periodo: String) async {
        rindiendo = periodo
        defer { rindiendo = nil }
        struct Cuerpo: Encodable { var periodo: String }
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/contratos/\(id)/rendiciones", Cuerpo(periodo: String(periodo.prefix(7))))
            estado.version += 1
            estado.abrir(ARendicion(contrato: id, id: n.id))
        } catch { estado.avisar(error) }
    }

    private func rescindir() async {
        struct Cuerpo: Encodable { var estado = "rescindido" }
        do {
            try await estado.api.hacer("PATCH", "/v1/contratos/\(id)", Cuerpo())
            estado.version += 1
            estado.avisar("Contrato rescindido") {
                Task {
                    struct Volver: Encodable { var estado = "vigente" }
                    do { try await estado.api.hacer("PATCH", "/v1/contratos/\(id)", Volver()) } catch { estado.avisar(error) }
                    estado.version += 1
                }
            }
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            let c: ContratoAPI = try await estado.api.get("/v1/contratos/\(id)")
            meses = (try? await estado.api.get("/v1/contratos/\(id)/cobros")) ?? []
            rendiciones = (try? await estado.api.get("/v1/contratos/\(id)/rendiciones")) ?? []
            ajuste = try? await estado.api.get("/v1/contratos/\(id)/ajuste")
            documentos = (try? await estado.api.get("/v1/documentos", query: [.init(name: "contrato", value: id)])) ?? []
            sacados = []
            inquilino = c.contactoId == nil ? nil : try? await estado.api.get("/v1/contactos/\(c.contactoId!)")
            propietario = c.propietarioId == nil ? nil : try? await estado.api.get("/v1/contactos/\(c.propietarioId!)")
            if let i = c.ajusteIndice, i != "fijo", let a = ajuste, a.proximo != nil {
                let desde = String((a.ultimoAjuste ?? c.inicio ?? "").prefix(8)) + "01"
                serie = (try? await estado.api.get("/v1/indices/\(i)", query: [.init(name: "desde", value: desde)])) ?? []
            }
            k = c
            error = nil
            if let recordar, !recordado, estado.escribe {
                recordado = true
                recordarMes(String(recordar.prefix(7)))
            }
        } catch let e as ErrorApi { if k == nil { error = e } } catch {}
    }

    // MARK: Formatos

    static func primerNombre(_ n: String?) -> String { TextosCobro.primerNombre(n) }

    /// «15/03».
    static func cortita(_ f: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: f)
        return String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
    }

    /// «1,25» con los decimales justos.
    static func dec(_ n: Double, _ d: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// «2026-12-01» → «dic 26».
    static func mesBarra(_ fecha: String) -> String {
        guard let d = Fecha.dia(fecha) else { return fecha }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "") + " " + fecha.dropFirst(2).prefix(2)
    }

    /// El último valor publicado en o antes de una fecha (como la API: indices.coeficienteEn).
    static func valorEn(_ serie: [Punto], _ f: String) -> Punto? {
        var v: Punto?
        for p in serie {
            if p.periodo > f { break }
            v = p
        }
        return v
    }
}
