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

/// Un acta (entrega o devolución) con sus firmas.
struct Acta: Codable, Identifiable, Hashable {
    struct Firma: Codable, Hashable { var nombre: String?; var trazo: String?; var en: Date? }
    var id: String
    var propiedadId: String?
    var contratoId: String?
    var tipo: String?
    var fecha: String?
    var observaciones: String?
    var firmas: [String: Firma]?
    var propiedadTitulo: String?
}

/// 11A Recorrida de inventario: los ambientes en chips, las fotos del ambiente, el estado de cada ítem
/// (Bueno · Regular · Malo) con su nota, y «Siguiente».
struct Inventario: View {
    @Environment(Estado.self) private var estado
    var propiedad: String
    @State private var items: [ItemInventario] = []
    @State private var actas: [Acta] = []
    @State private var prop: Propiedad?
    @State private var ambiente = ""
    @State private var foto: PhotosPickerItem?
    @State private var camara = false
    @State private var nuevoItem = ""
    @State private var nuevoAmbiente = ""
    @State private var sumandoAmbiente = false
    @State private var dictando = false

    private var ambientes: [String] {
        var vistos: [String] = []
        for i in items where !vistos.contains(i.ambiente) { vistos.append(i.ambiente) }
        return vistos
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prop?.nombre ?? "Inventario").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
                    if let i = ambientes.firstIndex(of: ambiente) {
                        Text("Ambiente \(i + 1) de \(ambientes.count)").estilo(.texto14).foregroundStyle(C.texto2)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ambientes, id: \.self) { a in
                            let hecho = items.filter { $0.ambiente == a }.allSatisfy { $0.estado != "" }
                            Button { ambiente = a } label: {
                                HStack(spacing: 4) {
                                    if hecho && a != ambiente { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                                    Text(a)
                                }
                                .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                                .foregroundStyle(a == ambiente ? C.sobreAccion : C.texto)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(a == ambiente ? C.accion : C.superficie, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if estado.escribe {
                            Button { sumandoAmbiente = true } label: { Image(systemName: "plus").frame(width: 36, height: 36).background(C.hundida, in: Circle()) }
                                .accessibilityLabel("Sumar ambiente")
                        }
                    }
                }
                let delAmbiente = items.filter { $0.ambiente == ambiente }
                let fotos = delAmbiente.flatMap { $0.fotosUrl ?? [] }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(fotos, id: \.self) { f in Foto(url: URL(string: f)).aspectRatio(1, contentMode: .fill).clipShape(.rect(cornerRadius: 12)) }
                    if estado.escribe, let primero = delAmbiente.first {
                        Menu {
                            Button { camara = true } label: { Label("Sacar foto", systemImage: "camera") }
                            PhotosPicker(selection: $foto, matching: .images) { Label("Elegir de la fototeca", systemImage: "photo") }
                        } label: {
                            Image(systemName: "camera.badge.ellipsis").font(.system(size: 24)).foregroundStyle(C.accion)
                                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        }
                        .accessibilityLabel("Sacar foto")
                        .onChange(of: foto) { _, i in
                            guard let i else { return }
                            Task { if let d = try? await i.loadTransferable(type: Data.self) { await sumarFoto(d, a: primero) }; foto = nil }
                        }
                        .fullScreenCover(isPresented: $camara) { Camara { d in Task { await sumarFoto(d, a: primero) } }.ignoresSafeArea() }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(delAmbiente.enumerated()), id: \.element.id) { i, it in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(it.descripcion + (it.cantidad.map { $0 > 1 ? " × \($0)" : "" } ?? "")).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                            HStack(spacing: 6) {
                                ForEach(ItemInventario.estados.filter { ["bueno", "regular", "malo"].contains($0.0) }, id: \.0) { k, n in
                                    let on = it.estado == k
                                    Button { Task { await poner(it, estado: k) } } label: {
                                        Text(n).font(Estilo(tamano: 14, peso: on ? .bold : .medium, relativo: .footnote).font)
                                            .foregroundStyle(on ? (k == "malo" ? C.errorTinta : k == "regular" ? C.avisoTinta : C.okTinta) : C.texto)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(on ? (k == "malo" ? C.errorFondo : k == "regular" ? C.avisoFondo : C.okFondo) : C.hundida, in: .rect(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain).disabled(!estado.escribe)
                                }
                            }
                            TextField("Nota (opcional)", text: Binding(get: { it.notas ?? "" }, set: { n in if let x = items.firstIndex(of: it) { items[x].notas = n } }))
                                .estilo(.texto14).foregroundStyle(C.texto2)
                                .onSubmit { Task { await guardar(items.first { $0.id == it.id } ?? it) } }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                    if estado.escribe {
                        HStack {
                            TextField("Sumar un ítem (placard, canilla…)", text: $nuevoItem).estilo(.body16)
                            if !nuevoItem.isEmpty { Button { Task { await sumarItem(nuevoItem, en: ambiente) } } label: { Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(C.accion) }.accessibilityLabel("Sumar") }
                        }
                        .padding(14).overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                    }
                }
                .tarjeta()
                if items.isEmpty {
                    EstadoVacio(icono: "checklist", titulo: "Armá el inventario", texto: "Sumá los ambientes y lo que hay en cada uno. Después lo firman las dos partes.",
                                accion: estado.escribe ? ("Sumar el primer ambiente", { sumandoAmbiente = true }) : nil)
                }
                if let i = ambientes.firstIndex(of: ambiente), i + 1 < ambientes.count {
                    Button("Siguiente: \(ambientes[i + 1])") { withAnimation { ambiente = ambientes[i + 1] } }.buttonStyle(BotonPrincipal())
                } else if !items.isEmpty {
                    Button("Ir a las firmas") { Task { await firmas() } }.buttonStyle(BotonPrincipal())
                }
                if !actas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TituloBloque(texto: "Actas")
                        VStack(spacing: 0) {
                            ForEach(Array(actas.enumerated()), id: \.element.id) { i, a in
                                Button { estado.abrir(AFirmas(id: "\(propiedad)/\(a.id)")) } label: {
                                    HStack {
                                        Text("\(a.tipo == "devolucion" ? "Devolución" : "Entrega") · \(a.fecha.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "")").estilo(.filaLista).foregroundStyle(C.texto)
                                        Spacer()
                                        Text("\(a.firmas?.count ?? 0) de 3 firmas").estilo(.footnote).foregroundStyle(C.texto2)
                                        Chevron()
                                    }
                                    .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                            }
                        }
                        .tarjeta()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .pantallaApilada("Acta de entrega")
        .toolbar { if estado.escribe { Button { dictando = true } label: { Label("Dictar", systemImage: "mic") } } }
        .sheet(isPresented: $dictando) {
            DictarInventario(propiedad: propiedad) { n in
                estado.avisar("Sumamos \(Formato.cantidad(n, "ítem", "ítems")) al inventario")
                Task { await cargar() }
            }
        }
        .task(id: estado.version) { await cargar() }
        .alert("Ambiente nuevo", isPresented: $sumandoAmbiente) {
            TextField("Living, baño, cocina…", text: $nuevoAmbiente)
            Button("Cancelar", role: .cancel) {}
            Button("Sumar") { Task { await sumarItem("Paredes y techo", en: nuevoAmbiente); ambiente = nuevoAmbiente; nuevoAmbiente = "" } }
        }
    }

    private func cargar() async {
        prop = try? await estado.api.get("/v1/propiedades/\(propiedad)")
        items = (try? await estado.api.get("/v1/propiedades/\(propiedad)/inventario")) ?? []
        actas = (try? await estado.api.get("/v1/propiedades/\(propiedad)/actas")) ?? []
        if ambiente.isEmpty || !ambientes.contains(ambiente) { ambiente = ambientes.first ?? "" }
    }

    private func cuerpo(_ it: ItemInventario) -> some Encodable {
        struct Cuerpo: Encodable { var ambiente: String; var descripcion: String; var cantidad: Int; var estado: String; var notas: String?; var fotos: [String] }
        return Cuerpo(ambiente: it.ambiente, descripcion: it.descripcion, cantidad: it.cantidad ?? 1, estado: it.estado.isEmpty ? "bueno" : it.estado, notas: it.notas?.nonEmpty, fotos: it.fotos ?? [])
    }

    private func guardar(_ it: ItemInventario) async {
        try? await estado.cola.enviar("PUT", "/v1/propiedades/\(propiedad)/inventario/\(it.id)", cuerpo(it), etiqueta: "Inventario de \(prop?.nombre ?? "")")
    }

    private func poner(_ it: ItemInventario, estado nuevo: String) async {
        guard let i = items.firstIndex(of: it) else { return }
        items[i].estado = nuevo
        Haptico.seleccion()
        await guardar(items[i])
    }

    private func sumarItem(_ d: String, en a: String) async {
        guard !a.isEmpty else { return }
        struct Cuerpo: Encodable { var ambiente: String; var descripcion: String; var cantidad = 1; var estado = "bueno" }
        try? await estado.api.hacer("POST", "/v1/propiedades/\(propiedad)/inventario", Cuerpo(ambiente: a, descripcion: d))
        nuevoItem = ""
        await cargar()
    }

    private func sumarFoto(_ d: Data, a it: ItemInventario) async {
        do {
            let f = try await estado.api.subir(UIImage(data: d)?.jpegData(compressionQuality: 0.8) ?? d, nombre: "inventario.jpg", tipo: "image/jpeg", uso: "foto")
            var x = it
            x.fotos = (x.fotos ?? []) + [f.id]
            await guardar(x)
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func firmas() async {
        if let a = actas.first(where: { ($0.firmas?.count ?? 0) < 3 }) {
            estado.abrir(AFirmas(id: "\(propiedad)/\(a.id)"))
            return
        }
        struct Cuerpo: Encodable { var tipo = "entrega"; var fecha: String }
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/actas", Cuerpo(fecha: Formato.diaISO(Date())))
            estado.abrir(AFirmas(id: "\(propiedad)/\(n.id)"))
        } catch { estado.avisar(error) }
    }
}

/// 11B–11C Firmas del acta: inquilino, propietario e inmobiliaria firman con el dedo en el iPhone (o
/// se les manda un link para que firmen desde el suyo). «Cerrar acta y mandar PDF».
struct Firmas: View {
    @Environment(Estado.self) private var estado
    /// «propiedad/acta».
    var clave: String
    @State private var acta: Acta?
    @State private var firmando: String?
    @State private var previo: ArchivoPrevio?

    private var propiedad: String { String(clave.split(separator: "/").first ?? "") }
    private var actaId: String { String(clave.split(separator: "/").last ?? "") }
    private static let partes = [("inquilino", "Inquilino"), ("propietario", "Propietario"), ("inmobiliaria", "Inmobiliaria")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Formato.sinViudas("Al firmar, las partes aceptan el estado de cada ambiente tal como quedó registrado, con sus fotos."))
                    .estilo(.subhead).foregroundStyle(C.texto2)
                ForEach(Self.partes, id: \.0) { k, n in
                    let f = acta?.firmas?[k]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(f?.nombre.map { "\(n) · \($0)" } ?? n).estilo(.footnote).foregroundStyle(C.texto2)
                            Spacer()
                            if f != nil, estado.escribe {
                                Button("Borrar") { Task { try? await estado.api.hacer("DELETE", "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(k)"); await cargar() } }
                                    .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.accion)
                            }
                        }
                        if let t = f?.trazo {
                            TrazoFirma(trazo: t).frame(height: 110).frame(maxWidth: .infinity).background(Color.tema(0xFAF8F3, 0x1A2420), in: .rect(cornerRadius: 12))
                            Label("Firmó \(f?.en.map { Formato.cuando($0) } ?? "")", systemImage: "checkmark.circle.fill").estilo(.footnote).foregroundStyle(C.texto2)
                        } else {
                            Button { firmando = k } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "signature").font(.system(size: 28))
                                    Text("Firmá con el dedo")
                                    Rectangle().fill(C.linea2).frame(height: 1).padding(.horizontal, 30)
                                }
                                .foregroundStyle(C.texto3).frame(maxWidth: .infinity, minHeight: 130)
                                .background(Color.tema(0xFAF8F3, 0x1A2420), in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }
                            .buttonStyle(.plain)
                            Button("Mandarle un link para que firme desde su teléfono") { Task { await link(k) } }
                                .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.accion)
                        }
                    }
                    .padding(14).tarjeta()
                }
                let completa = (acta?.firmas?.count ?? 0) >= 3
                Button {
                    Task {
                        guard let acta else { return }
                        let items: [ItemInventario] = (try? await estado.api.get("/v1/propiedades/\(propiedad)/inventario")) ?? []
                        let p: Propiedad? = try? await estado.api.get("/v1/propiedades/\(propiedad)")
                        if let u = await Documentos.acta(acta, items: items, propiedad: p?.nombre ?? "", api: estado.api) {
                            Haptico.exito()
                            previo = ArchivoPrevio(url: u)
                        }
                    }
                } label: {
                    Text("Cerrar acta y mandar PDF").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font)
                        .foregroundStyle(completa ? C.sobreAccion : C.texto3).frame(maxWidth: .infinity, minHeight: 52)
                        .background(completa ? C.accion : C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .disabled(!completa)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .pantallaApilada("Firmas")
        .vistaPrevia($previo)
        .task(id: estado.version) { await cargar() }
        .sheet(item: Binding(get: { firmando.map { CampoAlta(id: $0) } }, set: { firmando = $0?.id })) { p in
            HojaFirma(parte: p.id) { nombre, trazo in Task { await firmar(p.id, nombre, trazo) } }.presentationDetents([.medium])
        }
    }

    private func cargar() async { acta = try? await estado.api.get("/v1/propiedades/\(propiedad)/actas/\(actaId)") }

    private func firmar(_ parte: String, _ nombre: String, _ trazo: String) async {
        struct Cuerpo: Encodable { var nombre: String; var trazo: String }
        do {
            try await estado.api.hacer("PUT", "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(parte)", Cuerpo(nombre: nombre, trazo: trazo))
            Haptico.exito()
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func link(_ parte: String) async {
        struct L: Decodable { var url: String }
        do {
            let l: L = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/actas/\(actaId)/firmas/\(parte)/link", [String: String]())
            Afuera.whatsapp(nil, texto: "Para firmar el acta de entrega: \(l.url)")
        } catch { estado.avisar(error) }
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

/// La hoja para firmar con el dedo: el nombre y el recuadro.
struct HojaFirma: View {
    @Environment(\.dismiss) private var cerrar
    var parte: String
    var alFirmar: (String, String) -> Void
    @State private var nombre = ""
    @State private var trazos: [[CGPoint]] = []
    @State private var actual: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Firma del \(parte)").estilo(.titulo3)
            TextField("Nombre y apellido", text: $nombre).campoCorredor()
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
            .frame(height: 160)
            HStack {
                Button("Borrar") { trazos = [] }.buttonStyle(BotonHundido())
                Button("Firmar") {
                    alFirmar(nombre, svg())
                    cerrar()
                }
                .buttonStyle(BotonAccion()).disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || trazos.isEmpty)
            }
        }
        .padding(16)
    }

    @State private var tam = CGSize(width: 600, height: 200)

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
    var creadaEn: Date?
}

/// Dictar la recorrida: se graba la voz, se transcribe en el iPhone y la API arma los ítems del
/// inventario («living: paredes bien, una mancha de humedad en el techo…»).
struct DictarInventario: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: String
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
            struct C: Encodable { var transcripcion: String; var tipoActa = "entrega" }
            let g: GrabacionAPI = try await estado.api.enviar("POST", "/v1/propiedades/\(propiedad)/grabaciones", C(transcripcion: dictado.texto))
            Haptico.exito()
            alTerminar(g.itemsCreados ?? 0)
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
        .sheet(isPresented: $dictando) { DictarInventario(propiedad: propiedad) { _ in estado.version += 1 } }
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
