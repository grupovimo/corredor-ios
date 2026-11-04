import SwiftUI

// Consorcios: no los dibuja el handoff (decía «quedan en la web»), pero Nahuel los quiere en el
// celular. Se arman con las piezas del handoff: tarjetas de cifras, filas, chips y hojas.

struct ConsorcioAPI: Codable, Identifiable, Hashable {
    struct Metricas: Codable, Hashable {
        var unidades: Int?
        var deudores: Int?
        var saldoAdeudado: Double?
        var novedadesAbiertas: Int?
        var trabajosPendientes: Int?
        var trabajosVencidos: Int?
    }
    var id: String
    var nombre: String
    var direccion: String?
    var cuit: String?
    var cbu: String?
    var diaVencimiento: Int?
    var interesMensual: Double?
    var fotoUrl: String?
    var metricas: Metricas?
}

struct UnidadAPI: Codable, Identifiable, Hashable {
    var id: String
    var etiqueta: String?
    var piso: String?
    var tipo: String?
    var propietario: String?
    var inquilino: String?
    var propietarioEmail: String?
    var propietarioTelefono: String?
    var saldo: Double?
    var nombre: String { etiqueta ?? piso ?? "Unidad" }
}

struct PeriodoAPI: Codable, Identifiable, Hashable {
    struct Gasto: Codable, Identifiable, Hashable { var id: String; var descripcion: String?; var tipo: String?; var monto: Double?; var proveedor: String?; var fecha: String? }
    var id: String
    var periodo: String
    var estado: String?
    var gastosTotal: Double?
    var fondoTotal: Double?
    var total: Double?
    var liquidadoEn: Date?
    var gastos: [Gasto]?
}

struct TrabajoAPI: Codable, Identifiable, Hashable {
    var id: String
    var estado: String?
    var prioridad: String?
    var titulo: String
    var descripcion: String?
    var presupuesto: Double?
    var proveedor: String?
    var proveedorTelefono: String?
    var unidad: String?
    var venceEl: String?
}

struct NovedadAPI: Codable, Identifiable, Hashable {
    var id: String
    var tipo: String?
    var estado: String?
    var titulo: String
    var descripcion: String?
    var ocurrioEl: String?
}

struct DeudorAPI: Codable, Identifiable, Hashable {
    var unidadId: String
    var unidad: String?
    var propietario: String?
    var saldo: Double?
    var dias: Int?
    var interesEstimado: Double?
    var id: String { unidadId }
}

struct EmpleadoAPI: Codable, Identifiable, Hashable { var id: String; var nombre: String; var categoria: String?; var basico: Double? }
struct ReciboSueldoAPI: Codable, Identifiable, Hashable { var id: String; var empleado: String?; var periodo: String? }

/// La lista de consorcios con sus números (unidades, deuda, novedades, trabajos vencidos).
struct Consorcios: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [ConsorcioAPI]?
    @State private var alertas: [JSONLibre] = []
    @State private var nuevo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty {
                        EstadoVacio(icono: "building.columns", titulo: "Todavía no administrás consorcios", texto: "Cargá el edificio, sus unidades y liquidá las expensas desde acá.",
                                    accion: estado.esDuenio ? ("Cargar consorcio", { nuevo = true }) : nil).padding(.top, 40)
                    }
                    ForEach(alertas.prefix(3).indices, id: \.self) { i in
                        let a = alertas[i]
                        Label(a["texto"]?.texto ?? "", systemImage: "exclamationmark.triangle").estilo(.subhead).foregroundStyle(C.avisoTinta)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(C.avisoFondo, in: .rect(cornerRadius: 14))
                    }
                    ForEach(lista) { c in
                        NavigationLink(value: ASeccion(clave: "consorcio", id: c.id)) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Foto(url: c.fotoUrl.flatMap(URL.init(string:))).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                        Text(c.direccion ?? "").estilo(.footnote).foregroundStyle(C.texto2)
                                    }
                                    Spacer()
                                    Chevron()
                                }
                                HStack(spacing: 8) {
                                    chip("\(c.metricas?.unidades ?? 0) unidades", .neutro)
                                    if let d = c.metricas?.deudores, d > 0 { chip("\(d) deben", .rojo) }
                                    if let n = c.metricas?.novedadesAbiertas, n > 0 { chip("\(n) novedades", .oro) }
                                    if let t = c.metricas?.trabajosVencidos, t > 0 { chip("\(t) trabajos vencidos", .rojo) }
                                }
                            }
                            .padding(12).tarjeta()
                        }
                        .buttonStyle(.plain)
                    }
                } else { EsqueletoFilas(filas: 4, miniatura: 56) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Consorcios")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.esDuenio { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Consorcio nuevo") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { EditarConsorcio(c: nil) }
    }

    private func chip(_ t: String, _ tono: Tono) -> some View {
        Text(t).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
            .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
    }

    private func cargar() async {
        lista = (try? await estado.api.get("/v1/consorcios")) ?? lista ?? []
        if case .lista(let l)? = try? await estado.api.get("/v1/consorcios/alertas") as JSONLibre { alertas = l }
    }
}

/// Alta o edición de un consorcio.
struct EditarConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI?
    @State private var x = ConsorcioAPI(id: "", nombre: "")

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $x.nombre)
                TextField("Dirección", text: Binding(get: { x.direccion ?? "" }, set: { x.direccion = $0 }))
                TextField("CUIT", text: Binding(get: { x.cuit ?? "" }, set: { x.cuit = $0 })).keyboardType(.numbersAndPunctuation)
                TextField("CBU o alias para las expensas", text: Binding(get: { x.cbu ?? "" }, set: { x.cbu = $0 }))
                Stepper("Vence el \(x.diaVencimiento ?? 10)", value: Binding(get: { x.diaVencimiento ?? 10 }, set: { x.diaVencimiento = $0 }), in: 1...28)
                TextField("Interés mensual %", value: $x.interesMensual, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle(c == nil ? "Consorcio nuevo" : "Editar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            struct Cuerpo: Encodable { var nombre: String; var direccion: String?; var cuit: String?; var cbu: String?; var diaVencimiento: Int?; var interesMensual: Double? }
                            let b = Cuerpo(nombre: x.nombre, direccion: x.direccion?.nonEmpty, cuit: x.cuit?.nonEmpty, cbu: x.cbu?.nonEmpty, diaVencimiento: x.diaVencimiento, interesMensual: x.interesMensual)
                            do {
                                if let c { try await estado.api.hacer("PUT", "/v1/consorcios/\(c.id)", b) } else { try await estado.api.hacer("POST", "/v1/consorcios", b) }
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                    .disabled(x.nombre.isEmpty)
                }
            }
        }
        .onAppear { if let c { x = c } }
    }
}

/// Un consorcio: las cifras arriba y sus partes (unidades, expensas, deudores, trabajos, novedades, personal).
struct FichaConsorcio: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var c: ConsorcioAPI?
    @State private var parte = "unidades"
    @State private var unidades: [UnidadAPI] = []
    @State private var periodos: [PeriodoAPI] = []
    @State private var deudores: [DeudorAPI] = []
    @State private var trabajos: [TrabajoAPI] = []
    @State private var novedades: [NovedadAPI] = []
    @State private var empleados: [EmpleadoAPI] = []
    @State private var recibos: [ReciboSueldoAPI] = []
    @State private var editando = false
    @State private var nuevo: String?
    @State private var texto = ""
    @State private var monto: Double?
    @State private var pagando: UnidadAPI?

    private static let partes = [("unidades", "Unidades"), ("expensas", "Expensas"), ("deudores", "Deudores"), ("trabajos", "Trabajos"), ("novedades", "Novedades"), ("personal", "Personal")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Unidades", valor: "\(c.metricas?.unidades ?? unidades.count)")
                        Cifra(etiqueta: "Deuda", valor: Formato.plataCorta(c.metricas?.saldoAdeudado ?? 0))
                        Cifra(etiqueta: "Pendientes", valor: "\((c.metricas?.trabajosPendientes ?? 0) + (c.metricas?.novedadesAbiertas ?? 0))")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(Self.partes, id: \.0) { k, n in ChipFiltro(texto: n, activo: parte == k) { parte = k } } }
                }
                contenido
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada(c?.nombre ?? "Consorcio")
        .toolbar {
            if estado.escribe {
                Menu {
                    Button { nuevo = "unidad" } label: { Label("Sumar unidad", systemImage: "door.left.hand.open") }
                    Button { nuevo = "periodo" } label: { Label("Abrir período de expensas", systemImage: "calendar.badge.plus") }
                    Button { nuevo = "trabajo" } label: { Label("Nuevo trabajo", systemImage: "wrench.and.screwdriver") }
                    Button { nuevo = "novedad" } label: { Label("Nueva novedad", systemImage: "exclamationmark.bubble") }
                    Button { nuevo = "empleado" } label: { Label("Sumar personal", systemImage: "person.badge.plus") }
                    if estado.esDuenio { Button { editando = true } label: { Label("Editar el consorcio", systemImage: "pencil") } }
                } label: { Image(systemName: "plus") }
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editando) { EditarConsorcio(c: c) }
        .alert(Self.tituloNuevo(nuevo), isPresented: Binding(get: { nuevo != nil }, set: { if !$0 { nuevo = nil } })) {
            TextField(nuevo == "periodo" ? "2026-11" : "Nombre o título", text: $texto)
            Button("Cancelar", role: .cancel) { texto = "" }
            Button("Sumar") { Task { await crear() } }
        }
        .alert("Registrar pago", isPresented: Binding(get: { pagando != nil }, set: { if !$0 { pagando = nil } })) {
            TextField("Monto", value: $monto, format: .number).keyboardType(.decimalPad)
            Button("Cancelar", role: .cancel) {}
            Button("Registrar") { if let u = pagando { Task { await pagar(u) } } }
        } message: { Text(pagando.map { "\($0.nombre) · debe \(Formato.plata(max(0, $0.saldo ?? 0)))" } ?? "") }
    }

    @ViewBuilder
    private var contenido: some View {
        switch parte {
        case "unidades":
            lista(unidades.map { u in
                Fila(id: u.id, titulo: u.nombre, detalle: [u.propietario, u.inquilino.map { "Inq. \($0)" }].compactMap { $0 }.joined(separator: " · "),
                     derecha: Formato.plata(u.saldo ?? 0), tono: (u.saldo ?? 0) > 0 ? .rojo : .verde,
                     acciones: [("Registrar pago", { monto = u.saldo; pagando = u }), ("Mandar link de la cuenta", { Task { await link("/v1/consorcios/\(id)/unidades/\(u.id)/link", u.propietarioTelefono) } }),
                                ("WhatsApp", { Afuera.whatsapp(u.propietarioTelefono) })])
            }, vacio: "Sumá las unidades del edificio.")
        case "expensas":
            VStack(spacing: 10) {
                ForEach(periodos) { p in TarjetaPeriodo(consorcio: id, p: p) }
                if periodos.isEmpty { EstadoVacio(icono: "calendar", titulo: "Sin períodos", texto: "Abrí el período del mes, cargá los gastos y liquidá.") }
            }
        case "deudores":
            lista(deudores.map { d in
                Fila(id: d.id, titulo: d.unidad ?? "Unidad", detalle: [d.propietario, d.dias.map { "hace \($0) días" }].compactMap { $0 }.joined(separator: " · "),
                     derecha: Formato.plata(d.saldo ?? 0), tono: .rojo, acciones: [("Mandar link de la cuenta", { Task { await link("/v1/consorcios/\(id)/unidades/\(d.unidadId)/link", nil) } })])
            }, vacio: "Nadie debe expensas.")
        case "trabajos":
            lista(trabajos.map { t in
                Fila(id: t.id, titulo: t.titulo, detalle: [t.proveedor, t.unidad, t.venceEl.map { "vence \($0)" }].compactMap { $0 }.joined(separator: " · "),
                     derecha: Self.estadoTexto(t.estado), tono: t.estado == "hecho" ? .verde : (t.prioridad == "alta" ? .rojo : .oro),
                     acciones: [("Marcar hecho", { Task { await estadoTrabajo(t, "hecho") } }), ("En curso", { Task { await estadoTrabajo(t, "en_curso") } }),
                                ("WhatsApp al proveedor", { Afuera.whatsapp(t.proveedorTelefono) })])
            }, vacio: "No hay trabajos pendientes.")
        case "novedades":
            lista(novedades.map { n in
                Fila(id: n.id, titulo: n.titulo, detalle: n.descripcion ?? "", derecha: Self.estadoTexto(n.estado), tono: n.estado == "resuelta" ? .verde : .oro,
                     acciones: [("Marcar resuelta", { Task { await estadoNovedad(n, "resuelta") } })])
            }, vacio: "Sin novedades.")
        default:
            VStack(alignment: .leading, spacing: 12) {
                lista(empleados.map { e in
                    Fila(id: e.id, titulo: e.nombre, detalle: e.categoria ?? "", derecha: e.basico.map { Formato.plata($0) } ?? "", tono: .neutro,
                         acciones: [("Hacer el recibo del mes", { Task { await reciboSueldo(e) } })])
                }, vacio: "Sumá al encargado o al personal.")
                if !recibos.isEmpty {
                    TituloBloque(texto: "Recibos de sueldo")
                    lista(recibos.map { r in
                        Fila(id: r.id, titulo: r.empleado ?? "Recibo", detalle: r.periodo ?? "", derecha: "", tono: .neutro,
                             acciones: [("Mandar link", { Task { await link("/v1/consorcios/\(id)/sueldos/\(r.id)/link", nil) } })])
                    }, vacio: "")
                }
                Link("Formulario 931 del mes", destination: Api.web().appendingPathComponent("consorcios/\(id)/f931")).font(Estilo.subheadFuerte.font)
            }
        }
    }

    struct Fila: Identifiable {
        var id: String
        var titulo: String
        var detalle: String
        var derecha: String
        var tono: Tono
        var acciones: [(String, () -> Void)]
    }

    private func lista(_ filas: [Fila], vacio: String) -> some View {
        VStack(spacing: 0) {
            if filas.isEmpty && !vacio.isEmpty { Text(vacio).estilo(.texto14).foregroundStyle(C.texto3).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(Array(filas.enumerated()), id: \.element.id) { i, f in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                        if !f.detalle.isEmpty { Text(f.detalle).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2) }
                    }
                    Spacer()
                    if !f.derecha.isEmpty {
                        Text(f.derecha).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(f.tono.tinta)
                            .padding(.horizontal, 9).frame(height: 26).background(f.tono.fondo, in: Capsule())
                    }
                    if estado.escribe && !f.acciones.isEmpty {
                        Menu { ForEach(f.acciones, id: \.0) { t, h in Button(t, action: h) } } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36).foregroundStyle(C.texto2) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
        }
        .tarjeta()
    }

    static func estadoTexto(_ e: String?) -> String {
        ["pendiente": "Pendiente", "en_curso": "En curso", "hecho": "Hecho", "abierta": "Abierta", "resuelta": "Resuelta", "presupuestado": "Presupuestado"][e ?? ""] ?? (e?.capitalized ?? "")
    }

    static func tituloNuevo(_ t: String?) -> String {
        ["unidad": "Unidad nueva", "periodo": "Período nuevo (AAAA-MM)", "trabajo": "Trabajo nuevo", "novedad": "Novedad", "empleado": "Personal nuevo"][t ?? ""] ?? ""
    }

    private func cargar() async {
        let b = "/v1/consorcios/\(id)"
        c = try? await estado.api.get(b)
        unidades = (try? await estado.api.get("\(b)/unidades")) ?? []
        periodos = ((try? await estado.api.get("\(b)/periodos")) ?? [PeriodoAPI]()).sorted { $0.periodo > $1.periodo }
        deudores = (try? await estado.api.get("\(b)/deudores")) ?? []
        trabajos = (try? await estado.api.get("\(b)/trabajos")) ?? []
        novedades = (try? await estado.api.get("\(b)/novedades")) ?? []
        empleados = (try? await estado.api.get("\(b)/empleados")) ?? []
        recibos = (try? await estado.api.get("\(b)/sueldos")) ?? []
    }

    private func crear() async {
        let t = texto.trimmingCharacters(in: .whitespaces)
        texto = ""
        guard !t.isEmpty, let que = nuevo else { return }
        let b = "/v1/consorcios/\(id)"
        do {
            switch que {
            case "unidad":
                struct U: Encodable { var etiqueta: String; var tipo = "departamento" }
                try await estado.api.hacer("POST", "\(b)/unidades", U(etiqueta: t))
            case "periodo":
                struct P: Encodable { var periodo: String }
                try await estado.api.hacer("POST", "\(b)/periodos", P(periodo: t))
            case "trabajo":
                struct T: Encodable { var titulo: String; var estado = "pendiente"; var prioridad = "media" }
                try await estado.api.hacer("POST", "\(b)/trabajos", T(titulo: t))
            case "novedad":
                struct N: Encodable { var titulo: String; var tipo = "reclamo"; var estado = "abierta"; var ocurrioEl: String }
                try await estado.api.hacer("POST", "\(b)/novedades", N(titulo: t, ocurrioEl: Formato.diaISO(Date())))
            default:
                struct E: Encodable { var nombre: String }
                try await estado.api.hacer("POST", "\(b)/empleados", E(nombre: t))
            }
            await cargar()
        } catch { estado.avisar(error) }
        nuevo = nil
    }

    private func pagar(_ u: UnidadAPI) async {
        struct M: Encodable { var tipo = "pago"; var monto: Double; var fecha: String; var notas: String? }
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(id)/unidades/\(u.id)/movimientos", M(monto: monto ?? 0, fecha: Formato.diaISO(Date())))
            Haptico.exito()
            estado.avisar("Pago registrado en \(u.nombre)")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func link(_ ruta: String, _ telefono: String?) async {
        struct L: Decodable { var url: String }
        do {
            let l: L = try await estado.api.enviar("POST", ruta, [String: String]())
            Afuera.whatsapp(telefono, texto: l.url)
        } catch { estado.avisar(error) }
    }

    private func estadoTrabajo(_ t: TrabajoAPI, _ e: String) async {
        struct C: Encodable { var estado: String; var hechoEl: String? }
        try? await estado.api.hacer("PATCH", "/v1/consorcios/\(id)/trabajos/\(t.id)", C(estado: e, hechoEl: e == "hecho" ? Formato.diaISO(Date()) : nil))
        await cargar()
    }

    private func estadoNovedad(_ n: NovedadAPI, _ e: String) async {
        struct C: Encodable { var estado: String; var resueltoEl: String? }
        try? await estado.api.hacer("PATCH", "/v1/consorcios/\(id)/novedades/\(n.id)", C(estado: e, resueltoEl: Formato.diaISO(Date())))
        await cargar()
    }

    private func reciboSueldo(_ e: EmpleadoAPI) async {
        struct R: Encodable { var empleadoId: String; var periodo: String }
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(id)/sueldos", R(empleadoId: e.id, periodo: String(Formato.diaISO(Date()).prefix(7))))
            estado.avisar("Recibo de \(e.nombre) listo")
            await cargar()
        } catch { estado.avisar(error) }
    }
}

/// Un período de expensas: total, gastos (sumar con su monto), liquidar, mandar a los propietarios y cerrar.
struct TarjetaPeriodo: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    var p: PeriodoAPI
    @State private var abierto = false
    @State private var detalle: PeriodoAPI?
    @State private var gasto = ""
    @State private var monto: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { abierto.toggle(); if abierto { Task { await cargar() } } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formato.mayuscula(ReciboVista.mes(p.periodo))).estilo(.filaLista).foregroundStyle(C.texto)
                        Text(FichaConsorcio.estadoTexto(p.estado)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer()
                    Text(Formato.plata(p.total ?? p.gastosTotal ?? 0)).fontWeight(.semibold).foregroundStyle(C.texto)
                    Image(systemName: abierto ? "chevron.up" : "chevron.down").foregroundStyle(C.texto3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if abierto {
                ForEach(detalle?.gastos ?? []) { g in
                    HStack { Text(g.descripcion ?? g.proveedor ?? "Gasto").estilo(.texto14); Spacer(); Text(Formato.plata(g.monto ?? 0)).estilo(.texto14) }
                        .swipeActions { Button("Sacar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/consorcios/\(consorcio)/periodos/\(p.id)/gastos/\(g.id)"); await cargar() } } }
                }
                if p.estado != "cerrado" && estado.escribe {
                    HStack {
                        TextField("Gasto (limpieza, luz…)", text: $gasto).estilo(.texto14)
                        TextField("Monto", value: $monto, format: .number).keyboardType(.decimalPad).frame(width: 90).estilo(.texto14)
                        Button { Task { await sumar() } } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(C.accion) }.disabled(gasto.isEmpty || monto == nil)
                    }
                    HStack(spacing: 8) {
                        Button("Liquidar") { Task { await accion("liquidar", "Expensas liquidadas") } }.buttonStyle(BotonAccion())
                        Button("Mandar") { Task { await accion("enviar", "Expensas mandadas a los propietarios") } }.buttonStyle(BotonHundido())
                        Button("Cerrar") { Task { await accion("cerrar", "Período cerrado") } }.buttonStyle(BotonHundido())
                    }
                }
                Link("Ver la liquidación para imprimir", destination: Api.web().appendingPathComponent("consorcios/\(consorcio)/imprimir/expensas/\(p.id)")).font(Estilo.footnoteFuerte.font)
            }
        }
        .padding(14).tarjeta()
    }

    private func cargar() async { detalle = try? await estado.api.get("/v1/consorcios/\(consorcio)/periodos/\(p.id)") }

    private func sumar() async {
        struct G: Encodable { var descripcion: String; var monto: Double; var tipo = "ordinario"; var fecha: String }
        try? await estado.api.hacer("POST", "/v1/consorcios/\(consorcio)/periodos/\(p.id)/gastos", G(descripcion: gasto, monto: monto ?? 0, fecha: Formato.diaISO(Date())))
        gasto = ""
        monto = nil
        await cargar()
    }

    private func accion(_ a: String, _ ok: String) async {
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(consorcio)/periodos/\(p.id)/\(a)")
            estado.avisar(ok)
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}
