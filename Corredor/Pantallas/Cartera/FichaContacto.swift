import SwiftUI

/// Un renglón de «Todo con Valeria» (web: lib/crm/linea.ts).
struct ItemLinea: Identifiable, Hashable {
    enum Grupo: String, Hashable { case mensajes, visitas, notas, otros }
    var id: String
    var grupo: Grupo
    var en: Date
    var icono: String
    var tono: Tono
    var titulo: String
    var detalle: String?
    var burbuja: String?
    var mio = false
    /// Las notas van entre comillas.
    var cita = false

    /// Hoy, Ayer, Esta semana, Semana pasada, Antes (y lo que viene, arriba: Próximo).
    static func grupoDeFecha(_ en: Date, ahora: Date = Date()) -> String {
        let cal = Formato.calendario
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: en), to: cal.startOfDay(for: ahora)).day ?? 0
        if d < 0 { return "Próximo" }
        if d == 0 { return "Hoy" }
        if d == 1 { return "Ayer" }
        let dow = (cal.component(.weekday, from: ahora) + 5) % 7
        if d <= dow { return "Esta semana" }
        if d <= dow + 7 { return "Semana pasada" }
        return "Antes"
    }
}

/// 8B Ficha de un contacto, como la del panel (17C): WhatsApp, llamar y agendar a un toque; «¿Cómo le
/// fue?» después de una visita; qué busca; lo que le puede interesar con su estado y «Mandar»; los
/// datos; y «Todo con Valeria» (mensajes, visitas, operaciones —también las caídas—, notas y por dónde
/// llegó) con el filtro, la nota escrita o dictada y «Guardar y agendar».
struct FichaContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State private var c: Contacto?
    @State private var error: ErrorApi?
    @State private var props: [PropiedadDeContacto] = []
    @State private var linea: [ItemLinea] = []
    @State private var visitaReciente: Cita?
    @State private var equipo: [Miembro] = []
    @State private var vista: ItemLinea.Grupo?
    @State private var nota = ""
    @State private var guardando = false
    @State private var contando = false
    @State private var editando: String?
    @State private var agendar: AgendarDesdeFicha?
    @State private var nuevaOp = false
    @State private var dictado = Dictado()
    @State private var base = ""
    @State private var dictandoDesde: Date?

    struct AgendarDesdeFicha: Identifiable { var dia: Date; var hora: String?; var id: String { "\(dia.timeIntervalSince1970)\(hora ?? "")" } }

    private static let vistas: [(ItemLinea.Grupo?, String)] = [(nil, "Todo"), (.mensajes, "Mensajes"), (.visitas, "Visitas"), (.notas, "Notas")]
    private var primer: String { Charla.primerNombre(c?.nombre) }
    private var yo: String { estado.usuario?.id ?? "" }
    private var nombres: [String: String] { Dictionary(equipo.map { ($0.usuarioId, $0.completo) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        ScrollView {
            if let c {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(c)
                    acciones(c)
                    if let v = visitaReciente, estado.escribe { comoFue(v) }
                    tarjetaBusca(c)
                    if !props.isEmpty { leInteresan(c) }
                    datos(c)
                    todoCon(c)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else if let error {
                EstadoError(que: "el contacto", error: error) { Task { await cargar() } }.padding(.top, 40)
            } else { EsqueletoFilas(filas: 5).padding(16) }
        }
        .pantallaApilada("")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !nota.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pieNota.padding(.horizontal, 20).padding(.vertical, 8).background(C.fondo.opacity(0.95))
            }
        }
        .toolbar {
            if estado.escribe, c != nil {
                Menu {
                    Button { editando = "todo" } label: { Label("Editar", systemImage: "pencil") }
                    Button { agendar = AgendarDesdeFicha(dia: Date(), hora: nil) } label: { Label("Agendar visita", systemImage: "calendar") }
                    Button { nuevaOp = true } label: { Label("Nueva operación", systemImage: "rectangle.split.3x1") }
                    Button(role: .destructive) { Task { await borrar() } } label: { Label("Mandar a la papelera", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más")
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(item: Binding(get: { editando.map { HojaEditar(id: $0) } }, set: { editando = $0?.id })) { s in
            if let c { EditarContacto(contacto: c, soloBusca: s.id == "busca") }
        }
        .sheet(item: $agendar) { a in
            if let c { NuevaCita(contacto: (c.id, c.nombre), dia: a.dia, hora: a.hora).presentationDetents([.large]) }
        }
        .sheet(isPresented: $nuevaOp) { if let c { NuevaOperacion(contacto: Resultado(id: c.id, tipo: "contacto", titulo: c.nombre)) } }
        .onChange(of: dictado.texto) { _, t in if dictado.grabando { nota = [base, t].filter { !$0.isEmpty }.joined(separator: " ") } }
        .onChange(of: dictado.grabando) { _, g in dictandoDesde = g ? Date() : nil }
        .onDisappear { dictado.parar() }
        .userActivity("ar.com.corredor.app.contacto", isActive: c != nil) { a in
            a.title = c?.nombre
            a.userInfo = ["id": id]
            a.isEligibleForSearch = true
        }
    }

    private struct HojaEditar: Identifiable { var id: String }

    // MARK: Partes

    private func cabecera(_ c: Contacto) -> some View {
        let t = Contactos.tono(c.tipo)
        let agente = c.agenteId.flatMap { nombres[$0] }
        let origen = [agente.map { "de \(Charla.primerNombre($0))" },
                      c.origen?.nonEmpty.map { o in "llegó por \(o)\(c.creadoEn.map { " el \(Self.diaMes($0))" } ?? "")" }].compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 8) {
            Text(Formato.iniciales(c.nombre)).font(Estilo(tamano: 30, peso: .bold, relativo: .largeTitle).font).foregroundStyle(t.tinta)
                .frame(width: 84, height: 84).background(t.fondo, in: Circle())
            Text(c.nombre).font(Estilo(tamano: 26, peso: .bold, tracking: -0.02, relativo: .title).font).foregroundStyle(C.texto).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                pill(TextosContacto.rol(c.tipo), C.azulFondo, C.azulTinta)
                if let e = c.etiquetas?.first { pill(e, C.hundida, C.texto2) }
            }
            if !origen.isEmpty { Text(origen).estilo(.footnote).foregroundStyle(C.texto2) }
        }
        .frame(maxWidth: .infinity)
    }

    static func diaMes(_ f: Date) -> String {
        let c = Formato.calendario.dateComponents([.day, .month], from: f)
        return String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
    }

    private func pill(_ t: String, _ f: Color, _ tinta: Color) -> some View {
        Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(tinta)
            .padding(.horizontal, 10).frame(height: 24).background(f, in: Capsule())
    }

    private func acciones(_ c: Contacto) -> some View {
        HStack(spacing: 8) {
            Button { Task { await Contactos.abrirChat(c.id, estado: estado) } } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill").font(.system(size: 21))
                    Text("WhatsApp").font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
                }
                .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 64).background(C.accion, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(Presionable())
            accion("phone.fill", "Llamar") { Afuera.llamar(c.telefono) }.disabled(c.telefono == nil).opacity(c.telefono == nil ? 0.5 : 1)
            if estado.escribe { accion("calendar", "Agendar") { agendar = AgendarDesdeFicha(dia: Date(), hora: nil) } }
            if let m = c.email { accion("envelope.fill", "Mail") { if let u = URL(string: "mailto:\(m)") { UIApplication.shared.open(u) } } }
        }
    }

    private func accion(_ i: String, _ t: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            VStack(spacing: 4) {
                Image(systemName: i).font(.system(size: 21))
                Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
            }
            .foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 64).tarjeta(14)
        }
        .buttonStyle(Presionable())
    }

    /// «¿Cómo le fue en Mendoza 2350?»: la visita pasa a hecha y queda la nota.
    private func comoFue(_ v: Cita) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 22)).foregroundStyle(C.avisoTinta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Cómo le fue en \(v.propiedadTitulo ?? v.titulo ?? "la visita")?").estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Text("La visita terminó \(Formato.hace(v.terminaEn))").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            HStack(spacing: 8) {
                ForEach([("le_gusto", "Le gustó"), ("duda", "Duda"), ("no_va", "No va")], id: \.0) { k, t in
                    Button(t) { Task { await contar(v, k) } }.buttonStyle(BotonTonal()).disabled(contando)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(C.avisoFondo, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func tarjetaBusca(_ c: Contacto) -> some View {
        let busca = TextosContacto.buscaLarga(c)
        return VStack(alignment: .leading, spacing: 10) {
            Text("QUÉ BUSCA").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.5).foregroundStyle(C.okTinta)
            Text(busca.isEmpty ? "Todavía no sabemos qué busca \(primer)" : busca).estilo(.headline).foregroundStyle(C.texto)
            FlowLayout(espacio: 6) {
                ForEach(c.buscaDetalles ?? [], id: \.self) { d in
                    Text(d).font(Estilo(tamano: 13, peso: .medium, relativo: .footnote).font).foregroundStyle(C.texto)
                        .padding(.horizontal, 10).frame(height: 28).background(C.superficie, in: Capsule())
                }
                if estado.escribe {
                    Button(busca.isEmpty ? "Cargar qué busca" : "Editar") { editando = "busca" }
                        .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.accion)
                        .padding(.horizontal, 10).frame(height: 28)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(C.okFondo, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func leInteresan(_ c: Contacto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Le pueden interesar", cuenta: "\(props.count) de tu cartera")
            VStack(spacing: 0) {
                ForEach(Array(props.enumerated()), id: \.element.id) { i, p in
                    let (e, tono) = p.estadoTexto
                    HStack(spacing: 12) {
                        Button { estado.abrir(AFichaPropiedad(id: p.propiedadId)) } label: {
                            HStack(spacing: 12) {
                                Foto(url: p.miniatura(estado.api.base, inmobiliaria: estado.sesion?.inmobiliariaId)).frame(width: 56, height: 42).clipShape(.rect(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(String(p.nombre.split(separator: ",").first ?? "")).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                    Text(e).estilo(.footnote).foregroundStyle(tono == .verde ? C.okTinta : tono == .oro ? C.avisoTinta : C.texto2).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        if (p.estado ?? "nueva") == "nueva" && estado.escribe {
                            Button("Mandar") { Task { await mandar(p, a: c) } }.buttonStyle(BotonTonal())
                        } else if p.precio != nil {
                            Text(p.precioTexto).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    private func datos(_ c: Contacto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Datos")
            VStack(spacing: 0) {
                dato("Celular", c.telefono ?? "—", primera: true) { if c.telefono != nil { Afuera.llamar(c.telefono) } }
                dato("Mail", c.email ?? "—", primera: false) { if let m = c.email, let u = URL(string: "mailto:\(m)") { UIApplication.shared.open(u) } }
                dato("Etiquetas", (c.etiquetas ?? []).isEmpty ? "—" : (c.etiquetas ?? []).joined(separator: ", "), primera: false) { if estado.escribe { editando = "todo" } }
            }
            .tarjeta()
        }
    }

    private func dato(_ l: String, _ v: String, primera: Bool, _ tocar: @escaping () -> Void) -> some View {
        Button(action: tocar) {
            HStack {
                Text(l).foregroundStyle(C.texto2)
                Spacer()
                Text(v).foregroundStyle(C.texto).multilineTextAlignment(.trailing)
            }
            .estilo(.body16).padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Todo con …

    private var grupos: [(String, [ItemLinea])] {
        var out: [(String, [ItemLinea])] = []
        for it in linea where vista == nil || it.grupo == vista {
            let g = ItemLinea.grupoDeFecha(it.en)
            if out.last?.0 == g { out[out.count - 1].1.append(it) } else { out.append((g, [it])) }
        }
        return out
    }

    private func todoCon(_ c: Contacto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TituloBloque(texto: "Todo con \(primer)")
            Segmentado(opciones: Self.vistas, elegido: $vista)
            VStack(alignment: .leading, spacing: 0) {
                if estado.escribe { anotar.padding(.bottom, 12) }
                ForEach(grupos, id: \.0) { titulo, items in
                    Text(titulo.uppercased()).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.5).foregroundStyle(C.texto3).padding(.vertical, 6)
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in renglon(it, ultimo: i == items.count - 1) }
                }
                if grupos.isEmpty { Text("Todavía no hay nada con \(primer) en esta vista.").estilo(.texto14).foregroundStyle(C.texto3) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        }
    }

    private var anotar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(C.texto3).padding(.top, 3)
                TextField("Anotá algo de la charla…", text: $nota, axis: .vertical).estilo(.body16).lineLimit(1...6)
                Button {
                    if dictado.grabando { dictado.parar() } else { base = nota; dictado.empezar(base: nota) }
                } label: {
                    Image(systemName: dictado.grabando ? "mic.fill" : "mic").font(.system(size: 20)).foregroundStyle(dictado.grabando ? C.error : C.accion)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(dictado.grabando ? "Parar el dictado" : "Dictar la nota")
            }
            if dictado.grabando, let desde = dictandoDesde {
                TimelineView(.periodic(from: desde, by: 1)) { ctx in
                    let s = max(0, Int(ctx.date.timeIntervalSince(desde)))
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").foregroundStyle(C.error)
                        Text("Escuchando… \(s / 60):\(String(format: "%02d", s % 60))").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renglon(_ it: ItemLinea, ultimo: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: it.icono).font(.system(size: 14)).foregroundStyle(it.tono.tinta)
                    .frame(width: 30, height: 30).background(it.tono.fondo, in: Circle())
                if !ultimo { Rectangle().fill(C.linea2).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(it.titulo).estilo(.subheadFuerte).foregroundStyle(C.texto)
                if let b = it.burbuja {
                    Text(b).estilo(.texto14).foregroundStyle(C.texto)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(it.mio ? Color.tema(0xDCEBE3, 0x1F3B33) : C.hundida, in: .rect(cornerRadius: 12))
                } else if let d = it.detalle {
                    Text(it.cita ? "«\(d)»" : d).estilo(.texto14).foregroundStyle(C.texto2)
                }
            }
            .padding(.bottom, 12)
            Spacer(minLength: 0)
        }
    }

    /// «Guardar y agendar sábado» si la nota dice un día; si no, «Guardar».
    @ViewBuilder
    private var pieNota: some View {
        let e = Entender.entender(nota)
        if let d = e.dia, let f = Fecha.dia(d) {
            let cal = Calendar.current
            let texto = cal.isDateInToday(f) ? "hoy" : cal.isDateInTomorrow(f) ? "mañana" : AgendaRaiz.nombreDia(f)
            Button(guardando ? "Guardando…" : "Guardar y agendar \(texto)") {
                Task { if await anotarNota() { agendar = AgendarDesdeFicha(dia: f, hora: e.hora) } }
            }
            .buttonStyle(BotonPrincipal()).disabled(guardando)
        } else {
            Button(guardando ? "Guardando…" : "Guardar") { Task { await anotarNota() } }.buttonStyle(BotonPrincipal()).disabled(guardando)
        }
    }

    // MARK: Datos

    private func cargar() async {
        do {
            c = try await estado.api.get("/v1/contactos/\(id)")
            error = nil
        } catch let e as ErrorApi { if c == nil { error = e }; return } catch { return }
        guard let c else { return }
        let p: [PropiedadDeContacto] = (try? await estado.api.get("/v1/contactos/\(id)/propiedades")) ?? []
        props = Array(p.prefix(6))
        if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
        let notas: [NotaContacto] = (try? await estado.api.get("/v1/contactos/\(id)/notas")) ?? []
        let citas: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "contacto", value: id), .init(name: "rango", value: "todas"), .init(name: "limite", value: "60")])) ?? []
        let activas: [Operacion] = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "contacto", value: id)])) ?? []
        let caidas: [Operacion] = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "contacto", value: id), .init(name: "caidas", value: "si")])) ?? []
        struct Conv: Decodable { var id: String }
        let convs: [Conv] = (try? await estado.api.get("/v1/whatsapp/conversaciones", query: [.init(name: "contacto", value: id), .init(name: "limite", value: "1")])) ?? []
        var mensajes: [MensajeWA] = []
        if let cv = convs.first { mensajes = (try? await estado.api.get("/v1/whatsapp/conversaciones/\(cv.id)/mensajes", query: [.init(name: "limite", value: "20")])) ?? [] }
        linea = armarLinea(c, notas: notas, citas: citas, ops: activas + caidas, mensajes: mensajes)
        let ahora = Date()
        visitaReciente = citas.filter { $0.tipo == "visita" && $0.estado == "pendiente" && $0.terminaEn <= ahora && ahora.timeIntervalSince($0.terminaEn) < 6 * 3600 }
            .max { $0.terminaEn < $1.terminaEn }
    }

    /// Mensajes, visitas, operaciones, notas y por dónde llegó; lo más nuevo arriba.
    private func armarLinea(_ c: Contacto, notas: [NotaContacto], citas: [Cita], ops: [Operacion], mensajes: [MensajeWA]) -> [ItemLinea] {
        let quien = { (id: String?, n: String?) -> String in
            if let id, id == yo { return "vos" }
            return Charla.primerNombre(id.flatMap { nombres[$0] } ?? n)
        }
        var items: [ItemLinea] = []
        let pre = ["visita": "Visita a", "llamado": "Llamado por", "firma": "Firma de", "tasacion": "Tasación de", "otro": ""]
        for x in citas {
            let prop = x.propiedadTitulo ?? ""
            let p = pre[x.tipo ?? ""] ?? ""
            let titulo = !prop.isEmpty && !p.isEmpty ? "\(p) \(prop) · \(Formato.horaDe(x.empiezaEn))" : "\(x.titulo ?? x.tipoTexto) · \(Formato.horaDe(x.empiezaEn))"
            let con = quien(x.agenteId, x.agenteNombre)
            let est = ["hecha": "hecha", "cancelada": "cancelada"][x.estado ?? ""] ?? (x.recordadoEn != nil ? "le mandamos el recordatorio" : "")
            items.append(ItemLinea(id: "c" + x.id, grupo: .visitas, en: x.empiezaEn, icono: x.tipo == "firma" ? "signature" : "calendar",
                                   tono: x.estado == "cancelada" ? .neutro : .oro, titulo: titulo,
                                   detalle: [con.isEmpty ? nil : "con \(con)", est.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty))
        }
        let etapa = ["nuevo": "Nueva", "contactado": "Contactado", "visita": "En visita", "reserva": "Reservó", "cierre": "Cerró"]
        for o in ops {
            let prop = o.nombre
            let caida = o.caidaEn != nil
            let sena = o.sena.map { " · \(Formato.plata($0, o.senaMoneda ?? o.moneda ?? "USD"))" } ?? ""
            let en = o.caidaEn ?? o.actualizadoEn ?? Date()
            let con = quien(o.agenteId, o.agenteNombre)
            let detalle = [Formato.dia(en), caida ? o.caidaMotivo : (o.valor ?? 0) > 0 ? "ofrece \(Formato.plata(o.valor ?? 0, o.moneda ?? "USD"))" : nil,
                           con.isEmpty ? nil : "con \(con)"].compactMap { $0 }.joined(separator: " · ")
            items.append(ItemLinea(id: "o" + o.id, grupo: .otros, en: en,
                                   icono: caida ? "heart.slash" : o.etapa == "reserva" ? "bookmark" : o.etapa == "cierre" ? "hands.sparkles" : "rectangle.split.3x1",
                                   tono: caida ? .rojo : o.etapa == "reserva" ? .oro : o.etapa == "cierre" ? .verde : .azul,
                                   titulo: caida ? "Se cayó \(prop)" : "\(etapa[o.etapa] ?? o.etapa) \(prop)\(o.etapa == "reserva" ? sena : "")", detalle: detalle))
        }
        for n in notas {
            let autor = quien(n.autorId, nil)
            let titulo = n.tipo == "llamada" ? "Llamada · \(Formato.horaDe(n.ocurrioEn))" : autor == "vos" ? "Nota tuya" : autor.isEmpty ? "Nota" : "Nota de \(autor)"
            items.append(ItemLinea(id: "n" + n.id, grupo: .notas, en: n.ocurrioEn,
                                   icono: n.tipo == "llamada" ? "phone" : n.tipo == "visita" ? "calendar.badge.checkmark" : "note.text",
                                   tono: .neutro, titulo: titulo, detalle: n.texto, cita: true))
        }
        for m in mensajes {
            guard let t = m.texto?.nonEmpty else { continue }
            items.append(ItemLinea(id: "m" + m.id, grupo: .mensajes, en: m.ocurrioEn, icono: "bubble.left", tono: .verde,
                                   titulo: "WhatsApp · \(Formato.horaDe(m.ocurrioEn))", burbuja: t, mio: m.saliente))
        }
        items.append(ItemLinea(id: "llego", grupo: .otros, en: c.creadoEn ?? Date(), icono: "globe", tono: .azul,
                               titulo: c.origen?.nonEmpty.map { "Llegó por \($0)" } ?? "Lo cargaron en Corredor", detalle: c.creadoEn.map { Formato.dia($0) }))
        return items.sorted { $0.en > $1.en }
    }

    /// Guarda la nota (con «Deshacer», que la borra). Sin señal queda en la cola.
    @discardableResult
    private func anotarNota() async -> Bool {
        dictado.parar()
        let t = nota.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        struct Cuerpo: Encodable { var tipo = "nota"; var texto: String }
        guardando = true
        defer { guardando = false }
        do {
            let n: NotaContacto = try await estado.api.enviar("POST", "/v1/contactos/\(id)/notas", Cuerpo(texto: String(t.prefix(5000))))
            nota = ""
            estado.avisar("Nota guardada") {
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/contactos/\(id)/notas/\(n.id)")
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            await cargar()
            return true
        } catch let e as ErrorApi where e.sinConexion {
            do {
                try await estado.cola.enviar("POST", "/v1/contactos/\(id)/notas", Cuerpo(texto: t), etiqueta: "Nota en \(c?.nombre ?? "")")
                nota = ""
                estado.avisar("Sin señal · la nota se guarda cuando vuelva")
                return true
            } catch { estado.avisar(error); return false }
        } catch {
            estado.avisarReintentar(Estado.texto(error, si: "No se guardó")) { Task { await anotarNota() } }
            return false
        }
    }

    private func contar(_ v: Cita, _ como: String) async {
        struct EstadoCita: Encodable { var estado = "hecha" }
        struct Nota: Encodable { var tipo = "visita"; var texto: String }
        let frase = ["le_gusto": "Le gustó", "duda": "Tiene dudas", "no_va": "No va"][como] ?? ""
        contando = true
        defer { contando = false }
        do {
            try await estado.api.hacer("PATCH", "/v1/agenda/\(v.id)", EstadoCita())
            let texto = "\(frase) \(v.propiedadTitulo ?? v.titulo ?? "")".trimmingCharacters(in: .whitespaces)
            try await estado.api.hacer("POST", "/v1/contactos/\(id)/notas", Nota(texto: texto))
            estado.avisar("Anotado en la ficha")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// «Mandar»: deja escrita la ficha en la charla de WhatsApp con este contacto y la anota como enviada.
    private func mandar(_ p: PropiedadDeContacto, a c: Contacto) async {
        struct Envio: Encodable { var contactoId: String; var canal = "whatsapp" }
        struct Conv: Decodable { var id: String }
        struct Cuerpo: Encodable { var contactoId: String }
        do {
            let prop: Propiedad = try await estado.api.get("/v1/propiedades/\(p.propiedadId)")
            let web = await Documentos.inmobiliaria(estado.api)?.web
            let x: Conv = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: c.id))
            if let t = Charla.textoFicha(primer, prop, web: web) { BorradorChat.textos[x.id] = t }
            try await estado.api.hacer("POST", "/v1/propiedades/\(p.propiedadId)/envios", Envio(contactoId: c.id))
            estado.abrir(AChat(id: x.id))
        } catch { estado.avisar(error) }
    }

    /// A la papelera; «Deshacer» la restaura.
    private func borrar() async {
        let n = c?.nombre ?? "El contacto"
        do {
            try await estado.api.hacer("DELETE", "/v1/contactos/\(id)")
            cerrar()
            estado.avisar("\(n) fue a la papelera") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/papelera/contacto/\(id)/restaurar")
                        estado.version += 1
                        estado.abrir(AFichaContacto(id: id))
                    } catch { estado.avisar(error) }
                }
            }
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}

/// Alta o edición de un contacto (también lo trae de la agenda del iPhone). Al editar, el PUT lleva
/// el contacto entero con lo cambiado encima (si no, la API borra lo que esta pantalla no muestra).
/// `soloBusca`: sólo «Qué busca» (la tarjeta de la ficha).
struct EditarContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var contacto: Contacto? = nil
    var soloBusca = false
    @State private var c = Contacto(id: "", nombre: "", tipo: "comprador")
    @State private var barrios = ""
    @State private var detalles = ""
    @State private var etiquetas = ""
    @State private var equipo: [Miembro] = []
    @State private var agenda = false
    @State private var guardando = false
    @State private var error: String?
    /// Los errores por campo que devolvió la API (problem+json `issues`).
    @State private var errores: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MensajeError(texto: error) } }
                if !soloBusca {
                    Section {
                        TextField("Nombre", text: $c.nombre).textContentType(.name)
                        if let e = errores["nombre"] { MensajeError(texto: e) }
                        TextField("Celular", text: Binding(get: { c.telefono ?? "" }, set: { c.telefono = $0.nonEmpty })).keyboardType(.phonePad)
                        if let e = errores["telefono"] { MensajeError(texto: e) }
                        TextField("Mail", text: Binding(get: { c.email ?? "" }, set: { c.email = $0.nonEmpty })).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        if let e = errores["email"] { MensajeError(texto: e) }
                        Picker("Es", selection: Binding(get: { c.tipo ?? "comprador" }, set: { c.tipo = $0 })) { ForEach(TextosContacto.tiposElegir, id: \.0) { Text($0.1).tag($0.0) } }
                        if contacto != nil {
                            Picker("De", selection: Binding(get: { c.agenteId ?? "" }, set: { c.agenteId = $0.nonEmpty })) {
                                Text("Sin agente").tag("")
                                ForEach(equipo.filter { $0.rol != "lector" }) { Text($0.completo).tag($0.usuarioId) }
                            }
                        }
                        TextField("Llegó por (Zonaprop, WhatsApp, un cartel…)", text: Binding(get: { c.origen ?? "" }, set: { c.origen = $0.nonEmpty }))
                        if contacto == nil { Button { agenda = true } label: { Label("Traer de la agenda del iPhone", systemImage: "person.crop.circle") } }
                    }
                    Section { TextField("Etiquetas", text: $etiquetas) } header: { Text("Etiquetas") } footer: { Text("Separadas por comas: Con crédito, Con mascotas") }
                }
                Section("Qué busca") {
                    Picker("Quiere", selection: Binding(get: { c.buscaOperacion ?? "" }, set: { c.buscaOperacion = $0.nonEmpty })) {
                        Text("—").tag(""); Text("Comprar").tag("venta"); Text("Alquilar").tag("alquiler"); Text("Temporada").tag("temporario")
                    }
                    Picker("Tipo", selection: Binding(get: { c.buscaTipo ?? "" }, set: { c.buscaTipo = $0.nonEmpty })) {
                        Text("—").tag(""); ForEach(Propiedad.tipos, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Moneda", selection: Binding(get: { c.buscaMoneda ?? "USD" }, set: { c.buscaMoneda = $0 })) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("Desde", value: $c.buscaDesde, format: .number).keyboardType(.numberPad)
                    TextField("Hasta", value: $c.buscaHasta, format: .number).keyboardType(.numberPad)
                    Stepper("Ambientes: \(c.buscaAmbientes.map(String.init) ?? "—")", value: Binding(get: { c.buscaAmbientes ?? 0 }, set: { c.buscaAmbientes = $0 == 0 ? nil : $0 }), in: 0...10)
                    TextField("Barrios (Belgrano, Núñez)", text: $barrios)
                }
                Section { TextField("Además pide", text: $detalles) } footer: { Text("Con balcón, Apto crédito, Hasta 30 años") }
                if !soloBusca { Section("Notas") { TextField("Notas internas", text: Binding(get: { c.notas ?? "" }, set: { c.notas = $0.nonEmpty }), axis: .vertical) } }
            }
            .navigationTitle(soloBusca ? "Qué busca" : (contacto == nil ? "Contacto nuevo" : "Editar contacto")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(c.nombre.trimmingCharacters(in: .whitespaces).isEmpty || guardando) }
            }
            .sheet(isPresented: $agenda) {
                SelectorAgenda { cn in
                    c.nombre = [cn.givenName, cn.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    c.telefono = cn.phoneNumbers.first?.value.stringValue
                    c.email = cn.emailAddresses.first.map { String($0.value) }
                    if c.origen == nil { c.origen = "Agenda del celular" }
                }
            }
        }
        .onAppear {
            if let contacto {
                c = contacto
                barrios = (contacto.buscaBarrios ?? []).joined(separator: ", ")
                detalles = (contacto.buscaDetalles ?? []).joined(separator: ", ")
                etiquetas = (contacto.etiquetas ?? []).joined(separator: ", ")
            }
        }
        .task { if contacto != nil && !soloBusca { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] } }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        let lista = { (t: String) in t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        c.buscaBarrios = lista(barrios)
        c.buscaDetalles = lista(detalles)
        if !soloBusca { c.etiquetas = lista(etiquetas) }
        struct Cuerpo: Encodable {
            var nombre: String; var telefono: String?; var email: String?; var tipo: String?; var origen: String?; var notas: String?
            var buscaOperacion: String?; var buscaTipo: String?; var buscaMoneda: String?; var buscaDesde: Double?; var buscaHasta: Double?
            var buscaAmbientes: Int?; var buscaBarrios: [String]?; var buscaDetalles: [String]?; var etiquetas: [String]?; var agenteId: String?
        }
        let cuerpo = Cuerpo(nombre: c.nombre.trimmingCharacters(in: .whitespaces), telefono: c.telefono, email: c.email, tipo: c.tipo, origen: c.origen, notas: c.notas,
                            buscaOperacion: c.buscaOperacion, buscaTipo: c.buscaTipo, buscaMoneda: c.buscaMoneda, buscaDesde: c.buscaDesde, buscaHasta: c.buscaHasta,
                            buscaAmbientes: c.buscaAmbientes, buscaBarrios: c.buscaBarrios, buscaDetalles: c.buscaDetalles, etiquetas: c.etiquetas ?? [],
                            agenteId: contacto == nil ? estado.usuario?.id : c.agenteId)
        let metodo = contacto == nil ? "POST" : "PUT"
        let ruta = contacto.map { "/v1/contactos/\($0.id)" } ?? "/v1/contactos"
        do {
            // Primero directo (para ver los errores por campo); sin señal, a la cola.
            let campos = try await estado.api.hacerValidando(metodo, ruta, cuerpo)
            if !campos.isEmpty {
                errores = campos
                error = "Revisá los datos marcados."
                return
            }
            if contacto != nil { estado.avisar("Guardado") } else { estado.sugerir("Contacto guardado", "Agendar", AAgendaDia()) }
            estado.version += 1
            cerrar()
        } catch let e as ErrorApi where e.sinConexion {
            do {
                try await estado.cola.enviar(metodo, ruta, cuerpo, etiqueta: contacto == nil ? "Alta de \(c.nombre)" : "Cambios en \(c.nombre)")
                estado.avisar("Sin señal · se guarda cuando vuelva")
                estado.version += 1
                cerrar()
            } catch { self.error = Estado.texto(error, si: "No se guardó.") }
        } catch { self.error = Estado.texto(error, si: "No se guardó.") }
    }
}

extension Api {
    /// Como `hacer`, pero si la API rechaza los datos (400/422) devuelve los errores por campo
    /// (problem+json `issues`: path → message) en vez de tirar el error. Sin señal tira `ErrorApi.sinRed`.
    func hacerValidando<C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C) async throws -> [String: String] {
        var r = URLRequest(url: base.appendingPathComponent(ruta), timeoutInterval: 20)
        r.httpMethod = metodo
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try Api.codificador.encode(cuerpo)
        let datos: Data
        let resp: URLResponse
        do { (datos, resp) = try await http.data(for: r) } catch { throw ErrorApi.sinRed }
        guard let h = resp as? HTTPURLResponse else { throw ErrorApi.desconocido }
        if (200..<300).contains(h.statusCode) { return [:] }
        let p = try? JSONDecoder().decode(ProblemaApi.self, from: datos)
        let campos = Dictionary((p?.issues ?? []).compactMap { c in c.path.map { ($0, c.message ?? "Revisá este dato.") } }, uniquingKeysWith: { a, _ in a })
        if (h.statusCode == 400 || h.statusCode == 422), !campos.isEmpty { return campos }
        throw ErrorApi(estado: h.statusCode, codigo: p?.code ?? "interno", titulo: p?.title ?? "Algo salió mal", detalle: p?.detail ?? "Probá de nuevo en un rato.")
    }
}
