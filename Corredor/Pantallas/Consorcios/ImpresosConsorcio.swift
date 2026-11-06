import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// Los impresos de Consorcios, como los A4 del panel ((impresos)/consorcios/[id]/imprimir): la
// liquidación de expensas (una hoja por unidad, con el QR al recibo público) y el recibo de sueldo
// (con las dos firmas). Se arman en el iPhone como PDF y se ven con la vista previa del sistema.

extension Documentos {
    /// La liquidación de expensas del período: una hoja por unidad (`unidad`: sólo esa).
    static func expensas(consorcio: String, periodo pid: String, unidad: String?, api: Api) async throws -> URL {
        let base = "/v1/consorcios/\(consorcio)"
        let c: ConsorcioAPI = try await api.get(base)
        let p: PeriodoAPI = try await api.get("\(base)/periodos/\(pid)")
        let inmo = await inmobiliaria(api)
        let proveedores: [ProveedorConsorcio] = (try? await ProveedoresConsorcio.todos(api)) ?? []
        let liqs = (p.liquidaciones ?? []).filter { unidad == nil || $0.unidadId == unidad }.sorted { Cons.porUnidad($0.unidad, $1.unidad) }
        guard !liqs.isEmpty else {
            throw ErrorApi(estado: 404, codigo: "sin_liquidacion", titulo: "Sin liquidación",
                           detalle: p.estado == "borrador" ? "Este período todavía no se liquidó." : "Esa unidad no tiene liquidación en este período.")
        }

        // Cómo se reparte el gasto del período, por rubro del proveedor.
        let rubroDe = Dictionary(proveedores.map { ($0.id, $0.rubro?.trimmingCharacters(in: .whitespaces).nonEmpty) }, uniquingKeysWith: { a, _ in a })
        var porRubro: [(String, Double)] = []
        var total = 0.0
        for g in p.gastos ?? [] {
            let r = (g.proveedorId.flatMap { rubroDe[$0] ?? nil }) ?? (g.tipo == "extraordinaria" ? "Extraordinarias" : "Otros")
            if let i = porRubro.firstIndex(where: { $0.0 == r }) { porRubro[i].1 += g.monto } else { porRubro.append((r, g.monto)) }
            total += g.monto
        }
        let rubros: [(String, Int)] = total > 0 ? porRubro.map { ($0.0, Int(($0.1 / total * 100).rounded())) }.sorted { $0.1 > $1.1 } : []

        // Los vencimientos: los días del consorcio, en el mes siguiente al período.
        let sig = Cons.mesSiguiente(p.periodo)
        let dm: (Int) -> String = { String(format: "%02d/%@", $0, String(sig.suffix(2))) }
        var vence = ""
        if let d1 = c.diaVencimiento {
            vence = "Vence el \(dm(d1))"
            if let d2 = c.diaSegundoVencimiento {
                vence += "; 2.º vto. \(dm(d2))"
                if let i = c.interesMensual, i > 0 { vence += " con \(Cons.coma(i)) % de recargo" }
            }
            vence += "."
        }

        var hojas: [HojaExpensasA4.Datos] = []
        for l in liqs {
            let cuenta: CuentaUnidadAPI? = try? await api.get("\(base)/unidades/\(l.unidadId)/cuenta")
            let historial: [LiquidacionExpensas] = (try? await api.get("\(base)/unidades/\(l.unidadId)/liquidaciones")) ?? []
            let link: LinkConsorcio? = try? await api.enviar("POST", "\(base)/liquidaciones/\(l.id)/link", [String: String]())
            // El saldo anterior sólo tiene sentido en la última liquidación: lo que se debe además de esta.
            var anterior = 0.0
            if historial.first?.id == l.id, let k = cuenta { anterior = max(0, Cons.redondo(k.saldo - l.total)) + (k.interesEstimado ?? 0) }
            hojas.append(.init(liquidacion: l, anterior: anterior, qr: link.flatMap { qrConsorcio($0.url) }))
        }
        let mm = "\(p.periodo.suffix(2))/\(p.periodo.prefix(4))"
        let vistas: [AnyView] = hojas.map { h in
            AnyView(HojaExpensasA4(consorcio: c.nombre, cuit: c.cuit, inmobiliaria: inmo?.nombre ?? "Corredor", mm: mm, mes: Cons.nombreMes(p.periodo),
                                   rubros: rubros, vence: vence, d: h))
        }
        let nombre = "Expensas \(p.periodo.suffix(2))-\(p.periodo.prefix(4))\(liqs.count == 1 ? " · \(liqs[0].unidad)" : "")"
        guard let u = pdfDePaginas(vistas, nombre: nombre) else { throw ErrorApi.desconocido }
        return u
    }

    /// El recibo de sueldo A4: membrete con CUIT, CUIL, categoría, antigüedad, haberes y descuentos,
    /// el neto y las dos firmas.
    static func sueldo(consorcio: String, recibo: String, api: Api) async throws -> URL {
        let base = "/v1/consorcios/\(consorcio)"
        let c: ConsorcioAPI = try await api.get(base)
        let r: ReciboSueldoAPI = try await api.get("\(base)/sueldos/\(recibo)")
        let empleados: [EmpleadoAPI] = (try? await api.get("\(base)/empleados")) ?? []
        let e = empleados.first { $0.id == r.empleadoId }
        // Los años de antigüedad al mes del recibo.
        var anios: Int?
        if let i = e?.ingreso {
            let ai = Int(i.prefix(4)) ?? 0, mi = Int(i.dropFirst(5).prefix(2)) ?? 0
            let ap = Int(r.periodo.prefix(4)) ?? 0, mp = Int(r.periodo.dropFirst(5).prefix(2)) ?? 0
            anios = max(0, ap - ai - (mp < mi ? 1 : 0))
        }
        let v = AnyView(HojaSueldoA4(c: c, r: r, e: e, anios: anios))
        guard let u = pdfDePaginas([v], nombre: "Recibo de sueldo \(r.empleado) \(r.periodo)") else { throw ErrorApi.desconocido }
        return u
    }

    /// Un archivo de la API (un comprobante, un adjunto) guardado con su nombre, para la vista previa.
    static func archivoConsorcio(_ id: String, api: Api) async throws -> URL {
        struct A: Decodable { var nombre: String? }
        let a: A? = try? await api.get("/v1/archivos/\(id)")
        return try await archivo("/v1/archivos/\(id)/contenido", nombre: (a?.nombre?.nonEmpty ?? "archivo-\(id.prefix(8))").replacingOccurrences(of: "/", with: "-"), api: api)
    }

    /// Un QR (para el link del recibo público).
    static func qrConsorcio(_ texto: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(texto.utf8)
        f.correctionLevel = "M"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Un PDF A4 con una página por vista.
    static func pdfDePaginas(_ vistas: [AnyView], nombre: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre.replacingOccurrences(of: "/", with: "-") + ".pdf")
        var caja = CGRect(origin: .zero, size: Impresor.tam)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { return nil }
        for v in vistas {
            let r = ImageRenderer(content: v.frame(width: Impresor.tam.width, height: Impresor.tam.height).background(Color.white).environment(\.colorScheme, .light))
            r.proposedSize = ProposedViewSize(Impresor.tam)
            r.render { _, dibujar in
                ctx.beginPDFPage(nil)
                dibujar(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }

    /// «12.345,50»: el número con miles y hasta dos decimales.
    static func numeroPapel(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = n.rounded() == n ? 0 : 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// El membrete de la familia de papel: la inicial en el cuadrado verde, el nombre, la línea de abajo y
/// el número arriba a la derecha, con la raya verde.
struct MembreteConsorcio: View {
    var nombre: String
    var detalle: String?
    var numero: String?
    var letra: String?
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let letra {
                    Text(String(letra.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Color(hex: 0x16443B), in: .rect(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(nombre).font(.system(size: 13, weight: .bold))
                    if let detalle { Text(detalle).font(.system(size: 10)).foregroundStyle(Color(hex: 0x6B6457)) }
                }
                Spacer()
                if let numero { Text(numero).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x6B6457)) }
            }
            Rectangle().fill(Color(hex: 0x16443B)).frame(height: 2)
        }
    }
}

/// Una hoja de la liquidación de expensas (una unidad).
struct HojaExpensasA4: View {
    struct Datos { var liquidacion: LiquidacionExpensas; var anterior: Double; var qr: UIImage? }
    var consorcio: String
    var cuit: String?
    var inmobiliaria: String
    var mm: String
    var mes: String
    var rubros: [(String, Int)]
    var vence: String
    var d: Datos

    private let tinta = Color(hex: 0x18201D)
    private let raya = Color(hex: 0xE3E0D8)

    var body: some View {
        let l = d.liquidacion
        VStack(alignment: .leading, spacing: 12) {
            MembreteConsorcio(nombre: consorcio, detalle: "Adm. \(inmobiliaria)\(cuit.map { " · CUIT \($0)" } ?? "")", numero: "LIQ. \(mm)", letra: inmobiliaria)
            Text("Expensas de \(mes) · \(l.unidad)").font(.system(size: 16, weight: .bold))
            VStack(spacing: 0) {
                ForEach(Array((l.desglose ?? []).enumerated()), id: \.offset) { i, x in
                    renglon("\(x.columna) (\(Documentos.numeroPapel(Cons.redondo(x.coeficiente * 100))) %)", Documentos.numeroPapel(x.monto), primero: i == 0)
                }
                if let f = l.fondo, f > 0 { renglon("Fondo de reserva", Documentos.numeroPapel(f)) }
                if d.anterior > 0 { renglon("Saldo anterior + interés", Documentos.numeroPapel(d.anterior), rojo: true) }
                HStack {
                    Text("Total a pagar").font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text(Formato.plata(l.total + d.anterior)).font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .overlay(alignment: .top) { Rectangle().fill(raya).frame(height: 1) }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(raya))
            if !rubros.isEmpty {
                Text(rubros.map { "\($0.0) \($0.1)\u{00A0}%" }.joined(separator: "   ")).font(.system(size: 10)).foregroundStyle(Color(hex: 0x6B6457))
            }
            if d.qr != nil || !vence.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if let q = d.qr { Image(uiImage: q).interpolation(.none).resizable().frame(width: 84, height: 84) }
                    Text("\(d.qr != nil ? "Escaneá para ver el detalle, los comprobantes y pagar. " : "")\(vence)").font(.system(size: 10.5)).foregroundStyle(tinta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text("Hecha con Corredor").font(.system(size: 9)).foregroundStyle(Color(hex: 0x6B6457))
        }
        .foregroundStyle(tinta)
        .padding(32)
        .frame(width: Impresor.tam.width, height: Impresor.tam.height, alignment: .topLeading)
    }

    private func renglon(_ a: String, _ b: String, primero: Bool = false, rojo: Bool = false) -> some View {
        HStack {
            Text(a)
            Spacer(minLength: 12)
            Text(b)
        }
        .font(.system(size: 11)).foregroundStyle(rojo ? Color(hex: 0xA3392F) : tinta)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .overlay(alignment: .top) { if !primero { Rectangle().fill(Color(hex: 0xEFEDE7)).frame(height: 1) } }
    }
}

/// El recibo de sueldo A4.
struct HojaSueldoA4: View {
    var c: ConsorcioAPI
    var r: ReciboSueldoAPI
    var e: EmpleadoAPI?
    var anios: Int?

    private let tinta = Color(hex: 0x18201D)
    private let gris = Color(hex: 0x6B6457)

    var body: some View {
        let haberes: [(String, Double)] = [("Sueldo básico", r.basico ?? 0),
                                           (anios.map { "Antigüedad \(Cons.plural($0, "año", "años"))" } ?? "Antigüedad", r.antiguedad ?? 0),
                                           ("Otros remunerativos", r.otrosRemunerativos ?? 0)].filter { $0.1 > 0 }
        VStack(alignment: .leading, spacing: 12) {
            MembreteConsorcio(nombre: c.nombre + (c.cuit.map { " ·\u{00A0}CUIT\u{00A0}\($0)" } ?? ""), detalle: nil, numero: "RECIBO \(r.periodo.suffix(2))/\(r.periodo.prefix(4))", letra: nil)
            HStack(alignment: .firstTextBaseline) {
                (Text(r.empleado).bold() + Text(e?.documento.map { " · CUIL \($0)" } ?? "")).font(.system(size: 11))
                Spacer()
                if let k = e?.categoria { Text(k).font(.system(size: 11)).foregroundStyle(gris) }
            }
            VStack(spacing: 0) {
                fila("Concepto", "Haberes", "Descuentos", cabeza: true)
                ForEach(Array(haberes.enumerated()), id: \.offset) { _, h in fila(h.0, Documentos.numeroPapel(h.1), "") }
                ForEach(Array((r.deducciones ?? []).enumerated()), id: \.offset) { _, x in
                    fila("\(x.nombre) \(Cons.coma(x.tasa))\u{00A0}%", "", Documentos.numeroPapel(x.monto))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xE3E0D8)))
            HStack {
                Text("Neto a cobrar").font(.system(size: 12, weight: .bold))
                Spacer()
                Text(Formato.plata(r.neto ?? 0)).font(.system(size: 15, weight: .bold))
            }
            HStack(spacing: 40) {
                ForEach(["Firma del empleador", "Firma del empleado"], id: \.self) { f in
                    VStack(spacing: 4) {
                        Rectangle().fill(tinta).frame(height: 0.7)
                        Text(f).font(.system(size: 10)).foregroundStyle(gris)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 60)
            Spacer(minLength: 0)
            Text("Hecha con Corredor").font(.system(size: 9)).foregroundStyle(gris)
        }
        .foregroundStyle(tinta)
        .padding(32)
        .frame(width: Impresor.tam.width, height: Impresor.tam.height, alignment: .topLeading)
    }

    private func fila(_ a: String, _ b: String, _ d: String, cabeza: Bool = false) -> some View {
        HStack {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(width: 110, alignment: .trailing)
            Text(d).frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 11, weight: cabeza ? .semibold : .regular)).foregroundStyle(cabeza ? gris : tinta)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .overlay(alignment: .top) { if !cabeza { Rectangle().fill(Color(hex: 0xEFEDE7)).frame(height: 1) } }
    }
}
