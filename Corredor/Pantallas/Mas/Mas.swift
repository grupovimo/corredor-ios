import SwiftUI

/// La pestaña «Más»: todo lo que no entra en las otras cuatro, por áreas, con la persona arriba y un
/// buscador que filtra. Las filas son las del handoff (tarjeta con filas, ícono en `accion`, chevron).
struct MasRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var filtro = ""

    struct Item: Identifiable {
        var icono: String
        var texto: String
        var destino: AnyHashable
        var insignia = 0
        var id: String { texto }
    }

    private var grupos: [(String, [Item])] {
        var g: [(String, [Item])] = [
            ("Día a día", [Item(icono: "calendar", texto: "Agenda", destino: AAgendaDia()),
                           Item(icono: "bell", texto: "Avisos", destino: AAvisos(), insignia: estado.avisosPendientes),
                           Item(icono: "magnifyingglass", texto: "Buscar en todo", destino: ABuscar())]),
            ("Cartera", [Item(icono: "person.2", texto: "Contactos", destino: AContactos()),
                         Item(icono: "rectangle.split.3x1", texto: "Operaciones", destino: AOperaciones()),
                         Item(icono: "hand.raised", texto: "Reservas", destino: ASeccion(clave: "reservas")),
                         Item(icono: "building", texto: "Emprendimientos", destino: ASeccion(clave: "emprendimientos")),
                         Item(icono: "beach.umbrella", texto: "Temporada", destino: ASeccion(clave: "temporada"))]),
            ("Alquileres", [Item(icono: "dollarsign.circle", texto: "Cobranzas", destino: ACobranzas()),
                            Item(icono: "doc.text", texto: "Contratos", destino: AContratos()),
                            Item(icono: "doc.plaintext", texto: "Rendiciones", destino: ASeccion(clave: "rendiciones")),
                            Item(icono: "checklist", texto: "Actas de entrega", destino: ASeccion(clave: "inventarios")),
                            Item(icono: "chart.line.uptrend.xyaxis", texto: "Índices", destino: ASeccion(clave: "indices")),
                            Item(icono: "building.columns", texto: "Consorcios", destino: ASeccion(clave: "consorcios"))]),
            ("Difusión", [Item(icono: "globe", texto: "Mi web", destino: ASeccion(clave: "web")),
                          Item(icono: "megaphone", texto: "Portales", destino: ASeccion(clave: "difusion")),
                          Item(icono: "quote.bubble", texto: "Respuestas guardadas", destino: ASeccion(clave: "respuestas")),
                          Item(icono: "square.and.arrow.down", texto: "Importar la cartera", destino: ASeccion(clave: "importar"))]),
            ("Equipo", [Item(icono: "flag", texto: "Objetivos", destino: ASeccion(clave: "objetivos")),
                        Item(icono: "chart.bar", texto: "Informe", destino: ASeccion(clave: "informe")),
                        Item(icono: "checkmark.shield", texto: "Revisión de la IA", destino: ASeccion(clave: "revision")),
                        Item(icono: "clock.arrow.circlepath", texto: "Actividad", destino: ASeccion(clave: "actividad"))]),
        ]
        var ajustes = [Item(icono: "storefront", texto: "Inmobiliaria", destino: ASeccion(clave: "configuracion")),
                       Item(icono: "person.3", texto: "Equipo y permisos", destino: ASeccion(clave: "equipo")),
                       Item(icono: "puzzlepiece.extension", texto: "Integraciones", destino: ASeccion(clave: "integraciones")),
                       Item(icono: "wrench.and.screwdriver", texto: "Proveedores", destino: ASeccion(clave: "proveedores")),
                       Item(icono: "sparkles", texto: "Corredor en tu IA", destino: ASeccion(clave: "ia")),
                       Item(icono: "trash", texto: "Papelera", destino: ASeccion(clave: "papelera"))]
        if !estado.esDuenio { ajustes.removeAll { ["Integraciones", "Corredor en tu IA"].contains($0.texto) } }
        g.append(("Configuración", ajustes))
        let f = filtro.trimmingCharacters(in: .whitespaces).folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !f.isEmpty else { return g }
        return g.compactMap { t, items in
            let x = items.filter { $0.texto.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(f) }
            return x.isEmpty ? nil : (t, x)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CabeceraPestana(titulo: "Más")
                    .padding(.horizontal, -16)
                persona
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(C.texto3)
                    TextField("Buscar una sección", text: $filtro).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !filtro.isEmpty {
                        Button { filtro = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }.accessibilityLabel("Borrar lo escrito")
                    }
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(C.hundida, in: .rect(cornerRadius: 12))
                let gs = grupos
                if gs.isEmpty {
                    EstadoVacio(icono: "magnifyingglass", titulo: "No hay una sección «\(filtro)»", texto: "Probá con otra palabra, o buscá clientes y propiedades.",
                                accion: ("Buscar «\(filtro)» en todo", { estado.abrir(ABuscar(texto: filtro)) }))
                }
                ForEach(gs, id: \.0) { titulo, items in
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: titulo)
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                                Button { estado.abrir(it.destino) } label: { fila(it) }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 54) } }
                            }
                        }
                        .tarjeta()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .pantallaRaiz()
    }

    /// La persona y su inmobiliaria: abre el perfil (cuenta, firma, Face ID, cambiar de inmobiliaria, salir).
    private var persona: some View {
        Button { estado.abrir(APerfil()) } label: {
            HStack(spacing: 12) {
                Text(Formato.iniciales(estado.usuario?.completo ?? "C"))
                    .font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font)
                    .foregroundStyle(C.oro)
                    .frame(width: 48, height: 48)
                    .background(C.verde700, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(estado.usuario?.completo ?? "Tu cuenta").estilo(.filaLista).foregroundStyle(C.texto)
                    Text([estado.inmobiliaria?.nombre, estado.esDuenio ? "Dueño" : estado.rol == "lector" ? "Sólo mira" : "Agente"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.texto3)
            }
            .padding(14)
            .contentShape(Rectangle())
            .tarjeta()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tu perfil")
    }

    private func fila(_ it: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: it.icono).font(.system(size: 18, weight: .medium)).foregroundStyle(C.accion).frame(width: 28)
            Text(it.texto).estilo(.filaLista).foregroundStyle(C.texto)
            Spacer(minLength: 0)
            if it.insignia > 0 { InsigniaRoja(n: it.insignia) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.texto3)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
