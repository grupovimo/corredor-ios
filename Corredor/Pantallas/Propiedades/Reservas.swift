import SwiftUI

// MARK: - Reservas de venta y alquiler

/// Una reserva (GET /v1/reservas, /v1/reservas/{id}; dominio/reservas.Reserva).
struct ReservaAPI: Codable, Identifiable, Hashable {
    var id: String
    var propiedadId: String
    var contactoId: String?
    var interesadoNombre: String?
    var interesadoTelefono: String?
    var sena: Double?
    var senaMoneda: String?
    var reservadaEl: String?
    var venceEl: String?
    /// Hasta qué hora del día de vencimiento («18:00»).
    var venceHora: String?
    var notas: String?
    var operacionId: String?
    /// activa · concretada · caida
    var estado: String
    var cerradaEl: String?
    var motivoCierre: String?
    var contactoNombre: String?
    var propiedadNumero: Int?
    var propiedadTitulo: String?
    var vencida: Bool?
    var reciboNumero: Int?
    var creadaPor: String?
    var creadoEn: Date?

    var activa: Bool { estado == "activa" }
    var quien: String { contactoNombre ?? interesadoNombre ?? "Sin nombre" }

    /// Días hasta el vencimiento (negativo si ya venció).
    var faltan: Int? { venceEl.flatMap { Fecha.dia($0) }.map { diasCalendario(Date(), $0) } }

    /// «Vence en 3 días», «Venció ayer», «Aceptada», «Se cayó».
    var titular: String {
        if estado == "concretada" { return "Aceptada" }
        if estado == "caida" { return "Se cayó" }
        guard let f = faltan else { return "Sin vencimiento" }
        if f < -1 { return "Venció hace \(-f) días" }
        if f == -1 { return "Venció ayer" }
        if f == 0 { return vencida == true ? "Venció hoy" : "Vence hoy" }
        if f == 1 { return "Vence mañana" }
        return "Vence en \(f) días"
    }

    /// El cuerpo de PUT /v1/reservas/{id} (los datos editables, como datosDe de la web).
    struct Datos: Encodable {
        var contactoId: String?
        var interesadoNombre: String?
        var interesadoTelefono: String?
        var sena: Double?
        var senaMoneda: String
        var reservadaEl: String?
        var venceEl: String?
        var venceHora: String?
        var notas: String?
        var operacionId: String?

        func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: K.self)
            try c.encode(contactoId, forKey: .contactoId)
            try c.encode(interesadoNombre, forKey: .interesadoNombre)
            try c.encode(interesadoTelefono, forKey: .interesadoTelefono)
            try c.encode(sena, forKey: .sena)
            try c.encode(senaMoneda, forKey: .senaMoneda)
            try c.encode(reservadaEl, forKey: .reservadaEl)
            try c.encode(venceEl, forKey: .venceEl)
            try c.encode(venceHora, forKey: .venceHora)
            try c.encode(notas, forKey: .notas)
            try c.encode(operacionId, forKey: .operacionId)
        }
        enum K: String, CodingKey { case contactoId, interesadoNombre, interesadoTelefono, sena, senaMoneda, reservadaEl, venceEl, venceHora, notas, operacionId }
    }

    var datos: Datos {
        Datos(contactoId: contactoId, interesadoNombre: interesadoNombre, interesadoTelefono: interesadoTelefono, sena: sena, senaMoneda: senaMoneda ?? "USD",
              reservadaEl: reservadaEl, venceEl: venceEl, venceHora: venceEl != nil ? venceHora : nil, notas: notas, operacionId: operacionId)
    }

    /// «Ofrece USD 140.000» escrito en las notas (la API no tiene el campo).
    var oferta: (String, Double)? {
        guard let n = notas, let r = n.range(of: #"ofrece\s+(USD|ARS|U\$S|\$)\s*([\d.]+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let t = String(n[r])
        let moneda = t.range(of: "ARS", options: .caseInsensitive) != nil || t.range(of: #"\$\s*\d"#, options: .regularExpression) != nil && t.range(of: "U$S") == nil ? "ARS" : "USD"
        let num = t.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).filter { !$0.isEmpty }.last ?? ""
        guard let v = Double(num.replacingOccurrences(of: ".", with: "")) else { return nil }
        return (moneda, v)
    }

    /// «0001-00471».
    static func recibo(_ n: Int) -> String { String(format: "0001-%05d", n) }

    /// «12/10».
    static func corta(_ dia: String?) -> String {
        guard let d = dia, d.count >= 10 else { return "" }
        return "\(d.dropFirst(8).prefix(2))/\(d.dropFirst(5).prefix(2))"
    }
}

/// Las reservas: las activas primero, cada una con su estado, y «Vencen esta semana» arriba.
struct Reservas: View {
    @Environment(Estado.self) private var estado
    var ruta = "/v1/reservas"
    @State private var lista: [ReservaAPI]?
    @State private var proximas: [ReservaAPI] = []
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let lista {
                    if ruta == "/v1/reservas", !proximas.isEmpty {
                        TituloBloque(texto: "Vencen esta semana", cuenta: "\(proximas.count)")
                        tarjeta(proximas)
                    }
                    if lista.isEmpty {
                        EstadoVacio(icono: "hand.raised", titulo: "No hay reservas",
                                    texto: "Se toman desde la ficha de una propiedad: quién, la seña y hasta cuándo.",
                                    accion: ("Ir a la cartera", { estado.ir(Ruta(.propiedades)) }))
                            .padding(.top, 30)
                    } else {
                        TituloBloque(texto: "Todas", cuenta: "\(lista.count)")
                        tarjeta(lista)
                    }
                } else if let error {
                    EstadoError(que: "las reservas", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Reservas")
        .task(id: estado.version) { await cargar() }
    }

    private func tarjeta(_ rs: [ReservaAPI]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
                Button { estado.abrir(AReserva(id: r.id)) } label: { FilaReserva(r: r) }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
        }
        .tarjeta()
    }

    private func cargar() async {
        do {
            lista = try await estado.api.todas(ruta)
            error = nil
            if ruta == "/v1/reservas" {
                proximas = (try? await estado.api.get("/v1/reservas", query: [.init(name: "estado", value: "activa"), .init(name: "vencen", value: "7")])) ?? []
            }
        } catch let e as ErrorApi { error = e } catch {}
    }
}

/// Una fila de reserva: «Activa · vence 12/11 · seña USD 5.000», «Aceptada», «Se cayó».
struct FilaReserva: View {
    var r: ReservaAPI
    var body: some View {
        let tono: Tono = r.estado == "concretada" ? .verde : r.estado == "caida" ? .neutro : ((r.faltan ?? 9) <= 1 ? .rojo : .oro)
        HStack(spacing: 12) {
            IconoTono(icono: r.estado == "caida" ? "bookmark.slash" : "bookmark", tono: tono, tam: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.propiedadTitulo ?? "Propiedad").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                Text(detalle).estilo(.footnote).foregroundStyle(tono == .rojo ? C.errorTinta : C.texto2).lineLimit(2)
            }
            Spacer()
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58).contentShape(Rectangle())
    }

    private var detalle: String {
        if r.estado == "concretada" { return "\(r.quien) · Aceptada" }
        if r.estado == "caida" { return "\(r.quien) · Se cayó" + (r.motivoCierre.map { " · \($0)" } ?? "") }
        return [r.quien, "Activa", r.venceEl.map { "vence \(ReservaAPI.corta($0))" }, r.sena.map { "seña \(Formato.plata($0, r.senaMoneda ?? "USD"))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// La reserva (handoff 02 · 13E): la cuenta regresiva, la seña, la oferta, el interesado, la línea de
/// tiempo y las tres salidas (Aceptada, Extender 48 h, Se cayó). Aceptada y Se cayó esperan 6 s
/// para deshacer antes de ir a la API (la API no reabre una reserva cerrada).
struct PantallaReserva: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var r: ReservaAPI?
    @State private var prop: Propiedad?
    @State private var propietario: Contacto?
    @State private var telInteresado: String?
    @State private var proximas: [ReservaAPI] = []
    @State private var error: ErrorApi?
    @State private var ocupado = false
    @State private var preguntarSena = false

    private var clase: String { prop?.operacion == "venta" || prop == nil ? "compra" : "alquiler" }
    private var direccion: String { prop?.direccion ?? r?.propiedadTitulo ?? "la propiedad" }

    var body: some View {
        ScrollView {
            if let r {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(r)
                    datos(r)
                    tiempo(r)
                    if r.activa, estado.escribe { salidas(r) } else if !r.activa {
                        Text(Formato.sinViudas("La reserva quedó en el historial de la propiedad. Si vuelve el interesado, cargá una nueva."))
                            .estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    if let prop { propiedad(prop) }
                    if !proximas.filter({ $0.id != r.id }).isEmpty {
                        TituloBloque(texto: "Vencen esta semana")
                        VStack(spacing: 0) {
                            ForEach(Array(proximas.filter { $0.id != r.id }.enumerated()), id: \.element.id) { i, x in
                                Button { estado.abrir(AReserva(id: x.id)) } label: { FilaReserva(r: x) }.buttonStyle(Presionable())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                            }
                        }
                        .tarjeta()
                    }
                }
                .padding(16)
            } else if let error {
                EstadoError(que: "la reserva", error: error) { Task { await cargar() } }.padding(.top, 60)
            } else { EsqueletoFilas(filas: 4).padding(16) }
        }
        .pantallaApilada("Reserva")
        .task(id: estado.version) { await cargar() }
        .confirmationDialog("¿Devolvés la seña?", isPresented: $preguntarSena, titleVisibility: .visible) {
            Button("Sí, la devuelvo") { cerrarCon("caida", "Seña devuelta") }
            Button("No, queda retenida") { cerrarCon("caida", "Seña retenida") }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Seña de \(r?.quien ?? ""): \(r?.sena.map { Formato.plata($0, r?.senaMoneda ?? "USD") } ?? ""). La propiedad vuelve a estar disponible. Lo anotamos en la reserva.")
        }
    }

    private func cabecera(_ r: ReservaAPI) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reserva de \(clase) · \(direccion)", systemImage: r.estado == "caida" ? "bookmark.slash.fill" : "bookmark.fill")
                .estilo(.footnoteFuerte).foregroundStyle(C.texto2).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.titular).estilo(.titulo).foregroundStyle(r.activa && (r.faltan ?? 0) < 0 ? C.errorTinta : C.texto)
                if r.activa, let v = r.venceEl, let f = Fecha.dia(v) {
                    Text(Formato.fechaLarga(f) + (r.venceHora.map { " · \($0)" } ?? "")).estilo(.subhead).foregroundStyle(C.texto2)
                } else if !r.activa, let c = r.cerradaEl {
                    Text("el \(ReservaAPI.corta(c))").estilo(.subhead).foregroundStyle(C.texto2)
                }
            }
            if r.activa, let v = r.venceEl, let d = r.reservadaEl, let fv = Fecha.dia(v), let fd = Fecha.dia(d) {
                let total = max(1, diasCalendario(fd, fv))
                let pasaron = min(total, max(0, diasCalendario(fd, Date())))
                ProgressView(value: Double(pasaron), total: Double(total)).tint(C.oro)
                Text("Pasaron \(pasaron) de \(Formato.cantidad(total, "día", "días"))").estilo(.footnote).foregroundStyle(C.texto2)
            } else if !r.activa, let m = r.motivoCierre {
                Text(m).estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        .padding(16).tarjeta()
    }

    private func datos(_ r: ReservaAPI) -> some View {
        HStack(alignment: .top, spacing: 8) {
            dato("Seña", r.sena.map { Formato.plata($0, r.senaMoneda ?? "USD") } ?? "Sin seña",
                 r.sena != nil ? (r.reservadaEl.map { "recibida \(ReservaAPI.corta($0))" } ?? "") : "de palabra", verde: r.sena != nil)
            if let o = r.oferta {
                dato("Ofrece", Formato.plata(o.1, o.0), prop?.precio.map { "pide \(Formato.plata($0, prop?.moneda ?? "USD"))" } ?? "")
            } else {
                dato("Pide", prop?.precio.map { Formato.plata($0, prop?.moneda ?? "USD") } ?? "Consultar", "sin oferta anotada")
            }
            dato(clase == "compra" ? "Interesada" : "Inquilino", r.quien, r.interesadoTelefono ?? telInteresado ?? "sin teléfono")
        }
    }

    private func dato(_ clave: String, _ valor: String, _ nota: String, verde: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clave).estilo(.footnote).foregroundStyle(C.texto2)
            Text(valor).estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(2).minimumScaleFactor(0.8)
            Text(nota).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(verde ? C.okTinta : C.texto3).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).tarjeta(14)
    }

    private func tiempo(_ r: ReservaAPI) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            paso(hecho: r.sena != nil || !r.activa, ahora: false, r.sena != nil ? "Seña recibida" : "Reserva tomada",
                 r.sena != nil && r.reciboNumero != nil ? "Recibo \(ReservaAPI.recibo(r.reciboNumero!))\(r.reservadaEl.map { " · el \(ReservaAPI.corta($0))" } ?? "")"
                    : r.reservadaEl.map { "el \(ReservaAPI.corta($0))\(r.notas.map { " · \($0)" } ?? "")" })
            paso(hecho: !r.activa, ahora: r.activa, "Respuesta del propietario",
                 r.activa ? (propietario.map { "Esperando a \($0.nombre.components(separatedBy: " ").first ?? $0.nombre)" } ?? "Esperando respuesta")
                    : (r.estado == "concretada" ? "Aceptó la oferta" : "No se concretó"))
            paso(hecho: r.estado == "concretada", ahora: false, clase == "compra" ? "Boleto" : "Contrato", nil)
        }
        .padding(16).tarjeta()
    }

    private func paso(hecho: Bool, ahora: Bool, _ t: String, _ sub: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hecho ? "checkmark.circle.fill" : ahora ? "hourglass.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(hecho ? C.okTinta : ahora ? C.avisoTinta : C.texto3)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).estilo(.subheadFuerte).foregroundStyle(C.texto)
                if let sub { Text(sub).estilo(.footnote).foregroundStyle(ahora ? C.avisoTinta : C.texto2) }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func salidas(_ r: ReservaAPI) -> some View {
        VStack(spacing: 10) {
            if let t = propietario?.telefono, let n = propietario?.nombre {
                Button { Afuera.llamar(t) } label: { Label("Llamar a \(n), el propietario", systemImage: "phone.fill") }.buttonStyle(BotonPrincipal())
            } else if let t = r.interesadoTelefono ?? telInteresado {
                Button { Afuera.llamar(t) } label: { Label("Llamar a \(r.quien)", systemImage: "phone.fill") }.buttonStyle(BotonPrincipal())
            }
            HStack(spacing: 8) {
                Button("Aceptada") { cerrarCon("concretada", nil) }.buttonStyle(BotonHundido()).disabled(ocupado)
                Button(ocupado ? "Extendiendo…" : "Extender 48 h") { Task { await extender(r) } }.buttonStyle(BotonHundido()).disabled(ocupado)
                Button("Se cayó") { if r.sena != nil { preguntarSena = true } else { cerrarCon("caida", nil) } }.buttonStyle(BotonHundido()).disabled(ocupado)
            }
            Text(Formato.sinViudas("«Se cayó» te pregunta si devolvés la seña y deja la propiedad disponible otra vez, con deshacer."))
                .estilo(.footnote).foregroundStyle(C.texto2)
        }
    }

    private func propiedad(_ p: Propiedad) -> some View {
        Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
            HStack(spacing: 12) {
                Foto(url: p.miniatura).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.direccion ?? p.nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    Text([p.titulo, p.precioTexto].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    Text("La ficha de la propiedad").estilo(.footnoteFuerte).foregroundStyle(C.accion)
                }
                Spacer()
                Chevron()
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .tarjeta()
    }

    private func cerrarCon(_ resultado: String, _ motivo: String?) {
        guard let antes = r else { return }
        var nueva = antes
        nueva.estado = resultado
        nueva.cerradaEl = Formato.diaISO(Date())
        nueva.motivoCierre = motivo
        r = nueva
        let hoy = Formato.diaISO(Date())
        let tarea = Task {
            try? await Task.sleep(for: .seconds(6))
            if Task.isCancelled { return }
            struct C: Encodable { var resultado: String; var cerradaEl: String; var motivo: String? }
            do {
                let x: ReservaAPI = try await estado.api.enviar("POST", "/v1/reservas/\(antes.id)/cerrar", C(resultado: resultado, cerradaEl: hoy, motivo: motivo))
                r = x
                estado.version += 1
            } catch {
                r = antes
                estado.avisar(error)
            }
        }
        let texto = resultado == "concretada"
            ? "Reserva aceptada · \(direccion) queda \(clase == "compra" ? "vendida" : "alquilada")"
            : "Se cayó la reserva · \(direccion) vuelve a estar disponible"
        estado.avisar(texto) {
            tarea.cancel()
            r = antes
        }
    }

    private func extender(_ antes: ReservaAPI) async {
        let hoy = Date()
        let base = antes.venceEl.flatMap { Fecha.dia($0) }.map { $0 > hoy ? $0 : hoy } ?? hoy
        let nuevo = Formato.diaISO(Calendar.current.date(byAdding: .day, value: 2, to: base) ?? base)
        var d = antes.datos
        d.venceEl = nuevo
        ocupado = true
        defer { ocupado = false }
        do {
            let g: ReservaAPI = try await estado.api.enviar("PUT", "/v1/reservas/\(antes.id)", d)
            r = g
            estado.avisar("Extendida 48 h · ahora vence el \(Fecha.dia(nuevo).map { Formato.fechaLarga($0) } ?? nuevo)") {
                Task {
                    do {
                        let v: ReservaAPI = try await estado.api.enviar("PUT", "/v1/reservas/\(antes.id)", antes.datos)
                        r = v
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            let x: ReservaAPI = try await estado.api.get("/v1/reservas/\(id)")
            r = x
            error = nil
            prop = try? await estado.api.get("/v1/propiedades/\(x.propiedadId)")
            if let c = x.contactoId { telInteresado = (try? await estado.api.get("/v1/contactos/\(c)") as Contacto)?.telefono }
            if let pid = prop?.propietarioId { propietario = try? await estado.api.get("/v1/contactos/\(pid)") }
            proximas = (try? await estado.api.get("/v1/reservas", query: [.init(name: "estado", value: "activa"), .init(name: "vencen", value: "7")])) ?? []
        } catch let e as ErrorApi { error = e } catch {}
    }
}

/// Reservar una propiedad, un lote o una unidad: quién (nombre libre, no hace falta que sea un
/// contacto), el teléfono, la seña con su moneda y hasta qué día y hora. Queda reservada al toque.
struct NuevaReservaVenta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedadId: String
    var titulo: String
    var moneda = "USD"
    /// Al crearla (la ficha abre la reserva; el emprendimiento avisa con deshacer).
    var alReservar: (ReservaAPI) -> Void = { _ in }
    @State private var nombre = ""
    @State private var telefono = ""
    @State private var sena: Double?
    @State private var senaMoneda = "USD"
    @State private var vence = Date().addingTimeInterval(7 * 86400)
    @State private var hora = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var errores: [String: String] = [:]
    @State private var mandando = false
    @State private var envio = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Quién reserva", text: $nombre).textContentType(.name)
                    if let e = errores["interesadoNombre"] ?? errores["contactoId"] { MensajeError(texto: e) }
                    TextField("Teléfono (opcional)", text: $telefono).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    if let e = errores["interesadoTelefono"] { MensajeError(texto: e) }
                } footer: { Text("Queda reservada al toque y deja de ofrecerse.") }
                Section("Seña") {
                    Picker("Moneda", selection: $senaMoneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("Seña", value: $sena, format: .number).keyboardType(.decimalPad)
                    if let e = errores["sena"] ?? errores["senaMoneda"] { MensajeError(texto: e) }
                }
                Section {
                    DatePicker("Vence el", selection: $vence, displayedComponents: .date)
                    DatePicker("a las", selection: $hora, displayedComponents: .hourAndMinute)
                    if let e = errores["venceEl"] ?? errores["venceHora"] { MensajeError(texto: e) }
                }
            }
            .navigationTitle("Reservar \(titulo)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mandando ? "Reservando…" : "Reservar") { Task { await reservar() } }.fontWeight(.semibold).disabled(mandando)
                }
            }
            .onAppear { senaMoneda = moneda }
        }
    }

    private func reservar() async {
        errores = [:]
        guard nombre.trimmingCharacters(in: .whitespaces).count >= 2 else {
            errores = ["interesadoNombre": "Poné quién reserva. Sin nombre no sabés a quién devolverle la seña."]
            return
        }
        struct C: Encodable { var interesadoNombre: String; var interesadoTelefono: String?; var sena: Double?; var senaMoneda: String; var venceEl: String; var venceHora: String }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        mandando = true
        defer { mandando = false }
        do {
            let r: ReservaAPI = try await estado.api.conCampos("POST", "/v1/propiedades/\(propiedadId)/reservas",
                                                                C(interesadoNombre: nombre.trimmingCharacters(in: .whitespaces), interesadoTelefono: telefono.nonEmpty,
                                                                  sena: sena, senaMoneda: senaMoneda, venceEl: Formato.diaISO(vence), venceHora: f.string(from: hora)),
                                                                envio: envio, como: ReservaAPI.self)
            estado.version += 1
            cerrar()
            alReservar(r)
        } catch let e as ErrorConCampos {
            errores = e.campos
        } catch { estado.avisar(error) }
    }
}
