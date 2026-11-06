import PhotosUI
import SwiftUI

/// Una reserva de temporario (GET /v1/temporada/reservas, …/{id}; dominio/temporada.Reserva).
struct ReservaTemporada: Codable, Identifiable, Hashable {
    struct Checkin: Codable, Hashable {
        var saldo = false
        var deposito = false
        var inventario = false
        var dni: [String] = []
    }
    var id: String
    var propiedadId: String?
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var huespedNombre: String?
    var huespedTelefono: String?
    var huespedes: Int?
    var entrada: String
    var salida: String
    var estado: String?
    var monto: Double?
    var moneda: String?
    var sena: Double?
    var saldo: Double?
    var noches: Int?
    var notas: String?
    var checkin: Checkin?
    var llavesEn: Date?
    /// huesped · dueno (uso del dueño: las noches bloqueadas, sin huésped ni plata).
    var motivo: String?
    var quien: String { contactoNombre ?? huespedNombre ?? "Huésped" }
    var deDueno: Bool { motivo == "dueno" }
}

/// GET /v1/temporada/calendario: por casa, las reservas que caen en la ventana y las noches tomadas.
struct CalendarioTemporada: Codable {
    struct Ocupacion: Codable, Hashable, Identifiable {
        var id: String
        var entrada: String
        var salida: String
        var estado: String
        var huesped: String?
        var motivo: String?
    }
    struct Casa: Codable, Hashable, Identifiable {
        var id: String
        var numero: Int?
        var titulo: String?
        var nochesOcupadas: Int
        var ocupacion: Double?
        var reservas: [Ocupacion]
    }
    var desde: String
    var hasta: String
    var dias: Int?
    var propiedades: [Casa]
}

/// Una casa de temporario con lo que hace falta para el calendario, las reservas y las tarifas.
struct CasaTemporada: Identifiable, Hashable {
    var id: String
    var direccion: String
    var foto: URL?
    var ambientes: Int?
    var destaque: String?
    var huespedes: Int?
    var ciudad: String?
    var precio: Double?
    var moneda: String
    var periodo: String?
    var nochesOcupadas: Int
    var reservas: [CalendarioTemporada.Ocupacion]
    var tarifas: [TarifaAPI]
}

/// Las fechas sin hora del temporario (web: temp-fechas.ts): sumar días, contar noches, la tarifa de
/// cada noche, la cotización y los huecos.
enum TempFechas {
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private static func fecha(_ d: String) -> Date? {
        let p = d.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    private static func texto(_ f: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: f)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func sumarDias(_ d: String, _ n: Int) -> String {
        guard let f = fecha(d), let g = utc.date(byAdding: .day, value: n, to: f) else { return d }
        return texto(g)
    }

    /// Noches entre la entrada y la salida (la salida no cuenta).
    static func noches(_ entrada: String, _ salida: String) -> Int {
        guard let a = fecha(entrada), let b = fecha(salida) else { return 0 }
        return utc.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// 0 domingo … 6 sábado.
    static func diaSemana(_ d: String) -> Int { fecha(d).map { utc.component(.weekday, from: $0) - 1 } ?? 0 }
    static let inicialDia = Array("DLMMJVS")
    private static let mesesNombre = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// «Diciembre – enero», «Noviembre».
    static func meses(_ desde: String, _ hasta: String) -> String {
        let a = (Int(desde.dropFirst(5).prefix(2)) ?? 1) - 1, b = (Int(hasta.dropFirst(5).prefix(2)) ?? 1) - 1
        let t = a == b ? mesesNombre[a] : "\(mesesNombre[a]) – \(mesesNombre[b])"
        return Formato.mayuscula(t)
    }

    /// La temporada de verano: «2026‑27» de julio a junio (con guion que no corta).
    static func temporadaDe(_ d: String) -> String {
        let y = Int(d.prefix(4)) ?? 2026, m = Int(d.dropFirst(5).prefix(2)) ?? 1
        let desde = m >= 7 ? y : y - 1
        return "\(desde)\u{2011}\(String(format: "%02d", (desde + 1) % 100))"
    }

    /// «12/1».
    static func corto(_ d: String) -> String { "\(Int(d.dropFirst(8).prefix(2)) ?? 0)/\(d.dropFirst(5).prefix(2))" }

    /// La tarifa que rige una noche (la última cargada gana si se pisan).
    static func tarifaDe(_ ts: [TarifaAPI], _ d: String) -> TarifaAPI? {
        var t: TarifaAPI?
        for x in ts where x.desde <= d && d <= x.hasta { t = x }
        return t
    }

    static func porNoche(_ t: TarifaAPI) -> Double {
        switch t.periodo ?? "temporada" {
        case "semana": return t.precio / 7
        case "quincena": return t.precio / 15
        case "mes": return t.precio / 30
        case "temporada": return t.precio / Double(max(1, noches(t.desde, sumarDias(t.hasta, 1))))
        default: return t.precio
        }
    }

    struct Cotizacion { var noches: Int; var total: Double?; var moneda: String; var temporada: String?; var minimo: Int? }

    /// Cuánto sale una estadía: noche por noche la tarifa que rige; las noches sin tarifa van al precio
    /// por noche de la casa (`base`), si tiene.
    static func cotizar(_ ts: [TarifaAPI], _ entrada: String, _ salida: String, base: (Double?, String)?) -> Cotizacion {
        let n = noches(entrada, salida)
        var total = 0.0
        var falta = false
        var moneda = base?.1 ?? ts.first?.moneda ?? "USD"
        var cuenta: [String: Int] = [:]
        var minimo: Int?
        for i in 0..<max(0, n) {
            let d = sumarDias(entrada, i)
            if let t = tarifaDe(ts, d) {
                total += porNoche(t)
                moneda = t.moneda ?? moneda
                cuenta[t.nombre ?? "", default: 0] += 1
                if let m = t.nochesMinimas, n < m { minimo = max(minimo ?? 0, m) }
            } else if let p = base?.0 { total += p } else { falta = true }
        }
        let temporada = cuenta.sorted { $0.value > $1.value }.first?.key.nonEmpty
        return Cotizacion(noches: n, total: falta ? nil : total.rounded(), moneda: moneda, temporada: temporada, minimo: minimo)
    }

    /// Los huecos libres de menos de `max` noches entre reservas, dentro de la ventana.
    static func huecos(_ rs: [CalendarioTemporada.Ocupacion], _ desde: String, _ hasta: String, max tope: Int = 4) -> Int {
        let r = rs.sorted { $0.entrada < $1.entrada }
        var n = 0
        for i in r.indices.dropFirst() {
            let libre = noches(r[i - 1].salida, r[i].entrada)
            if libre > 0, libre < tope, r[i - 1].salida >= desde, r[i].entrada <= hasta { n += 1 }
        }
        return n
    }
}

/// Lo que abre la hoja de una reserva nueva: la casa y las fechas ya puestas.
struct PedidoReservaTemporada: Identifiable { var casa: String; var entrada: String; var salida: String; var id: String { casa + entrada } }

/// 15E Alquiler temporario: «¿qué casa está libre y cuánto cobro esa semana?». Una fila por casa y 31
/// días a lo ancho (con las reservas, el uso del dueño, hoy, los fines de semana y la temporada de
/// cada día); tocar un día libre reserva desde ese día. Arriba, lo de hoy (check-in y check-out) y
/// las señas pendientes; abajo, la lista de las reservas.
struct Temporada: View {
    @Environment(Estado.self) private var estado
    @State private var desde = Formato.diaISO(Date())
    @State private var cal: CalendarioTemporada?
    @State private var casas: [CasaTemporada] = []
    @State private var deHoy: [ReservaTemporada] = []
    @State private var reservas: [ReservaTemporada] = []
    @State private var error: ErrorApi?
    @State private var filtro = 0
    @State private var nueva: PedidoReservaTemporada?
    @State private var tarifas = false

    private static let dias = 31
    private static let ancho: CGFloat = 34
    private var hoy: String { Formato.diaISO(Date()) }
    private var hasta: String { TempFechas.sumarDias(desde, Self.dias - 1) }
    private var ventana: [String] { (0..<Self.dias).map { TempFechas.sumarDias(desde, $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if cal != nil {
                    cabecera
                    if casas.isEmpty {
                        EstadoVacio(icono: "beach.umbrella", titulo: "Todavía no hay casas de temporada",
                                    texto: "Una propiedad aparece acá cuando su operación es temporario o cuando además se alquila por temporada.",
                                    accion: estado.escribe ? ("Cargar propiedad", { estado.abrir(AAltaPropiedad()) }) : nil)
                            .padding(.top, 20)
                    } else {
                        hoyBloque
                        leyenda
                        calendario
                        Text(Formato.sinViudas("Tocá un día libre de una casa para reservar desde ese día."))
                            .estilo(.footnote).foregroundStyle(C.texto2)
                        lista
                    }
                } else if let error {
                    EstadoError(que: "la temporada", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Temporada")
        .toolbar {
            if estado.escribe, !casas.isEmpty {
                Button("Tarifas") { tarifas = true }
                Button { nueva = PedidoReservaTemporada(casa: casas.first?.id ?? "", entrada: hoy, salida: TempFechas.sumarDias(hoy, 3)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nueva reserva")
            }
        }
        .task(id: "\(estado.version)-\(desde)") { await cargar() }
        .sheet(item: $nueva) { n in NuevaReservaTemporada(casas: casas, casa: n.casa, entrada: n.entrada, salida: n.salida).hojaTLW([.large]) }
        .sheet(isPresented: $tarifas) { HojaTarifasTemporada(casas: casas).hojaTLW([.large]) }
    }

    // MARK: Cabecera, hoy y leyenda

    private var ciudad: String? {
        let cs = casas.compactMap(\.ciudad)
        return cs.max { a, b in cs.filter { $0 == a }.count < cs.filter { $0 == b }.count }
    }

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temporada \(TempFechas.temporadaDe(desde))\(ciudad.map { " · \($0)" } ?? "")").estilo(.titulo3).foregroundStyle(C.texto)
            HStack {
                Button { desde = TempFechas.sumarDias(desde, -Self.dias) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 36) }
                    .accessibilityLabel("31 días antes")
                Spacer()
                Text(TempFechas.meses(desde, hasta)).estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Button { desde = TempFechas.sumarDias(desde, Self.dias) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 36) }
                    .accessibilityLabel("31 días después")
            }
            .foregroundStyle(C.accion).background(C.superficie, in: .rect(cornerRadius: 12, style: .continuous))
            if desde != hoy { Button("Volver a hoy") { desde = hoy }.estilo(.footnoteFuerte).foregroundStyle(C.accion) }
        }
    }

    private var pendientes: [CalendarioTemporada.Ocupacion] { casas.flatMap { $0.reservas.filter { $0.estado == "pendiente" && $0.motivo != "dueno" } } }

    private var hoyBloque: some View {
        let entran = deHoy.filter { $0.entrada == hoy }
        let salen = deHoy.filter { $0.salida == hoy }
        return VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Hoy")
            VStack(spacing: 0) {
                if entran.isEmpty, salen.isEmpty {
                    filaHoy("calendar.badge.checkmark", .neutro, "Sin entradas ni salidas", nil, primera: true) {}
                }
                ForEach(Array(entran.enumerated()), id: \.element.id) { i, r in
                    filaHoy("key", .oro, direccion(r), "Check-in · \(r.quien)", primera: i == 0) { estado.abrir(AReservaTemporada(id: r.id)) }
                }
                ForEach(Array(salen.enumerated()), id: \.element.id) { i, r in
                    filaHoy("rectangle.portrait.and.arrow.right", .azul, direccion(r), "Check-out · \(r.quien)", primera: entran.isEmpty && i == 0) { estado.abrir(AReservaTemporada(id: r.id)) }
                }
                filaHoy("hourglass", .oro, "Señas pendientes", "\(pendientes.count)", primera: false) {
                    if let p = pendientes.first { estado.abrir(AReservaTemporada(id: p.id)) }
                }
            }
            .tarjeta()
        }
    }

    private func direccion(_ r: ReservaTemporada) -> String { casas.first { $0.id == r.propiedadId }?.direccion ?? r.propiedadTitulo ?? "Casa" }

    private func filaHoy(_ icono: String, _ tono: Tono, _ t: String, _ d: String?, primera: Bool, _ ir: @escaping () -> Void) -> some View {
        Button(action: ir) {
            HStack(spacing: 12) {
                IconoTono(icono: icono, tono: tono, tam: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    if let d { Text(d).estilo(.footnote).foregroundStyle(tono == .oro ? C.avisoTinta : C.texto2) }
                }
                Spacer()
            }
            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    /// Las temporadas que aparecen, de la más barata a la más cara: azul, oro, rojo.
    private var temporadas: [(TarifaAPI, Tono)] {
        var m: [String: TarifaAPI] = [:]
        for c in casas { for t in c.tarifas { let k = t.nombre ?? ""; if m[k] == nil || t.precio < (m[k]?.precio ?? 0) { m[k] = t } } }
        let xs = m.values.sorted { $0.precio < $1.precio }
        let tonos: [Tono] = [.azul, .oro, .rojo]
        return xs.enumerated().map { i, t in (t, tonos[xs.count == 1 ? 1 : Int((Double(i) / Double(max(1, xs.count - 1)) * 2).rounded())]) }
    }

    private func tonoDia(_ d: String) -> Tono? {
        guard let t = TempFechas.tarifaDe(casas.flatMap(\.tarifas), d) else { return nil }
        return temporadas.first { $0.0.nombre == t.nombre }?.1
    }

    private var leyenda: some View {
        let ocupado = casas.isEmpty ? 0 : Double(casas.reduce(0) { $0 + $1.nochesOcupadas }) / Double(casas.count * Self.dias)
        let huecos = casas.reduce(0) { $0 + TempFechas.huecos($1.reservas, desde, hasta) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(temporadas.enumerated()), id: \.offset) { _, x in
                let t = x.0, tono = x.1
                HStack(spacing: 6) {
                    Circle().fill(tono.tinta).frame(width: 9, height: 9)
                    Text("\(t.nombre ?? "") · \(Formato.plata(t.precio, t.moneda ?? "USD"))\(t.nochesMinimas.map { " · mín. \($0) noches" } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            (Text(Formato.porcentaje((ocupado * 100).rounded())).bold() + Text(" ocupado · ") + Text("\(huecos) \(huecos == 1 ? "hueco" : "huecos")").bold() + Text(" de menos de 4 noches"))
                .estilo(.footnote).foregroundStyle(C.texto)
        }
    }

    // MARK: Calendario

    private var calendario: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Casa").estilo(.footnoteFuerte).foregroundStyle(C.texto2).frame(height: 40)
                ForEach(casas) { c in infoCasa(c).frame(height: 56) }
            }
            .frame(width: 140)
            .padding(.leading, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) { ForEach(ventana, id: \.self) { d in cabezaDia(d) } }.frame(height: 40)
                    ForEach(casas) { c in filaCasa(c).frame(height: 56) }
                }
            }
        }
        .padding(.vertical, 6)
        .tarjeta()
    }

    private func infoCasa(_ c: CasaTemporada) -> some View {
        Button { estado.abrir(AFichaPropiedad(id: c.id)) } label: {
            HStack(spacing: 8) {
                Foto(url: c.foto).frame(width: 34, height: 34).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.direccion).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto).lineLimit(1)
                    Text([c.ambientes.map { "\($0) amb" }, c.destaque?.lowercased(), c.huespedes.map { "\($0) p." }].compactMap { $0 }.joined(separator: " · "))
                        .font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font).foregroundStyle(C.texto2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(Presionable())
    }

    private func cabezaDia(_ d: String) -> some View {
        let w = TempFechas.diaSemana(d)
        let tono = tonoDia(d)
        return VStack(spacing: 1) {
            Text(String(TempFechas.inicialDia[w])).font(Estilo(tamano: 10, peso: .semibold, relativo: .caption2).font)
            Text("\(Int(d.dropFirst(8)) ?? 0)").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
        }
        .foregroundStyle(d == hoy ? C.sobreAccion : (w == 0 || w == 6 ? C.texto : C.texto2))
        .frame(width: Self.ancho - 2, height: 36)
        .background(d == hoy ? C.accion : (tono?.fondo ?? .clear), in: .rect(cornerRadius: 8))
        .frame(width: Self.ancho)
    }

    private func filaCasa(_ c: CasaTemporada) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(ventana, id: \.self) { d in
                    let ocupado = c.reservas.contains { $0.entrada <= d && d < $0.salida }
                    let w = TempFechas.diaSemana(d)
                    Rectangle().fill(w == 0 || w == 6 ? C.hundida.opacity(0.6) : Color.clear)
                        .frame(width: Self.ancho, height: 56)
                        .overlay(alignment: .leading) { Rectangle().fill(C.linea).frame(width: 0.5) }
                        .contentShape(Rectangle())
                        .onTapGesture { if !ocupado, estado.escribe { reservarDesde(c, d) } }
                        .accessibilityLabel(ocupado ? "\(d) ocupado" : "\(d) libre, tocá para reservar")
                }
            }
            ForEach(c.reservas) { r in barra(r) }
        }
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    @ViewBuilder
    private func barra(_ r: CalendarioTemporada.Ocupacion) -> some View {
        let a = max(0, TempFechas.noches(desde, r.entrada))
        let b = min(Self.dias, TempFechas.noches(desde, r.salida))
        if b > a {
            let dueno = r.motivo == "dueno"
            let n = TempFechas.noches(r.entrada, r.salida)
            let texto = dueno ? "Uso del dueño" : r.estado == "pendiente" ? "Seña pendiente\(r.huesped.map { " · \($0)" } ?? "")" : "\(r.huesped ?? "Reservada")\(n >= 7 ? " · \(n) n." : "")"
            Button { estado.abrir(AReservaTemporada(id: r.id)) } label: {
                Label(texto, systemImage: dueno ? "nosign" : r.estado == "confirmada" ? "person.fill" : "hourglass")
                    .font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).lineLimit(1)
                    .foregroundStyle(dueno ? C.texto2 : r.estado == "confirmada" ? C.sobreAccion : C.avisoTinta)
                    .padding(.horizontal, 6)
                    .frame(width: CGFloat(b - a) * Self.ancho - 4, height: 30, alignment: .leading)
                    .background(dueno ? C.hundida : r.estado == "confirmada" ? C.accion : C.avisoFondo, in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(r.estado == "pendiente" && !dueno ? C.avisoTinta.opacity(0.5) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .buttonStyle(Presionable())
            .offset(x: CGFloat(a) * Self.ancho + 2)
        }
    }

    /// Tocar un día libre: la reserva desde ese día, con las noches mínimas de la temporada (2 o más).
    private func reservarDesde(_ c: CasaTemporada, _ d: String) {
        let t = TempFechas.tarifaDe(c.tarifas, d)
        nueva = PedidoReservaTemporada(casa: c.id, entrada: d, salida: TempFechas.sumarDias(d, max(2, t?.nochesMinimas ?? 2)))
    }

    // MARK: Lista

    private var lista: some View {
        VStack(alignment: .leading, spacing: 10) {
            TituloBloque(texto: "Reservas")
            Segmentado(opciones: [(0, "Próximas"), (1, "Adentro"), (2, "Pasadas")], elegido: $filtro)
            let l = reservas.filter {
                switch filtro {
                case 0: return $0.entrada >= hoy
                case 1: return $0.entrada <= hoy && $0.salida >= hoy
                default: return $0.salida < hoy
                }
            }
            if l.isEmpty {
                Text("No hay reservas acá.").estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(l.enumerated()), id: \.element.id) { i, r in
                        Button { estado.abrir(AReservaTemporada(id: r.id)) } label: { FilaReservaTemporada(r: r) }.buttonStyle(Presionable())
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
        }
        .task(id: filtro) {
            if filtro == 2, !reservas.contains(where: { $0.salida < hoy }) {
                let pasadas: [ReservaTemporada] = (try? await estado.api.get("/v1/temporada/reservas", query: [.init(name: "pasadas", value: "si"), .init(name: "limite", value: "1000")])) ?? []
                reservas = pasadas.sorted { $0.entrada < $1.entrada }
            }
        }
    }

    // MARK: Cargar

    private func cargar() async {
        do {
            let c: CalendarioTemporada = try await estado.api.get("/v1/temporada/calendario", query: [.init(name: "desde", value: desde), .init(name: "hasta", value: hasta)])
            let props: [Propiedad] = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "operacion", value: "temporario"), .init(name: "limite", value: "200")])) ?? []
            var porId = Dictionary(props.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for x in c.propiedades where porId[x.id] == nil {
                if let p: Propiedad = try? await estado.api.get("/v1/propiedades/\(x.id)") { porId[x.id] = p }
            }
            var cs: [CasaTemporada] = []
            for x in c.propiedades {
                let p = porId[x.id]
                let ts: [TarifaAPI] = (try? await estado.api.get("/v1/propiedades/\(x.id)/tarifas")) ?? []
                let huespedes: Int? = {
                    if case .numero(let n)? = p?.ficha?["temporario"]?["huespedes"] { return Int(n) }
                    return nil
                }()
                cs.append(CasaTemporada(id: x.id, direccion: p?.direccion ?? x.titulo ?? "Casa", foto: p?.miniatura, ambientes: p?.ambientes,
                                        destaque: p?.comodidades?.first { ["Pileta", "Parrilla", "Vista al mar"].contains($0) }, huespedes: huespedes,
                                        ciudad: p?.ciudad ?? p?.barrio, precio: p?.precio, moneda: p?.moneda ?? "USD", periodo: p?.periodo,
                                        nochesOcupadas: x.nochesOcupadas, reservas: x.reservas, tarifas: ts))
            }
            casas = cs
            cal = c
            error = nil
            deHoy = (try? await estado.api.get("/v1/temporada/reservas", query: [.init(name: "desde", value: TempFechas.sumarDias(hoy, -1)), .init(name: "hasta", value: hoy),
                                                                                .init(name: "estado", value: "pendiente,confirmada")])) ?? []
            let rs: [ReservaTemporada] = (try? await estado.api.get("/v1/temporada/reservas", query: [.init(name: "limite", value: "1000")])) ?? []
            reservas = rs.sorted { $0.entrada < $1.entrada }
        } catch let e as ErrorApi { error = e } catch {}
    }
}

/// Una reserva en la lista: el huésped (o «Uso del dueño»), la casa, las fechas y el saldo.
struct FilaReservaTemporada: View {
    var r: ReservaTemporada
    var body: some View {
        HStack(spacing: 12) {
            IconoTono(icono: r.deDueno ? "nosign" : r.estado == "confirmada" ? "person.fill" : r.estado == "cancelada" ? "xmark" : "hourglass",
                      tono: r.deDueno ? .neutro : r.estado == "confirmada" ? .verde : r.estado == "cancelada" ? .neutro : .oro, tam: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.deDueno ? "Uso del dueño" : r.quien).estilo(.filaLista).foregroundStyle(C.texto)
                Text("\(r.propiedadTitulo ?? "") · \(TempFechas.corto(r.entrada)) al \(TempFechas.corto(r.salida))\(r.deDueno ? "" : " · \(Formato.cantidad(r.huespedes ?? 1, "persona", "personas"))")")
                    .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                if !r.deDueno, r.estado == "pendiente" { Text("Seña pendiente").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.avisoTinta) }
                else if let s = r.saldo, s > 0, !r.deDueno { Text("Saldo \(Formato.plata(s, r.moneda ?? "ARS"))").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.errorTinta) }
            }
            Spacer()
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }
}

/// Nueva reserva de temporada (o uso del dueño): la casa y las fechas ya puestas, la cotización sola
/// según las tarifas de cada noche, el huésped y la seña. Con seña queda confirmada; sin seña,
/// pendiente. Se crea al toque, con deshacer.
struct NuevaReservaTemporada: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var casas: [CasaTemporada]
    @State var casa: String
    @State var entrada: String
    @State var salida: String
    @State private var motivo = "huesped"
    @State private var nombre = ""
    @State private var telefono = ""
    @State private var huespedes: Int?
    @State private var total: Double?
    @State private var totalPropio = false
    @State private var moneda = "USD"
    @State private var sena: Double?
    @State private var errores: [String: String] = [:]
    @State private var enviando = false
    @State private var envio = UUID().uuidString

    private var elegida: CasaTemporada? { casas.first { $0.id == casa } }
    private var cot: TempFechas.Cotizacion? {
        guard let c = elegida, salida > entrada else { return nil }
        return TempFechas.cotizar(c.tarifas, entrada, salida, base: c.periodo == "noche" ? (c.precio, c.moneda) : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Para quién", selection: $motivo) { Text("Huésped").tag("huesped"); Text("Uso del dueño").tag("dueno") }.pickerStyle(.segmented)
                } footer: {
                    Text(motivo == "dueno" ? "Las noches quedan bloqueadas en el calendario, sin huésped ni cobro." : "Con seña queda confirmada y ocupa la casa; sin seña, pendiente.")
                }
                Section {
                    Picker("Casa", selection: $casa) { ForEach(casas) { Text($0.direccion).tag($0.id) } }
                    DatePicker("Entrada", selection: dia($entrada), displayedComponents: .date)
                    if let e = errores["entrada"] { MensajeError(texto: e) }
                    DatePicker("Salida", selection: dia($salida), displayedComponents: .date)
                    if let e = errores["salida"] { MensajeError(texto: e) }
                    if let cot, motivo == "huesped" {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Formato.cantidad(cot.noches, "noche", "noches"))\(cot.total.map { " · \(Formato.plata($0, cot.moneda))" } ?? "")\(cot.temporada.map { " · temporada \($0.lowercased())" } ?? "")")
                                .estilo(.subheadFuerte)
                            if let m = cot.minimo { Text("Esa temporada pide mínimo \(m) noches.").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                            if cot.total == nil { Text("Faltan tarifas para alguna noche: poné el total a mano.").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                        }
                    }
                }
                if motivo == "dueno" {
                    Section("Nota (opcional)") {
                        TextField("Viene con la familia", text: $nombre)
                        if let e = errores["notas"] { MensajeError(texto: e) }
                    }
                } else {
                    Section("Huésped") {
                        TextField("Huésped", text: $nombre).textContentType(.name)
                        if let e = errores["huespedNombre"] ?? errores["contactoId"] { MensajeError(texto: e) }
                        TextField("Teléfono (opcional)", text: $telefono).keyboardType(.phonePad)
                        Stepper(huespedes.map { Formato.cantidad($0, "persona", "personas") } ?? "Personas (opcional)",
                                value: Binding(get: { huespedes ?? 0 }, set: { huespedes = $0 == 0 ? nil : $0 }), in: 0...(elegida?.huespedes ?? 40))
                        if let e = errores["huespedes"] { MensajeError(texto: e) }
                    }
                    Section("Plata") {
                        Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                        TextField("Total", value: Binding(get: { total }, set: { total = $0; totalPropio = true }), format: .number).keyboardType(.decimalPad)
                        if let e = errores["monto"] { MensajeError(texto: e) }
                        TextField("Seña recibida", value: $sena, format: .number).keyboardType(.decimalPad)
                        if let e = errores["sena"] { MensajeError(texto: e) }
                    }
                }
            }
            .navigationTitle(motivo == "dueno" ? "Uso del dueño" : "Nueva reserva").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(enviando ? (motivo == "dueno" ? "Bloqueando…" : "Reservando…") : (motivo == "dueno" ? "Bloquear" : "Reservar")) { Task { await crear() } }
                        .fontWeight(.semibold).disabled(enviando || elegida == nil)
                }
            }
            .onAppear { recotizar() }
            .onChange(of: "\(casa)-\(entrada)-\(salida)") { _, _ in totalPropio = false; recotizar() }
        }
    }

    private func dia(_ b: Binding<String>) -> Binding<Date> {
        Binding(get: { Fecha.dia(b.wrappedValue) ?? Date() }, set: { b.wrappedValue = Formato.diaISO($0) })
    }

    private func recotizar() {
        guard !totalPropio else { return }
        total = cot?.total
        moneda = cot?.moneda ?? elegida?.moneda ?? "USD"
    }

    private func crear() async {
        guard let c = elegida, salida > entrada else { errores = ["salida": "La salida tiene que ser después de la entrada."]; return }
        enviando = true
        errores = [:]
        defer { enviando = false }
        struct Huesped: Encodable {
            var propiedadId: String; var huespedNombre: String; var huespedTelefono: String?; var huespedes: Int?
            var entrada: String; var salida: String; var estado: String; var monto: Double?; var moneda: String; var sena: Double?
        }
        struct Dueno: Encodable { var propiedadId: String; var motivo = "dueno"; var entrada: String; var salida: String; var notas: String? }
        let dueno = motivo == "dueno"
        let n = TempFechas.noches(entrada, salida)
        do {
            let r: ReservaTemporada
            if dueno {
                r = try await estado.api.conCampos("POST", "/v1/temporada/reservas", Dueno(propiedadId: casa, entrada: entrada, salida: salida, notas: nombre.nonEmpty),
                                                   envio: envio, como: ReservaTemporada.self)
            } else {
                r = try await estado.api.conCampos("POST", "/v1/temporada/reservas",
                                                   Huesped(propiedadId: casa, huespedNombre: nombre.trimmingCharacters(in: .whitespaces), huespedTelefono: telefono.nonEmpty,
                                                           huespedes: huespedes, entrada: entrada, salida: salida, estado: (sena ?? 0) > 0 ? "confirmada" : "pendiente",
                                                           monto: total, moneda: moneda, sena: sena),
                                                   envio: envio, como: ReservaTemporada.self)
            }
            estado.version += 1
            cerrar()
            estado.avisar(dueno ? "Bloqueada \(c.direccion) · \(n) noches de uso del dueño" : "Reservada \(c.direccion) · \(n) noches") {
                Task {
                    do { try await estado.api.hacer("DELETE", "/v1/temporada/reservas/\(r.id)"); estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch let e as ErrorConCampos {
            errores = e.campos
        } catch { estado.avisar(error) }
    }
}

/// 15C Check-in de una reserva: el estado («Check-in hoy 14:00», «En la casa», «Check-out hoy»…), el
/// huésped con su WhatsApp, la lista de la puerta (saldo, depósito, los DNI con la cámara, inventario
/// rápido) y «Entregar llaves», con deshacer. Cada tilde se guarda sola. El uso del dueño muestra
/// las noches y «Liberar las noches».
struct CheckinTemporada: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var r: ReservaTemporada?
    @State private var casa: Propiedad?
    @State private var telefono: String?
    @State private var error: ErrorApi?
    @State private var subiendo = false
    @State private var camara = false
    @State private var fototeca: [PhotosPickerItem] = []
    @State private var pidiendoFoto = false

    private var hoy: String { Formato.diaISO(Date()) }
    private func temporario(_ k: String) -> JSONLibre? { casa?.ficha?["temporario"]?[k] }
    private var checkIn: String? { temporario("checkIn")?.texto }
    private var checkOut: String? { temporario("checkOut")?.texto }
    private var deposito: Double? { if case .numero(let n)? = temporario("deposito") { return n }; return nil }

    var body: some View {
        ScrollView {
            if let r {
                VStack(alignment: .leading, spacing: 16) {
                    portada(r)
                    if r.deDueno { dueno(r) } else { huesped(r); listaPuerta(r) }
                    accesos(r)
                }
                .padding(.bottom, 100)
            } else if let error {
                EstadoError(que: "la reserva", error: error) { Task { await cargar() } }.padding(.top, 60)
            } else { EsqueletoFilas(filas: 4).padding(16) }
        }
        .pantallaApilada("Check-in")
        .barraAccion { if let r { pie(r) } }
        .task(id: estado.version) { await cargar() }
        .fullScreenCover(isPresented: $camara) { Camara { d in Task { await subirDNI([d]) } }.ignoresSafeArea() }
        .photosPicker(isPresented: $pidiendoFoto, selection: $fototeca, maxSelectionCount: 10, matching: .images)
        .onChange(of: fototeca) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var datos: [Data] = []
                for i in items {
                    do { if let d = try await i.loadTransferable(type: Data.self) { datos.append(d) } } catch { estado.avisar(error) }
                }
                fototeca = []
                await subirDNI(datos)
            }
        }
    }

    private func titular(_ r: ReservaTemporada) -> String {
        let h = checkIn.map { " \($0)" } ?? ""
        if r.deDueno { return r.estado == "cancelada" ? "Bloqueo liberado" : "Uso del dueño" }
        if r.estado == "cancelada" { return "Reserva cancelada" }
        if r.entrada == hoy { return "Check-in hoy\(h)" }
        if r.entrada > hoy { return "Check-in el \(Fecha.dia(r.entrada).map { Formato.fechaLarga($0) } ?? r.entrada)\(h)" }
        if r.salida > hoy { return "En la casa" }
        if r.salida == hoy { return "Check-out hoy\(checkOut.map { " \($0)" } ?? "")" }
        return "Terminó la estadía"
    }

    private func rango(_ r: ReservaTemporada) -> String {
        r.entrada.dropFirst(5).prefix(2) == r.salida.dropFirst(5).prefix(2)
            ? "\(Int(r.entrada.dropFirst(8)) ?? 0) al \(TempFechas.corto(r.salida))" : "\(TempFechas.corto(r.entrada)) al \(TempFechas.corto(r.salida))"
    }

    private func portada(_ r: ReservaTemporada) -> some View {
        ZStack(alignment: .bottomLeading) {
            Foto(url: casa?.portada).frame(height: 200).frame(maxWidth: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(titular(r)).estilo(.subheadFuerte).foregroundStyle(C.oro)
                Text(casa?.direccion ?? r.propiedadTitulo ?? "").estilo(.titulo3).foregroundStyle(.white)
            }
            .padding(16)
        }
        .clipped()
    }

    private func dueno(_ r: ReservaTemporada) -> some View {
        HStack(spacing: 12) {
            IconoTono(icono: "nosign", tono: .neutro, tam: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Uso del dueño").estilo(.filaLista).foregroundStyle(C.texto)
                Text("\(rango(r)) · \(Formato.cantidad(r.noches ?? 0, "noche", "noches"))\(r.notas.map { " · \($0)" } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
        }
        .padding(14).tarjeta().padding(.horizontal, 16)
    }

    private func huesped(_ r: ReservaTemporada) -> some View {
        HStack(spacing: 12) {
            AvatarIniciales(nombre: r.quien, tam: 44, fondo: C.azulFondo, tinta: C.azulTinta)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.quien).estilo(.filaLista).foregroundStyle(C.texto)
                Text([r.huespedes.map { Formato.cantidad($0, "persona", "personas") }, rango(r), Formato.cantidad(r.noches ?? 0, "noche", "noches")].compactMap { $0 }.joined(separator: " · "))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            if let t = telefono ?? r.huespedTelefono {
                Button { Afuera.whatsapp(t) } label: { Image(systemName: "bubble.left.fill").frame(width: 44, height: 44).background(C.okFondo, in: .rect(cornerRadius: 12)).foregroundStyle(C.okTinta) }
                    .accessibilityLabel("Escribirle a \(r.quien) por WhatsApp")
            }
        }
        .padding(14).tarjeta().padding(.horizontal, 16)
    }

    private func listaPuerta(_ r: ReservaTemporada) -> some View {
        let l = r.checkin ?? .init()
        let personas = r.huespedes
        let dniListo = !l.dni.isEmpty && (personas == nil || l.dni.count >= (personas ?? 0))
        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                tilde(l.saldo, "Saldo cobrado", r.saldo.map { Formato.plata($0, r.moneda ?? "ARS") }, primera: true) { Task { await guardar(saldo: !l.saldo) } }
                tilde(l.deposito, "Depósito en garantía", deposito.map { Formato.plata($0, temporario("moneda")?.texto ?? r.moneda ?? "ARS") }, primera: false) {
                    Task { await guardar(deposito: !l.deposito) }
                }
                Menu {
                    Button { camara = true } label: { Label("Sacar la foto", systemImage: "camera") }
                    Button { pidiendoFoto = true } label: { Label("Elegir de Fotos", systemImage: "photo.on.rectangle") }
                } label: {
                    filaTilde(dniListo, "DNI \(personas.map { "de los \($0)" } ?? "de los huéspedes")\(l.dni.isEmpty ? "" : " · \(Formato.cantidad(l.dni.count, "foto", "fotos"))")",
                              nil, icono: subiendo ? nil : "camera.fill", cargando: subiendo)
                }
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                HStack(spacing: 0) {
                    Button { Task { await guardar(inventario: !l.inventario) } } label: { caja(l.inventario).padding(.leading, 14) }
                        .accessibilityLabel("Inventario rápido hecho")
                    Button { if let p = r.propiedadId { estado.abrir(ASeccion(clave: "actas", id: p)) } } label: {
                        HStack {
                            Text("Inventario rápido").estilo(.body16).foregroundStyle(C.accion)
                            Spacer()
                            Text("desde el anterior").estilo(.footnote).foregroundStyle(C.texto3)
                        }
                        .padding(.horizontal, 12).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                }
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
            .tarjeta()
            Text("Check-out el \(Fecha.dia(r.salida).map { Formato.fechaLarga($0) } ?? r.salida)\(checkOut.map { " a las \($0)" } ?? "").")
                .estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
    }

    private func caja(_ on: Bool) -> some View {
        ZStack { if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(C.sobreAccion) } }
            .frame(width: 26, height: 26).background(on ? C.accion : .clear, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? .clear : C.linea2, lineWidth: 1.5))
    }

    private func filaTilde(_ on: Bool, _ t: String, _ valor: String?, icono: String? = nil, cargando: Bool = false) -> some View {
        HStack(spacing: 12) {
            caja(on)
            Text(t).estilo(.body16).foregroundStyle(C.texto).multilineTextAlignment(.leading)
            Spacer()
            if let valor { Text(valor).estilo(.subheadFuerte).foregroundStyle(C.texto) }
            if cargando { ProgressView() } else if let icono { Image(systemName: icono).foregroundStyle(C.okTinta) }
        }
        .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
    }

    private func tilde(_ on: Bool, _ t: String, _ valor: String?, primera: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) { filaTilde(on, t, valor) }
            .buttonStyle(Presionable())
            .accessibilityAddTraits(on ? .isSelected : [])
            .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func accesos(_ r: ReservaTemporada) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Esta reserva")
            VStack(spacing: 0) {
                acceso("calendar", "Calendario", primera: true) { estado.abrir(ASeccion(clave: "temporada")) }
                if let p = r.propiedadId {
                    acceso("checklist", "Inventario de la casa") { estado.abrir(ASeccion(clave: "actas", id: p)) }
                    acceso("house", "Ficha de la casa") { estado.abrir(AFichaPropiedad(id: p)) }
                }
                if estado.escribe, !r.deDueno, r.estado != "cancelada" {
                    if r.estado == "pendiente" { acceso("checkmark.circle", "Confirmar la reserva") { Task { await poner(r, "confirmada") } } }
                    acceso("xmark.circle", "Cancelar la reserva") { Task { await poner(r, "cancelada") } }
                }
            }
            .tarjeta()
        }
        .padding(.horizontal, 16)
    }

    private func acceso(_ i: String, _ t: String, primera: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: i).foregroundStyle(C.accion).frame(width: 24)
                Text(t).estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    @ViewBuilder
    private func pie(_ r: ReservaTemporada) -> some View {
        if !estado.escribe {
            EmptyView()
        } else if r.deDueno {
            Button { Task { await liberar(r) } } label: { Label("Liberar las noches", systemImage: "lock.open") }
                .buttonStyle(BotonHundido()).disabled(r.estado == "cancelada")
        } else if let l = r.llavesEn {
            Button { Task { await guardar(llaves: false) } } label: { Label("Llaves entregadas · \(Formato.horaDe(l))", systemImage: "checkmark.circle") }
                .buttonStyle(BotonHundido())
        } else {
            Button { Task { await entregarLlaves(r) } } label: { Label("Entregar llaves", systemImage: "key.fill") }
                .buttonStyle(BotonPrincipal()).disabled(r.estado == "cancelada")
        }
    }

    // MARK: Guardar

    /// Manda la lista entera de la puerta (la API la reemplaza) y, si viene, las llaves.
    @discardableResult
    private func guardar(saldo: Bool? = nil, deposito: Bool? = nil, inventario: Bool? = nil, dni: [String]? = nil, llaves: Bool? = nil) async -> Bool {
        guard let antes = r else { return false }
        var l = antes.checkin ?? .init()
        if let saldo { l.saldo = saldo }
        if let deposito { l.deposito = deposito }
        if let inventario { l.inventario = inventario }
        if let dni { l.dni = dni }
        var nueva = antes
        nueva.checkin = l
        if let llaves { nueva.llavesEn = llaves ? Date() : nil }
        r = nueva
        struct C: Encodable { var saldo: Bool; var deposito: Bool; var inventario: Bool; var dni: [String]; var llaves: Bool? }
        do {
            let x: ReservaTemporada = try await estado.api.enviar("PUT", "/v1/temporada/reservas/\(antes.id)/checkin",
                                                                  C(saldo: l.saldo, deposito: l.deposito, inventario: l.inventario, dni: l.dni, llaves: llaves))
            r = x
            return true
        } catch {
            r = antes
            estado.avisar(error)
            return false
        }
    }

    private func entregarLlaves(_ r: ReservaTemporada) async {
        if await guardar(llaves: true) {
            Haptico.exito()
            estado.avisar("Llaves entregadas a \(r.quien.components(separatedBy: " ").first ?? r.quien)") { Task { await guardar(llaves: false) } }
        }
    }

    private func subirDNI(_ fotos: [Data]) async {
        guard !fotos.isEmpty else { return }
        subiendo = true
        defer { subiendo = false }
        do {
            var ids: [String] = []
            for f in fotos {
                let jpg = UIImage(data: f)?.jpegData(compressionQuality: 0.8) ?? f
                guard jpg.count <= 25 << 20 else { estado.avisar("El archivo pasa de 25 MB.", ok: false); continue }
                ids.append(try await estado.api.subir(jpg, nombre: "dni-\(Int(Date().timeIntervalSince1970)).jpg", tipo: "image/jpeg", uso: "documento").id)
            }
            await guardar(dni: (r?.checkin?.dni ?? []) + ids)
        } catch { estado.avisar(error) }
    }

    private func liberar(_ r: ReservaTemporada) async {
        struct C: Encodable { var estado: String }
        do {
            let x: ReservaTemporada = try await estado.api.enviar("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: "cancelada"))
            self.r = x
            estado.version += 1
            estado.avisar("Liberadas \(Formato.cantidad(r.noches ?? 0, "noche", "noches")) de \(casa?.direccion ?? "la casa")") {
                Task {
                    do { let y: ReservaTemporada = try await estado.api.enviar("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: "confirmada")); self.r = y; estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func poner(_ r: ReservaTemporada, _ e: String) async {
        struct C: Encodable { var estado: String }
        do {
            let x: ReservaTemporada = try await estado.api.enviar("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: e))
            self.r = x
            estado.version += 1
            estado.avisar(e == "cancelada" ? "Reserva cancelada" : "Reserva confirmada") {
                Task {
                    do { let y: ReservaTemporada = try await estado.api.enviar("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: r.estado ?? "pendiente")); self.r = y; estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            let x: ReservaTemporada = try await estado.api.get("/v1/temporada/reservas/\(id)")
            r = x
            error = nil
            if let p = x.propiedadId { casa = try? await estado.api.get("/v1/propiedades/\(p)") }
            if let c = x.contactoId { telefono = (try? await estado.api.get("/v1/contactos/\(c)") as Contacto)?.telefono }
        } catch let e as ErrorApi { error = e } catch {}
    }
}
