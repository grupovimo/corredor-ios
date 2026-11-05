import SwiftUI

/// El recorrido de la primera vez (5 pasos, poco texto): qué hay en cada pestaña. Se marca visto en la
/// API (`PATCH /v1/panel/guia {tourVisto}`), así no vuelve ni en la web ni en otro iPhone.
struct Recorrido: View {
    @Environment(Estado.self) private var estado
    @Binding var visible: Bool
    @State private var paso = 0

    private static let pasos: [(String, String, String, Pestana)] = [
        ("house", "Tu día, de un vistazo", "Lo que hay que hacer ahora, tu próxima visita y lo que encontramos por vos.", .inicio),
        ("building.2", "Tu cartera", "Cargá una propiedad en un minuto y mandala por WhatsApp deslizando la fila.", .propiedades),
        ("viewfinder", "MIRA", "Fotografiá un cartel de «Vende» y lo cargamos por vos.", .mira),
        ("bubble.left.and.bubble.right", "Todas las consultas juntas", "WhatsApp, Mercado Libre y tu web en una sola bandeja.", .mensajes),
        ("square.grid.2x2", "Todo lo demás, en «Más»", "Agenda, contactos, cobranzas, contratos, consorcios, tu web y la configuración, ordenados por área.", .mas),
    ]

    var body: some View {
        let p = Self.pasos[paso]
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { siguiente() }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconoTono(icono: p.0, tono: p.3 == .mira ? .oro : .verde, tam: 44)
                    Spacer()
                    Text("\(paso + 1) de \(Self.pasos.count)").estilo(.footnote).foregroundStyle(C.texto3)
                }
                Text(p.1).estilo(.titulo3).foregroundStyle(C.texto)
                Text(Formato.sinViudas(p.2)).estilo(.subhead).foregroundStyle(C.texto2)
                HStack {
                    Button("Saltear") { terminar() }.buttonStyle(BotonTexto(color: C.texto2)).frame(width: 110)
                    Button(paso == Self.pasos.count - 1 ? "Empezar" : "Siguiente") { siguiente() }.buttonStyle(BotonAccion())
                }
            }
            .padding(18)
            .background(C.superficie, in: .rect(cornerRadius: 24, style: .continuous))
            .sombraE3()
            .padding(.horizontal, 16).padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(paso)
        }
        .animation(.spring(duration: 0.3), value: paso)
        .onAppear { if p.3 != .mira { estado.pestana = p.3 } }
    }

    private func siguiente() {
        Haptico.seleccion()
        if paso + 1 >= Self.pasos.count { return terminar() }
        paso += 1
        let x = Self.pasos[paso].3
        if x != .mira { estado.pestana = x }
    }

    private func terminar() {
        visible = false
        estado.pestana = .inicio
        Task {
            struct C: Encodable { var tourVisto = true }
            try? await estado.api.hacer("PATCH", "/v1/panel/guia", C())
        }
    }
}
