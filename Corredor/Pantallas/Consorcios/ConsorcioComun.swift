import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Consorcios: los tipos de la API (/v1/consorcios/*, con los tags json del Go de
// api/internal/dominio/consorcios) y las cuentas chicas que comparten las pantallas, como
// web/src/lib/consorcios/comun.ts. Los montos llegan en pesos con dos decimales.

// MARK: - Destinos del área

/// Liquidar expensas (el flujo Gastos → Prorrateo → Emitir). `periodo`: «AAAA-MM»; nil es el que toca.
struct ALiquidarConsorcio: Hashable { var consorcio: String; var periodo: String? = nil }
/// La ficha de un trabajo o reclamo.
struct ATrabajoConsorcio: Hashable { var consorcio: String; var id: String }
/// La ficha de un consorcio abierta en una pestaña (las alertas llevan a Unidades que deben, Trabajos…).
/// `pedido`: lo que se abre adentro («deben», «nueva», «unidad:<id>», «liquidar», «recibo:<id>»).
struct AFichaConsorcioEn: Hashable { var id: String; var pestana: String; var pedido: String? = nil }

extension View {
    /// Los destinos de Consorcios. Los registran la lista y la ficha (los dos pueden apilarlos).
    func destinosConsorcios() -> some View {
        self
            .navigationDestination(for: ALiquidarConsorcio.self) { l in LiquidarConsorcio(consorcio: l.consorcio, pedido: l.periodo) }
            .navigationDestination(for: ATrabajoConsorcio.self) { t in FichaTrabajoConsorcio(consorcio: t.consorcio, id: t.id) }
            .navigationDestination(for: AFichaConsorcioEn.self) { f in FichaConsorcio(id: f.id, pestanaInicial: f.pestana, pedidoInicial: f.pedido) }
    }
}

// MARK: - Modelos

struct ConsorcioAPI: Codable, Identifiable, Hashable {
    struct Metricas: Codable, Hashable {
        var unidades: Int?
        var deudores: Int?
        var saldoAdeudado: Double?
        var novedadesAbiertas: Int?
        var trabajosPendientes: Int?
        var trabajosVencidos: Int?
        var servicesPorVencer: Int?
    }
    var id: String
    var nombre: String
    var direccion: String?
    var cuit: String?
    var cbu: String?
    var diaVencimiento: Int?
    var diaSegundoVencimiento: Int?
    var interesMensual: Double?
    // Lo que la app no edita pero el PUT pisa: viaja tal como vino (como datos.ts de la web).
    var modoExpensas: String?
    var fondoTipo: String?
    var fondoValor: Double?
    var notas: String?
    var agenteId: String?
    var fotoId: String?
    var fotoUrl: String?
    var reglamentoEn: String?
    var metricas: Metricas?
    /// Sólo en la ficha (GET /v1/consorcios/{id}).
    var columnas: [ColumnaAPI]?

    /// «Consorcio Cabildo 2620» → «Cabildo 2620».
    var nombreCorto: String { nombre.replacingOccurrences(of: "^consorcio\\s+", with: "", options: [.regularExpression, .caseInsensitive]) }
    /// El barrio: lo que va después de la primera coma de la dirección.
    var barrio: String? {
        let p = (direccion ?? "").split(separator: ",", maxSplits: 1)
        return p.count > 1 ? p[1].trimmingCharacters(in: .whitespaces).nonEmpty : nil
    }
    /// La columna General (la de por defecto) o la primera.
    var general: ColumnaAPI? { columnas?.first { $0.porDefecto == true } ?? columnas?.first }
}

struct ColumnaAPI: Codable, Identifiable, Hashable { var id: String; var nombre: String; var metodo: String?; var porDefecto: Bool?; var orden: Int? }

/// GET /v1/consorcios/alertas.
struct AlertaConsorcio: Codable, Hashable {
    var consorcioId: String
    var consorcio: String
    var tipo: String
    var texto: String
    var monto: Double?
    var fecha: String?
    var dias: Int?
}

struct UnidadAPI: Codable, Identifiable, Hashable {
    var id: String
    var etiqueta: String
    var piso: String?
    var tipo: String?
    var propietarioId: String?
    var inquilinoId: String?
    var notas: String?
    var expensaFija: Double?
    var coeficientes: [String: Double]?
    var propietario: String?
    var inquilino: String?
    var propietarioEmail: String?
    var propietarioTelefono: String?
    var saldo: Double?
    var nombre: String { etiqueta }

    static let tipos = [("departamento", "Departamento"), ("cochera", "Cochera"), ("baulera", "Baulera"), ("local", "Local"), ("otro", "Otro")]
}

struct DeudorAPI: Codable, Identifiable, Hashable {
    var unidadId: String
    var unidad: String
    var propietario: String?
    var saldo: Double
    var impagoDesde: String?
    var dias: Int?
    var interesEstimado: Double?
    var id: String { unidadId }
    var total: Double { saldo + (interesEstimado ?? 0) }
}

struct MovimientoUnidad: Codable, Identifiable, Hashable {
    var id: String
    var fecha: String
    var tipo: String
    var monto: Double
    var notas: String?
    var periodoId: String?

    static let nombres = ["pago": "Pago", "cargo": "Expensas", "interes": "Interés", "ajuste": "Ajuste"]
    var signo: Double { tipo == "pago" ? -monto : monto }
}

/// GET /v1/consorcios/{id}/unidades/{u}/cuenta.
struct CuentaUnidadAPI: Codable, Hashable {
    var unidad: String?
    var saldo: Double
    var impagoDesde: String?
    var interesEstimado: Double?
    var movimientos: [MovimientoUnidad]?
}

struct PeriodoAPI: Codable, Identifiable, Hashable {
    var id: String
    var periodo: String
    var estado: String
    var gastosTotal: Double?
    var fondoTotal: Double?
    var total: Double?
    var notas: String?
    var cargado: Double?
    /// Sólo en GET …/periodos/{p}.
    var gastos: [GastoExpensas]?
    var liquidaciones: [LiquidacionExpensas]?
}

struct GastoExpensas: Codable, Identifiable, Hashable {
    var id: String
    var descripcion: String
    var tipo: String?
    var monto: Double
    var columnaId: String?
    var proveedorId: String?
    var documentoId: String?
    var fecha: String?
    var columna: String?
    var proveedor: String?
    var proveedorRubro: String?
}

struct LineaExpensas: Codable, Hashable { var columnaId: String?; var columna: String; var base: Double?; var coeficiente: Double; var monto: Double }

struct LiquidacionExpensas: Codable, Identifiable, Hashable {
    var id: String
    var periodoId: String?
    var periodo: String
    var unidadId: String
    var unidad: String
    var propietario: String?
    var email: String?
    var propietarioId: String?
    var telefono: String?
    var desglose: [LineaExpensas]?
    var subtotal: Double?
    var fondo: Double?
    var total: Double
}

/// GET …/periodos/{p}/prorrateo.
struct ProrrateoExpensas: Codable, Hashable {
    struct Unidad: Codable, Hashable { var unidadId: String; var subtotal: Double?; var fondo: Double?; var total: Double }
    var unidades: [Unidad]
    var gastosTotal: Double?
    var fondoTotal: Double?
    var total: Double?
}

struct AdjuntoTrabajo: Codable, Hashable, Identifiable { var archivoId: String; var nombre: String; var tipo: String; var bytes: Int?; var url: String?; var id: String { archivoId } }

struct TrabajoAPI: Codable, Identifiable, Hashable {
    var id: String
    var unidadId: String?
    var estado: String
    var prioridad: String?
    var titulo: String
    var descripcion: String?
    var presupuesto: Double?
    var costoReal: Double?
    var responsable: String?
    var proveedorId: String?
    var proveedor: String?
    var proveedorRubro: String?
    var proveedorTelefono: String?
    var unidad: String?
    var venceEl: String?
    var hechoEl: String?
    var adjuntos: [AdjuntoTrabajo]?
    var creadoEn: String?
}

struct NovedadAPI: Codable, Identifiable, Hashable {
    var id: String
    var unidadId: String?
    var bienId: String?
    var tipo: String?
    var estado: String?
    var titulo: String
    var descripcion: String?
    var costo: Double?
    var responsable: String?
    var ocurrioEl: String?
    var resueltoEl: String?

    static let tipos = [("rotura", "Rotura"), ("arreglo", "Arreglo"), ("reclamo", "Reclamo"), ("aviso", "Aviso"), ("mantenimiento", "Mantenimiento"), ("gasto", "Gasto"), ("otro", "Nota")]
}

struct ProveedorConsorcio: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var cuit: String?
    var rubro: String?
    var telefono: String?
    var email: String?
    var notas: String?
    var conRubro: String { rubro?.nonEmpty.map { "\(nombre) · \($0)" } ?? nombre }
}

struct EmpleadoAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var documento: String?
    var categoria: String?
    var ingreso: String?
    var basico: Double?
    var horario: String?
    var notas: String?
}

struct DeduccionAPI: Codable, Hashable { var nombre: String; var tasa: Double; var monto: Double }

struct ReciboSueldoAPI: Codable, Identifiable, Hashable {
    var id: String
    var empleadoId: String
    var empleado: String
    var periodo: String
    var notas: String?
    var basico: Double?
    var antiguedad: Double?
    var otrosRemunerativos: Double?
    var bruto: Double?
    var deducciones: [DeduccionAPI]?
    var deduccionesTotal: Double?
    var neto: Double?
    var sac: Double?
}

struct EscalaAPI: Codable, Identifiable, Hashable { var id: String; var categoria: String; var basico: Double; var vigenteDesde: String?; var notas: String? }

/// Un link público (cuenta, recibo de expensas, recibo de sueldo).
struct LinkConsorcio: Codable, Hashable { var id: String?; var url: String }

/// POST …/periodos/{p}/enviar.
struct EnvioMailExpensas: Codable, Hashable { var encolados: Int; var sinEmail: [String]? }

// MARK: - Cuentas chicas (comun.ts)

enum Cons {
    /// Hoy, «AAAA-MM-DD».
    static var hoy: String { Formato.diaISO(Date()) }

    static func fechaDeMes(_ p: String) -> Date? { Fecha.dia(String(p.prefix(7)) + "-01") }
    /// «2026-11» → «noviembre».
    static func nombreMes(_ p: String) -> String { fechaDeMes(p).map(Formato.mesDe) ?? p }
    /// «2026-11» → «Noviembre».
    static func NombreMes(_ p: String) -> String { Formato.mayuscula(nombreMes(p)) }
    /// «Noviembre» o «Noviembre 2025» si no es de este año.
    static func mesConAnio(_ p: String) -> String { NombreMes(p) + (p.prefix(4) == hoy.prefix(4) ? "" : " \(p.prefix(4))") }
    /// «2026-11» → «nov.».
    static func mesCorto(_ p: String) -> String { String(nombreMes(p).prefix(3)) + "." }

    /// El mes siguiente: «2026-11» → «2026-12».
    static func mesSiguiente(_ p: String, _ n: Int = 1) -> String {
        let x = p.prefix(7).split(separator: "-").compactMap { Int($0) }
        guard x.count == 2 else { return p }
        let t = x[0] * 12 + (x[1] - 1) + n
        return String(format: "%04d-%02d", t / 12, t % 12 + 1)
    }

    /// El vencimiento: el día `dia` del mes siguiente al período.
    static func vencimiento(_ p: String, _ dia: Int?) -> String? {
        guard let dia, dia > 0 else { return nil }
        return "\(mesSiguiente(p))-\(String(format: "%02d", dia))"
    }

    /// «2026-12-10» → «10/12».
    static func diaBarraMes(_ f: String) -> String {
        guard f.count >= 10 else { return f }
        let a = f.split(separator: "-")
        return a.count >= 3 ? "\(a[2].prefix(2))/\(a[1])" : f
    }

    /// «2026-11-10» → «10/11/2026».
    static func fechaPapel(_ f: String) -> String {
        let a = f.prefix(10).split(separator: "-")
        return a.count == 3 ? "\(a[2])/\(a[1])/\(a[0])" : f
    }

    /// El período que toca liquidar: el borrador más nuevo; si no, el mes siguiente al último; si no
    /// hay ninguno, el mes de hoy.
    static func aLiquidar(_ periodos: [PeriodoAPI]) -> (periodo: String, borrador: PeriodoAPI?) {
        let ord = periodos.sorted { $0.periodo > $1.periodo }
        if let b = ord.first(where: { $0.estado == "borrador" }) { return (b.periodo, b) }
        if let u = ord.first { return (mesSiguiente(u.periodo), nil) }
        return (String(hoy.prefix(7)), nil)
    }

    /// En la lista: el mes que toca si hay borrador, o si el mes que sigue ya empezó.
    static func liquidarEnLista(_ periodos: [PeriodoAPI]) -> (periodo: String, borrador: Bool)? {
        let a = aLiquidar(periodos)
        if a.borrador != nil { return (a.periodo, true) }
        if !periodos.isEmpty, a.periodo <= String(hoy.prefix(7)) { return (a.periodo, false) }
        return nil
    }

    /// El período liquidado justo antes de `periodo`.
    static func anterior(_ periodos: [PeriodoAPI], _ periodo: String) -> PeriodoAPI? {
        periodos.filter { $0.estado != "borrador" && $0.periodo < periodo }.sorted { $0.periodo > $1.periodo }.first
    }

    /// 4.2 → «4,20 %».
    static func coeficiente(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") + " %" }
    /// Un número con coma: 3.5 → «3,5».
    static func coma(_ v: Double) -> String {
        let s = v.rounded() == v ? String(Int(v)) : String(format: "%g", v)
        return s.replacingOccurrences(of: ".", with: ",")
    }

    static func sumaCoeficientes(_ unidades: [UnidadAPI], _ columna: String) -> Double {
        (unidades.reduce(0) { $0 + ($1.coeficientes?[columna] ?? 0) } * 100).rounded() / 100
    }

    /// El primero del personal cuya categoría dice encargado (o el primero).
    static func encargado(_ e: [EmpleadoAPI]) -> EmpleadoAPI? {
        e.first { ($0.categoria ?? "").range(of: "encargad", options: .caseInsensitive) != nil } ?? e.first
    }

    /// Los años completos desde el ingreso.
    static func antiguedad(_ ingreso: String?, _ al: String = hoy) -> Int? {
        guard let ingreso, ingreso.count >= 10, al.count >= 10 else { return nil }
        var n = (Int(al.prefix(4)) ?? 0) - (Int(ingreso.prefix(4)) ?? 0)
        if al.dropFirst(5) < ingreso.dropFirst(5) { n -= 1 }
        return max(0, n)
    }

    /// Los pasos del reclamo y el estado de la API de cada uno.
    static let pasosTrabajo: [(String, String)] = [("pendiente", "Abierto"), ("aprobado", "Presupuesto"), ("en_curso", "En obra"), ("hecho", "Cerrado")]

    /// El chip de un trabajo: Esperando · Agendado · En obra · Cerrado.
    static func chipTrabajo(_ t: TrabajoAPI) -> (String, Tono) {
        switch t.estado {
        case "pendiente": return ("Esperando", .oro)
        case "aprobado": return (t.venceEl != nil ? "Agendado" : "Aprobado", .azul)
        case "en_curso": return ("En obra", .azul)
        case "hecho": return ("Cerrado", .verde)
        default: return ("Cancelado", .neutro)
        }
    }

    private static func hay(_ s: String, _ patron: String) -> Bool { s.range(of: patron, options: [.regularExpression, .caseInsensitive]) != nil }

    static func iconoTrabajo(_ t: TrabajoAPI) -> String {
        let s = "\(t.titulo) \(t.proveedorRubro ?? "")".lowercased()
        if hay(s, "filtr|humed|gote|agua|plom|ca[ñn]o|p[ée]rdida") { return "drop.triangle" }
        if hay(s, "luz|el[ée]ctr|l[aá]mpara|lumin") { return "lightbulb" }
        if hay(s, "ascensor") { return "arrow.up.arrow.down.square" }
        if hay(s, "port[oó]n|puerta|cerradura|herrer") { return "door.garage.closed" }
        if hay(s, "pint") { return "paintbrush" }
        if hay(s, "gas") { return "flame" }
        return "wrench.and.screwdriver"
    }

    static func iconoRubro(_ rubro: String?) -> String {
        let s = (rubro ?? "").lowercased()
        if hay(s, "plom|agua") { return "drop" }
        if hay(s, "el[ée]ctr") { return "bolt" }
        if hay(s, "ascensor|manten") { return "arrow.up.arrow.down.square" }
        if hay(s, "herrer|repar") { return "hammer" }
        if hay(s, "limp") { return "sparkles" }
        if hay(s, "segur") { return "shield" }
        return "wrench.and.screwdriver"
    }

    static func iconoGasto(_ g: GastoExpensas) -> String {
        let s = "\(g.descripcion) \(g.proveedorRubro ?? "")".lowercased()
        if hay(s, "f931|cargas|afip") { return "building.columns" }
        if hay(s, "sueldo|encargad|personal") { return "person.text.rectangle" }
        if hay(s, "edenor|edesur|luz|electric") { return "bolt" }
        if hay(s, "aysa|agua") { return "drop" }
        if hay(s, "ascensor") { return "arrow.up.arrow.down.square" }
        if hay(s, "limpi") { return "sparkles" }
        if hay(s, "port[oó]n|herrer") { return "door.garage.closed" }
        if hay(s, "segur") { return "shield" }
        if hay(s, "honorario|administr") { return "building.2" }
        if hay(s, "plom|ca[ñn]er") { return "drop" }
        return "doc.text"
    }

    /// El rubro de la fila del gasto: el del proveedor o, si no, la columna o el tipo.
    static func rubroGasto(_ g: GastoExpensas) -> String {
        g.proveedorRubro ?? (g.tipo == "extraordinaria" ? "Extraordinaria" : (g.columna ?? "Ordinaria"))
    }

    /// «+10,4 %» de un total contra el anterior.
    static func variacion(_ ahora: Double, _ antes: Double) -> String {
        guard antes != 0 else { return "" }
        let v = (ahora - antes) / antes * 100
        let s = v > 0 ? "+" : v < 0 ? "−" : ""
        return s + String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",") + " %"
    }

    /// Montos sin moneda, como en las tablas: «818.000».
    static func cifra(_ n: Double) -> String { Formato.numero(Int(n.rounded())) }

    /// Los días enteros desde una fecha ISO hasta hoy.
    static func diasDesde(_ f: String?) -> Int {
        guard let f, let a = Fecha.dia(String(f.prefix(10))), let b = Fecha.dia(hoy) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// «hoy», «ayer», «hace 6 días».
    static func haceDias(_ n: Int) -> String { n == 0 ? "hoy" : n == 1 ? "ayer" : "hace \(n) días" }

    /// Los chips de un edificio en la lista: morosos, liquidar el mes, reclamos; si nada, «Al día».
    static func chipsEdificio(_ c: ConsorcioAPI, _ liquidar: String?) -> [(String, Tono)] {
        let m = c.metricas
        var out: [(String, Tono)] = []
        if let d = m?.deudores, d > 0 { out.append((d == 1 ? "1 moroso" : "\(d) morosos", .rojo)) }
        if let l = liquidar { out.append(("Liquidar \(mesCorto(l))", .oro)) }
        if let t = m?.trabajosPendientes, t > 0 { out.append((t == 1 ? "1 reclamo" : "\(t) reclamos", .azul)) }
        if out.isEmpty { out.append(("Al día", .verde)) }
        return out
    }

    private static func claveUnidad(_ e: String) -> String {
        e.replacingOccurrences(of: "^\\s*(PB|planta baja)", with: "0", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "^\\s*(SS|subsuelo)", with: "-1", options: [.regularExpression, .caseInsensitive])
    }

    /// Las unidades como se leen en el edificio: PB, 1.º A, 1.º B… 10.º A.
    static func porUnidad(_ a: String, _ b: String) -> Bool {
        claveUnidad(a).compare(claveUnidad(b), options: [.numeric, .caseInsensitive, .diacriticInsensitive], locale: Formato.argentina) == .orderedAscending
    }

    /// Un monto con dos decimales a lo sumo (la API rechaza más).
    static func redondo(_ n: Double) -> Double { (n * 100).rounded() / 100 }

    static func plural(_ n: Int, _ uno: String, _ varios: String) -> String { Formato.cantidad(n, uno, varios) }

    /// «3.º B y 4.º A», «1.º A, 2.º B y 3.º C».
    static func lista(_ l: [String]) -> String {
        guard l.count > 1 else { return l.first ?? "" }
        return l.dropLast().joined(separator: ", ") + " y " + l.last!
    }

    static func copiar(_ s: String) { UIPasteboard.general.string = s }
}

// MARK: - Piezas comunes del área

/// Un chip de estado (cápsula en el tono).
struct ChipConsorcio: View {
    var texto: String
    var tono: Tono
    var body: some View {
        Text(texto).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
            .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
            .fixedSize()
    }
}

/// Un bloque con título (y una acción a la derecha) sobre una tarjeta de renglones.
struct BloqueConsorcio<Contenido: View>: View {
    var titulo: String?
    var tono: Tono? = nil
    var accion: (String, () -> Void)? = nil
    @ViewBuilder var contenido: () -> Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if titulo != nil || accion != nil {
                HStack {
                    if let titulo { Text(titulo).estilo(.subheadFuerte).foregroundStyle(tono?.tinta ?? C.texto) }
                    Spacer()
                    if let accion { Button(accion.0, action: accion.1).font(Estilo.subheadFuerte.font).foregroundStyle(C.accion) }
                }
                .padding(.horizontal, 4)
            }
            VStack(spacing: 0) { contenido() }.tarjeta()
        }
    }
}

/// Un renglón de una tarjeta (con la raya de arriba si no es el primero).
struct RenglonConsorcio<Contenido: View>: View {
    var primero = false
    @ViewBuilder var contenido: () -> Contenido
    var body: some View {
        HStack(spacing: 10) { contenido() }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if !primero { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }
}

/// Dos líneas: título fuerte y detalle.
struct DosLineasConsorcio: View {
    var titulo: String
    var detalle: String?
    var tonoDetalle: Color = C.texto2
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
            if let d = detalle?.nonEmpty { Text(d).estilo(.footnote).foregroundStyle(tonoDetalle).lineLimit(3) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El texto gris de una tarjeta vacía.
struct VacioConsorcio: View {
    var texto: String
    var body: some View {
        Text(texto).estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un archivo de la API (con la sesión): la foto de un trabajo, un comprobante.
struct ImagenConsorcio: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var imagen: UIImage?
    @State private var fallo = false

    var body: some View {
        Color.clear
            .overlay {
                if let imagen {
                    Image(uiImage: imagen).resizable().scaledToFill()
                } else {
                    ZStack { C.hundida; if fallo { Image(systemName: "photo").foregroundStyle(C.texto3) } else { ProgressView() } }
                }
            }
            .clipped()
            .task(id: id) {
                do {
                    let d = try await estado.api.pedir("GET", "/v1/archivos/\(id)/contenido")
                    imagen = UIImage(data: d)
                    fallo = imagen == nil
                } catch { fallo = true }
            }
            .accessibilityHidden(true)
    }
}

/// Un campo con etiqueta para las hojas (Form): etiqueta arriba en gris y el control.
struct CampoConsorcio<Contenido: View>: View {
    var etiqueta: String
    var ayuda: String? = nil
    @ViewBuilder var contenido: () -> Contenido
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etiqueta).estilo(.footnote).foregroundStyle(C.texto2)
            contenido()
            if let ayuda { Text(ayuda).estilo(.footnote).foregroundStyle(C.texto3) }
        }
    }
}

/// Elegir un archivo para subir: cámara, fotos o Archivos (el «soltá o tocá para elegir» de la web).
struct ElegirArchivoConsorcio: ViewModifier {
    @Binding var abierto: Bool
    var tiposArchivo: [UTType] = [.pdf, .image]
    var multiple = false
    /// Datos, nombre y tipo MIME de cada archivo elegido.
    var alElegir: ([(Data, String, String)]) -> Void
    @State private var camara = false
    @State private var fotos = false
    @State private var archivos = false
    @State private var elegidas: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Sumar", isPresented: $abierto) {
                Button("Sacar una foto") { camara = true }
                Button("Elegir de Fotos") { fotos = true }
                Button("Elegir de Archivos") { archivos = true }
                Button("Cancelar", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $camara) {
                Camara { d in alElegir([(d, "foto-\(Int(Date().timeIntervalSince1970)).jpg", "image/jpeg")]) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $fotos, selection: $elegidas, maxSelectionCount: multiple ? 10 : 1, matching: .images)
            .onChange(of: elegidas) { _, l in
                guard !l.isEmpty else { return }
                Task {
                    var out: [(Data, String, String)] = []
                    for (i, it) in l.enumerated() {
                        if let d = try? await it.loadTransferable(type: Data.self) {
                            let jpg = UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d
                            out.append((jpg, "foto-\(i + 1).jpg", "image/jpeg"))
                        }
                    }
                    elegidas = []
                    if !out.isEmpty { alElegir(out) }
                }
            }
            .fileImporter(isPresented: $archivos, allowedContentTypes: tiposArchivo, allowsMultipleSelection: multiple) { r in
                guard case .success(let urls) = r else { return }
                var out: [(Data, String, String)] = []
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource()
                    defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: u) {
                        let tipo = UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        out.append((d, u.lastPathComponent, tipo))
                    }
                }
                if !out.isEmpty { alElegir(out) }
            }
    }
}

extension View {
    func elegirArchivoConsorcio(_ abierto: Binding<Bool>, tipos: [UTType] = [.pdf, .image], multiple: Bool = false, alElegir: @escaping ([(Data, String, String)]) -> Void) -> some View {
        modifier(ElegirArchivoConsorcio(abierto: abierto, tiposArchivo: tipos, multiple: multiple, alElegir: alElegir))
    }
}

/// Los proveedores de la inmobiliaria (todos, de a 200).
enum ProveedoresConsorcio {
    static func todos(_ api: Api) async throws -> [ProveedorConsorcio] {
        try await api.todas("/v1/proveedores")
    }

    struct Nuevo: Encodable { var nombre: String; var rubro: String?; var cuit: String? = nil; var telefono: String? = nil; var email: String? = nil; var notas: String? = nil }

    /// Da de alta un proveedor (queda para todos los edificios).
    static func crear(_ api: Api, _ n: Nuevo) async throws -> ProveedorConsorcio {
        try await api.enviar("POST", "/v1/proveedores", n)
    }
}
