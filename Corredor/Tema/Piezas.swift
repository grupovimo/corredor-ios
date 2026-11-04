import SwiftUI
import UIKit

// Las piezas del handoff, para armar cada pantalla (y lo que el handoff no dibuja) con lo mismo.

// MARK: - Tarjetas y filas

extension View {
    /// Tarjeta: fondo `surface`, sin sombra, anillo de 1 pt `card-ring`.
    func tarjeta(radio: CGFloat = 20, relleno: CGFloat? = nil) -> some View {
        self.padding(relleno ?? 0)
            .background(C.superficie, in: RoundedRectangle(cornerRadius: radio, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radio, style: .continuous).strokeBorder(C.anillo, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
    }

    /// Margen horizontal de la pantalla (20, o 16 en SE).
    func margenPantalla() -> some View { modifier(MargenPantalla()) }
}

private struct MargenPantalla: ViewModifier {
    @Environment(\.margen) private var margen
    func body(content: Content) -> some View { content.padding(.horizontal, margen) }
}

/// Separador de fila con inset donde arranca el texto.
struct Separador: View {
    var inset: CGFloat = 16
    var body: some View {
        Rectangle().fill(C.linea).frame(height: 1).padding(.leading, inset)
    }
}

/// El chevron de fila (9 × 15, `#B5A193`).
struct Chevron: View {
    var ancho: CGFloat = 9
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: ancho * 1.45, weight: .semibold))
            .foregroundStyle(C.chevron)
            .accessibilityHidden(true)
    }
}

/// Label de sección (14/600, `text-2`).
struct EtiquetaSeccion: View {
    var texto: String
    var body: some View {
        Text(texto).estilo(.label).foregroundStyle(C.texto2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Título de sección (21/700) con acción opcional a la derecha.
struct TituloSeccion: View {
    var texto: String
    var accion: String?
    var alTocar: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(texto).estilo(.tituloSeccion).foregroundStyle(C.texto).accessibilityAddTraits(.isHeader)
            Spacer()
            if let accion, let alTocar {
                Button(accion, action: alTocar).estilo(.subheadFuerte).foregroundStyle(C.primarioTexto)
            }
        }
    }
}

/// Encabezado de las pantallas raíz: Large Title 34/700 y un botón redondo de 40 a la derecha.
struct EncabezadoGrande<Derecha: View>: View {
    var titulo: String
    @ViewBuilder var derecha: () -> Derecha
    var body: some View {
        HStack(alignment: .bottom) {
            Text(titulo).estilo(.tituloGrande).foregroundStyle(C.texto)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            derecha().padding(.bottom, 2)
        }
    }
}

extension EncabezadoGrande where Derecha == EmptyView {
    init(titulo: String) {
        self.titulo = titulo
        self.derecha = { EmptyView() }
    }
}

/// Botón redondo de 40 (campana, filtro, escanear) en blanco con anillo.
struct BotonRedondo: View {
    var simbolo: String
    var etiqueta: String
    var punto = false
    var accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(C.texto)
                .frame(width: 40, height: 40)
                .background(C.superficie, in: Circle())
                .overlay(Circle().strokeBorder(C.linea, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if punto {
                        Circle().fill(C.error).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(C.superficie, lineWidth: 2).padding(-2))
                            .offset(x: -9, y: 8)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
    }
}

// MARK: - Botones

/// Botón principal: Acción (verde; oro en oscuro) con SobreAccion, 52 de alto, radio 12 continuo.
struct BotonPrincipal: ButtonStyle {
    var alto: CGFloat = 52
    @Environment(\.isEnabled) private var habilitado
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .estilo(.headline)
            .foregroundStyle(C.sobreAccion)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: alto)
            .background(C.accion, in: RoundedRectangle(cornerRadius: M.rControl, style: .continuous))
            .shadow(color: C.sombraPrimario, radius: 8, x: 0, y: 6)
            .opacity(habilitado ? (configuration.isPressed ? 0.85 : 1) : 0.5)
    }
}

/// Botón de texto (`primary-text`, 17/600).
struct BotonTexto: ButtonStyle {
    var alto: CGFloat = 52
    var color: Color = C.primarioTexto
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .estilo(.headline)
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: alto)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Botón tonal (`cream` con `primary-ink`).
struct BotonTonal: ButtonStyle {
    var alto: CGFloat = 34
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font)
            .foregroundStyle(C.primarioTinta)
            .padding(.horizontal, 14)
            .frame(minHeight: alto)
            .background(C.crema, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Botón secundario: blanco con borde `line-2` y texto `primary-text`.
struct BotonSecundario: ButtonStyle {
    var alto: CGFloat = 46
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Estilo.fila.font)
            .foregroundStyle(C.primarioTexto)
            .padding(.horizontal, 20)
            .frame(minHeight: alto)
            .background(C.superficie, in: RoundedRectangle(cornerRadius: M.rControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: M.rControl, style: .continuous).strokeBorder(C.linea2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Botón destructivo (`error-bg` con `error-ink`, 700).
struct BotonDestructivo: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
            .foregroundStyle(C.errorTinta)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(C.errorFondo, in: RoundedRectangle(cornerRadius: M.rControl, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Acción rápida en `cream-2` (Llamar, WhatsApp, Copiar mail; Ver tienda, Compartir, QR).
struct AccionRapida: View {
    var simbolo: String
    var texto: String
    var alto: CGFloat = 58
    var accion: () -> Void
    var body: some View {
        Button(action: accion) {
            VStack(spacing: 3) {
                Image(systemName: simbolo).font(.system(size: 18, weight: .regular)).foregroundStyle(C.primarioTexto)
                Text(texto).estilo(.footnoteFuerte).foregroundStyle(C.primarioTinta).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: alto)
            .background(C.crema2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips, etiquetas, insignias

/// Insignia numérica (fondo `error`).
struct Insignia: View {
    var n: Int
    var body: some View {
        Text(n > 99 ? "99+" : "\(n)")
            .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(C.error, in: Capsule())
    }
}

/// Chip de filtro (34 de alto): activo con fondo `text` y texto `bg-elevated`.
struct ChipFiltro: View {
    var texto: String
    var cuenta: Int?
    var cuentaAlerta = false
    var activo: Bool
    var accion: () -> Void
    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Text(texto)
                if let cuenta, cuenta > 0 {
                    Text("\(cuenta)").fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(activo ? C.elevado.opacity(0.75) : (cuentaAlerta ? C.errorTinta : C.texto2))
                }
            }
            .estilo(.label)
            .foregroundStyle(activo ? C.elevado : C.texto)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(activo ? C.texto : C.superficie, in: Capsule())
            .overlay(Capsule().strokeBorder(activo ? Color.clear : C.linea2, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

// MARK: - Segmentado y buscador

/// Control segmentado (36 de alto, radio 11/8).
struct Segmentado<Valor: Hashable>: View {
    var opciones: [(Valor, String)]
    @Binding var elegido: Valor
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(opciones, id: \.0) { op in
                let activo = op.0 == elegido
                Button {
                    withAnimation(.snappy(duration: 0.22)) { elegido = op.0 }
                    Haptico.seleccion()
                } label: {
                    Text(op.1)
                        .estilo(.label)
                        .foregroundStyle(activo ? C.texto : C.texto2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if activo {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(C.segmentoElegido)
                                    .shadow(color: C.verde800.opacity(0.12), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "elegido", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activo ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(C.segmentado, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Buscador (40 de alto, radio 12).
struct Buscador: View {
    var placeholder: String
    @Binding var texto: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.texto3)
            TextField("", text: $texto, prompt: Text(placeholder).foregroundStyle(C.texto3))
                .estilo(.body16)
                .foregroundStyle(C.texto)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3)
                }
                .accessibilityLabel("Borrar la búsqueda")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(C.segmentado, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Campo de formulario (52 de alto, radio 14) con label 13/600 arriba.
struct Campo<Contenido: View>: View {
    var label: String
    var error = false
    var enfocado = false
    @ViewBuilder var contenido: () -> Contenido
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).estilo(.footnoteFuerte).foregroundStyle(C.texto2)
            HStack { contenido() }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(C.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(error ? C.error : (enfocado ? C.acento : C.linea2), lineWidth: error || enfocado ? 1.5 : 1))
        }
    }
}

/// Mensaje de error de campo, con el círculo «!» de 17.
struct MensajeError: View {
    var texto: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(.white)
                .frame(width: 17, height: 17).background(C.error, in: Circle()).padding(.top, 1)
            Text(Formato.sinViudas(texto)).estilo(.texto14).foregroundStyle(C.errorTinta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Miniaturas y avatares

/// El rayado diagonal de los placeholders de fotos.
struct Rayado: View {
    var paso: CGFloat = 5
    var body: some View {
        Canvas { ctx, tam in
            ctx.fill(Path(CGRect(origin: .zero, size: tam)), with: .color(C.rayado2))
            let diag = tam.width + tam.height
            var x: CGFloat = -tam.height
            while x < diag {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + paso, y: 0))
                p.addLine(to: CGPoint(x: x + paso + tam.height, y: tam.height))
                p.addLine(to: CGPoint(x: x + tam.height, y: tam.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(C.rayado1))
                x += paso * 2 * 1.4142
            }
        }
    }
}

/// La URL de una foto de la API: https, o el id de Unsplash de la demo.
func urlDeFoto(_ f: String?, ancho: Int = 300) -> URL? {
    guard let f, !f.isEmpty else { return nil }
    if f.hasPrefix("https://") { return URL(string: f) }
    if f.range(of: "^[\\w-]+$", options: .regularExpression) != nil {
        return URL(string: "https://images.unsplash.com/photo-\(f)?auto=format&fit=crop&w=\(ancho)&q=70")
    }
    return nil
}

/// Miniatura de producto: la foto, o el rayado mientras carga o si no tiene.
struct Miniatura: View {
    var foto: String?
    var tam: CGFloat = 48
    var alto: CGFloat? = nil
    var radio: CGFloat = 12
    var body: some View {
        ZStack {
            Rayado()
            if let u = urlDeFoto(foto, ancho: Int(tam * 3)) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { fase in
                    if let img = fase.image { img.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: tam, height: alto ?? tam)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Avatar de iniciales (tienda: `cream` + `primary-text`; clienta: verde).
struct AvatarIniciales: View {
    var nombre: String
    var tam: CGFloat = 40
    var radio: CGFloat? = nil
    var fondo: Color = C.crema
    var tinta: Color = C.primarioTexto
    var body: some View {
        let t = Text(Formato.iniciales(nombre))
            .font(Estilo(tamano: tam * 0.35, peso: .bold, relativo: .body).font)
            .foregroundStyle(tinta)
            .frame(width: tam, height: tam)
        Group {
            if let radio {
                t.background(fondo, in: RoundedRectangle(cornerRadius: radio, style: .continuous))
            } else {
                t.background(fondo, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Colores del avatar de una tienda o clienta, estables por nombre (como 1d: crema, verde, neutro).
func coloresAvatar(_ nombre: String) -> (Color, Color) {
    let paleta: [(Color, Color)] = [(C.crema, C.primarioTexto), (C.okFondo, C.okTinta),
                                    (C.azulFondo, C.azulTinta), (C.violetaFondo, C.violetaTinta)]
    let h = nombre.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return paleta[h % paleta.count]
}

// MARK: - Hojas

/// Grabber de hoja (36 × 5).
struct Grabber: View {
    var body: some View {
        Capsule().fill(C.linea2).frame(width: 36, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Hoja inferior del handoff: fondo `bg-elevated`, radio 30, grabber propio.
    func hojaTLW(_ detentes: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self.presentationDetents(detentes)
            .presentationCornerRadius(30)
            .presentationBackground(C.elevado)
            .presentationDragIndicator(.hidden)
    }
}

// MARK: - Interruptor

/// Toggle de 51 × 31 en `ok`.
struct Interruptor: View {
    var texto: String
    @Binding var prendido: Bool
    var body: some View {
        Toggle(isOn: $prendido) {
            Text(texto).estilo(.body16).foregroundStyle(C.texto)
        }
        .tint(C.ok)
    }
}

// MARK: - Hápticos

enum Haptico {
    static func exito() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func impacto() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func seleccion() { UISelectionFeedbackGenerator().selectionChanged() }
}


extension View {
    /// La acción principal de una pantalla (Guardar, Publicar…) fija abajo, siempre a la vista. Va
    /// como `safeAreaInset`: el contenido se corre para arriba y al bajar del todo no queda tapado.
    func barraAccion<Botones: View>(@ViewBuilder _ botones: () -> Botones) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) { botones() }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background {
                    // Funde el contenido que pasa por debajo con el fondo.
                    LinearGradient(stops: [.init(color: C.fondo.opacity(0), location: 0), .init(color: C.fondo, location: 0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

