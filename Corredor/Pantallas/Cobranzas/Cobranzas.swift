import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers

extension View {
    /// Los destinos de Cobranzas, contratos, rendiciones y actas.
    func destinosCobranzas() -> some View {
        self
            .navigationDestination(for: ACobranzas.self) { _ in Cobranzas() }
            .navigationDestination(for: ARegistrarCobro.self) { r in Cobranzas(registrar: true, contrato: r.contrato) }
            .navigationDestination(for: AContratos.self) { _ in Contratos() }
            .navigationDestination(for: AContratosFiltro.self) { f in Contratos(vista: f.vista, indice: f.indice) }
            .navigationDestination(for: AFichaContrato.self) { c in FichaContrato(id: c.id) }
            .navigationDestination(for: ARecordarMes.self) { c in FichaContrato(id: c.contrato, recordar: c.periodo) }
            .navigationDestination(for: AAltaContrato.self) { a in AltaContratoPantalla(destino: a) }
            .navigationDestination(for: ARecibo.self) { r in ReciboVista(contrato: r.contrato, cobro: r.cobro) }
            .navigationDestination(for: ARendicion.self) { r in RendicionVista(contrato: r.contrato, id: r.id) }
            .navigationDestination(for: ARendicionVista.self) { r in RendicionVista(contrato: r.contrato, id: r.id, verComoPropietario: true) }
            .navigationDestination(for: AInventario.self) { i in Inventario(propiedad: i.id) }
            .navigationDestination(for: AFirmas.self) { f in Firmas(clave: f.id) }
            .destinosInventarios()
    }
}

/// «Registrar cobro» con la hoja abierta (`/cobranzas?registrar=1&contrato=<id>` de los avisos y la
/// búsqueda): el cobro de ese contrato, o «¿De quién es el cobro?».
struct ARegistrarCobro: Hashable { var contrato: String? = nil }
/// La ficha del contrato con el recordatorio de un mes abierto (`/contratos/<id>?recordar=AAAA-MM`).
struct ARecordarMes: Hashable { var contrato: String; var periodo: String }
/// Los contratos con un filtro (`/contratos?vista=ajustan|vencen|todos`, `?indice=icl`).
struct AContratosFiltro: Hashable { var vista: String? = nil; var indice: String? = nil }
/// El alta de un contrato a pantalla completa: seguir un borrador (`/contratos/nuevo?borrador=`) o
/// renovar (`?renovar=`).
struct AAltaContrato: Hashable { var borrador: String? = nil; var renovar: String? = nil; var leer = false }
/// La rendición «como la ve el propietario» (`/rendiciones/<id>?contrato=<c>&vista=1`).
struct ARendicionVista: Hashable { var contrato: String; var id: String }

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

/// Un mes del contrato (GET /v1/contratos/{id}/cobros): lo esperado y, si se cobró, el cobro. Estado:
/// cobrado, pendiente, atrasado (se debe) o sin_registro (vencido sin cobro, de antes de Corredor).
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
    var totalComision: [String: Double]?
}

/// Un mes anterior sin cobrar (GET /v1/cobranzas/atrasadas?mes=).
struct Atraso: Codable, Hashable {
    var contratoId: String
    var periodo: String
    var vence: String
    var monto: Double
    var moneda: String
    var estimado: Bool?
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var agenteId: String?
    var punitorioDiario: Double?
}

/// Lo que debe un alquiler (GET /v1/contratos/deudas): los meses, del más viejo al más nuevo, con la
/// forma de la API (`Deuda` del núcleo tiene otra forma para los meses).
struct DeudaContrato: Codable, Hashable {
    var contratoId: String
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var moneda: String?
    var punitorioDiario: Double?
    var meses: [MesContrato]
    var total: Double?
    var estimado: Bool?
}

/// Lo que hace falta para cobrar un mes de un contrato.
struct ACobrar: Identifiable, Hashable {
    var contratoId: String
    var contactoId: String?
    var nombre: String?
    var telefono: String? = nil
    var propiedad: String?
    /// «AAAA-MM» o «AAAA-MM-01».
    var periodo: String
    var esperado: Double
    var moneda: String
    var vence: String
    /// La cláusula de punitorios del contrato (% por día de atraso).
    var punitorioDiario: Double?
    /// Con un cobro ya registrado, la hoja abre directo en el recibo («Mandar recibo»).
    var cobro: Cobro? = nil
    var id: String { "\(contratoId)|\(periodo.prefix(7))|\(cobro?.id ?? "")" }
}

// MARK: - 10A–10B Por cobrar

/// Una fila de «Deben» o de «Vencen el…»: un contrato y un mes (los atrasados de antes también deben).
struct FilaDeuda: Identifiable, Hashable {
    var contratoId: String
    var periodo: String
    var propiedad: String?
    var nombre: String?
    var contactoId: String?
    var monto: Double
    var moneda: String
    var vence: String
    var estado: String
    var cobro: Cobro?
    var punitorioDiario: Double?
    var pagadoEl: String? { cobro?.pagadoEl }
    var id: String { "\(contratoId)|\(periodo.prefix(7))" }

    var aCobrar: ACobrar {
        ACobrar(contratoId: contratoId, contactoId: contactoId, nombre: nombre, propiedad: propiedad, periodo: periodo,
                esperado: monto, moneda: moneda, vence: vence, punitorioDiario: punitorioDiario)
    }
}

/// 10A–10B Cobranzas del mes (23E, y P en el celular): quién debe (también de meses anteriores), qué
/// vence pronto, agrupado por día, y qué se cobró. Deslizar a la derecha cobra, a la izquierda recuerda.
struct Cobranzas: View {
    @Environment(Estado.self) private var estado
    /// «Registrar cobro» abierto al entrar (de los avisos o la búsqueda) y el contrato, si viene.
    var registrar = false
    var contrato: String? = nil
    @State private var mes: MesCobranzas?
    @State private var previo: MesCobranzas?
    @State private var atrasadas: [Atraso] = []
    @State private var contactos: [String: String] = [:]
    @State private var periodo = Date()
    @State private var cobrando: ACobrar?
    @State private var mensaje: PedidoMensaje?
    @State private var todos = false
    @State private var elegir = false
    @State private var cargarContrato = false
    @State private var ocultos: Set<String> = []
    @State private var error: ErrorApi?
    @State private var excel: ArchivoPrevio?
    @State private var bajandoExcel = false
    @State private var pedidoHecho = false

    private var hoy: String { Formato.diaISO(Date()) }
    private var nombreMes: String { TextosCobro.nombreMes(mes?.periodo ?? Formato.diaISO(periodo)) }
    private var Mes: String { Formato.mayuscula(nombreMes) }
    private var moneda: String {
        let ms = Array((mes?.totalCobrado ?? [:]).keys) + Array((mes?.totalPendiente ?? [:]).keys)
        return ms.contains("ARS") || ms.isEmpty ? "ARS" : ms[0]
    }
    private var enCurso: Bool { (mes?.periodo.prefix(7) ?? "") == hoy.prefix(7) }

    private func fila(_ f: FilaCobranza, periodo p: String) -> FilaDeuda {
        FilaDeuda(contratoId: f.contratoId, periodo: p, propiedad: f.propiedadTitulo, nombre: f.contactoNombre, contactoId: contactos[f.contratoId],
                  monto: f.monto, moneda: f.moneda, vence: f.vence ?? p, estado: f.estado ?? "pendiente", cobro: f.cobro, punitorioDiario: f.punitorioDiario)
    }

    private var visibles: [FilaDeuda] {
        guard let mes else { return [] }
        return mes.pendientes.map { fila($0, periodo: mes.periodo) }.filter { !ocultos.contains($0.id) }
    }
    private var deben: [FilaDeuda] {
        let viejas = atrasadas.map { a in
            FilaDeuda(contratoId: a.contratoId, periodo: a.periodo, propiedad: a.propiedadTitulo, nombre: a.contactoNombre, contactoId: a.contactoId,
                      monto: a.monto, moneda: a.moneda, vence: a.vence, estado: "atrasado", cobro: nil, punitorioDiario: a.punitorioDiario)
        }.filter { !ocultos.contains($0.id) }
        return viejas + visibles.filter { $0.estado == "atrasado" }
    }
    private var porVencer: [FilaDeuda] { visibles.filter { $0.estado != "atrasado" } }
    /// Lo que vence pronto, agrupado por día («Vencen el lunes 16»).
    private var grupos: [(String, [FilaDeuda])] {
        var m: [String: [FilaDeuda]] = [:]
        for f in porVencer { m[f.vence, default: []].append(f) }
        return m.keys.sorted().map { ($0, m[$0] ?? []) }
    }
    private var cobradas: [FilaDeuda] { (mes?.cobradas ?? []).map { fila($0, periodo: mes?.periodo ?? "") } }
    private var cobradasHoy: [FilaDeuda] { cobradas.filter { $0.pagadoEl == hoy } }
    private var listaCobradas: [FilaDeuda] { cobradasHoy.isEmpty ? Array(cobradas.suffix(6).reversed()) : cobradasHoy }

    private func sumar(_ fs: [FilaDeuda]) -> Double { fs.filter { $0.moneda == moneda }.reduce(0) { $0 + $1.monto } }
    private var totalCobrado: Double {
        (mes?.totalCobrado?[moneda] ?? 0) + sumar((mes?.pendientes ?? []).map { fila($0, periodo: mes?.periodo ?? "") }.filter { ocultos.contains($0.id) })
    }
    private var totalMes: Double { (mes?.totalCobrado?[moneda] ?? 0) + (mes?.totalPendiente?[moneda] ?? 0) }
    private var deuda: Double { sumar(deben) }
    private var deudaDelMes: Double { sumar(deben.filter { $0.periodo == mes?.periodo }) }
    private var pct: Double { totalMes > 0 ? totalCobrado / totalMes : 0 }
    private var pctDeuda: Double { totalMes > 0 ? deudaDelMes / totalMes : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let mes {
                    resumen
                    if mes.pendientes.isEmpty && mes.cobradas.isEmpty && atrasadas.isEmpty {
                        EstadoVacio(icono: "dollarsign.circle", titulo: "Todavía no hay alquileres para cobrar",
                                    texto: "Cargá un contrato y los cobros se arman solos.",
                                    accion: estado.escribe ? ("Cargar contrato", { cargarContrato = true }) : nil).padding(.top, 20)
                    } else {
                        bloqueDeben
                        ForEach(grupos, id: \.0) { g in bloqueVencen(g.0, g.1) }
                        if !listaCobradas.isEmpty { bloqueCobradas }
                    }
                    panelSeccion
                    HStack(spacing: 8) {
                        Button("Contratos") { estado.abrir(AContratos()) }.buttonStyle(BotonHundido())
                        Button("Rendiciones") { estado.abrir(ASeccion(clave: "rendiciones")) }.buttonStyle(BotonHundido())
                    }
                    GraficoCobranzaMeses()
                } else if let error {
                    EstadoError(que: "las cobranzas", error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Cobranzas · \(nombreMes)")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { barra }
        .task(id: "\(estado.version)\(Formato.diaISO(periodo).prefix(7))") { await cargar() }
        .sheet(item: $cobrando) { c in HojaCobro(item: c, ocultar: { _ = ocultos.insert($0) }, mostrar: { _ = ocultos.remove($0) }) }
        .hojaMensaje($mensaje)
        .sheet(isPresented: $todos) { RecordarATodos(deudores: deben).hojaTLW([.large]) }
        .sheet(isPresented: $elegir) { elegirCobro }
        .sheet(isPresented: $cargarContrato) { AltaContrato() }
        .vistaPrevia($excel)
    }

    @ToolbarContentBuilder private var barra: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(-6...0, id: \.self) { d in
                    let f = Calendar.current.date(byAdding: .month, value: d, to: Date())!
                    Button(Formato.mayuscula("\(Formato.mesDe(f)) \(Calendar.current.component(.year, from: f))")) { periodo = f }
                }
            } label: { Label(Mes, systemImage: "calendar") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if estado.escribe {
                    Button { elegir = true } label: { Label("Registrar cobro", systemImage: "dollarsign.circle") }
                }
                Button { Task { await bajarExcel() } } label: { Label("Excel", systemImage: "square.and.arrow.down") }.disabled(bajandoExcel)
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más")
        }
    }

    // MARK: Resumen

    private var resumen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Formato.plata(totalCobrado, moneda)).font(Estilo(tamano: 32, peso: .bold, tracking: -0.03, relativo: .largeTitle).font).foregroundStyle(.white)
            Text("Cobrado \(Formato.plata(totalCobrado, moneda)) de \(Formato.numero(Int(totalMes.rounded()))) · \(Int((pct * 100).rounded()))\u{00A0}%")
                .estilo(.texto14).foregroundStyle(Color(hex: 0xCFE0D8))
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(C.oro).frame(width: max(0, g.size.width * pct))
                    Capsule().fill(Color(hex: 0xF29B92)).frame(width: max(0, g.size.width * pctDeuda))
                    Capsule().fill(.white.opacity(0.14))
                }
            }
            .frame(height: 8).padding(.top, 6)
            .accessibilityLabel("Cobrado \(Int((pct * 100).rounded())) %, vencido \(Int((pctDeuda * 100).rounded())) %")
            .animation(.spring(duration: 0.5), value: totalCobrado)
            Text(deben.isEmpty ? "Nadie debe \(nombreMes)" : "\(Formato.cantidad(deben.count, "inquilino debe", "inquilinos deben")) \(Formato.plata(deuda, moneda))")
                .estilo(.subheadFuerte).foregroundStyle(deben.isEmpty ? Color(hex: 0xCFE0D8) : Color(hex: 0xF7C3BC)).padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ZStack { C.verde800; Image("Patron").resizable(resizingMode: .tile).opacity(0.06); Image("GranoClaro").resizable(resizingMode: .tile) } }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE3()
    }

    // MARK: Deben

    private var bloqueDeben: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DEBEN · \(deben.count)").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.errorTinta)
                Text(Formato.plata(deuda, moneda)).estilo(.footnoteFuerte).foregroundStyle(C.texto2)
                Spacer()
                if deben.count > 1 {
                    Button("Recordar a todos") { todos = true }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(deben.enumerated()), id: \.element.id) { i, f in filaDeudor(f, primera: i == 0, tono: .rojo, atraso: atraso(f)) }
                if deben.isEmpty {
                    Label("Nadie debe \(nombreMes). Todo al día.", systemImage: "checkmark.circle.fill").estilo(.subheadFuerte).foregroundStyle(C.okTinta)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tarjeta()
            if !deben.isEmpty {
                Text("Deslizá a la derecha para cobrar, a la izquierda para recordar.").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
            }
        }
    }

    private func bloqueVencen(_ vence: String, _ fs: [FilaDeuda]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vencen el \(Fecha.dia(vence).map { Formato.diaCompleto($0) } ?? vence)").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Text("\(fs.count) · \(Formato.plata(sumar(fs), moneda))").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(fs.enumerated()), id: \.element.id) { i, f in
                    filaDeudor(f, primera: i == 0, tono: .neutro, atraso: "vence \(Fecha.dia(f.vence).map { Self.diaCorto($0) } ?? f.vence)")
                }
            }
            .tarjeta()
        }
    }

    enum TonoFila { case rojo, neutro }

    private func filaDeudor(_ f: FilaDeuda, primera: Bool, tono: TonoFila, atraso: String) -> some View {
        FilaDeslizable(
            izquierda: estado.escribe ? [AccionFila(texto: "Cobrar", simbolo: "dollarsign.circle", color: Color(hex: 0x2F9E6F)) { cobrarYa(f) }] : [],
            derecha: [AccionFila(texto: "Recordar", simbolo: "bell.badge", color: C.oro) { recordar(f) }], anchoAccion: 112) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.nombre ?? "Sin inquilino").font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                    (Text("\(f.propiedad ?? "") · ") + Text(atraso).foregroundColor(tono == .rojo ? C.error : C.texto2).fontWeight(.semibold))
                        .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer()
                Text(Formato.plata(f.monto, f.moneda)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                Button { recordar(f) } label: { Image(systemName: "bell.badge").font(.system(size: 20)).foregroundStyle(C.texto2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Mandar recordatorio por WhatsApp")
                if estado.escribe {
                    Button { cobrando = f.aCobrar } label: {
                        Text("Cobrar").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.sobreAccion)
                            .padding(.horizontal, 12).frame(height: 34).background(C.accion, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                }
            }
            .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
            .background(C.superficie)
            .contentShape(Rectangle())
            .onTapGesture { if estado.escribe { cobrando = f.aCobrar } else { estado.abrir(AFichaContrato(id: f.contratoId)) } }
            .contextMenu {
                if estado.escribe {
                    Button { cobrando = f.aCobrar } label: { Label("Cobrar", systemImage: "dollarsign.circle") }
                }
                Button { recordar(f) } label: { Label("Recordar", systemImage: "bell.badge") }
                Button { estado.abrir(AFichaContrato(id: f.contratoId)) } label: { Label("Ver el contrato", systemImage: "doc.text") }
            }
        }
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Cobrado

    private var bloqueCobradas: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cobradasHoy.isEmpty ? "Cobrado en \(nombreMes)" : "Cobrado hoy").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Text("\(listaCobradas.count) · \(Formato.plata(sumar(listaCobradas), moneda))").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(listaCobradas.enumerated()), id: \.element.id) { i, f in filaCobrada(f, primera: i == 0) }
            }
            .tarjeta()
        }
    }

    private func filaCobrada(_ f: FilaDeuda, primera: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0x2F9E6F))
            Button { if let k = f.cobro { estado.abrir(ARecibo(contrato: f.contratoId, cobro: k.id)) } } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(f.nombre ?? "Sin inquilino").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(f.propiedad ?? "").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(Presionable())
            Text(Formato.numero(Int((f.cobro?.monto ?? f.monto).rounded()))).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
            if f.cobro?.compartido == true {
                Image(systemName: "checkmark.circle").font(.system(size: 18)).foregroundStyle(C.azulTinta).accessibilityLabel("Recibo enviado")
            } else if let k = f.cobro {
                Button("Mandar recibo") { var c = f.aCobrar; c.cobro = k; c.esperado = k.monto; cobrando = c }
                    .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.accion)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Panel de la sección (medios de cobro y el mes)

    @ViewBuilder private var panelSeccion: some View {
        let medios = mediosDelMes
        let conMedio = medios.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 8) {
            if conMedio > 0 {
                TituloBloque(texto: "Medios de cobro")
                VStack(spacing: 0) {
                    ForEach(Array(medios.enumerated()), id: \.element.0) { i, m in
                        HStack(spacing: 10) {
                            Image(systemName: m.0 == "transferencia" ? "building.columns" : m.0 == "efectivo" ? "banknote" : "qrcode").foregroundStyle(m.0 == "mercadopago" ? C.azulTinta : C.texto2).frame(width: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ReciboVista.medioNombre(m.0)).estilo(.filaLista).foregroundStyle(C.texto)
                                Text("\(m.1) este mes").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            Text("\(Int((Double(m.1) / Double(conMedio) * 100).rounded())) %").estilo(.subheadFuerte).foregroundStyle(C.texto)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
            TituloBloque(texto: "Mes")
            VStack(spacing: 0) {
                filaMes(Mes, enCurso ? "en curso" : "\(Self.pct(mes, moneda)) % cobrado", activo: true) {}
                if let previo {
                    filaMes(Formato.mayuscula(TextosCobro.nombreMes(previo.periodo)), "\(Self.pct(previo, moneda)) % cobrado", activo: false) {
                        if let d = Fecha.dia(String(previo.periodo.prefix(7)) + "-15") { periodo = d }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
            }
            .tarjeta()
        }
    }

    private func filaMes(_ t: String, _ d: String, activo: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(activo ? C.accion : C.texto2).frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                    Text(d).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer()
                if !activo { Chevron() }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(Presionable()).disabled(activo)
    }

    private var mediosDelMes: [(String, Int)] {
        var m: [String: Int] = [:]
        for f in mes?.cobradas ?? [] { if let x = f.cobro?.medio { m[x, default: 0] += 1 } }
        return ["transferencia", "efectivo", "mercadopago"].compactMap { k in m[k].map { (k, $0) } }
    }

    static func pct(_ c: MesCobranzas?, _ moneda: String) -> Int {
        let tc = c?.totalCobrado?[moneda] ?? 0
        let tp = c?.totalPendiente?[moneda] ?? 0
        return tc + tp > 0 ? Int((tc / (tc + tp) * 100).rounded()) : 0
    }

    // MARK: «¿De quién es el cobro?»

    private var elegirCobro: some View {
        NavigationStack {
            List {
                if visibles.isEmpty {
                    Text("No queda nada por cobrar en \(nombreMes).").foregroundStyle(C.texto2)
                }
                ForEach(visibles) { f in
                    Button {
                        elegir = false
                        Task { try? await Task.sleep(for: .milliseconds(350)); cobrando = f.aCobrar }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.nombre ?? "Sin inquilino").estilo(.filaLista).foregroundStyle(C.texto)
                                Text(f.propiedad ?? "").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            Text(Formato.numero(Int(f.monto.rounded()))).fontWeight(.semibold).foregroundStyle(C.texto)
                        }
                    }
                }
            }
            .navigationTitle("¿De quién es el cobro?").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text("\(Mes) · lo que falta cobrar").estilo(.footnote).foregroundStyle(C.texto2).frame(maxWidth: .infinity).padding(.bottom, 4)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { elegir = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Acciones

    private func atraso(_ f: FilaDeuda) -> String {
        if f.periodo != mes?.periodo { return "debe \(TextosCobro.mesConAnio(f.periodo, hoy: hoy))" }
        let d = Self.diasEntre(f.vence, hoy)
        return d <= 0 ? "vence hoy" : d == 1 ? "venció hace 1 día" : "venció hace \(d) días"
    }

    static func diasEntre(_ desde: String, _ hasta: String) -> Int {
        guard let a = Fecha.dia(desde), let b = Fecha.dia(hasta) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// «lunes 16».
    static func diaCorto(_ f: Date) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "es_AR")
        d.dateFormat = "EEEE d"
        return d.string(from: f)
    }

    static func vence(_ s: String?) -> (String, Bool) {
        guard let s, let d = Fecha.dia(s) else { return ("", false) }
        let dias = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d)).day ?? 0
        if dias < 0 { return ("vencido hace \(Formato.cantidad(-dias, "día", "días"))", true) }
        if dias == 0 { return ("vence hoy", true) }
        return ("vence el \(Calendar.current.component(.day, from: d))", false)
    }

    private func recordar(_ f: FilaDeuda) {
        let n = TextosCobro.primerNombre(f.nombre)
        mensaje = PedidoMensaje(
            titulo: "Recordarle a \(n.isEmpty ? "el inquilino" : n)",
            descripcion: "\(Formato.mayuscula(TextosCobro.mesConAnio(f.periodo, hoy: hoy))) · \(f.propiedad ?? "") · \(Formato.plata(f.monto, f.moneda))",
            contactoId: f.contactoId, nombre: f.nombre,
            texto: TextosCobro.recordatorio(nombre: f.nombre, periodo: f.periodo, importe: f.monto, moneda: f.moneda, vence: f.vence, hoy: hoy),
            para: "recordatorio",
            parametros: [n, TextosCobro.nombreMes(f.periodo), Formato.plata(f.monto, f.moneda), TextosCobro.fechaCortita(f.vence)],
            listo: "Quedó en la ficha de \(n) y en la bandeja.")
    }

    /// Deslizar «Cobrar»: el cobro del monto esperado sin preguntar (la fila se va, queda «Deshacer» y
    /// «Mandar recibo» en el aviso).
    private func cobrarYa(_ f: FilaDeuda) {
        let n = TextosCobro.primerNombre(f.nombre)
        Cobrar.registrar(estado, f.aCobrar, texto: "Cobrado · \(n.isEmpty ? (f.propiedad ?? "") : n)",
                         ocultar: { _ = ocultos.insert(f.id) }, mostrar: { _ = ocultos.remove(f.id) },
                         recibo: { c in var x = f.aCobrar; x.cobro = c; x.esperado = c.monto; cobrando = x })
    }

    private func bajarExcel() async {
        bajandoExcel = true
        defer { bajandoExcel = false }
        let p = String((mes?.periodo ?? Formato.diaISO(periodo)).prefix(7))
        do {
            let u = try await Documentos.archivo("/v1/cobranzas/excel?mes=\(p)", nombre: "cobranzas-\(p).xlsx", api: estado.api)
            excel = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        let p = String(Formato.diaISO(periodo).prefix(7))
        do {
            let m: MesCobranzas = try await estado.api.get("/v1/cobranzas", query: [.init(name: "mes", value: p)])
            let deMes = String(m.periodo.prefix(7))
            atrasadas = (try? await estado.api.get("/v1/cobranzas/atrasadas", query: [.init(name: "mes", value: deMes)])) ?? []
            let cs: [ContratoAPI] = (try? await estado.api.todas("/v1/contratos", query: [.init(name: "tipo", value: "alquiler")])) ?? []
            contactos = Dictionary(cs.compactMap { k in k.contactoId.map { (k.id, $0) } }, uniquingKeysWith: { a, _ in a })
            if let d = Fecha.dia(deMes + "-01"), let ant = Calendar.current.date(byAdding: .month, value: -1, to: d) {
                previo = try? await estado.api.get("/v1/cobranzas", query: [.init(name: "mes", value: String(Formato.diaISO(ant).prefix(7)))])
            }
            // Lo que vuelve de la API ya está al día: se olvida lo que se ocultó a mano.
            let pend = Set(m.pendientes.map { "\($0.contratoId)|\(m.periodo.prefix(7))" } + atrasadas.map { "\($0.contratoId)|\($0.periodo.prefix(7))" })
            ocultos = ocultos.filter { pend.contains($0) }
            mes = m
            error = nil
            abrirPedido()
        } catch let e as ErrorApi { if mes == nil { error = e } } catch {}
    }

    /// `?registrar=1&contrato=<id>`: abre el cobro de ese contrato, o «¿De quién es el cobro?».
    private func abrirPedido() {
        guard registrar, !pedidoHecho, estado.escribe else { return }
        pedidoHecho = true
        if let contrato, let f = (deben + visibles).first(where: { $0.contratoId == contrato }) { cobrando = f.aCobrar } else { elegir = true }
    }
}

/// Registrar un cobro con el patrón del prototipo P: la fila se va al toque, queda el aviso con
/// «Deshacer» y el pedido va por detrás. Deshacer borra el cobro (vuelve la deuda); si el pedido
/// falla, la fila vuelve y el aviso ofrece «Reintentar». Sin señal, queda en la cola.
@MainActor
enum Cobrar {
    struct Cuerpo: Encodable {
        var periodo: String
        var monto: Double?
        var medio: String?
        var conceptos: [Cobro.Concepto]?
        var pagadoEl: String?
    }

    @discardableResult
    static func registrar(_ estado: Estado, _ a: ACobrar, monto: Double? = nil, medio: String? = nil, conceptos: [Cobro.Concepto] = [], pagadoEl: String? = nil,
                          texto: String = "Cobro registrado", ocultar: (() -> Void)? = nil, mostrar: (() -> Void)? = nil,
                          recibo: ((Cobro) -> Void)? = nil, alListo: ((Cobro) -> Void)? = nil) -> Task<Cobro?, Never> {
        ocultar?()
        let cuerpo = Cuerpo(periodo: String(a.periodo.prefix(7)), monto: conceptos.isEmpty ? monto : nil, medio: medio,
                            conceptos: conceptos.isEmpty ? nil : conceptos, pagadoEl: pagadoEl)
        let ruta = "/v1/contratos/\(a.contratoId)/cobros"
        let pedido = Task<Cobro, Error> { try await estado.api.enviar("POST", ruta, cuerpo) }
        let caja = CajaCobro()
        estado.avisar(texto) {
            caja.deshecho = true
            mostrar?()
            Task {
                if let c = try? await pedido.value {
                    do { try await estado.api.hacer("DELETE", "\(ruta)/\(c.id)") } catch { estado.avisar("No se pudo deshacer · \((error as? ErrorApi)?.detalle ?? "")", ok: false) }
                }
                estado.version += 1
            }
        }
        // El aviso muestra «Deshacer»; «Mandar recibo» queda en la fila de lo cobrado (VistaAviso
        // muestra una sola acción).
        _ = recibo
        return Task {
            do {
                let c = try await pedido.value
                if caja.deshecho { return nil }
                alListo?(c)
                Haptico.exito()
                estado.version += 1
                return c
            } catch let e as ErrorApi where e.sinConexion {
                if caja.deshecho { return nil }
                do {
                    try await estado.cola.enviar("POST", ruta, cuerpo, etiqueta: "Cobro de \(a.nombre ?? a.propiedad ?? "")")
                    estado.avisar("Sin señal · el cobro queda en cola")
                } catch { mostrar?(); estado.avisar(error) }
                return nil
            } catch {
                if caja.deshecho { return nil }
                mostrar?()
                let n = TextosCobro.primerNombre(a.nombre)
                let detalle = (error as? ErrorApi)?.detalle ?? ""
                estado.sugerir("No se guardó el cobro de \(n.isEmpty ? "este contrato" : n). \(detalle)", "Reintentar") {
                    _ = registrar(estado, a, monto: monto, medio: medio, conceptos: conceptos, pagadoEl: pagadoEl, texto: texto,
                              ocultar: ocultar, mostrar: mostrar, recibo: recibo, alListo: alListo)
                }
                return nil
            }
        }
    }
}

/// Si el cobro se deshizo antes de que vuelva el pedido.
@MainActor
final class CajaCobro { var deshecho = false }

/// «Recordar a todos» (23E): un WhatsApp por persona con su monto y su mes (uno solo aunque deba
/// varios meses), con la vista previa y el estado de cada envío. Con el WhatsApp de la inmobiliaria
/// conectado salen de a uno desde Corredor; sin él, cada fila abre su wa.me.
struct RecordarATodos: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var deudores: [FilaDeuda]
    enum EstadoEnvio { case esperando, mandando, enviado, error, sinTelefono }
    struct Persona: Identifiable { var id: String; var ds: [FilaDeuda]; var texto: String }
    @State private var estados: [String: EstadoEnvio] = [:]
    @State private var mandando = false
    @State private var conectado = false
    @State private var telefonos: [String: String] = [:]

    private var porPersona: [Persona] {
        var orden: [String] = []
        var m: [String: [FilaDeuda]] = [:]
        for d in deudores {
            let k = d.contactoId ?? d.id
            if m[k] == nil { orden.append(k) }
            m[k, default: []].append(d)
        }
        return orden.map { k in Persona(id: k, ds: m[k] ?? [], texto: texto(m[k] ?? [])) }
    }
    private var enviados: Int { porPersona.filter { estados[$0.id] == .enviado }.count }

    private func texto(_ ds: [FilaDeuda]) -> String {
        guard let d = ds.first else { return "" }
        if ds.count == 1 { return TextosCobro.recordatorio(nombre: d.nombre, periodo: d.periodo, importe: d.monto, moneda: d.moneda, vence: d.vence) }
        return TextosCobro.recordatorioVarios(nombre: d.nombre, meses: ds.map(\.periodo), total: ds.reduce(0) { $0 + $1.monto }, moneda: d.moneda)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(porPersona) { p in fila(p) }
                } header: {
                    Text("\(Formato.cantidad(porPersona.count, "persona", "personas")) · un WhatsApp a cada una, con su monto")
                }
            }
            .navigationTitle("Recordar a todos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
            .safeAreaInset(edge: .bottom) {
                if conectado {
                    Button {
                        if enviados == porPersona.count && enviados > 0 { cerrar() } else { Task { await mandarTodos() } }
                    } label: {
                        Text(mandando ? "Mandando \(enviados + 1) de \(porPersona.count)…" : (enviados == porPersona.count && enviados > 0 ? "Listo" : "Mandar a \(Formato.cantidad(porPersona.count, "persona", "personas"))"))
                    }
                    .buttonStyle(BotonPrincipal()).disabled(mandando).padding(16).background(C.fondo)
                } else {
                    Text("Sin el WhatsApp de la inmobiliaria conectado, cada uno se abre en tu WhatsApp.").estilo(.footnote).foregroundStyle(C.texto2)
                        .multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity).background(C.fondo)
                }
            }
            .task {
                conectado = await WhatsAppCorredor.conectado(estado.api)
                for p in porPersona {
                    guard let c = p.ds.first?.contactoId, telefonos[c] == nil else { continue }
                    let x: WhatsAppCorredor.Contacto? = try? await estado.api.get("/v1/contactos/\(c)")
                    if let t = x?.telefono?.nonEmpty { telefonos[c] = t }
                }
            }
        }
    }

    private func fila(_ p: Persona) -> some View {
        let d = p.ds.first
        let e = estados[p.id] ?? .esperando
        let tel = d?.contactoId.flatMap { telefonos[$0] }
        return HStack(alignment: .top, spacing: 10) {
            AvatarIniciales(nombre: d?.nombre ?? "?", tam: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(d?.nombre ?? "Sin inquilino").estilo(.filaLista).foregroundStyle(C.texto)
                Text(p.texto).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 4)
            Group {
                switch e {
                case .mandando: ProgressView()
                case .enviado: Image(systemName: "checkmark.circle.fill").foregroundStyle(C.azulTinta).accessibilityLabel("Enviado")
                case .error: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(C.error).accessibilityLabel("No salió")
                case .sinTelefono: Text("Sin contacto").estilo(.caption).foregroundStyle(C.texto3)
                case .esperando:
                    if !conectado {
                        Button(tel == nil ? "Sin teléfono" : "Abrir") { abrir(p, tel) }.font(Estilo.subheadFuerte.font).disabled(tel == nil)
                    }
                }
            }
        }
    }

    private func abrir(_ p: Persona, _ tel: String?) {
        guard let tel, let u = WhatsAppCorredor.waMe(tel, p.texto) else {
            let n = TextosCobro.primerNombre(p.ds.first?.nombre)
            estado.avisar("\(n.isEmpty ? "Esta persona" : n) no tiene teléfono cargado.", ok: false)
            return
        }
        UIApplication.shared.open(u)
        estados[p.id] = .enviado
    }

    private func mandarTodos() async {
        mandando = true
        var fallaron = 0
        for p in porPersona {
            guard let d = p.ds.first, estados[p.id] != .enviado else { continue }
            guard let c = d.contactoId else { estados[p.id] = .sinTelefono; continue }
            estados[p.id] = .mandando
            let total = p.ds.reduce(0) { $0 + $1.monto }
            do {
                let u = try await WhatsAppCorredor.mandar(estado.api, contactoId: c, texto: p.texto, para: "recordatorio",
                                                          parametros: [TextosCobro.primerNombre(d.nombre), p.ds.map { TextosCobro.nombreMes($0.periodo) }.joined(separator: " y "),
                                                                       Formato.plata(total, d.moneda), TextosCobro.fechaCortita(d.vence)])
                if let u { UIApplication.shared.open(u) }
                estados[p.id] = .enviado
            } catch {
                estados[p.id] = .error
                fallaron += 1
            }
        }
        mandando = false
        let ok = porPersona.filter { estados[$0.id] == .enviado }.count
        if fallaron > 0 {
            estado.avisar("Salieron \(ok) de \(porPersona.count). \(fallaron == 1 ? "Uno no salió" : "\(fallaron) no salieron"): probá de nuevo.", ok: false)
        } else {
            estado.avisar("Listo: \(Formato.cantidad(ok, "recordatorio enviado", "recordatorios enviados")).")
        }
    }
}
