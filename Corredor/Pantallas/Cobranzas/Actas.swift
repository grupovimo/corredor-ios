import PhotosUI
import SwiftUI

/// Un ítem del inventario de una propiedad.
struct ItemInventario: Codable, Identifiable, Hashable {
    var id: String
    var ambiente: String
    var descripcion: String
    var cantidad: Int?
    var estado: String
    var notas: String?
    var fotos: [String]?
    var fotosUrl: [String]?

    static let estados = [("nuevo", "Nuevo"), ("muy_bueno", "Muy bueno"), ("bueno", "Bueno"), ("regular", "Regular"), ("malo", "Malo")]
}

/// Un acta con sus firmas. La API la llama «entrada» (entrega) o «salida» (devolución).
struct Acta: Codable, Identifiable, Hashable {
    struct Firma: Codable, Hashable { var nombre: String?; var trazo: String?; var en: Date? }
    /// Un ítem tal como quedó congelado al labrar el acta.
    struct Item: Codable, Hashable {
        var ambiente: String
        var descripcion: String
        var cantidad: Int?
        var estado: String
        var notas: String?
        var fotos: [String]?
        var fotosUrl: [String]?
    }
    var id: String
    var propiedadId: String?
    var contratoId: String?
    var tipo: String?
    var fecha: String?
    var items: [Item]?
    var observaciones: String?
    var firmas: [String: Firma]?
    var propiedadTitulo: String?
    var creadoEn: Date?

    var esSalida: Bool { tipo == "salida" }
    var tipoTexto: String { esSalida ? "Devolución" : "Entrega" }
}

/// 11A Recorrida por ambientes (web 14C): un ambiente por pantalla, el estado de cada ítem de un toque,
/// la foto de cada ítem con la cámara y la nota de voz manteniendo el micrófono. Cada cambio se guarda
/// solo; al final se labra el acta de entrega o, si ya hay entrada y falta la salida, se compara la
/// devolución con la entrega.
struct Inventario: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    /// «entrega» o «devolucion» para forzar el modo (web ?tipo=); nil decide solo.
    var tipoPedido: String? = nil
    @State private var items: [ItemInventario] = []
    @State private var actas: [Acta] = []
    @State private var cargado = false
    @State private var error: ErrorApi?
    /// El contrato de la propiedad (el vigente o el último), para atar el acta de entrega.
    @State private var contrato: ContratoAPI?
    @State private var prop: Propiedad?
    @State private var ambiente = ""
    /// El ítem elegido: la nota de voz va a ese.
    @State private var elegido: String?
    @State private var subiendo: Set<String> = []
    @State private var durNota: [String: Int] = [:]
    @State private var fotoDe: String?
    @State private var foto: PhotosPickerItem?
    @State private var camaraPara: String?
    @State private var sumando: String?
    @State private var nuevoItem = ""
    @State private var nuevoAmbiente = ""
    @State private var enviando = false
    @State private var labrando = false
    @State private var voz = NotaDeVoz()
    @State private var apretando = false
    @State private var apretadoDesde = Date()
    @State private var soltarIgnora = false

    private var ambientes: [String] { Inv.ambientes(items.map(\.ambiente)) }
    private var paso: Int { ambientes.firstIndex(of: ambiente) ?? 0 }
    private var ultimo: Bool { paso >= ambientes.count - 1 }
    private var entrada: Acta? { actas.first { $0.tipo == "entrada" } }
    private var salida: Acta? { actas.first { $0.tipo == "salida" } }
    private var tipo: String {
        if let t = tipoPedido, t == "entrega" || t == "devolucion" { return t }
        return entrada != nil && salida == nil ? "devolucion" : "entrega"
    }
    private var delAmbiente: [ItemInventario] { items.filter { $0.ambiente == ambiente } }
    private var direccion: String { prop?.direccion ?? prop?.nombre ?? "" }
    private var textoSeguir: String {
        if !ultimo { return "Seguir: \(ambientes[paso + 1])" }
        return tipo == "devolucion" ? "Comparar con la entrega" : "Labrar el acta de entrega"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !cargado, let error {
                    EstadoError(que: "el inventario", error: error) { Task { await cargar() } }
                } else if !cargado {
                    EsqueletoFilas(filas: 4)
                } else {
                    cabeza
                    if ambientes.isEmpty {
                        primerAmbiente
                    } else {
                        chipsAmbientes
                        listaItems
                        sumarBloque
                        Text(Formato.sinViudas("Los ítems salen del inventario anterior de esta propiedad. Las fotos llevan fecha y hora."))
                            .estilo(.footnote).foregroundStyle(C.texto3)
                    }
                    bloqueActas
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .safeAreaInset(edge: .bottom) { if cargado && !ambientes.isEmpty { pie } }
        .pantallaApilada(tipo == "devolucion" ? "Recorrida de devolución" : "Recorrida de entrega")
        .task(id: estado.version) { await cargar() }
        .photosPicker(isPresented: $elegirDeFototeca, selection: $foto, matching: .images)
        .onChange(of: foto) { _, i in
            guard let i, let id = fotoDe else { return }
            Task {
                do {
                    if let d = try await i.loadTransferable(type: Data.self) { await sumarFoto(d, a: id) }
                } catch { estado.avisar(error) }
                foto = nil
            }
        }
        .fullScreenCover(item: Binding(get: { camaraPara.map { CampoAlta(id: $0) } }, set: { camaraPara = $0?.id })) { c in
            Camara { d in Task { await sumarFoto(d, a: c.id) } }.ignoresSafeArea()
        }
    }

    // MARK: Partes de la pantalla

    private var cabeza: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tipo == "entrega" ? "Entrega" : "Devolución") · \(direccion)").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                    Text(ambientes.isEmpty ? "Primer ambiente" : ambiente).font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
                }
                Spacer()
                if !ambientes.isEmpty { Text("\(paso + 1) de \(ambientes.count)").estilo(.footnote).foregroundStyle(C.texto2) }
            }
            if !ambientes.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<ambientes.count, id: \.self) { k in
                        Capsule().fill(k < paso ? C.accion : k == paso ? C.oro : C.hundida).frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private var chipsAmbientes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ambientes, id: \.self) { a in
                    let n = items.filter { $0.ambiente == a }.count
                    Button { withAnimation { ambiente = a; elegido = nil } } label: {
                        HStack(spacing: 4) {
                            Text(a)
                            Text("\(n)").foregroundStyle(a == ambiente ? C.sobreAccion.opacity(0.7) : C.texto3)
                        }
                        .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                        .foregroundStyle(a == ambiente ? C.sobreAccion : C.texto)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(a == ambiente ? C.accion : C.superficie, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityLabel("\(a), \(Formato.cantidad(n, "ítem", "ítems"))")
                }
            }
        }
    }

    private var primerAmbiente: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Empezá por el primer ambiente").estilo(.subheadFuerte).foregroundStyle(C.texto)
            Text(Formato.sinViudas("Poné el ambiente y el primer ítem. Después sumás el resto caminando la casa.")).estilo(.footnote).foregroundStyle(C.texto2)
            if estado.escribe {
                TextField("Ambiente (Cocina, Living…)", text: $nuevoAmbiente).campoCorredor()
                TextField("Ítem (Anafe 4 hornallas)", text: $nuevoItem).campoCorredor()
                Button(enviando ? "Sumando…" : "Sumar") { Task { await sumar(ambienteNuevo: true) } }
                    .buttonStyle(BotonPrincipal())
                    .disabled(enviando || nuevoAmbiente.nonEmpty == nil || nuevoItem.nonEmpty == nil)
            }
        }
        .padding(14).tarjeta()
    }

    private var listaItems: some View {
        VStack(spacing: 0) {
            ForEach(Array(delAmbiente.enumerated()), id: \.element.id) { i, it in
                filaItem(it)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
        }
        .tarjeta()
    }

    private func filaItem(_ it: ItemInventario) -> some View {
        HStack(alignment: .top, spacing: 12) {
            fotoItem(it)
            VStack(alignment: .leading, spacing: 8) {
                Text(it.descripcion + ((it.cantidad ?? 1) > 1 ? " · \(it.cantidad ?? 1)" : ""))
                    .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                tresEstados(it)
                notaItem(it)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(elegido == it.id ? C.hundida.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { elegido = it.id }
    }

    @ViewBuilder private func fotoItem(_ it: ItemInventario) -> some View {
        let ultima = it.fotosUrl?.last
        let caja = ZStack {
            if let u = ultima { Foto(url: urlDeFoto(u)) } else {
                ZStack { C.hundida; Image(systemName: "camera").font(.system(size: 20)).foregroundStyle(C.accion) }
            }
            if subiendo.contains(it.id) { ZStack { Color.black.opacity(0.35); ProgressView().tint(.white) } }
        }
        .frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
        if estado.escribe {
            Menu {
                Button { elegido = it.id; camaraPara = it.id } label: { Label("Sacar foto", systemImage: "camera") }
                Button { elegido = it.id; fotoDe = it.id; elegirDeFototeca = true } label: { Label("Elegir de la fototeca", systemImage: "photo") }
            } label: { caja }
            .accessibilityLabel(ultima == nil ? "Sacar una foto de \(it.descripcion)" : "Sumar otra foto de \(it.descripcion)")
        } else {
            caja
        }
    }

    @State private var elegirDeFototeca = false

    private func tresEstados(_ it: ItemInventario) -> some View {
        HStack(spacing: 6) {
            ForEach([("bueno", "Bueno"), ("regular", "Regular"), ("malo", "Malo")], id: \.0) { k, n in
                let on = Inv.grupo(it.estado) == k
                Button { Task { await poner(it, estado: k) } } label: {
                    HStack(spacing: 3) {
                        if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        Text(n)
                    }
                    .font(Estilo(tamano: 14, peso: on ? .bold : .medium, relativo: .footnote).font)
                    .foregroundStyle(on ? (k == "malo" ? C.errorTinta : k == "regular" ? C.avisoTinta : C.okTinta) : C.texto)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(on ? (k == "malo" ? C.errorFondo : k == "regular" ? C.avisoFondo : C.okFondo) : C.hundida, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(Presionable()).disabled(!estado.escribe)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func notaItem(_ it: ItemInventario) -> some View {
        if voz.grabando && elegido == it.id {
            Label("\(voz.texto.isEmpty ? "Escuchando…" : voz.texto) · \(NotaDeVoz.duracion(voz.segundos))", systemImage: "waveform")
                .estilo(.footnote).foregroundStyle(C.errorTinta)
        } else if estado.escribe {
            TextField("Nota (opcional)", text: Binding(get: { items.first { $0.id == it.id }?.notas ?? "" },
                                                        set: { n in if let x = items.firstIndex(where: { $0.id == it.id }) { items[x].notas = n } }), axis: .vertical)
                .estilo(.texto14).foregroundStyle(C.texto2)
                .submitLabel(.done)
                .onSubmit { Task { await guardarNotaEscrita(it.id) } }
            if let d = durNota[it.id] {
                Label("Nota de voz · \(NotaDeVoz.duracion(d))", systemImage: "waveform").estilo(.footnote).foregroundStyle(C.texto3)
            }
        } else if let n = it.notas?.nonEmpty {
            Label("«\(n)»", systemImage: "waveform").estilo(.footnote).foregroundStyle(C.texto2)
        }
    }

    @ViewBuilder private var sumarBloque: some View {
        if estado.escribe {
            if let s = sumando {
                VStack(alignment: .leading, spacing: 8) {
                    if s == "ambiente" { TextField("Ambiente nuevo (Baño de servicio)", text: $nuevoAmbiente).campoCorredor() }
                    TextField("Ítem (Alacena superior)", text: $nuevoItem).campoCorredor().submitLabel(.done)
                        .onSubmit { Task { await sumar(ambienteNuevo: s == "ambiente") } }
                    HStack(spacing: 8) {
                        Button(enviando ? "Sumando…" : "Sumar") { Task { await sumar(ambienteNuevo: s == "ambiente") } }
                            .buttonStyle(BotonAccion())
                            .disabled(enviando || nuevoItem.nonEmpty == nil || (s == "ambiente" && nuevoAmbiente.nonEmpty == nil))
                        Button("Cancelar") { sumando = nil }.buttonStyle(BotonHundido())
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button { sumando = "item" } label: { Label("Sumar ítem a \(ambiente)", systemImage: "plus") }.buttonStyle(BotonHundido())
                    Button("Otro ambiente") { sumando = "ambiente" }.buttonStyle(BotonHundido())
                }
            }
        }
    }

    private var pie: some View {
        HStack(spacing: 10) {
            if estado.escribe { microfono }
            Button {
                Task { await terminar() }
            } label: {
                HStack(spacing: 6) {
                    Text(labrando ? "Labrando el acta…" : textoSeguir).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(labrando || (ultimo && tipo == "entrega" && !estado.escribe))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    /// Mantener apretado para grabar (o tocar para empezar y tocar para terminar).
    private var microfono: some View {
        Image(systemName: "mic.fill").font(.system(size: 24))
            .foregroundStyle(voz.grabando ? .white : C.accion)
            .frame(width: 52, height: 52)
            .background(voz.grabando ? C.error : C.hundida, in: Circle())
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !apretando else { return }
                    apretando = true
                    apretadoDesde = Date()
                    if voz.grabando {
                        soltarIgnora = true
                        Task { await terminarNota() }
                    } else {
                        Task { await empezarNota() }
                    }
                }
                .onEnded { _ in
                    apretando = false
                    if soltarIgnora { soltarIgnora = false; return }
                    if Date().timeIntervalSince(apretadoDesde) > 0.6 { Task { await terminarNota() } }
                })
            .accessibilityElement()
            .accessibilityLabel(voz.grabando ? "Terminar la nota de voz" : "Mantener para grabar una nota de voz")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { if voz.grabando { await terminarNota() } else { await empezarNota() } } }
    }

    @ViewBuilder private var bloqueActas: some View {
        if !actas.isEmpty || (entrada != nil && salida == nil) {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Actas")
                VStack(spacing: 0) {
                    ForEach(Array(actas.enumerated()), id: \.element.id) { i, a in
                        let firmada = (a.firmas?.count ?? 0) >= 3
                        Button { estado.abrir(AFirmas(id: "\(propiedad)/\(a.id)")) } label: {
                            HStack(spacing: 12) {
                                IconoTono(icono: "doc.text", tono: .azul, tam: 34)
                                Text(a.tipo == "entrada" ? "Acta de entrega" : "Acta de devolución").estilo(.filaLista).foregroundStyle(C.texto)
                                Spacer()
                                Text(firmada ? "firmada" : "faltan firmas").estilo(.footnote).foregroundStyle(firmada ? C.okTinta : C.avisoTinta)
                                Chevron()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                    if entrada != nil && salida == nil {
                        Button { estado.abrir(ADevolucion(id: propiedad)) } label: {
                            HStack(spacing: 12) {
                                IconoTono(icono: "arrow.left.arrow.right", tono: .oro, tam: 34)
                                Text("Comparar con la entrega").estilo(.filaLista).foregroundStyle(C.texto)
                                Spacer()
                                Chevron()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if !actas.isEmpty { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
        }
    }

    // MARK: Datos

    private func cargar() async {
        do {
            let p: Propiedad = try await estado.api.get("/v1/propiedades/\(propiedad)")
            let l: [ItemInventario] = try await estado.api.get("/v1/propiedades/\(propiedad)/inventario")
            let a: [Acta] = try await estado.api.get("/v1/propiedades/\(propiedad)/actas")
            prop = p
            items = l
            actas = a
            error = nil
            cargado = true
        } catch let e as ErrorApi {
            if !cargado { error = e }
            return
        } catch { return }
        let ks: [ContratoAPI] = (try? await estado.api.get("/v1/contratos", query: [.init(name: "propiedad", value: propiedad), .init(name: "limite", value: "5")])) ?? []
        contrato = ks.first { $0.estado == "vigente" } ?? ks.first
        if ambiente.isEmpty || !ambientes.contains(ambiente) { ambiente = ambientes.first ?? "" }
    }

    private struct Cuerpo: Encodable { var ambiente: String; var descripcion: String; var cantidad: Int; var estado: String; var notas: String?; var fotos: [String] }

    private func cuerpo(_ it: ItemInventario) -> Cuerpo {
        Cuerpo(ambiente: it.ambiente, descripcion: it.descripcion, cantidad: it.cantidad ?? 1, estado: it.estado.isEmpty ? "bueno" : it.estado,
               notas: it.notas?.nonEmpty, fotos: it.fotos ?? [])
    }

    private func reemplazar(_ it: ItemInventario) {
        if let i = items.firstIndex(where: { $0.id == it.id }) { items[i] = it }
    }

    /// Cambio optimista: se ve al toque; sin señal queda en la cola; si la API no lo guarda, vuelve
    /// atrás y ofrece «Reintentar».
    private func guardar(_ nuevo: ItemInventario, antes: ItemInventario) async {
        reemplazar(nuevo)
        do {
            try await estado.cola.enviar("PUT", "/v1/propiedades/\(propiedad)/inventario/\(nuevo.id)", cuerpo(nuevo), etiqueta: "Inventario de \(direccion)")
        } catch {
            reemplazar(antes)
            Inv.errorConReintento(estado, error) { Task { await guardar(nuevo, antes: antes) } }
        }
    }

    private func poner(_ it: ItemInventario, estado nuevo: String) async {
        elegido = it.id
        guard let actual = items.first(where: { $0.id == it.id }), Inv.grupo(actual.estado) != nuevo else { return }
        var x = actual
        x.estado = nuevo
        Haptico.seleccion()
        await guardar(x, antes: actual)
    }

    private func guardarNotaEscrita(_ id: String) async {
        guard let it = items.first(where: { $0.id == id }) else { return }
        var antes = it
        antes.notas = nil
        await guardar(it, antes: antes)
    }

    private func sumarFoto(_ d: Data, a id: String) async {
        elegido = id
        subiendo.insert(id)
        defer { subiendo.remove(id) }
        do {
            let f = try await estado.api.subir(UIImage(data: d)?.jpegData(compressionQuality: 0.8) ?? d, nombre: "inventario.jpg", tipo: "image/jpeg", uso: "foto")
            guard let ahora = items.first(where: { $0.id == id }) else { return }
            var x = ahora
            x.fotos = (x.fotos ?? []) + [f.id]
            x.fotosUrl = (x.fotosUrl ?? []) + [f.url ?? ""]
            await guardar(x, antes: ahora)
        } catch let e as ErrorApi where e.sinConexion {
            estado.avisar("No se pudo subir la foto: no hay señal.", ok: false)
        } catch { estado.avisar(error) }
    }

    private func empezarNota() async {
        guard let destino = elegido ?? delAmbiente.first?.id else {
            estado.avisar("Sumá un ítem primero: la nota va con un ítem.")
            return
        }
        elegido = destino
        if let e = await voz.empezar() { estado.avisar(e, ok: false) }
    }

    private func terminarNota() async {
        guard voz.grabando else { return }
        let id = elegido
        let g = await voz.terminar()
        guard let id, let i = items.first(where: { $0.id == id }) else { return }
        if !g.texto.isEmpty {
            durNota[id] = g.segundos
            var x = i
            x.notas = String(g.texto.prefix(1000))
            await guardar(x, antes: i)
        } else if g.audio == nil {
            estado.avisar("No escuchamos nada. Probá de nuevo, más cerca.")
        }
        guard let u = g.audio else { return }
        struct Grabacion: Encodable { var transcripcion: String; var audioId: String; var audioSegundos: Int }
        do {
            let d = try Data(contentsOf: u)
            let a = try await estado.api.subir(d, nombre: "nota.m4a", tipo: "audio/mp4", uso: "audio")
            try await estado.api.hacer("POST", "/v1/propiedades/\(propiedad)/grabaciones",
                                       Grabacion(transcripcion: g.texto.isEmpty ? "Nota de voz de \(i.descripcion)" : g.texto, audioId: a.id, audioSegundos: g.segundos))
            durNota[id] = g.segundos
        } catch {
            estado.avisar("El audio no se subió; la nota quedó escrita.")
        }
    }

    /// Sumar un ítem al ambiente que se ve o a uno nuevo; el aviso deja deshacerlo (lo borra).
    private func sumar(ambienteNuevo: Bool) async {
        let amb = (ambienteNuevo || ambiente.isEmpty) ? nuevoAmbiente.trimmingCharacters(in: .whitespaces) : ambiente
        let desc = nuevoItem.trimmingCharacters(in: .whitespaces)
        guard !amb.isEmpty, !desc.isEmpty else { return }
        enviando = true
        defer { enviando = false }
        struct Nuevo: Encodable { var ambiente: String; var descripcion: String; var estado = "bueno" }
        do {
            let it: ItemInventario = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/inventario", Nuevo(ambiente: amb, descripcion: desc))
            items.append(it)
            nuevoItem = ""
            Haptico.exito()
            let api = estado.api
            let prop = propiedad
            estado.avisar("\(it.descripcion) sumado a \(amb)") {
                Task {
                    do {
                        try await api.hacer("DELETE", "/v1/propiedades/\(prop)/inventario/\(it.id)")
                        items.removeAll { $0.id == it.id }
                    } catch { estado.avisar(error) }
                }
            }
            if amb != ambiente {
                sumando = nil
                nuevoAmbiente = ""
                withAnimation { ambiente = amb }
            }
        } catch { estado.avisar(error) }
    }

    private func terminar() async {
        if !ultimo {
            withAnimation { ambiente = ambientes[paso + 1]; elegido = nil }
            return
        }
        if tipo == "devolucion" {
            estado.abrir(ADevolucion(id: propiedad))
            return
        }
        labrando = true
        defer { labrando = false }
        struct Labrar: Encodable { var tipo = "entrada"; var contratoId: String? }
        do {
            let a: Acta = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/actas",
                                                      Labrar(contratoId: entrada == nil ? contrato?.id : nil))
            estado.version += 1
            estado.abrir(AFirmas(id: "\(propiedad)/\(a.id)"))
        } catch {
            Inv.errorConReintento(estado, error) { Task { await terminar() } }
        }
    }
}

/// 11B–11C El acta (web 14): la hoja con el membrete (y la matrícula), los ítems congelados y las tres
/// firmas. Una firma pendiente se toca y se firma acá (el teléfono pasa de mano en mano); «Pedir firma»
/// le manda por WhatsApp a quien falta un link para firmar desde su celular (vence en 7 días; se puede
/// dar de baja). Imprimir saca la misma hoja en PDF en cualquier momento.
struct Firmas: View {
    @Environment(Estado.self) private var estado
    /// «propiedad/acta».
    var clave: String
    @State private var acta: Acta?
    @State private var error: ErrorApi?
    @State private var prop: Propiedad?
    @State private var inmo: InmobiliariaActa?
    @State private var links: [LinkFirma] = []
    @State private var inquilino: ContactoActa?
    @State private var propietario: ContactoActa?
    @State private var firmando: String?
    @State private var pidiendo = false
    @State private var previo: ArchivoPrevio?

    private var propiedad: String { String(clave.split(separator: "/").first ?? "") }
    private var actaId: String { String(clave.split(separator: "/").last ?? "") }

    struct Parte: Hashable { var parte: String; var rotulo: String; var nombre: String; var telefono: String? }

    private var inmoNombre: String { inmo?.nombre ?? estado.inmobiliaria?.nombre ?? "" }
    private var inmoCorta: String { inmoNombre.replacingOccurrences(of: "Propiedades", with: "Prop.") }

    private var partes: [Parte] {
        [Parte(parte: "inquilino", rotulo: "Inquilina/o", nombre: inquilino?.nombre ?? "", telefono: inquilino?.telefono),
         Parte(parte: "propietario", rotulo: "Propietario", nombre: propietario?.nombre ?? "", telefono: propietario?.telefono),
         Parte(parte: "inmobiliaria", rotulo: "Por \(inmoCorta)", nombre: estado.usuario?.completo ?? "", telefono: nil)]
    }

    private var pendiente: Parte? {
        partes.first { $0.parte != "inmobiliaria" && acta?.firmas?[$0.parte] == nil && ($0.telefono?.nonEmpty != nil) }
    }

    private var titulo: String { acta?.tipo == "salida" ? "Acta de devolución e inventario" : "Acta de entrega e inventario" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let acta {
                    hoja(acta)
                    linksVigentes(acta)
                    acciones(acta)
                } else if let error {
                    EstadoError(que: "el acta", error: error) { Task { await cargar() } }
                } else {
                    EsqueletoFilas(filas: 6)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .pantallaApilada(acta?.tipo == "salida" ? "Acta de devolución" : "Acta de entrega")
        .vistaPrevia($previo)
        .toolbar {
            if acta != nil {
                Button { Task { await imprimir() } } label: { Image(systemName: "printer") }.accessibilityLabel("Imprimir")
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(item: Binding(get: { firmando.map { CampoAlta(id: $0) } }, set: { firmando = $0?.id })) { p in
            let parte = partes.first { $0.parte == p.id }
            HojaFirma(parte: p.id, titulo: tituloFirma(p.id), nombreInicial: parte?.nombre ?? "") { nombre, trazo in
                Task { await firmar(p.id, nombre, trazo) }
            }
            .presentationDetents([.large])
        }
    }

    private func tituloFirma(_ p: String) -> String {
        p == "inmobiliaria" ? "Firma por \(inmoNombre)" : "Firma \(p == "inquilino" ? "de la parte inquilina" : "del propietario")"
    }

    // MARK: La hoja

    private static let tinta = Color(hex: 0x18201D)
    private static let gris = Color(hex: 0x6B6457)
    private static let linea = Color(hex: 0xE3DDCF)

    private func hoja(_ a: Acta) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            membrete(a)
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(Estilo(tamano: 20, peso: .bold, tracking: -0.02, relativo: .title3).font)
                Text(lineaLugar(a)).font(Estilo(tamano: 13, peso: .regular, relativo: .footnote).font).foregroundStyle(Self.gris)
            }
            partesTexto(a).font(Estilo(tamano: 14, peso: .regular, relativo: .subheadline).font)
            tabla(a)
            firmasHoja(a)
        }
        .foregroundStyle(Self.tinta)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFFEFB), in: .rect(cornerRadius: 6, style: .continuous))
        .sombraE2()
    }

    private func membrete(_ a: Acta) -> some View {
        HStack(spacing: 10) {
            Text(String(inmoNombre.prefix(1))).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                .foregroundStyle(Color(hex: 0xE9DCC3)).frame(width: 36, height: 36).background(Color(hex: 0x1E3A5F), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(inmoNombre).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font)
                if let m = inmo?.matricula { Text(m).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(Self.gris) }
            }
            Spacer()
            Text("ACTA · \(Inv.numerica(a.fecha))").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.gris)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Self.linea).frame(height: 1) }
    }

    private func lineaLugar(_ a: Acta) -> String {
        var s = prop?.direccion ?? prop?.nombre ?? ""
        if let b = prop?.barrio?.nonEmpty { s += " · \(b)" }
        if let f = a.fecha.flatMap(Fecha.dia) {
            s += " · \(Formato.fechaLarga(f))"
            if let c = a.creadoEn, Formato.diaISO(c) == String((a.fecha ?? "").prefix(10)) { s += ", \(Formato.horaDe(c))" }
        }
        return s
    }

    private func partesTexto(_ a: Acta) -> Text {
        var t = Text("")
        if let i = inquilino { t = t + Text("Inquilina/o: ") + Text(i.nombre).bold() + Text(". ") }
        if let p = propietario { t = t + Text("Propietario: ") + Text(p.nombre).bold() + Text(". ") }
        if let o = a.observaciones?.nonEmpty { t = t + Text(o) }
        return t
    }

    private func tabla(_ a: Acta) -> some View {
        let filas = Self.filas(a.items ?? [])
        return VStack(spacing: 0) {
            HStack {
                Text("AMBIENTE · ÍTEM")
                Spacer()
                Text("ESTADO · FOTO")
            }
            .font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).tracking(0.4).foregroundStyle(Self.gris)
            .padding(.vertical, 6)
            if filas.isEmpty {
                Text("El inventario estaba vacío cuando se labró el acta.").font(Estilo(tamano: 13, peso: .regular, relativo: .footnote).font)
                    .foregroundStyle(Self.gris).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(filas.enumerated()), id: \.offset) { _, f in
                let ojo = f.item.estado == "regular" || f.item.estado == "malo"
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.item.ambiente).font(Estilo(tamano: 11, peso: .semibold, relativo: .caption2).font).foregroundStyle(Self.gris)
                        Text(Self.textoItem(f.item)).font(Estilo(tamano: 13, peso: .regular, relativo: .footnote).font)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Inv.nombre(f.item.estado)).font(Estilo(tamano: 13, peso: ojo ? .bold : .regular, relativo: .footnote).font)
                        Text(f.codigo).font(.system(size: 11, design: .monospaced)).foregroundStyle(Self.gris)
                    }
                }
                .padding(.vertical, 7)
                .background(ojo ? Color(hex: 0xFBF1DC) : Color.clear)
                .overlay(alignment: .top) { Rectangle().fill(Self.linea).frame(height: 0.5) }
            }
        }
    }

    /// Las fotos del acta se numeran en orden: F-01, F-02…
    static func filas(_ items: [Acta.Item]) -> [(item: Acta.Item, codigo: String)] {
        var n = 0
        return items.map { i in
            if (i.fotos ?? []).isEmpty { return (i, "—") }
            n += 1
            return (i, String(format: "F-%02d", n))
        }
    }

    static func textoItem(_ i: Acta.Item) -> String {
        var s = i.descripcion
        if (i.cantidad ?? 1) > 1 { s += " (\(i.cantidad ?? 1))" }
        if let n = i.notas?.nonEmpty { s += " · " + n.prefix(1).lowercased() + n.dropFirst() }
        return s
    }

    private func firmasHoja(_ a: Acta) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(partes, id: \.parte) { p in
                VStack(spacing: 4) {
                    if let f = a.firmas?[p.parte], let t = f.trazo {
                        TrazoFirma(trazo: t).environment(\.colorScheme, .light).frame(height: 54)
                            .contextMenu {
                                if estado.escribe {
                                    Button(role: .destructive) { Task { await borrarFirma(p.parte) } } label: { Label("Borrar la firma", systemImage: "trash") }
                                }
                            }
                    } else {
                        Button { firmando = p.parte } label: {
                            Text("Firma pendiente").font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.azulTinta)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Self.linea, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(Presionable()).disabled(!estado.escribe)
                    }
                    Rectangle().fill(Self.tinta.opacity(0.4)).frame(height: 0.5)
                    Text(p.rotulo).font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font).foregroundStyle(Self.gris).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func linksVigentes(_ a: Acta) -> some View {
        ForEach(partes, id: \.parte) { p in
            if let l = links.first(where: { $0.parte == p.parte && a.firmas?[p.parte] == nil }) {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(C.azulTinta)
                    Text("Le mandamos el link a \(Inv.primerNombre(p.nombre).nonEmpty ?? p.rotulo.lowercased()) · vence el\u{00A0}\(String(Inv.numerica(l.venceEn).prefix(5)))")
                        .estilo(.footnote).foregroundStyle(C.texto2)
                    Spacer()
                    if estado.escribe {
                        Button("Dar de baja") { Task { await darDeBaja(l) } }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder private func acciones(_ a: Acta) -> some View {
        VStack(spacing: 8) {
            if estado.escribe, let p = pendiente {
                Button { Task { await pedirFirma(p) } } label: { Label(pidiendo ? "Armando el link…" : "Pedir firma a \(Inv.primerNombre(p.nombre))", systemImage: "bubble.left") }
                    .buttonStyle(BotonPrincipal()).disabled(pidiendo)
            }
            if estado.escribe {
                // Las partes sin teléfono cargado: el link igual, para mandarlo por donde sea.
                ForEach(partes.filter { $0.parte != "inmobiliaria" && a.firmas?[$0.parte] == nil && $0.parte != pendiente?.parte }, id: \.parte) { p in
                    Button("Mandarle un link a \(p.nombre.nonEmpty.map(Inv.primerNombre) ?? p.rotulo.lowercased()) para que firme desde su teléfono") {
                        Task { await pedirFirma(p) }
                    }
                    .buttonStyle(BotonTexto(alto: 44)).font(Estilo.subheadFuerte.font)
                }
            }
            HStack(spacing: 8) {
                Button { Task { await imprimir() } } label: { Label("Imprimir", systemImage: "printer") }.buttonStyle(BotonHundido())
                Button { estado.abrir(AInventario(id: propiedad)) } label: { Label("Recorrida", systemImage: "figure.walk") }.buttonStyle(BotonHundido())
            }
            if a.tipo == "entrada" {
                Button { estado.abrir(ADevolucion(id: propiedad)) } label: { Label("Comparar la devolución", systemImage: "arrow.left.arrow.right") }.buttonStyle(BotonHundido())
            }
        }
    }

    // MARK: Datos

    private func cargar() async {
        do {
            let a: Acta = try await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(actaId)")
            acta = a
            error = nil
        } catch let e as ErrorApi {
            if acta == nil { error = e }
            return
        } catch { return }
        prop = try? await estado.api.get("/v1/propiedades/\(propiedad)")
        inmo = try? await estado.api.get("/v1/inmobiliaria")
        let l: [LinkFirma] = (try? await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(actaId)/links")) ?? []
        links = l.filter { $0.estado == "vigente" }
        var k: ContratoAPI?
        if let c = acta?.contratoId { k = try? await estado.api.get("/v1/contratos/\(c)") }
        if let pid = k?.propietarioId ?? prop?.propietarioId {
            propietario = try? await estado.api.get("/v1/contactos/\(pid)")
        }
        if let cid = k?.contactoId {
            inquilino = try? await estado.api.get("/v1/contactos/\(cid)")
        }
        if inquilino == nil, let n = k?.contactoNombre { inquilino = ContactoActa(id: k?.contactoId ?? "", nombre: n, telefono: nil) }
    }

    private func firmar(_ parte: String, _ nombre: String, _ trazo: String) async {
        struct Cuerpo: Encodable { var nombre: String; var trazo: String }
        let ruta = "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(parte)"
        do {
            let a: Acta = try await estado.api.enviar("PUT", ruta, Cuerpo(nombre: nombre, trazo: trazo))
            acta = a
            Haptico.exito()
            let api = estado.api
            estado.avisar("Firmó \(nombre.trimmingCharacters(in: .whitespaces))") {
                Task {
                    do {
                        let b: Acta = try await api.enviar("DELETE", ruta, [String: String]())
                        acta = b
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func borrarFirma(_ parte: String) async {
        do {
            let a: Acta = try await estado.api.enviar("DELETE", "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(parte)", [String: String]())
            acta = a
        } catch { estado.avisar(error) }
    }

    /// Un link nuevo para esa parte (revoca el anterior) y el WhatsApp a su teléfono con el link.
    private func pedirFirma(_ p: Parte) async {
        pidiendo = true
        defer { pidiendo = false }
        do {
            let l: LinkFirma = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(p.parte)/link", [String: String]())
            let dir = prop?.direccion ?? prop?.nombre ?? ""
            let n = Inv.primerNombre(p.nombre)
            let texto = "Hola \(n), te escribo de \(inmoNombre). El acta de \(acta?.tipo == "entrada" ? "entrega" : "devolución") de \(dir) está lista: falta tu firma. La podés firmar desde el celular acá: \(l.url ?? "")"
            Afuera.whatsapp(p.telefono, texto: texto)
            let todos: [LinkFirma] = (try? await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(actaId)/links")) ?? []
            links = todos.filter { $0.estado == "vigente" }
        } catch {
            Inv.errorConReintento(estado, error) { Task { await pedirFirma(p) } }
        }
    }

    private func darDeBaja(_ l: LinkFirma) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/actas/\(actaId)/links/\(l.id)")
            links.removeAll { $0.id == l.id }
            estado.avisar("El link para firmar ya no abre")
        } catch { estado.avisar(error) }
    }

    private func imprimir() async {
        guard let acta else { return }
        if let u = await Documentos.actaFirmada(acta, direccion: prop?.direccion ?? prop?.nombre ?? "", barrio: prop?.barrio, inmobiliaria: inmo,
                                                inquilino: inquilino?.nombre, propietario: propietario?.nombre, firmaInmobiliaria: "Por \(inmoCorta)",
                                                api: estado.api) {
            previo = ArchivoPrevio(url: u)
        } else {
            estado.avisar("No pudimos armar el PDF. Probá de nuevo.", ok: false)
        }
    }
}

/// Una firma guardada (path SVG sobre 600 × 200).
struct TrazoFirma: View {
    var trazo: String
    var body: some View {
        GeometryReader { g in
            Path { p in
                let esc = min(g.size.width / 600, g.size.height / 200)
                let dx = (g.size.width - 600 * esc) / 2, dy = (g.size.height - 200 * esc) / 2
                let t = trazo.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
                var i = 0
                while i < t.count {
                    let c = t[i]
                    if (c == "M" || c == "L"), i + 2 < t.count, let x = Double(t[i + 1]), let y = Double(t[i + 2]) {
                        let pt = CGPoint(x: dx + x * esc, y: dy + y * esc)
                        if c == "M" { p.move(to: pt) } else { p.addLine(to: pt) }
                        i += 3
                    } else { i += 1 }
                }
            }
            .stroke(C.texto, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Firma")
    }
}

/// La hoja para firmar con el dedo: el nombre (completado con el de la parte) y el recuadro.
struct HojaFirma: View {
    @Environment(\.dismiss) private var cerrar
    var parte: String
    var titulo: String = ""
    var nombreInicial: String = ""
    var alFirmar: (String, String) -> Void
    @State private var nombre = ""
    @State private var trazos: [[CGPoint]] = []
    @State private var actual: [CGPoint] = []
    @State private var tam = CGSize(width: 600, height: 200)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titulo.isEmpty ? "Firma del \(parte)" : titulo).estilo(.titulo3)
            Text(Formato.sinViudas("Firmá con el dedo en el recuadro. Queda en el acta con la fecha y la hora.")).estilo(.footnote).foregroundStyle(C.texto2)
            Etiquetado("Nombre de quien firma") {
                TextField("Nombre y apellido", text: $nombre).textContentType(.name).campoCorredor()
            }
            GeometryReader { g in
                Canvas { ctx, _ in
                    for t in trazos + [actual] where t.count > 1 {
                        var p = Path()
                        p.addLines(t)
                        ctx.stroke(p, with: .color(C.texto), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .background(Color.tema(0xFAF8F3, 0x1A2420), in: .rect(cornerRadius: 12))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { actual.append($0.location) }
                    .onEnded { _ in trazos.append(actual); actual = [] })
                .onAppear { tam = g.size }
            }
            .frame(height: 180)
            Button("Borrar el trazo") { trazos = [] }.buttonStyle(BotonTexto(alto: 40)).disabled(trazos.isEmpty)
            HStack {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonHundido())
                Button("Guardar la firma") {
                    alFirmar(nombre.trimmingCharacters(in: .whitespaces), svg())
                    cerrar()
                }
                .buttonStyle(BotonAccion()).disabled(nombre.trimmingCharacters(in: .whitespaces).count < 2 || trazos.isEmpty)
            }
        }
        .padding(16)
        .onAppear { if nombre.isEmpty { nombre = nombreInicial } }
    }

    /// Los trazos como path SVG en el lienzo de 600 × 200 que guarda la API.
    private func svg() -> String {
        let ex = 600 / max(tam.width, 1), ey = 200 / max(tam.height, 1)
        return trazos.filter { $0.count > 1 }.map { t in
            t.enumerated().map { i, p in "\(i == 0 ? "M" : "L") \(Int(p.x * ex)) \(Int(p.y * ey))" }.joined(separator: " ")
        }.joined(separator: " ")
    }
}

struct GrabacionAPI: Codable, Identifiable, Hashable {
    var id: String
    var transcripcion: String?
    var audioUrl: String?
    var audioSegundos: Int?
    var itemsCreados: Int?
    var creadaPor: String?
    /// La API la manda como `creadoEn`.
    var creadoEn: Date?
    var creadaEn: Date? { creadoEn }
}

/// Dictar la recorrida: se graba la voz, se transcribe en el iPhone y la API arma los ítems del
/// inventario («living: paredes bien, una mancha de humedad en el techo…»).
struct DictarInventario: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: String
    /// «entrada» o «salida» para respaldar el acta (la API lo pide junto con el contrato); nil si no hay contrato.
    var tipoActa: String? = nil
    var contrato: String? = nil
    var alTerminar: (Int) -> Void
    @State private var dictado = Dictado()
    @State private var enviando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictá la recorrida").estilo(.titulo)
            Text(Formato.sinViudas("Ambiente por ambiente: qué hay y cómo está. Armamos los ítems del inventario.")).estilo(.subhead).foregroundStyle(C.texto2)
            ScrollView {
                Text(dictado.texto.isEmpty ? "«Living: paredes bien, piso de madera con un rayón, una mancha de humedad en el techo…»" : dictado.texto)
                    .estilo(.body16).foregroundStyle(dictado.texto.isEmpty ? C.texto3 : C.texto).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(14).background(C.hundida, in: .rect(cornerRadius: 16))
            if dictado.grabando {
                Button("Terminar") { Task { await terminar() } }.buttonStyle(BotonPrincipal())
            } else if dictado.texto.isEmpty {
                Button { dictado.empezar(base: "") } label: { Label("Empezar a dictar", systemImage: "mic.fill") }.buttonStyle(BotonPrincipal())
            } else {
                Button(enviando ? "Armando los ítems…" : "Armar el inventario") { Task { await enviar() } }.buttonStyle(BotonPrincipal()).disabled(enviando)
                Button("Dictar de nuevo") { dictado.texto = ""; dictado.empezar(base: "") }.buttonStyle(BotonTexto())
            }
        }
        .padding(20)
        .background(C.fondo)
    }

    private func terminar() async { dictado.parar() }

    private func enviar() async {
        enviando = true
        defer { enviando = false }
        do {
            struct C: Encodable { var transcripcion: String; var tipoActa: String?; var contratoId: String?; var armar = true }
            let ok = tipoActa == "entrada" || tipoActa == "salida"
            // Con `armar`, la API arma los ítems desde el texto y responde {grabacion, items}.
            struct Guardada: Decodable { var grabacion: GrabacionAPI; var items: [ItemInventario]? }
            let g: Guardada = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/grabaciones",
                                                          C(transcripcion: dictado.texto, tipoActa: ok && contrato != nil ? tipoActa : nil, contratoId: ok ? contrato : nil))
            Haptico.exito()
            alTerminar(g.grabacion.itemsCreados ?? g.items?.count ?? 0)
            cerrar()
        } catch { estado.avisar(error) }
    }
}

/// Las recorridas dictadas de una propiedad: escuchar el audio, leer la transcripción y cuántos ítems armó.
struct Grabaciones: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var lista: [GrabacionAPI] = []
    @State private var dictando = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if lista.isEmpty { EstadoVacio(icono: "waveform", titulo: "Sin recorridas dictadas", texto: "Dictá la recorrida y armamos el inventario.", accion: estado.escribe ? ("Dictar", { dictando = true }) : nil).padding(.top, 40) }
                ForEach(lista) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(g.creadaEn.map { Formato.cuando($0) } ?? "").estilo(.footnote).foregroundStyle(C.texto3)
                            Spacer()
                            if let n = g.itemsCreados { Text(Formato.cantidad(n, "ítem", "ítems")).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.okTinta) }
                        }
                        if let u = g.audioUrl { AudioMensaje(url: URL(string: u)) }
                        Text(g.transcripcion ?? "").estilo(.texto14).foregroundStyle(C.texto)
                    }
                    .padding(14).tarjeta()
                }
            }
            .padding(16)
        }
        .pantallaApilada("Recorridas dictadas")
        .toolbar { if estado.escribe { Button { dictando = true } label: { Image(systemName: "mic") }.accessibilityLabel("Dictar") } }
        .task(id: estado.version) { lista = (try? await estado.api.get("/v1/propiedades/\(propiedad)/grabaciones")) ?? [] }
        .sheet(isPresented: $dictando) {
            DictarInventario(propiedad: propiedad) { n in
                estado.version += 1
                if n > 0 { estado.sugerir("Armamos \(Formato.cantidad(n, "ítem", "ítems")) del inventario.", "Ver", AInventario(id: propiedad)) }
                else { estado.avisar("Guardamos la recorrida, pero no encontramos ítems. Sumalos a mano en el inventario.", ok: false) }
            }
        }
    }
}

struct EnvioAPI: Codable, Identifiable, Hashable {
    var id: String
    var contactoId: String?
    var contactoNombre: String?
    var canal: String?
    var enviadaPor: String?
    var enviadaEn: Date?
}

/// A quién se le mandó la ficha, por dónde y cuándo.
struct FichasMandadas: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var lista: [EnvioAPI] = []

    var body: some View {
        List {
            if lista.isEmpty {
                EstadoVacio(icono: "paperplane", titulo: "Todavía no se la mandaste a nadie", texto: "Cuando mandes la ficha por WhatsApp o por mail, queda acá.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(lista) { e in
                Button { if let c = e.contactoId { estado.abrir(AFichaContacto(id: c)) } } label: {
                    HStack {
                        Image(systemName: e.canal == "email" ? "envelope" : "bubble.left").foregroundStyle(C.accion)
                        VStack(alignment: .leading) {
                            Text(e.contactoNombre ?? "Contacto").estilo(.filaLista).foregroundStyle(C.texto)
                            Text([e.enviadaPor, e.enviadaEn.map { Formato.cuando($0) }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                    }
                }
                .swipeActions { if estado.escribe { Button("Quitar", role: .destructive) { Task { try? await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/envios/\(e.id)"); await cargar() } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Fichas mandadas")
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/propiedades/\(propiedad)/envios")) ?? [] }
}
