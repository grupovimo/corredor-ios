import Charts
import SwiftUI

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
                    if l.isEmpty { EstadoVacio(icono: "megaphone", titulo: "Nada acá", texto: "Publicás desde la ficha de cada propiedad.").padding(.top, 30) }
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
                                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion) }
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
            if let lista {
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
        .navigationTitle("Actividad")
        .refreshable { await cargar() }
        .task { await cargar() }
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
        .navigationTitle("Tarifas")
        .toolbar { if estado.escribe { Button { editando = TarifaAPI(id: "", desde: Formato.diaISO(Date()), hasta: Formato.diaISO(Date().addingTimeInterval(30 * 86400)), precio: 0, moneda: "USD", periodo: "noche") } label: { Image(systemName: "plus") } } }
        .task { await cargar() }
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
                    HStack { Text(u).font(.footnote.monospaced()); Spacer(); Button { UIPasteboard.general.string = u; estado.avisar("Link copiado") } label: { Image(systemName: "doc.on.doc") } }
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
        .navigationTitle("Corredor en tu IA")
        .task { await cargar() }
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
            estado.avisar("WhatsApp conectado")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
