import SwiftUI

/// Una acción de swipe (84 de ancho, ícono 20 y texto 13/600 en blanco).
struct AccionFila: Identifiable {
    var id: String { texto }
    var texto: String
    var simbolo: String
    var color: Color
    var accion: () -> Void
}

/// Fila con swipe dentro de una tarjeta (3a): a la izquierda muestra `derecha` (la última es la
/// principal y se ejecuta al deslizar hasta el final); a la derecha, `izquierda`. Las mismas
/// acciones quedan como acciones de VoiceOver.
struct FilaDeslizable<Contenido: View>: View {
    var izquierda: [AccionFila] = []
    var derecha: [AccionFila] = []
    var anchoAccion: CGFloat = 84
    @ViewBuilder var contenido: () -> Contenido

    @State private var desplazamiento: CGFloat = 0
    @State private var base: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var ancho: CGFloat = 0

    var body: some View {
        ZStack {
            // Fondo: el color de la acción que se ve.
            HStack(spacing: 0) {
                if desplazamiento > 0, let a = izquierda.first {
                    a.color.overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(izquierda) { botonAccion($0).frame(width: max(anchoAccion, desplazamiento / CGFloat(izquierda.count))) }
                        }
                    }
                }
                Spacer(minLength: 0)
                if desplazamiento < 0, let a = derecha.last {
                    a.color.overlay(alignment: .trailing) {
                        HStack(spacing: 0) {
                            ForEach(Array(derecha.enumerated()), id: \.element.id) { i, acc in
                                botonAccion(acc)
                                    .frame(width: i == derecha.count - 1
                                           ? max(anchoAccion, -desplazamiento - anchoAccion * CGFloat(derecha.count - 1))
                                           : anchoAccion)
                            }
                        }
                    }
                }
            }
            contenido()
                .background(C.superficie)
                .offset(x: desplazamiento)
        }
        .clipped()
        .background(GeometryReader { g in Color.clear.onAppear { ancho = g.size.width } })
        .simultaneousGesture(arrastre)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            ForEach(izquierda + derecha) { a in
                Button(a.texto, action: a.accion)
            }
        }
    }

    private func botonAccion(_ a: AccionFila) -> some View {
        Button {
            cerrar()
            a.accion()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: a.simbolo).font(.system(size: 18, weight: .semibold))
                Text(a.texto).estilo(.footnoteFuerte)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(a.color)
        }
        .buttonStyle(.plain)
    }

    private var abiertoDerecha: CGFloat { -anchoAccion * CGFloat(derecha.count) }
    private var abiertoIzquierda: CGFloat { anchoAccion * CGFloat(izquierda.count) }

    private var arrastre: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                if horizontal == nil {
                    horizontal = abs(v.translation.width) > abs(v.translation.height) * 1.3
                }
                guard horizontal == true else { return }
                var x = base + v.translation.width
                if izquierda.isEmpty { x = min(0, x) }
                if derecha.isEmpty { x = max(0, x) }
                // Resistencia más allá del largo total.
                let tope = ancho * 0.92
                if abs(x) > tope { x = x > 0 ? tope + (x - tope) * 0.2 : -tope + (x + tope) * 0.2 }
                desplazamiento = x
            }
            .onEnded { v in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let x = base + v.translation.width
                let completo = ancho * 0.6
                if x < -completo, let principal = derecha.last {
                    Haptico.impacto()
                    withAnimation(.snappy) { desplazamiento = -ancho }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        principal.accion()
                        cerrar(animar: false)
                    }
                } else if x > completo, let principal = izquierda.first {
                    Haptico.impacto()
                    withAnimation(.snappy) { desplazamiento = ancho }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        principal.accion()
                        cerrar(animar: false)
                    }
                } else if x < abiertoDerecha / 2 {
                    withAnimation(.snappy) { desplazamiento = abiertoDerecha }
                    base = abiertoDerecha
                } else if x > abiertoIzquierda / 2, !izquierda.isEmpty {
                    withAnimation(.snappy) { desplazamiento = abiertoIzquierda }
                    base = abiertoIzquierda
                } else {
                    cerrar()
                }
            }
    }

    private func cerrar(animar: Bool = true) {
        base = 0
        if animar { withAnimation(.snappy) { desplazamiento = 0 } } else { desplazamiento = 0 }
    }
}
