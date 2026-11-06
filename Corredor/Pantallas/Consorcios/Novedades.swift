import SwiftUI

// MARK: - Libro de novedades

/// Libro de novedades: lo que pasa en el edificio (asambleas, arreglos, avisos), con fecha y quién lo
/// anotó; lo pendiente se marca resuelto al toque (o vuelve a pendiente), con deshacer.
struct PestanaNovedadesConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    @Binding var pedido: String?
    @State private var novedades: [NovedadAPI]?
    @State private var local: [String: String] = [:]
    @State private var error: ErrorApi?
    @State private var escribir = false

    private static let tipo = Dictionary(uniqueKeysWithValues: NovedadAPI.tipos)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let novedades { lista(novedades) } else if let error {
                EstadoError(que: "el libro", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 4) }
        }
        .task(id: estado.version) { await cargar() }
        .onChange(of: pedido, initial: true) { _, p in
            if p == "nueva" { if estado.escribe { escribir = true }; pedido = nil }
        }
        .sheet(isPresented: $escribir) { HojaNovedadConsorcio(c: c) }
    }

    private func estadoDe(_ n: NovedadAPI) -> String { local[n.id] ?? n.estado ?? "abierto" }

    @ViewBuilder private func lista(_ l: [NovedadAPI]) -> some View {
        let pendientes = l.filter { estadoDe($0) != "resuelto" }.count
        HStack {
            Text(pendientes == 0 ? "Nada pendiente" : "\(pendientes) pendiente\(pendientes == 1 ? "" : "s")").estilo(.footnote).foregroundStyle(C.texto2)
            Spacer()
            if estado.escribe { Button { escribir = true } label: { Label("Escribir", systemImage: "pencil") }.font(Estilo.footnoteFuerte.font).buttonStyle(.borderedProminent).tint(C.accion) }
        }
        VStack(spacing: 0) {
            if l.isEmpty { VacioConsorcio(texto: "El libro está vacío. Anotá lo que pasa en el edificio: asambleas, arreglos, avisos a los vecinos.") }
            ForEach(Array(l.enumerated()), id: \.element.id) { i, n in fila(n, primera: i == 0) }
        }
        .tarjeta()
    }

    private func fila(_ n: NovedadAPI, primera: Bool) -> some View {
        let e = estadoDe(n)
        return RenglonConsorcio(primero: primera) {
            VStack(alignment: .leading, spacing: 2) {
                Text([n.ocurrioEl.map { Cons.diaBarraMes($0) }, n.responsable, Self.tipo[n.tipo ?? "otro"]].compactMap { $0 }.joined(separator: " · "))
                    .estilo(.footnote).foregroundStyle(C.texto2)
                Text(n.titulo).estilo(.texto14).foregroundStyle(C.texto)
                if let d = n.descripcion?.nonEmpty { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await marcar(n) } } label: {
                ChipConsorcio(texto: e == "resuelto" ? "Resuelta" : "Pendiente", tono: e == "resuelto" ? .verde : .oro)
            }
            .buttonStyle(Presionable()).disabled(!estado.escribe)
            .accessibilityAddTraits(e == "resuelto" ? .isSelected : [])
        }
    }

    private struct Estado_: Encodable { var estado: String }

    private func marcar(_ n: NovedadAPI) async {
        let antes = estadoDe(n)
        let despues = antes == "resuelto" ? "abierto" : "resuelto"
        local[n.id] = despues
        let ruta = "/v1/consorcios/\(c.id)/novedades/\(n.id)"
        do {
            let _: NovedadAPI = try await estado.api.enviar("PATCH", ruta, Estado_(estado: despues))
            let api = estado.api
            estado.avisar(despues == "resuelto" ? "Marcada como resuelta" : "Volvió a pendiente") {
                local[n.id] = antes
                Task {
                    do { let _: NovedadAPI = try await api.enviar("PATCH", ruta, Estado_(estado: antes)) } catch { estado.avisar(error) }
                    estado.version += 1
                }
            }
        } catch {
            local[n.id] = antes
            estado.avisar(error)
        }
    }

    private func cargar() async {
        do {
            novedades = try await estado.api.get("/v1/consorcios/\(c.id)/novedades", query: [.init(name: "limite", value: "200")])
            local = [:]
            error = nil
        } catch let e as ErrorApi {
            if novedades == nil { error = e }
        } catch {}
    }
}

/// Escribir en el libro: qué pasó, el tipo, la fecha, la firma (quien escribe) y si queda pendiente.
struct HojaNovedadConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var c: ConsorcioAPI
    @State private var titulo = ""
    @State private var tipo = "aviso"
    @State private var fecha = Date()
    @State private var firma = ""
    @State private var pendiente = false
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                CampoConsorcio(etiqueta: "Qué pasó") {
                    TextField("Se aprobó en asamblea cambiar el portón.", text: $titulo, axis: .vertical).lineLimit(3...6)
                }
                if titulo.count > 200 { Text("Hasta 200 letras.").estilo(.footnote).foregroundStyle(C.error) }
                Picker("Es", selection: $tipo) { ForEach(NovedadAPI.tipos, id: \.0) { Text($0.1).tag($0.0) } }
                DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                CampoConsorcio(etiqueta: "Firma") { TextField("", text: $firma) }
                Toggle("Queda pendiente (aparece en las alertas hasta resolverla)", isOn: $pendiente)
            }
            .navigationTitle("Escribir en el libro").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anotar") { Task { await anotar() } }.disabled(titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || titulo.count > 200 || guardando)
                }
            }
        }
        .onAppear { if firma.isEmpty { firma = estado.usuario?.nombre.split(separator: " ").first.map(String.init) ?? "" } }
    }

    private func anotar() async {
        guardando = true
        defer { guardando = false }
        struct N: Encodable { var titulo: String; var descripcion: String?; var tipo: String; var estado: String; var responsable: String?; var ocurrioEl: String }
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(c.id)/novedades",
                                       N(titulo: titulo.trimmingCharacters(in: .whitespacesAndNewlines), descripcion: nil, tipo: tipo, estado: pendiente ? "abierto" : "resuelto",
                                         responsable: String(firma.prefix(80)).nonEmpty, ocurrioEl: Formato.diaISO(fecha)))
            estado.avisar("Anotado en el libro")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

// MARK: - Proveedores del consorcio

/// Proveedores del edificio: primero los que trabajan acá (con lo gastado en el último mes y los
/// trabajos abiertos), después el resto de la inmobiliaria. WhatsApp y mail a un toque.
struct PestanaProveedoresConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    var periodos: [PeriodoAPI]
    @State private var proveedores: [ProveedorConsorcio]?
    @State private var uso: [String: (gastado: Double, trabajos: Int)] = [:]
    @State private var error: ErrorApi?
    @State private var nuevo = false

    private var periodoUso: String? { periodos.first?.periodo }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let proveedores { contenido(proveedores) } else if let error {
                EstadoError(que: "los proveedores", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 4) }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { HojaProveedorConsorcio() }
    }

    @ViewBuilder private func contenido(_ l: [ProveedorConsorcio]) -> some View {
        let ord = l.sorted { a, b in
            let ua = uso[a.id] != nil, ub = uso[b.id] != nil
            return ua != ub ? ua : a.nombre.localizedCompare(b.nombre) == .orderedAscending
        }
        let deAca = ord.filter { uso[$0.id] != nil }
        let otros = ord.filter { uso[$0.id] == nil }
        HStack {
            Text(Cons.plural(l.count, "proveedor", "proveedores")).estilo(.footnote).foregroundStyle(C.texto2)
            Spacer()
            if estado.escribe { Button { nuevo = true } label: { Label("Nuevo proveedor", systemImage: "plus") }.font(Estilo.footnoteFuerte.font).buttonStyle(.bordered) }
        }
        if !deAca.isEmpty {
            BloqueConsorcio(titulo: "Trabajan en este edificio") {
                ForEach(Array(deAca.enumerated()), id: \.element.id) { i, p in fila(p, primera: i == 0) }
            }
        }
        BloqueConsorcio(titulo: deAca.isEmpty ? "Proveedores" : "Los demás") {
            if otros.isEmpty {
                VacioConsorcio(texto: l.isEmpty ? "Cargá a los que trabajan en tus edificios: plomeros, electricistas, el abono del ascensor." : "Todos trabajan en este edificio.")
            }
            ForEach(Array(otros.enumerated()), id: \.element.id) { i, p in fila(p, primera: i == 0) }
        }
    }

    private func detalle(_ id: String) -> String? {
        guard let u = uso[id] else { return nil }
        return [u.gastado > 0 ? periodoUso.map { "\(Formato.plata(u.gastado)) en \(Cons.nombreMes($0))" } : nil,
                u.trabajos > 0 ? Cons.plural(u.trabajos, "trabajo abierto", "trabajos abiertos") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func fila(_ p: ProveedorConsorcio, primera: Bool) -> some View {
        RenglonConsorcio(primero: primera) {
            IconoTono(icono: Cons.iconoRubro(p.rubro), tono: .neutro, tam: 36)
            DosLineasConsorcio(titulo: p.nombre, detalle: [p.rubro, detalle(p.id)?.nonEmpty ?? p.telefono ?? p.email].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Sin datos de contacto")
            if let m = p.email?.nonEmpty, let u = URL(string: "mailto:\(m)") {
                Link(destination: u) { Image(systemName: "envelope").frame(width: 36, height: 36) }.accessibilityLabel("Mandarle un mail a \(p.nombre)")
            }
            if let t = p.telefono?.nonEmpty {
                Button { Afuera.whatsapp(t, texto: "Hola, te escribo de la administración del \(c.nombre).") } label: {
                    Image("LogoWhatsApp").resizable().frame(width: 22, height: 22).frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless).accessibilityLabel("Escribirle a \(p.nombre) por WhatsApp")
            }
        }
    }

    private func cargar() async {
        let b = "/v1/consorcios/\(c.id)"
        do {
            let l = try await ProveedoresConsorcio.todos(estado.api)
            let trabajos: [TrabajoAPI] = (try? await estado.api.get("\(b)/trabajos", query: [.init(name: "limite", value: "200")])) ?? []
            var u: [String: (gastado: Double, trabajos: Int)] = [:]
            if let ultimo = periodos.first, let f: PeriodoAPI = try? await estado.api.get("\(b)/periodos/\(ultimo.id)") {
                for g in f.gastos ?? [] { if let p = g.proveedorId { u[p, default: (0, 0)].gastado += g.monto } }
            }
            for t in trabajos where t.estado != "hecho" && t.estado != "cancelado" { if let p = t.proveedorId { u[p, default: (0, 0)].trabajos += 1 } }
            uso = u
            proveedores = l
            error = nil
        } catch let e as ErrorApi {
            if proveedores == nil { error = e }
        } catch {}
    }
}

/// Un proveedor nuevo (queda para todos los edificios): nombre, rubro, CUIT, celular y mail.
struct HojaProveedorConsorcio: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var rubro = ""
    @State private var cuit = ""
    @State private var telefono = ""
    @State private var email = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                CampoConsorcio(etiqueta: "Nombre") { TextField("Plomería Rossi", text: $nombre) }
                CampoConsorcio(etiqueta: "Rubro (opcional)") { TextField("Plomería", text: $rubro) }
                CampoConsorcio(etiqueta: "CUIT (opcional)") { TextField("", text: $cuit).keyboardType(.numbersAndPunctuation) }
                CampoConsorcio(etiqueta: "Celular (opcional)") { TextField("", text: $telefono).keyboardType(.phonePad) }
                CampoConsorcio(etiqueta: "Mail (opcional)") { TextField("", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            .navigationTitle("Nuevo proveedor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || guardando) }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        do {
            _ = try await ProveedoresConsorcio.crear(estado.api, .init(nombre: nombre.trimmingCharacters(in: .whitespaces), rubro: rubro.nonEmpty, cuit: cuit.nonEmpty,
                                                                       telefono: telefono.nonEmpty, email: email.nonEmpty))
            estado.avisar("Proveedor cargado")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
