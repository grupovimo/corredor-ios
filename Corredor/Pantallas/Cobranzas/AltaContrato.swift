import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Lo que se carga (y el borrador de /v1/borradores?clase=contrato, con la forma de la web)

/// Algo elegido en el alta: una propiedad o un contacto.
struct ElegidoAlta: Codable, Hashable {
    var id: String
    var nombre: String
    var detalle: String? = nil
}

/// Un documento ya subido para colgarlo del contrato al crearlo.
struct DocumentoAlta: Codable, Hashable, Identifiable {
    var id: String
    var nombre: String
    var tipo: String
    var bytes: Int
}

/// Los datos del alta, como `DatosContrato` de lib/contratos/alta.ts: el borrador se sigue igual en
/// la web y en la app. Los nulos se escriben (un «Sin ajuste» tiene que llegar como `indice: null`).
struct DatosContratoAlta: Codable, Equatable {
    struct Renueva: Codable, Equatable { var id: String; var titulo: String }
    var tipo = "alquiler"
    var propiedad: ElegidoAlta?
    var inquilino: ElegidoAlta?
    var propietario: ElegidoAlta?
    var garanteNombre = ""
    var garanteTelefono = ""
    var garanteNotas = ""
    var inicio: String
    /// Duración en meses (el fin se calcula).
    var meses: Int? = 36
    var monto: Double?
    var moneda = "ARS"
    var diaVencimiento = 10
    var indice: String? = "icl"
    var ajusteMeses: Int? = 6
    var ajustePorcentaje: Double?
    var honorarios: Double?
    var comision: Double?
    var punitorioDiario: Double?
    var deposito: Double?
    var documentos: [DocumentoAlta] = []
    var notas = ""
    var renueva: Renueva?

    init(hoy: String = Formato.diaISO(Date())) { inicio = DatosContratoAlta.primeroDelMesQueViene(hoy) }

    static func primeroDelMesQueViene(_ hoy: String) -> String {
        guard let d = Fecha.dia(String(hoy.prefix(7)) + "-01"), let s = Calendar.current.date(byAdding: .month, value: 1, to: d) else { return hoy }
        return Formato.diaISO(s)
    }

    enum K: String, CodingKey {
        case tipo, propiedad, inquilino, propietario, garanteNombre, garanteTelefono, garanteNotas, inicio, meses, monto, moneda, diaVencimiento
        case indice, ajusteMeses, ajustePorcentaje, honorarios, comision, punitorioDiario, deposito, documentos, notas, renueva
    }

    /// Un borrador como venga, completado con lo que falta (como `desdeBorrador`).
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: K.self)
        func v<T: Decodable>(_ k: K) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        if let x: String = v(.tipo), x == "alquiler" || x == "venta" { tipo = x }
        propiedad = v(.propiedad)
        inquilino = v(.inquilino)
        propietario = v(.propietario)
        garanteNombre = v(.garanteNombre) ?? ""
        garanteTelefono = v(.garanteTelefono) ?? ""
        garanteNotas = v(.garanteNotas) ?? ""
        if let x: String = v(.inicio) { inicio = x }
        if c.contains(.meses) { meses = v(.meses) }
        monto = v(.monto)
        if let x: String = v(.moneda), x == "USD" { moneda = x }
        if let x: Int = v(.diaVencimiento) { diaVencimiento = x }
        if c.contains(.indice) { indice = v(.indice) }
        if c.contains(.ajusteMeses) { ajusteMeses = v(.ajusteMeses) }
        ajustePorcentaje = v(.ajustePorcentaje)
        honorarios = v(.honorarios)
        comision = v(.comision)
        punitorioDiario = v(.punitorioDiario)
        deposito = v(.deposito)
        documentos = v(.documentos) ?? []
        notas = v(.notas) ?? ""
        renueva = v(.renueva)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(propiedad, forKey: .propiedad)
        try c.encode(inquilino, forKey: .inquilino)
        try c.encode(propietario, forKey: .propietario)
        try c.encode(garanteNombre, forKey: .garanteNombre)
        try c.encode(garanteTelefono, forKey: .garanteTelefono)
        try c.encode(garanteNotas, forKey: .garanteNotas)
        try c.encode(inicio, forKey: .inicio)
        try c.encode(meses, forKey: .meses)
        try c.encode(monto, forKey: .monto)
        try c.encode(moneda, forKey: .moneda)
        try c.encode(diaVencimiento, forKey: .diaVencimiento)
        try c.encode(indice, forKey: .indice)
        try c.encode(ajusteMeses, forKey: .ajusteMeses)
        try c.encode(ajustePorcentaje, forKey: .ajustePorcentaje)
        try c.encode(honorarios, forKey: .honorarios)
        try c.encode(comision, forKey: .comision)
        try c.encode(punitorioDiario, forKey: .punitorioDiario)
        try c.encode(deposito, forKey: .deposito)
        try c.encode(documentos, forKey: .documentos)
        try c.encode(notas, forKey: .notas)
        try c.encode(renueva, forKey: .renueva)
    }

    var alquiler: Bool { tipo == "alquiler" }
}

/// `{paso, datos}` en /v1/borradores?clase=contrato.
struct BorradorContrato: Codable, Equatable {
    var paso = 0
    var datos = DatosContratoAlta()

    init(paso: Int = 0, datos: DatosContratoAlta = DatosContratoAlta()) {
        self.paso = paso
        self.datos = datos
    }

    enum K: String, CodingKey { case paso, datos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        paso = min(4, max(0, ((try? c.decodeIfPresent(Int.self, forKey: .paso)) ?? nil) ?? 0))
        datos = ((try? c.decodeIfPresent(DatosContratoAlta.self, forKey: .datos)) ?? nil) ?? DatosContratoAlta()
    }
}

/// Un borrador de GET /v1/borradores?clase=contrato.
struct BorradorContratoAPI: Decodable, Identifiable {
    var id: String
    var datos: BorradorContrato
    var actualizadoEn: Date?

    enum K: String, CodingKey { case id, datos, actualizadoEn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        datos = ((try? c.decodeIfPresent(BorradorContrato.self, forKey: .datos)) ?? nil) ?? BorradorContrato()
        actualizadoEn = (try? c.decodeIfPresent(Date.self, forKey: .actualizadoEn)) ?? nil
    }
}

// MARK: - Alta

/// El alta de un contrato (/contratos/nuevo): pasos cortos (Partes → Plazo y monto → Ajuste →
/// Condiciones → Documentos; una venta saltea Ajuste), validación por paso, guardado solo en un
/// borrador de /v1/borradores?clase=contrato («Guardado hace 2 s», «Seguir después») y «Subir el PDF y
/// que lo lea». Con `renovar` arranca desde el contrato anterior; con `operacion`, desde la operación.
struct AltaContrato: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var leer = false
    var renovar: String? = nil
    var operacion: String? = nil
    /// Seguir un borrador (el de la web, el de otro aparato).
    var borrador: String? = nil
    /// Apilada (desde una ruta) en vez de en una hoja.
    var apilada = false

    static let pasosNombre = ["Partes", "Plazo y monto", "Ajuste", "Condiciones", "Documentos"]
    static let titulos = ["¿Quiénes firman?", "Plazo y monto", "¿Cómo se ajusta?", "Condiciones", "Documentos"]
    static let indices: [(String?, String, String)] = [("icl", "ICL", "BCRA, diario"), ("ipc", "IPC", "INDEC, mensual"), ("uva", "UVA", "BCRA, diario"),
                                                        ("fijo", "Fijo", "un porcentaje"), (nil, "Sin ajuste", "monto fijo")]
    /// En qué paso se revisa cada dato leído (para marcar «No se lee bien» donde corresponde).
    static let pasoDe: [String: Int] = ["tipo": 0, "direccion": 0, "inquilino": 0, "propietario": 0, "garante": 0, "inicio": 1, "fin": 1, "meses": 1,
                                        "monto": 1, "moneda": 1, "diaVencimiento": 1, "ajusteIndice": 2, "ajusteMeses": 2, "ajustePorcentaje": 2,
                                        "garantia": 3, "deposito": 3, "honorarios": 3, "punitorioDiario": 3, "notas": 3]
    static let nombreDato: [String: String] = ["tipo": "el tipo", "direccion": "la dirección", "inquilino": "el inquilino", "propietario": "el propietario",
                                               "garante": "el garante", "garantia": "la garantía", "inicio": "el inicio", "fin": "el fin", "meses": "la duración",
                                               "monto": "el monto", "moneda": "la moneda", "diaVencimiento": "el día de vencimiento", "ajusteIndice": "el índice",
                                               "ajusteMeses": "cada cuánto ajusta", "ajustePorcentaje": "el porcentaje", "deposito": "el depósito",
                                               "honorarios": "los honorarios", "punitorioDiario": "el punitorio", "notas": "las notas"]

    @State private var d = DatosContratoAlta()
    @State private var paso = 0
    @State private var idBorrador: String?
    @State private var errores: [String: String] = [:]
    @State private var creando = false
    @State private var cargado = false
    @State private var sinPermiso = false
    @State private var paraSeguir: [BorradorContratoAPI] = []
    // Guardado.
    @State private var guardado = "nada"
    @State private var guardadoEn: Date?
    @State private var ultimoGuardado = ""
    @State private var espera: Task<Void, Never>?
    @State private var fila: Task<Void, Never>?
    @State private var envioAlta = UUID().uuidString
    // Leer el PDF.
    @State private var leyendo = false
    @State private var leidoDe: String?
    @State private var dudosos: [String] = []
    @State private var sugeridos: [String: String] = [:]
    @State private var eligiendoLectura = false
    @State private var fotoLectura: PhotosPickerItem?
    // Elegir y subir.
    @State private var eligiendo: String?
    @State private var eligiendoDoc = false
    @State private var fotoDoc: PhotosPickerItem?
    @State private var subiendoDoc = false
    // Textos de los campos con coma decimal.
    @State private var tHonorarios = ""
    @State private var tComision = ""
    @State private var tPunitorio = ""
    @State private var tPorcentaje = ""
    @State private var tDia = "10"
    @State private var tMeses = ""

    private var hoy: String { Formato.diaISO(Date()) }
    private var pasos: [Int] { d.alquiler ? [0, 1, 2, 3, 4] : [0, 1, 3, 4] }
    private var indicePaso: Int { max(0, pasos.firstIndex(of: paso) ?? 0) }
    private var ultimo: Bool { indicePaso == pasos.count - 1 }
    private var fin: String? { Self.finDe(d.inicio, d.meses) }
    private var kicker: String { d.renueva.map { "Renovación · \($0.titulo)" } ?? (d.alquiler ? "Contrato nuevo" : "Venta nueva") }
    private var titulo: String { d.renueva != nil ? "Renovar contrato" : "Nuevo contrato" }

    var body: some View {
        if apilada {
            contenido
        } else {
            NavigationStack { contenido }
        }
    }

    @ViewBuilder private var contenido: some View {
        Group {
            if sinPermiso {
                EstadoVacio(icono: "lock", titulo: "No podés cargar contratos",
                            texto: "Tu rol es Lector: podés ver los contratos y sus cobros. Para cargar uno, pedile acceso a la dueña de la inmobiliaria.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { lector in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            cabeza.id("arriba")
                            if !dudososAca.isEmpty {
                                Label("No se lee bien en el contrato: \(dudososAca.compactMap { Self.nombreDato[$0] }.joined(separator: ", ")). Revisalo.", systemImage: "questionmark.circle")
                                    .estilo(.footnote).foregroundStyle(C.avisoTinta).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(C.avisoFondo, in: .rect(cornerRadius: 12))
                            }
                            switch paso {
                            case 0: pasoPartes
                            case 1: pasoPlazo
                            case 2: pasoAjuste
                            case 3: pasoCondiciones
                            default: pasoDocumentos
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .onChange(of: paso) { _, _ in withAnimation { lector.scrollTo("arriba", anchor: .top) } }
                }
                .safeAreaInset(edge: .bottom) { pie }
            }
        }
        .background(C.fondo)
        .navigationTitle(titulo).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !apilada {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sinPermiso ? "Cerrar" : "Seguir después") { Task { await salir() } }
                }
            } else if !sinPermiso {
                ToolbarItem(placement: .topBarTrailing) { Button("Seguir después") { Task { await salir() } } }
            }
        }
        .interactiveDismissDisabled(!sinPermiso && d != DatosContratoAlta())
        .task { await arrancar() }
        .onChange(of: d) { _, _ in programarGuardado() }
        .onChange(of: paso) { _, _ in programarGuardado() }
        .sheet(item: Binding(get: { eligiendo.map { Eleccion(id: $0) } }, set: { eligiendo = $0?.id })) { e in eleccion(e.id) }
        .fileImporter(isPresented: $eligiendoLectura, allowedContentTypes: [.pdf, .image]) { r in
            if case .success(let u) = r { Task { await leerArchivo(u) } }
        }
        .onChange(of: fotoLectura) { _, i in
            guard let i else { return }
            Task {
                if let datos = try? await i.loadTransferable(type: Data.self) { await leerDatos(UIImage(data: datos)?.jpegData(compressionQuality: 0.85) ?? datos, nombre: "Contrato.jpg", tipo: "image/jpeg") }
                fotoLectura = nil
            }
        }
        .fileImporter(isPresented: $eligiendoDoc, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { r in
            if case .success(let us) = r { Task { for u in us { await subirDocArchivo(u) } } }
        }
        .onChange(of: fotoDoc) { _, i in
            guard let i else { return }
            Task {
                if let datos = try? await i.loadTransferable(type: Data.self) { await subirDoc(UIImage(data: datos)?.jpegData(compressionQuality: 0.85) ?? datos, nombre: "Foto \(Formato.diaISO(Date())).jpg", tipo: "image/jpeg") }
                fotoDoc = nil
            }
        }
    }

    struct Eleccion: Identifiable { var id: String }

    // MARK: Cabecera y pie

    private var cabeza: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(pasos.enumerated()), id: \.element) { i, _ in
                    Capsule().fill(i <= indicePaso ? C.accion : C.hundida).opacity(i < indicePaso ? 0.5 : 1).frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text(d.propiedad?.nombre ?? kicker).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                Spacer()
                estadoGuardado
            }
            Text(Self.titulos[paso]).estilo(.titulo).foregroundStyle(C.texto)
        }
    }

    @ViewBuilder private var estadoGuardado: some View {
        TimelineView(.periodic(from: .now, by: 1)) { t in
            HStack(spacing: 4) {
                Image(systemName: guardado == "error" ? "exclamationmark.icloud" : guardado == "guardando" ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                Text(textoGuardado(t.date))
                if guardado == "error" { Button("Reintentar") { programarGuardado(ya: true) }.font(Estilo.footnoteFuerte.font) }
            }
            .estilo(.caption).foregroundStyle(guardado == "error" ? C.errorTinta : C.texto3)
        }
    }

    private func textoGuardado(_ ahora: Date) -> String {
        if guardado == "guardando" { return "Guardando…" }
        if guardado == "error" { return "No se guardó" }
        guard guardado != "nada", let g = guardadoEn else { return "Se guarda solo" }
        let s = max(1, Int(ahora.timeIntervalSince(g).rounded()))
        return s < 60 ? "Guardado hace \(s) s" : "Guardado hace \(s / 60) min"
    }

    private var pie: some View {
        HStack(spacing: 8) {
            if indicePaso > 0 { Button("Atrás") { paso = pasos[indicePaso - 1]; errores = [:] }.buttonStyle(BotonHundido()).frame(width: 100) }
            Button { Task { await seguir() } } label: {
                HStack(spacing: 6) {
                    if creando { ProgressView().tint(C.sobreAccion) }
                    Text(ultimo ? "Crear contrato" : "Seguir: \(Self.pasosNombre[pasos[min(indicePaso + 1, pasos.count - 1)]])")
                    Image(systemName: ultimo ? "checkmark" : "arrow.right")
                }
            }
            .buttonStyle(BotonAccion()).disabled(creando)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(C.fondo)
    }

    // MARK: Paso 0 · Partes

    private var yaLeido: Bool { !dudosos.isEmpty || !sugeridos.isEmpty || d.documentos.contains { $0.id == leidoDe } }

    @ViewBuilder private var pasoPartes: some View {
        if idBorrador == nil && renovar == nil && operacion == nil && !paraSeguir.isEmpty && d == DatosContratoAlta() { aMedioCargar }
        tarjetaLeer
        Etiquetado("Contrato de") {
            Segmentado(opciones: [("alquiler", "Alquiler"), ("venta", "Venta")], elegido: $d.tipo)
        }
        campoElegir("Propiedad", d.propiedad, sugerido: sugeridos["propiedad"], dudoso: dudosos.contains("direccion"), error: errores["propiedadId"], clave: "propiedad", opcional: false)
        campoElegir(d.alquiler ? "Inquilino" : "Comprador", d.inquilino, sugerido: sugeridos["inquilino"], dudoso: dudosos.contains("inquilino"), error: errores["contactoId"], clave: "inquilino", opcional: false)
        campoElegir("Propietario", d.propietario, sugerido: sugeridos["propietario"], dudoso: dudosos.contains("propietario"), error: errores["propietarioId"], clave: "propietario", opcional: true)
        if d.alquiler {
            Etiquetado("Garante (opcional)") {
                VStack(spacing: 8) {
                    TextField("Nombre y apellido", text: $d.garanteNombre).campoCorredor().textContentType(.name)
                    TextField("Teléfono", text: $d.garanteTelefono).keyboardType(.phonePad).campoCorredor()
                    TextField("Garantía: recibo de sueldo, propietaria, seguro de caución…", text: $d.garanteNotas).campoCorredor()
                    ForEach(["garanteNombre", "garanteTelefono", "garanteNotas"], id: \.self) { k in if let e = errores[k] { textoError(e) } }
                }
            }
        }
    }

    private var tarjetaLeer: some View {
        Menu {
            Button { eligiendoLectura = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
            PhotosPicker(selection: $fotoLectura, matching: .images) { Label("Una foto", systemImage: "camera") }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if leyendo { ProgressView() } else { Image(systemName: yaLeido ? "checkmark.circle.fill" : "sparkles").font(.system(size: 22)) }
                }
                .foregroundStyle(yaLeido ? C.okTinta : C.accion).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leyendo ? "Leyendo el contrato…" : yaLeido ? "Leímos el contrato" : "Subir el PDF y que lo lea").estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Text(leyendo ? "Tarda unos segundos." : yaLeido ? "Revisá cada paso. Podés subir otro." : "O una foto. Completamos lo que se lea.").estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer()
            }
            .padding(14).background(yaLeido ? C.okFondo : C.superficie, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1, dash: yaLeido ? [] : [5])))
        }
        .disabled(leyendo)
    }

    private func campoElegir(_ etiqueta: String, _ v: ElegidoAlta?, sugerido: String?, dudoso: Bool, error: String?, clave: String, opcional: Bool) -> some View {
        Etiquetado(etiqueta + (opcional ? " (opcional)" : "")) {
            HStack(spacing: 6) {
            Button { eligiendo = clave } label: {
                HStack(spacing: 10) {
                    Image(systemName: clave == "propiedad" ? "house" : "person").foregroundStyle(C.texto2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v?.nombre ?? (sugerido.map { "¿\($0)?" } ?? "Elegí")).estilo(.body).foregroundStyle(v == nil ? C.texto3 : C.texto)
                        if let det = v?.detalle { Text(det).estilo(.footnote).foregroundStyle(C.texto2) } else if v == nil, sugerido != nil {
                            Text("Lo leímos del contrato: tocá para buscarlo o cargarlo").estilo(.footnote).foregroundStyle(C.avisoTinta)
                        }
                    }
                    Spacer()
                    if dudoso { Text("Revisá").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.avisoTinta).padding(.horizontal, 8).frame(height: 22).background(C.avisoFondo, in: Capsule()) }
                    Chevron()
                }
                .padding(.horizontal, 14).frame(minHeight: 50)
                .background(C.superficie, in: .rect(cornerRadius: M.rControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: M.rControl, style: .continuous).strokeBorder(error == nil ? C.linea2 : C.error))
            }
            .buttonStyle(Presionable())
            if v != nil && opcional {
                Button { d.propietario = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(C.texto3).frame(width: 36, height: 44) }
                    .accessibilityLabel("Sacar \(etiqueta.lowercased())")
            }
            }
            if let error { textoError(error) }
        }
    }

    private func textoError(_ e: String) -> some View {
        Label(e, systemImage: "exclamationmark.circle").estilo(.footnote).foregroundStyle(C.errorTinta)
    }

    /// Los borradores a medio cargar («Para seguir»).
    private var aMedioCargar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Para seguir")
            VStack(spacing: 0) {
                ForEach(Array(paraSeguir.enumerated()), id: \.element.id) { i, b in
                    Button { seguirBorrador(b) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.pencil").foregroundStyle(C.oroTinta).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.datos.datos.propiedad?.nombre ?? "Sin propiedad todavía").estilo(.filaLista).foregroundStyle(C.texto)
                                Text("\(Self.pasosNombre[b.datos.paso]) · \(b.actualizadoEn.map { Formato.hace($0) } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer()
                            Chevron()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    // MARK: Paso 1 · Plazo y monto

    @ViewBuilder private var pasoPlazo: some View {
        Etiquetado("Empieza el") {
            DatePicker("", selection: Binding(get: { Fecha.dia(d.inicio) ?? Date() }, set: { d.inicio = Formato.diaISO($0) }), displayedComponents: .date)
                .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            if let e = errores["inicio"] { textoError(e) }
        }
        if d.alquiler {
            Etiquetado("Vence el pago") {
                HStack {
                    Text("día").foregroundStyle(C.texto2)
                    TextField("10", text: $tDia).keyboardType(.numberPad)
                        .onChange(of: tDia) { _, v in if let n = Int(v.filter(\.isNumber)), (1...31).contains(n) { d.diaVencimiento = n } }
                }
                .campoCorredor()
                Text("Día de cada mes (1 a 31)").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Etiquetado("Dura") {
                HStack(spacing: 8) {
                    ForEach([24, 36], id: \.self) { m in
                        let on = d.meses == m && tMeses.isEmpty
                        Button { d.meses = m; tMeses = "" } label: {
                            Text("\(m) meses").estilo(.subheadFuerte).foregroundStyle(on ? C.sobreAccion : C.texto).frame(maxWidth: .infinity, minHeight: 44)
                                .background(on ? C.accion : C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(Presionable()).accessibilityAddTraits(on ? .isSelected : [])
                    }
                    HStack(spacing: 4) {
                        TextField("Otra", text: $tMeses).keyboardType(.numberPad).multilineTextAlignment(.center)
                            .onChange(of: tMeses) { _, v in
                                guard !v.isEmpty else { return }
                                let n = Int(v.filter(\.isNumber)) ?? 0
                                d.meses = n > 0 && n <= 240 ? n : nil
                            }
                            .accessibilityLabel("Otra duración, en meses")
                        if !tMeses.isEmpty { Text("meses").estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                    .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44)
                    .background(tMeses.isEmpty ? C.hundida : C.okFondo, in: .rect(cornerRadius: 12, style: .continuous))
                }
                if let fin { Text("Termina el \(Self.fmtFecha(fin)) · \(Self.mesesEntre(d.inicio, fin)) meses.").estilo(.footnote).foregroundStyle(C.texto2) }
                if let e = errores["fin"] { textoError(e) }
            }
        }
        Etiquetado(d.alquiler ? "Alquiler del primer mes" : "Monto de la venta") {
            HStack(spacing: 8) {
                Picker("Moneda", selection: $d.moneda) { Text("ARS").tag("ARS"); Text("USD").tag("USD") }.pickerStyle(.segmented).frame(width: 110)
                TextField("0", value: $d.monto, format: .number).keyboardType(.numberPad).campoCorredor()
            }
            if let e = errores["monto"] { textoError(e) }
        }
        if d.renueva != nil {
            Text("Viene del alquiler de hoy del contrato anterior, con el último ajuste. Cambialo si pactaron otro.").estilo(.footnote).foregroundStyle(C.texto2)
        }
    }

    // MARK: Paso 2 · Ajuste

    @ViewBuilder private var pasoAjuste: some View {
        Etiquetado("Índice") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.indices, id: \.1) { i in
                    let on = d.indice == i.0
                    Button { elegirIndice(i.0) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(i.1).estilo(.subheadFuerte)
                            Text(i.2).estilo(.footnote).opacity(0.8)
                        }
                        .foregroundStyle(on ? C.sobreAccion : C.texto).padding(10).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(on ? C.accion : C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(Presionable()).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        if let indice = d.indice {
            Etiquetado("Se ajusta cada") {
                Segmentado(opciones: [(3, "3 meses"), (4, "4 meses"), (6, "6 meses"), (12, "12 meses")],
                           elegido: Binding(get: { d.ajusteMeses ?? 6 }, set: { d.ajusteMeses = $0 }))
                if let e = errores["ajusteMeses"] { textoError(e) }
            }
            if indice == "fijo" {
                Etiquetado("Aumento en cada ajuste") {
                    campoPorcentaje($tPorcentaje, sufijo: "%") { d.ajustePorcentaje = $0 }
                    if let e = errores["ajustePorcentaje"] { textoError(e) }
                }
            }
            Label {
                Text(indice == "fijo"
                     ? "Cada \(d.ajusteMeses ?? 0) meses el alquiler sube \(tPorcentaje.isEmpty ? "0" : tPorcentaje)\u{00A0}%. Te avisamos antes para que se lo cuentes a las\u{00A0}partes."
                     : "Cada \(d.ajusteMeses ?? 0) meses, el alquiler se multiplica por lo que subió el \(TextosCobro.nombreIndice[indice] ?? "") en ese período. Corredor hace la cuenta, te la explica y te avisa\u{00A0}antes.")
            } icon: { Image(systemName: "function").foregroundStyle(C.okTinta) }
                .estilo(.footnote).foregroundStyle(C.texto2).padding(12).background(C.okFondo, in: .rect(cornerRadius: 12))
        } else {
            Text("El alquiler queda igual todo el contrato.").estilo(.footnote).foregroundStyle(C.texto2)
        }
    }

    private func campoPorcentaje(_ t: Binding<String>, sufijo: String, _ poner: @escaping (Double?) -> Void) -> some View {
        HStack {
            TextField("0", text: t).keyboardType(.decimalPad).onChange(of: t.wrappedValue) { _, v in poner(Self.leerPorcentaje(v)) }
            Text(sufijo).foregroundStyle(C.texto2)
        }
        .campoCorredor()
    }

    // MARK: Paso 3 · Condiciones

    private var totalContrato: Double { d.alquiler && (d.monto ?? 0) > 0 && (d.meses ?? 0) > 0 ? (d.monto ?? 0) * Double(d.meses ?? 0) : (d.monto ?? 0) }
    private var honorariosMonto: Double? { (d.honorarios ?? 0) > 0 && totalContrato > 0 ? (totalContrato * (d.honorarios ?? 0) / 100).rounded() : nil }

    @ViewBuilder private var pasoCondiciones: some View {
        Etiquetado("Honorarios (opcional)") {
            campoPorcentaje($tHonorarios, sufijo: "%") { d.honorarios = $0 }
            Text(honorariosMonto.map { "\(Formato.plata($0, d.moneda)) del total del contrato" } ?? "Del total del contrato").estilo(.footnote).foregroundStyle(C.texto2)
            if let e = errores["honorarios"] { textoError(e) }
        }
        Etiquetado(d.alquiler ? "Administración (opcional)" : "Comisión (opcional)") {
            campoPorcentaje($tComision, sufijo: "%") { d.comision = $0 }
            Text(d.alquiler ? "De lo cobrado cada mes; se descuenta al rendir" : "Sobre el monto de la venta").estilo(.footnote).foregroundStyle(C.texto2)
            if let e = errores["comision"] { textoError(e) }
        }
        if d.alquiler {
            Etiquetado("Punitorios (opcional)") {
                campoPorcentaje($tPunitorio, sufijo: "% diario") { d.punitorioDiario = $0 }
                Text("Por día de atraso, sobre el alquiler del mes").estilo(.footnote).foregroundStyle(C.texto2)
                if let e = errores["punitorioDiario"] { textoError(e) }
            }
            Etiquetado("Depósito") {
                HStack {
                    Text(d.moneda).foregroundStyle(C.texto2)
                    TextField("0", value: $d.deposito, format: .number).keyboardType(.numberPad)
                }
                .campoCorredor()
                if let m = d.monto, m > 0, d.deposito != m {
                    Button("Un mes de alquiler: \(Formato.plata(m, d.moneda))") { d.deposito = m }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                }
                if let e = errores["deposito"] { textoError(e) }
            }
        }
    }

    // MARK: Paso 4 · Documentos

    @ViewBuilder private var pasoDocumentos: some View {
        Text("El contrato firmado, el acta de entrega, el DNI de las partes. Lo podés sumar después desde la\u{00A0}ficha.").estilo(.subhead).foregroundStyle(C.texto2)
        VStack(spacing: 0) {
            ForEach(Array(d.documentos.enumerated()), id: \.element.id) { i, doc in
                HStack(spacing: 12) {
                    Image(systemName: doc.tipo.contains("pdf") ? "doc.richtext" : "photo").foregroundStyle(C.azulTinta).frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(doc.bytes), countStyle: .file)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer()
                    Button { sacarDoc(doc) } label: { Image(systemName: "trash").foregroundStyle(C.texto3).frame(width: 44, height: 44) }.accessibilityLabel("Sacar \(doc.nombre)")
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
            Menu {
                Button { eligiendoDoc = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                PhotosPicker(selection: $fotoDoc, matching: .images) { Label("Una foto", systemImage: "photo") }
            } label: {
                Label(subiendoDoc ? "Subiendo…" : "Tocá para subir un archivo", systemImage: "arrow.up.doc").estilo(.subheadFuerte).foregroundStyle(C.accion)
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            }
            .disabled(subiendoDoc)
            .overlay(alignment: .top) { if !d.documentos.isEmpty { Rectangle().fill(C.linea).frame(height: 0.5) } }
        }
        .tarjeta()
        Etiquetado("Notas (opcional)") {
            TextField("Lo que conviene recordar: cláusulas especiales, acuerdos de palabra…", text: $d.notas, axis: .vertical)
                .lineLimit(3...8).padding(.vertical, 12).campoCorredor()
            if let e = errores["notas"] { textoError(e) }
        }
    }

    // MARK: Elegir

    @ViewBuilder private func eleccion(_ clave: String) -> some View {
        switch clave {
        case "propiedad":
            ElegirPropiedadAlta(operacion: d.tipo, sugerido: sugeridos["propiedad"]) { p in
                d.propiedad = p
                sugeridos["propiedad"] = nil
                errores["propiedadId"] = nil
                Task { await propietarioDe(p) }
            }
        case "inquilino":
            ElegirParteAlta(tipo: d.alquiler ? "inquilino" : "comprador", sugerido: sugeridos["inquilino"]) { c in
                d.inquilino = c
                sugeridos["inquilino"] = nil
                errores["contactoId"] = nil
            }
        default:
            ElegirParteAlta(tipo: "propietario", sugerido: sugeridos["propietario"]) { c in
                d.propietario = c
                sugeridos["propietario"] = nil
            }
        }
    }

    /// El propietario de la propiedad, si está cargado, viene solo.
    private func propietarioDe(_ p: ElegidoAlta) async {
        guard d.propietario == nil else { return }
        struct Prop: Decodable { var propietarioId: String? }
        struct Ct: Decodable { var id: String; var nombre: String }
        guard let pr: Prop = try? await estado.api.get("/v1/propiedades/\(p.id)"), let pid = pr.propietarioId,
              let c: Ct = try? await estado.api.get("/v1/contactos/\(pid)"), d.propietario == nil else { return }
        d.propietario = ElegidoAlta(id: c.id, nombre: c.nombre, detalle: "Propietario de la propiedad")
    }

    // MARK: Pasos

    /// Lo que falta para seguir desde un paso (campo → mensaje).
    private func faltan(_ p: Int) -> [String: String] {
        var e: [String: String] = [:]
        if p == 0 {
            if d.propiedad == nil { e["propiedadId"] = "Elegí la propiedad del contrato." }
            if d.inquilino == nil { e["contactoId"] = d.alquiler ? "Elegí quién alquila." : "Elegí quién compra." }
        }
        if p == 1 {
            if Fecha.dia(d.inicio) == nil { e["inicio"] = "Poné la fecha de inicio." }
            if d.alquiler && (d.meses ?? 0) <= 0 { e["fin"] = "Poné cuántos meses dura." }
            if (d.monto ?? 0) <= 0 { e["monto"] = d.alquiler ? "Poné el alquiler del primer mes." : "Poné el monto de la venta." }
        }
        if p == 2 && d.alquiler && d.indice != nil {
            if (d.ajusteMeses ?? 0) <= 0 { e["ajusteMeses"] = "Elegí cada cuántos meses se ajusta." }
            if d.indice == "fijo" && (d.ajustePorcentaje ?? 0) <= 0 { e["ajustePorcentaje"] = "Poné el porcentaje de cada aumento." }
        }
        return e
    }

    private func revisar(hasta: Int) -> Bool {
        for p in pasos where p < hasta {
            let e = faltan(p)
            if !e.isEmpty { errores = e; paso = p; return false }
        }
        errores = [:]
        return true
    }

    private var dudososAca: [String] { paso == 0 ? [] : dudosos.filter { Self.pasoDe[$0] == paso } }

    private func seguir() async {
        guard !creando else { return }
        let e = faltan(paso)
        if !e.isEmpty { errores = e; Haptico.error(); return }
        errores = [:]
        if !ultimo { paso = pasos[indicePaso + 1]; return }
        await crear()
    }

    private func elegirIndice(_ v: String?) {
        d.indice = v
        if v != nil && (d.ajusteMeses ?? 0) <= 0 { d.ajusteMeses = v == "ipc" ? 3 : 6 }
    }

    // MARK: Guardado

    private var cuerpoBorrador: BorradorContrato { BorradorContrato(paso: paso, datos: d) }

    private func firma() -> String {
        (try? String(data: Api.codificador.encode(cuerpoBorrador), encoding: .utf8)) ?? ""
    }

    private func programarGuardado(ya: Bool = false) {
        guard cargado, !creando, !sinPermiso else { return }
        espera?.cancel()
        espera = Task {
            if !ya { try? await Task.sleep(for: .milliseconds(700)) }
            if Task.isCancelled { return }
            let previa = fila
            fila = Task {
                await previa?.value
                await guardarYa()
            }
        }
    }

    private func guardarYa() async {
        let s = firma()
        guard s != ultimoGuardado, !creando else { return }
        guardado = "guardando"
        struct Creado: Decodable { var id: String }
        do {
            if let b = idBorrador {
                try await estado.api.hacer("PUT", "/v1/borradores/\(b)", cuerpoBorrador)
            } else {
                let c: Creado = try await estado.api.enviar("POST", "/v1/borradores?clase=contrato", cuerpoBorrador)
                idBorrador = c.id
            }
            ultimoGuardado = s
            guardado = "listo"
            guardadoEn = Date()
        } catch {
            guardado = "error"
        }
    }

    /// «Seguir después»: queda en borrador y se sigue cuando se quiera.
    private func salir() async {
        espera?.cancel()
        if !sinPermiso && d != DatosContratoAlta() {
            await fila?.value
            await guardarYa()
        }
        if let id = idBorrador {
            estado.sugerir("Quedó en borrador. Seguilo cuando quieras.", "Seguir", AAltaContrato(borrador: id))
        }
        cerrar()
    }

    // MARK: Crear

    private struct Cuerpo: Encodable {
        var tipo: String; var estado = "vigente"; var propiedadId: String?; var contactoId: String?; var propietarioId: String?; var agenteId: String?
        var inicio: String; var fin: String?; var monto: Double; var moneda: String; var ajusteMeses: Int?; var ajusteIndice: String?; var ajustePorcentaje: Double?
        var comision: Double; var honorarios: Double?; var punitorioDiario: Double?; var deposito: Double?; var diaVencimiento: Int?
        var garanteNombre: String?; var garanteTelefono: String?; var garanteNotas: String?; var notas: String?
    }

    private func cuerpo() -> Cuerpo {
        let a = d.alquiler
        return Cuerpo(tipo: d.tipo, propiedadId: d.propiedad?.id, contactoId: d.inquilino?.id, propietarioId: d.propietario?.id, agenteId: estado.usuario?.id,
                      inicio: d.inicio, fin: a ? Self.finDe(d.inicio, d.meses) : nil, monto: d.monto ?? 0, moneda: d.moneda,
                      ajusteMeses: a && d.indice != nil ? d.ajusteMeses : nil, ajusteIndice: a ? d.indice : nil,
                      ajustePorcentaje: a && d.indice == "fijo" ? d.ajustePorcentaje : nil, comision: d.comision ?? 0, honorarios: d.honorarios,
                      punitorioDiario: a ? d.punitorioDiario : nil, deposito: d.deposito, diaVencimiento: a ? d.diaVencimiento : nil,
                      garanteNombre: d.garanteNombre.nonEmpty, garanteTelefono: d.garanteTelefono.nonEmpty, garanteNotas: d.garanteNotas.nonEmpty, notas: d.notas.nonEmpty)
    }

    private func crear() async {
        guard revisar(hasta: 99) else { return }
        espera?.cancel()
        await fila?.value
        await guardarYa()
        creando = true
        struct Nuevo: Decodable { var id: String }
        let ruta = "/v1/contratos" + (idBorrador.map { "?borrador=\($0)" } ?? "")
        let n: Nuevo
        do {
            let datos = try await estado.api.pedir("POST", ruta, cuerpo: Api.codificador.encode(cuerpo()), envio: envioAlta)
            n = try Api.decodificador.decode(Nuevo.self, from: datos)
        } catch {
            creando = false
            estado.sugerir((error as? ErrorApi).map { $0.detalle.isEmpty ? $0.titulo : $0.detalle } ?? "No se creó el contrato.", "Reintentar") { Task { await crear() } }
            return
        }
        // Los documentos ya subidos se cuelgan del contrato.
        var sinSubir: [String] = []
        for doc in d.documentos {
            struct Doc: Encodable { var archivoId: String; var contratoId: String; var nombre: String }
            do {
                _ = try await estado.api.pedir("POST", "/v1/documentos", cuerpo: Api.codificador.encode(Doc(archivoId: doc.id, contratoId: n.id, nombre: doc.nombre)),
                                               envio: "\(envioAlta)-\(doc.id.prefix(8))")
            } catch { sinSubir.append(doc.nombre) }
        }
        estado.version += 1
        cerrar()
        estado.abrir(AFichaContrato(id: n.id))
        estado.avisar(sinSubir.isEmpty ? "Contrato cargado. Ya calcula ajustes y cobros." : "Contrato cargado. Faltó sumar \(sinSubir.joined(separator: ", ")): subilo desde la ficha.",
                      ok: sinSubir.isEmpty)
    }

    // MARK: Arranque

    private func arrancar() async {
        guard !cargado else { return }
        let bs: [BorradorContratoAPI]
        do {
            bs = try await estado.api.get("/v1/borradores", query: [.init(name: "clase", value: "contrato")])
        } catch let e as ErrorApi where e.estado == 403 {
            sinPermiso = true
            cargado = true
            return
        } catch {
            bs = []
        }
        paraSeguir = bs
        if let borrador {
            if let b = bs.first(where: { $0.id == borrador }) { seguirBorrador(b) } else { estado.avisar("Ese borrador ya no está: empezamos uno nuevo.") }
        } else if let renovar {
            await desdeContrato(renovar)
        } else if let operacion {
            await desdeOperacion(operacion)
        }
        tDia = String(d.diaVencimiento)
        ultimoGuardado = firma()
        cargado = true
        if leer { eligiendoLectura = true }
    }

    private func seguirBorrador(_ b: BorradorContratoAPI) {
        d = b.datos.datos
        paso = b.datos.paso
        if !pasos.contains(paso) { paso = pasos.last ?? 0 }
        idBorrador = b.id
        guardado = "listo"
        guardadoEn = b.actualizadoEn
        textosDesdeDatos()
        ultimoGuardado = firma()
    }

    private func textosDesdeDatos() {
        tHonorarios = Self.textoPorcentaje(d.honorarios)
        tComision = Self.textoPorcentaje(d.comision)
        tPunitorio = Self.textoPorcentaje(d.punitorioDiario)
        tPorcentaje = Self.textoPorcentaje(d.ajustePorcentaje)
        tDia = String(d.diaVencimiento)
        tMeses = d.meses.map { [24, 36].contains($0) ? "" : String($0) } ?? ""
    }

    /// Renovar: las mismas partes y condiciones, desde el día después del fin, con el alquiler de hoy y
    /// la duración del anterior.
    private func desdeContrato(_ id: String) async {
        guard let c: ContratoAPI = try? await estado.api.get("/v1/contratos/\(id)") else { return }
        let a: AjusteContrato? = try? await estado.api.get("/v1/contratos/\(id)/ajuste")
        var x = DatosContratoAlta()
        x.tipo = c.tipo ?? "alquiler"
        x.propiedad = c.propiedadId.map { ElegidoAlta(id: $0, nombre: c.propiedadTitulo ?? "Propiedad") }
        x.inquilino = c.contactoId.map { ElegidoAlta(id: $0, nombre: c.contactoNombre ?? "Inquilino") }
        x.propietario = c.propietarioId.map { ElegidoAlta(id: $0, nombre: c.propietarioNombre ?? "Propietario") }
        x.garanteNombre = c.garanteNombre ?? ""
        x.garanteTelefono = c.garanteTelefono ?? ""
        x.garanteNotas = c.garanteNotas ?? ""
        if let fin = c.fin.flatMap(Fecha.dia), let sig = Calendar.current.date(byAdding: .day, value: 1, to: fin) { x.inicio = Formato.diaISO(sig) }
        if let i = c.inicio.flatMap(Fecha.dia), let f = c.fin.flatMap(Fecha.dia) {
            x.meses = max(1, Int((f.timeIntervalSince(i) / (30.44 * 86400)).rounded()))
        } else { x.meses = 36 }
        x.monto = (a?.vigente ?? c.monto).map { $0.rounded() }
        x.moneda = c.moneda == "USD" ? "USD" : "ARS"
        x.diaVencimiento = c.diaVencimiento ?? 1
        x.indice = c.ajusteIndice
        x.ajusteMeses = c.ajusteMeses
        x.ajustePorcentaje = c.ajustePorcentaje
        x.honorarios = c.honorarios
        x.comision = (c.comision ?? 0) > 0 ? c.comision : nil
        x.punitorioDiario = c.punitorioDiario
        x.deposito = c.deposito
        x.renueva = .init(id: c.id, titulo: c.propiedadTitulo ?? "el contrato")
        d = x
        textosDesdeDatos()
    }

    /// «Hacer el contrato» de una operación en cierre: la propiedad, el contacto y el valor.
    private func desdeOperacion(_ id: String) async {
        guard let o: Operacion = try? await estado.api.get("/v1/operaciones/\(id)") else { return }
        if let p = o.propiedadId { d.propiedad = ElegidoAlta(id: p, nombre: o.propiedadTitulo ?? "Propiedad") }
        if let c = o.contactoId { d.inquilino = ElegidoAlta(id: c, nombre: o.contactoNombre ?? "Contacto") }
        if o.moneda == "ARS" || o.moneda == "USD" { d.moneda = o.moneda ?? "ARS" }
        if let v = o.valor, v > 0 { d.monto = v }
        if let p = d.propiedad { await propietarioDe(p) }
    }

    // MARK: Leer el PDF

    private func leerArchivo(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let datos = try? Data(contentsOf: u) else { estado.avisar("No se pudo leer el archivo.", ok: false); return }
        await leerDatos(datos, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
    }

    struct ParteLeida: Decodable { var nombre: String; var telefono: String? }
    struct Leido: Decodable {
        var tipo: String?; var inquilino: ParteLeida?; var propietario: ParteLeida?; var garante: ParteLeida?; var garantia: String?; var direccion: String?
        var inicio: String?; var fin: String?; var meses: Int?; var monto: Double?; var moneda: String?; var ajusteIndice: String?; var ajusteMeses: Int?
        var ajustePorcentaje: Double?; var deposito: Double?; var honorarios: Double?; var punitorioDiario: Double?; var diaVencimiento: Int?
        var notas: String?; var dudosos: [String]?
    }

    private func leerDatos(_ datos: Data, nombre: String, tipo: String) async {
        guard !leyendo else { return }
        leyendo = true
        defer { leyendo = false }
        struct Lectura: Decodable { var datos: Leido; var prueba: Bool? }
        struct C: Encodable { var archivoId: String }
        do {
            let sub = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            let r: Lectura = try await estado.api.enviar("POST", "/v1/contratos/leer", C(archivoId: sub.id))
            let l = r.datos
            var nuevo = Self.aplicarLectura(d, l)
            if !nuevo.documentos.contains(where: { $0.id == sub.id }) {
                nuevo.documentos.append(DocumentoAlta(id: sub.id, nombre: sub.nombre ?? nombre, tipo: sub.tipo ?? tipo, bytes: sub.bytes ?? datos.count))
            }
            if d.propiedad == nil, let dir = l.direccion { nuevo.propiedad = await encontrar("propiedad", dir, nil) }
            if d.inquilino == nil, let n = l.inquilino?.nombre { nuevo.inquilino = await encontrar("contacto", n, n) }
            if d.propietario == nil, let n = l.propietario?.nombre { nuevo.propietario = await encontrar("contacto", n, n) }
            let antes = d
            let antesTextos = (tHonorarios, tComision, tPunitorio, tPorcentaje, tDia, tMeses)
            d = nuevo
            textosDesdeDatos()
            leidoDe = sub.id
            var s: [String: String] = [:]
            if nuevo.propiedad == nil, let x = l.direccion { s["propiedad"] = x }
            if nuevo.inquilino == nil, let x = l.inquilino?.nombre { s["inquilino"] = x }
            if nuevo.propietario == nil, let x = l.propietario?.nombre { s["propietario"] = x }
            sugeridos = s
            dudosos = (l.dudosos ?? []).filter { Self.pasoDe[$0] != nil }
            if antes.propiedad == nil, let p = nuevo.propiedad { await propietarioDe(p) }
            let texto = r.prueba == true ? "Datos de prueba: la lectura no está configurada"
                : dudosos.isEmpty ? "Lo leímos. Revisá y seguí"
                : "Lo leímos. Revisá \(dudosos.count == 1 ? "lo marcado" : "las \(dudosos.count) cosas marcadas")"
            estado.avisar(texto) {
                d = antes
                (tHonorarios, tComision, tPunitorio, tPorcentaje, tDia, tMeses) = antesTextos
                dudosos = []
                sugeridos = [:]
                leidoDe = nil
            }
        } catch {
            estado.avisar("No se pudo leer · \((error as? ErrorApi)?.detalle ?? "probá de nuevo")", ok: false)
        }
    }

    /// Una sola coincidencia, o la que se llama igual: se elige sola. Si no, queda sugerida.
    private func encontrar(_ tipo: String, _ q: String, _ igual: String?) async -> ElegidoAlta? {
        guard let r: [Resultado] = try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: tipo), .init(name: "q", value: q)]) else { return nil }
        let x = igual.flatMap { n in r.first { Self.mismoNombre($0.titulo, n) } } ?? (r.count == 1 ? r.first : nil)
        return x.map { ElegidoAlta(id: $0.id, nombre: $0.titulo, detalle: $0.subtitulo) }
    }

    /// Lo leído pisa lo cargado sólo donde se leyó algo; las partes y la propiedad se buscan aparte.
    static func aplicarLectura(_ d: DatosContratoAlta, _ l: Leido) -> DatosContratoAlta {
        var x = d
        let positivo: (Double?) -> Double? = { v in v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        if l.tipo == "alquiler" || l.tipo == "venta" { x.tipo = l.tipo! }
        if let i = l.inicio, Fecha.dia(i) != nil { x.inicio = i }
        var meses: Double? = positivo(l.meses.map(Double.init))
        if meses == nil, let i = l.inicio.flatMap(Fecha.dia), let f = l.fin.flatMap(Fecha.dia) {
            meses = max(1, (f.timeIntervalSince(i) / (30.44 * 86400)).rounded())
        }
        if let m = meses { x.meses = Int(m.rounded()) }
        if let m = positivo(l.monto) { x.monto = m }
        if l.moneda == "ARS" || l.moneda == "USD" { x.moneda = l.moneda! }
        if let dv = l.diaVencimiento, (1...28).contains(dv) { x.diaVencimiento = dv }
        if let i = l.ajusteIndice, ["icl", "ipc", "uva", "fijo"].contains(i) { x.indice = i }
        if let m = positivo(l.ajusteMeses.map(Double.init)) { x.ajusteMeses = Int(m.rounded()) }
        if let p = positivo(l.ajustePorcentaje) { x.ajustePorcentaje = p }
        if let p = positivo(l.deposito) { x.deposito = p }
        if let p = positivo(l.honorarios) { x.honorarios = p }
        if let p = positivo(l.punitorioDiario) { x.punitorioDiario = p }
        if let g = l.garante?.nombre.nonEmpty {
            x.garanteNombre = g
            if let t = l.garante?.telefono?.nonEmpty { x.garanteTelefono = t }
        }
        let notas = [l.garantia.map { "Garantía: \($0)" }, l.notas?.nonEmpty].compactMap { $0 }.joined(separator: "\n")
        if !notas.isEmpty && !x.notas.contains(notas) { x.notas = [x.notas.trimmingCharacters(in: .whitespacesAndNewlines), notas].filter { !$0.isEmpty }.joined(separator: "\n\n") }
        return x
    }

    // MARK: Documentos

    private func subirDocArchivo(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let datos = try? Data(contentsOf: u) else { estado.avisar("No se pudo leer el archivo.", ok: false); return }
        await subirDoc(datos, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
    }

    private func subirDoc(_ datos: Data, nombre: String, tipo: String) async {
        subiendoDoc = true
        defer { subiendoDoc = false }
        do {
            let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            d.documentos.append(DocumentoAlta(id: a.id, nombre: a.nombre ?? nombre, tipo: a.tipo ?? tipo, bytes: a.bytes ?? datos.count))
        } catch { estado.avisar("No se subió · \((error as? ErrorApi)?.detalle ?? "")", ok: false) }
    }

    private func sacarDoc(_ doc: DocumentoAlta) {
        let antes = d.documentos
        d.documentos.removeAll { $0.id == doc.id }
        estado.avisar("Sacaste «\(doc.nombre)»") { d.documentos = antes }
    }

    // MARK: Cuentas y formatos

    /// Meses enteros entre dos fechas (del 01/07/2024 al 30/06/2027 → 36): el último día cuenta.
    static func mesesEntre(_ desde: String, _ hasta: String) -> Int {
        let a = desde.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard a.count == 3, let h0 = Fecha.dia(hasta), let h = Calendar.current.date(byAdding: .day, value: 1, to: h0) else { return 0 }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: h)
        return max(0, ((c.year ?? 0) - a[0]) * 12 + ((c.month ?? 0) - a[1]) - ((c.day ?? 0) < a[2] ? 1 : 0))
    }

    /// El último día del plazo: 36 meses desde el 01/07/2024 → 30/06/2027.
    static func finDe(_ inicio: String, _ meses: Int?) -> String? {
        guard let meses, meses > 0 else { return nil }
        let p = inicio.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let total = p[1] - 1 + meses
        let anio = p[0] + total / 12
        let mes = total % 12 + 1
        guard let primero = cal.date(from: DateComponents(year: anio, month: mes, day: 1, hour: 12)),
              let dias = cal.range(of: .day, in: .month, for: primero)?.count,
              let f = cal.date(from: DateComponents(year: anio, month: mes, day: min(p[2], dias), hour: 12)),
              let menos = cal.date(byAdding: .day, value: -1, to: f) else { return nil }
        return Formato.diaISO(menos)
    }

    /// «01/07/2027».
    static func fmtFecha(_ f: String) -> String { "\(TextosCobro.fechaCortita(f))/\(f.prefix(4))" }

    /// «4,15» o «4.15» → 4.15. Vacío → nil.
    static func leerPorcentaje(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return t.isEmpty ? nil : Double(t)
    }

    /// 4.15 → «4,15».
    static func textoPorcentaje(_ n: Double?) -> String {
        guard let n else { return "" }
        return (n.rounded() == n ? String(Int(n)) : String(n)).replacingOccurrences(of: ".", with: ",")
    }

    /// «Martín  Ríos» y «martin rios» son el mismo nombre.
    static func mismoNombre(_ a: String, _ b: String) -> Bool {
        let n: (String) -> String = { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return n(a) == n(b)
    }
}

/// El alta apilada desde una ruta (`/contratos/nuevo?borrador=` o `?renovar=`).
struct AltaContratoPantalla: View {
    var destino: AAltaContrato
    var body: some View { AltaContrato(leer: destino.leer, renovar: destino.renovar, borrador: destino.borrador, apilada: true) }
}

// MARK: - Elegir propiedad y partes

/// Elegir la propiedad del contrato: sin texto, las de la operación del contrato (alquiler o venta).
struct ElegirPropiedadAlta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var operacion: String
    var sugerido: String?
    var alElegir: (ElegidoAlta) -> Void
    @State private var q = ""
    @State private var res: [ElegidoAlta] = []
    @State private var cargando = true

    struct Prop: Decodable { var id: String; var titulo: String?; var barrio: String?; var estado: String? }

    var body: some View {
        NavigationStack {
            List {
                if !cargando && res.isEmpty {
                    Text(q.count >= 2 ? "No encontramos propiedades con «\(q)»." : "Escribí la calle, el barrio o el código.").foregroundStyle(C.texto2)
                }
                ForEach(res, id: \.id) { r in
                    Button { alElegir(r); cerrar() } label: {
                        VStack(alignment: .leading) {
                            Text(r.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                            if let s = r.detalle { Text(s).estilo(.footnote).foregroundStyle(C.texto2) }
                        }
                    }
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Calle, barrio o código")
            .navigationTitle("Elegí la propiedad").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .onAppear { if let sugerido, q.isEmpty { q = sugerido } }
            .task(id: q) {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                cargando = true
                if q.count >= 2 {
                    let r: [Resultado] = (try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "propiedad"), .init(name: "q", value: q)])) ?? []
                    res = r.map { ElegidoAlta(id: $0.id, nombre: $0.titulo, detalle: $0.subtitulo) }
                } else {
                    let l: [Prop] = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "limite", value: "8"), .init(name: "operacion", value: operacion)])) ?? []
                    res = l.map { p in
                        ElegidoAlta(id: p.id, nombre: p.titulo ?? "Propiedad",
                                    detalle: [p.barrio, p.estado == "disponible" ? nil : p.estado].compactMap { $0 }.joined(separator: " · ").nonEmpty)
                    }
                }
                cargando = false
            }
        }
    }
}

/// Elegir una parte: sin texto, los más recientes del tipo (inquilino, comprador o propietario), con
/// tipo y teléfono; «Cargar «…» como contacto nuevo» con ese tipo.
struct ElegirParteAlta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var tipo: String
    var sugerido: String?
    var alElegir: (ElegidoAlta) -> Void
    @State private var q = ""
    @State private var res: [ElegidoAlta] = []
    @State private var creando = false

    static let tipos = ["inquilino": "Inquilino", "propietario": "Propietario", "garante": "Garante", "comprador": "Comprador", "vendedor": "Vendedor"]
    struct Ct: Decodable { var id: String; var nombre: String; var telefono: String?; var tipo: String? }

    var body: some View {
        NavigationStack {
            List {
                ForEach(res, id: \.id) { r in
                    Button { alElegir(r); cerrar() } label: {
                        VStack(alignment: .leading) {
                            Text(r.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                            if let s = r.detalle { Text(s).estilo(.footnote).foregroundStyle(C.texto2) }
                        }
                    }
                }
                if q.trimmingCharacters(in: .whitespaces).count >= 2 && estado.escribe {
                    Button { Task { await crear() } } label: { Label("Cargar «\(q)» como contacto nuevo", systemImage: "person.badge.plus") }.disabled(creando)
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nombre o teléfono")
            .navigationTitle("Elegí \(Self.tipos[tipo]?.lowercased() ?? "el contacto")").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .onAppear { if let sugerido, q.isEmpty { q = sugerido } }
            .task(id: q) {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                if q.count >= 2 {
                    let r: [Resultado] = (try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: q)])) ?? []
                    res = r.map { ElegidoAlta(id: $0.id, nombre: $0.titulo, detalle: $0.subtitulo) }
                } else {
                    let l: [Ct] = (try? await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "8"), .init(name: "tipo", value: tipo)])) ?? []
                    res = l.map { c in ElegidoAlta(id: c.id, nombre: c.nombre, detalle: [c.tipo.flatMap { Self.tipos[$0] }, c.telefono].compactMap { $0 }.joined(separator: " · ").nonEmpty) }
                }
            }
        }
    }

    private func crear() async {
        creando = true
        defer { creando = false }
        struct Cuerpo: Encodable { var nombre: String; var tipo: String }
        do {
            let c: Ct = try await estado.api.enviar("POST", "/v1/contactos", Cuerpo(nombre: q.trimmingCharacters(in: .whitespaces), tipo: tipo))
            estado.avisar("\(c.nombre) quedó en Contactos")
            alElegir(ElegidoAlta(id: c.id, nombre: c.nombre, detalle: Self.tipos[tipo]))
            cerrar()
        } catch { estado.avisar(error) }
    }
}
