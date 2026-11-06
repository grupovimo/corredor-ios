import SwiftUI

/// La pestaña «Más», en dos partes (decisión de Nahuel, 5/11): «Mi inmobiliaria» (la web, los datos,
/// el equipo, el plan…) y «Herramientas» (todo lo del día a día, por áreas). Arriba de todo la
/// apariencia (claro, oscuro o automático) y el buscador; la tarjeta de la inmobiliaria con el
/// porcentaje del alta mientras falte algo. La estructura la arma la API (la misma que el panel web);
/// sin ella todavía, la de siempre.
struct MasRaiz: View {
    @Environment(Estado.self) private var estado
    @Environment(\.colorScheme) private var esquema
    @AppStorage("tema") private var tema = "sistema"
    @AppStorage("todasLasSecciones") private var todas = false
    @State private var filtro = ""
    /// Lo que pasa en cada sección, a la derecha de su fila («3 deben», «WhatsApp sin conectar»), por clave.
    @State private var estados: [String: (String, Tono)] = [:]
    @State private var potenciar: [Potencia] = []
    /// La web pública de la inmobiliaria («Ver la web»).
    @State private var web: URL?
    /// «Tus inmobiliarias» (el «Cambiar» del menú del celular).
    @State private var cambiando = false

    /// Algo que el negocio todavía no usa, con su beneficio en una línea.
    struct Potencia: Identifiable {
        var icono: String
        var titulo: String
        var texto: String
        var destino: AnyHashable
        var id: String { titulo }
    }

    private var partes: [Estructura.Parte] { estado.estructura?.partes ?? Self.partesFijas(duenio: estado.esDuenio) }

    static func normal(_ t: String) -> String {
        t.trimmingCharacters(in: .whitespaces).folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    /// «Cobrar» encuentra Cobranzas, «expensas» Consorcios, «logo» Mi web: el nombre y sus palabras.
    static func coincide(_ it: Estructura.Item, _ f: String) -> Bool {
        normal(it.nombre).contains(f) || it.palabras.contains { normal($0).contains(f) || f.contains(normal($0)) }
    }

    private var encontradas: [Estructura.Item] {
        let f = Self.normal(filtro)
        guard !f.isEmpty else { return [] }
        return partes.flatMap { $0.grupos.flatMap(\.items) }.filter { Self.coincide($0, f) && Lugares.secciones[$0.clave] != nil }
    }

    /// Todas las secciones que se ven (para Spotlight y el buscador del Inicio): las de la estructura, o
    /// la guardada, o las de siempre; sólo las que la app sabe abrir.
    @MainActor
    static func secciones(_ e: Estructura?, duenio: Bool) -> [Estructura.Item] {
        let partes = (e ?? Guardado.leer(Estructura.self, clave: "estructura")?.0)?.partes ?? partesFijas(duenio: duenio)
        return partes.flatMap { $0.grupos.flatMap(\.items) }.filter { Lugares.secciones[$0.clave] != nil }
    }

    /// Sin la API todavía (la primera vez sin señal): las mismas dos partes, sin esconder nada.
    static func partesFijas(duenio: Bool) -> [Estructura.Parte] {
        func it(_ c: String, _ n: String) -> Estructura.Item { .init(clave: c, nombre: n, palabras: []) }
        var mia = [it("web", "Mi web"), it("configuracion", "Datos de la inmobiliaria"), it("equipo", "Equipo y permisos"), it("plan", "Tu plan")]
        if duenio { mia += [it("integraciones", "Integraciones"), it("ia", "Corredor en tu IA")] }
        mia.append(it("papelera", "Papelera"))
        return [
            .init(clave: "inmobiliaria", titulo: "Mi inmobiliaria", grupos: [.init(titulo: "", items: mia)]),
            .init(clave: "herramientas", titulo: "Herramientas", grupos: [
                .init(titulo: "Día a día", items: [it("agenda", "Agenda"), it("avisos", "Avisos"), it("buscar", "Buscar en todo")]),
                .init(titulo: "Cartera", items: [it("contactos", "Contactos"), it("operaciones", "Operaciones"), it("reservas", "Reservas"),
                                                 it("emprendimientos", "Emprendimientos"), it("temporada", "Temporada")]),
                .init(titulo: "Alquileres", items: [it("cobranzas", "Cobranzas"), it("contratos", "Contratos"), it("rendiciones", "Rendiciones"),
                                                    it("inventarios", "Actas de entrega"), it("indices", "Índices"), it("consorcios", "Consorcios"),
                                                    it("proveedores", "Proveedores")]),
                .init(titulo: "Difusión", items: [it("difusion", "Portales"), it("respuestas", "Respuestas guardadas"), it("importar", "Importar la cartera")]),
                .init(titulo: "Equipo", items: [it("objetivos", "Objetivos"), it("informe", "Informe"), it("revision", "Revisión de la IA"), it("actividad", "Actividad")]),
            ]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CabeceraPestana(sobre: estado.inmobiliaria?.nombre, titulo: "Más", acciones: [botonTema], logo: estado.estructura?.logo)
                    .padding(.horizontal, -16)
                persona
                Segmentado(opciones: [("sistema", "Automático"), ("claro", "Claro"), ("oscuro", "Oscuro")], elegido: $tema)
                    .accessibilityLabel("Apariencia")
                Buscador(placeholder: "Buscar una sección", texto: $filtro)
                if filtro.isEmpty {
                    AvisoPlan()
                    if let a = estado.estructura?.alta, estado.esDuenio, a.completo < 100 { completar(a) }
                    if !potenciar.isEmpty { potencia }
                    ForEach(partes) { p in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(p.titulo).estilo(.tituloSeccion).foregroundStyle(C.texto).padding(.horizontal, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(p.grupos, id: \.titulo) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    if !g.titulo.isEmpty { TituloBloque(texto: g.titulo) }
                                    lista(g.items)
                                }
                            }
                        }
                    }
                    if estado.estructura?.escondido == true || todas {
                        Toggle(isOn: $todas) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mostrar todas las secciones").estilo(.filaLista).foregroundStyle(C.texto)
                                Text(Formato.sinViudas("Escondemos lo que no usás según tus rubros. Los cambiás en Datos de la inmobiliaria."))
                                    .estilo(.footnote).foregroundStyle(C.texto2)
                            }
                        }
                        .tint(C.accion)
                        .padding(14).tarjeta()
                    }
                    if let web { verLaWeb(web) }
                    Button {
                        Consejos.reiniciar()
                        estado.pestana = .inicio
                        estado.mostrarRecorrido = true
                    } label: {
                        Label("Ver el recorrido de nuevo", systemImage: "play.circle").font(Estilo.subheadFuerte.font)
                            .foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    pie
                } else if encontradas.isEmpty {
                    EstadoVacio(icono: "magnifyingglass", titulo: "No hay una sección «\(filtro)»", texto: "Probá con otra palabra, o buscá clientes y propiedades.",
                                accion: ("Buscar «\(filtro)» en todo", { estado.abrir(ABuscar(texto: filtro)) }))
                } else {
                    lista(encontradas)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .pantallaRaiz()
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $cambiando) { TusInmobiliarias().presentationDetents([.medium, .large]) }
        .onChange(of: todas) { _, _ in Task { await estado.cargarEstructura() } }
    }

    /// El sol o la luna, para pasar de claro a oscuro en un toque (también arriba del Inicio).
    private var botonTema: AccionCabecera {
        let oscuro = esquema == .dark
        return AccionCabecera(icono: oscuro ? "sun.max" : "moon", etiqueta: oscuro ? "Pasar a modo claro" : "Pasar a modo oscuro") {
            Haptico.seleccion()
            tema = oscuro ? "claro" : "oscuro"
        }
    }

    private func lista(_ items: [Estructura.Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if let l = Lugares.secciones[it.clave] {
                    Button { estado.abrir(l.1) } label: { fila(it, icono: l.0) }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 54) } }
                }
            }
        }
        .tarjeta()
    }

    /// «Tu inmobiliaria al 70 %»: lo que falta del alta, a un toque.
    private func completar(_ a: Alta) -> some View {
        Button { estado.altaAbierta = PasoAlta(clave: a.faltan.first) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(C.linea, lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(a.completo) / 100).stroke(C.accion, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(a.completo)%").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu inmobiliaria al \(a.completo) %").estilo(.filaLista).foregroundStyle(C.texto)
                    Text(Formato.sinViudas("Completala y tu web queda lista")).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.texto3)
            }
            .padding(14)
            .background(C.crema, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .accessibilityLabel("Tu inmobiliaria está completa al \(a.completo) por ciento. Completar")
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
        if !deudas.isEmpty { e["cobranzas"] = ("\(deudas.count) \(deudas.count == 1 ? "debe" : "deben")", .rojo) }
        if let n = panel?.numeros?.rendicionesListas, n > 0 { e["rendiciones"] = ("\(n) para rendir", .azul) }
        if let n = panel?.numeros?.alquileresVigentes, n > 0 { e["contratos"] = ("\(n) vigentes", .neutro) }
        if let n = panel?.numeros?.operacionesAbiertas, n > 0 { e["operaciones"] = ("\(n) abiertas", .neutro) }
        if let n = guia?.contactos, n > 0 { e["contactos"] = ("\(n)", .neutro) }
        if estado.avisosPendientes > 0 { e["avisos"] = ("\(estado.avisosPendientes)", .rojo) }
        if let j: JSONLibre = try? await api.get("/v1/revision"), Self.cuenta(j) > 0 { e["revision"] = ("\(Self.cuenta(j)) para revisar", .oro) }
        if let j: JSONLibre = try? await api.get("/v1/papelera"), Self.cuenta(j) > 0 { e["papelera"] = ("\(Self.cuenta(j))", .neutro) }
        var iaConectada = true, consorcios = 1
        if estado.esDuenio {
            if let j: JSONLibre = try? await api.get("/v1/ia/conexiones") { iaConectada = Self.cuenta(j) > 0 }
            if let j: JSONLibre = try? await api.get("/v1/consorcios") {
                consorcios = Self.cuenta(j)
                if consorcios > 0 { e["consorcios"] = ("\(consorcios)", .neutro) }
            }
            if let b: Borrador = try? await api.get("/v1/web/borrador"), b.hayBorrador { e["web"] = ("Sin publicar", .oro) }
        }
        let pasos = guia?.pasos
        if pasos?.whatsapp == false { e["integraciones"] = ("WhatsApp sin conectar", .oro) }
        if e["web"] == nil, pasos?.web == false { e["web"] = ("Sin estrenar", .oro) }
        if pasos?.portales == false { e["difusion"] = ("Sin publicar", .oro) }
        if pasos?.equipo == false { e["equipo"] = ("Sólo vos", .neutro) }
        // Como el panel (lib/server/configuracion.ts): «6 · 1 invitación», «ML pide reconectar» o «ML con N
        // errores», «2 · 30 días» en la papelera.
        if let personas: [Miembro] = try? await api.get("/v1/equipo") {
            var t = "\(personas.count)"
            if estado.esDuenio, let inv: JSONLibre = try? await api.get("/v1/invitaciones"), Self.cuenta(inv) > 0 {
                t += " · \(Formato.cantidad(Self.cuenta(inv), "invitación", "invitaciones"))"
            }
            e["equipo"] = (t, .neutro)
        }
        struct ML: Decodable { var conectada: Bool?; var reautorizar: Bool? }
        let ml: ML? = try? await api.get("/v1/mercadolibre")
        if ml?.conectada == true, ml?.reautorizar == true {
            e["integraciones"] = ("ML pide reconectar", .oro)
        } else if let j: JSONLibre = try? await api.get("/v1/publicaciones", query: [.init(name: "portal", value: "mercadolibre"), .init(name: "estado", value: "error"), .init(name: "limite", value: "50")]),
                  Self.cuenta(j) > 0 {
            e["integraciones"] = ("ML con \(Formato.cantidad(Self.cuenta(j), "error", "errores"))", .oro)
        }
        if let n = e["papelera"]?.0 { e["papelera"] = ("\(n) · 30 días", .neutro) }
        if let i: Inmobiliaria = try? await api.get("/v1/inmobiliaria") { web = i.web.flatMap(URL.init(string:)) }
        if let sus = estado.suscripcion {
            e["plan"] = (sus.nombreEstado, sus.estado == "vencida" ? .rojo : sus.pideAtencion ? .oro : .verde)
        }
        estados = e

        // Lo que se puede activar, sólo si la sección está a la vista (los rubros la pueden esconder).
        let visibles = Set(partes.flatMap { $0.grupos.flatMap { $0.items.map(\.clave) } })
        var x: [Potencia] = []
        if estado.esDuenio {
            if pasos?.whatsapp == false { x.append(.init(icono: "bubble.left.and.bubble.right", titulo: "Conectá tu WhatsApp", texto: "Todas las consultas en una bandeja, con respuestas guardadas.", destino: ASeccion(clave: "integraciones"))) }
            if (guia?.contratos ?? 0) == 0, visibles.contains("contratos") { x.append(.init(icono: "dollarsign.circle", titulo: "Cobrá los alquileres", texto: "Quién debe, el recibo por WhatsApp y la rendición al dueño.", destino: AContratos())) }
            if pasos?.portales == false { x.append(.init(icono: "megaphone", titulo: "Publicá en portales", texto: "Mercado Libre y los portales, sin cargar dos veces.", destino: ASeccion(clave: "difusion"))) }
            if !iaConectada { x.append(.init(icono: "sparkles", titulo: "Corredor en tu IA", texto: "Preguntale a ChatGPT o Claude por tu cartera y tus cobros.", destino: ASeccion(clave: "ia"))) }
            if consorcios == 0, visibles.contains("consorcios") { x.append(.init(icono: "building.columns", titulo: "Administrá consorcios", texto: "Expensas, deudores y trabajos del edificio.", destino: ASeccion(clave: "consorcios"))) }
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

    /// La persona y su inmobiliaria: abre el perfil (cuenta, firma, Face ID, salir); «Cambiar» abre «Tus
    /// inmobiliarias» (pasar a otra, aceptar una invitación o crear otra), como el menú del celular.
    private var persona: some View {
        HStack(spacing: 8) {
            Button { estado.abrir(APerfil()) } label: {
                HStack(spacing: 12) {
                    Text(Formato.iniciales(estado.usuario?.completo ?? "C"))
                        .font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font)
                        .foregroundStyle(C.oro)
                        .frame(width: 48, height: 48)
                        .background(C.verde700, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(estado.usuario?.completo ?? "Tu cuenta").estilo(.filaLista).foregroundStyle(C.texto)
                        Text([estado.inmobiliaria?.nombre, ElegirInmobiliaria.rol(estado.rol)].compactMap { $0 }.joined(separator: " · "))
                            .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            .accessibilityLabel("Mi perfil y avisos")
            Button("Cambiar") { cambiando = true }
                .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                .padding(.horizontal, 12).frame(height: 34).background(C.hundida, in: Capsule())
                .frame(minHeight: 44)
                .accessibilityLabel("Cambiar de inmobiliaria")
        }
        .padding(14)
        .tarjeta()
    }

    /// «Ver la web»: la web pública de la inmobiliaria, se abre aparte.
    private func verLaWeb(_ u: URL) -> some View {
        Link(destination: u) {
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.system(size: 18, weight: .medium)).foregroundStyle(C.accion).frame(width: 28)
                Text("Ver la web").estilo(.filaLista).foregroundStyle(C.texto)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.texto3)
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .tarjeta()
        .accessibilityLabel("Ver la web (se abre aparte)")
    }

    /// El pie del menú: quiénes están en la calle y si todo está guardado (o sin señal, en cola).
    private var pie: some View {
        let ins = Insignias.compartidas
        return VStack(alignment: .leading, spacing: 8) {
            if !ins.enLaCalle.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(ins.enLaCalle.prefix(3)) { p in
                            AvatarIniciales(nombre: p.nombre, tam: 26).overlay(Circle().stroke(C.fondo, lineWidth: 2))
                        }
                    }
                    Text("\(ins.enLaCalle.count) en la calle").estilo(.footnoteFuerte).foregroundStyle(C.texto2)
                }
                .accessibilityElement(children: .combine)
            }
            if ins.sinRed || !estado.cola.cambios.isEmpty {
                Label("Sin señal · se envía al volver", systemImage: "icloud.slash").estilo(.footnote).foregroundStyle(C.avisoTinta)
            } else {
                Label("Todo guardado\(ins.guardadoEn.map { " · " + Formato.hace($0) } ?? "")", systemImage: "checkmark.icloud").estilo(.footnote).foregroundStyle(C.texto3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func fila(_ it: Estructura.Item, icono: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono).font(.system(size: 18, weight: .medium)).foregroundStyle(C.accion).frame(width: 28)
            Text(it.nombre).estilo(.filaLista).foregroundStyle(C.texto)
            Spacer(minLength: 0)
            if case let (t, tono)? = estados[it.clave] {
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

/// GET /v1/web/borrador: la marca con los cambios sin publicar (la misma que edita el panel).
struct Borrador: Codable, Equatable {
    var marca: [String: JSONLibre]
    var hayBorrador: Bool
    var en: String?
}

/// «Tus inmobiliarias»: la actual con el tilde, las otras para pasar con un toque («Estás en …») y abajo
/// aceptar una invitación o crear otra (lib/ui/shell/CambioInmobiliaria.svelte).
struct TusInmobiliarias: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var enviando = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(estado.sesion?.inmobiliarias ?? []) { m in
                        let esta = m.id == estado.sesion?.inmobiliariaId
                        Button { elegir(m, esta: esta) } label: {
                            HStack(spacing: 12) {
                                Text(String(m.nombre.prefix(1)).uppercased()).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                                    .foregroundStyle(esta ? C.oro : C.texto)
                                    .frame(width: 38, height: 38).background(esta ? C.verde700 : C.hundida, in: .rect(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text("\(ElegirInmobiliaria.rol(m.rol)) · \(m.slug).\(Api.web().host ?? "corredor.com.ar")").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                                }
                                Spacer()
                                if esta { Image(systemName: "checkmark.circle.fill").foregroundStyle(C.accion) }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(enviando)
                        .accessibilityAddTraits(esta ? .isSelected : [])
                    }
                }
                Section {
                    Button { ir(ASeccion(clave: "invitaciones")) } label: { Label("Aceptar una invitación", systemImage: "envelope") }
                    Button { ir(ASeccion(clave: "empezar")) } label: { Label("Crear otra inmobiliaria", systemImage: "plus.square.on.square") }
                }
            }
            .navigationTitle("Tus inmobiliarias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } } }
        }
    }

    private func ir(_ d: AnyHashable) {
        cerrar()
        estado.abrir(d)
    }

    private func elegir(_ m: Sesion.Membresia, esta: Bool) {
        guard !esta else { return cerrar() }
        enviando = true
        Task {
            defer { enviando = false }
            do {
                try await estado.elegir(m)
                cerrar()
                estado.avisar("Estás en \(m.nombre)")
            } catch { estado.avisar(error) }
        }
    }
}
