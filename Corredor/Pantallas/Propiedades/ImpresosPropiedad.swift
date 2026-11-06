import CoreImage.CIFilterBuiltins
import SwiftUI

// Los impresos de una propiedad (web: (impresos)/propiedades/[id]/ficha y /tarjeta): la ficha A4 para
// entregar (foto, dirección y precio, lo que tiene, dos fotos más, el agente con su teléfono y el QR a
// la ficha pública o al WhatsApp del agente) y la tarjeta de 85 × 55 mm que se deja en la visita.

@MainActor
enum FichaImpresa {
    struct Datos {
        var p: Propiedad
        var inmobiliaria: String
        var fotos: [UIImage]
        var agente: String?
        var telefono: String?
        var qr: UIImage?
        var publica: Bool
    }

    /// Un QR nítido (sin suavizar) del texto.
    static func qr(_ texto: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(texto.utf8)
        f.correctionLevel = "M"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func datos(_ p: Propiedad, api: Api, fotos cuantas: Int) async -> Datos {
        let inmo: Inmobiliaria? = try? await api.get("/v1/inmobiliaria")
        let equipo: [Miembro] = (try? await api.get("/v1/equipo")) ?? []
        let m = equipo.first { $0.usuarioId == p.agenteId }
        let publica = p.publicada == true && p.slug != nil ? "\(inmo?.web ?? Api.web().absoluteString)/propiedades/\(p.slug ?? "")" : nil
        let wa = m?.telefono.map { "https://wa.me/\($0.filter(\.isNumber))" }
        var fotos: [UIImage] = []
        for u in (p.fotosUrl ?? []).prefix(cuantas) {
            if let url = URL(string: u), let i = await Documentos.foto(url) { fotos.append(i) }
        }
        return Datos(p: p, inmobiliaria: inmo?.nombre ?? "Corredor", fotos: fotos, agente: m?.completo, telefono: m?.telefono,
                     qr: (publica ?? wa).flatMap { qr($0) }, publica: publica != nil)
    }

    /// La ficha A4 en PDF.
    static func a4(_ p: Propiedad, api: Api) async -> URL? {
        let d = await datos(p, api: api, fotos: 3)
        return pdf(HojaFichaA4(d: d), tam: CGSize(width: 595, height: 842), nombre: "Ficha \(p.nombre)")
    }

    /// La tarjeta de 85 × 55 mm en PDF (241 × 156 pt).
    static func tarjeta(_ p: Propiedad, api: Api) async -> URL? {
        let d = await datos(p, api: api, fotos: 1)
        return pdf(HojaTarjeta(d: d), tam: CGSize(width: 241, height: 156), nombre: "Tarjeta \(p.nombre)")
    }

    static func pdf<V: View>(_ v: V, tam: CGSize, nombre: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre.replacingOccurrences(of: "/", with: "-") + ".pdf")
        var caja = CGRect(origin: .zero, size: tam)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { return nil }
        let r = ImageRenderer(content: v.frame(width: tam.width, height: tam.height))
        r.proposedSize = ProposedViewSize(tam)
        r.render { _, dibujar in
            ctx.beginPDFPage(nil)
            dibujar(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// «Belgrano · 3 amb · 74 m² · 2 dorm. · 1 baño · apto crédito · expensas ARS 80.000».
    static func linea(_ p: Propiedad) -> String {
        let credito = p.aptoCredito == true && !(p.comodidades ?? []).contains { $0.lowercased().contains("crédito") || $0.lowercased().contains("credito") }
        return [p.barrio, p.ambientes.map { "\($0) amb" }, p.superficie.map { "\(Formato.numero(Int($0))) m²" }, p.dormitorios.map { "\($0) dorm." },
                p.banos.map { Formato.cantidad($0, "baño", "baños") }, credito ? "apto crédito" : nil, p.expensas.map { "expensas \(Formato.plata($0, "ARS"))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// La ficha A4 (07 · 48 «Ficha para entregar · A4»).
struct HojaFichaA4: View {
    var d: FichaImpresa.Datos
    var body: some View {
        let p = d.p
        let n = p.fotosUrl?.count ?? 0
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(hex: 0xECE6DA)
                if let f = d.fotos.first { Image(uiImage: f).resizable().scaledToFill() }
                Text(d.inmobiliaria.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.white, in: .rect(cornerRadius: 4)).padding(16)
            }
            .frame(height: 340).clipped()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.titulo ?? p.nombre).font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text(p.precioTexto).font(.system(size: 20, weight: .bold))
                }
                Text(FichaImpresa.linea(p)).font(.system(size: 11)).foregroundStyle(Color(white: 0.3))
                if d.fotos.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(1..<min(3, d.fotos.count), id: \.self) { i in
                            Image(uiImage: d.fotos[i]).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 4))
                        }
                    }
                }
                if let t = p.descripcion?.nonEmpty { Text(t).font(.system(size: 10.5)).lineLimit(10) }
                Spacer(minLength: 0)
                if d.qr != nil || d.agente != nil {
                    HStack(spacing: 12) {
                        if let q = d.qr { Image(uiImage: q).interpolation(.none).resizable().frame(width: 64, height: 64) }
                        VStack(alignment: .leading, spacing: 2) {
                            if let a = d.agente { Text(a + (d.telefono.map { " · \($0)" } ?? "")).font(.system(size: 11, weight: .bold)) }
                            if d.qr != nil {
                                Text(d.publica ? (n > 1 ? "Escaneá para ver las \(n) fotos y consultar" : "Escaneá para ver la ficha y consultar") : "Escaneá y escribime")
                                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.35))
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(hex: 0xFAF8F3))
        .environment(\.colorScheme, .light)
    }
}

/// La tarjeta de 85 × 55 mm (08 · T3 «se deja en la visita»).
struct HojaTarjeta: View {
    var d: FichaImpresa.Datos
    var body: some View {
        let p = d.p
        let n = p.fotosUrl?.count ?? 0
        let linea1 = [p.ambientes.map { "\($0) amb" }, p.superficie.map { "\(Formato.numero(Int($0))) m²" }].compactMap { $0 }.joined(separator: " · ")
        let extras = (p.comodidades ?? []).map { $0.lowercased() } + (p.aptoCredito == true ? ["apto crédito"] : [])
        let linea2 = extras.reduce([String]()) { acc, x in acc.joined(separator: " · ").count + x.count <= 20 || acc.isEmpty ? acc + [x] : acc }.joined(separator: " · ")
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(hex: 0xECE6DA)
                if let f = d.fotos.first { Image(uiImage: f).resizable().scaledToFill() }
                Text(p.precioTexto).font(.system(size: 7, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 5).frame(height: 15).background(.white, in: .rect(cornerRadius: 4)).padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(p.titulo ?? p.nombre).font(.system(size: 7.5, weight: .bold)).lineLimit(3)
                Text(linea1 + (linea2.isEmpty ? "" : "\n" + linea2)).font(.system(size: 6.5)).foregroundStyle(Color(white: 0.4))
                Spacer(minLength: 0)
                if let q = d.qr, d.publica {
                    Image(uiImage: q).interpolation(.none).resizable().frame(width: 44, height: 44)
                    Text(n > 1 ? "\(n) fotos y consulta" : "Fotos y consulta").font(.system(size: 6)).foregroundStyle(Color(white: 0.4))
                }
            }
            .padding(10).frame(width: 90, alignment: .leading)
        }
        .background(Color(hex: 0xFAF8F3))
        .environment(\.colorScheme, .light)
    }
}

/// La tarjeta para la visita: cómo queda y el PDF para imprimir o mandar.
struct TarjetaVisita: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var d: FichaImpresa.Datos?
    @State private var error: ErrorApi?
    @State private var previo: ArchivoPrevio?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let d {
                    HojaTarjeta(d: d).frame(width: 340, height: 220).clipShape(.rect(cornerRadius: 8)).sombraE2()
                    Text(Formato.sinViudas("85 × 55 mm, para dejar en la visita. El QR abre la ficha en tu web (sólo si está publicada)."))
                        .estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.center)
                    Button { Task { if let u = await FichaImpresa.tarjeta(d.p, api: estado.api) { previo = ArchivoPrevio(url: u) } } } label: {
                        Label("Imprimir o mandar", systemImage: "printer")
                    }
                    .buttonStyle(BotonPrincipal())
                    Button { Task { if let u = await FichaImpresa.a4(d.p, api: estado.api) { previo = ArchivoPrevio(url: u) } } } label: {
                        Label("La ficha A4", systemImage: "doc.richtext")
                    }
                    .buttonStyle(BotonHundido())
                } else if let error {
                    EstadoError(que: "la propiedad", error: error) { Task { await cargar() } }
                } else { ProgressView().padding(.top, 60) }
            }
            .padding(20)
        }
        .pantallaApilada("Tarjeta para la visita")
        .vistaPrevia($previo)
        .task { await cargar() }
    }

    private func cargar() async {
        do {
            let p: Propiedad = try await estado.api.get("/v1/propiedades/\(id)")
            d = await FichaImpresa.datos(p, api: estado.api, fotos: 1)
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }
}
