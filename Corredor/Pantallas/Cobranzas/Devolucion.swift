import SwiftUI

/// La devolución comparada con la entrega (web 14E): «¿qué cambió y quién lo paga?». Cada ítem que
/// cambió muestra la foto de la entrega al lado de la de hoy; lo que paga la parte inquilina se
/// descuenta del depósito y sale en el acta de devolución. Lo que se elige queda en la API (contra el
/// acta de entrada): lo ve cualquiera del equipo y entra solo si otro lo cambia.
struct Devolucion: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var prop: Propiedad?
    @State private var items: [ItemInventario] = []
    @State private var entrada: Acta?
    @State private var salida: Acta?
    @State private var contrato: ContratoAPI?
    @State private var decisiones: [String: DecisionDevolucion] = [:]
    @State private var cargado = false
    @State private var error: ErrorApi?
    @State private var vista = "cambios"
    @State private var espera: Task<Void, Never>?
    @State private var mandando = false
    @State private var previo: ArchivoPrevio?

    private var cambios: [Inv.Cambio] { Inv.comparar(entrada?.items ?? [], items.map(Inv.comoActa)) }
    private var total: Int { entrada?.items?.count ?? 0 }
    private var moneda: String { contrato?.moneda ?? "ARS" }
    private var inquilina: String? { contrato?.contactoNombre?.nonEmpty }
    private var cobrados: [Inv.Cambio] { cambios.filter { decision($0).quien == "inquilino" && (decision($0).importe ?? 0) > 0 } }
    private var descuentos: Double { cobrados.reduce(0) { $0 + (decision($1).importe ?? 0) } }
    private var devolver: Double? { contrato?.deposito.map { max(0, $0 - descuentos) } }
    /// Lo que no cambió (para «Todo»).
    private var iguales: [Acta.Item] {
        let conCambio = Set(cambios.compactMap { $0.entrega.map { Inv.clave($0.ambiente, $0.descripcion) } })
        return (entrada?.items ?? []).filter { !conCambio.contains(Inv.clave($0.ambiente, $0.descripcion)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !cargado, let error {
                    EstadoError(que: "la devolución", error: error) { Task { await cargar() } }
                } else if !cargado {
                    EsqueletoFilas(filas: 5)
                } else if entrada == nil {
                    EstadoVacio(icono: "checklist", titulo: "Todavía no hay acta de entrega",
                                texto: "Para comparar la devolución hace falta la recorrida de entrega con su acta.",
                                accion: ("Hacer la recorrida de entrega", { estado.abrir(ARecorrida(id: propiedad, tipo: "entrega")) }))
                        .padding(.top, 30)
                } else {
                    cabeza
                    Segmentado(opciones: [("cambios", "Sólo cambios \(cambios.count)"), ("todo", "Todo \(total)")], elegido: $vista)
                    listaCambios
                    if vista == "todo" { listaIguales }
                    deposito
                    antesDeFirmar
                    botones
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Devolución")
        .vistaPrevia($previo)
        .toolbar {
            if salida != nil {
                Button { Task { await actaPDF() } } label: { Label("Acta PDF", systemImage: "arrow.down.doc") }
            }
        }
        .task(id: estado.version) { await cargar() }
    }

    // MARK: Partes

    private var cabeza: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lineaContrato).estilo(.footnote).foregroundStyle(C.texto2)
            Text("Devolución · \(Formato.cantidad(cambios.count, "cambio", "cambios")) de \(Formato.cantidad(total, "ítem", "ítems"))")
                .font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
        }
    }

    private var lineaContrato: String {
        var s = prop?.direccion ?? prop?.nombre ?? ""
        if let i = inquilina { s += " · inquilina \(i)" }
        if let k = contrato {
            s += " · contrato \(String((k.inicio ?? "").prefix(4)))-\(String((k.fin ?? "").prefix(4)))"
        }
        return s
    }

    @ViewBuilder private var listaCambios: some View {
        if cambios.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(C.okTinta)
                (Text("Está todo como en la entrega.").bold() + Text(" Si recorriste la casa, labrá el acta de devolución y se devuelve el depósito\u{00A0}entero."))
                    .estilo(.texto14).foregroundStyle(C.texto)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(C.okFondo, in: .rect(cornerRadius: 16))
        } else {
            VStack(spacing: 10) {
                ForEach(cambios) { c in tarjetaCambio(c) }
            }
        }
    }

    private func tarjetaCambio(_ c: Inv.Cambio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                figura(c.entrega?.fotosUrl?.first, pie: c.entrega.map { "Entrega \(fechaCorta(entrada?.fecha)) · \(tituloEstado($0))" } ?? "No estaba en la entrega",
                       tinta: C.texto2, grave: false)
                figura(c.hoy?.fotosUrl?.last, pie: textoHoy(c), tinta: grave(c) ? C.errorTinta : C.avisoTinta, grave: grave(c))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Inv.rotulo(c.ambiente, c.descripcion)).estilo(.subheadFuerte).foregroundStyle(C.texto)
                if let n = c.hoy?.notas?.nonEmpty { Text(n).estilo(.footnote).foregroundStyle(C.texto2) }
            }
            if c.entrega != nil { quienPaga(c) }
        }
        .padding(14)
        .tarjeta()
    }

    private func figura(_ foto: String?, pie: String, tinta: Color, grave: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let f = foto { Foto(url: urlDeFoto(f, ancho: 500)) } else {
                    ZStack { C.hundida; Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(C.texto3) }
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(grave ? C.error : Color.clear, lineWidth: 2))
            Text(pie).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(tinta).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func opciones(_ c: Inv.Cambio) -> [(String, String)] {
        c.desgaste ? [("inquilino", "Inquilina"), ("desgaste", "Desgaste")] : [("inquilino", "Inquilina"), ("dueno", "Dueño")]
    }

    private func quienPaga(_ c: Inv.Cambio) -> some View {
        let d = decision(c)
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿Quién paga?").estilo(.footnoteFuerte).foregroundStyle(C.texto2)
            Segmentado(opciones: opciones(c), elegido: Binding(get: { decision(c).quien }, set: { elegir(c, $0) }))
                .disabled(!estado.escribe)
            if d.quien == "inquilino" {
                HStack(spacing: 8) {
                    Text(moneda).estilo(.subheadFuerte).foregroundStyle(C.texto2)
                    TextField("0", text: Binding(get: { decision(c).importe.map { Formato.numero(Int($0)) } ?? "" }, set: { importe(c, $0) }))
                        .keyboardType(.numberPad).estilo(.body16)
                        .disabled(!estado.escribe)
                        .accessibilityLabel("Importe a descontar")
                }
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background(C.hundida, in: .rect(cornerRadius: 12))
            } else {
                Text("no se descuenta").estilo(.footnote).foregroundStyle(C.texto3)
            }
        }
    }

    private var listaIguales: some View {
        VStack(spacing: 0) {
            ForEach(Array(iguales.enumerated()), id: \.offset) { i, it in
                HStack(spacing: 10) {
                    Group {
                        if let f = it.fotosUrl?.first { Foto(url: urlDeFoto(f)) } else { C.hundida }
                    }
                    .frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 8))
                    Text(Inv.rotulo(it.ambiente, it.descripcion)).estilo(.texto14).foregroundStyle(C.texto).lineLimit(2)
                    Spacer()
                    Text("Igual · \(Inv.nombre(it.estado))").estilo(.footnote).foregroundStyle(C.texto2)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
        }
        .tarjeta()
    }

    private var deposito: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEPÓSITO EN GARANTÍA").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.6).foregroundStyle(C.oro)
            if let dep = contrato?.deposito {
                HStack { Text("Depósito"); Spacer(); Text(Formato.plata(dep, moneda)) }
                HStack { Text("Descuentos (\(cobrados.count))"); Spacer(); Text(descuentos > 0 ? "−" + Formato.numero(Int(descuentos)) : "0") }
                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                HStack {
                    Text("A devolver\(inquilina.map { " a \(Inv.primerNombre($0))" } ?? "")").bold()
                    Spacer()
                    Text(Formato.numero(Int(devolver ?? 0))).font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font)
                }
            } else {
                Text(Formato.sinViudas("El contrato no tiene el depósito cargado. Los descuentos (\(Formato.plata(descuentos, moneda))) igual salen en el acta."))
            }
        }
        .estilo(.subhead)
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.verde800, in: .rect(cornerRadius: M.rDestacada, style: .continuous))
    }

    private var antesDeFirmar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Antes de firmar").estilo(.subheadFuerte).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Las fotos de la entrega y las de hoy van al acta, ítem por ítem.")).estilo(.footnote).foregroundStyle(C.texto2)
            Text(Formato.sinViudas("Lo que se descuenta sale en el acta de devolución con su importe.")).estilo(.footnote).foregroundStyle(C.texto2)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
    }

    @ViewBuilder private var botones: some View {
        VStack(spacing: 8) {
            if let s = salida {
                Button("Ver el acta de devolución") { estado.abrir(AFirmas(id: "\(propiedad)/\(s.id)")) }.buttonStyle(BotonPrincipal())
                Button { Task { await actaPDF() } } label: { Label("Acta PDF", systemImage: "arrow.down.doc") }.buttonStyle(BotonHundido())
            } else if estado.escribe {
                Button(mandando ? "Labrando el acta…" : "Mandar acta para firmar") { Task { await mandar() } }
                    .buttonStyle(BotonPrincipal()).disabled(mandando)
            }
            HStack(spacing: 8) {
                Button { estado.abrir(ARecorrida(id: propiedad, tipo: "devolucion")) } label: { Label("Recorrida de devolución", systemImage: "figure.walk") }
                    .buttonStyle(BotonHundido())
                if let e = entrada {
                    Button { estado.abrir(AFirmas(id: "\(propiedad)/\(e.id)")) } label: { Label("Acta de entrega", systemImage: "doc.text") }
                        .buttonStyle(BotonHundido())
                }
            }
        }
    }

    // MARK: Textos

    /// «12/03/26».
    private func fechaCorta(_ s: String?) -> String {
        let n = Inv.numerica(s)
        return n.count == 10 ? String(n.prefix(6)) + String(n.suffix(2)) : n
    }

    private func tituloEstado(_ i: Acta.Item) -> String {
        Inv.nombre(i.estado) + ((i.cantidad ?? 1) > 1 ? " · \(i.cantidad ?? 1)" : "")
    }

    private func textoHoy(_ c: Inv.Cambio) -> String {
        guard let h = c.hoy else { return "Hoy · no está" }
        if let e = c.entrega, (h.cantidad ?? 1) != (e.cantidad ?? 1) { return "Hoy · \(Formato.cantidad(h.cantidad ?? 1, "unidad", "unidades"))" }
        return "Hoy · \(Inv.nombre(h.estado))"
    }

    private func grave(_ c: Inv.Cambio) -> Bool {
        guard let h = c.hoy else { return true }
        guard let e = c.entrega else { return false }
        return (h.cantidad ?? 1) < (e.cantidad ?? 1) || (Inv.grupo(h.estado) == "malo" && Inv.grupo(e.estado) == "bueno")
    }

    // MARK: Decisiones

    private func decision(_ c: Inv.Cambio) -> DecisionDevolucion {
        decisiones[c.clave] ?? DecisionDevolucion(quien: c.desgaste ? "desgaste" : c.empeoro ? "inquilino" : "dueno", importe: nil)
    }

    private func elegir(_ c: Inv.Cambio, _ quien: String) {
        var d = decision(c)
        d.quien = quien
        decisiones[c.clave] = d
        guardar()
    }

    private func importe(_ c: Inv.Cambio, _ texto: String) {
        let n = Double(texto.filter(\.isNumber)) ?? 0
        var d = decision(c)
        d.importe = n > 0 ? n : nil
        decisiones[c.clave] = d
        guardar()
    }

    /// Se guarda solo, al ratito de elegir (el importe se escribe de a una cifra).
    private func guardar() {
        espera?.cancel()
        guard let e = entrada else { return }
        let ruta = "/v1/propiedades/\(propiedad)/actas/\(e.id)/devolucion"
        espera = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            let todo = decisiones
            do {
                try await estado.cola.enviar("PUT", ruta, todo, etiqueta: "Devolución de \(prop?.direccion ?? "")")
            } catch {
                Inv.errorConReintento(estado, error) { guardar() }
            }
            espera = nil
        }
    }

    // MARK: Datos

    private func cargar() async {
        let p: Propiedad
        let l: [ItemInventario]
        let actas: [Acta]
        do {
            p = try await estado.api.get("/v1/propiedades/\(propiedad)")
            l = try await estado.api.get("/v1/propiedades/\(propiedad)/inventario")
            actas = try await estado.api.get("/v1/propiedades/\(propiedad)/actas")
        } catch let e as ErrorApi {
            if !cargado { error = e }
            return
        } catch { return }
        prop = p
        items = l
        let e = actas.first { $0.tipo == "entrada" }
        entrada = e
        salida = actas.first { $0.tipo == "salida" && (e?.contratoId == nil || $0.contratoId == e?.contratoId) }
        if let e {
            let d: [String: DecisionDevolucion] = (try? await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(e.id)/devolucion")) ?? [:]
            // Lo que otro cambió entra solo, salvo que justo haya algo propio por guardar.
            if espera == nil { decisiones = d }
            if let c = e.contratoId {
                contrato = try? await estado.api.get("/v1/contratos/\(c)")
            } else {
                let ks: [ContratoAPI] = (try? await estado.api.get("/v1/contratos", query: [.init(name: "propiedad", value: propiedad), .init(name: "limite", value: "5")])) ?? []
                contrato = ks.first
            }
        }
        error = nil
        cargado = true
    }

    /// Labra el acta de salida con las observaciones armadas (cada descuento con su importe y quién lo
    /// paga, y la cuenta del depósito) y lleva a firmarla.
    private func mandar() async {
        guard let e = entrada else { return }
        mandando = true
        defer { mandando = false }
        let lineas = cobrados.map { "\(Inv.rotulo($0.ambiente, $0.descripcion)): \(Formato.plata(decision($0).importe ?? 0, moneda)) a cargo de la parte inquilina." }
        let otros = cambios.filter { decision($0).quien != "inquilino" }.map {
            "\(Inv.rotulo($0.ambiente, $0.descripcion)): \(decision($0).quien == "desgaste" ? "desgaste por uso, no se descuenta" : "a cargo del dueño")."
        }
        var pie = ""
        if let dep = contrato?.deposito {
            pie = "Depósito \(Formato.plata(dep, moneda)); descuentos \(Formato.plata(descuentos, moneda)); a devolver \(Formato.plata(devolver ?? 0, moneda))."
        }
        let obs = (lineas + otros + [pie]).filter { !$0.isEmpty }.joined(separator: "\n")
        struct Cuerpo: Encodable { var tipo = "salida"; var contratoId: String?; var observaciones: String? }
        do {
            let a: Acta = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/actas",
                                                      Cuerpo(contratoId: e.contratoId, observaciones: obs.isEmpty ? nil : String(obs.prefix(5000))))
            estado.version += 1
            estado.abrir(AFirmas(id: "\(propiedad)/\(a.id)"))
        } catch {
            Inv.errorConReintento(estado, error) { Task { await mandar() } }
        }
    }

    private func actaPDF() async {
        guard let s = salida else { return }
        let a: Acta = (try? await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(s.id)")) ?? s
        let inmo: InmobiliariaActa? = try? await estado.api.get("/v1/inmobiliaria")
        var prop2: ContactoActa?
        if let pid = contrato?.propietarioId ?? prop?.propietarioId { prop2 = try? await estado.api.get("/v1/contactos/\(pid)") }
        let nombreInmo = inmo?.nombre ?? estado.inmobiliaria?.nombre ?? ""
        if let u = await Documentos.actaFirmada(a, direccion: prop?.direccion ?? prop?.nombre ?? "", barrio: prop?.barrio, inmobiliaria: inmo,
                                                inquilino: contrato?.contactoNombre, propietario: prop2?.nombre ?? contrato?.propietarioNombre,
                                                firmaInmobiliaria: "Por \(nombreInmo.replacingOccurrences(of: "Propiedades", with: "Prop."))", api: estado.api) {
            previo = ArchivoPrevio(url: u)
        } else {
            estado.avisar("No pudimos armar el PDF. Probá de nuevo.", ok: false)
        }
    }
}
