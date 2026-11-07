import SwiftUI

// Los estados de cada pantalla (handoff: «Interactions & Behavior · Estados»): cargando con
// esqueletos de forma real (2c), vacío con la primera acción (E1), error con reintento (E3) y
// «Reintentar» (12f), sin conexión con el banner y la hora de lo guardado (5a).

/// Lo que puede pasar al traer algo de la API.
enum Carga<T> {
    case cargando
    case listo(T)
    case error(ErrorApi)

    var valor: T? {
        if case let .listo(v) = self { return v }
        return nil
    }
}

/// Un estado vacío o de error del handoff (E1–E3): ícono en un círculo hundido, título, texto y una
/// o dos acciones.
struct EstadoVacio: View {
    var icono: String
    var titulo: String
    var texto: String? = nil
    var accion: (String, () -> Void)? = nil
    var secundaria: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(C.accion)
                .frame(width: 72, height: 72)
                .background(C.hundida, in: Circle())
                .accessibilityHidden(true)
            Text(titulo).estilo(.titulo3).foregroundStyle(C.texto).multilineTextAlignment(.center)
            if let texto {
                Text(Formato.sinViudas(texto)).estilo(.subhead).foregroundStyle(C.texto2).multilineTextAlignment(.center)
            }
            if let accion {
                Button(accion.0, action: accion.1).buttonStyle(BotonPrincipal()).padding(.top, 4)
            }
            if let secundaria {
                Button(secundaria.0, action: secundaria.1).buttonStyle(BotonTexto())
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

/// El error de traer una lista (12f): «No pudimos traer los pedidos».
struct EstadoError: View {
    var que: String
    var error: ErrorApi
    var reintentar: () -> Void
    var body: some View {
        if error.sinConexion {
            EstadoVacio(icono: "wifi.slash", titulo: "Sin conexión",
                        texto: "Lo que cargues queda en cola y se sube solo cuando vuelva la señal.",
                        accion: ("Reintentar", reintentar))
        } else {
            EstadoVacio(icono: "exclamationmark.triangle", titulo: "No pudimos traer \(que)",
                        texto: "Probá de nuevo en un ratito.",
                        accion: ("Reintentar", reintentar))
        }
    }
}

/// Banner `warn-bg` de sin conexión (5a).
struct BannerSinConexion: View {
    var guardado: Date
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 14, weight: .semibold))
            Text("Sin conexión. Ves lo guardado \(Formato.cuando(guardado)).")
                .estilo(.texto14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(C.bannerTinta)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(C.avisoFondo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Bloque de esqueleto con el brillo horizontal de 1,2 s (respeta Reducir movimiento).
struct Esqueleto: View {
    var ancho: CGFloat? = nil
    var alto: CGFloat
    var radio: CGFloat? = nil
    var suave = false
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var fase: CGFloat = -1

    var body: some View {
        let base = suave ? C.esqueleto2 : C.esqueleto1
        RoundedRectangle(cornerRadius: radio ?? alto / 2, style: .continuous)
            .fill(base)
            .overlay {
                if !reducir {
                    GeometryReader { g in
                        LinearGradient(colors: [base, C.elevado.opacity(0.9), base], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width)
                            .offset(x: fase * g.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radio ?? alto / 2, style: .continuous))
                }
            }
            .frame(width: ancho, height: alto)
            .onAppear {
                guard !reducir else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { fase = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// Filas de lista mientras cargan.
struct EsqueletoFilas: View {
    var filas = 4
    var miniatura: CGFloat = 48
    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<filas, id: \.self) { i in
                HStack(spacing: 13) {
                    Esqueleto(ancho: miniatura, alto: miniatura, radio: 12)
                    VStack(alignment: .leading, spacing: 7) {
                        GeometryReader { g in
                            VStack(alignment: .leading, spacing: 7) {
                                Esqueleto(ancho: g.size.width * (i.isMultiple(of: 2) ? 0.7 : 0.8), alto: 13)
                                Esqueleto(ancho: g.size.width * (i.isMultiple(of: 2) ? 0.45 : 0.35), alto: 11, suave: true)
                            }
                        }
                        .frame(height: 31)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .tarjeta()
        .accessibilityLabel("Cargando")
    }
}

// MARK: - Toast


struct VistaAviso: View {
    var aviso: Aviso
    var cerrar: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: aviso.ok ? "checkmark" : "exclamationmark")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(aviso.ok ? Color(hex: 0x1E5749) : C.error, in: Circle())
            Text(aviso.texto).estilo(.subhead).foregroundStyle(Color(hex: 0xE8EFE9))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Con las dos (p. ej. «Cobro registrado» con «Mandar recibo»), la acción y al lado «Deshacer».
            if let a = aviso.accion {
                Button(a.0) {
                    a.1()
                    cerrar()
                }
                .font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                .foregroundStyle(C.oro)
            }
            if let d = aviso.deshacer {
                Button("Deshacer") {
                    d()
                    cerrar()
                }
                .font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                .foregroundStyle(C.oro)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Color.tema(0x0F3530, 0x2E3336), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: C.verde800.opacity(0.4), radius: 12, y: 10)
        .accessibilityElement(children: .contain)
    }
}

/// Andamio mientras se arma un área: sólo para desarrollo, nunca llega a TestFlight así.
struct Pendiente: View {
    var titulo: String
    var body: some View {
        EstadoVacio(icono: "hammer", titulo: titulo)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(C.fondo)
    }
}
