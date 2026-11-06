import AVFoundation
import PhotosUI
import Speech
import SwiftUI
import UniformTypeIdentifiers

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
            ficha: b?.ficha, destacada: b?.destacada, publicada: publicar["web"] ?? true,
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

/// Las 12 comodidades del alta (web: COMODIDADES) con su ícono y cómo se nombran en una descripción.
enum ComodidadesAlta {
    static let todas: [(nombre: String, icono: String, patron: String)] = [
        ("Balcón", "sun.max", "balcon"), ("Cochera", "car", "cochera|garage"), ("Luminoso", "light.max", "luminos[oa]"),
        ("Apto mascotas", "pawprint", "mascotas?"), ("Pileta", "figure.pool.swim", "pileta|piscina"), ("Parrilla", "flame", "parrilla"),
        ("Amenities", "dumbbell", "amenities|gimnasio"), ("Apto crédito", "building.columns", "apto credito"), ("Lavadero", "washer", "lavadero"),
        ("Baulera", "shippingbox", "baulera"), ("A estrenar", "sparkles", "a estrenar"), ("Vista abierta", "mountain.2", "vista abierta"),
    ]

    /// Las que se nombran en el texto (sin acentos), en orden de aparición.
    static func nombradas(_ texto: String) -> [String] {
        let t = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        var out: [(String, String.Index)] = []
        for c in todas {
            if let r = t.range(of: c.patron, options: .regularExpression) { out.append((c.nombre, r.lowerBound)) }
        }
        return out.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// «una», «dos»… para «Marcamos dos que nombraste».
    static func enLetras(_ n: Int) -> String {
        ["cero", "una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce"][safe: n] ?? "\(n)"
    }
}

/// Cómo salió en cada lugar al publicar.
struct SalidaAlta: Identifiable, Equatable {
    var lugar: String
    /// esperando · publicando · ok · revision · error
    var estado = "esperando"
    var detalle: String?
    var id: String { lugar }
}

/// 4A Alta (y edición) de una propiedad, con lo mismo que los cinco pasos de la web en una sola
/// pantalla: las fotos (con los ajustes de la subida), lo mínimo, la descripción (dictada, con audio
/// y las comodidades que nombra), el título para los portales, las comodidades y dónde publicarla. En
/// el alta se guarda sola como borrador (el mismo que se sigue en la web); en la edición cada cambio
/// se guarda solo. Al publicar, la pantalla «Publicada» muestra cómo salió en cada portal.
struct AltaPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    /// El id de la propiedad a editar (nil: una nueva).
    var editar: String?
    /// El id de un borrador de /v1/borradores para seguirlo.
    var borrador: String? = nil
    var inicial: DatosAlta? = nil
    /// Abrir en un paso puntual: «fotos», «comodidades» o «portales».
    var enPaso: String? = nil

    @State private var d = DatosAlta()
    /// En la edición, la propiedad entera como vino: el PUT parte de ella.
    @State private var base: Propiedad?
    @State private var paso = 0
    /// Los borradores a medio cargar (para seguir uno en vez de empezar otro).
    @State private var paraSeguir: [BorradorPropiedad] = []
    @State private var borradorId: String?
    @State private var guardadoEn: Date?
    /// nada · guardando · listo · error
    @State private var guardado = "nada"
    @State private var errores: [String: String] = [:]
    @State private var publicando = false
    @State private var elegidas: [PhotosPickerItem] = []
    @State private var subiendo = 0
    @State private var camara = false
    @State private var campo: String?
    @State private var masDatos = false
    @State private var dictado = Dictado()
    @State private var ahora = Date()
    @State private var sinPermiso = false
    /// Las fotos que la API enderezó o aclaró al subirlas, y si se está viendo el antes.
    @State private var ajustadas: Set<String> = []
    @State private var verAntes = false
    /// nada · subiendo · listo
    @State private var audio = "nada"
    @State private var dictadoGrabado = false
    @State private var eligiendoAudio = false
    /// En la edición: el estado de cada portal (publicada, error, finalizada…).
    @State private var portales: [String: String] = [:]
    /// La pantalla «Publicada» (nil mientras se carga).
    @State private var salidas: [SalidaAlta]?
    @State private var creada: Propiedad?
    @State private var interesadosN = 0
    @State private var envioAlta = UUID().uuidString
    @State private var web: String?
    @State private var ultimo: DatosAlta?

    var body: some View {
        Group {
            if sinPermiso {
                EstadoVacio(icono: "lock", titulo: "No podés cargar propiedades",
                            texto: "Tu rol es Lector: podés ver la cartera y compartirla. Para cargar una, pedile acceso a la dueña de la inmobiliaria.",
                            accion: ("Volver", { cerrar() }))
                    .frame(maxHeight: .infinity)
            } else if let salidas {
                publicada(salidas)
            } else {
                formulario
            }
        }
        .background(FondoApp())
        .navigationTitle(salidas != nil ? "Publicada" : editar == nil ? "Nueva propiedad" : "Editar propiedad")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            if salidas == nil, !sinPermiso {
                ToolbarItem(placement: .cancellationAction) { Button(editar == nil ? "Salir" : "Volver") { Task { await salir() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(etiquetaSeguir) { Task { await seguir() } }
                        .fontWeight(.semibold).disabled(publicando || subiendo > 0 || (editar != nil && base == nil))
                }
            } else if salidas != nil {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() }.disabled(publicando) }
            }
        }
        .sheet(item: Binding(get: { campo.map { CampoAlta(id: $0) } }, set: { campo = $0?.id })) { c in
            EditorCampoAlta(campo: c.id, d: $d).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $camara) { Camara { datos in Task { await subir(datos) } }.ignoresSafeArea() }
        .fileImporter(isPresented: $eligiendoAudio, allowedContentTypes: [.audio]) { r in
            if case .success(let u) = r { Task { await subirAudio(u, segundos: nil) } }
        }
        .onChange(of: elegidas) { _, items in
            Task {
                for i in items {
                    do { if let datos = try await i.loadTransferable(type: Data.self) { await subir(datos) } } catch { estado.avisar(error) }
                }
                elegidas = []
            }
        }
        .onChange(of: d) { _, nuevo in
            marcarNombradas(nuevo.descripcion)
            if !nuevo.tituloPropio, nuevo.titulo != nuevo.tituloSugerido { d.titulo = nuevo.tituloSugerido }
            programarGuardado()
        }
        .onChange(of: dictado.texto) { _, t in if dictado.grabando { d.descripcion = String((dictado.base + t).prefix(3000)) } }
        .task { await arrancar() }
        .task {
            dictado.alGrabar = { u, s in Task { await subirAudio(u, segundos: s) } }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                ahora = Date()
            }
        }
    }

    private var lugares: [String] { ["web", "mercadolibre", "zonaprop", "argenprop"].filter { d.publicar[$0] == true } }

    private var etiquetaSeguir: String {
        if editar != nil { return "Listo" }
        if publicando { return "Publicando…" }
        let n = lugares.count
        return n == 0 ? "Guardar sin publicar" : "Publicar en \(n) \(n == 1 ? "lugar" : "lugares")"
    }

    private var textoGuardado: String {
        if guardado == "guardando" { return "Guardando…" }
        if guardado == "error" { return "No se guardó" }
        guard guardado != "nada", let g = guardadoEn else { return editar != nil ? "Cada cambio se guarda solo" : "Se guarda solo como borrador" }
        let s = max(1, Int(ahora.timeIntervalSince(g)))
        return s < 60 ? "Guardado hace \(s) s" : "Guardado hace \(s / 60) min"
    }

    // MARK: Formulario

    private var formulario: some View {
        ScrollViewReader { lector in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    estadoGuardado
                    if editar == nil, borradorId == nil, !paraSeguir.isEmpty, d == DatosAlta() { aMedioCargar }
                    fotos.id("fotos")
                    lominimo
                    descripcion.id("descripcion")
                    titulo
                    comodidades.id("comodidades")
                    dondePublicar.id("portales")
                    mas
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 40)
            }
            .onAppear {
                guard let enPaso else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { lector.scrollTo(enPaso, anchor: .top) } }
            }
            .onChange(of: errores) { _, e in
                let a = e["fotos"] != nil ? "fotos" : e["titulo"] != nil ? "descripcion" : nil
                if let a { withAnimation { lector.scrollTo(a, anchor: .top) } }
            }
        }
    }

    private var estadoGuardado: some View {
        HStack(spacing: 6) {
            if guardado == "guardando" { ProgressView().controlSize(.mini) } else {
                Image(systemName: guardado == "error" ? "exclamationmark.icloud" : "checkmark.icloud")
            }
            Text(textoGuardado)
            if guardado == "error" { Button("Reintentar") { Task { await guardarYa() } }.fontWeight(.bold) }
        }
        .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
        .foregroundStyle(guardado == "error" ? C.errorTinta : C.okTinta)
        .padding(.horizontal, 12).frame(height: 28).background(guardado == "error" ? C.errorFondo : C.okFondo, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private var lominimo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmentado(opciones: [("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporario")], elegido: $d.operacion)
            VStack(spacing: 0) {
                filaCampo("Tipo", Propiedad.tipos.first { $0.0 == d.tipo }?.1 ?? d.tipo, primera: true) { campo = "tipo" }
                filaCampo("Dirección", d.direccion.nonEmpty ?? "Calle y altura, piso y depto") { campo = "direccion" }
                filaCampo("Barrio", d.barrio.nonEmpty ?? "Barrio") { campo = "barrio" }
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
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(errores["direccion"] != nil ? C.error : .clear, lineWidth: 1.5))
            if let e = errores["direccion"] { MensajeError(texto: e) }
            if let e = errores["precio"] ?? errores["tipo"] ?? errores["operacion"] { MensajeError(texto: e) }
            Text(Formato.sinViudas("Superficie, expensas y antigüedad las sumás después desde la ficha. No hacen falta para publicar."))
                .estilo(.footnote).foregroundStyle(C.texto3).padding(.horizontal, 4)
        }
    }

    private var titulo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Título para los portales").estilo(.footnoteFuerte).foregroundStyle(C.texto2)
            TextField("", text: Binding(get: { d.titulo }, set: { d.titulo = String($0.prefix(120)); d.tituloPropio = true }))
                .estilo(.body16).padding(.horizontal, 14).frame(height: 50).background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(errores["titulo"] != nil ? C.error : C.linea2, lineWidth: 1))
            let n = d.titulo.count
            Text("\(d.tituloPropio ? "Lo escribiste vos." : "Lo armamos de la descripción.") Mercado Libre corta en 60 caracteres: este tiene \(n)\(n > 60 ? ", sacale \(n - 60)" : "").")
                .estilo(.footnote).foregroundStyle(n > 60 ? C.avisoTinta : C.texto3)
            if let e = errores["titulo"] { MensajeError(texto: e) }
        }
    }

    private var sugeridasEnTexto: [String] { ComodidadesAlta.nombradas(d.descripcion).filter { d.comodidades.contains($0) } }

    /// Lo que se nombra se marca en Comodidades (una vez: si la persona la desmarca, queda así).
    private func marcarNombradas(_ texto: String) {
        let nuevas = ComodidadesAlta.nombradas(texto).filter { !d.sugeridas.contains($0) }
        guard !nuevas.isEmpty else { return }
        d.sugeridas += nuevas
        for n in nuevas where !d.comodidades.contains(n) { d.comodidades.append(n) }
    }

    private var comodidades: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COMODIDADES").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2)
                Spacer()
                Text("\(d.comodidades.count) \(d.comodidades.count == 1 ? "marcada" : "marcadas")").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .padding(.horizontal, 4)
            Text("Tocá las que tiene.\(sugeridasEnTexto.isEmpty ? "" : " Marcamos \(ComodidadesAlta.enLetras(sugeridasEnTexto.count)) que nombraste en la descripción.")")
                .estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
            FlujoLayout(espacio: 8) {
                ForEach(ComodidadesAlta.todas, id: \.nombre) { c in
                    let on = d.comodidades.contains(c.nombre)
                    Button {
                        Haptico.seleccion()
                        if on { d.comodidades.removeAll { $0 == c.nombre } } else { d.comodidades.append(c.nombre) }
                    } label: {
                        Label(c.nombre, systemImage: on ? "checkmark" : "plus")
                            .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(on ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(on ? C.accion : C.superficie, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? .clear : C.linea2, lineWidth: 1))
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var faltaPortales: [String] {
        var f: [String] = []
        if d.fotos.isEmpty { f.append("fotos") }
        if d.precio == nil { f.append("precio") }
        if d.direccion.trimmingCharacters(in: .whitespaces).count < 3 { f.append("dirección") }
        if d.descripcion.trimmingCharacters(in: .whitespacesAndNewlines).count < 30 { f.append("descripción") }
        return f
    }

    private func detalleLugar(_ l: String) -> String {
        if editar != nil, l != "web", portales[l] == "error" { return "La rechazó · mirá la ficha" }
        switch l {
        case "web": return (web ?? "tu web").replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        case "mercadolibre": return "publicación clásica"
        default: return "por feed, en 15 min"
        }
    }

    private var dondePublicar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DÓNDE PUBLICARLA").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
            Text(Formato.sinViudas("Un toque y sale en todos. Si un portal la rechaza, te decimos qué arreglar.")).estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(["web", "mercadolibre", "zonaprop", "argenprop"].enumerated()), id: \.element) { i, l in
                    HStack(spacing: 12) {
                        LogoPortal(portal: l)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(PublicacionPortal.nombres[l] ?? l).estilo(.filaLista).foregroundStyle(C.texto)
                            Text(detalleLugar(l)).estilo(.footnote).foregroundStyle(portales[l] == "error" && editar != nil ? C.errorTinta : C.texto2)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { d.publicar[l] == true }, set: { _ in Task { await alternarLugar(l) } })).labelsHidden().tint(C.ok)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 58)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta(16)
            let f = faltaPortales
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: f.isEmpty ? "checkmark.seal.fill" : "info.circle.fill").foregroundStyle(f.isEmpty ? C.okTinta : C.avisoTinta)
                Text(f.isEmpty ? "Tiene todo lo que piden los portales: \(Formato.cantidad(d.fotos.count, "foto", "fotos")), precio, dirección y descripción."
                     : "Para los portales falta \(Cartera.lista(f)). La web la muestra igual.")
                    .estilo(.footnote).foregroundStyle(C.texto)
            }
            .padding(12).background(f.isEmpty ? C.okFondo : C.avisoFondo, in: .rect(cornerRadius: 12, style: .continuous))
        }
    }

    private var mas: some View {
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
    }

    // MARK: A medio cargar

    /// «Para seguir»: los borradores de la persona (de la web, de otro aparato o de MIRA).
    private var aMedioCargar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARA SEGUIR").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5)
                .foregroundStyle(C.texto2).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(paraSeguir.enumerated()), id: \.element.id) { i, b in
                    Button { seguir(b) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.pencil").font(.system(size: 18)).foregroundStyle(C.oro).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.datos.datos.direccion.nonEmpty ?? "Sin dirección todavía").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                Text(["Paso \(b.datos.paso + 1) de 5", b.actualizadoEn.map { Formato.hace($0, ahora: ahora) }].compactMap { $0 }.joined(separator: " · "))
                                    .estilo(.footnote).foregroundStyle(C.texto2)
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
        ultimo = d
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
                        Foto(url: URL(string: verAntes && ajustadas.contains(d.fotos[safe: i] ?? "") ? u : u + (u.contains("?") ? "&" : "?") + "tam=chica"))
                            .frame(width: 88, height: 88).clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                Text("\(i + 1)").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle()).padding(6)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { sacarFoto(i) } label: {
                                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle()).padding(6)
                                }
                                .accessibilityLabel("Sacar esta foto")
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
            Text("Mantené apretada una foto y arrastrala para ordenar. La primera es la portada.").estilo(.footnote).foregroundStyle(C.texto3).padding(.horizontal, 4)
            if !ajustadas.isEmpty {
                Button { verAntes.toggle() } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wand.and.stars").foregroundStyle(C.avisoTinta)
                        Text(verAntes ? "Estás viendo el antes. Tocá para volver a las arregladas."
                             : "Enderezamos y aclaramos \(ajustadas.count == 1 ? "1 foto oscura" : "\(ajustadas.count) fotos oscuras"). Tocá para ver el antes.")
                            .estilo(.footnote).foregroundStyle(C.texto).multilineTextAlignment(.leading)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(C.avisoFondo, in: .rect(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(Presionable())
            }
            if let e = errores["fotos"] { MensajeError(texto: e) }
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
        guard d.fotos.indices.contains(i) else { return }
        let antes = d
        d.fotos.remove(at: i)
        d.fotosUrl.remove(at: i)
        estado.avisar("Sacamos la foto") { d = antes }
    }

    private func subir(_ datos: Data) async {
        subiendo += 1
        defer { subiendo -= 1 }
        let jpg = UIImage(data: datos)?.jpegData(compressionQuality: 0.85) ?? datos
        guard jpg.count <= 25 << 20 else { estado.avisar("El archivo pasa de 25 MB.", ok: false); return }
        struct Subida: Decodable { var id: String; var url: String?; var ajustes: [String]? }
        do {
            let raw = try await estado.api.multipart("/v1/archivos", query: [URLQueryItem(name: "uso", value: "foto")], datos: jpg,
                                                     nombre: "foto-\(Int(Date().timeIntervalSince1970)).jpg", tipo: "image/jpeg")
            let a = try Api.decodificador.decode(Subida.self, from: raw)
            d.fotos.append(a.id)
            d.fotosUrl.append(a.url ?? "")
            if !(a.ajustes ?? []).isEmpty { ajustadas.insert(a.id) }
        } catch { estado.avisar(error) }
    }

    // MARK: Descripción

    private var descripcion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Descripción").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Button { eligiendoAudio = true } label: {
                    Label(audio == "subiendo" ? "Subiendo…" : "Subir audio", systemImage: "waveform")
                        .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                        .padding(.horizontal, 12).frame(height: 36).background(C.hundida, in: Capsule())
                }
                .disabled(audio == "subiendo")
                Button { dictado.grabando ? dictado.parar() : dictado.empezar(base: d.descripcion.isEmpty ? "" : d.descripcion + " ") } label: {
                    Label(dictado.grabando ? "Terminar" : "Dictar", systemImage: dictado.grabando ? "stop.circle" : "mic")
                        .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
                        .padding(.horizontal, 12).frame(height: 36).background(C.avisoFondo, in: Capsule())
                }
            }
            Text(Formato.sinViudas("Contala como se la contarías a un interesado. Nosotros la pasamos en limpio para los portales."))
                .estilo(.footnote).foregroundStyle(C.texto2)
            TextField("Ej.: «Tres ambientes al frente, muy luminoso, balcón corrido, a dos cuadras de Cabildo…»",
                      text: Binding(get: { d.descripcion }, set: { d.descripcion = String($0.prefix(3000)) }), axis: .vertical)
                .font(Estilo(tamano: 16, peso: .regular, relativo: .body).font).lineSpacing(4).lineLimit(3...12)
            HStack {
                Text(dictado.grabando ? "Escuchando… tocá para terminar" : "Tocá para dictar · o escribí").estilo(.footnote).foregroundStyle(C.texto3)
                Spacer()
                Text("\(Formato.numero(d.descripcion.count)) / 3.000 caracteres").estilo(.footnote).foregroundStyle(d.descripcion.count >= 3000 ? C.avisoTinta : C.texto3)
            }
            if dictado.grabando {
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { i in
                        Capsule().fill(C.avisoTinta).frame(width: 3, height: 4 + CGFloat(abs(sin(Double(i) + ahora.timeIntervalSince1970 * 6))) * 18)
                    }
                }
                .frame(height: 22)
                .accessibilityHidden(true)
            }
            if audio == "listo" {
                pista("waveform", dictadoGrabado
                      ? (editar != nil ? "Guardamos el audio de lo que dictaste en la propiedad." : "Guardamos el audio de lo que dictaste: queda en la propiedad al publicar.")
                      : (editar != nil ? "Guardamos el audio en la propiedad." : "Guardamos el audio: queda en la propiedad al publicar."))
            }
            if !sugeridasEnTexto.isEmpty {
                let s = sugeridasEnTexto
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(C.avisoTinta)
                    Text("Mencionaste \(Cartera.lista(s)): \(s.count == 1 ? "la marcamos" : "las marcamos") en Comodidades.").estilo(.footnote).foregroundStyle(C.texto)
                    Spacer(minLength: 0)
                }
                .padding(10).background(C.avisoFondo, in: .rect(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14).tarjeta(16)
    }

    private func pista(_ icono: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icono).foregroundStyle(C.avisoTinta)
            Text(t).estilo(.footnote).foregroundStyle(C.texto)
            Spacer(minLength: 0)
        }
        .padding(10).background(C.avisoFondo, in: .rect(cornerRadius: 10, style: .continuous))
    }

    /// El audio de la descripción (subido o dictado) queda en la propiedad como grabación con el texto:
    /// en el alta va al borrador y se asocia al publicar; en la edición, va derecho.
    private func subirAudio(_ u: URL, segundos: Double?) async {
        audio = "subiendo"
        dictadoGrabado = segundos != nil
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        do {
            let datos = try Data(contentsOf: u)
            guard datos.count <= 25 << 20 else { audio = d.audioId == nil ? "nada" : "listo"; estado.avisar("El archivo pasa de 25 MB.", ok: false); return }
            let ext = u.pathExtension.lowercased()
            let tipo = ["mp3": "audio/mpeg", "ogg": "audio/ogg", "wav": "audio/wav", "aac": "audio/aac", "webm": "audio/webm"][ext] ?? "audio/mp4"
            let a = try await estado.api.subir(datos, nombre: u.lastPathComponent, tipo: tipo, uso: "audio")
            d.audioId = a.id
            d.audioSegundos = segundos
            if let id = base?.id { try await asociarAudio(id) }
            audio = "listo"
        } catch {
            audio = d.audioId == nil ? "nada" : "listo"
            estado.avisar(error)
        }
    }

    private func asociarAudio(_ propiedad: String) async throws {
        guard let a = d.audioId else { return }
        struct C: Encodable { var transcripcion: String; var audioId: String; var audioSegundos: Int? }
        _ = try await estado.api.pedir("POST", "/v1/propiedades/\(propiedad)/grabaciones",
                                       cuerpo: Api.codificador.encode(C(transcripcion: d.descripcion.trimmingCharacters(in: .whitespacesAndNewlines), audioId: a,
                                                                       audioSegundos: d.audioSegundos.map { Int($0.rounded()) })),
                                       envio: "audio-\(a)")
        d.audioId = nil
        d.audioSegundos = nil
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

    // MARK: Publicada

    private func publicada(_ salidas: [SalidaAlta]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    Foto(url: d.fotosUrl.first.flatMap(URL.init(string:))).frame(height: 240).frame(maxWidth: .infinity)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.precio.map { Formato.plata($0, d.moneda) } ?? "Consultar precio").font(Estilo(tamano: 26, peso: .bold, relativo: .title).font)
                        Text([d.direccion, d.barrio].filter { !$0.isEmpty }.joined(separator: " · ")).estilo(.subhead)
                    }
                    .foregroundStyle(.white).padding(16)
                }
                .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
                VStack(spacing: 0) {
                    if salidas.isEmpty {
                        filaSalida(icono: "square.and.pencil", tono: C.texto3, "Guardada sin publicar", nil, nil, primera: true)
                    }
                    ForEach(Array(salidas.enumerated()), id: \.element.id) { i, s in
                        let ok = s.estado == "ok" || s.estado == "revision"
                        filaSalida(icono: ok ? "checkmark.circle.fill" : s.estado == "error" ? "exclamationmark.circle.fill" : "clock",
                                   tono: ok ? C.okTinta : s.estado == "error" ? C.errorTinta : C.texto3,
                                   PublicacionPortal.nombres[s.lugar] ?? s.lugar, s.estado == "error" ? s.detalle : nil,
                                   s.estado == "ok" ? "Publicada" : s.estado == "revision" ? "En revisión de Mercado Libre" : s.estado == "error" ? "No la publicó" : "Publicando…",
                                   primera: i == 0)
                            .opacity(s.estado == "esperando" || s.estado == "publicando" ? 0.6 : 1)
                    }
                }
                .tarjeta()
                if interesadosN > 0, let c = creada {
                    Button { estado.abrir(AMandarPropiedad(id: c.id)) } label: {
                        Label("Mandar a \(interesadosN) \(interesadosN == 1 ? "interesado que le encaja" : "interesados que le encajan")", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BotonPrincipal())
                }
                if let c = creada { Button("Ver la ficha") { estado.abrir(AFichaPropiedad(id: c.id)) }.buttonStyle(BotonHundido()) }
                Button("Cargar otra") { cargarOtra() }.buttonStyle(BotonTexto()).frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private func filaSalida(icono: String, tono: Color, _ t: String, _ motivo: String?, _ st: String?, primera: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono).font(.system(size: 20)).foregroundStyle(tono)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                if let motivo { Text(motivo).estilo(.footnote).foregroundStyle(C.errorTinta) }
            }
            Spacer()
            if let st { Text(st).estilo(.footnote).foregroundStyle(C.texto2) }
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func cargarOtra() {
        d = DatosAlta()
        ultimo = nil
        borradorId = nil
        creada = nil
        salidas = nil
        interesadosN = 0
        ajustadas = []
        audio = "nada"
        guardado = "nada"
        envioAlta = UUID().uuidString
    }

    // MARK: Guardar

    private func arrancar() async {
        if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        if let inicial { d = inicial; return }
        if let editar {
            do {
                let p: Propiedad = try await estado.api.get("/v1/propiedades/\(editar)")
                base = p
                d = DatosAlta(p)
                ultimo = d
                guardado = "listo"
                let pubs: [PublicacionPortal] = (try? await estado.api.get("/v1/propiedades/\(editar)/publicaciones")) ?? []
                for x in pubs {
                    portales[x.portal] = x.estado
                    d.publicar[x.portal] = x.estado == "publicada" || x.estado == "activa"
                }
                ultimo = d
            } catch { estado.avisar(error) }
            return
        }
        do {
            let bs: [BorradorPropiedad] = try await estado.api.get("/v1/borradores")
            if let borrador {
                if let b = bs.first(where: { $0.id == borrador }) { seguir(b) } else { estado.avisar("Ese borrador ya no está: empezamos uno nuevo.") }
            } else {
                paraSeguir = bs
            }
        } catch let e as ErrorApi where e.estado == 403 {
            sinPermiso = true
        } catch {
            if borrador != nil { estado.avisar(error) }
        }
    }

    @State private var espera: Task<Void, Never>?
    /// El guardado en curso: los guardados van en fila (el primero crea el borrador y los que siguen
    /// lo actualizan), y no se cancelan a mitad del pedido.
    @State private var enFila: Task<Void, Never>?

    private func programarGuardado() {
        guard !publicando, salidas == nil, d != ultimo else { return }
        espera?.cancel()
        espera = Task {
            try? await Task.sleep(for: .milliseconds(editar == nil ? 800 : 700))
            if Task.isCancelled { return }
            await guardarYa()
        }
    }

    private func guardarYa() async {
        let previo = enFila
        let t = Task {
            await previo?.value
            await guardarAhora()
        }
        enFila = t
        await t.value
    }

    private func guardarAhora() async {
        guard d != ultimo else { return }
        let foto = d
        guardado = "guardando"
        struct Creado: Decodable { var id: String }
        do {
            if editar != nil, let b = base {
                let p: Propiedad = try await estado.api.conCampos("PUT", "/v1/propiedades/\(b.id)", d.cuerpo(base: b), como: Propiedad.self)
                base = p
            } else if let b = borradorId {
                try await estado.api.hacer("PUT", "/v1/borradores/\(b)", BorradorAlta(paso: paso, datos: foto))
            } else {
                let c: Creado = try await estado.api.enviar("POST", "/v1/borradores", BorradorAlta(paso: paso, datos: foto))
                borradorId = c.id
            }
            ultimo = foto
            guardado = "listo"
            guardadoEn = Date()
            errores = [:]
        } catch let e as ErrorConCampos {
            guardado = "error"
            errores = e.campos
        } catch {
            guardado = "error"
            if editar != nil { estado.avisar(error) }
        }
    }

    private func salir() async {
        dictado.parar()
        espera?.cancel()
        await guardarYa()
        if editar == nil, let id = borradorId {
            estado.sugerir("Quedó en borrador. Seguila cuando quieras.", "Seguir", AAltaPropiedad(borrador: id))
        }
        cerrar()
    }

    private func seguir() async {
        errores = [:]
        guard d.direccion.trimmingCharacters(in: .whitespaces).count >= 3 else {
            errores = ["direccion": "Poné la dirección: sin ella no se puede publicar."]
            return
        }
        if editar != nil {
            espera?.cancel()
            await guardarYa()
            if guardado != "error" { estado.version += 1; cerrar() }
            return
        }
        await publicar()
    }

    /// En la edición, cada portal se prende y apaga al toque (con deshacer al despublicar). En el alta,
    /// sólo se elige.
    private func alternarLugar(_ l: String) async {
        let antes = d.publicar[l] == true
        d.publicar[l] = !antes
        guard editar != nil, l != "web", let id = base?.id else { return }
        let nombre = PublicacionPortal.nombres[l] ?? l
        func hacer(_ prender: Bool) async {
            struct R: Decodable { var estado: String? }
            do {
                let raw = try await estado.api.pedir(prender ? "POST" : "DELETE", "/v1/propiedades/\(id)/publicaciones/\(l)")
                let x = try? Api.decodificador.decode(R.self, from: raw)
                portales[l] = x?.estado ?? (prender ? "publicada" : "finalizada")
                d.publicar[l] = portales[l] == "publicada"
                ultimo = d
                if portales[l] == "error" { estado.avisar("\(nombre) no la publicó. Mirá qué falta en la ficha.", ok: false) }
            } catch {
                d.publicar[l] = !prender
                ultimo = d
                estado.avisar(error)
            }
        }
        await hacer(!antes)
        if antes, d.publicar[l] != true {
            estado.avisar("Despublicada de \(nombre)") { Task { await hacer(true) } }
        }
    }

    private func publicar() async {
        espera?.cancel()
        await guardarYa()
        publicando = true
        defer { publicando = false }
        let ruta = "/v1/propiedades" + (borradorId.map { "?borrador=\($0)" } ?? "")
        let nueva: Propiedad
        do {
            nueva = try await estado.api.conCampos("POST", ruta, d.cuerpo(), envio: envioAlta, como: Propiedad.self)
        } catch let e as ErrorConCampos {
            errores = e.campos
            estado.avisar(e.error)
            return
        } catch let e as ErrorApi where e.sinConexion {
            // Sin señal, el alta queda en la cola y se sube sola.
            do {
                _ = try await estado.cola.enviar("POST", ruta, d.cuerpo(), etiqueta: "Alta de \(d.direccion)")
                estado.avisar("En cola · se publica cuando vuelva la señal")
                estado.version += 1
                cerrar()
            } catch { estado.avisar(error) }
            return
        } catch {
            estado.avisar(error)
            return
        }
        creada = nueva
        borradorId = nil
        estado.version += 1
        do { try await asociarAudio(nueva.id) } catch { estado.avisar("El audio de la descripción no se guardó en la propiedad.", ok: false) }
        var s = lugares.map { SalidaAlta(lugar: $0) }
        salidas = s
        if let xs: [Interesado] = try? await estado.api.get("/v1/propiedades/\(nueva.id)/interesados", query: [.init(name: "sinVisita", value: "si")]) { interesadosN = xs.count }
        struct R: Decodable { var estado: String?; var error: String? }
        for i in s.indices {
            s[i].estado = "publicando"
            salidas = s
            try? await Task.sleep(for: .milliseconds(350))
            if s[i].lugar == "web" { s[i].estado = "ok"; salidas = s; continue }
            do {
                let raw = try await estado.api.pedir("POST", "/v1/propiedades/\(nueva.id)/publicaciones/\(s[i].lugar)", envio: "\(envioAlta)-\(s[i].lugar)")
                let x = try? Api.decodificador.decode(R.self, from: raw)
                switch x?.estado {
                case "publicada": s[i].estado = s[i].lugar == "mercadolibre" ? "revision" : "ok"
                case "error": s[i].estado = "error"; s[i].detalle = x?.error
                default: s[i].estado = "revision"
                }
            } catch let e as ErrorApi {
                s[i].estado = "error"
                s[i].detalle = e.detalle
            } catch {
                s[i].estado = "error"
            }
            salidas = s
        }
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

/// Dictado en español con el reconocimiento de voz del iPhone. Además graba el audio (m4a) y, al
/// terminar, lo entrega con su duración (`alGrabar`): queda en la propiedad como grabación.
@Observable
@MainActor
final class Dictado {
    var texto = ""
    var grabando = false
    var base = ""
    /// El audio de lo dictado y cuántos segundos dura.
    @ObservationIgnored var alGrabar: ((URL, Double) -> Void)?
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var archivo: AVAudioFile?
    private var desde = Date()
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
        let formato = entrada.outputFormat(forBus: 0)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("descripcion-\(Int(Date().timeIntervalSince1970)).m4a")
        let ajustes: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: formato.sampleRate, AVNumberOfChannelsKey: formato.channelCount]
        let a = try? AVAudioFile(forWriting: u, settings: ajustes, commonFormat: formato.commonFormat, interleaved: formato.isInterleaved)
        archivo = a
        desde = Date()
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
            p.append(buffer)
            try? a?.write(from: buffer)
        }
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
        let segundos = Date().timeIntervalSince(desde)
        if let u = archivo?.url, segundos >= 2 {
            archivo = nil
            alGrabar?(u, segundos)
        }
        archivo = nil
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
