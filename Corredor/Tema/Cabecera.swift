import SwiftUI

/// Una acción de ícono de la cabecera (buscar, avisos, nueva propiedad…), con insignia opcional.
struct AccionCabecera: Identifiable {
    var id: String { etiqueta }
    var icono: String
    var etiqueta: String
    var insignia: Int? = nil
    var hacer: () -> Void
}

/// La cabecera grande de una pestaña (handoff · `h.grande`): fila de 44 con las acciones y el avatar
/// con aro oro, el «sobre» en versalitas 13/600, el título 34/800 y, si hay, la caja de búsqueda.
struct CabeceraPestana: View {
    @Environment(Estado.self) private var estado
    var sobre: String? = nil
    var titulo: String
    var acciones: [AccionCabecera] = []
    var avatar = false
    var busca: String? = nil
    var alBuscar: (() -> Void)? = nil
    /// El logo de la inmobiliaria (su marca de Mi web), a la izquierda del renglón de arriba.
    var logo: URL? = nil

    /// Los botones (y el avatar), a la derecha.
    private var botones: some View {
        HStack(spacing: 0) {
            ForEach(acciones) { a in
                Button(action: a.hacer) {
                    Image(systemName: a.icono).font(.system(size: 21, weight: .medium))
                        .foregroundStyle(C.accion)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if let n = a.insignia, n > 0 { InsigniaRoja(n: n).offset(x: -3, y: 3) }
                        }
                }
                .accessibilityLabel(a.etiqueta)
            }
            if avatar {
                Button { estado.abrir(APerfil()) } label: {
                    Text(Formato.iniciales(estado.usuario?.completo ?? "C"))
                        .font(Estilo(tamano: 13, peso: .bold, relativo: .caption).font)
                        .foregroundStyle(C.oro)
                        .frame(width: 34, height: 34)
                        .background(C.verde700, in: Circle())
                        .padding(2).background(C.fondo, in: Circle())
                        .padding(1.5).background(C.oro, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tu perfil")
            }
        }
        .padding(.trailing, -8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Con renglón de arriba (fecha, inmobiliaria), los botones van ahí; sin él, en el renglón del
            // título (antes quedaban solos en una fila vacía, lejos de todo).
            if sobre != nil {
                HStack(spacing: 0) { Spacer(); botones }.frame(height: 44)
            } else {
                Color.clear.frame(height: 12)
            }
            if let sobre {
                HStack(spacing: 10) {
                    if let logo {
                        AsyncImage(url: logo) { $0.resizable().scaledToFit() } placeholder: { C.hundida }
                            .frame(width: 34, height: 34)
                            .background(C.superficie)
                            .clipShape(.rect(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(C.linea))
                            .accessibilityHidden(true)
                    }
                    Text(sobre.uppercased()).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                        .tracking(13 * 0.04).foregroundStyle(C.texto2).lineLimit(1)
                }
                .padding(.bottom, logo == nil ? 0 : 4)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(titulo).estilo(.tituloGrande).foregroundStyle(C.texto)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if sobre == nil {
                    Spacer(minLength: 0)
                    botones
                }
            }
            if let busca {
                Button { alBuscar?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 17))
                        Text(busca).estilo(.body).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "mic").font(.system(size: 17))
                    }
                    .foregroundStyle(C.texto3)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(C.hundida, in: .rect(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

/// La insignia roja de las cabeceras y la barra (#e5484d, 18 de alto).
struct InsigniaRoja: View {
    var n: Int
    var body: some View {
        Text(n > 99 ? "99+" : "\(n)")
            .font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color(hex: 0xE5484D), in: Capsule())
    }
}

/// El título de un bloque («Para hacer ahora», con la cuenta a la derecha): 20/700 y 15 en tinta 2.
struct TituloBloque: View {
    var texto: String
    var cuenta: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(texto).estilo(.titulo3).foregroundStyle(C.texto)
            Spacer()
            if let cuenta { Text(cuenta).estilo(.subhead).foregroundStyle(C.texto2) }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Los tonos del handoff (g, o, b, v, r y neutro): fondo y tinta.
enum Tono {
    case verde, oro, azul, violeta, rojo, neutro

    var fondo: Color {
        switch self {
        case .verde: return C.okFondo
        case .oro: return C.avisoFondo
        case .azul: return C.azulFondo
        case .violeta: return C.violetaFondo
        case .rojo: return C.errorFondo
        case .neutro: return C.hundida
        }
    }

    var tinta: Color {
        switch self {
        case .verde: return C.okTinta
        case .oro: return C.avisoTinta
        case .azul: return C.azulTinta
        case .violeta: return C.violetaTinta
        case .rojo: return C.errorTinta
        case .neutro: return C.texto2
        }
    }
}

/// El ícono de una fila: 40×40, radio 12, en el tono.
struct IconoTono: View {
    var icono: String
    var tono: Tono
    var tam: CGFloat = 40
    var body: some View {
        Image(systemName: icono).font(.system(size: tam * 0.5, weight: .medium))
            .foregroundStyle(tono.tinta)
            .frame(width: tam, height: tam)
            .background(tono.fondo, in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Cuántas pantallas se mostraron: las pruebas lo usan para verificar que cada destino navegable abre su
/// pantalla y no el placeholder de SwiftUI (el triángulo amarillo de un destino que no se encuentra).
@MainActor
enum PantallasMostradas {
    static var cuenta = 0
}

/// El fondo de la app: `Fondo` con el grano en mosaico (multiplicado en claro, al 55 % en oscuro).
struct FondoApp: View {
    @Environment(\.colorScheme) private var esquema
    var body: some View {
        ZStack {
            C.fondo
            if esquema == .dark {
                Image("GranoClaro").resizable(resizingMode: .tile).opacity(0.55)
            } else {
                Image("Grano").resizable(resizingMode: .tile).blendMode(.multiply)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { PantallasMostradas.cuenta += 1 }
    }
}

extension View {
    /// Una pantalla raíz de pestaña: fondo con grano y sin barra de navegación (la cabecera es propia).
    func pantallaRaiz() -> some View {
        background(FondoApp())
            .toolbar(.hidden, for: .navigationBar)
            // La franja de la hora: lo que sube al hacer scroll pasa por detrás, desenfocado (sin esto el
            // contenido se montaba sobre la hora y la batería).
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                    .background(C.fondo.opacity(0.7), ignoresSafeAreaEdges: .top)
            }
    }

    /// Una pantalla apilada: fondo con grano y título chico en la barra nativa.
    func pantallaApilada(_ titulo: String) -> some View {
        background(FondoApp()).navigationTitle(titulo).navigationBarTitleDisplayMode(.inline)
    }
}

extension Formato {
    /// «ARS 540.000», «USD 172.000» (sin decimales si es entero).
    static func plata(_ n: Double, _ moneda: String = "ARS") -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = n.rounded() == n ? 0 : 2
        f.minimumFractionDigits = 0
        return "\(moneda) \(f.string(from: NSNumber(value: n)) ?? "\(n)")"
    }

    /// «ARS 1,84 M» para las cifras de la dueña.
    static func plataCorta(_ n: Double, _ moneda: String = "ARS") -> String {
        if abs(n) >= 1_000_000 {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "es_AR")
            f.maximumFractionDigits = 2
            return "\(moneda) \(f.string(from: NSNumber(value: n / 1_000_000)) ?? "") M"
        }
        return plata(n, moneda)
    }

    /// «jueves 12 de noviembre».
    static func diaCompleto(_ f: Date) -> String {
        let d = DateFormatter()
        d.locale = Locale(identifier: "es_AR")
        d.dateFormat = "EEEE d 'de' MMMM"
        return d.string(from: f)
    }

    /// «yyyy-MM-dd» en la hora del iPhone (lo que piden los filtros de la API).
    static func diaISO(_ f: Date) -> String {
        let d = DateFormatter()
        d.calendar = Calendar(identifier: .gregorian)
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "yyyy-MM-dd"
        return d.string(from: f)
    }
}

/// Abre WhatsApp con un número y un texto (o el teléfono, o Mapas).
enum Afuera {
    static func whatsapp(_ telefono: String?, texto: String = "") {
        let n = (telefono ?? "").filter(\.isNumber)
        var c = URLComponents(string: "https://wa.me/\(n)")!
        if !texto.isEmpty { c.queryItems = [URLQueryItem(name: "text", value: texto)] }
        if let u = c.url { UIApplication.shared.open(u) }
    }

    static func llamar(_ telefono: String?) {
        let n = (telefono ?? "").filter { $0.isNumber || $0 == "+" }
        if let u = URL(string: "tel://\(n)") { UIApplication.shared.open(u) }
    }

    static func mapas(_ direccion: String) {
        var c = URLComponents(string: "http://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: direccion)]
        if let u = c.url { UIApplication.shared.open(u) }
    }
}

extension Fecha {
    /// «2026-11-12» → la fecha a las 12 del mediodía (sin corrimientos de huso).
    static func dia(_ s: String) -> Date? {
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

/// Un campo con su etiqueta arriba (13/600 en tinta 2).
struct Etiquetado<Contenido: View>: View {
    var etiqueta: String
    @ViewBuilder var contenido: () -> Contenido
    init(_ etiqueta: String, @ViewBuilder contenido: @escaping () -> Contenido) {
        self.etiqueta = etiqueta
        self.contenido = contenido
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(etiqueta).estilo(.footnoteFuerte).foregroundStyle(C.texto2)
            contenido()
        }
    }
}
