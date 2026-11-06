import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RendicionAPI: Codable, Identifiable, Hashable {
    struct Item: Codable, Identifiable, Hashable {
        var id: String
        var descripcion: String
        var monto: Double
        /// El comprobante del gasto (factura, ticket).
        var archivoId: String?
    }
    var id: String
    var contratoId: String?
    var periodo: String
    var moneda: String?
    var cobrado: Double?
    var comisionPorcentaje: Double?
    var comision: Double?
    var gastos: Double?
    var neto: Double?
    var estado: String?
    var notas: String?
    var compartida: Bool?
    var numero: Int?
    var emitidaEn: Date?
    var items: [Item]?

    static func estadoTexto(_ e: String?) -> String {
        ["pendiente": "Borrador para revisar", "liquidada": "Emitida", "pagada": "Transferida"][e ?? ""] ?? "Borrador"
    }

    /// «0012».
    static func numeroTexto(_ n: Int?) -> String? { n.map { String(format: "%04d", $0) } }
}

/// Lo que ve el propietario por el link y lo que se imprime (GET …/rendiciones/{rid}/imprimir).
struct ComprobanteRendicion: Codable, Hashable {
    struct Inmo: Codable, Hashable { var nombre: String }
    struct Proximo: Codable, Hashable { var indice: String; var fecha: String; var monto: Double?; var estimado: Bool? }
    var inmobiliaria: Inmo?
    var periodo: String
    var moneda: String
    var propiedadTitulo: String?
    var propiedadDireccion: String?
    var propietario: String?
    var inquilino: String?
    var cobrado: Double
    var comisionPorcentaje: Double?
    var comision: Double?
    var items: [RendicionAPI.Item]?
    var gastos: Double?
    var neto: Double
    var estado: String
    var notas: String?
    var pagadoEl: String?
    var proximo: Proximo?
    var numero: Int?
}

/// La rendición al propietario (24E): se arma sola con lo cobrado; se revisa, se suma un gasto si hubo
/// (con su comprobante) y se emite. Emitir es lo único que pide confirmación (le llega a otra persona).
struct RendicionVista: View {
    @Environment(Estado.self) private var estado
    var contrato: String
    var id: String
    /// Abre «Así la ve <propietario>» al entrar (`?vista=1`).
    var verComoPropietario = false
    @State private var r: RendicionAPI?
    @State private var comp: ComprobanteRendicion?
    @State private var k: ContratoAPI?
    @State private var propietario: FichaContrato.Persona?
    @State private var otras: [RendicionAPI] = []
    @State private var listas: [RendicionesListas.Lista] = []
    @State private var sacados: Set<String> = []
    @State private var error: ErrorApi?
    // Sumar un gasto.
    @State private var sumando = false
    @State private var descripcion = ""
    @State private var monto: Double?
    @State private var comprobante: Archivo?
    @State private var errores: [String: String] = [:]
    @State private var guardando = false
    // Comprobantes.
    @State private var adjuntandoA: String?
    @State private var eligiendoArchivo = false
    @State private var foto: PhotosPickerItem?
    @State private var subiendo = false
    @State private var previo: ArchivoPrevio?
    // Emitir y mandar.
    @State private var confirmar = false
    @State private var emitiendo = false
    @State private var url: String?
    @State private var texto = ""
    @State private var enviado = false
    @State private var vista = false
    @State private var vistaHecha = false

    private var ruta: String { "/v1/contratos/\(contrato)/rendiciones/\(id)" }
    private var nombre: String { propietario?.nombre ?? comp?.propietario ?? "el propietario" }
    private var n: String { TextosCobro.primerNombre(nombre) }
    private var mes: String { TextosCobro.nombreMes(r?.periodo ?? "") }
    private var editable: Bool { r?.estado == "pendiente" && estado.escribe }
    private var items: [RendicionAPI.Item] { (r?.items ?? []).filter { !sacados.contains($0.id) } }
    private var neto: Double { (r?.neto ?? 0) + (r?.items ?? []).filter { sacados.contains($0.id) }.reduce(0) { $0 + $1.monto } }
    private var moneda: String { r?.moneda ?? "ARS" }

    var body: some View {
        ScrollView {
            if let r {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(r)
                    tabla(r)
                    lateral(r)
                    panel
                }
                .padding(16)
            } else if let error {
                EstadoError(que: "la rendición", error: error) { Task { await cargar() } }.padding(.top, 40)
            } else { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
        }
        .pantallaApilada("Rendición")
        .vistaPrevia($previo)
        .toolbar {
            Button { Task { await pdf() } } label: { Image(systemName: "printer") }.accessibilityLabel("PDF de la rendición")
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $confirmar) { hojaConfirmar }
        .sheet(isPresented: $vista) {
            NavigationStack {
                ScrollView { if let comp { RendicionPublica(c: comp, items: items, neto: neto).padding(16) } }
                    .background(C.fondo)
                    .navigationTitle("Así la ve \(n)").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { vista = false } } }
            }
        }
        .fileImporter(isPresented: $eligiendoArchivo, allowedContentTypes: [.pdf, .image]) { res in
            if case .success(let u) = res { Task { await subirArchivo(u) } }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) {
                    await subirComprobante(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "Comprobante.jpg", tipo: "image/jpeg")
                }
                foto = nil
            }
        }
    }

    // MARK: Cabecera y tabla

    private func cabecera(_ r: RendicionAPI) -> some View {
        let estadoTxt = r.estado == "liquidada" ? " · emitida" : r.estado == "pagada" ? " · transferida" : ""
        let titulo = RendicionAPI.numeroTexto(r.numero).map { "Rendición N.º \($0) · \(mes)" } ?? "Rendición de \(mes)"
        return VStack(alignment: .leading, spacing: 2) {
            Text(titulo + estadoTxt).estilo(.footnote).foregroundStyle(C.texto2)
            Text(nombre).estilo(.titulo).foregroundStyle(C.texto)
            Text(comp?.propiedadTitulo ?? k?.propiedadTitulo ?? "").estilo(.subhead).foregroundStyle(C.texto2)
        }
    }

    private func tabla(_ r: RendicionAPI) -> some View {
        VStack(spacing: 0) {
            linea("Alquiler cobrado\(comp?.inquilino.map { " a \($0)" } ?? "")", Formato.numero(Int((r.cobrado ?? 0).rounded())), primera: true)
            if let c = r.comision, c > 0 {
                linea("Administración \(TextosCobro.numero(r.comisionPorcentaje ?? 0))\u{00A0}%", "−" + Formato.numero(Int(c.rounded())), gris: true)
            }
            ForEach(items) { it in filaGasto(it) }
            if editable {
                if sumando { formularioGasto } else {
                    Button { sumando = true } label: {
                        Label("Sumar gasto o ajuste", systemImage: "plus").estilo(.subheadFuerte).foregroundStyle(C.accion)
                            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
            }
            HStack {
                Text("A transferir a \(n)").bold()
                Spacer()
                Text(Formato.plata(neto, moneda)).bold()
            }
            .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
            .padding(14).overlay(alignment: .top) { Rectangle().fill(C.linea2).frame(height: 1) }
        }
        .tarjeta()
    }

    private func linea(_ l: String, _ v: String, primera: Bool = false, gris: Bool = false) -> some View {
        HStack { Text(l).foregroundStyle(gris ? C.texto2 : C.texto); Spacer(); Text(v).foregroundStyle(C.texto) }
            .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func filaGasto(_ it: RendicionAPI.Item) -> some View {
        HStack(spacing: 8) {
            Text(it.descripcion).foregroundStyle(C.texto2)
            if let a = it.archivoId {
                Button { Task { await ver(a, nombre: "Comprobante \(it.descripcion)") } } label: { Image(systemName: "doc.text.fill").foregroundStyle(C.azulTinta) }
                    .accessibilityLabel("Ver el comprobante")
            } else if editable {
                Menu {
                    Button { adjuntandoA = it.id; eligiendoArchivo = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                    PhotosPicker(selection: Binding(get: { foto }, set: { adjuntandoA = it.id; foto = $0 }), matching: .images) { Label("Una foto", systemImage: "photo") }
                } label: { Image(systemName: "paperclip").foregroundStyle(C.texto3) }
                    .accessibilityLabel("Adjuntar el comprobante de «\(it.descripcion)»")
            }
            Spacer()
            Text("−" + Formato.numero(Int(it.monto.rounded()))).foregroundStyle(C.texto)
            if editable {
                Button { sacar(it) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }.accessibilityLabel("Sacar «\(it.descripcion)»")
            }
        }
        .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    private var formularioGasto: some View {
        VStack(alignment: .leading, spacing: 10) {
            Etiquetado("Qué se descuenta") {
                TextField("Arreglo de canilla · Plomería Rossi", text: $descripcion).campoCorredor()
                    .onChange(of: descripcion) { _, t in if t.count > 200 { descripcion = String(t.prefix(200)) } }
                if let e = errores["descripcion"] { Text(e).estilo(.footnote).foregroundStyle(C.errorTinta) }
            }
            Etiquetado("Monto") {
                TextField(moneda, value: $monto, format: .number).keyboardType(.decimalPad).campoCorredor()
                if let e = errores["monto"] { Text(e).estilo(.footnote).foregroundStyle(C.errorTinta) }
            }
            if let c = comprobante {
                HStack {
                    Label(c.nombre ?? "Comprobante", systemImage: "doc.text.fill").estilo(.subhead).foregroundStyle(C.texto)
                    Spacer()
                    Button("Sacar") { comprobante = nil }.font(Estilo.subheadFuerte.font).foregroundStyle(C.error)
                }
            } else {
                Menu {
                    Button { adjuntandoA = "nuevo"; eligiendoArchivo = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                    PhotosPicker(selection: Binding(get: { foto }, set: { adjuntandoA = "nuevo"; foto = $0 }), matching: .images) { Label("Una foto", systemImage: "photo") }
                } label: {
                    Label(subiendo ? "Subiendo…" : "El comprobante: tocá para elegir", systemImage: "paperclip").estilo(.subhead).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
                }
                .disabled(subiendo)
            }
            HStack(spacing: 8) {
                Button("Cancelar") { sumando = false; errores = [:] }.buttonStyle(BotonHundido())
                Button { Task { await sumar() } } label: { if guardando { ProgressView() } else { Text("Sumar") } }.buttonStyle(BotonAccion()).disabled(guardando || subiendo)
            }
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    // MARK: Al emitir, emitida

    @ViewBuilder private func lateral(_ r: RendicionAPI) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if r.estado == "pendiente" && estado.esDuenio {
                Text("Al emitir").estilo(.headline).foregroundStyle(C.texto)
                punto("lock", "Queda emitida y no se puede editar. Si hay un error, se corrige con una nota en la próxima.")
                punto("bubble.left", "Le mandamos el link por WhatsApp a \(n).")
                punto("building.columns", "Te queda pendiente «Transferir \(Formato.plata(neto, moneda))» hasta que la marques hecha.")
                Button("Emitir y mandar") { confirmar = true }.buttonStyle(BotonPrincipal())
                Button("Ver como la ve \(n)") { vista = true }.buttonStyle(BotonHundido())
                quedan
            } else if r.estado == "pendiente" {
                if estado.escribe {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(C.texto2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Las rendiciones las emite la dueña").estilo(.subheadFuerte).foregroundStyle(C.texto)
                            Text("Como agente podés prepararlas y dejarlas listas. La dueña las revisa y las manda.").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                    }
                }
                Button("Ver como la ve \(n)") { vista = true }.buttonStyle(BotonHundido())
            } else {
                Text(r.estado == "pagada" ? "Transferida" : "Emitida").estilo(.headline).foregroundStyle(C.texto)
                if let url {
                    MensajeWhatsApp(contactoId: propietario?.id ?? k?.propietarioId, telefono: propietario?.telefono, nombre: nombre, texto: $texto, para: "rendicion",
                                    parametros: [n, mes, Formato.plata(r.neto ?? 0, moneda), url], listo: "Quedó en la ficha de \(n).", enviado: $enviado,
                                    alListo: { self.url = nil })
                } else {
                    punto(r.estado == "pagada" ? "checkmark.circle" : "building.columns",
                          r.estado == "pagada" ? "Le transferiste \(Formato.plata(r.neto ?? 0, moneda)) a \(n)." : "Falta transferirle \(Formato.plata(r.neto ?? 0, moneda)) a \(n).")
                    if r.estado == "liquidada" && estado.escribe {
                        Button { Task { await transferida() } } label: { Label("Ya la transferí", systemImage: "checkmark") }.buttonStyle(BotonPrincipal())
                    }
                    if estado.escribe {
                        Button { Task { await linkNuevo() } } label: { Label("Mandar el link de nuevo", systemImage: "bubble.left") }.buttonStyle(BotonHundido())
                    }
                    Button("Ver como la ve \(n)") { vista = true }.buttonStyle(BotonTexto())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.crema2, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func punto(_ icono: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono).font(.system(size: 16)).foregroundStyle(C.texto2).frame(width: 22)
            Text(t).estilo(.subhead).foregroundStyle(C.texto)
        }
    }

    /// «Quedan N rendiciones listas este mes», al próximo contrato.
    @ViewBuilder private var quedan: some View {
        let otrasListas = listas.filter { $0.contratoId != contrato }
        if let primera = otrasListas.first {
            Button { estado.abrir(AFichaContrato(id: primera.contratoId)) } label: {
                Text("Quedan \(otrasListas.count == 1 ? "1 rendición lista" : "\(otrasListas.count) rendiciones listas") este\u{00A0}mes")
                    .estilo(.subheadFuerte).foregroundStyle(C.accion).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Panel de la sección

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !otras.isEmpty {
                TituloBloque(texto: "Rendiciones de este contrato")
                VStack(spacing: 0) {
                    ForEach(Array(otras.prefix(6).enumerated()), id: \.element.id) { i, o in
                        Button { if o.id != id { estado.abrir(ARendicion(contrato: contrato, id: o.id)) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.plaintext").foregroundStyle(o.estado == "pendiente" ? C.oroTinta : C.texto2).frame(width: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(Formato.mayuscula(TextosCobro.nombreMes(o.periodo))).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(o.estado == "pendiente" ? "para revisar" : o.estado == "liquidada" ? "emitida" : "transferida").estilo(.footnote).foregroundStyle(C.texto2)
                                }
                                Spacer()
                                if o.id == id { Image(systemName: "checkmark").foregroundStyle(C.accion) } else { Chevron() }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
            TituloBloque(texto: "Contrato")
            Button { estado.abrir(AFichaContrato(id: contrato)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").foregroundStyle(C.texto2).frame(width: 24)
                    Text(k?.propiedadTitulo ?? "Contrato").estilo(.filaLista).foregroundStyle(C.texto)
                    Spacer()
                    Chevron()
                }
                .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(Presionable()).tarjeta()
        }
    }

    // MARK: Confirmar

    private var hojaConfirmar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Vas a emitir \(mes)", systemImage: "checkmark.seal").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text("Le llega a \(nombre) y ya no se puede editar.").estilo(.subhead).foregroundStyle(C.texto2)
            VStack(spacing: 0) {
                linea(comp?.propiedadTitulo ?? k?.propiedadTitulo ?? "", "", primera: true)
                linea("Cobrado", Formato.numero(Int((r?.cobrado ?? 0).rounded())))
                if let c = r?.comision, c > 0 { linea("Administración", "−" + Formato.numero(Int(c.rounded())), gris: true) }
                ForEach(items) { it in linea(it.descripcion, "−" + Formato.numero(Int(it.monto.rounded())), gris: true) }
                HStack { Text("A transferir").bold(); Spacer(); Text(Formato.plata(neto, moneda)).bold() }
                    .estilo(.headline).foregroundStyle(C.texto).padding(14).overlay(alignment: .top) { Rectangle().fill(C.linea2).frame(height: 1) }
            }
            .tarjeta()
            HStack(spacing: 8) {
                Button("Cancelar") { confirmar = false }.buttonStyle(BotonHundido())
                Button { Task { await emitir() } } label: { Text(emitiendo ? "Emitiendo…" : "Emitir y mandar") }.buttonStyle(BotonAccion()).disabled(emitiendo)
            }
        }
        .padding(.horizontal, 16).padding(.top, 24)
        .interactiveDismissDisabled(emitiendo)
        .hojaTLW([.medium, .large])
    }

    // MARK: Acciones

    private func cargar() async {
        do {
            let x: RendicionAPI = try await estado.api.get(ruta)
            comp = try? await estado.api.get("\(ruta)/imprimir")
            let c: ContratoAPI? = try? await estado.api.get("/v1/contratos/\(contrato)")
            k = c
            otras = (try? await estado.api.get("/v1/contratos/\(contrato)/rendiciones")) ?? []
            if let p = c?.propietarioId { propietario = try? await estado.api.get("/v1/contactos/\(p)") }
            listas = (try? await estado.api.get("/v1/rendiciones/listas", query: [.init(name: "mes", value: String(x.periodo.prefix(7)))])) ?? []
            sacados = []
            r = x
            error = nil
            if verComoPropietario && !vistaHecha { vistaHecha = true; vista = true }
        } catch let e as ErrorApi { if r == nil { error = e } } catch {}
    }

    private func sumar() async {
        var e: [String: String] = [:]
        let d = descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { e["descripcion"] = "Poné qué se descuenta." }
        if !((monto ?? 0) > 0) { e["monto"] = "Poné un monto mayor a cero." }
        errores = e
        guard e.isEmpty else { return }
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var descripcion: String; var monto: Double; var archivoId: String? }
        do {
            let nueva: RendicionAPI = try await estado.api.enviar("POST", "\(ruta)/items", Cuerpo(descripcion: d, monto: monto ?? 0, archivoId: comprobante?.id))
            let item = nueva.items?.last
            r = nueva
            estado.avisar("Sumaste «\(d)»") {
                if let item {
                    Task {
                        do { try await estado.api.hacer("DELETE", "\(ruta)/items/\(item.id)") } catch { estado.avisar(error) }
                        estado.version += 1
                    }
                }
            }
            descripcion = ""
            monto = nil
            comprobante = nil
            sumando = false
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// Sacar un gasto: «Deshacer» lo vuelve a sumar igual, con su comprobante.
    private func sacar(_ it: RendicionAPI.Item) {
        sacados.insert(it.id)
        let pedido = Task<Bool, Never> {
            do { try await estado.api.hacer("DELETE", "\(ruta)/items/\(it.id)"); return true } catch {
                sacados.remove(it.id)
                estado.avisar("No se sacó · \((error as? ErrorApi)?.detalle ?? "")", ok: false)
                return false
            }
        }
        estado.avisar("Sacaste «\(it.descripcion)»") {
            Task {
                guard await pedido.value else { return }
                struct Cuerpo: Encodable { var descripcion: String; var monto: Double; var archivoId: String? }
                do { try await estado.api.hacer("POST", "\(ruta)/items", Cuerpo(descripcion: it.descripcion, monto: it.monto, archivoId: it.archivoId)) } catch { estado.avisar(error) }
                estado.version += 1
            }
        }
        Task { if await pedido.value { estado.version += 1 } }
    }

    private func subirArchivo(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u) else { estado.avisar("No se pudo leer el archivo.", ok: false); return }
        await subirComprobante(d, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
    }

    /// El comprobante del gasto nuevo, o de uno ya cargado (PATCH …/items/{item} {archivoId}).
    private func subirComprobante(_ datos: Data, nombre: String, tipo: String) async {
        guard let destino = adjuntandoA else { return }
        subiendo = true
        defer { subiendo = false; adjuntandoA = nil }
        do {
            let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            if destino == "nuevo" {
                comprobante = a
            } else {
                struct Cuerpo: Encodable { var archivoId: String? }
                try await estado.api.hacer("PATCH", "\(ruta)/items/\(destino)", Cuerpo(archivoId: a.id))
                estado.version += 1
                estado.avisar("Comprobante adjunto")
            }
        } catch {
            estado.avisar("No se adjuntó · \((error as? ErrorApi)?.detalle ?? "")", ok: false)
        }
    }

    private func ver(_ archivo: String, nombre: String) async {
        do {
            let datos = try await estado.api.pedir("GET", "/v1/archivos/\(archivo)/contenido")
            struct A: Decodable { var nombre: String?; var tipo: String? }
            let info: A? = try? await estado.api.get("/v1/archivos/\(archivo)")
            let ext = info?.tipo?.contains("pdf") == true ? "pdf" : "jpg"
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(info?.nombre ?? "\(nombre).\(ext)")
            try datos.write(to: u)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func emitir() async {
        emitiendo = true
        struct L: Decodable { var url: String }
        do {
            let l: L = try await estado.api.enviar("POST", "\(ruta)/emitir", [String: String]())
            emitiendo = false
            confirmar = false
            url = l.url
            texto = TextosCobro.rendicion(nombre: nombre, periodo: r?.periodo ?? "", neto: r?.neto ?? 0, moneda: moneda, url: l.url)
            enviado = false
            Haptico.exito()
            estado.version += 1
        } catch {
            emitiendo = false
            confirmar = false
            let detalle = (error as? ErrorApi)?.detalle ?? ""
            estado.sugerir("No se emitió · \(detalle)", "Reintentar") { confirmar = true }
        }
    }

    /// Un link nuevo (el anterior deja de andar): para volver a mandarlo.
    private func linkNuevo() async {
        struct L: Decodable { var url: String }
        do {
            let l: L = try await estado.api.enviar("POST", "\(ruta)/compartir", [String: String]())
            url = l.url
            texto = TextosCobro.rendicion(nombre: nombre, periodo: r?.periodo ?? "", neto: r?.neto ?? 0, moneda: moneda, url: l.url)
            enviado = false
        } catch {
            estado.avisar("No pudimos armar el link · \((error as? ErrorApi)?.detalle ?? "")", ok: false)
        }
    }

    private func transferida() async {
        struct Cuerpo: Encodable { var estado: String }
        do {
            try await estado.api.hacer("PATCH", ruta, Cuerpo(estado: "pagada"))
            estado.version += 1
            estado.avisar("Transferencia a \(n) marcada como hecha") {
                Task {
                    do { try await estado.api.hacer("PATCH", ruta, Cuerpo(estado: "liquidada")) } catch { estado.avisar(error) }
                    estado.version += 1
                }
            }
        } catch { estado.avisar("No se guardó · \((error as? ErrorApi)?.detalle ?? "")", ok: false) }
    }

    private func pdf() async {
        guard let comp else { return }
        if let u = await Documentos.rendicion(comp, items: items, neto: neto, api: estado.api) { previo = ArchivoPrevio(url: u) }
    }
}

/// Lo que ve el propietario al tocar el link (24 «Link público de la rendición»): el neto grande en la
/// tarjeta verde, el detalle y el próximo ajuste.
struct RendicionPublica: View {
    var c: ComprobanteRendicion
    var items: [RendicionAPI.Item]
    var neto: Double

    var body: some View {
        let nombre = TextosCobro.primerNombre(c.propietario)
        let mes = TextosCobro.nombreMes(c.periodo)
        let inmo = c.inmobiliaria?.nombre ?? ""
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(String(inmo.prefix(1)).uppercased()).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.oro)
                    .frame(width: 36, height: 36).background(C.verde700, in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 0) {
                    Text(inmo).estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Text("Rendición de \(mes)").estilo(.caption).foregroundStyle(C.texto2)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Hola\(nombre.isEmpty ? "" : " " + nombre), te \(c.estado == "pagada" ? "transferimos" : "vamos a transferir")").estilo(.subhead)
                Text(Formato.plata(neto, c.moneda)).font(Estilo(tamano: 34, peso: .bold, tracking: -0.03, relativo: .largeTitle).font)
                Text("a tu cuenta").estilo(.footnote)
            }
            .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background { ZStack { C.verde700; Image("GranoClaro").resizable(resizingMode: .tile) } }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            VStack(spacing: 0) {
                fila("Alquiler\(c.inquilino.map { " cobrado a \($0)" } ?? "")", Formato.numero(Int(c.cobrado.rounded())), primera: true)
                if let x = c.comision, x > 0 { fila("Administración \(TextosCobro.numero(c.comisionPorcentaje ?? 0))\u{00A0}%", "−" + Formato.numero(Int(x.rounded()))) }
                ForEach(items) { it in fila(it.descripcion + (it.archivoId == nil ? "" : "\u{00A0}· comprobante adjunto"), "−" + Formato.numero(Int(it.monto.rounded()))) }
            }
            .tarjeta()
            Text(pie).estilo(.footnote).foregroundStyle(C.texto2)
            HStack(spacing: 6) {
                Image("Simbolo").resizable().scaledToFit().frame(height: 10)
                (Text("Hecha con ") + Text("Corredor").bold()).font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font).foregroundStyle(C.texto3)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var pie: String {
        var t = c.propiedadTitulo ?? ""
        if let i = c.inquilino, let p = c.pagadoEl { t += "\u{00A0}· \(i) pagó el\u{00A0}\(TextosCobro.fechaCortita(p))." } else { t += "." }
        if let p = c.proximo, let m = p.monto {
            let fecha = Fecha.dia(p.fecha).map { Formato.diaCompleto($0).split(separator: " ").dropFirst().joined(separator: " ") } ?? p.fecha
            t += " El alquiler ajusta por \(TextosCobro.nombreIndice[p.indice] ?? "índice") el \(fecha) a\u{00A0}\(Formato.plata(m, c.moneda))\(p.estimado == true ? " (estimado)" : "")."
        }
        if let n = c.notas?.nonEmpty { t += "\n\(n)" }
        return t
    }

    private func fila(_ l: String, _ v: String, primera: Bool = false) -> some View {
        HStack { Text(l).foregroundStyle(C.texto2); Spacer(); Text(v).foregroundStyle(C.texto) }
            .estilo(.subhead).padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }
}
