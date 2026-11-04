import QuickLook
import SwiftUI

// Los impresos (ficha A4, recibo, rendición, contrato, acta, expensas, recibo de sueldo, informe) se
// arman en el iPhone como PDF, con los mismos datos que la web: nada se abre en el navegador (que no
// tiene la sesión de la app). Se ven con la vista previa del sistema, que ya trae compartir e imprimir.

/// Un documento para imprimir: encabezado, bloques de filas (clave · valor), texto libre, foto y firmas.
struct Documento {
    struct Bloque {
        var titulo: String?
        var filas: [(String, String)] = []
        var texto: String? = nil
        var total: (String, String)? = nil
    }
    struct Firma { var parte: String; var nombre: String?; var trazo: String? }

    var titulo: String
    var subtitulo: String?
    var numero: String?
    var foto: UIImage? = nil
    var bloques: [Bloque] = []
    var firmas: [Firma] = []
    var pie: String? = nil
}

/// Arma el PDF (A4, 595 × 842 pt) en varias páginas si hace falta y lo deja en un archivo temporal.
@MainActor
enum Impresor {
    static let tam = CGSize(width: 595, height: 842)

    static func pdf(_ d: Documento, inmobiliaria: String, nombre: String) -> URL? {
        let paginas = paginar(d)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre.replacingOccurrences(of: "/", with: "-") + ".pdf")
        var caja = CGRect(origin: .zero, size: tam)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { return nil }
        for (i, p) in paginas.enumerated() {
            let r = ImageRenderer(content: HojaA4(inmobiliaria: inmobiliaria, documento: d, pagina: p, numero: i + 1, total: paginas.count))
            r.proposedSize = ProposedViewSize(tam)
            r.render { _, dibujar in
                ctx.beginPDFPage(nil)
                dibujar(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }

    /// Reparte los bloques en páginas por cantidad de renglones (unos 34 por página, menos en la primera
    /// si lleva foto).
    static func paginar(_ d: Documento) -> [[Documento.Bloque]] {
        var paginas: [[Documento.Bloque]] = [[]]
        var usados = d.foto == nil ? 0 : 12
        let tope = 34
        for b in d.bloques {
            var resto = b
            while true {
                let texto = (resto.texto?.count ?? 0) / 90 + (resto.texto == nil ? 0 : 1)
                let alto = 2 + resto.filas.count + texto + (resto.total == nil ? 0 : 2)
                if usados + alto <= tope || (usados == 0) {
                    if usados + alto > tope, resto.filas.count > tope - usados - 2 {
                        let entran = max(1, tope - usados - 2)
                        var parte = resto
                        parte.filas = Array(resto.filas.prefix(entran))
                        parte.total = nil
                        paginas[paginas.count - 1].append(parte)
                        resto.filas = Array(resto.filas.dropFirst(entran))
                        resto.titulo = resto.titulo.map { $0 + " (sigue)" }
                        paginas.append([])
                        usados = 0
                        continue
                    }
                    paginas[paginas.count - 1].append(resto)
                    usados += alto
                    break
                }
                paginas.append([])
                usados = 0
            }
        }
        return paginas
    }
}

/// Una página A4: la marca de la inmobiliaria arriba, los bloques y el pie «Hecha con Corredor».
struct HojaA4: View {
    var inmobiliaria: String
    var documento: Documento
    var pagina: [Documento.Bloque]
    var numero: Int
    var total: Int

    private let tinta = Color(hex: 0x18201D)
    private let gris = Color(hex: 0x6B6457)
    private let linea = Color(hex: 0xE3DDCF)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(inmobiliaria.prefix(1))).font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0xE9DCC3))
                    .frame(width: 34, height: 34).background(Color(hex: 0x1E3A5F), in: Circle())
                Text(inmobiliaria.uppercased()).font(.system(size: 13, weight: .bold)).tracking(0.6).foregroundStyle(Color(hex: 0x1E3A5F))
                Spacer()
                if let n = documento.numero { Text(n).font(.system(size: 11)).foregroundStyle(gris) }
            }
            Rectangle().fill(linea).frame(height: 1)
            if numero == 1 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(documento.titulo).font(.system(size: 22, weight: .bold)).foregroundStyle(tinta)
                    if let s = documento.subtitulo { Text(s).font(.system(size: 12)).foregroundStyle(gris) }
                }
                if let f = documento.foto {
                    Image(uiImage: f).resizable().scaledToFill().frame(height: 210).frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 8))
                }
            }
            ForEach(Array(pagina.enumerated()), id: \.offset) { _, b in
                VStack(alignment: .leading, spacing: 5) {
                    if let t = b.titulo { Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(gris).padding(.top, 4) }
                    ForEach(Array(b.filas.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .firstTextBaseline) {
                            Text(f.0).font(.system(size: 11)).foregroundStyle(gris)
                            Spacer(minLength: 12)
                            Text(f.1).font(.system(size: 11, weight: .medium)).foregroundStyle(tinta).multilineTextAlignment(.trailing)
                        }
                        Rectangle().fill(linea).frame(height: 0.5)
                    }
                    if let t = b.texto { Text(t).font(.system(size: 11)).foregroundStyle(tinta).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                    if let t = b.total {
                        HStack { Text(t.0).font(.system(size: 13, weight: .bold)); Spacer(); Text(t.1).font(.system(size: 13, weight: .bold)) }
                            .foregroundStyle(tinta).padding(.top, 4)
                    }
                }
            }
            if numero == total && !documento.firmas.isEmpty {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(Array(documento.firmas.enumerated()), id: \.offset) { _, f in
                        VStack(spacing: 4) {
                            Group {
                                if let t = f.trazo { TrazoFirma(trazo: t).environment(\.colorScheme, .light) } else { Color.clear }
                            }
                            .frame(height: 50)
                            Rectangle().fill(tinta).frame(height: 0.7)
                            Text(f.nombre ?? f.parte).font(.system(size: 10, weight: .semibold)).foregroundStyle(tinta)
                            Text(f.parte).font(.system(size: 9)).foregroundStyle(gris)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 16)
            }
            Spacer(minLength: 0)
            HStack {
                Text(documento.pie ?? "Hecha con Corredor").font(.system(size: 9)).foregroundStyle(gris)
                Spacer()
                if total > 1 { Text("\(numero) de \(total)").font(.system(size: 9)).foregroundStyle(gris) }
            }
        }
        .padding(36)
        .frame(width: Impresor.tam.width, height: Impresor.tam.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// La vista previa del sistema (QuickLook): ver, compartir, guardar en Archivos e imprimir.
struct VistaPrevia: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UINavigationController {
        let q = QLPreviewController()
        q.dataSource = context.coordinator
        return UINavigationController(rootViewController: q)
    }
    func updateUIViewController(_ c: UINavigationController, context: Context) {}
    func makeCoordinator() -> Fuente { Fuente(url: url) }
    final class Fuente: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

/// Un archivo para la vista previa (`.sheet(item:)`).
struct ArchivoPrevio: Identifiable { var url: URL; var id: String { url.absoluteString } }

extension View {
    /// Muestra un PDF armado en la app con la vista previa del sistema.
    func vistaPrevia(_ archivo: Binding<ArchivoPrevio?>) -> some View {
        sheet(item: archivo) { a in VistaPrevia(url: a.url).ignoresSafeArea() }
    }
}

/// Los documentos de Corredor, armados con los datos de la API.
@MainActor
enum Documentos {
    static func inmobiliaria(_ api: Api) async -> Inmobiliaria? { try? await api.get("/v1/inmobiliaria") }

    static func foto(_ url: URL?) async -> UIImage? {
        guard let url, let (d, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: d)
    }

    /// La ficha A4 de una propiedad (lo que se manda o se imprime para una visita).
    static func ficha(_ p: Propiedad, api: Api) async -> URL? {
        let inmo = await inmobiliaria(api)
        var datos: [(String, String)] = [("Operación", p.operacionTexto.capitalized), ("Tipo", p.tipoTexto)]
        if let a = p.ambientes { datos.append(("Ambientes", "\(a)")) }
        if let d = p.dormitorios { datos.append(("Dormitorios", "\(d)")) }
        if let b = p.banos { datos.append(("Baños", "\(b)")) }
        if let c = p.cocheras { datos.append(("Cocheras", "\(c)")) }
        if let s = p.superficie { datos.append(("Superficie total", "\(Formato.numero(Int(s))) m²")) }
        if let s = p.cubierta { datos.append(("Cubierta", "\(Formato.numero(Int(s))) m²")) }
        if let e = p.expensas { datos.append(("Expensas", Formato.plata(e, "ARS"))) }
        if p.aptoCredito == true { datos.append(("Apto crédito", "Sí")) }
        var bloques = [Documento.Bloque(titulo: "Datos", filas: datos)]
        if let d = p.descripcion?.nonEmpty { bloques.append(.init(titulo: "Descripción", texto: d)) }
        let extras = (p.comodidades ?? []) + (p.caracteristicas ?? []) + (p.servicios ?? [])
        if !extras.isEmpty { bloques.append(.init(titulo: "Comodidades", texto: extras.joined(separator: " · "))) }
        var contacto: [(String, String)] = []
        if let w = inmo?.web, let s = p.slug { contacto.append(("Ficha online", "\(w.replacingOccurrences(of: "https://", with: ""))/propiedades/\(s)")) }
        if !contacto.isEmpty { bloques.append(.init(titulo: "Más fotos y consultas", filas: contacto)) }
        let d = Documento(titulo: p.nombre, subtitulo: [p.precioTexto, p.barrio].compactMap { $0 }.joined(separator: " · "),
                          numero: p.numero.map { "LP-\(String(format: "%04d", $0))" }, foto: await foto(p.portada), bloques: bloques)
        return Impresor.pdf(d, inmobiliaria: inmo?.nombre ?? "Corredor", nombre: "Ficha \(p.nombre)")
    }

    /// El recibo de un cobro.
    static func recibo(_ c: Cobro, contrato k: ContratoAPI?, api: Api) async -> URL? {
        let inmo = await inmobiliaria(api)
        var filas: [(String, String)] = (c.conceptos ?? []).map { ($0.concepto, Formato.plata($0.monto, c.moneda)) }
        if filas.isEmpty { filas = [("Alquiler", Formato.plata(c.monto, c.moneda))] }
        let pago = [c.pagadoEl.flatMap(Fecha.dia).map { "Pagado el \(Formato.diaCompleto($0))" }, c.medio.map { "por \($0)" }].compactMap { $0 }.joined(separator: " ")
        let d = Documento(titulo: k?.contactoNombre ?? "Recibo", subtitulo: "\(k?.propiedadTitulo ?? "") · \(ReciboVista.mes(c.periodo))",
                          numero: c.numero.map { "Recibo N.º " + String(format: "0001-%05d", $0) },
                          bloques: [.init(titulo: "Conceptos", filas: filas, total: ("Total cobrado", Formato.plata(c.monto, c.moneda))),
                                    .init(texto: pago.isEmpty ? nil : pago)] + (inmo?.cbu.map { [.init(texto: "CBU o alias: \($0)")] } ?? []))
        return Impresor.pdf(d, inmobiliaria: inmo?.nombre ?? "Corredor", nombre: "Recibo \(c.periodo)")
    }

    /// La rendición al propietario.
    static func rendicion(_ r: RendicionAPI, contrato k: ContratoAPI?, api: Api) async -> URL? {
        let inmo = await inmobiliaria(api)
        let m = r.moneda ?? "ARS"
        var filas: [(String, String)] = [("Alquiler cobrado", Formato.plata(r.cobrado ?? 0, m))]
        if let c = r.comision, c > 0 { filas.append(("Administración \(Formato.numero(Int(r.comisionPorcentaje ?? 0))) %", "−" + Formato.plata(c, m))) }
        for it in r.items ?? [] { filas.append((it.descripcion, "−" + Formato.plata(it.monto, m))) }
        let d = Documento(titulo: k?.propietarioNombre ?? "Rendición", subtitulo: "\(k?.propiedadTitulo ?? "") · \(ReciboVista.mes(r.periodo))",
                          numero: r.numero.map { "Rendición N.º \($0)" },
                          bloques: [.init(titulo: "Detalle", filas: filas, total: ("A transferir", Formato.plata(r.neto ?? 0, m)))])
        return Impresor.pdf(d, inmobiliaria: inmo?.nombre ?? "Corredor", nombre: "Rendición \(r.periodo)")
    }

    /// El contrato: partes, plazo, monto, ajuste y condiciones.
    static func contrato(_ k: ContratoAPI, api: Api) async -> URL? {
        let inmo = await inmobiliaria(api)
        let m = k.moneda ?? "ARS"
        var partes: [(String, String)] = []
        if let x = k.contactoNombre { partes.append((k.tipo == "venta" ? "Comprador" : "Inquilino", x)) }
        if let x = k.propietarioNombre { partes.append(("Propietario", x)) }
        if let x = k.garanteNombre { partes.append(("Garante", x + (k.garanteTelefono.map { " · \($0)" } ?? ""))) }
        var cond: [(String, String)] = [("Desde", k.inicio.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "—"), ("Hasta", k.fin.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "—")]
        if let x = k.monto { cond.append((k.tipo == "venta" ? "Precio" : "Alquiler mensual", Formato.plata(x, m))) }
        if k.tipo != "venta" { cond.append(("Ajuste", k.ajusteTexto)) }
        if let x = k.diaVencimiento { cond.append(("Vence", "El \(x) de cada mes")) }
        if let x = k.deposito { cond.append(("Depósito", Formato.plata(x, m))) }
        if let x = k.honorarios { cond.append(("Honorarios", "\(Formato.numero(Int(x))) %")) }
        if let x = k.punitorioDiario { cond.append(("Punitorio diario", "\(x) %")) }
        if let x = k.comision { cond.append(("Administración", "\(Formato.numero(Int(x))) % de lo cobrado")) }
        var bloques = [Documento.Bloque(titulo: "Partes", filas: partes), .init(titulo: "Condiciones", filas: cond)]
        if let n = k.notas?.nonEmpty { bloques.append(.init(titulo: "Notas", texto: n)) }
        let d = Documento(titulo: k.propiedadTitulo ?? "Contrato", subtitulo: k.tipo == "venta" ? "Boleto de compraventa · resumen" : "Contrato de locación · resumen",
                          bloques: bloques, firmas: [.init(parte: k.tipo == "venta" ? "Comprador" : "Inquilino", nombre: k.contactoNombre),
                                                     .init(parte: "Propietario", nombre: k.propietarioNombre)])
        return Impresor.pdf(d, inmobiliaria: inmo?.nombre ?? "Corredor", nombre: "Contrato \(k.propiedadTitulo ?? "")")
    }

    /// El acta de entrega o devolución: cada ambiente con sus ítems y su estado, y las tres firmas.
    static func acta(_ a: Acta, items: [ItemInventario], propiedad: String, api: Api) async -> URL? {
        let inmo = await inmobiliaria(api)
        var ambientes: [String] = []
        for i in items where !ambientes.contains(i.ambiente) { ambientes.append(i.ambiente) }
        var bloques = ambientes.map { amb in
            Documento.Bloque(titulo: amb, filas: items.filter { $0.ambiente == amb }.map { i in
                (i.descripcion + (i.cantidad.map { $0 > 1 ? " × \($0)" : "" } ?? ""),
                 (ItemInventario.estados.first { $0.0 == i.estado }?.1 ?? i.estado) + (i.notas?.nonEmpty.map { " · \($0)" } ?? ""))
            })
        }
        if let o = a.observaciones?.nonEmpty { bloques.append(.init(titulo: "Observaciones", texto: o)) }
        let firmas = [("inquilino", "Inquilino"), ("propietario", "Propietario"), ("inmobiliaria", "Inmobiliaria")].map { k, n in
            Documento.Firma(parte: n, nombre: a.firmas?[k]?.nombre, trazo: a.firmas?[k]?.trazo)
        }
        let d = Documento(titulo: a.tipo == "devolucion" ? "Acta de devolución" : "Acta de entrega",
                          subtitulo: "\(propiedad) · \(a.fecha.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "")", bloques: bloques, firmas: firmas,
                          pie: "Las partes aceptan el estado de cada ambiente tal como quedó registrado. Hecha con Corredor")
        return Impresor.pdf(d, inmobiliaria: inmo?.nombre ?? "Corredor", nombre: "Acta \(propiedad)")
    }

    /// Cualquier respuesta de la API (liquidación de expensas, recibo de sueldo): las listas como bloques
    /// y los campos sueltos como filas.
    static func generico(titulo: String, subtitulo: String?, json: JSONLibre, api: Api, nombre: String) async -> URL? {
        let inmo = await inmobiliaria(api)
        var bloques: [Documento.Bloque] = []
        var sueltos: [(String, String)] = []
        if case .objeto(let o) = json {
            for (k, v) in o.sorted(by: { $0.key < $1.key }) {
                switch v {
                case .texto(let t): if !k.hasSuffix("Id"), k != "id" { sueltos.append((Self.etiqueta(k), t)) }
                case .numero(let n): sueltos.append((Self.etiqueta(k), Formato.numero(Int(n))))
                case .lista(let l):
                    let filas: [(String, String)] = l.prefix(200).map { x in
                        (ListaGenerica.titulo(x), ["monto", "total", "importe", "saldo", "neto", "subtotal"].compactMap { if case .numero(let n)? = x[$0] { return Formato.plata(n) }; return nil }.first ?? (ListaGenerica.detalle(x) ?? ""))
                    }
                    if !filas.isEmpty { bloques.append(.init(titulo: Self.etiqueta(k), filas: filas)) }
                default: break
                }
            }
        }
        if !sueltos.isEmpty { bloques.insert(.init(titulo: nil, filas: sueltos), at: 0) }
        return Impresor.pdf(Documento(titulo: titulo, subtitulo: subtitulo, bloques: bloques), inmobiliaria: inmo?.nombre ?? "Corredor", nombre: nombre)
    }

    static func etiqueta(_ k: String) -> String {
        var s = ""
        for c in k { if c.isUppercase { s += " " + c.lowercased() } else { s.append(c) } }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Un archivo crudo de la API (el F931 para AFIP) guardado para compartir.
    static func archivo(_ ruta: String, nombre: String, api: Api) async throws -> URL {
        let d = try await api.pedir("GET", ruta)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(nombre)
        try d.write(to: u)
        return u
    }
}
