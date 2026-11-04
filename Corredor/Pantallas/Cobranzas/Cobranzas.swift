import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Los destinos de Cobranzas, contratos, rendiciones y actas.
    func destinosCobranzas() -> some View {
        self
            .navigationDestination(for: ACobranzas.self) { _ in Cobranzas() }
            .navigationDestination(for: AContratos.self) { _ in Contratos() }
            .navigationDestination(for: AFichaContrato.self) { c in FichaContrato(id: c.id) }
            .navigationDestination(for: ARecibo.self) { r in ReciboVista(contrato: r.contrato, cobro: r.cobro) }
            .navigationDestination(for: ARendicion.self) { r in RendicionVista(contrato: r.contrato, id: r.id) }
            .navigationDestination(for: AInventario.self) { i in Inventario(propiedad: i.id) }
            .navigationDestination(for: AFirmas.self) { f in Firmas(clave: f.id) }
    }
}

/// Una fila de cobranzas del mes (GET /v1/cobranzas).
struct FilaCobranza: Codable, Identifiable, Hashable {
    var contratoId: String
    var propiedadTitulo: String?
    var contactoNombre: String?
    var propietarioNombre: String?
    var agenteId: String?
    var monto: Double
    var moneda: String
    var estimado: Bool?
    var vence: String?
    var estado: String?
    var cobro: Cobro?
    var comision: Double?
    var punitorioDiario: Double?
    var id: String { contratoId }
}

struct Cobro: Codable, Identifiable, Hashable {
    struct Concepto: Codable, Hashable { var concepto: String; var monto: Double }
    var id: String
    var periodo: String
    var monto: Double
    var moneda: String
    var pagadoEl: String?
    var notas: String?
    var medio: String?
    var compartido: Bool?
    var numero: Int?
    var conceptos: [Concepto]?
}

/// Un mes del contrato (GET /v1/contratos/{id}/cobros): lo esperado y, si se cobró, el cobro.
struct MesContrato: Codable, Hashable {
    var periodo: String
    var vence: String?
    var esperado: Double?
    var estimado: Bool?
    var estado: String?
    var cobro: Cobro?
}

struct MesCobranzas: Codable {
    var periodo: String
    var cobradas: [FilaCobranza]
    var pendientes: [FilaCobranza]
    var totalCobrado: [String: Double]?
    var totalPendiente: [String: Double]?
}

// MARK: - 10A–10B Por cobrar

/// 10A–10B Cobranzas del mes: lo que falta cobrar arriba (verde, con la barra), deslizar a la derecha
/// para cobrar y a la izquierda para recordar; lo cobrado hoy abajo, con el recibo listo.
struct Cobranzas: View {
    @Environment(Estado.self) private var estado
    @State private var mes: MesCobranzas?
    @State private var periodo = Date()
    @State private var cobrando: FilaCobranza?
    @State private var recibo: ARecibo?
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let mes {
                    resumen(mes)
                    if mes.pendientes.isEmpty {
                        Label("Cobraste todo \(Formato.mesDe(periodo))", systemImage: "checkmark.seal.fill").estilo(.subheadFuerte).foregroundStyle(C.okTinta)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(C.okFondo, in: .rect(cornerRadius: 18))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(mes.pendientes.sorted { ($0.vence ?? "") < ($1.vence ?? "") }.enumerated()), id: \.element.id) { i, c in
                                filaPendiente(c, primera: i == 0)
                            }
                        }
                        .tarjeta()
                        Text("Deslizá a la derecha para cobrar, a la izquierda para recordar.").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
                    }
                    if !mes.cobradas.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COBRADOS").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(mes.cobradas.enumerated()), id: \.element.id) { i, c in
                                    Button { if let k = c.cobro { recibo = ARecibo(contrato: c.contratoId, cobro: k.id) } } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0x2F9E6F))
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(c.contactoNombre ?? c.propiedadTitulo ?? "").estilo(.filaLista).foregroundStyle(C.texto)
                                                Text(c.cobro?.compartido == true ? "Recibo mandado" : "Recibo listo para mandar").estilo(.footnote).foregroundStyle(C.texto2)
                                            }
                                            Spacer()
                                            Text(Formato.plata(c.cobro?.monto ?? c.monto, c.moneda)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta()
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Contratos") { estado.abrir(AContratos()) }.buttonStyle(BotonHundido())
                        Button("Rendiciones") { estado.abrir(ASeccion(clave: "rendiciones")) }.buttonStyle(BotonHundido())
                    }
                } else if let error {
                    EstadoError(que: "las cobranzas", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Cobranzas")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(-6...0, id: \.self) { d in
                        let f = Calendar.current.date(byAdding: .month, value: d, to: Date())!
                        Button(Formato.mayuscula("\(Formato.mesDe(f)) \(Calendar.current.component(.year, from: f))")) { periodo = f }
                    }
                } label: { Label(Formato.mayuscula(Formato.mesDe(periodo)), systemImage: "calendar") }
            }
        }
        .task(id: "\(estado.version)\(Formato.diaISO(periodo).prefix(7))") { await cargar() }
        .sheet(item: $cobrando) { c in HojaCobro(fila: c) { r in recibo = r }.presentationDetents([.medium]) }
        .sheet(item: Binding(get: { recibo.map { ReciboHoja(r: $0) } }, set: { recibo = $0?.r })) { x in
            NavigationStack { ReciboVista(contrato: x.r.contrato, cobro: x.r.cobro, enHoja: true) }.presentationDetents([.large])
        }
    }

    private func resumen(_ m: MesCobranzas) -> some View {
        let falta = m.totalPendiente?["ARS"] ?? 0
        let cobrado = m.totalCobrado?["ARS"] ?? 0
        let total = falta + cobrado
        return VStack(alignment: .leading, spacing: 6) {
            Text("Falta cobrar").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.oro)
            Text(Formato.plata(falta)).font(Estilo(tamano: 32, peso: .bold, tracking: -0.03, relativo: .largeTitle).font).foregroundStyle(.white)
            if let usd = m.totalPendiente?["USD"], usd > 0 { Text("y \(Formato.plata(usd, "USD"))").estilo(.subhead).foregroundStyle(.white) }
            Text("\(Formato.cantidad(m.pendientes.count, "inquilino", "inquilinos")) · \(total > 0 ? Int((cobrado / total * 100).rounded()) : 100) % cobrado")
                .estilo(.texto14).foregroundStyle(Color(hex: 0xCFE0D8))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(C.oro).frame(width: g.size.width * (total > 0 ? cobrado / total : 1))
                }
            }
            .frame(height: 8).padding(.top, 6)
            .animation(.spring(duration: 0.5), value: cobrado)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ZStack { C.verde800; Image("Patron").resizable(resizingMode: .tile).opacity(0.06); Image("GranoClaro").resizable(resizingMode: .tile) } }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE3()
    }

    private func filaPendiente(_ c: FilaCobranza, primera: Bool) -> some View {
        let (venceTexto, vencido) = Self.vence(c.vence)
        return FilaDeslizable(
            izquierda: estado.escribe ? [AccionFila(texto: "Cobrar", simbolo: "dollarsign.circle", color: Color(hex: 0x2F9E6F)) { cobrando = c }] : [],
            derecha: [AccionFila(texto: "Recordar", simbolo: "bell.badge", color: C.oro) { recordar(c) }], anchoAccion: 112) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.contactoNombre ?? "Inquilino").font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                    (Text("\(c.propiedadTitulo ?? "") · ") + Text(venceTexto).foregroundColor(vencido ? C.error : C.texto2).fontWeight(.semibold))
                        .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer()
                Text(Formato.plata(c.monto, c.moneda)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                Button { recordar(c) } label: { Image(systemName: "bell.badge").font(.system(size: 20)).foregroundStyle(C.texto2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Mandar recordatorio por WhatsApp")
                if estado.escribe {
                    Button { cobrando = c } label: {
                        Text("Cobrar").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.sobreAccion)
                            .padding(.horizontal, 12).frame(height: 34).background(C.accion, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
            .background(C.superficie)
            .contentShape(Rectangle())
            .onTapGesture { estado.abrir(AFichaContrato(id: c.contratoId)) }
        }
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    static func vence(_ s: String?) -> (String, Bool) {
        guard let s, let d = Fecha.dia(s) else { return ("", false) }
        let dias = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d)).day ?? 0
        if dias < 0 { return ("vencido hace \(Formato.cantidad(-dias, "día", "días"))", true) }
        if dias == 0 { return ("vence hoy", true) }
        return ("vence el \(Calendar.current.component(.day, from: d))", false)
    }

    private func recordar(_ c: FilaCobranza) {
        Task {
            struct Ct: Decodable { var telefono: String? }
            struct K: Decodable { var contactoId: String? }
            let k: K? = try? await estado.api.get("/v1/contratos/\(c.contratoId)")
            let x: Ct? = k?.contactoId == nil ? nil : try? await estado.api.get("/v1/contactos/\(k!.contactoId!)")
            let inmo: Inmobiliaria? = try? await estado.api.get("/v1/inmobiliaria")
            let nombre = c.contactoNombre?.split(separator: " ").first.map(String.init) ?? ""
            var t = "Hola \(nombre), te recuerdo el alquiler de \(c.propiedadTitulo ?? "") de \(Formato.mesDe(periodo)): \(Formato.plata(c.monto, c.moneda))."
            if let cbu = inmo?.cbu { t += " Podés transferir a \(cbu)." }
            Afuera.whatsapp(x?.telefono, texto: t)
        }
    }

    private func cargar() async {
        let p = String(Formato.diaISO(periodo).prefix(7))
        do {
            mes = try await estado.api.get("/v1/cobranzas", query: [.init(name: "periodo", value: p)])
            error = nil
        } catch let e as ErrorApi { if mes == nil { error = e } } catch {}
    }
}

struct ReciboHoja: Identifiable { var r: ARecibo; var id: String { r.cobro } }

/// 10C Registrar pago: el monto (con su desglose), el medio y la fecha. Al registrar, el recibo.
struct HojaCobro: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var fila: FilaCobranza
    var alRegistrar: (ARecibo) -> Void
    @State private var medio = "transferencia"
    @State private var monto: Double?
    @State private var fecha = Date()
    @State private var guardando = false
    @State private var listo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Registrar pago").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
                Text("\(fila.contactoNombre ?? "") · \(fila.propiedadTitulo ?? "")").estilo(.texto14).foregroundStyle(C.texto2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Monto").estilo(.footnote).foregroundStyle(C.texto2)
                TextField(Formato.plata(fila.monto, fila.moneda), value: $monto, format: .number)
                    .font(Estilo(tamano: 32, peso: .bold, tracking: -0.03, relativo: .largeTitle).font).keyboardType(.decimalPad)
                Text(fila.estimado == true ? "Con el ajuste estimado (el índice todavía no salió)" : "Alquiler del mes con su ajuste").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(C.hundida, in: .rect(cornerRadius: 16))
            Segmentado(opciones: [("transferencia", "Transferencia"), ("efectivo", "Efectivo"), ("otro", "Otro")], elegido: $medio)
            HStack {
                Text("Fecha").foregroundStyle(C.texto2)
                Spacer()
                DatePicker("", selection: $fecha, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            .estilo(.subhead).padding(.horizontal, 4)
            Button { Task { await registrar() } } label: {
                Text("Registrar pago").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.sobreAccion)
                    .frame(maxWidth: .infinity, minHeight: 54).background(C.accion, in: .rect(cornerRadius: 15, style: .continuous))
            }
            .disabled(guardando)
        }
        .padding(.horizontal, 16).padding(.top, 20)
        .background(C.superficie)
        .sensoryFeedback(.success, trigger: listo)
    }

    private func registrar() async {
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var periodo: String; var monto: Double; var pagadoEl: String; var medio: String }
        struct Nuevo: Decodable { var id: String }
        let p = String((fila.vence ?? Formato.diaISO(Date())).prefix(7))
        do {
            let n: Nuevo = try await estado.api.enviar("POST", "/v1/contratos/\(fila.contratoId)/cobros",
                                                        Cuerpo(periodo: p, monto: monto ?? fila.monto, pagadoEl: Formato.diaISO(fecha), medio: medio))
            listo = true
            estado.version += 1
            cerrar()
            estado.avisar("Cobro registrado") {
                Task { try? await estado.api.hacer("DELETE", "/v1/contratos/\(fila.contratoId)/cobros/\(n.id)"); estado.version += 1 }
            }
            alRegistrar(ARecibo(contrato: fila.contratoId, cobro: n.id))
        } catch let e as ErrorApi where e.sinConexion {
            let c = Cuerpo(periodo: p, monto: monto ?? fila.monto, pagadoEl: Formato.diaISO(fecha), medio: medio)
            try? await estado.cola.enviar("POST", "/v1/contratos/\(fila.contratoId)/cobros", c, etiqueta: "Cobro de \(fila.contactoNombre ?? "")")
            estado.avisar("Sin señal · el cobro queda en cola")
            cerrar()
        } catch { estado.avisar(error) }
    }
}

// MARK: - 10D Recibo

/// 10D Recibo: el papel con la marca de la inmobiliaria, el desglose y «Mandar por WhatsApp».
struct ReciboVista: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var contrato: String
    var cobro: String
    var enHoja = false
    @State private var c: Cobro?
    @State private var k: ContratoAPI?
    @State private var inmo: Inmobiliaria?
    @State private var link: URL?
    @State private var previo: ArchivoPrevio?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(String((inmo?.nombre ?? "C").prefix(1))).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                        .foregroundStyle(Color(hex: 0xE9DCC3)).frame(width: 36, height: 36).background(Color(hex: 0x1E3A5F), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text((inmo?.nombre ?? "").uppercased()).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).tracking(0.6).foregroundStyle(Color(hex: 0x1E3A5F))
                        Text("Recibo N.º \(c?.numero.map { String(format: "0001-%05d", $0) } ?? "—")").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(Color(hex: 0x6B6457))
                    }
                }
                Rectangle().fill(Color(hex: 0xE3DDCF)).frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(k?.contactoNombre ?? "").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                    Text("\(k?.propiedadTitulo ?? "") · \(c.map { Self.mes($0.periodo) } ?? "")").estilo(.texto14).foregroundStyle(Color(hex: 0x6B6457))
                }
                if let l = c?.conceptos, !l.isEmpty {
                    ForEach(l, id: \.self) { x in HStack { Text(x.concepto); Spacer(); Text(Formato.plata(x.monto, c?.moneda ?? "ARS")) }.estilo(.texto14) }
                } else if let c {
                    HStack { Text("Alquiler"); Spacer(); Text(Formato.plata(c.monto, c.moneda)) }.estilo(.texto14)
                }
                Rectangle().fill(Color(hex: 0xE3DDCF)).frame(height: 1)
                HStack { Text("Total cobrado").bold(); Spacer(); Text(c.map { Formato.plata($0.monto, $0.moneda) } ?? "").bold() }
                    .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                if let p = c?.pagadoEl { Text("Pagado el \(Fecha.dia(p).map { Formato.diaCompleto($0) } ?? p)\(c?.medio.map { " · \($0)" } ?? "")").estilo(.footnote).foregroundStyle(Color(hex: 0x6B6457)) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image("Simbolo").resizable().scaledToFit().frame(height: 10).colorMultiply(Color(hex: 0xC9A04A))
                    Text("Hecha con Corredor").font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font).foregroundStyle(Color(hex: 0x6B6457))
                }
            }
            .foregroundStyle(Color(hex: 0x18201D))
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: 0xFAF8F3), in: .rect(cornerRadius: 16, style: .continuous))
            Button { Task { await mandar() } } label: {
                HStack(spacing: 8) {
                    Image("LogoWhatsApp").renderingMode(.template).resizable().frame(width: 20, height: 20)
                    Text("Mandar por WhatsApp").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                }
                .foregroundStyle(Color(hex: 0x0B3D1F)).frame(maxWidth: .infinity, minHeight: 54).background(Color(hex: 0x25D366), in: .rect(cornerRadius: 15, style: .continuous))
            }
            HStack(spacing: 16) {
                if let link { ShareLink("Compartir el link", item: link) }
                Button { Task { if let c, let u = await Documentos.recibo(c, contrato: k, api: estado.api) { previo = ArchivoPrevio(url: u) } } } label: { Label("PDF", systemImage: "doc.richtext") }
            }
            .font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
        }
        .padding(16)
        .background(C.superficie)
        .navigationTitle("Recibo listo").navigationBarTitleDisplayMode(.inline)
        .vistaPrevia($previo)
        .toolbar { if enHoja { Button("Listo") { cerrar() } } }
        .task {
            let l: [MesContrato] = (try? await estado.api.get("/v1/contratos/\(contrato)/cobros")) ?? []
            c = l.compactMap(\.cobro).first { $0.id == cobro }
            k = try? await estado.api.get("/v1/contratos/\(contrato)")
            inmo = try? await estado.api.get("/v1/inmobiliaria")
        }
    }

    static func mes(_ p: String) -> String {
        guard let d = Fecha.dia(p + "-01") else { return p }
        return "\(Formato.mesDe(d)) \(Calendar.current.component(.year, from: d))"
    }

    private func mandar() async {
        struct L: Decodable { var url: String }
        do {
            let l: L = try await estado.api.enviar("POST", "/v1/contratos/\(contrato)/cobros/\(cobro)/compartir", [String: String]())
            link = URL(string: l.url)
            struct Ct: Decodable { var telefono: String? }
            let x: Ct? = k?.contactoId == nil ? nil : try? await estado.api.get("/v1/contactos/\(k!.contactoId!)")
            Afuera.whatsapp(x?.telefono, texto: "Hola \(k?.contactoNombre?.split(separator: " ").first.map(String.init) ?? ""), te paso el recibo: \(l.url)")
        } catch { estado.avisar(error) }
    }
}

// MARK: - Contratos

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
}

/// Los contratos: vigentes, por vencer y terminados, con lo que deben.
struct Contratos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [ContratoAPI]?
    @State private var deudas: [String: Deuda] = [:]
    @State private var filtro = "vigente"
    @State private var nuevo = false
    @State private var leerPDF = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Segmentado(opciones: [("vigente", "Vigentes"), ("vencen", "Por vencer"), ("todos", "Todos")], elegido: $filtro)
                if let lista {
                    let l = lista.filter { k in
                        switch filtro {
                        case "vigente": return k.estado == "vigente" || k.estado == nil
                        case "vencen": return k.fin.flatMap(Fecha.dia).map { $0 < Date().addingTimeInterval(90 * 86400) && $0 > Date() } ?? false
                        default: return true
                        }
                    }
                    if lista.isEmpty {
                        EstadoVacio(icono: "doc.text", titulo: "Todavía no hay contratos",
                                    texto: "Cargá un contrato y Corredor calcula cada ajuste, te avisa antes y arma los cobros del mes.",
                                    accion: estado.escribe ? ("Cargar contrato", { nuevo = true }) : nil,
                                    secundaria: estado.escribe ? ("Subir el PDF y que lo lea", { leerPDF = true; nuevo = true }) : nil).padding(.top, 30)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, k in
                            Button { estado.abrir(AFichaContrato(id: k.id)) } label: {
                                HStack(spacing: 12) {
                                    IconoTono(icono: k.tipo == "venta" ? "key" : "doc.text", tono: deudas[k.id] != nil ? .rojo : .verde)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(k.propiedadTitulo ?? "Contrato").estilo(.filaLista).foregroundStyle(C.texto)
                                        Text([k.contactoNombre, k.monto.map { Formato.plata($0, k.moneda ?? "ARS") }, k.ajusteTexto].compactMap { $0 }.joined(separator: " · "))
                                            .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                                        if let d = deudas[k.id] {
                                            Text("Debe \(Formato.plata(d.total ?? 0, d.moneda ?? "ARS"))").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.errorTinta)
                                        } else if let f = k.fin.flatMap(Fecha.dia) {
                                            Text("Hasta el \(Formato.diaCompleto(f))").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
                                        }
                                    }
                                    Spacer()
                                    Chevron()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Contratos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if estado.escribe {
                Menu {
                    Button { leerPDF = false; nuevo = true } label: { Label("Cargar contrato", systemImage: "square.and.pencil") }
                    Button { leerPDF = true; nuevo = true } label: { Label("Subir el PDF y que lo lea", systemImage: "doc.viewfinder") }
                } label: { Image(systemName: "plus") }
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { AltaContrato(leer: leerPDF) }
    }

    private func cargar() async {
        lista = (try? await estado.api.get("/v1/contratos", query: [.init(name: "limite", value: "1000")])) ?? lista ?? []
        let d: [Deuda] = (try? await estado.api.get("/v1/contratos/deudas")) ?? []
        deudas = Dictionary(d.map { ($0.contratoId, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// La ficha de un contrato: partes, plazo, ajuste (el próximo, con avisar), los cobros mes a mes, las
/// rendiciones al propietario y lo demás (imprimir, renovar, rescindir).
struct FichaContrato: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var k: ContratoAPI?
    @State private var cobros: [Cobro] = []
    @State private var rendiciones: [RendicionAPI] = []
    @State private var deuda: Deuda?
    @State private var ajuste: AjusteAPI?
    @State private var cobrando: FilaCobranza?
    @State private var recibo: ARecibo?
    @State private var previo: ArchivoPrevio?

    /// GET /v1/contratos/{id}/ajuste: el próximo ajuste y a quién ya se le avisó.
    struct AjusteAPI: Codable {
        struct Proximo: Codable { var indice: String?; var fecha: String?; var monto: Double?; var estimado: Bool? }
        var proximo: Proximo?
        var avisos: [String: Date]?
        var fecha: String? { proximo?.fecha }
        var montoNuevo: Double? { proximo?.monto }
        var estimado: Bool? { proximo?.estimado }
        var avisado: Bool? { (avisos?.isEmpty == false) }
    }

    var body: some View {
        ScrollView {
            if let k {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(k.propiedadTitulo ?? "Contrato").estilo(.titulo).foregroundStyle(C.texto)
                        Text("\(k.tipo == "venta" ? "Venta" : "Alquiler") · \(k.inicio.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "") al \(k.fin.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "—")")
                            .estilo(.subhead).foregroundStyle(C.texto2)
                    }
                    if let d = deuda, (d.total ?? 0) > 0 {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Debe").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.errorTinta)
                                Text(Formato.plata(d.total ?? 0, d.moneda ?? "ARS")).font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font).foregroundStyle(C.texto)
                                Text(Formato.cantidad(d.meses?.count ?? 0, "mes", "meses")).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            if estado.escribe {
                                Button("Cobrar") {
                                    cobrando = FilaCobranza(contratoId: k.id, propiedadTitulo: k.propiedadTitulo, contactoNombre: k.contactoNombre, monto: d.meses?.first?.esperado ?? d.total ?? 0,
                                                            moneda: d.moneda ?? "ARS", vence: d.meses?.first?.periodo.map { $0 + "-10" })
                                }
                                .buttonStyle(BotonAccion()).frame(width: 110)
                            }
                        }
                        .padding(14).background(C.errorFondo, in: .rect(cornerRadius: 18))
                    }
                    VStack(spacing: 0) {
                        dato("Inquilino", k.contactoNombre ?? "—", primera: true) { if let c = k.contactoId { estado.abrir(AFichaContacto(id: c)) } }
                        dato("Propietario", k.propietarioNombre ?? "—") { if let c = k.propietarioId { estado.abrir(AFichaContacto(id: c)) } }
                        dato("Alquiler", k.monto.map { Formato.plata($0, k.moneda ?? "ARS") } ?? "—")
                        dato("Ajuste", k.ajusteTexto)
                        if let a = ajuste, let f = a.fecha {
                            dato("Próximo ajuste", "\(Fecha.dia(f).map { Formato.diaCompleto($0) } ?? f)\(a.montoNuevo.map { " · \(Formato.plata($0, k.moneda ?? "ARS"))\(a.estimado == true ? " (estimado)" : "")" } ?? "")")
                        }
                        dato("Vence", k.diaVencimiento.map { "El \($0) de cada mes" } ?? "—")
                        if let d = k.deposito { dato("Depósito", Formato.plata(d, k.moneda ?? "ARS")) }
                        if let c = k.comision { dato("Administración", "\(Formato.numero(Int(c))) % de lo cobrado") }
                        if let g = k.garanteNombre { dato("Garante", g) { Afuera.llamar(k.garanteTelefono) } }
                    }
                    .tarjeta()
                    if let a = ajuste, a.avisado != true, a.fecha != nil, estado.escribe {
                        Button {
                            Task { try? await estado.api.hacer("POST", "/v1/contratos/\(id)/ajuste/avisos"); estado.avisar("Le avisamos del ajuste"); await cargar() }
                        } label: { Label("Avisarle el ajuste por WhatsApp", systemImage: "bell") }
                        .buttonStyle(BotonHundido())
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: "Cobros")
                        VStack(spacing: 0) {
                            ForEach(Array(cobros.sorted { $0.periodo > $1.periodo }.enumerated()), id: \.element.id) { i, c in
                                Button { recibo = ARecibo(contrato: id, cobro: c.id) } label: {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x2F9E6F))
                                        Text(Formato.mayuscula(ReciboVista.mes(c.periodo))).estilo(.body16).foregroundStyle(C.texto)
                                        Spacer()
                                        Text(Formato.plata(c.monto, c.moneda)).fontWeight(.semibold).foregroundStyle(C.texto)
                                    }
                                    .estilo(.body16).padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                            }
                            if cobros.isEmpty { Text("Todavía no hay cobros.").estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        .tarjeta()
                    }
                    if k.tipo != "venta" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TituloBloque(texto: "Rendiciones al propietario")
                                if estado.escribe {
                                    Button("Armar") { Task { await armarRendicion() } }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                                }
                            }
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
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                                if rendiciones.isEmpty { Text("Se arman solas con lo cobrado.").estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
                            }
                            .tarjeta()
                        }
                    }
                    VStack(spacing: 8) {
                        if let p = k.propiedadId { Button("Inventario y actas") { estado.abrir(AInventario(id: p)) }.buttonStyle(BotonHundido()) }
                        Button("Ver o imprimir el contrato") { Task { if let u = await Documentos.contrato(k, api: estado.api) { previo = ArchivoPrevio(url: u) } } }
                            .buttonStyle(BotonHundido())
                        if estado.escribe {
                            Button("Renovar") { estado.abrir(ASeccion(clave: "contrato-renovar", id: id)) }.buttonStyle(BotonHundido())
                            if k.estado != "rescindido" { Button("Rescindir") { Task { await rescindir() } }.buttonStyle(BotonTexto(color: C.error)) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("Contrato")
        .vistaPrevia($previo)
        .task(id: estado.version) { await cargar() }
        .sheet(item: $cobrando) { c in HojaCobro(fila: c) { recibo = $0 }.presentationDetents([.medium]) }
        .sheet(item: Binding(get: { recibo.map { ReciboHoja(r: $0) } }, set: { recibo = $0?.r })) { x in
            NavigationStack { ReciboVista(contrato: x.r.contrato, cobro: x.r.cobro, enHoja: true) }
        }
    }

    private func dato(_ l: String, _ v: String, primera: Bool = false, _ hacer: (() -> Void)? = nil) -> some View {
        Button { hacer?() } label: {
            HStack {
                Text(l).foregroundStyle(C.texto2)
                Spacer()
                Text(v).fontWeight(.semibold).foregroundStyle(C.texto).multilineTextAlignment(.trailing)
                if hacer != nil { Chevron() }
            }
            .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(hacer == nil)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cargar() async {
        k = try? await estado.api.get("/v1/contratos/\(id)")
        let meses: [MesContrato] = (try? await estado.api.get("/v1/contratos/\(id)/cobros")) ?? []
        cobros = meses.compactMap(\.cobro)
        rendiciones = (try? await estado.api.get("/v1/contratos/\(id)/rendiciones")) ?? []
        ajuste = try? await estado.api.get("/v1/contratos/\(id)/ajuste")
        let d: [Deuda] = (try? await estado.api.get("/v1/contratos/deudas")) ?? []
        deuda = d.first { $0.contratoId == id }
    }

    private func armarRendicion() async {
        struct Cuerpo: Encodable { var periodo: String }
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/contratos/\(id)/rendiciones", Cuerpo(periodo: String(Formato.diaISO(Date()).prefix(7))))
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
                    try? await estado.api.hacer("PATCH", "/v1/contratos/\(id)", Volver())
                    estado.version += 1
                }
            }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Rendiciones

struct RendicionAPI: Codable, Identifiable, Hashable {
    struct Item: Codable, Identifiable, Hashable { var id: String; var descripcion: String; var monto: Double; var archivoId: String? }
    var id: String
    var contratoId: String?
    var periodo: String
    var moneda: String?
    var cobrado: Double?
    var comisionPorcentaje: Double?
    var comision: Double?
    var gastos: Double?
    var neto: Double?
    var estado: String?
    var numero: Int?
    var items: [Item]?

    static func estadoTexto(_ e: String?) -> String {
        ["pendiente": "Borrador para revisar", "liquidada": "Emitida", "pagada": "Transferida"][e ?? ""] ?? "Borrador"
    }
}

/// La rendición al propietario: lo cobrado, la administración, los gastos (sumar con comprobante,
/// sacar con «Deshacer») y «Emitir y mandar».
struct RendicionVista: View {
    @Environment(Estado.self) private var estado
    var contrato: String
    var id: String
    @State private var r: RendicionAPI?
    @State private var descripcion = ""
    @State private var monto: Double?
    @State private var link: URL?
    @State private var previo: ArchivoPrevio?

    var body: some View {
        ScrollView {
            if let r {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rendición de \(ReciboVista.mes(r.periodo))").estilo(.titulo).foregroundStyle(C.texto)
                        Text(RendicionAPI.estadoTexto(r.estado)).estilo(.subhead).foregroundStyle(C.texto2)
                    }
                    VStack(spacing: 0) {
                        linea("Alquiler cobrado", r.cobrado ?? 0, r.moneda, primera: true)
                        if let c = r.comision, c > 0 { linea("Administración \(Formato.numero(Int(r.comisionPorcentaje ?? 0))) %", -c, r.moneda) }
                        ForEach(r.items ?? []) { it in
                            HStack {
                                Text(it.descripcion).foregroundStyle(C.texto2)
                                Spacer()
                                Text("−" + Formato.plata(it.monto, r.moneda ?? "ARS")).foregroundStyle(C.texto)
                                if r.estado == "pendiente" && estado.escribe {
                                    Button { Task { await sacar(it) } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }.accessibilityLabel("Sacar \(it.descripcion)")
                                }
                            }
                            .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
                            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                        }
                        HStack {
                            Text("A transferir").bold()
                            Spacer()
                            Text(Formato.plata(r.neto ?? 0, r.moneda ?? "ARS")).bold()
                        }
                        .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                        .padding(14).overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                    }
                    .tarjeta()
                    if r.estado == "pendiente" && estado.escribe {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sumar gasto o ajuste").estilo(.subheadFuerte)
                            TextField("Arreglo de canilla · Plomería Rossi", text: $descripcion).campoCorredor()
                            TextField("Monto", value: $monto, format: .number).keyboardType(.decimalPad).campoCorredor()
                            Button("Sumar") { Task { await sumar() } }.buttonStyle(BotonHundido()).disabled(descripcion.isEmpty || monto == nil)
                        }
                        if estado.esDuenio {
                            Button("Emitir y mandar") { Task { await emitir() } }.buttonStyle(BotonPrincipal())
                        }
                    }
                    if r.estado == "liquidada" && estado.escribe {
                        Button("Marcar transferida") { Task { await transferida() } }.buttonStyle(BotonPrincipal())
                    }
                    if let link { ShareLink("Compartir la rendición", item: link).font(Estilo.subheadFuerte.font) }
                }
                .padding(16)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("Rendición")
        .vistaPrevia($previo)
        .toolbar {
            Button {
                Task {
                    let k: ContratoAPI? = try? await estado.api.get("/v1/contratos/\(contrato)")
                    if let r, let u = await Documentos.rendicion(r, contrato: k, api: estado.api) { previo = ArchivoPrevio(url: u) }
                }
            } label: { Image(systemName: "printer") }
            .accessibilityLabel("PDF de la rendición")
        }
        .task(id: estado.version) { r = try? await estado.api.get("/v1/contratos/\(contrato)/rendiciones/\(id)") }
    }

    private func linea(_ l: String, _ v: Double, _ m: String?, primera: Bool = false) -> some View {
        HStack { Text(l).foregroundStyle(C.texto2); Spacer(); Text((v < 0 ? "−" : "") + Formato.plata(abs(v), m ?? "ARS")).foregroundStyle(C.texto) }
            .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private var ruta: String { "/v1/contratos/\(contrato)/rendiciones/\(id)" }

    private func sumar() async {
        struct Cuerpo: Encodable { var descripcion: String; var monto: Double }
        do {
            let n: RendicionAPI = try await estado.api.enviar("POST", "\(ruta)/items", Cuerpo(descripcion: descripcion, monto: monto ?? 0))
            let item = n.items?.last
            r = n
            estado.avisar("Sumaste «\(descripcion)»") {
                if let item { Task { try? await estado.api.hacer("DELETE", "\(ruta)/items/\(item.id)"); estado.version += 1 } }
            }
            descripcion = ""
            monto = nil
        } catch { estado.avisar(error) }
    }

    private func sacar(_ it: RendicionAPI.Item) async {
        struct Cuerpo: Encodable { var descripcion: String; var monto: Double }
        try? await estado.api.hacer("DELETE", "\(ruta)/items/\(it.id)")
        estado.version += 1
        estado.avisar("Sacaste «\(it.descripcion)»") {
            Task { try? await estado.api.hacer("POST", "\(ruta)/items", Cuerpo(descripcion: it.descripcion, monto: it.monto)); estado.version += 1 }
        }
    }

    private func emitir() async {
        struct L: Decodable { var url: String? }
        do {
            let l: L = try await estado.api.enviar("POST", "\(ruta)/emitir", [String: String]())
            link = l.url.flatMap(URL.init(string:))
            estado.version += 1
            if let u = l.url { Afuera.whatsapp(nil, texto: "Te paso la rendición de \(ReciboVista.mes(r?.periodo ?? "")): \(u)") }
        } catch { estado.avisar(error) }
    }

    private func transferida() async {
        struct Cuerpo: Encodable { var estado = "pagada" }
        try? await estado.api.hacer("PATCH", ruta, Cuerpo())
        estado.version += 1
        estado.avisar("Transferencia marcada como hecha") {
            Task {
                struct Volver: Encodable { var estado = "liquidada" }
                try? await estado.api.hacer("PATCH", ruta, Volver())
                estado.version += 1
            }
        }
    }
}

// MARK: - Alta de contrato (con «Subir el PDF y que lo lea»)

/// Alta de un contrato: a mano o leyendo el PDF o una foto (POST /v1/contratos/leer); lo que no se lee
/// bien queda marcado con «Revisá».
struct AltaContrato: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var leer = false
    @State private var k = ContratoAPI(id: "", tipo: "alquiler", moneda: "ARS", ajusteMeses: 6, ajusteIndice: "icl", diaVencimiento: 10)
    @State private var inicio = Date()
    @State private var meses = 36
    @State private var prop: Propiedad?
    @State private var inq: Resultado?
    @State private var duenio: Resultado?
    @State private var dudosos: Set<String> = []
    @State private var leyendo = false
    @State private var archivo: Archivo?
    @State private var eligiendoArchivo = false
    @State private var foto: PhotosPickerItem?
    @State private var elegirP = false
    @State private var elegirI = false
    @State private var elegirD = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { eligiendoArchivo = true } label: { Label(leyendo ? "Leyendo el contrato…" : (archivo == nil ? "Subir el PDF y que lo lea" : "Leímos el contrato. Revisá lo marcado."), systemImage: "doc.viewfinder") }
                        .disabled(leyendo)
                    PhotosPicker(selection: $foto, matching: .images) { Label("O una foto del contrato", systemImage: "camera") }
                }
                Section("Partes") {
                    Picker("Contrato de", selection: Binding(get: { k.tipo ?? "alquiler" }, set: { k.tipo = $0 })) { Text("Alquiler").tag("alquiler"); Text("Venta").tag("venta") }.pickerStyle(.segmented)
                    Button { elegirP = true } label: { campo("Propiedad", prop?.nombre ?? "Elegí", "direccion") }
                    Button { elegirI = true } label: { campo(k.tipo == "venta" ? "Comprador" : "Inquilino", inq?.titulo ?? "Elegí", "inquilino") }
                    Button { elegirD = true } label: { campo("Propietario", duenio?.titulo ?? "Opcional", "propietario") }
                    TextField("Garante", text: Binding(get: { k.garanteNombre ?? "" }, set: { k.garanteNombre = $0.nonEmpty }))
                }
                Section("Plazo y monto") {
                    DatePicker("Empieza", selection: $inicio, displayedComponents: .date)
                    Stepper("Duración: \(meses) meses", value: $meses, in: 1...120)
                    Picker("Moneda", selection: Binding(get: { k.moneda ?? "ARS" }, set: { k.moneda = $0 })) { Text("ARS").tag("ARS"); Text("USD").tag("USD") }.pickerStyle(.segmented)
                    TextField("Monto", value: $k.monto, format: .number).keyboardType(.decimalPad).listRowBackground(dudosos.contains("monto") ? C.avisoFondo : nil)
                    Stepper("Vence el \(k.diaVencimiento ?? 10)", value: Binding(get: { k.diaVencimiento ?? 10 }, set: { k.diaVencimiento = $0 }), in: 1...28)
                }
                if k.tipo != "venta" {
                    Section("Ajuste") {
                        Picker("Índice", selection: Binding(get: { k.ajusteIndice ?? "" }, set: { k.ajusteIndice = $0.nonEmpty })) {
                            Text("ICL").tag("icl"); Text("IPC").tag("ipc"); Text("UVA").tag("uva"); Text("Fijo").tag("fijo"); Text("Sin ajuste").tag("")
                        }
                        .listRowBackground(dudosos.contains("ajusteIndice") ? C.avisoFondo : nil)
                        Picker("Cada", selection: Binding(get: { k.ajusteMeses ?? 6 }, set: { k.ajusteMeses = $0 })) { ForEach([3, 4, 6, 12], id: \.self) { Text("\($0) meses").tag($0) } }
                        if k.ajusteIndice == "fijo" { TextField("Porcentaje", value: $k.ajustePorcentaje, format: .number).keyboardType(.decimalPad) }
                    }
                }
                Section("Condiciones") {
                    TextField("Depósito", value: $k.deposito, format: .number).keyboardType(.decimalPad)
                    TextField("Honorarios %", value: $k.honorarios, format: .number).keyboardType(.decimalPad)
                    TextField("Administración % de lo cobrado", value: $k.comision, format: .number).keyboardType(.decimalPad)
                    TextField("Punitorio diario %", value: $k.punitorioDiario, format: .number).keyboardType(.decimalPad)
                    TextField("Notas", text: Binding(get: { k.notas ?? "" }, set: { k.notas = $0.nonEmpty }), axis: .vertical)
                }
            }
            .navigationTitle("Nuevo contrato").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Crear") { Task { await crear() } }.disabled(prop == nil || inq == nil || k.monto == nil) }
            }
            .fileImporter(isPresented: $eligiendoArchivo, allowedContentTypes: [.pdf, .image]) { r in
                if case .success(let u) = r { Task { await leerArchivo(u) } }
            }
            .onChange(of: foto) { _, i in
                guard let i else { return }
                Task { if let d = try? await i.loadTransferable(type: Data.self) { await leerDatos(d, nombre: "contrato.jpg", tipo: "image/jpeg") } }
            }
            .sheet(isPresented: $elegirP) { ElegirPropiedad { prop = $0 } }
            .sheet(isPresented: $elegirI) { ElegirContacto(tipo: "inquilino") { inq = $0 } }
            .sheet(isPresented: $elegirD) { ElegirContacto(tipo: "propietario") { duenio = $0 } }
            .onAppear { if leer { eligiendoArchivo = true } }
        }
    }

    private func campo(_ l: String, _ v: String, _ clave: String) -> some View {
        HStack {
            Text(l).foregroundStyle(C.texto)
            Spacer()
            if dudosos.contains(clave) { Text("Revisá").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.avisoTinta).padding(.horizontal, 8).frame(height: 22).background(C.avisoFondo, in: Capsule()) }
            Text(v).foregroundStyle(C.texto2)
        }
    }

    private func leerArchivo(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u) else { return }
        await leerDatos(d, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
    }

    private func leerDatos(_ d: Data, nombre: String, tipo: String) async {
        leyendo = true
        defer { leyendo = false }
        struct Parte: Decodable { var nombre: String; var telefono: String? }
        struct Leido: Decodable {
            var tipo: String?; var inquilino: Parte?; var propietario: Parte?; var garante: Parte?; var direccion: String?; var inicio: String?; var meses: Int?
            var monto: Double?; var moneda: String?; var ajusteIndice: String?; var ajusteMeses: Int?; var ajustePorcentaje: Double?; var deposito: Double?
            var honorarios: Double?; var punitorioDiario: Double?; var diaVencimiento: Int?; var notas: String?; var dudosos: [String]?
        }
        struct Lectura: Decodable { var datos: Leido }
        struct Cuerpo: Encodable { var archivoId: String }
        do {
            let a = try await estado.api.subir(d, nombre: nombre, tipo: tipo, uso: "documento")
            archivo = a
            let l: Lectura = try await estado.api.enviar("POST", "/v1/contratos/leer", Cuerpo(archivoId: a.id))
            let x = l.datos
            if x.tipo == "venta" || x.tipo == "alquiler" { k.tipo = x.tipo }
            if let i = x.inicio.flatMap(Fecha.dia) { inicio = i }
            if let m = x.meses { meses = m }
            k.monto = x.monto ?? k.monto
            if x.moneda == "USD" || x.moneda == "ARS" { k.moneda = x.moneda }
            if let i = x.ajusteIndice { k.ajusteIndice = i }
            k.ajusteMeses = x.ajusteMeses ?? k.ajusteMeses
            k.ajustePorcentaje = x.ajustePorcentaje ?? k.ajustePorcentaje
            k.deposito = x.deposito ?? k.deposito
            k.honorarios = x.honorarios ?? k.honorarios
            k.punitorioDiario = x.punitorioDiario ?? k.punitorioDiario
            k.diaVencimiento = x.diaVencimiento ?? k.diaVencimiento
            k.garanteNombre = x.garante?.nombre ?? k.garanteNombre
            k.garanteTelefono = x.garante?.telefono ?? k.garanteTelefono
            k.notas = x.notas ?? k.notas
            dudosos = Set(x.dudosos ?? [])
            if let n = x.inquilino?.nombre, let r: [Resultado] = try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: n)]), let p = r.first { inq = p }
            if let n = x.propietario?.nombre, let r: [Resultado] = try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: n)]), let p = r.first { duenio = p }
            if let dir = x.direccion, let r: [Resultado] = try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "propiedad"), .init(name: "q", value: dir)]), let p = r.first {
                prop = try? await estado.api.get("/v1/propiedades/\(p.id)")
            }
            estado.avisar(dudosos.isEmpty ? "Lo leímos. Revisá y creá el contrato." : "Lo leímos. Revisá lo marcado.")
        } catch { estado.avisar(error) }
    }

    private func crear() async {
        struct Cuerpo: Encodable {
            var tipo: String; var propiedadId: String?; var contactoId: String?; var propietarioId: String?; var agenteId: String?
            var inicio: String; var fin: String; var monto: Double?; var moneda: String; var ajusteMeses: Int?; var ajusteIndice: String?; var ajustePorcentaje: Double?
            var comision: Double?; var deposito: Double?; var diaVencimiento: Int?; var garanteNombre: String?; var garanteTelefono: String?
            var notas: String?; var honorarios: Double?; var punitorioDiario: Double?
        }
        let fin = Calendar.current.date(byAdding: DateComponents(month: meses, day: -1), to: inicio)!
        struct Nuevo: Decodable { var id: String }
        do {
            let n: Nuevo = try await estado.api.enviar("POST", "/v1/contratos", Cuerpo(
                tipo: k.tipo ?? "alquiler", propiedadId: prop?.id, contactoId: inq?.id, propietarioId: duenio?.id, agenteId: estado.usuario?.id,
                inicio: Formato.diaISO(inicio), fin: Formato.diaISO(fin), monto: k.monto, moneda: k.moneda ?? "ARS", ajusteMeses: k.ajusteIndice == nil ? nil : k.ajusteMeses,
                ajusteIndice: k.ajusteIndice, ajustePorcentaje: k.ajustePorcentaje, comision: k.comision, deposito: k.deposito, diaVencimiento: k.diaVencimiento,
                garanteNombre: k.garanteNombre, garanteTelefono: k.garanteTelefono, notas: k.notas, honorarios: k.honorarios, punitorioDiario: k.punitorioDiario))
            if let a = archivo {
                struct Doc: Encodable { var archivoId: String; var contratoId: String; var nombre: String }
                try? await estado.api.hacer("POST", "/v1/documentos", Doc(archivoId: a.id, contratoId: n.id, nombre: a.nombre ?? "Contrato firmado.pdf"))
            }
            estado.version += 1
            cerrar()
            estado.abrir(AFichaContrato(id: n.id))
        } catch { estado.avisar(error) }
    }
}

// MARK: - Reservas

/// Tomar una reserva de una propiedad: el interesado, la seña y hasta cuándo.
struct NuevaReserva: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: Propiedad
    @State private var con: Resultado?
    @State private var sena: Double?
    @State private var moneda = "USD"
    @State private var vence = Date().addingTimeInterval(7 * 86400)
    @State private var elegir = false

    var body: some View {
        NavigationStack {
            Form {
                Button { elegir = true } label: { LabeledContent("Interesado", value: con?.titulo ?? "Elegí") }
                Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Seña", value: $sena, format: .number).keyboardType(.decimalPad)
                DatePicker("Vence", selection: $vence, in: Date()..., displayedComponents: .date)
            }
            .navigationTitle("Reserva de \(propiedad.nombre)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reservar") {
                        Task {
                            struct Cuerpo: Encodable { var contactoId: String?; var interesadoNombre: String?; var sena: Double?; var senaMoneda: String; var reservadaEl: String; var venceEl: String }
                            do {
                                try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad.id)/reservas", Cuerpo(contactoId: con?.id, interesadoNombre: con?.titulo, sena: sena, senaMoneda: moneda, reservadaEl: Formato.diaISO(Date()), venceEl: Formato.diaISO(vence)))
                                estado.version += 1
                                estado.avisar("\(propiedad.nombre) quedó reservada")
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                    .disabled(con == nil)
                }
            }
            .sheet(isPresented: $elegir) { ElegirContacto { con = $0 } }
        }
    }
}
