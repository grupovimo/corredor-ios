import PhotosUI
import SwiftUI
import UIKit
import WebKit

// Las piezas para editar la marca y la web desde el celular: el borrador (lo mismo que edita el panel
// web, sin publicar hasta «Publicar»), la vista previa de la web real con el borrador, y la subida del
// logo y la portada. Las usan el alta (Pantallas/Entrada/Alta.swift) y Mi web.

/// El borrador de la web en la API: leer, guardar (con el `en` que se leyó: si otro lo guardó en el
/// medio, 409) y publicar o descartar.
@MainActor
enum BorradorWeb {
    static func leer(_ api: Api) async throws -> Borrador { try await api.get("/v1/web/borrador") }

    /// Guarda la marca entera. Devuelve el borrador nuevo; con 409 (`borrador_cambiado`), el error.
    static func guardar(_ api: Api, marca: [String: JSONLibre], si: String?) async throws -> Borrador {
        struct Cuerpo: Encodable { var marca: [String: JSONLibre]; var si: String? }
        return try await api.enviar("PUT", "/v1/web/borrador", Cuerpo(marca: marca, si: si))
    }

    static func publicar(_ api: Api) async throws { try await api.hacer("POST", "/v1/web/publicar") }
    static func descartar(_ api: Api) async throws { try await api.hacer("DELETE", "/v1/web/borrador") }

    /// La dirección de la vista previa: siempre el subdominio (con dominio propio la cookie sería de
    /// terceros), con un token de 15 minutos.
    static func urlPrevia(_ api: Api, slug: String) async throws -> URL {
        struct T: Decodable { var token: String }
        let t: T = try await api.enviar("POST", "/v1/web/previa", [String: String]())
        let host = Api.web().host ?? "corredor.com.ar"
        return URL(string: "https://\(slug).\(host)/?previa=\(t.token)")!
    }
}

extension Dictionary where Key == String, Value == JSONLibre {
    /// Un texto de la marca ("" si no está).
    func texto(_ k: String) -> String { self[k]?.texto ?? "" }
    /// Pone un texto (vacío lo saca).
    mutating func poner(_ k: String, _ v: String) {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        self[k] = t.isEmpty ? nil : .texto(t)
    }
}

/// La web de la inmobiliaria con el borrador, dentro de la app. Tocar una zona marcada (logo, portada,
/// frase, una sección, el contacto) avisa cuál (`alEditar`) en vez de navegar. `recarga` cambia cada
/// vez que se guarda el borrador, para volver a pedirla.
struct WebPrevia: UIViewRepresentable {
    var url: URL?
    var recarga: Int
    var alEditar: (String) -> Void

    func makeCoordinator() -> Coordinador { Coordinador(alEditar: alEditar) }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.userContentController.add(context.coordinator, name: "corredor")
        conf.websiteDataStore = .nonPersistent()
        let w = WKWebView(frame: .zero, configuration: conf)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.accessibilityLabel = "Vista previa de tu web"
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        context.coordinator.alEditar = alEditar
        guard let url else { return }
        let clave = "\(url.absoluteString)#\(recarga)"
        if context.coordinator.cargada != clave {
            // El token va sólo la primera vez (queda en la cookie); después alcanza con recargar.
            if context.coordinator.cargada?.hasPrefix(url.absoluteString) == true, w.url != nil { w.reload() } else { w.load(URLRequest(url: url)) }
            context.coordinator.cargada = clave
        }
    }

    final class Coordinador: NSObject, WKScriptMessageHandler {
        var alEditar: (String) -> Void
        var cargada: String?
        init(alEditar: @escaping (String) -> Void) { self.alEditar = alEditar }

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let d = m.body as? [String: Any], let zona = d["editar"] as? String else { return }
            Haptico.seleccion()
            alEditar(zona)
        }
    }
}

/// La vista previa dentro de un marco de teléfono, con la etiqueta «Tocá lo que quieras cambiar».
struct MarcoPrevia: View {
    var url: URL?
    var recarga: Int
    var alto: CGFloat = 520
    var alEditar: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if url == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                WebPrevia(url: url, recarga: recarga, alEditar: alEditar)
            }
            .frame(height: alto)
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(C.texto.opacity(0.85), lineWidth: 6))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
            Label("Tocá lo que quieras cambiar", systemImage: "hand.tap").estilo(.footnote).foregroundStyle(C.texto2)
        }
    }
}

/// Elegir y subir una imagen de la marca (logo o portada): galería o cámara, recortada y comprimida.
/// Devuelve la URL pública y, para el logo, sus colores (para sugerirlos).
struct SubirImagenMarca: View {
    @Environment(Estado.self) private var estado
    var titulo: String
    var url: String?
    var ancha = false
    var alSubir: (String, [UInt32]) -> Void
    @State private var item: PhotosPickerItem?
    @State private var subiendo = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            VStack(spacing: 8) {
                if let u = url.flatMap(URL.init(string:)) {
                    AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxWidth: ancha ? .infinity : 150, maxHeight: ancha ? 170 : 110)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: ancha ? "photo.on.rectangle.angled" : "photo.badge.plus").font(.system(size: 38, weight: .light))
                        .foregroundStyle(C.accion)
                }
                Text(subiendo ? "Subiendo…" : (url == nil ? titulo : "Cambiar")).estilo(.filaLista).foregroundStyle(C.texto)
                Text(ancha ? "Una foto horizontal y luminosa" : "JPG o PNG, con fondo transparente si tenés").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .frame(maxWidth: .infinity, minHeight: ancha ? 220 : 200)
            .padding(16)
            .background(C.superficie, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: M.rTarjeta, style: .continuous).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .disabled(subiendo)
        .onChange(of: item) { _, i in
            guard let i else { return }
            Task {
                subiendo = true
                defer { subiendo = false; item = nil }
                guard let d = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: d) else {
                    return estado.avisar("No pudimos leer la imagen.", ok: false)
                }
                // El logo va en PNG (puede tener transparencia); la portada, en JPG achicada.
                let (datos, nombre, tipo) = ancha
                    ? (img.achicada(2000).jpegData(compressionQuality: 0.85) ?? d, "portada.jpg", "image/jpeg")
                    : (img.achicada(1000).pngData() ?? d, "logo.png", "image/png")
                do {
                    let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "marca")
                    guard let u = a.url else { return }
                    alSubir(u, ancha ? [] : img.coloresMarca())
                } catch { estado.avisar(error) }
            }
        }
    }
}

extension UIImage {
    /// La imagen con su lado más largo en `lado` puntos como mucho.
    func achicada(_ lado: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > lado else { return self }
        let s = CGSize(width: size.width * lado / m, height: size.height * lado / m)
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return UIGraphicsImageRenderer(size: s, format: f).image { _ in draw(in: CGRect(origin: .zero, size: s)) }
    }

    /// Los colores de un logo, para sugerirlos (la misma cuenta que el panel: web/src/lib/web/colores.ts):
    /// se agrupan los píxeles parecidos, sin casi blancos, casi negros ni grises, y se descartan los
    /// parecidos a uno ya elegido. El más usado primero.
    func coloresMarca(cuantos: Int = 4) -> [UInt32] {
        let lado = 48
        var px = [UInt8](repeating: 0, count: lado * lado * 4)
        guard let cg = cgImage else { return [] }
        let dibujada = px.withUnsafeMutableBytes { b -> Bool in
            guard let ctx = CGContext(data: b.baseAddress, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: lado, height: lado))
            return true
        }
        guard dibujada else { return [] }
        var grupos: [Int: (n: Double, r: Double, v: Double, a: Double)] = [:]
        for i in stride(from: 0, to: px.count, by: 4) {
            let alfa = Double(px[i + 3])
            guard alfa >= 128 else { continue }
            // Sin premultiplicar (el contexto lo guarda multiplicado por la transparencia).
            let r = Double(px[i]) * 255 / alfa, v = Double(px[i + 1]) * 255 / alfa, a = Double(px[i + 2]) * 255 / alfa
            let mx = max(r, v, a), mn = min(r, v, a)
            if (mx > 240 && mn > 225) || mx < 22 || mx - mn < 24 { continue }
            let k = (Int(r) >> 5) << 6 | (Int(v) >> 5) << 3 | (Int(a) >> 5)
            let x = grupos[k] ?? (0, 0, 0, 0)
            grupos[k] = (x.n + 1, x.r + r, x.v + v, x.a + a)
        }
        var elegidos: [Acento.Rgb] = []
        for x in grupos.values.sorted(by: { $0.n > $1.n }) {
            let c: Acento.Rgb = (x.r / x.n, x.v / x.n, x.a / x.n)
            if elegidos.contains(where: { sqrt(pow($0.0 - c.0, 2) + pow($0.1 - c.1, 2) + pow($0.2 - c.2, 2)) < 70 }) { continue }
            elegidos.append(c)
            if elegidos.count == cuantos { break }
        }
        return elegidos.map(Acento.hex)
    }
}

extension UInt32 {
    /// «#1e3a5f».
    var hexColor: String { String(format: "#%06x", self) }
}

/// Elegir un color de la marca: los sugeridos (los del logo primero) y el selector del sistema.
struct ElegirColor: View {
    var titulo: String
    var sugeridos: [UInt32]
    @Binding var hex: String

    /// Sin repetidos (el del logo puede coincidir con uno de los de siempre).
    private var unicos: [UInt32] {
        var vistos = Set<UInt32>()
        return sugeridos.filter { vistos.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).estilo(.filaLista).foregroundStyle(C.texto)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(unicos, id: \.self) { c in
                        let elegido = hex.lowercased() == c.hexColor
                        Button { hex = c.hexColor; Haptico.seleccion() } label: {
                            Circle().fill(Color(hex: c)).frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(.black.opacity(0.1)))
                                .padding(3)
                                .overlay(Circle().strokeBorder(elegido ? C.texto : .clear, lineWidth: 2.5))
                        }
                        .accessibilityLabel("Usar el color \(c.hexColor)")
                        .accessibilityAddTraits(elegido ? .isSelected : [])
                    }
                    ColorPicker("Otro color", selection: Binding(get: {
                        Acento.rgb(hex).map { Color(hex: Acento.hex($0)) } ?? C.verde700
                    }, set: { c in
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
                        hex = Acento.hex((Double(r) * 255, Double(g) * 255, Double(b) * 255)).hexColor
                    }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 50, height: 50)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Lo que se abre al tocar una parte de la web en la vista previa: el logo, la portada, la frase, el
/// contacto o «nosotros». Cambia la marca de Mi web; `alListo` la guarda en el borrador.
struct EditorZonaWeb: View {
    @Environment(\.dismiss) private var cerrar
    var zona: String
    @Binding var marca: [String: String]
    var alListo: () -> Void

    private var titulo: String {
        ["logo": "Tu logo", "portada": "La portada", "frase": "La frase de la portada", "contacto": "Contacto", "nosotros": "Nosotros"][zona] ?? "Tu web"
    }

    private func campo(_ k: String) -> Binding<String> { Binding(get: { marca[k] ?? "" }, set: { marca[k] = $0 }) }

    var body: some View {
        NavigationStack {
            Form {
                switch zona {
                case "logo":
                    SubirImagenMarca(titulo: "Subí tu logo", url: marca["logoUrl"]) { u, _ in marca["logoUrl"] = u; alListo(); cerrar() }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                case "portada":
                    SubirImagenMarca(titulo: "Subí la foto de portada", url: marca["portadaUrl"], ancha: true) { u, _ in marca["portadaUrl"] = u; alListo(); cerrar() }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    Section("Frase") { TextField("Tu próximo hogar en Palermo", text: campo("frase"), axis: .vertical).lineLimit(2...3) }
                case "frase":
                    TextField("Tu próximo hogar en Palermo", text: campo("frase"), axis: .vertical).lineLimit(2...4)
                case "contacto":
                    TextField("WhatsApp", text: campo("whatsapp")).keyboardType(.phonePad)
                    TextField("Teléfono", text: campo("telefono")).keyboardType(.phonePad)
                    TextField("Mail", text: campo("email")).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Dirección", text: campo("direccion"))
                    TextField("Horario", text: campo("horario"))
                case "nosotros":
                    TextField("Título", text: campo("nosotrosTitulo"))
                    TextField("Quiénes son, desde cuándo, en qué barrios trabajan.", text: campo("nosotros"), axis: .vertical).lineLimit(3...10)
                default:
                    Text("Esta parte se cambia en Mi web, más abajo.").foregroundStyle(C.texto2)
                }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle(titulo).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { alListo(); cerrar() } }
            }
        }
    }
}
