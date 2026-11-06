import SwiftUI

/// Tarjeta del agente · 85 × 55 mm (08 · T2 «se arma sola desde Equipo»): la foto, la marca de la
/// inmobiliaria, el nombre, de qué barrios es (los de su cartera) y cómo encontrarlo. Se ve en
/// pantalla y se comparte o imprime como PDF del tamaño de la tarjeta.
struct TarjetaAgente: View {
    @Environment(Estado.self) private var estado
    var usuario: String
    @State private var datos: Datos?
    @State private var error: ErrorApi?
    @State private var noEsta = false
    @State private var previa: ArchivoPrevio?

    /// `GET /v1/equipo` (equipo.Miembro, con el WhatsApp).
    struct Persona: Decodable { var usuarioId: String; var email: String?; var nombre: String?; var apellido: String?; var foto: String?; var telefono: String?; var whatsapp: String?; var rol: String? }
    struct ConBarrio: Decodable, Identifiable { var id: String; var barrio: String? }

    struct Datos {
        var nombre: String
        var email: String
        var telefono: String?
        var foto: UIImage?
        var rol: String
        var barrios: [String]
        var inmobiliaria: String
        var marca: MarcaResumen
        var linea: String { ([rol == "duenio" ? "Corredor inmobiliario" : "Agente", barrios.isEmpty ? nil : barrios.joined(separator: " y ")] as [String?]).compactMap { $0 }.joined(separator: " · ") }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let datos {
                    TarjetaImpresa(d: datos)
                        .frame(width: 340, height: 220)
                        .clipShape(.rect(cornerRadius: 10))
                        .sombraE2()
                    Text(Formato.sinViudas("85 × 55 mm. Compartila o mandala a imprimir.")).estilo(.footnote).foregroundStyle(C.texto2)
                    Button { previa = pdf(datos).map(ArchivoPrevio.init) } label: { Label("Compartir o imprimir", systemImage: "printer") }
                        .buttonStyle(BotonPrincipal())
                } else if noEsta {
                    EstadoVacio(icono: "person.crop.circle.badge.questionmark", titulo: "Esa persona no está en el equipo.",
                                accion: ("Ver el equipo", { estado.abrir(ASeccion(clave: "equipo")) }))
                    .padding(.top, 60)
                } else if let error {
                    EstadoError(que: "la tarjeta", error: error) { Task { await cargar() } }.padding(.top, 60)
                } else {
                    Esqueleto(ancho: 340, alto: 220, radio: 10)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(FondoApp())
        .pantallaApilada(datos.map { "Tarjeta · \($0.nombre)" } ?? "Tarjeta")
        .task { await cargar() }
        .vistaPrevia($previa)
    }

    private func cargar() async {
        do {
            let equipo: [Persona] = try await estado.api.get("/v1/equipo")
            guard let m = equipo.first(where: { $0.usuarioId == usuario }), m.rol != "lector" else { noEsta = true; return }
            let inmo: Inmobiliaria? = try? await estado.api.get("/v1/inmobiliaria")
            let props: [ConBarrio] = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "agente", value: usuario), .init(name: "limite", value: "200")])) ?? []
            var cuenta: [String: Int] = [:]
            for p in props { if let b = p.barrio?.nonEmpty { cuenta[b, default: 0] += 1 } }
            let barrios = cuenta.sorted { $0.value > $1.value }.prefix(2).map(\.key)
            let nombre = [m.nombre, m.apellido].compactMap { $0?.nonEmpty }.joined(separator: " ").nonEmpty ?? m.email ?? ""
            let foto = await Documentos.foto(m.foto.flatMap(URL.init(string:)))
            let tel = (m.whatsapp ?? m.telefono).map { $0.replacingOccurrences(of: "^\\s*\\+?54\\s*9?\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            datos = Datos(nombre: nombre, email: m.email ?? "", telefono: tel?.nonEmpty, foto: foto, rol: m.rol ?? "agente", barrios: barrios,
                          inmobiliaria: inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "", marca: MarcaResumen(marca: inmo?.marca, nombre: inmo?.nombre ?? ""))
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }

    /// El PDF del tamaño de la tarjeta (85 × 55 mm = 241 × 156 pt).
    @MainActor
    private func pdf(_ d: Datos) -> URL? {
        let tam = CGSize(width: 241, height: 156)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tarjeta \(d.nombre).pdf".replacingOccurrences(of: "/", with: "-"))
        var caja = CGRect(origin: .zero, size: tam)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else {
            estado.avisar("No pudimos armar la tarjeta.", ok: false)
            return nil
        }
        let r = ImageRenderer(content: TarjetaImpresa(d: d).frame(width: tam.width, height: tam.height))
        r.proposedSize = ProposedViewSize(tam)
        r.render { _, dibujar in
            ctx.beginPDFPage(nil)
            dibujar(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }
}

/// La tarjeta en sí (siempre clara, como el papel): la foto a la izquierda y los datos con la marca.
struct TarjetaImpresa: View {
    var d: TarjetaAgente.Datos

    var body: some View {
        GeometryReader { g in
            let e = g.size.width / 241
            HStack(spacing: 0) {
                ZStack {
                    d.marca.primario
                    if let f = d.foto {
                        Image(uiImage: f).resizable().scaledToFill()
                    } else {
                        Text(Formato.iniciales(d.nombre)).font(.system(size: 26 * e, weight: .bold)).foregroundStyle(d.marca.acento)
                    }
                }
                .frame(width: g.size.width * 0.36).clipped()
                VStack(alignment: .leading, spacing: 3 * e) {
                    HStack(spacing: 4 * e) {
                        Text(d.marca.inicial).font(.system(size: 8 * e, weight: .bold)).foregroundStyle(d.marca.acento)
                            .frame(width: 14 * e, height: 14 * e).background(d.marca.primario, in: Circle())
                        Text(d.inmobiliaria.uppercased()).font(.system(size: 7 * e, weight: .bold)).tracking(0.4).foregroundStyle(d.marca.primario).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(d.nombre).font(.system(size: 13 * e, weight: .bold)).foregroundStyle(Color(hex: 0x18201D)).lineLimit(2).minimumScaleFactor(0.7)
                    Text(d.linea).font(.system(size: 7.5 * e)).foregroundStyle(Color(hex: 0x6B6457)).lineLimit(2)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 1) {
                        if let t = d.telefono { Text(t) }
                        Text(d.email)
                    }
                    .font(.system(size: 7 * e, weight: .medium)).foregroundStyle(Color(hex: 0x18201D)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 3 * e) {
                        Image("Simbolo").resizable().scaledToFit().frame(width: 7 * e, height: 7 * e).opacity(0.6)
                        Text("Hecha con Corredor").font(.system(size: 5.5 * e)).foregroundStyle(Color(hex: 0x6B6457))
                    }
                }
                .padding(10 * e)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
        }
        .environment(\.colorScheme, .light)
    }
}
