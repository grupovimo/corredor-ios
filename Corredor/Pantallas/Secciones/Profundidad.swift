import Charts
import SwiftUI
import UniformTypeIdentifiers

// Las secciones del panel que en la primera tanda eran listas genéricas, ahora con todo lo de la web.

// MARK: - Portales (difusión)

struct ResumenPublicaciones: Codable {
    var total: Int?
    var difundibles: Int?
    var sinPublicar: Int?
    var conError: Int?
    var esperando: Int?
    var sinVistas: Int?
    var webVisitasSemana: Int?
    var webVisitasSemanaAnterior: Int?
}

struct PublicacionLista: Codable, Identifiable, Hashable {
    var id: String
    var propiedadId: String
    var propiedad: String?
    var portal: String
    var estado: String
    var url: String?
    var error: String?
    var visitas: Int?
    var visitasSemana: Int?
    var consultas: Int?
    var publicadaEn: Date?
}

/// Portales: qué está publicado dónde, lo que tiene error y lo que falta difundir; pausar y republicar.
struct Portales: View {
    @Environment(Estado.self) private var estado
    @State private var r: ResumenPublicaciones?
    @State private var pubs: [PublicacionLista]?
    @State private var portal = "todos"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Publicadas", valor: "\((r.total ?? 0) - (r.sinPublicar ?? 0))")
                        Cifra(etiqueta: "Sin publicar", valor: "\(r.sinPublicar ?? 0)")
                        Cifra(etiqueta: "Con error", valor: "\(r.conError ?? 0)")
                    }
                    if let v = r.webVisitasSemana {
                        let antes = r.webVisitasSemanaAnterior ?? 0
                        TarjetaAvance(titulo: "Visitas a tu web", cifra: "\(Formato.numero(v)) esta semana",
                                      avance: antes > 0 ? min(1, Double(v) / Double(max(v, antes))) : 1,
                                      pie: antes > 0 ? (v >= antes ? "▲ \(Int((Double(v - antes) / Double(antes) * 100).rounded())) % contra la anterior" : "▼ \(Int((Double(antes - v) / Double(antes) * 100).rounded())) % contra la anterior") : "La primera semana con datos")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("todos", "Todos"), ("error", "Con error"), ("mercadolibre", "Mercado Libre"), ("zonaprop", "Zonaprop"), ("argenprop", "Argenprop")], id: \.0) { k, n in
                            ChipFiltro(texto: n, activo: portal == k) { portal = k }
                        }
                    }
                }
                if let pubs {
                    let l = pubs.filter { portal == "todos" || (portal == "error" ? $0.error != nil : $0.portal == portal) }
                    if l.isEmpty {
                        EstadoVacio(icono: "megaphone", titulo: "Todavía no publicaste en portales",
                                    texto: "Conectá Mercado Libre y los portales, y publicás desde la ficha de cada propiedad sin cargar dos veces.",
                                    accion: estado.esDuenio ? ("Conectar", { estado.abrir(ASeccion(clave: "integraciones")) }) : nil,
                                    secundaria: ("Ver la cartera", { estado.pestana = .propiedades }))
                            .padding(.top, 30)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, p in
                            HStack(spacing: 12) {
                                LogoPortal(portal: p.portal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.propiedad ?? "Propiedad").estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(p.error ?? [PublicacionPortal.nombres[p.portal] ?? p.portal, p.visitasSemana.map { "\($0) visitas" }, p.consultas.map { Formato.cantidad($0, "consulta", "consultas") }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .estilo(.footnote).foregroundStyle(p.error != nil ? C.errorTinta : C.texto2).lineLimit(2)
                                }
                                Spacer()
                                if estado.escribe {
                                    Menu {
                                        Button { estado.abrir(AFichaPropiedad(id: p.propiedadId)) } label: { Label("Ver la propiedad", systemImage: "house") }
                                        if let u = p.url.flatMap(URL.init(string:)) { Link(destination: u) { Label("Ver en el portal", systemImage: "safari") } }
                                        if p.estado == "publicada" || p.estado == "activa" {
                                            Button { Task { await accion(p, pausar: true) } } label: { Label("Pausar", systemImage: "pause.circle") }
                                        } else {
                                            Button { Task { await accion(p, pausar: false) } } label: { Label(p.error != nil ? "Reintentar" : "Publicar", systemImage: "arrow.up.circle") }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion) }.accessibilityLabel("Más acciones")
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                } else { EsqueletoFilas(filas: 6) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Portales")
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        r = try? await estado.api.get("/v1/publicaciones/resumen")
        pubs = (try? await estado.api.get("/v1/publicaciones", query: [.init(name: "limite", value: "500")])) ?? pubs ?? []
    }

    private func accion(_ p: PublicacionLista, pausar: Bool) async {
        do {
            try await estado.api.hacer("POST", "/v1/propiedades/\(p.propiedadId)/publicaciones/\(p.portal)\(pausar ? "/pausar" : "")")
            estado.avisar(pausar ? "Pausada" : "Publicando")
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}

// MARK: - Actividad

struct EntradaActividad: Codable, Identifiable, Hashable {
    var id: String
    var actorTipo: String?
    var actorNombre: String?
    var accion: String?
    var entidad: String?
    var entidadId: String?
    var entidadTitulo: String?
    var creadoEn: Date?
}

/// Actividad: quién hizo qué y cuándo (también la IA), con el filtro por persona y lo que se tocó.
struct Actividad: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [EntradaActividad]?
    @State private var quien = ""

    var body: some View {
        List {
            if let lista, lista.isEmpty {
                EstadoVacio(icono: "clock.arrow.circlepath", titulo: "Todavía no hay movimientos",
                            texto: "Acá vas a ver quién cargó, cambió o borró algo, y cuándo.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if let lista {
                let personas = Array(Set(lista.compactMap(\.actorNombre))).sorted()
                if personas.count > 1 {
                    Picker("Quién", selection: $quien) { Text("Todos").tag(""); ForEach(personas, id: \.self) { Text($0).tag($0) } }
                }
                ForEach(lista.filter { quien.isEmpty || $0.actorNombre == quien }) { a in
                    Button { abrir(a) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            IconoTono(icono: a.actorTipo == "ia" ? "sparkles" : Self.icono(a.accion), tono: a.actorTipo == "ia" ? .violeta : .verde, tam: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.actorNombre ?? (a.actorTipo == "ia" ? "Tu IA" : "Alguien")) \(Self.verbo(a.accion)) \(Self.cosa(a.entidad))").estilo(.subhead).foregroundStyle(C.texto)
                                if let t = a.entidadTitulo { Text(t).estilo(.filaLista).foregroundStyle(C.texto) }
                                if let f = a.creadoEn { Text(Formato.cuando(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                            }
                        }
                    }
                }
            } else { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Actividad")
        .refreshable { await cargar() }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/actividad", query: [.init(name: "limite", value: "300")])) ?? lista ?? [] }

    private func abrir(_ a: EntradaActividad) {
        guard let id = a.entidadId else { return }
        switch a.entidad {
        case "propiedad": estado.abrir(AFichaPropiedad(id: id))
        case "contacto": estado.abrir(AFichaContacto(id: id))
        case "operacion": estado.abrir(AFichaOperacion(id: id))
        case "contrato": estado.abrir(AFichaContrato(id: id))
        case "cita": estado.abrir(ACita(id: id))
        default: break
        }
    }

    static func verbo(_ a: String?) -> String {
        ["crear": "cargó", "editar": "cambió", "borrar": "borró", "restaurar": "restauró", "mover": "movió", "compartir": "compartió", "emitir": "emitió", "cobrar": "cobró"][a ?? ""] ?? (a ?? "tocó")
    }

    static func cosa(_ e: String?) -> String {
        ["propiedad": "una propiedad", "contacto": "un contacto", "operacion": "una operación", "contrato": "un contrato", "cobro": "un cobro", "cita": "una cita",
         "rendicion": "una rendición", "respuesta_guardada": "una respuesta guardada"][e ?? ""] ?? (e ?? "")
    }

    static func icono(_ a: String?) -> String {
        ["crear": "plus", "editar": "pencil", "borrar": "trash", "mover": "arrow.right", "compartir": "square.and.arrow.up", "cobrar": "dollarsign"][a ?? ""] ?? "clock"
    }
}

// MARK: - Tarifas de temporada

struct TarifaAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String?
    var desde: String
    var hasta: String
    var precio: Double
    var moneda: String?
    var periodo: String?
    var nochesMinimas: Int?
}

/// Tarifas de temporada de una propiedad: por rango de fechas, con noches mínimas.
struct TarifasTemporada: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var lista: [TarifaAPI] = []
    @State private var editando: TarifaAPI?

    var body: some View {
        List {
            if lista.isEmpty { Text("Cargá la tarifa de cada temporada (alta, baja, fines de semana largos).").foregroundStyle(C.texto2) }
            ForEach(lista) { t in
                Button { editando = t } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.nombre ?? "Tarifa").estilo(.filaLista).foregroundStyle(C.texto)
                            Text("\(t.desde) al \(t.hasta)\(t.nochesMinimas.map { " · mínimo \($0) noches" } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Text("\(Formato.plata(t.precio, t.moneda ?? "USD")) / \(t.periodo == "semana" ? "semana" : t.periodo == "mes" ? "mes" : "noche")").fontWeight(.semibold).foregroundStyle(C.texto)
                    }
                }
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/tarifas/\(t.id)"); await cargar() } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Tarifas")
        .toolbar { if estado.escribe { Button { editando = TarifaAPI(id: "", desde: Formato.diaISO(Date()), hasta: Formato.diaISO(Date().addingTimeInterval(30 * 86400)), precio: 0, moneda: "USD", periodo: "noche") } label: { Image(systemName: "plus") }.accessibilityLabel("Sumar") } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { t in FormTarifa(t: t) { x in Task { await guardar(x) } } }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/propiedades/\(propiedad)/tarifas")) ?? [] }

    private func guardar(_ t: TarifaAPI) async {
        struct C: Encodable { var nombre: String?; var desde: String; var hasta: String; var precio: Double; var moneda: String; var periodo: String; var nochesMinimas: Int? }
        let c = C(nombre: t.nombre?.nonEmpty, desde: t.desde, hasta: t.hasta, precio: t.precio, moneda: t.moneda ?? "USD", periodo: t.periodo ?? "noche", nochesMinimas: t.nochesMinimas)
        do {
            if t.id.isEmpty { try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad)/tarifas", c) } else { try await estado.api.hacer("PUT", "/v1/propiedades/\(propiedad)/tarifas/\(t.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormTarifa: View {
    @Environment(\.dismiss) private var cerrar
    @State var t: TarifaAPI
    var guardar: (TarifaAPI) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (temporada alta…)", text: Binding(get: { t.nombre ?? "" }, set: { t.nombre = $0 }))
                DatePicker("Desde", selection: Binding(get: { Fecha.dia(t.desde) ?? Date() }, set: { t.desde = Formato.diaISO($0) }), displayedComponents: .date)
                DatePicker("Hasta", selection: Binding(get: { Fecha.dia(t.hasta) ?? Date() }, set: { t.hasta = Formato.diaISO($0) }), displayedComponents: .date)
                Picker("Moneda", selection: Binding(get: { t.moneda ?? "USD" }, set: { t.moneda = $0 })) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Precio", value: $t.precio, format: .number).keyboardType(.decimalPad)
                Picker("Por", selection: Binding(get: { t.periodo ?? "noche" }, set: { t.periodo = $0 })) { Text("Noche").tag("noche"); Text("Semana").tag("semana"); Text("Mes").tag("mes") }
                Stepper("Mínimo \(t.nochesMinimas ?? 1) noches", value: Binding(get: { t.nochesMinimas ?? 1 }, set: { t.nochesMinimas = $0 }), in: 1...60)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(t); cerrar() }.disabled(t.precio <= 0) }
            }
        }
    }
}

// MARK: - Vistas de una propiedad

/// Vistas y consultas de una propiedad: el gráfico por día de los últimos 30 días.
struct VistasPropiedad: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var dias: [Dia] = []
    struct Dia: Codable, Identifiable { var dia: String; var cantidad: Int; var id: String { dia } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Cifra(etiqueta: "Últimos 30 días", valor: Formato.numero(dias.reduce(0) { $0 + $1.cantidad }))
                    Cifra(etiqueta: "Últimos 7 días", valor: Formato.numero(dias.suffix(7).reduce(0) { $0 + $1.cantidad }))
                }
                Chart(dias) { d in
                    BarMark(x: .value("Día", Fecha.dia(d.dia) ?? Date(), unit: .day), y: .value("Vistas", d.cantidad))
                        .foregroundStyle(C.accion).cornerRadius(3)
                }
                .frame(height: 220).padding(14).tarjeta()
                if dias.isEmpty { Text("Todavía nadie la vio. Publicala y compartila para que llegue.").estilo(.subhead).foregroundStyle(C.texto2) }
            }
            .padding(16)
        }
        .pantallaApilada("Vistas")
        .task {
            if let l: [Dia] = try? await estado.api.get("/v1/propiedades/\(propiedad)/vistas") { dias = l }
            else if let o: [String: [Dia]] = try? await estado.api.get("/v1/propiedades/\(propiedad)/vistas") { dias = o.values.first ?? [] }
        }
    }
}

// MARK: - Corredor en tu IA

/// Corredor en tu IA: las IA conectadas (Claude, ChatGPT), qué pueden hacer y el link para conectar.
struct CorredorEnTuIA: View {
    @Environment(Estado.self) private var estado
    @State private var conexiones: [JSONLibre] = []
    @State private var ajustes: Ajustes?
    struct Ajustes: Codable { var habilitado: Bool?; var aviso: Bool?; var mover: Bool?; var agendar: Bool?; var url: String? }

    var body: some View {
        Form {
            Section(footer: Text("Agregá Corredor como conector en Claude o ChatGPT con este link. Lo que tu IA quiera cambiar te llega a Revisión.")) {
                if let u = ajustes?.url {
                    HStack { Text(u).font(.footnote.monospaced()); Spacer(); Button { UIPasteboard.general.string = u; estado.avisar("Link copiado") } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copiar el link") }
                }
            }
            if estado.esDuenio, ajustes != nil {
                Section("Qué puede hacer") {
                    Toggle("Prendido", isOn: bind(\.habilitado))
                    Toggle("Mover operaciones sin pedir permiso", isOn: bind(\.mover))
                    Toggle("Agendar visitas sin pedir permiso", isOn: bind(\.agendar))
                    Toggle("Avisarme cuando use algo", isOn: bind(\.aviso))
                }
            }
            Section("Conectadas") {
                if conexiones.isEmpty { Text("Todavía no conectaste ninguna.").foregroundStyle(C.texto2) }
                ForEach(conexiones.indices, id: \.self) { i in
                    let c = conexiones[i]
                    VStack(alignment: .leading) {
                        Text(c["cliente"]?.texto ?? c["nombre"]?.texto ?? "IA").estilo(.filaLista)
                        Text([c["persona"]?.texto ?? c["usuarioNombre"]?.texto, c["usadaEn"]?.texto.flatMap(Fecha.iso).map { "usada \(Formato.hace($0))" }].compactMap { $0 }.joined(separator: " · "))
                            .estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions {
                        if let id = c["id"]?.texto { Button("Desconectar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/ia/conexiones/\(id)"); await cargar() } } }
                    }
                }
            }
            Section { Button("Revisión de la IA") { estado.abrir(ASeccion(clave: "revision")) } }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Corredor en tu IA")
        .task(id: estado.version) { await cargar() }
    }

    private func bind(_ k: WritableKeyPath<Ajustes, Bool?>) -> Binding<Bool> {
        Binding(get: { ajustes?[keyPath: k] ?? false }, set: { v in
            ajustes?[keyPath: k] = v
            Task { if let a = ajustes { try? await estado.api.hacer("PUT", "/v1/ia/ajustes", a) } }
        })
    }

    private func cargar() async {
        ajustes = try? await estado.api.get("/v1/ia/ajustes")
        if case .lista(let l)? = try? await estado.api.get("/v1/ia/conexiones") as JSONLibre { conexiones = l }
    }
}

// MARK: - Conectar el número de WhatsApp

/// Conectar el número de WhatsApp (Meta) desde el celular: el identificador del número, la cuenta, el
/// token y el secreto de la app; después, la verificación.
struct ConectarWhatsApp: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var numeroId = ""
    @State private var cuentaId = ""
    @State private var token = ""
    @State private var secreto = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Lo sacás de Meta for Developers › tu app › WhatsApp › Configuración de la API.")) {
                    TextField("Identificador del número de teléfono", text: $numeroId).keyboardType(.numberPad)
                    TextField("Identificador de la cuenta de WhatsApp Business", text: $cuentaId).keyboardType(.numberPad)
                    SecureField("Token de acceso permanente", text: $token)
                    SecureField("Clave secreta de la app (opcional)", text: $secreto)
                }
            }
            .navigationTitle("Conectar WhatsApp").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Conectar") { Task { await conectar() } }.disabled(numeroId.isEmpty || token.isEmpty || guardando) }
            }
        }
    }

    private func conectar() async {
        guardando = true
        defer { guardando = false }
        struct C: Encodable { var numeroId: String; var cuentaId: String?; var token: String; var appSecreto: String? }
        do {
            try await estado.api.hacer("PUT", "/v1/whatsapp/numero", C(numeroId: numeroId, cuentaId: cuentaId.nonEmpty, token: token, appSecreto: secreto.nonEmpty))
            try? await estado.api.hacer("POST", "/v1/whatsapp/numero/verificacion")
            estado.sugerir("WhatsApp conectado", "Respuestas", ASeccion(clave: "respuestas"))
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

// MARK: - Perfil: firma y sesiones

/// La firma de los mails que salen a tu nombre y las sesiones abiertas (cerrar las de otros aparatos).
struct FirmaYSesiones: View {
    @Environment(Estado.self) private var estado
    @State private var firma = ""
    @State private var activa = false
    @State private var sesiones: [SesionAbierta] = []
    struct SesionAbierta: Codable, Identifiable { var id: String; var agente: String?; var ip: String?; var vistoEn: Date?; var actual: Bool? }

    var body: some View {
        Form {
            Section(header: Text("Firma de tus mails"), footer: Text("Sale al pie de las fichas y los mails que mandás desde Corredor.")) {
                Toggle("Usar firma", isOn: $activa)
                TextField("Martín Ríos · Luna Propiedades · 11 4823-1190", text: $firma, axis: .vertical).lineLimit(2...6)
                Button("Guardar la firma") {
                    Task {
                        struct C: Encodable { var activa: Bool; var texto: String? }
                        do { try await estado.api.hacer("PUT", "/v1/perfil/firma", C(activa: activa, texto: firma.nonEmpty)); estado.avisar("Firma guardada") } catch { estado.avisar(error) }
                    }
                }
            }
            Section("Sesiones abiertas") {
                ForEach(sesiones) { x in
                    VStack(alignment: .leading) {
                        Text((x.agente ?? "Aparato") + (x.actual == true ? " · este" : "")).estilo(.filaLista).lineLimit(1)
                        Text([x.ip, x.vistoEn.map { "visto \(Formato.hace($0))" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions {
                        if x.actual != true { Button("Cerrar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/auth/sesiones/\(x.id)"); await cargar() } } }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Firma y sesiones")
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        struct F: Decodable { var activa: Bool?; var texto: String? }
        if let f: F = try? await estado.api.get("/v1/perfil/firma") { activa = f.activa ?? false; firma = f.texto ?? "" }
        sesiones = (try? await estado.api.get("/v1/auth/sesiones")) ?? []
    }
}

// MARK: - Reservas

/// Las reservas de venta y alquiler abiertas: la seña, hasta cuándo vale, y cerrarla (concretada o caída).
struct Reservas: View {
    @Environment(Estado.self) private var estado
    var ruta = "/v1/reservas"
    var body: some View {
        ListaGenerica(titulo: "Reservas", ruta: ruta, icono: "hand.raised", vacio: "No hay reservas abiertas.") { x in
            guard let id = x["id"]?.texto, estado.escribe else { return [] }
            struct C: Encodable { var resultado: String; var motivo: String?; var cerradaEl: String }
            return [
                ("Se concretó", { Task { try? await estado.api.hacer("POST", "/v1/reservas/\(id)/cerrar", C(resultado: "concretada", cerradaEl: Formato.diaISO(Date()))); estado.version += 1; estado.avisar("Reserva concretada") } }),
                ("Se cayó", { Task { try? await estado.api.hacer("POST", "/v1/reservas/\(id)/cerrar", C(resultado: "caida", cerradaEl: Formato.diaISO(Date()))); estado.version += 1; estado.avisar("Reserva caída") } }),
            ]
        }
    }
}

// MARK: - Revisión (lo que armó la IA)

struct BorradorIA: Codable, Identifiable, Hashable {
    var id: String
    var estado: String?
    var tipo: String?
    var canal: String?
    var asunto: String?
    var texto: String?
    var motivo: String?
    var contactoId: String?
    var propiedadId: String?
    var contactoNombre: String?
    var propiedadTitulo: String?
    var deLaIA: Bool?
    var creadoEn: Date?
}

/// Revisión: mensajes, descripciones y notas que armó la IA (o vos) y esperan que alguien los mire. Se
/// corrigen, se usan (WhatsApp, mail, la descripción de la ficha, una nota) o se descartan.
struct RevisionIA: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [BorradorIA]?
    @State private var editando: BorradorIA?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty { EstadoVacio(icono: "checkmark.shield", titulo: "Nada para revisar", texto: "Lo que tu IA arme (mensajes, descripciones, notas) llega acá antes de usarse.").padding(.top, 40) }
                    ForEach(lista) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(Self.tipo(b), systemImage: b.deLaIA == true ? "sparkles" : "doc.text").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font)
                                    .foregroundStyle(b.deLaIA == true ? C.violetaTinta : C.texto2)
                                Spacer()
                                if let f = b.creadoEn { Text(Formato.hace(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                            }
                            Text([b.contactoNombre, b.propiedadTitulo].compactMap { $0 }.joined(separator: " · ")).estilo(.filaLista).foregroundStyle(C.texto)
                            if let a = b.asunto { Text(a).estilo(.subheadFuerte).foregroundStyle(C.texto) }
                            Text(b.texto ?? "").estilo(.texto14).foregroundStyle(C.texto2).lineLimit(6)
                            if estado.escribe {
                                HStack(spacing: 8) {
                                    Button(Self.usar(b)) { Task { await usar(b) } }.buttonStyle(BotonAccion())
                                    Button("Corregir") { editando = b }.buttonStyle(BotonHundido())
                                    Button { Task { await descartar(b) } } label: { Image(systemName: "trash") }.buttonStyle(BotonHundido()).frame(width: 56)
                                        .accessibilityLabel("Descartar")
                                }
                            }
                        }
                        .padding(14).tarjeta()
                    }
                } else { EsqueletoFilas(filas: 4) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Revisión")
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { b in
            EditorTexto(titulo: b.asunto ?? Self.tipo(b), texto: b.texto ?? "") { _, t in
                Task {
                    struct C: Encodable { var texto: String }
                    do { try await estado.api.hacer("PATCH", "/v1/revision/\(b.id)", C(texto: t)); await cargar() } catch { estado.avisar(error) }
                }
            }
        }
    }

    static func tipo(_ b: BorradorIA) -> String {
        switch b.tipo {
        case "descripcion": return "Descripción para la ficha"
        case "nota": return "Nota"
        default: return b.canal == "email" ? "Mail" : "Mensaje de WhatsApp"
        }
    }

    static func usar(_ b: BorradorIA) -> String {
        switch b.tipo {
        case "descripcion": return "Ponerla en la ficha"
        case "nota": return "Guardar la nota"
        default: return b.canal == "email" ? "Mandar el mail" : "Mandar por WhatsApp"
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/revision")) ?? lista ?? [] }

    /// Usarlo: lo hace (abre WhatsApp o mail, pega la descripción, guarda la nota) y lo marca usado.
    private func usar(_ b: BorradorIA) async {
        let t = b.texto ?? ""
        do {
            switch b.tipo {
            case "descripcion":
                if let p = b.propiedadId {
                    struct C: Encodable { var descripcion: String }
                    try await estado.api.hacer("PATCH", "/v1/propiedades/\(p)", C(descripcion: t))
                }
            case "nota":
                if let c = b.contactoId {
                    struct N: Encodable { var tipo = "nota"; var texto: String }
                    try await estado.api.hacer("POST", "/v1/contactos/\(c)/notas", N(texto: t))
                }
            default:
                struct Ct: Decodable { var telefono: String?; var email: String? }
                let c: Ct? = b.contactoId == nil ? nil : try? await estado.api.get("/v1/contactos/\(b.contactoId!)")
                if b.canal == "email" {
                    var u = URLComponents(string: "mailto:\(c?.email ?? "")")!
                    u.queryItems = [.init(name: "subject", value: b.asunto ?? ""), .init(name: "body", value: t)]
                    if let x = u.url { await UIApplication.shared.open(x) }
                } else {
                    Afuera.whatsapp(c?.telefono, texto: t)
                }
            }
            try await estado.api.hacer("POST", "/v1/revision/\(b.id)/usado")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func descartar(_ b: BorradorIA) async {
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            try? await estado.api.hacer("DELETE", "/v1/revision/\(b.id)")
            estado.version += 1
        }
        lista?.removeAll { $0.id == b.id }
        estado.avisar("Descartado") { tarea.cancel(); Task { await cargar() } }
    }
}

// MARK: - Importar la cartera

struct ImportacionAPI: Codable {
    struct Nota: Codable, Hashable { var campo: String?; var mensaje: String }
    struct Fila: Codable, Hashable { var fila: Int; var datos: [String: JSONLibre]?; var errores: [Nota]?; var avisos: [Nota]? }
    struct Resultado: Codable { var creadas: Int?; var yaEstaban: Int?; var conErrores: Int? }
    var id: String
    var tipo: String?
    var archivo: String?
    var estado: String?
    var columnas: [String]?
    var total: Int?
    var validas: Int?
    var conErrores: Int?
    var conAvisos: Int?
    var filas: [Fila]?
    var resultado: Resultado?
}

/// Traer la cartera de otro sistema: un Excel o CSV de propiedades o contactos. Primero la vista
/// previa (cuántas entran, avisos y errores por fila); después se traen, sin publicar.
struct Importar: View {
    @Environment(Estado.self) private var estado
    @State private var tipo = "propiedades"
    @State private var eligiendo = false
    @State private var subiendo = false
    @State private var imp: ImportacionAPI?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = imp?.resultado {
                    EstadoVacio(icono: "checkmark.circle", titulo: "Listo: \(Formato.cantidad(r.creadas ?? 0, tipo == "contactos" ? "contacto nuevo" : "propiedad nueva", tipo == "contactos" ? "contactos nuevos" : "propiedades nuevas"))",
                                texto: [(r.yaEstaban ?? 0) > 0 ? "\(r.yaEstaban!) ya estaban" : nil, (r.conErrores ?? 0) > 0 ? "\(r.conErrores!) con errores quedaron afuera" : nil].compactMap { $0 }.joined(separator: " · ").nonEmpty,
                                accion: ("Ver la cartera", { estado.pestana = tipo == "contactos" ? .inicio : .propiedades; if tipo == "contactos" { estado.abrir(AContactos()) } }))
                        .padding(.top, 30)
                } else if let i = imp {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Entran", valor: "\(i.validas ?? 0)")
                        Cifra(etiqueta: "Con avisos", valor: "\(i.conAvisos ?? 0)")
                        Cifra(etiqueta: "Con errores", valor: "\(i.conErrores ?? 0)")
                    }
                    if let c = i.columnas, !c.isEmpty {
                        Text("Reconocimos: \(c.joined(separator: ", "))").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array((i.filas ?? []).filter { !($0.errores ?? []).isEmpty || !($0.avisos ?? []).isEmpty }.prefix(60).enumerated()), id: \.offset) { n, f in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Fila \(f.fila) · \(ListaGenerica.titulo(.objeto(f.datos ?? [:])))").estilo(.filaLista).foregroundStyle(C.texto)
                                ForEach(f.errores ?? [], id: \.self) { e in Label(e.mensaje, systemImage: "xmark.circle").estilo(.footnote).foregroundStyle(C.errorTinta) }
                                ForEach(f.avisos ?? [], id: \.self) { e in Label(e.mensaje, systemImage: "exclamationmark.triangle").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { if n > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                    Button("Traer \(Formato.cantidad(i.validas ?? 0, tipo == "contactos" ? "contacto" : "propiedad", tipo == "contactos" ? "contactos" : "propiedades"))") { Task { await confirmar(i) } }
                        .buttonStyle(BotonPrincipal()).disabled((i.validas ?? 0) == 0 || subiendo)
                    Button("Elegir otro archivo") { imp = nil; eligiendo = true }.buttonStyle(BotonTexto())
                } else {
                    Segmentado(opciones: [("propiedades", "Propiedades"), ("contactos", "Contactos")], elegido: $tipo)
                    EstadoVacio(icono: "tablecells", titulo: "Traé tu cartera", texto: "Un Excel o un CSV de tu sistema anterior. Primero ves cómo queda y después se trae, sin publicar.",
                                accion: (subiendo ? "Leyendo…" : "Elegir el archivo", { eligiendo = true }),
                                secundaria: ("O captá en la calle con MIRA", { estado.miraAbierta = true }))
                        .padding(.top, 20)
                }
            }
            .padding(16)
        }
        .pantallaApilada("Importar")
        .fileImporter(isPresented: $eligiendo, allowedContentTypes: [.commaSeparatedText, .spreadsheet, .data]) { r in
            if case .success(let u) = r { Task { await subir(u) } }
        }
    }

    private func subir(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u) else { return }
        subiendo = true
        defer { subiendo = false }
        do {
            let r = try await estado.api.multipart("/v1/importaciones", query: [.init(name: "tipo", value: tipo)], datos: d, nombre: u.lastPathComponent,
                                                   tipo: u.pathExtension.lowercased() == "csv" ? "text/csv" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            imp = try Api.decodificador.decode(ImportacionAPI.self, from: r)
        } catch { estado.avisar(error) }
    }

    private func confirmar(_ i: ImportacionAPI) async {
        subiendo = true
        defer { subiendo = false }
        do {
            imp = try await estado.api.enviar("POST", "/v1/importaciones/\(i.id)/confirmar", [String: String]())
            estado.version += 1
            Haptico.exito()
        } catch { estado.avisar(error) }
    }
}
