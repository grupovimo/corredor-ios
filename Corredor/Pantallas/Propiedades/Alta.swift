import PhotosUI
import Speech
import SwiftUI

/// Lo que se carga en el alta (y en el borrador que se guarda solo). En /v1/borradores va con el
/// formato de la web (lib/propiedades/alta-modelo.ts), para seguirlo en cualquier aparato: las fotos
/// como `[{id, url}]`, más título, comodidades y dónde publicar, que acá no se editan pero se respetan.
struct DatosAlta: Codable, Equatable {
    var operacion = "venta"
    var tipo = "departamento"
    var direccion = ""
    var barrio = ""
    var ciudad = ""
    var precio: Double?
    var moneda = "USD"
    var expensas: Double?
    var ambientes = 2
    var dormitorios: Int?
    var banos: Int?
    var cocheras: Int?
    var superficie: Double?
    var cubierta: Double?
    var antiguedad: Int?
    var aptoCredito = false
    var descripcion = ""
    var fotos: [String] = []
    var fotosUrl: [String] = []
    var propietarioId: String?
    var propietarioNombre: String?
    // Los de la web.
    var titulo = ""
    /// El título lo tocó la persona: ya no se arma solo de la descripción.
    var tituloPropio = false
    var comodidades: [String] = []
    var sugeridas: [String] = []
    var publicar: [String: Bool] = ["web": true, "mercadolibre": true, "zonaprop": true, "argenprop": false]
    var audioId: String?
    var audioSegundos: Double?

    init() {}

    init(_ p: Propiedad) {
        operacion = p.operacion ?? "venta"
        tipo = p.tipo ?? "departamento"
        direccion = p.direccion ?? ""
        barrio = p.barrio ?? ""
        ciudad = p.ciudad ?? ""
        precio = p.precio
        moneda = p.moneda ?? "USD"
        expensas = p.expensas
        ambientes = p.ambientes ?? 2
        dormitorios = p.dormitorios
        banos = p.banos
        cocheras = p.cocheras
        superficie = p.superficie
        cubierta = p.cubierta
        antiguedad = p.antiguedad
        aptoCredito = p.aptoCredito ?? false
        descripcion = p.descripcion ?? ""
        fotos = p.fotos ?? []
        fotosUrl = p.fotosUrl ?? []
        propietarioId = p.propietarioId
        titulo = p.titulo ?? ""
        tituloPropio = true
        comodidades = p.comodidades ?? []
        sugeridas = comodidades
        publicar = ["web": p.publicada ?? true, "mercadolibre": false, "zonaprop": false, "argenprop": false]
    }

    // MARK: El formato de la web

    private struct FotoAlta: Codable { var id: String; var url: String? }

    private enum K: String, CodingKey {
        case operacion, tipo, direccion, barrio, ciudad, precio, moneda, expensas, ambientes, dormitorios, banos, cocheras, superficie,
             cubierta, antiguedad, aptoCredito, descripcion, fotos, fotosUrl, propietarioId, propietarioNombre, titulo, tituloPropio,
             comodidades, sugeridas, publicar, audioId, audioSegundos
    }

    /// Tolerante: el de la web, el de MIRA y el viejo de la app (fotos como ids sueltos y `fotosUrl`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func v<T: Decodable>(_ k: K) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        operacion = v(.operacion) ?? operacion
        tipo = v(.tipo) ?? tipo
        if tipo == "terreno" { tipo = "lote" }
        direccion = v(.direccion) ?? ""
        barrio = v(.barrio) ?? ""
        ciudad = v(.ciudad) ?? ""
        precio = v(.precio)
        moneda = v(.moneda) ?? moneda
        expensas = v(.expensas)
        ambientes = v(.ambientes) ?? ambientes
        dormitorios = v(.dormitorios)
        banos = v(.banos)
        cocheras = v(.cocheras)
        superficie = v(.superficie)
        cubierta = v(.cubierta)
        antiguedad = v(.antiguedad)
        aptoCredito = v(.aptoCredito) ?? false
        descripcion = v(.descripcion) ?? ""
        let urls: [String] = v(.fotosUrl) ?? []
        for (i, f) in ((v(.fotos) as [JSONLibre]?) ?? []).enumerated() {
            if let id = f["id"]?.texto, !id.hasPrefix("subiendo-") {
                fotos.append(id)
                fotosUrl.append(f["url"]?.texto ?? "")
            } else if let id = f.texto {
                fotos.append(id)
                fotosUrl.append(urls.indices.contains(i) ? urls[i] : "")
            }
        }
        propietarioId = v(.propietarioId)
        propietarioNombre = v(.propietarioNombre)
        titulo = v(.titulo) ?? ""
        tituloPropio = v(.tituloPropio) ?? false
        comodidades = v(.comodidades) ?? []
        sugeridas = v(.sugeridas) ?? []
        publicar.merge((v(.publicar) as [String: Bool]?) ?? [:]) { _, nuevo in nuevo }
        audioId = v(.audioId)
        audioSegundos = v(.audioSegundos)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(operacion, forKey: .operacion)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(direccion, forKey: .direccion)
        try c.encode(barrio, forKey: .barrio)
        try c.encode(precio, forKey: .precio)
        try c.encode(moneda, forKey: .moneda)
        try c.encode(ambientes, forKey: .ambientes)
        try c.encode(zip(fotos, fotosUrl).map { FotoAlta(id: $0, url: $1.nonEmpty) }, forKey: .fotos)
        try c.encode(descripcion, forKey: .descripcion)
        try c.encode(titulo, forKey: .titulo)
        try c.encode(tituloPropio, forKey: .tituloPropio)
        try c.encode(comodidades, forKey: .comodidades)
        try c.encode(sugeridas, forKey: .sugeridas)
        try c.encode(publicar, forKey: .publicar)
        try c.encodeIfPresent(audioId, forKey: .audioId)
        try c.encodeIfPresent(audioSegundos, forKey: .audioSegundos)
        // Lo que la web no carga en el alta (la web lo deja pasar tal cual).
        try c.encodeIfPresent(ciudad.nonEmpty, forKey: .ciudad)
        try c.encodeIfPresent(expensas, forKey: .expensas)
        try c.encodeIfPresent(dormitorios, forKey: .dormitorios)
        try c.encodeIfPresent(banos, forKey: .banos)
        try c.encodeIfPresent(cocheras, forKey: .cocheras)
        try c.encodeIfPresent(superficie, forKey: .superficie)
        try c.encodeIfPresent(cubierta, forKey: .cubierta)
        try c.encodeIfPresent(antiguedad, forKey: .antiguedad)
        if aptoCredito { try c.encode(true, forKey: .aptoCredito) }
        try c.encodeIfPresent(propietarioId, forKey: .propietarioId)
        try c.encodeIfPresent(propietarioNombre, forKey: .propietarioNombre)
    }

    // MARK: El título (tituloSugerido y tituloFinal de la web)

    private var tipoCorto: String { tipo == "departamento" ? "Depto" : (Propiedad.tipos.first { $0.0 == tipo }?.1 ?? tipo) }

    /// «3 amb al frente con balcón · Belgrano · apto crédito», armado de la descripción.
    var tituloSugerido: String {
        let t = descripcion.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let cabeza = [tipo == "departamento" || tipo == "ph" ? "\(ambientes) amb" : "\(tipoCorto) \(ambientes) amb",
                      t.contains("al frente") ? "al frente" : "",
                      t.contains("balcon") ? "con balcón" : t.contains("terraza") ? "con terraza" : t.contains("patio") ? "con patio" : ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return [cabeza, barrio.trimmingCharacters(in: .whitespaces), t.contains("apto credito") ? "apto crédito" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Un título que la API acepte (3 a 120 letras).
    var tituloFinal: String {
        let t = (tituloPropio ? titulo : titulo.nonEmpty ?? tituloSugerido).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 3 { return String(t.prefix(120)) }
        return String("\(tipoCorto) · \(direccion)".prefix(120))
    }

    // MARK: Lo que va a la API

    /// El cuerpo de POST/PUT /v1/propiedades (propiedades.Datos). El PUT reemplaza todo: en la edición
    /// se parte de la propiedad entera (`base`) y se cambia sólo lo del alta, como cuerpo() de la web.
    /// Sin `base` (el alta), se publica en la web según `publicar`.
    func cuerpo(base b: Propiedad? = nil) -> CuerpoPropiedad {
        let periodo: String? = operacion == "alquiler" ? (b?.periodo ?? "mes") : operacion == "temporario" ? (b?.periodo ?? "noche") : nil
        return CuerpoPropiedad(
            titulo: tituloFinal, slug: b?.slug, descripcion: descripcion.nonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines),
            tipo: tipo, operacion: operacion, estado: b?.estado, precio: precio, moneda: moneda, periodo: periodo, expensas: expensas,
            precioOculto: b?.precioOculto, direccion: direccion.trimmingCharacters(in: .whitespacesAndNewlines),
            barrio: barrio.nonEmpty?.trimmingCharacters(in: .whitespaces), ciudad: ciudad.nonEmpty?.trimmingCharacters(in: .whitespaces),
            lat: b?.lat, lng: b?.lng, ambientes: ambientes, dormitorios: dormitorios, banos: banos, cocheras: cocheras,
            superficie: superficie, cubierta: cubierta, antiguedad: antiguedad,
            aptoCredito: b?.aptoCredito == nil && !aptoCredito ? nil : aptoCredito, tambienTemporario: b?.tambienTemporario,
            comodidades: comodidades, caracteristicas: b?.caracteristicas, servicios: b?.servicios, fotos: fotos, video: b?.video,
            ficha: b?.ficha, destacada: b?.destacada, publicada: b.map { $0.publicada ?? true } ?? (publicar["web"] ?? true),
            agenteId: b?.agenteId, propietarioId: propietarioId, emprendimientoId: b?.emprendimientoId)
    }
}

/// POST/PUT /v1/propiedades: todos los campos de propiedades.Datos (lo que falta va como null).
struct CuerpoPropiedad: Encodable {
    var titulo: String
    var slug: String?
    var descripcion: String?
    var tipo: String
    var operacion: String
    var estado: String?
    var precio: Double?
    var moneda: String
    var periodo: String?
    var expensas: Double?
    var precioOculto: Bool?
    var direccion: String
    var barrio: String?
    var ciudad: String?
    var lat: Double?
    var lng: Double?
    var ambientes: Int?
    var dormitorios: Int?
    var banos: Int?
    var cocheras: Int?
    var superficie: Double?
    var cubierta: Double?
    var antiguedad: Int?
    var aptoCredito: Bool?
    var tambienTemporario: Bool?
    var comodidades: [String]?
    var caracteristicas: [String]?
    var servicios: [String]?
    var fotos: [String]
    var video: String?
    var ficha: JSONLibre?
    var destacada: Bool?
    var publicada: Bool?
    var agenteId: String?
    var propietarioId: String?
    var emprendimientoId: String?
}

/// Lo que se guarda en /v1/borradores: `{paso, datos}`, como la web (el paso es el del alta de la web,
/// de 0 a 4; la app lo respeta para que allá se siga donde quedó).
struct BorradorAlta: Codable, Equatable {
    var paso = 0
    var datos = DatosAlta()

    init(paso: Int = 0, datos: DatosAlta = DatosAlta()) {
        self.paso = paso
        self.datos = datos
    }

    private enum CodingKeys: String, CodingKey { case paso, datos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paso = min(4, max(0, ((try? c.decodeIfPresent(Int.self, forKey: .paso)) ?? nil) ?? 0))
        datos = ((try? c.decodeIfPresent(DatosAlta.self, forKey: .datos)) ?? nil) ?? DatosAlta()
    }
}

/// Un borrador de GET /v1/borradores.
struct BorradorPropiedad: Decodable, Identifiable {
    var id: String
    var datos: BorradorAlta
    var actualizadoEn: Date?

    private enum K: String, CodingKey { case id, datos, actualizadoEn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        datos = ((try? c.decodeIfPresent(BorradorAlta.self, forKey: .datos)) ?? nil) ?? BorradorAlta()
        actualizadoEn = (try? c.decodeIfPresent(Date.self, forKey: .actualizadoEn)) ?? nil
    }
}

/// 4A Alta rápida (y edición): fotos de la cámara o la fototeca (la primera es la portada), operación,
/// tipo, dirección, barrio, precio, ambientes y la descripción dictada. Se guarda sola como borrador
/// («Borrador guardado · hace 3 s»), el mismo que se sigue en la web; sin señal, el alta queda en cola.
struct AltaPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    /// El id de la propiedad a editar (nil: una nueva).
    var editar: String?
    /// El id de un borrador de /v1/borradores para seguirlo.
    var borrador: String? = nil
    var inicial: DatosAlta? = nil

    @State private var d = DatosAlta()
    /// En la edición, la propiedad entera como vino: el PUT parte de ella.
    @State private var base: Propiedad?
    @State private var paso = 0
    /// Los borradores a medio cargar (para seguir uno en vez de empezar otro).
    @State private var paraSeguir: [BorradorPropiedad] = []
    @State private var borradorId: String?
    @State private var guardadoEn: Date?
    @State private var sinGuardar = false
    @State private var cargando = false
    @State private var publicando = false
    @State private var elegidas: [PhotosPickerItem] = []
    @State private var subiendo = 0
    @State private var camara = false
    @State private var campo: String?
    @State private var masDatos = false
    @State private var dictado = Dictado()
    @State private var ahora = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if editar == nil {
                    if sinGuardar {
                        Label("No se pudo guardar el borrador", systemImage: "exclamationmark.icloud")
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.errorTinta)
                            .padding(.horizontal, 12).frame(height: 28).background(C.errorFondo, in: Capsule())
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(guardadoEn.map { "Borrador guardado · \(Formato.hace($0, ahora: ahora))" } ?? "Se guarda solo como borrador", systemImage: "checkmark.icloud")
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.okTinta)
                            .padding(.horizontal, 12).frame(height: 28).background(C.okFondo, in: Capsule())
                            .frame(maxWidth: .infinity)
                    }
                    if borradorId == nil, !paraSeguir.isEmpty, d == DatosAlta() { aMedioCargar }
                }
                fotos
                Segmentado(opciones: Propiedad.operaciones.map { ($0.0, $0.1) }, elegido: $d.operacion)
                VStack(spacing: 0) {
                    filaCampo("Tipo", Propiedad.tipos.first { $0.0 == d.tipo }?.1 ?? d.tipo, primera: true) { campo = "tipo" }
                    filaCampo("Dirección", d.direccion.nonEmpty ?? "Calle y número") { campo = "direccion" }
                    filaCampo("Barrio", d.barrio.nonEmpty ?? "Barrio o localidad") { campo = "barrio" }
                    filaCampo("Precio", d.precio.map { Formato.plata($0, d.moneda) } ?? "Sin precio") { campo = "precio" }
                    HStack(spacing: 10) {
                        Text("Ambientes").estilo(.subhead).foregroundStyle(C.texto2).frame(width: 96, alignment: .leading)
                        Text("\(d.ambientes)").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                        Spacer()
                        Stepper("Ambientes", value: $d.ambientes, in: 1...20).labelsHidden()
                    }
                    .padding(.leading, 14).padding(.trailing, 8).frame(minHeight: 54)
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
                .tarjeta(16)
                descripcion
                DisclosureGroup(isExpanded: $masDatos) {
                    VStack(spacing: 0) {
                        numero("Dormitorios", $d.dormitorios)
                        numero("Baños", $d.banos)
                        numero("Cocheras", $d.cocheras)
                        decimal("Superficie m²", $d.superficie)
                        decimal("Cubierta m²", $d.cubierta)
                        decimal("Expensas ARS", $d.expensas)
                        numero("Antigüedad (años)", $d.antiguedad)
                        Toggle("Apto crédito", isOn: $d.aptoCredito).estilo(.body16).tint(Color(hex: 0x2F9E6F))
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                        filaCampo("Propietario", d.propietarioNombre ?? (d.propietarioId == nil ? "Elegí un contacto" : "Cargado")) { campo = "propietario" }
                    }
                    .tarjeta(16).padding(.top, 8)
                } label: {
                    Text("Más datos").estilo(.subheadFuerte).foregroundStyle(C.accion)
                }
                .tint(C.accion)
                Text(Formato.sinViudas("Expensas, amenities y portales los completás después, desde la ficha."))
                    .estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 20)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 40)
        }
        .background(FondoApp())
        .navigationTitle(editar == nil ? "Nueva propiedad" : "Editar propiedad")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(editar == nil ? "Publicar" : "Guardar") { Task { await publicar() } }
                    .fontWeight(.semibold).disabled(publicando || subiendo > 0 || d.direccion.isEmpty || (editar != nil && base == nil))
            }
        }
        .sheet(item: Binding(get: { campo.map { CampoAlta(id: $0) } }, set: { campo = $0?.id })) { c in
            EditorCampoAlta(campo: c.id, d: $d).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $camara) { Camara { datos in Task { await subir(datos) } }.ignoresSafeArea() }
        .onChange(of: elegidas) { _, items in
            Task {
                for i in items { if let datos = try? await i.loadTransferable(type: Data.self) { await subir(datos) } }
                elegidas = []
            }
        }
        .onChange(of: d) { _, _ in programarBorrador() }
        .onChange(of: dictado.texto) { _, t in if dictado.grabando { d.descripcion = dictado.base + t } }
        .task { await arrancar() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                ahora = Date()
            }
        }
    }

    // MARK: A medio cargar

    /// Los borradores de la persona (de la web, de otro aparato o de MIRA): tocar uno lo sigue.
    private var aMedioCargar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A MEDIO CARGAR").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5)
                .foregroundStyle(C.texto2).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(paraSeguir.enumerated()), id: \.element.id) { i, b in
                    Button { seguir(b) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.pencil").font(.system(size: 18)).foregroundStyle(C.oro).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.datos.datos.direccion.nonEmpty ?? "Sin dirección todavía").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                Text([Formato.cantidad(b.datos.datos.fotos.count, "foto", "fotos"), b.actualizadoEn.map { Formato.hace($0, ahora: ahora) }]
                                    .compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            Chevron()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
        }
    }

    private func seguir(_ b: BorradorPropiedad) {
        borradorId = b.id
        paso = b.datos.paso
        d = b.datos.datos
        paraSeguir = []
    }

    // MARK: Fotos

    private var fotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOTOS · \(d.fotos.count)").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5)
                .foregroundStyle(C.texto2).padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(d.fotosUrl.enumerated()), id: \.element) { i, u in
                        Foto(url: URL(string: u + (u.contains("?") ? "&" : "?") + "tam=chica"))
                            .frame(width: 88, height: 88).clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                Text("\(i + 1)").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle()).padding(6)
                            }
                            .overlay(alignment: .bottom) {
                                if i == 0 {
                                    Text("Portada").font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(Color(hex: 0x1A1405))
                                        .frame(maxWidth: .infinity, minHeight: 20).background(C.oro, in: .rect(cornerRadius: 6)).padding(6)
                                }
                            }
                            .contextMenu {
                                if i > 0 { Button { mover(i, a: 0) } label: { Label("Usar de portada", systemImage: "star") } }
                                if i > 0 { Button { mover(i, a: i - 1) } label: { Label("Mover antes", systemImage: "arrow.left") } }
                                if i < d.fotos.count - 1 { Button { mover(i, a: i + 1) } label: { Label("Mover después", systemImage: "arrow.right") } }
                                Button(role: .destructive) { sacarFoto(i) } label: { Label("Sacar", systemImage: "trash") }
                            }
                            .draggable(u)
                            .dropDestination(for: String.self) { items, _ in
                                if let x = items.first, let desde = d.fotosUrl.firstIndex(of: x) { mover(desde, a: i) }
                                return true
                            }
                    }
                    if subiendo > 0 {
                        ProgressView().frame(width: 88, height: 88).background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    botonFoto("camera", "Cámara") { camara = true }
                    PhotosPicker(selection: $elegidas, maxSelectionCount: 30, matching: .images) {
                        etiquetaFoto("photo.on.rectangle", "Fototeca")
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 6)
            }
            Text("Mantené apretada una foto y arrastrala para ordenar.").estilo(.footnote).foregroundStyle(C.texto3).padding(.horizontal, 4)
        }
    }

    private func botonFoto(_ icono: String, _ texto: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) { etiquetaFoto(icono, texto) }.buttonStyle(Presionable())
    }

    private func etiquetaFoto(_ icono: String, _ texto: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icono).font(.system(size: 24))
            Text(texto).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
        }
        .foregroundStyle(C.accion)
        .frame(width: 88, height: 88)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private func mover(_ i: Int, a j: Int) {
        guard i != j, d.fotos.indices.contains(i), d.fotos.indices.contains(j) else { return }
        let f = d.fotos.remove(at: i), u = d.fotosUrl.remove(at: i)
        d.fotos.insert(f, at: j)
        d.fotosUrl.insert(u, at: j)
        Haptico.impacto()
    }

    private func sacarFoto(_ i: Int) {
        let antes = d
        d.fotos.remove(at: i)
        d.fotosUrl.remove(at: i)
        estado.avisar("Foto sacada") { d = antes }
    }

    private func subir(_ datos: Data) async {
        subiendo += 1
        defer { subiendo -= 1 }
        let jpg = UIImage(data: datos)?.jpegData(compressionQuality: 0.85) ?? datos
        do {
            let a = try await estado.api.subir(jpg, nombre: "foto-\(Int(Date().timeIntervalSince1970)).jpg", tipo: "image/jpeg", uso: "foto")
            d.fotos.append(a.id)
            d.fotosUrl.append(a.url ?? "")
        } catch { estado.avisar(error) }
    }

    // MARK: Descripción

    private var descripcion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Descripción").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Button { dictado.grabando ? dictado.parar() : dictado.empezar(base: d.descripcion.isEmpty ? "" : d.descripcion + " ") } label: {
                    Label(dictado.grabando ? "Listo" : "Dictar", systemImage: dictado.grabando ? "stop.circle" : "mic")
                        .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
                        .padding(.horizontal, 12).frame(height: 36).background(C.avisoFondo, in: Capsule())
                }
            }
            TextField("Luminoso, al frente, con balcón…", text: $d.descripcion, axis: .vertical)
                .font(Estilo(tamano: 16, peso: .regular, relativo: .body).font).lineSpacing(4).lineLimit(3...12)
            if dictado.grabando {
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { i in
                        Capsule().fill(C.avisoTinta).frame(width: 3, height: 4 + CGFloat(abs(sin(Double(i) + ahora.timeIntervalSince1970 * 6))) * 18)
                    }
                }
                .frame(height: 22)
                .accessibilityHidden(true)
            }
        }
        .padding(14).tarjeta(16)
    }

    // MARK: Filas

    private func filaCampo(_ l: String, _ v: String, primera: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 10) {
                Text(l).estilo(.subhead).foregroundStyle(C.texto2).frame(width: 96, alignment: .leading)
                Text(v).font(Estilo(tamano: 16, peso: .medium, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func numero(_ l: String, _ v: Binding<Int?>) -> some View {
        HStack {
            Text(l).estilo(.subhead).foregroundStyle(C.texto2)
            Spacer()
            TextField("—", value: v, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).estilo(.body16).frame(width: 90)
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    private func decimal(_ l: String, _ v: Binding<Double?>) -> some View {
        HStack {
            Text(l).estilo(.subhead).foregroundStyle(C.texto2)
            Spacer()
            TextField("—", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).estilo(.body16).frame(width: 110)
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    // MARK: Guardar

    private func arrancar() async {
        if let inicial { d = inicial; return }
        if let editar {
            cargando = true
            defer { cargando = false }
            do {
                let p: Propiedad = try await estado.api.get("/v1/propiedades/\(editar)")
                base = p
                d = DatosAlta(p)
            } catch { estado.avisar(error) }
            return
        }
        do {
            let bs: [BorradorPropiedad] = try await estado.api.get("/v1/borradores")
            if let borrador {
                if let b = bs.first(where: { $0.id == borrador }) { seguir(b) } else { estado.avisar("Ese borrador ya no está: se publicó o se borró") }
            } else {
                paraSeguir = bs
            }
        } catch {
            if borrador != nil { estado.avisar(error) }
        }
    }

    @State private var esperaBorrador: Task<Void, Never>?
    /// El guardado en curso: los guardados van en fila (el primero crea el borrador y los que siguen
    /// lo actualizan), y no se cancelan a mitad del pedido.
    @State private var guardando: Task<Void, Never>?

    private func programarBorrador() {
        guard editar == nil else { return }
        esperaBorrador?.cancel()
        esperaBorrador = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            let previo = guardando
            guardando = Task {
                await previo?.value
                await guardarBorrador()
            }
        }
    }

    private func guardarBorrador() async {
        struct Creado: Decodable { var id: String }
        let cuerpo = BorradorAlta(paso: paso, datos: d)
        do {
            if let b = borradorId {
                try await estado.api.hacer("PUT", "/v1/borradores/\(b)", cuerpo)
            } else {
                let c: Creado = try await estado.api.enviar("POST", "/v1/borradores", cuerpo)
                borradorId = c.id
            }
            guardadoEn = Date()
            sinGuardar = false
        } catch {
            sinGuardar = true
        }
    }

    private func publicar() async {
        publicando = true
        defer { publicando = false }
        // Que no quede un guardado del borrador a medias (ni uno nuevo después de publicar).
        esperaBorrador?.cancel()
        await guardando?.value
        do {
            if let editar {
                guard let base else { return }
                try await estado.cola.enviar("PUT", "/v1/propiedades/\(editar)", d.cuerpo(base: base), etiqueta: "Cambios en \(d.direccion)")
                estado.avisar("Propiedad guardada")
            } else {
                let subio = try await estado.cola.enviar("POST", "/v1/propiedades", d.cuerpo(), etiqueta: "Alta de \(d.direccion)")
                if let b = borradorId {
                    do { try await estado.api.hacer("DELETE", "/v1/borradores/\(b)") } catch let e as ErrorApi where e.sinConexion {
                        // Sin señal queda en «a medio cargar»: se borra a mano.
                    } catch { estado.avisar(error) }
                }
                if subio {
                    estado.sugerir("\(d.direccion) quedó publicada en tu web", "Portales", ASeccion(clave: "difusion"))
                } else {
                    estado.avisar("En cola · se publica cuando vuelva la señal")
                }
            }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}

struct CampoAlta: Identifiable { var id: String }

/// La hoja para editar un campo del alta (tipo, dirección, barrio, precio, propietario).
struct EditorCampoAlta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var campo: String
    @Binding var d: DatosAlta
    @State private var texto = ""
    @State private var precio: Double?
    @State private var contactos: [Resultado] = []

    var body: some View {
        NavigationStack {
            Form {
                switch campo {
                case "tipo":
                    Picker("Tipo", selection: $d.tipo) { ForEach(Propiedad.tipos, id: \.0) { Text($0.1).tag($0.0) } }
                        .pickerStyle(.inline).labelsHidden()
                case "direccion":
                    TextField("Mendoza 2350, 5.º A", text: $d.direccion).textContentType(.fullStreetAddress)
                    TextField("Ciudad (opcional)", text: $d.ciudad)
                case "barrio":
                    TextField("Belgrano", text: $d.barrio)
                case "precio":
                    Picker("Moneda", selection: $d.moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("172000", value: $d.precio, format: .number).keyboardType(.numberPad)
                case "propietario":
                    TextField("Buscar contacto", text: $texto)
                    ForEach(contactos) { c in
                        Button {
                            d.propietarioId = c.id
                            d.propietarioNombre = c.titulo
                            cerrar()
                        } label: { VStack(alignment: .leading) { Text(c.titulo); if let s = c.subtitulo { Text(s).font(.footnote).foregroundStyle(.secondary) } } }
                    }
                default: EmptyView()
                }
            }
            .navigationTitle(["tipo": "Tipo", "direccion": "Dirección", "barrio": "Barrio", "precio": "Precio", "propietario": "Propietario"][campo] ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .task(id: texto) {
                guard campo == "propietario", texto.count >= 2 else { return }
                try? await Task.sleep(for: .milliseconds(220))
                contactos = ((try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: texto)])) as [Resultado]?) ?? []
            }
        }
    }
}

/// Dictado en español con el reconocimiento de voz del iPhone.
@Observable
@MainActor
final class Dictado {
    var texto = ""
    var grabando = false
    var base = ""
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-AR"))

    func empezar(base: String) {
        self.base = base
        texto = ""
        SFSpeechRecognizer.requestAuthorization { permiso in
            Task { @MainActor in
                guard permiso == .authorized else { return }
                self.arrancar()
            }
        }
    }

    private func arrancar() {
        let sesion = AVAudioSession.sharedInstance()
        try? sesion.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? sesion.setActive(true, options: .notifyOthersOnDeactivation)
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        pedido = p
        let entrada = motor.inputNode
        entrada.installTap(onBus: 0, bufferSize: 1024, format: entrada.outputFormat(forBus: 0)) { buffer, _ in p.append(buffer) }
        motor.prepare()
        try? motor.start()
        grabando = true
        tarea = reconocedor?.recognitionTask(with: p) { r, e in
            Task { @MainActor in
                if let r { self.texto = r.bestTranscription.formattedString }
                if e != nil || r?.isFinal == true { self.parar() }
            }
        }
    }

    func parar() {
        guard grabando else { return }
        motor.stop()
        motor.inputNode.removeTap(onBus: 0)
        pedido?.endAudio()
        tarea?.cancel()
        grabando = false
    }
}

/// La cámara del sistema para sacar una foto (UIImagePickerController).
struct Camara: UIViewControllerRepresentable {
    var alSacar: (Data) -> Void
    @Environment(\.dismiss) private var cerrar

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let padre: Camara
        init(_ p: Camara) { padre = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let i = info[.originalImage] as? UIImage, let d = i.jpegData(compressionQuality: 0.85) { padre.alSacar(d) }
            padre.cerrar()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { padre.cerrar() }
    }
}
