import SwiftUI

/// Cuentas de los objetivos, como la web (lib/crm/objetivos.ts): la raya de dónde debería ir hoy (los
/// días hábiles que pasaron del período) y el estado de cada meta contra esa raya.
enum Ritmo {
    static let metricas: [(clave: String, texto: String)] = [("propiedades_captadas", "Captaciones"), ("visitas_hechas", "Visitas"), ("operaciones_cerradas", "Cierres")]
    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    private static func habil(_ d: Date) -> Bool { let w = Calendar.current.component(.weekday, from: d); return w != 1 && w != 7 }

    /// Días hábiles (lunes a viernes) entre dos fechas (yyyy-MM-dd), inclusive.
    static func habiles(_ desde: String, _ hasta: String) -> Int {
        guard var d = Fecha.dia(desde), let h = Fecha.dia(hasta) else { return 0 }
        var n = 0, vueltas = 0
        while d <= h && vueltas < 800 {
            if habil(d) { n += 1 }
            d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? h.addingTimeInterval(1)
            vueltas += 1
        }
        return n
    }

    /// Qué parte del período tendría que estar hecha hoy (0 a 1) y cuántos días hábiles quedan.
    static func ritmo(_ desde: String, _ hasta: String, hoy: String) -> (esperado: Double, quedan: Int) {
        let total = habiles(desde, hasta)
        guard total > 0 else { return (1, 0) }
        let ayer = Entender.sumar(hoy, -1)
        let pasados = hoy <= desde ? 0 : habiles(desde, ayer < hasta ? ayer : hasta)
        // Hoy cuenta como medio día si es hábil (a la mañana todavía no se espera lo de hoy entero).
        let hoyCuenta: Double = hoy >= desde && hoy <= hasta && (Fecha.dia(hoy).map(habil) ?? false) ? 0.5 : 0
        return (min(1, (Double(pasados) + hoyCuenta) / Double(total)), max(0, total - pasados - (hoyCuenta > 0 ? 1 : 0)))
    }

    /// «cumplido», «adelante», «al día» o «atrás».
    static func estado(_ avance: Double, _ meta: Double, _ esperado: Double) -> String {
        let p = meta > 0 ? avance / meta : 1
        if p >= 1 { return "cumplido" }
        if p + 1e-9 < esperado { return "atrás" }
        return p >= esperado + 0.15 ? "adelante" : "al día"
    }

    /// Cuántas le faltan para ir al día.
    static func faltan(_ avance: Double, _ meta: Double, _ esperado: Double) -> Int { max(0, Int(ceil(meta * esperado - avance - 1e-9))) }
}

/// Una meta de una persona (o del equipo) en una métrica, con su objetivo si lo tiene.
struct MetaFila: Hashable {
    var id: String?
    var metrica: String
    var texto: String
    var avance: Double
    var meta: Double
}

/// Objetivos del mes, como la página del panel (20E y 20C): «Tu noviembre» con la meta que más atrás
/// va, lo que falta para ir al día y qué hacer; el tablero del equipo con la raya del día, la zona de
/// cada uno y «Para ayudar»; la fila «Equipo» y los honorarios; y «Editar metas» para la dueña.
struct Objetivos: View {
    @Environment(Estado.self) private var estado
    @State private var objetivos: [Objetivo]?
    @State private var equipo: [Miembro] = []
    @State private var sugerencias: [Sugerencia] = []
    @State private var ops: [Operacion] = []
    @State private var props: [Propiedad] = []
    @State private var error: ErrorApi?
    @State private var editar = false

    private var hoy: String { Formato.diaISO(Date()) }
    private var desde: String { objetivos?.first?.desde ?? String(hoy.prefix(8)) + "01" }
    private var hasta: String {
        if let h = objetivos?.first?.hasta { return h }
        let cal = Calendar.current
        let ini = Fecha.dia(desde) ?? Date()
        return Formato.diaISO(cal.date(byAdding: DateComponents(month: 1, day: -1), to: ini) ?? ini)
    }
    private var mes: String { Int(desde.dropFirst(5).prefix(2)).map { Ritmo.meses[max(0, min(11, $0 - 1))] } ?? "" }
    private var ritmo: (esperado: Double, quedan: Int) { Ritmo.ritmo(desde, hasta, hoy: hoy) }

    private func fila(_ agente: String?) -> [MetaFila] {
        Ritmo.metricas.map { m in
            if let o = (objetivos ?? []).first(where: { $0.agenteId == agente && $0.metrica == m.clave }) {
                return MetaFila(id: o.id, metrica: m.clave, texto: m.texto, avance: o.avance ?? 0, meta: o.meta ?? 0)
            }
            return MetaFila(id: nil, metrica: m.clave, texto: m.texto, avance: 0, meta: 0)
        }
    }

    private var agentes: [Miembro] {
        equipo.filter { p in (objetivos ?? []).contains { $0.agenteId == p.usuarioId } || p.rol == "agente" }
    }

    /// Los barrios donde tiene más propiedades.
    private func zona(_ id: String) -> String {
        let n = Dictionary(grouping: props.filter { $0.agenteId == id }.compactMap(\.barrio), by: { $0 }).mapValues(\.count)
        let bs = n.sorted { $0.value > $1.value }.map(\.key)
        return bs.count > 1 ? "\(bs[0]) y \(bs[1])" : (bs.first ?? "")
    }

    /// La acción concreta para quien va atrás: su primera sugerencia, una reserva sin seña o las nuevas sin contactar.
    private func ayuda(_ id: String) -> (String, AnyHashable)? {
        if let s = sugerencias.first(where: { $0.agenteId == id }) {
            let d: AnyHashable = s.operacionId.map { AnyHashable(AFichaOperacion(id: $0)) } ?? s.contactoId.map { AnyHashable(AFichaContacto(id: $0)) }
                ?? s.propiedadId.map { AnyHashable(AFichaPropiedad(id: $0)) } ?? AnyHashable(AOperaciones())
            return ([s.destacado, s.motivo].compactMap { $0?.nonEmpty }.joined(separator: ": "), d)
        }
        if let o = ops.first(where: { $0.agenteId == id && $0.etapa == "reserva" && $0.sena == nil }) {
            return ("\(String(o.nombre.split(separator: ",").first ?? "")): reserva sin seña cargada", AFichaOperacion(id: o.id))
        }
        let nuevas = ops.filter { $0.agenteId == id && $0.etapa == "nuevo" }.count
        if nuevas > 0 { return ("\(nuevas == 1 ? "Una operación nueva" : "\(nuevas) operaciones nuevas") sin contactar", AOperaciones()) }
        return nil
    }

    private var honorariosMeta: Objetivo? { (objetivos ?? []).first { $0.agenteId == nil && ($0.metrica == "honorarios_usd" || $0.metrica == "honorarios_ars") } }
    private var honorariosMes: Double {
        let cal = Formato.calendario
        return ops.filter { $0.etapa == "cierre" && ($0.moneda ?? "USD") == "USD" && ($0.actualizadoEn.map { cal.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false) }
            .reduce(0) { $0 + ($1.valor ?? 0) * (($1.honorariosComprador ?? 0) + ($1.honorariosVendedor ?? 0)) / 100 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let objetivos {
                    cabecera
                    if objetivos.isEmpty {
                        EstadoVacio(icono: "flag", titulo: "Todavía no hay metas este mes",
                                    texto: "Poné cuántas captaciones, visitas y cierres esperás de cada uno. El avance se cuenta solo con lo que pasa en Corredor.",
                                    accion: estado.esDuenio ? ("Poner metas", { editar = true }) : nil)
                            .padding(.top, 30)
                    } else {
                        if let yo = estado.usuario?.id, fila(yo).contains(where: { $0.meta > 0 }) { tuMes(yo) }
                        tablero
                    }
                } else if let error {
                    EstadoError(que: "los objetivos", error: error) { Task { await cargar() } }.padding(.top, 30)
                } else { EsqueletoFilas(filas: 4) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Objetivos")
        .toolbar { if estado.esDuenio && objetivos?.isEmpty == false { Button("Editar metas") { editar = true } } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $editar) {
            EditarMetas(desde: desde, hasta: hasta, mes: mes, agentes: agentes, filas: Dictionary(uniqueKeysWithValues: agentes.map { ($0.usuarioId, fila($0.usuarioId)) }),
                        equipo: fila(nil), honorarios: honorariosMeta)
        }
    }

    private var cabecera: some View {
        let mio = estado.usuario.map { fila($0.id).contains { $0.meta > 0 } } ?? false
        return VStack(alignment: .leading, spacing: 2) {
            Text(mio ? "Tu \(mes)" : "Objetivos de \(mes)").estilo(.titulo).foregroundStyle(C.texto)
            Text((ritmo.quedan > 0 ? "Quedan \(Formato.cantidad(ritmo.quedan, "día hábil", "días hábiles"))" : "Último día del período") + " · la raya marca dónde deberían ir hoy")
                .estilo(.subhead).foregroundStyle(C.texto2)
        }
    }

    private func bien(_ m: MetaFila) -> Bool { ["cumplido", "adelante", "al día"].contains(Ritmo.estado(m.avance, m.meta, ritmo.esperado)) }

    private func barra(_ m: MetaFila, alto: CGFloat = 8, sobreVerde: Bool = false) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(sobreVerde ? Color.white.opacity(0.25) : C.hundida)
                Capsule().fill(sobreVerde ? C.oro : (bien(m) ? C.verde700 : C.oro))
                    .frame(width: g.size.width * CGFloat(m.meta > 0 ? min(1, m.avance / m.meta) : 0))
                Rectangle().fill(sobreVerde ? Color.white : C.texto).frame(width: 2, height: alto + 6)
                    .offset(x: g.size.width * CGFloat(ritmo.esperado) - 1)
            }
        }
        .frame(height: alto)
        .accessibilityElement()
        .accessibilityLabel("\(Formato.numero(Int(m.avance))) de \(Formato.numero(Int(m.meta))), \(Ritmo.estado(m.avance, m.meta, ritmo.esperado))")
    }

    /// «Tu noviembre»: la meta que más atrás va, lo que falta y qué hacer; las otras, chicas.
    @ViewBuilder
    private func tuMes(_ yo: String) -> some View {
        let metas = fila(yo).filter { $0.meta > 0 }
        let peor = metas.min { ($0.avance / $0.meta - ritmo.esperado) < ($1.avance / $1.meta - ritmo.esperado) }
        if let peor {
            let e = Ritmo.estado(peor.avance, peor.meta, ritmo.esperado)
            let falta = Ritmo.faltan(peor.avance, peor.meta, ritmo.esperado)
            let a = ayuda(yo)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(peor.texto) · \(e == "atrás" ? "vas atrás" : e)".uppercased()).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.5).foregroundStyle(C.oro)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.numero(Int(peor.avance))).estilo(.montoMeta).foregroundStyle(.white)
                    Text("de \(Formato.numero(Int(peor.meta)))").estilo(.subhead).foregroundStyle(.white.opacity(0.8))
                }
                barra(peor, alto: 10, sobreVerde: true)
                Text((falta > 0 ? "Te falta \(Formato.numero(falta)) para ir al día." : "¡Vas bien!") + (a.map { " \($0.0)." } ?? "")).estilo(.subhead).foregroundStyle(.white)
                if let a { Button("Ver qué hacer") { estado.abrir(a.1) }.buttonStyle(BotonTonal(alto: 44)) }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(C.verde700, in: .rect(cornerRadius: 22, style: .continuous))
            let otras = metas.filter { $0 != peor }
            if !otras.isEmpty {
                HStack(spacing: 10) {
                    ForEach(otras, id: \.metrica) { m in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.texto).estilo(.footnote).foregroundStyle(C.texto2)
                            Text("\(Formato.numero(Int(m.avance))) de \(Formato.numero(Int(m.meta)))").estilo(.headline).foregroundStyle(C.texto)
                            barra(m, alto: 6)
                            Text(Ritmo.estado(m.avance, m.meta, ritmo.esperado)).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(bien(m) ? C.okTinta : C.avisoTinta)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).tarjeta(16)
                    }
                }
            }
        }
    }

    /// El tablero del equipo: una tarjeta por agente con sus tres metas, su zona y «Para ayudar»; y el total.
    private var tablero: some View {
        VStack(alignment: .leading, spacing: 10) {
            TituloBloque(texto: "El equipo")
            ForEach(agentes) { p in
                let metas = fila(p.usuarioId)
                let a = ayuda(p.usuarioId)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        AvatarIniciales(nombre: p.completo, tam: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.completo).estilo(.filaLista).foregroundStyle(C.texto)
                            let z = zona(p.usuarioId)
                            if !z.isEmpty { Text(z).estilo(.footnote).foregroundStyle(C.texto2) }
                        }
                    }
                    ForEach(metas, id: \.metrica) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.texto).estilo(.footnote).foregroundStyle(C.texto2)
                                Spacer()
                                if m.meta > 0 {
                                    Text("\(Formato.numero(Int(m.avance))) de \(Formato.numero(Int(m.meta))) · \(Ritmo.estado(m.avance, m.meta, ritmo.esperado))")
                                        .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(bien(m) ? C.texto : C.avisoTinta)
                                } else {
                                    Text("\(Formato.numero(Int(m.avance))) · sin meta").estilo(.footnote).foregroundStyle(C.texto3)
                                }
                            }
                            if m.meta > 0 { barra(m) }
                        }
                    }
                    if let a {
                        HStack(spacing: 10) {
                            Text(a.0).estilo(.footnote).foregroundStyle(C.avisoTinta).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Ver") { estado.abrir(a.1) }.buttonStyle(BotonTonal())
                        }
                    } else if metas.allSatisfy({ $0.meta == 0 || bien($0) }) {
                        Text("Al día").estilo(.footnote).foregroundStyle(C.okTinta)
                    }
                }
                .padding(14).tarjeta()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Equipo").estilo(.filaLista).foregroundStyle(C.texto)
                ForEach(fila(nil), id: \.metrica) { m in
                    HStack {
                        Text(m.texto).estilo(.footnote).foregroundStyle(C.texto2)
                        Spacer()
                        Text("\(Formato.numero(Int(m.avance)))\(m.meta > 0 ? " de \(Formato.numero(Int(m.meta))) · \(Ritmo.estado(m.avance, m.meta, ritmo.esperado))" : "")")
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                    }
                }
                if let h = honorariosMeta {
                    Text("\(Formato.plata(h.avance ?? 0, h.metrica == "honorarios_ars" ? "ARS" : "USD")) de \(Formato.numero(Int(h.meta ?? 0))) en honorarios").estilo(.footnote).foregroundStyle(C.texto2)
                } else if honorariosMes > 0 {
                    Text("\(Formato.plata(honorariosMes, "USD")) en honorarios").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(C.hundida, in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    private func cargar() async {
        do {
            objetivos = try await estado.api.get("/v1/objetivos", query: [.init(name: "vigentes", value: "si")])
            error = nil
        } catch let e as ErrorApi { if objetivos == nil { error = e }; return } catch { return }
        equipo = (try? await estado.api.get("/v1/equipo")) ?? equipo
        sugerencias = (try? await estado.api.get("/v1/sugerencias")) ?? []
        ops = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "limite", value: "500")])) ?? []
        props = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "200"), .init(name: "orden", value: "actualizada")])) ?? []
    }
}

/// «Metas de noviembre»: la grilla del equipo (cada agente × captaciones, visitas y cierres, la fila
/// Equipo y los honorarios del equipo). Cambiar un número edita la meta; 0 o vacío la borra.
struct EditarMetas: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var desde: String
    var hasta: String
    var mes: String
    var agentes: [Miembro]
    var filas: [String: [MetaFila]]
    var equipo: [MetaFila]
    var honorarios: Objetivo?
    @State private var valores: [String: String] = [:]
    @State private var honorariosValor = ""
    @State private var moneda = "USD"
    @State private var guardando = false

    private func clave(_ agente: String?, _ metrica: String) -> String { "\(agente ?? "equipo"):\(metrica)" }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(agentes) { p in seccion(p.completo, p.usuarioId, filas[p.usuarioId] ?? []) }
                seccion("Equipo", nil, equipo)
                Section("Honorarios del equipo") {
                    Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("—", text: $honorariosValor).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Metas de \(mes)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
        }
        .onAppear {
            var v: [String: String] = [:]
            for p in agentes { for m in filas[p.usuarioId] ?? [] { v[clave(p.usuarioId, m.metrica)] = m.meta > 0 ? Formato.numero(Int(m.meta)) : "" } }
            for m in equipo { v[clave(nil, m.metrica)] = m.meta > 0 ? Formato.numero(Int(m.meta)) : "" }
            valores = v
            honorariosValor = honorarios.flatMap { $0.meta }.map { Formato.numero(Int($0)) } ?? ""
            moneda = honorarios?.metrica == "honorarios_ars" ? "ARS" : "USD"
        }
    }

    private func seccion(_ nombre: String, _ id: String?, _ metas: [MetaFila]) -> some View {
        Section(nombre) {
            ForEach(Ritmo.metricas, id: \.clave) { m in
                HStack {
                    Text(m.texto)
                    Spacer()
                    TextField("—", text: Binding(get: { valores[clave(id, m.clave)] ?? "" }, set: { valores[clave(id, m.clave)] = $0 }))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .accessibilityLabel("\(m.texto) de \(nombre)")
                }
            }
        }
    }

    private struct Cambio { var id: String?; var agenteId: String?; var metrica: String; var meta: Double; var antes: Double }
    private struct Cuerpo: Encodable { var agenteId: String?; var metrica: String; var meta: Double; var desde: String; var hasta: String }

    private func numero(_ s: String) -> Double { Double(s.filter(\.isNumber)) ?? 0 }

    private func guardar() async {
        var cambios: [Cambio] = []
        for p in agentes {
            for m in filas[p.usuarioId] ?? [] { cambios.append(Cambio(id: m.id, agenteId: p.usuarioId, metrica: m.metrica, meta: numero(valores[clave(p.usuarioId, m.metrica)] ?? ""), antes: m.meta)) }
        }
        for m in equipo { cambios.append(Cambio(id: m.id, agenteId: nil, metrica: m.metrica, meta: numero(valores[clave(nil, m.metrica)] ?? ""), antes: m.meta)) }
        // La meta de honorarios en su moneda (cambiar de moneda borra la otra).
        let metrica = moneda == "ARS" ? "honorarios_ars" : "honorarios_usd"
        let n = numero(honorariosValor)
        if let h = honorarios, h.metrica != metrica {
            cambios.append(Cambio(id: h.id, agenteId: nil, metrica: h.metrica ?? "", meta: 0, antes: h.meta ?? 0))
            cambios.append(Cambio(id: nil, agenteId: nil, metrica: metrica, meta: n, antes: 0))
        } else {
            cambios.append(Cambio(id: honorarios?.id, agenteId: nil, metrica: metrica, meta: n, antes: honorarios?.meta ?? 0))
        }
        guardando = true
        defer { guardando = false }
        do {
            for c in cambios where c.meta != c.antes {
                let cuerpo = Cuerpo(agenteId: c.agenteId, metrica: c.metrica, meta: c.meta, desde: desde, hasta: hasta)
                if let id = c.id, c.meta > 0 { try await estado.api.hacer("PUT", "/v1/objetivos/\(id)", cuerpo) }
                else if let id = c.id { try await estado.api.hacer("DELETE", "/v1/objetivos/\(id)") }
                else if c.meta > 0 { try await estado.api.hacer("POST", "/v1/objetivos", cuerpo) }
            }
            estado.avisar("Metas guardadas")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
