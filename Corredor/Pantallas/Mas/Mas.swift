import SwiftUI

/// La pestaña «Más»: todo lo que no entra en las otras cuatro, por áreas, con la persona arriba y un
/// buscador que filtra. Las filas son las del handoff (tarjeta con filas, ícono en `accion`, chevron).
struct MasRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var filtro = ""
    /// Lo que pasa en cada sección, a la derecha de su fila («3 deben», «WhatsApp sin conectar»).
    @State private var estados: [String: (String, Tono)] = [:]
    @State private var potenciar: [Potencia] = []

    /// Algo que el negocio todavía no usa, con su beneficio en una línea.
    struct Potencia: Identifiable {
        var icono: String
        var titulo: String
        var texto: String
        var destino: AnyHashable
        var id: String { titulo }
    }

    struct Item: Identifiable {
        var icono: String
        var texto: String
        var destino: AnyHashable
        var insignia = 0
        var id: String { texto }
    }

    private var grupos: [(String, [Item])] {
        let g = Self.grupos(duenio: estado.esDuenio, avisos: estado.avisosPendientes)
        let f = Self.normal(filtro)
        guard !f.isEmpty else { return g }
        return g.compactMap { t, items in
            let x = items.filter { Self.coincide($0, f) }
            return x.isEmpty ? nil : (t, x)
        }
    }

    /// «Cobrar» encuentra Cobranzas, «expensas» Consorcios, «excel» Importar: el nombre y sus palabras.
    static let claves: [String: [String]] = [
        "Cobranzas": ["cobrar", "cobro", "recibo", "deuda", "debe", "pago", "alquiler", "plata"],
        "Contratos": ["contrato", "inquilino", "ajuste", "icl", "ipc", "renovar", "alquiler"],
        "Rendiciones": ["rendir", "rendicion", "dueño", "propietario", "liquidacion"],
        "Consorcios": ["expensas", "edificio", "unidad", "administracion", "f931"],
        "Mi web": ["web", "dominio", "logo", "colores", "pagina", "sitio"],
        "Portales": ["portal", "zonaprop", "argenprop", "mercado libre", "publicar", "difusion"],
        "Integraciones": ["whatsapp", "mercado libre", "conectar", "meta"],
        "Corredor en tu IA": ["ia", "chatgpt", "claude", "inteligencia artificial"],
        "Revisión de la IA": ["ia", "sugerencias", "aprobar"],
        "Importar la cartera": ["importar", "excel", "csv", "tokko", "migrar"],
        "Equipo y permisos": ["equipo", "agente", "invitar", "permisos", "usuarios"],
        "Actas de entrega": ["inventario", "acta", "entrega", "firma", "devolucion"],
        "Temporada": ["temporario", "vacaciones", "check-in", "llaves"],
        "Emprendimientos": ["loteo", "lotes", "masterplan", "desarrollo", "pozo"],
        "Informe": ["informe", "estadisticas", "metricas", "reporte"],
        "Agenda": ["visita", "cita", "calendario"],
        "Inmobiliaria": ["cbu", "cuit", "matricula", "datos"],
        "Tu plan": ["plan", "suscripcion", "pagar", "precio", "prueba", "factura", "abono"],
    ]

    static func normal(_ t: String) -> String {
        t.trimmingCharacters(in: .whitespaces).folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    static func coincide(_ it: Item, _ f: String) -> Bool {
        normal(it.texto).contains(f) || (claves[it.texto] ?? []).contains { normal($0).contains(f) || f.contains(normal($0)) }
    }

    /// Todas las secciones, por área (también las usa el buscador).
    static func grupos(duenio: Bool, avisos: Int) -> [(String, [Item])] {
        var g: [(String, [Item])] = [
            ("Día a día", [Item(icono: "calendar", texto: "Agenda", destino: AAgendaDia()),
                           Item(icono: "bell", texto: "Avisos", destino: AAvisos(), insignia: avisos),
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
        var ajustes = [Item(icono: "crown", texto: "Tu plan", destino: ASeccion(clave: "plan")),
                       Item(icono: "storefront", texto: "Inmobiliaria", destino: ASeccion(clave: "configuracion")),
                       Item(icono: "person.3", texto: "Equipo y permisos", destino: ASeccion(clave: "equipo")),
                       Item(icono: "puzzlepiece.extension", texto: "Integraciones", destino: ASeccion(clave: "integraciones")),
                       Item(icono: "wrench.and.screwdriver", texto: "Proveedores", destino: ASeccion(clave: "proveedores")),
                       Item(icono: "sparkles", texto: "Corredor en tu IA", destino: ASeccion(clave: "ia")),
                       Item(icono: "trash", texto: "Papelera", destino: ASeccion(clave: "papelera"))]
        if !duenio { ajustes.removeAll { ["Integraciones", "Corredor en tu IA"].contains($0.texto) } }
        g.append(("Configuración", ajustes))
        return g
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
                if filtro.isEmpty { AvisoPlan() }
                if filtro.isEmpty, !potenciar.isEmpty { potencia }
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
                                    .buttonStyle(Presionable())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 54) } }
                            }
                        }
                        .tarjeta()
                    }
                }
                if filtro.isEmpty {
                    Button {
                        Consejos.reiniciar()
                        estado.pestana = .inicio
                        estado.mostrarRecorrido = true
                    } label: {
                        Label("Ver el recorrido de nuevo", systemImage: "play.circle").font(Estilo.subheadFuerte.font)
                            .foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
    }

    /// «Potenciá tu negocio»: lo que todavía no usa, en tarjetas que se deslizan, cada una con «Activar».
    private var potencia: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Potenciá tu negocio")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(potenciar) { x in
                        VStack(alignment: .leading, spacing: 8) {
                            IconoTono(icono: x.icono, tono: .verde, tam: 40)
                            Text(x.titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
                            Text(Formato.sinViudas(x.texto)).estilo(.footnote).foregroundStyle(C.texto2)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Activar") { estado.abrir(x.destino) }.buttonStyle(BotonAccion())
                        }
                        .padding(14)
                        .frame(width: 220, height: 200, alignment: .topLeading)
                        .tarjeta()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
            .padding(.horizontal, -16)
        }
    }

    /// Los contadores y lo que falta activar, con lo que ya da la API (sin pedidos pesados).
    private func cargar() async {
        let api = estado.api
        var e: [String: (String, Tono)] = [:]
        let guia: Guia? = try? await api.get("/v1/panel/guia")
        let panel: Panel? = try? await api.get("/v1/panel")
        let deudas: [Deuda] = (try? await api.get("/v1/contratos/deudas")) ?? []
        if !deudas.isEmpty { e["Cobranzas"] = ("\(deudas.count) \(deudas.count == 1 ? "debe" : "deben")", .rojo) }
        if let n = panel?.numeros?.rendicionesListas, n > 0 { e["Rendiciones"] = ("\(n) para rendir", .azul) }
        if let n = panel?.numeros?.alquileresVigentes, n > 0 { e["Contratos"] = ("\(n) vigentes", .neutro) }
        if let n = panel?.numeros?.operacionesAbiertas, n > 0 { e["Operaciones"] = ("\(n) abiertas", .neutro) }
        if let n = guia?.contactos, n > 0 { e["Contactos"] = ("\(n)", .neutro) }
        if let j: JSONLibre = try? await api.get("/v1/revision"), Self.cuenta(j) > 0 { e["Revisión de la IA"] = ("\(Self.cuenta(j)) para revisar", .oro) }
        var iaConectada = true, consorcios = 1
        if estado.esDuenio {
            if let j: JSONLibre = try? await api.get("/v1/papelera"), Self.cuenta(j) > 0 { e["Papelera"] = ("\(Self.cuenta(j))", .neutro) }
            if let j: JSONLibre = try? await api.get("/v1/ia/conexiones") { iaConectada = Self.cuenta(j) > 0 }
            if let j: JSONLibre = try? await api.get("/v1/consorcios") {
                consorcios = Self.cuenta(j)
                if consorcios > 0 { e["Consorcios"] = ("\(consorcios)", .neutro) }
            }
        }
        let pasos = guia?.pasos
        if pasos?.whatsapp == false { e["Integraciones"] = ("WhatsApp sin conectar", .oro) }
        if pasos?.web == false { e["Mi web"] = ("Sin estrenar", .oro) }
        if pasos?.portales == false { e["Portales"] = ("Sin publicar", .oro) }
        if pasos?.equipo == false { e["Equipo y permisos"] = ("Sólo vos", .neutro) }
        if let sus = estado.suscripcion {
            e["Tu plan"] = (sus.nombreEstado, sus.estado == "vencida" ? .rojo : sus.pideAtencion ? .oro : .verde)
        }
        estados = e

        var x: [Potencia] = []
        if estado.esDuenio {
            if pasos?.whatsapp == false { x.append(.init(icono: "bubble.left.and.bubble.right", titulo: "Conectá tu WhatsApp", texto: "Todas las consultas en una bandeja, con respuestas guardadas.", destino: ASeccion(clave: "integraciones"))) }
            if (guia?.contratos ?? 0) == 0 { x.append(.init(icono: "dollarsign.circle", titulo: "Cobrá los alquileres", texto: "Quién debe, el recibo por WhatsApp y la rendición al dueño.", destino: AContratos())) }
            if pasos?.portales == false { x.append(.init(icono: "megaphone", titulo: "Publicá en portales", texto: "Mercado Libre y los portales, sin cargar dos veces.", destino: ASeccion(clave: "difusion"))) }
            if pasos?.web == false { x.append(.init(icono: "globe", titulo: "Tu web, con tu marca", texto: "Tus propiedades en tu web, con tu logo y tu dominio.", destino: ASeccion(clave: "web"))) }
            if !iaConectada { x.append(.init(icono: "sparkles", titulo: "Corredor en tu IA", texto: "Preguntale a ChatGPT o Claude por tu cartera y tus cobros.", destino: ASeccion(clave: "ia"))) }
            if consorcios == 0 { x.append(.init(icono: "building.columns", titulo: "Administrá consorcios", texto: "Expensas, deudores y trabajos del edificio.", destino: ASeccion(clave: "consorcios"))) }
            if pasos?.equipo == false { x.append(.init(icono: "person.badge.plus", titulo: "Sumá a tu equipo", texto: "Cada agente con su cartera y su agenda.", destino: ASeccion(clave: "equipo"))) }
        }
        if (guia?.propiedades ?? 0) < 5, estado.escribe { x.append(.init(icono: "square.and.arrow.down", titulo: "Traé tu cartera", texto: "Un Excel de tu sistema anterior y queda todo cargado.", destino: ASeccion(clave: "importar"))) }
        potenciar = x
    }

    /// Cuántos elementos trae una respuesta: una lista, o un objeto con su lista adentro.
    static func cuenta(_ j: JSONLibre) -> Int {
        switch j {
        case .lista(let l): return l.count
        case .objeto(let o):
            for k in ["items", "elementos", "filas", "lista", "datos", "resultados"] { if case .lista(let l)? = o[k] { return l.count } }
            return o.values.compactMap { if case .lista(let l) = $0 { return l.count } else { return nil } }.first ?? 0
        default: return 0
        }
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
        .buttonStyle(Presionable())
        .accessibilityLabel("Tu perfil")
    }

    private func fila(_ it: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: it.icono).font(.system(size: 18, weight: .medium)).foregroundStyle(C.accion).frame(width: 28)
            Text(it.texto).estilo(.filaLista).foregroundStyle(C.texto)
            Spacer(minLength: 0)
            if it.insignia > 0 { InsigniaRoja(n: it.insignia) }
            if case let (t, tono)? = estados[it.texto] {
                Text(t).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                    .foregroundStyle(tono == .neutro ? C.texto3 : tono.tinta).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.texto3)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
