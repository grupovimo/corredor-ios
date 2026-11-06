import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Lotes y masterplan de un emprendimiento

/// Crear lotes en serie (manzana, del 1 al 40, superficie, precio).
struct NuevosLotes: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var emprendimiento: String
    @State private var manzana = "A"
    @State private var desde = 1
    @State private var hasta = 20
    @State private var superficie: Double?
    @State private var frente: Double?
    @State private var fondo: Double?
    @State private var precio: Double?
    @State private var moneda = "USD"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Manzana", text: $manzana)
                Stepper("Desde el lote \(desde)", value: $desde, in: 1...999)
                Stepper("Hasta el lote \(hasta)", value: $hasta, in: desde...999)
                TextField("Superficie m²", value: $superficie, format: .number).keyboardType(.decimalPad)
                TextField("Frente m", value: $frente, format: .number).keyboardType(.decimalPad)
                TextField("Fondo m", value: $fondo, format: .number).keyboardType(.decimalPad)
                Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Precio", value: $precio, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Lotes en serie").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        Task {
                            struct C: Encodable { var manzana: String; var desde: Int; var hasta: Int; var superficie: Double?; var frente: Double?; var fondo: Double?; var precio: Double?; var moneda: String }
                            struct R: Decodable { var creados: Int?; var salteados: Int? }
                            do {
                                let r: R = try await estado.api.enviar("POST", "/v1/emprendimientos/\(emprendimiento)/lotes",
                                                                       C(manzana: manzana, desde: desde, hasta: hasta, superficie: superficie, frente: frente, fondo: fondo, precio: precio, moneda: moneda))
                                estado.avisar("Creamos \(Formato.cantidad(r.creados ?? 0, "lote", "lotes"))\((r.salteados ?? 0) > 0 ? " · \(r.salteados!) ya estaban" : "")")
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
        }
    }
}

/// El masterplan: el plano con cada lote marcado en el color de su estado. Tocando el plano se ubica el
/// lote elegido (como en el editor de la web).
struct MasterplanVista: View {
    @Environment(Estado.self) private var estado
    var emprendimiento: String
    var imagen: String?
    var unidades: [UnidadEmp]
    var elegido: String? = nil
    /// «disponible», «reservado» o «vendido»: lo demás se atenúa.
    var ver: String? = nil
    var alElegir: (String) -> Void = { _ in }
    @State private var marcas: [(String, Double, Double)] = []
    /// El archivo del plano como lo guarda la API: el PUT reemplaza el masterplan entero, así que
    /// va siempre (si no, mover una marca borraba el plano).
    @State private var imagenId: String?
    @State private var ubicando: String?
    @State private var plano: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TituloBloque(texto: "Masterplan")
                if estado.escribe {
                    PhotosPicker(selection: $plano, matching: .images) { Text(imagen == nil ? "Subir el plano" : "Cambiar el plano").font(Estilo.footnoteFuerte.font) }
                }
            }
            if let imagen, let u = URL(string: imagen) {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { C.hundida }
                        ForEach(marcas, id: \.0) { m in
                            let p = unidades.first { $0.id == m.0 }
                            let v = p?.vista ?? "disponible"
                            Text(p?.lote ?? "").font(.system(size: 9, weight: .bold)).foregroundStyle(v == "vendido" ? .white : C.texto)
                                .frame(width: 22, height: 22).background(Self.color(v), in: Circle())
                                .overlay(Circle().stroke(elegido == m.0 ? C.oro : .white, lineWidth: elegido == m.0 ? 3 : 2))
                                .opacity(ver != nil && ver != v ? 0.3 : 1)
                                .position(x: g.size.width * m.1 / 100, y: g.size.height * m.2 / 100)
                                .onTapGesture { alElegir(m.0) }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { punto in
                        guard let id = ubicando else { return }
                        marcas.removeAll { $0.0 == id }
                        marcas.append((id, Double(punto.x / g.size.width * 100), Double(punto.y / g.size.height * 100)))
                        ubicando = nil
                        Task { await guardar() }
                    }
                }
                .aspectRatio(1.4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                if estado.escribe {
                    Picker("Ubicar un lote", selection: Binding(get: { ubicando ?? "" }, set: { ubicando = $0.nonEmpty })) {
                        Text("Elegí un lote para ubicarlo").tag("")
                        ForEach(unidades) { Text($0.nombre(loteo: true)).tag($0.id) }
                    }
                    if ubicando != nil { Text("Tocá el plano donde está el lote.").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                }
            }
        }
        .task {
            struct E: Decodable { struct M: Decodable { struct Marca: Decodable { var propiedadId: String; var x: Double; var y: Double }; var imagen: String?; var lotes: [Marca]? }; var masterplan: M? }
            if let e: E = try? await estado.api.get("/v1/emprendimientos/\(emprendimiento)") {
                marcas = (e.masterplan?.lotes ?? []).map { ($0.propiedadId, $0.x, $0.y) }
                imagenId = e.masterplan?.imagen
            }
        }
        .onChange(of: plano) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self), let a = try? await estado.api.subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "plano.jpg", tipo: "image/jpeg", uso: "foto") {
                    await guardar(imagen: a.id)
                    estado.version += 1
                }
                plano = nil
            }
        }
    }

    /// Los colores de la grilla: disponible verde claro, reservado oro, vendido gris oscuro.
    static func color(_ vista: String) -> Color {
        switch vista {
        case "vendido": return C.texto2
        case "reservado": return C.oro
        default: return C.okFondo
        }
    }

    private func guardar(imagen nueva: String? = nil) async {
        struct Marca: Encodable { var propiedadId: String; var x: Double; var y: Double }
        struct C: Encodable { var imagen: String?; var lotes: [Marca] }
        do {
            try await estado.api.hacer("PUT", "/v1/emprendimientos/\(emprendimiento)/masterplan", C(imagen: nueva ?? imagenId, lotes: marcas.map { Marca(propiedadId: $0.0, x: $0.1, y: $0.2) }))
            if let nueva { imagenId = nueva }
        } catch { estado.avisar(error) }
    }
}

/// Un emprendimiento (GET /v1/emprendimientos, /{id}; dominio/emprendimientos.Emprendimiento).
struct EmprendimientoAPI: Codable, Identifiable, Hashable {
    struct Cuentas: Codable, Hashable { var total = 0; var disponibles = 0; var reservadas = 0; var vendidas = 0 }
    var id: String
    var slug: String?
    var nombre: String
    var masterplanUrl: String?
    var tipo: String?
    var estado: String?
    var descripcion: String?
    var direccion: String?
    var barrio: String?
    var avance: Double?
    var entrega: String?
    var desarrolladora: String?
    var precioDesde: Double?
    var moneda: String?
    var publicado: Bool?
    var fotosUrl: [String]?
    var unidades: Cuentas?

    var esLoteo: Bool { tipo == "loteo" || tipo == "barrio_cerrado" }

    /// «entrega dic. 2027».
    var entregaTexto: String? {
        guard let e = entrega else { return nil }
        let p = e.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2, (1...12).contains(p[1]) else { return nil }
        let meses = ["ene.", "feb.", "mar.", "abr.", "may.", "jun.", "jul.", "ago.", "sep.", "oct.", "nov.", "dic."]
        return "entrega \(meses[p[1] - 1]) \(p[0])"
    }
}

/// Una unidad (lote o departamento) de un emprendimiento (GET /v1/emprendimientos/{id}/unidades).
struct UnidadEmp: Codable, Identifiable, Hashable {
    var id: String
    var numero: Int?
    var titulo: String?
    var tipo: String?
    var operacion: String?
    var estado: String?
    var precio: Double?
    var moneda: String?
    var superficie: Double?
    var ambientes: Int?
    var manzana: String?
    var lote: String?
    var piso: Int?
    var depto: String?
    var agenteId: String?
    var fotoUrl: String?

    /// Vendida o alquilada cuentan como vendido; suspendida, como reservada (no se ofrece).
    var vista: String {
        switch estado {
        case "vendida", "alquilada": return "vendido"
        case "reservada", "suspendida": return "reservado"
        default: return "disponible"
        }
    }
    static let nombresVista = ["disponible": "Disponible", "reservado": "Reservado", "vendido": "Vendido"]

    /// Piso y depto: de la ficha o, si no vino, del título («5.º B · Cabildo 3100»).
    var pisoDepto: (Int?, String) {
        if let piso { return (piso, depto ?? "") }
        if let t = titulo, let r = t.range(of: #"^(\d+)\s*\.?\s*º\s*([A-Za-z0-9]+)"#, options: .regularExpression) {
            let s = String(t[r])
            let n = Int(s.prefix { $0.isNumber }) ?? 0
            let d = s.components(separatedBy: "º").last?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
            return (n, d)
        }
        return (nil, lote ?? numero.map(String.init) ?? "")
    }

    /// «Lote 21» o «5.º B».
    func nombre(loteo: Bool) -> String {
        if loteo { return "Lote \(lote ?? numero.map(String.init) ?? "")" }
        let (p, d) = pisoDepto
        return p.map { "\($0).º \(d)" } ?? (titulo ?? "Unidad")
    }

    var precioTexto: String { precio.map { Formato.plata($0, moneda ?? "USD") } ?? "Consultar" }

    static func tono(_ vista: String) -> Tono { vista == "vendido" ? .neutro : vista == "reservado" ? .oro : .verde }
}

/// Emprendimientos: la lista, cada uno con su avance y la cuenta de lotes o unidades.
struct Emprendimientos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [EmprendimientoAPI]?
    @State private var error: ErrorApi?
    @State private var nuevo = false
    @State private var nombre = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty {
                        EstadoVacio(icono: "building", titulo: "Así se va a ver tu primer loteo",
                                    texto: "Con el masterplan de lotes o las unidades por piso, y cuánto se vendió. Cargá las unidades como propiedades y sumalas al emprendimiento.",
                                    accion: estado.escribe ? ("Cargar propiedad", { estado.abrir(AAltaPropiedad()) }) : nil,
                                    secundaria: estado.escribe ? ("Cargar emprendimiento", { nuevo = true }) : nil)
                            .padding(.top, 40)
                    }
                    ForEach(lista) { e in
                        NavigationLink(value: ASeccion(clave: "emprendimiento", id: e.id)) {
                            HStack(spacing: 12) {
                                Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                    Text([e.barrio, e.entregaTexto, e.precioDesde.map { "desde \(Formato.plata($0, e.moneda ?? "USD"))" }].compactMap { $0 }.joined(separator: " · "))
                                        .estilo(.footnote).foregroundStyle(C.texto2)
                                    if let u = e.unidades {
                                        Text("\(Formato.numero(u.total)) \(e.esLoteo ? "lotes" : "unid.") · \(u.disponibles) disp. · \(u.reservadas) res. · \(u.vendidas) vend.")
                                            .font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2)
                                    }
                                    if let a = e.avance, a > 0 { ProgressView(value: a / 100).tint(C.oro).padding(.top, 4) }
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(10).tarjeta()
                        }
                        .buttonStyle(Presionable())
                    }
                } else if let error {
                    EstadoError(que: "los emprendimientos", error: error) { Task { await cargar() } }.padding(.top, 40)
                } else { EsqueletoFilas(filas: 3, miniatura: 72) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Emprendimientos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo emprendimiento") } }
        .task(id: estado.version) { await cargar() }
        .alert("Emprendimiento nuevo", isPresented: $nuevo) {
            TextField("Nombre", text: $nombre)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") {
                Task {
                    // La API acepta preventa, en_obra o terminado (emprendimientos.Estados).
                    struct C: Encodable { var nombre: String; var tipo = "edificio"; var estado = "preventa" }
                    do {
                        try await estado.api.hacer("POST", "/v1/emprendimientos", C(nombre: nombre))
                        nombre = ""
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        }
    }

    private func cargar() async {
        do {
            lista = try await estado.api.get("/v1/emprendimientos", query: [.init(name: "limite", value: "50")])
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }
}

/// 12E/12C Un emprendimiento: el masterplan es la pantalla. Loteo: la grilla de lotes (de a 8 por fila,
/// con la calle al medio) o el plano con los lotes encima; edificio: una fila por piso. Tocá un lote y
/// abajo aparece su ficha con la acción (reservar, ver la reserva o la operación) y «Mandar por
/// WhatsApp». Arriba, la leyenda con las cuentas y lo vendido; «Ver» atenúa lo que no es de ese estado.
struct FichaEmprendimiento: View {
    @Environment(Estado.self) private var estado
    @State var id: String
    @State private var e: EmprendimientoAPI?
    @State private var lista: [EmprendimientoAPI] = []
    @State private var unidades: [UnidadEmp] = []
    @State private var senales: [String: Senal] = [:]
    @State private var reservas: [String: ReservaAPI] = [:]
    @State private var error: ErrorApi?
    @State private var elegidoId: String?
    @State private var ver: String?
    @State private var lotes = false
    @State private var reservando: UnidadEmp?
    @State private var web: String?
    @State private var buscando = false

    private var loteo: Bool {
        guard let e else { return false }
        if e.esLoteo { return true }
        if e.tipo == "edificio" { return false }
        return unidades.contains { $0.lote != nil }
    }
    private var elegida: UnidadEmp? { unidades.first { $0.id == elegidoId } ?? unidades.first { $0.vista == "disponible" } ?? unidades.first }
    private var cuenta: [String: Int] { Dictionary(grouping: unidades, by: \.vista).mapValues(\.count) }

    var body: some View {
        ScrollView {
            if let e {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(e)
                    if unidades.isEmpty {
                        EstadoVacio(icono: "building.2", titulo: loteo ? "Así se va a ver el masterplan" : "Así se van a ver las unidades",
                                    texto: "Cada \(loteo ? "lote" : "unidad") es una propiedad del emprendimiento. Cargalas y aparecen acá con su estado.",
                                    accion: estado.escribe ? ("Cargar propiedad", { estado.abrir(AAltaPropiedad()) }) : nil,
                                    secundaria: estado.escribe && loteo ? ("Crear lotes en serie", { lotes = true }) : nil)
                    } else {
                        leyenda
                        filtroVer
                        paraHacer
                        masterplan(e)
                        if let u = elegida { fichaUnidad(u, e) }
                    }
                    if let a = e.avance, a > 0 {
                        TarjetaAvance(titulo: "Avance de obra", cifra: "\(Int(a)) %", avance: a / 100, degrade: [Color(hex: 0xE9AD44), Color(hex: 0xF2BB57)],
                                      pie: e.entrega.map { "Entrega: \($0)" } ?? "Sin fecha de entrega")
                    }
                    if let d = e.descripcion { Text(d).estilo(.body16).foregroundStyle(C.texto) }
                    if estado.escribe, loteo, !unidades.isEmpty { Button("Crear lotes en serie") { lotes = true }.buttonStyle(BotonHundido()) }
                }
                .padding(16)
            } else if let error {
                EstadoError(que: "el emprendimiento", error: error) { Task { await cargar() } }.padding(.top, 60)
            } else { ProgressView().padding(.top, 60).frame(maxWidth: .infinity) }
        }
        .refreshable { await cargar() }
        .pantallaApilada(e?.nombre ?? "Emprendimiento")
        .sheet(isPresented: $lotes) { NuevosLotes(emprendimiento: id) }
        .sheet(item: $reservando) { u in
            NuevaReservaVenta(propiedadId: u.id, titulo: u.nombre(loteo: loteo), moneda: u.moneda ?? "USD") { r in reservada(u, r) }
        }
        .task(id: "\(estado.version)-\(id)") { await cargar() }
    }

    private func cabecera(_ e: EmprendimientoAPI) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if lista.count > 1 {
                Menu {
                    ForEach(lista) { x in
                        Button("\(x.nombre) · \(Formato.numero(x.unidades?.total ?? 0)) \(x.esLoteo ? "lotes" : "unid.")") { elegidoId = nil; ver = nil; id = x.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Emprendimientos · \(lista.count)").estilo(.footnoteFuerte)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(C.accion)
                }
            }
            ZStack(alignment: .bottomLeading) {
                Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(height: 180).frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.nombre)\(e.barrio.map { " · \($0)" } ?? "")").estilo(.titulo3)
                    let sub = [e.barrio, e.entregaTexto, e.precioDesde.map { "desde \(Formato.plata($0, e.moneda ?? "USD"))" }].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).estilo(.footnote) }
                }
                .foregroundStyle(.white).padding(14)
            }
            .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
            if let x = [e.direccion, e.desarrolladora].compactMap({ $0 }).joined(separator: " · ").nonEmpty {
                Text(x).estilo(.subhead).foregroundStyle(C.texto2)
            }
        }
    }

    private var leyenda: some View {
        let vendidas = unidades.filter { $0.vista == "vendido" }
        let monto = vendidas.reduce(0.0) { $0 + ($1.precio ?? 0) }
        let moneda = unidades.first { $0.precio != nil }?.moneda ?? e?.moneda ?? "USD"
        let pct = unidades.isEmpty ? 0 : Double(vendidas.count) / Double(unidades.count) * 100
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                ForEach(["disponible", "reservado", "vendido"], id: \.self) { k in
                    HStack(spacing: 5) {
                        cuadro(k, tam: 14)
                        (Text("\(UnidadEmp.nombresVista[k] ?? k) ").foregroundColor(C.texto2) + Text("\(cuenta[k] ?? 0)").bold()).estilo(.footnote)
                    }
                }
            }
            Text("Vendido el \(Formato.porcentaje(pct.rounded()))\(monto > 0 ? " · \(Formato.plata(monto, moneda)) en \(loteo ? "lotes" : "unidades") vendidos" : "")")
                .estilo(.footnoteFuerte).foregroundStyle(C.texto)
        }
    }

    /// Liso disponible, rayado reservado, lleno con tilde vendido.
    @ViewBuilder
    private func cuadro(_ vista: String, tam: CGFloat) -> some View {
        switch vista {
        case "vendido":
            Image(systemName: "checkmark").font(.system(size: tam * 0.6, weight: .bold)).foregroundStyle(.white)
                .frame(width: tam, height: tam).background(C.texto2, in: .rect(cornerRadius: 3))
        case "reservado":
            Rayado(paso: 2).frame(width: tam, height: tam).clipShape(.rect(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(C.oro, lineWidth: 1.5))
        default:
            RoundedRectangle(cornerRadius: 3).fill(C.okFondo).frame(width: tam, height: tam)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(C.okTinta.opacity(0.5), lineWidth: 1))
        }
    }

    private var filtroVer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipFiltro(texto: loteo ? "Todos los lotes · \(unidades.count)" : "Todas las unidades · \(unidades.count)", activo: ver == nil) { ver = nil }
                ChipFiltro(texto: "Disponibles · \(cuenta["disponible"] ?? 0)", activo: ver == "disponible") { ver = "disponible" }
                ChipFiltro(texto: "Reservados · \(cuenta["reservado"] ?? 0)", activo: ver == "reservado") { ver = "reservado" }
                ChipFiltro(texto: "Vendidos · \(cuenta["vendido"] ?? 0)", activo: ver == "vendido") { ver = "vendido" }
            }
        }
    }

    /// Las reservas del emprendimiento que vencen («vence hoy / mañana / en N días»).
    @ViewBuilder
    private var paraHacer: some View {
        let vencen = reservas.values.filter { $0.venceEl != nil }.sorted { ($0.venceEl ?? "") < ($1.venceEl ?? "") }.prefix(5)
        if !vencen.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Para hacer")
                VStack(spacing: 0) {
                    ForEach(Array(vencen.enumerated()), id: \.element.id) { i, r in
                        let n = r.faltan ?? 0
                        Button { estado.abrir(AReserva(id: r.id)) } label: {
                            HStack(spacing: 12) {
                                IconoTono(icono: "hourglass", tono: .oro, tam: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.propiedadTitulo ?? "Reserva").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                    Text(n < 0 ? "La reserva venció" : n == 0 ? "La reserva vence hoy" : n == 1 ? "La reserva vence mañana" : "Vence en \(n) días")
                                        .estilo(.footnote).foregroundStyle(n <= 1 ? C.avisoTinta : C.texto2)
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
        }
    }

    // MARK: Masterplan

    @ViewBuilder
    private func masterplan(_ e: EmprendimientoAPI) -> some View {
        if loteo {
            if e.masterplanUrl != nil {
                MasterplanVista(emprendimiento: id, imagen: e.masterplanUrl, unidades: unidades, elegido: elegida?.id, ver: ver) { elegidoId = $0 }
            } else {
                grillaLotes(e)
            }
        } else {
            pisos
        }
    }

    private func botonUnidad(_ u: UnidadEmp, _ texto: String, ancho: CGFloat? = nil) -> some View {
        let v = u.vista
        let elegido = elegida?.id == u.id
        return Button { Haptico.seleccion(); elegidoId = u.id } label: {
            HStack(spacing: 2) {
                Text(texto).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).lineLimit(1).minimumScaleFactor(0.7)
                if v == "vendido" { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .foregroundStyle(v == "vendido" ? .white : C.texto)
            .frame(maxWidth: ancho == nil ? .infinity : nil).frame(width: ancho, height: 38)
            .background {
                switch v {
                case "vendido": C.texto2
                case "reservado": Rayado(paso: 3)
                default: C.okFondo
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(elegido ? C.oro : (v == "reservado" ? C.oro.opacity(0.6) : .clear), lineWidth: elegido ? 2.5 : 1))
            .opacity(ver != nil && ver != v ? 0.3 : 1)
        }
        .buttonStyle(Presionable())
        .accessibilityLabel("\(u.nombre(loteo: loteo)), \((UnidadEmp.nombresVista[v] ?? v).lowercased())")
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    /// La grilla de lotes: de a 8 por fila, con la calle al medio cuando hay cuatro filas o más.
    private func grillaLotes(_ e: EmprendimientoAPI) -> some View {
        let filas = stride(from: 0, to: unidades.count, by: 8).map { Array(unidades[$0..<min($0 + 8, unidades.count)]) }
        let corte = filas.count >= 4 ? Int((Double(filas.count) / 2).rounded(.up)) : -1
        return VStack(spacing: 4) {
            ForEach(Array(filas.enumerated()), id: \.offset) { i, fila in
                if i == corte {
                    Text((e.direccion ?? "Calle").uppercased()).font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).tracking(1.5)
                        .foregroundStyle(C.texto3).frame(maxWidth: .infinity, minHeight: 26).background(C.hundida, in: .rect(cornerRadius: 4))
                }
                HStack(spacing: 4) {
                    ForEach(fila) { u in botonUnidad(u, u.lote ?? u.numero.map(String.init) ?? "") }
                    if fila.count < 8 { ForEach(0..<(8 - fila.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 38) } }
                }
            }
        }
        .padding(10).tarjeta()
    }

    /// Un edificio, de arriba hacia abajo: una fila por piso y una caja por depto.
    private var pisos: some View {
        var m: [Int: [UnidadEmp]] = [:]
        for u in unidades { m[u.pisoDepto.0 ?? -1, default: []].append(u) }
        let orden = m.keys.sorted(by: >)
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(orden, id: \.self) { piso in
                    HStack(spacing: 4) {
                        Text(piso >= 0 ? "\(piso).º" : "—").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2).frame(width: 34, alignment: .leading)
                        ForEach((m[piso] ?? []).sorted { $0.pisoDepto.1.localizedStandardCompare($1.pisoDepto.1) == .orderedAscending }) { u in
                            botonUnidad(u, u.pisoDepto.1, ancho: 52)
                        }
                    }
                }
            }
            .padding(10)
        }
        .tarjeta()
    }

    // MARK: Ficha de la unidad

    private func nota(_ u: UnidadEmp) -> String {
        switch u.vista {
        case "reservado":
            guard let r = reservas[u.id] else { return "Reservado. La reserva no está cargada en Corredor: miralo en la ficha." }
            let sena = r.sena.map { " · seña \(Formato.plata($0, r.senaMoneda ?? "USD"))" } ?? ""
            var vence = ""
            if let n = r.faltan { vence = n < 0 ? " · venció" : n == 0 ? " · vence hoy" : n == 1 ? " · vence mañana" : " · vence el \(ReservaAPI.corta(r.venceEl))" }
            return "Reservado por \(r.quien)\(sena)\(vence)."
        case "vendido": return "Vendido. La operación tiene el boleto y las cuotas."
        default:
            let n = senales[u.id]?.interesados ?? 0, v = senales[u.id]?.vistasSemana ?? 0
            if n > 0 { return "\(Formato.cantidad(n, "interesado lo consulta", "interesados lo consultan"))\(v > 0 ? " · \(Formato.cantidad(v, "vista", "vistas")) en la web esta semana" : "")." }
            if v > 0 { return "\(Formato.cantidad(v, "vista", "vistas")) en la web esta semana." }
            return "Nadie lo consultó todavía. Mandalo a quien busque algo así."
        }
    }

    private func fichaUnidad(_ u: UnidadEmp, _ e: EmprendimientoAPI) -> some View {
        let v = u.vista
        let sub = loteo ? u.manzana.map { "Manzana \($0)" } : u.ambientes.map { "\($0) amb" }
        let cta = v == "vendido" ? ("Ver la operación", "doc.text") : v == "reservado" ? ("Ver la reserva", "bookmark") : (loteo ? "Reservar este lote" : "Reservar", "bookmark.fill")
        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Foto(url: u.fotoUrl.flatMap(URL.init(string:))).frame(height: 140).frame(maxWidth: .infinity)
                let t = UnidadEmp.tono(v)
                Text(UnidadEmp.nombresVista[v] ?? v).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(t.tinta)
                    .padding(.horizontal, 9).frame(height: 24).background(t.fondo, in: Capsule()).padding(10)
            }
            .clipShape(.rect(cornerRadius: 14))
            HStack(alignment: .firstTextBaseline) {
                Text(u.nombre(loteo: loteo)).estilo(.titulo3).foregroundStyle(C.texto)
                if let sub { Text(sub).estilo(.subhead).foregroundStyle(C.texto2) }
            }
            HStack(spacing: 8) {
                caja("Superficie", u.superficie.map { "\(Formato.numero(Int($0))) m²" } ?? "—")
                caja("Precio", u.precioTexto)
            }
            Text(nota(u)).estilo(.subhead).foregroundStyle(C.texto2)
            if estado.escribe || v != "disponible" {
                Button { Task { await accion(u) } } label: { Label(buscando ? "Buscando…" : cta.0, systemImage: cta.1) }
                    .buttonStyle(BotonPrincipal()).disabled(buscando)
            }
            Button { mandar(u, e) } label: { Label("Mandar \(loteo ? "el lote" : "la unidad") por WhatsApp", systemImage: "square.and.arrow.up") }
                .buttonStyle(BotonHundido())
            Button("La ficha de la propiedad") { estado.abrir(AFichaPropiedad(id: u.id)) }.estilo(.footnoteFuerte).foregroundStyle(C.accion)
        }
        .padding(14).tarjeta()
    }

    private func caja(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).estilo(.footnote).foregroundStyle(C.texto2)
            Text(v).estilo(.subheadFuerte).foregroundStyle(C.texto)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(C.hundida, in: .rect(cornerRadius: 12))
    }

    private func accion(_ u: UnidadEmp) async {
        switch u.vista {
        case "disponible": reservando = u
        case "reservado":
            if let r = reservas[u.id] { estado.abrir(AReserva(id: r.id)) } else { estado.abrir(AFichaPropiedad(id: u.id)) }
        default:
            buscando = true
            defer { buscando = false }
            let ops: [Operacion] = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "propiedad", value: u.id)])) ?? []
            if let o = ops.first { estado.abrir(AFichaOperacion(id: o.id)) } else { estado.abrir(AFichaPropiedad(id: u.id)) }
        }
    }

    private func mandar(_ u: UnidadEmp, _ e: EmprendimientoAPI) {
        let link = e.publicado == true ? web.map { "\($0)/emprendimientos/\(e.slug ?? e.id)" } : nil
        let sub = loteo ? u.manzana.map { " · Manzana \($0)" } ?? "" : ""
        let texto = ["\(u.nombre(loteo: loteo))\(sub) · \(e.nombre)", u.superficie.map { "\(Formato.numero(Int($0))) m²" }, u.precioTexto, link]
            .compactMap { $0 }.joined(separator: "\n")
        Afuera.whatsapp(nil, texto: texto)
    }

    /// Recién reservado: aviso con deshacer (cierra la reserva como caída).
    private func reservada(_ u: UnidadEmp, _ r: ReservaAPI) {
        let antes = u.estado
        if let i = unidades.firstIndex(where: { $0.id == u.id }) { unidades[i].estado = "reservada" }
        reservas[u.id] = r
        estado.avisar("\(u.nombre(loteo: loteo)) reservado · vence el \(r.venceEl.map { ReservaAPI.corta($0) } ?? "—")") {
            if let i = unidades.firstIndex(where: { $0.id == u.id }) { unidades[i].estado = antes }
            reservas[u.id] = nil
            Task {
                struct C: Encodable { var resultado = "caida"; var motivo = "Deshecha al crearla" }
                do { try await estado.api.hacer("POST", "/v1/reservas/\(r.id)/cerrar", C()); estado.version += 1 }
                catch { estado.avisar(error) }
            }
        }
    }

    private func cargar() async {
        do {
            let x: EmprendimientoAPI = try await estado.api.get("/v1/emprendimientos/\(id)")
            e = x
            error = nil
            unidades = (try? await estado.api.get("/v1/emprendimientos/\(id)/unidades")) ?? []
            lista = (try? await estado.api.get("/v1/emprendimientos", query: [.init(name: "limite", value: "50")])) ?? lista
            if let s = try? await Senal.de(unidades.map(\.id), api: estado.api) { senales = s }
            let rs: [ReservaAPI] = (try? await estado.api.get("/v1/reservas", query: [.init(name: "estado", value: "activa"), .init(name: "limite", value: "200")])) ?? []
            let deEste = Set(unidades.map(\.id))
            reservas = Dictionary(rs.filter { deEste.contains($0.propiedadId) }.map { ($0.propiedadId, $0) }, uniquingKeysWith: { a, _ in a })
            if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        } catch let e as ErrorApi { error = e } catch {}
    }
}
