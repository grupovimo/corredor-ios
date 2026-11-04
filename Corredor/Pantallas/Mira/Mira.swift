import AVFoundation
import CoreLocation
import PhotosUI
import SwiftUI

extension View {
    /// Los destinos de MIRA: lo captado.
    func destinosMira() -> some View {
        navigationDestination(for: ACaptadas.self) { _ in Captadas() }
    }
}

/// Lo que MIRA leyó de un cartel (POST /v1/mira/extraer).
struct LecturaMira: Codable, Equatable {
    struct Datos: Codable, Equatable {
        var operacion: String?
        var tipo: String?
        var precio: Double?
        var moneda: String?
        var telefono: String?
        var inmobiliaria: String?
        var direccion: String?
        var ambientes: Int?
        var dormitorios: Int?
        var superficie: Double?
        var notas: String?
        var precioAlternativas: [Double]?
        var precioConfianza: String?
        var persona: Bool?
    }
    var datos: Datos
    var proveedor: String?
    var prueba: Bool?
}

/// Una foto de MIRA: en cola (sin señal), leída para revisar o ya captada.
struct FotoMira: Codable, Identifiable, Equatable {
    var id = UUID()
    var archivo: String
    var lat: Double?
    var lng: Double?
    var direccionGPS: String?
    var creada = Date()
    var estado = "cola"
    var lectura: LecturaMira.Datos?
    var archivoId: String?
    var propiedadId: String?
    var error: String?
}

/// Las fotos de MIRA guardadas en el iPhone (la cola sin señal y lo captado), con su imagen en disco.
@Observable
@MainActor
final class ColaMira {
    static let compartida = ColaMira()
    private(set) var fotos: [FotoMira] = Guardado.leer([FotoMira].self, clave: "mira")?.0 ?? []

    static var carpeta: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mira")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func guardar(_ datos: Data, lat: Double?, lng: Double?, direccion: String?) -> FotoMira {
        let nombre = UUID().uuidString + ".jpg"
        try? datos.write(to: ColaMira.carpeta.appendingPathComponent(nombre))
        let f = FotoMira(archivo: nombre, lat: lat, lng: lng, direccionGPS: direccion)
        fotos.insert(f, at: 0)
        persistir()
        return f
    }

    func actualizar(_ f: FotoMira) {
        if let i = fotos.firstIndex(where: { $0.id == f.id }) { fotos[i] = f; persistir() }
    }

    func sacar(_ f: FotoMira) {
        fotos.removeAll { $0.id == f.id }
        try? FileManager.default.removeItem(at: ColaMira.carpeta.appendingPathComponent(f.archivo))
        persistir()
    }

    func imagen(_ f: FotoMira) -> UIImage? { UIImage(contentsOfFile: ColaMira.carpeta.appendingPathComponent(f.archivo).path) }

    /// Lee lo que quedó en cola (al volver la señal o al abrir MIRA).
    func leerPendientes(_ api: Api) async {
        for f in fotos where f.estado == "cola" {
            var x = f
            do {
                try await MiraLector.leer(&x, api: api)
            } catch let e as ErrorApi where e.sinConexion {
                return
            } catch let e as ErrorApi {
                x.estado = "error"
                x.error = e.detalle
            } catch {}
            actualizar(x)
        }
    }

    private func persistir() { Guardado.guardar(fotos, clave: "mira") }
}

enum MiraLector {
    /// Sube la foto y la lee. Deja la foto en «leida» (para revisar), «persona» o «ilegible».
    @MainActor
    static func leer(_ f: inout FotoMira, api: Api) async throws {
        guard let datos = try? Data(contentsOf: ColaMira.carpeta.appendingPathComponent(f.archivo)) else { return }
        if f.archivoId == nil {
            f.archivoId = try await api.subir(datos, nombre: f.archivo, tipo: "image/jpeg", uso: "foto").id
        }
        struct Cuerpo: Encodable { var archivoId: String }
        do {
            let l: LecturaMira = try await api.enviar("POST", "/v1/mira/extraer", Cuerpo(archivoId: f.archivoId!))
            f.lectura = l.datos
            f.estado = l.datos.persona == true ? "persona" : "leida"
        } catch let e as ErrorApi where e.codigo == "ilegible" {
            f.estado = "ilegible"
        }
    }
}

/// 5A–5H MIRA: la cámara a pantalla completa con el visor oro. Saca la foto, la lee (barrido),
/// muestra la revisión con lo dudoso marcado y la capta como borrador. Sin señal queda en cola.
struct MiraRaiz: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var camara = CamaraMira()
    @State private var ubicacion = Ubicacion()
    @State private var fase = Fase.apuntando
    @State private var foto: FotoMira?
    @State private var barrido = false
    @State private var elegida: PhotosPickerItem?
    @State private var captadas = false
    @State private var editando: String?
    private let cola = ColaMira.compartida

    enum Fase: Equatable { case apuntando, leyendo, revision, captada(String), sinSenal, persona, ilegible }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0x050807).ignoresSafeArea()
                if camara.permiso == .denied || camara.permiso == .restricted {
                    sinPermiso
                } else {
                    VistaCamara(sesion: camara.sesion).ignoresSafeArea()
                    if let foto, fase != .apuntando, let i = cola.imagen(foto) {
                        Image(uiImage: i).resizable().scaledToFill().ignoresSafeArea()
                    }
                    visor
                    arriba
                    if fase == .apuntando || fase == .leyendo { pista; controles }
                    if fase == .leyendo { chips }
                    switch fase {
                    case .revision: revision
                    case .captada(let d): captada(d)
                    case .sinSenal: aviso("icloud.slash", .neutro, "Sin señal. La foto quedó en cola.", "La leemos sola cuando vuelva la señal y te avisamos. Podés seguir captando.",
                                          ("Seguir captando", repetir), ("Ver la cola", { captadas = true }))
                    case .persona: aviso("person.crop.circle.badge.xmark", .oro, "Hay una persona en la foto", "Por privacidad no la leemos. Sacala de nuevo apuntando sólo al cartel.",
                                         ("Sacar de nuevo", repetir), nil)
                    case .ilegible: aviso("aqi.medium", .rojo, "No pudimos leer el cartel", "Acercate un poco más y evitá reflejos. Si no, cargalo a mano.",
                                          ("Sacar de nuevo", repetir), ("Cargar a mano", { cargarAMano() }))
                    default: EmptyView()
                    }
                }
            }
            .foregroundStyle(.white)
            .navigationDestination(isPresented: $captadas) { Captadas() }
        }
        .statusBarHidden()
        .task {
            await camara.arrancar()
            ubicacion.pedir()
            await cola.leerPendientes(estado.api)
        }
        .onDisappear { camara.parar() }
        .onChange(of: elegida) { _, i in
            guard let i else { return }
            Task {
                if let d = try? await i.loadTransferable(type: Data.self) { await procesar(d) }
                elegida = nil
            }
        }
        .sensoryFeedback(.success, trigger: fase == .revision)
        .sheet(item: Binding(get: { editando.map { CampoAlta(id: $0) } }, set: { editando = $0?.id })) { c in
            EditorLectura(campo: c.id, foto: Binding(get: { foto ?? FotoMira(archivo: "") }, set: { foto = $0; cola.actualizar($0) }))
                .presentationDetents([.medium])
        }
    }

    // MARK: Partes

    private var visor: some View {
        GeometryReader { g in
            let r = CGRect(x: 36, y: 210, width: g.size.width - 72, height: 300)
            ZStack {
                Rectangle().fill(.black.opacity(0.52)).mask {
                    Rectangle().overlay(RoundedRectangle(cornerRadius: 24).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).blendMode(.destinationOut))
                        .compositingGroup()
                }
                Visor(color: C.oro, grosor: 6).frame(width: r.width + 6, height: r.height + 6).position(x: r.midX, y: r.midY)
                if fase == .leyendo {
                    Capsule().fill(C.oro).frame(width: r.width - 28, height: 4)
                        .shadow(color: C.oro.opacity(0.55), radius: 15)
                        .position(x: r.midX, y: r.minY + (barrido ? 282 : 6))
                        .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: barrido)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var arriba: some View {
        VStack {
            HStack {
                botonRedondo("xmark", "Cerrar MIRA") { cerrar() }
                Spacer()
                HStack(spacing: 8) {
                    Visor(color: C.oro, grosor: 2).frame(width: 16, height: 16)
                    Text("MIRA").font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).tracking(0.9)
                }
                .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.45), in: Capsule())
                Spacer()
                botonRedondo(camara.flash ? "bolt.fill" : "bolt.slash", "Flash") { camara.flash.toggle() }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            Spacer()
        }
    }

    private var pista: some View {
        VStack {
            Label(fase == .leyendo ? "Leyendo el cartel…" : "Fotografiá sólo el cartel, sin personas",
                  systemImage: fase == .leyendo ? "sparkles" : "person.crop.circle.badge.xmark")
                .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 100)
            Spacer()
        }
    }

    private var chips: some View {
        VStack {
            Spacer().frame(height: 528)
            if let d = foto?.lectura {
                FlowChips(items: [d.operacion.map { ("tag", $0.capitalized) }, d.precio.map { ("dollarsign", Formato.plata($0, d.moneda ?? "USD")) },
                                  d.telefono.map { ("phone", $0) }, d.ambientes.map { ("bed.double", "\($0) amb") }].compactMap { $0 })
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    private var controles: some View {
        VStack {
            Spacer()
            HStack {
                PhotosPicker(selection: $elegida, matching: .images) {
                    RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)).frame(width: 52, height: 52)
                        .overlay(Image(systemName: "photo").foregroundStyle(.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.8), lineWidth: 2))
                }
                .accessibilityLabel("Elegir de la fototeca")
                Spacer()
                Button { Task { await disparar() } } label: {
                    Circle().fill(.white).frame(width: 64, height: 64).padding(8).overlay(Circle().strokeBorder(.white, lineWidth: 5))
                }
                .disabled(fase == .leyendo)
                .accessibilityLabel("Sacar foto del cartel")
                Spacer()
                Button { captadas = true } label: {
                    Image(systemName: "tray.full").font(.system(size: 22)).frame(width: 52, height: 52).background(.black.opacity(0.45), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            let n = cola.fotos.filter { $0.estado != "captada" }.count
                            if n > 0 {
                                Text("\(n)").font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(Color(hex: 0x1A1405))
                                    .frame(width: 20, height: 20).background(C.oro, in: Circle()).offset(x: 2, y: -2)
                            }
                        }
                }
                .accessibilityLabel("Captadas")
            }
            .padding(.horizontal, 48).padding(.bottom, 44)
        }
    }

    private var revision: some View {
        let d = foto?.lectura ?? LecturaMira.Datos()
        let dudaPrecio = (d.precioAlternativas?.count ?? 0) > 1 || d.precioConfianza == "baja"
        let campos: [(String, String, String, Bool)] = [
            ("operacion", "Operación", d.operacion.map { $0 == "temporario" ? "Temporada" : $0.capitalized } ?? "—", d.operacion == nil),
            ("tipo", "Tipo", Propiedad.tipos.first { $0.0 == d.tipo }?.1 ?? d.tipo?.capitalized ?? "—", d.tipo == nil),
            ("precio", "Precio", d.precio.map { Formato.plata($0, d.moneda ?? "USD") } ?? "Sin precio", dudaPrecio),
            ("telefono", "Teléfono", d.telefono ?? "—", false),
            ("direccion", "Dirección", d.direccion ?? foto?.direccionGPS.map { "\($0) · por tu ubicación" } ?? "—", d.direccion == nil),
        ]
        return VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Capsule().fill(C.linea2).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revisá lo que leímos").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font)
                    Text("Lo leyó Google Gemini. Corregí lo que no esté bien antes del alta.").estilo(.footnote).foregroundStyle(C.texto2)
                }
                VStack(spacing: 0) {
                    ForEach(Array(campos.enumerated()), id: \.element.0) { i, c in
                        Button { editando = c.0 } label: {
                            HStack(spacing: 10) {
                                Text(c.1).estilo(.texto14).foregroundStyle(C.texto2).frame(width: 86, alignment: .leading)
                                Text(c.2).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                                Spacer()
                                if c.3 {
                                    Text("Revisá").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.avisoTinta)
                                        .padding(.horizontal, 8).frame(height: 24).background(C.avisoFondo, in: Capsule())
                                }
                                Image(systemName: "pencil").foregroundStyle(C.texto3)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .background(C.hundida, in: .rect(cornerRadius: 16, style: .continuous))
                Button { Task { await captar() } } label: {
                    Label("Captar como borrador", systemImage: "checkmark").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                        .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 54)
                        .background(C.accion, in: .rect(cornerRadius: 15, style: .continuous))
                }
                Button("Sacar de nuevo", action: repetir).font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(C.texto)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            .background(C.superficie, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
        }
        .background(Color.black.opacity(0.25))
        .ignoresSafeArea(edges: .bottom)
    }

    private func captada(_ direccion: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark").font(.system(size: 54, weight: .bold)).foregroundStyle(Color(hex: 0x1A1405))
                .frame(width: 108, height: 108).background(C.oro, in: Circle())
                .background(C.oro.opacity(0.2), in: Circle().inset(by: -14))
            Text("Captada").font(Estilo(tamano: 26, peso: .bold, relativo: .title).font)
            Text("\(direccion) quedó en borradores").estilo(.body16).foregroundStyle(Color(hex: 0xCFE0D8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0F3530, alfa: 0.82))
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            repetir()
        }
    }

    private func aviso(_ icono: String, _ tono: Tono, _ titulo: String, _ texto: String, _ a: (String, () -> Void), _ b: (String, () -> Void)?) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconoTono(icono: icono, tono: tono, tam: 44)
                    Text(titulo).font(Estilo(tamano: 18, peso: .bold, relativo: .headline).font)
                }
                Text(texto).estilo(.subhead).foregroundStyle(C.texto2)
                HStack(spacing: 8) {
                    Button(a.0, action: a.1).buttonStyle(BotonAccion())
                    if let b { Button(b.0, action: b.1).buttonStyle(BotonHundido()) }
                }
            }
            .foregroundStyle(C.texto)
            .padding(18)
            .background(C.superficie, in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
    }

    private var sinPermiso: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.badge.ellipsis").font(.system(size: 38)).foregroundStyle(C.oro)
                .frame(width: 84, height: 84).background(C.oro.opacity(0.16), in: .rect(cornerRadius: 26, style: .continuous))
            Text("MIRA necesita la cámara").font(Estilo(tamano: 24, peso: .bold, tracking: -0.02, relativo: .title2).font)
            Text("Activala en Ajustes › Corredor › Cámara. Sólo la usamos para leer carteles.").estilo(.body16)
                .foregroundStyle(Color(hex: 0xCFE0D8)).multilineTextAlignment(.center)
            Button("Abrir Ajustes") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(Color(hex: 0x1A1405))
                .padding(.horizontal, 26).frame(height: 52).background(C.oro, in: .rect(cornerRadius: 14, style: .continuous)).padding(.top, 8)
            Button("Cargar a mano") { cargarAMano() }.font(Estilo.subheadFuerte.font).foregroundStyle(Color(hex: 0xCFE0D8)).frame(height: 44)
            HStack {}.frame(height: 0)
            Button("Cerrar") { cerrar() }.foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoVerde(patron: 0))
    }

    private func botonRedondo(_ icono: String, _ etiqueta: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: icono).font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(etiqueta)
    }

    // MARK: Acciones

    private func disparar() async {
        guard let d = await camara.sacar() else { return }
        await procesar(d)
    }

    private func procesar(_ datos: Data) async {
        Haptico.impacto()
        let jpg = UIImage(data: datos)?.jpegData(compressionQuality: 0.8) ?? datos
        var f = cola.guardar(jpg, lat: ubicacion.ultima?.coordinate.latitude, lng: ubicacion.ultima?.coordinate.longitude, direccion: ubicacion.direccion)
        foto = f
        fase = .leyendo
        barrido = false
        try? await Task.sleep(for: .milliseconds(60))
        barrido = true
        do {
            try await MiraLector.leer(&f, api: estado.api)
            cola.actualizar(f)
            foto = f
            switch f.estado {
            case "persona": fase = .persona; cola.sacar(f)
            case "ilegible": fase = .ilegible
            default: fase = .revision
            }
        } catch let e as ErrorApi where e.sinConexion {
            fase = .sinSenal
        } catch {
            fase = .ilegible
        }
    }

    private func captar() async {
        guard var f = foto, let d = f.lectura else { return }
        struct Captada: Encodable {
            var archivoId: String?
            var titulo = ""
            var tipo: String
            var operacion: String
            var precio: Double?
            var moneda: String
            var direccion: String
            var lat: Double?
            var lng: Double?
            var ambientes: Int?
            var dormitorios: Int?
            var superficie: Double?
            var telefono: String?
            var inmobiliaria: String?
            var notas: String?
        }
        let direccion = d.direccion ?? f.direccionGPS ?? ""
        struct Creada: Decodable { var id: String }
        do {
            let c: Creada = try await estado.api.enviar("POST", "/v1/mira/propiedad", Captada(
                archivoId: f.archivoId, tipo: d.tipo ?? "departamento", operacion: d.operacion ?? "venta", precio: d.precio, moneda: d.moneda ?? "USD",
                direccion: direccion, lat: f.lat, lng: f.lng, ambientes: d.ambientes, dormitorios: d.dormitorios, superficie: d.superficie,
                telefono: d.telefono, inmobiliaria: d.inmobiliaria, notas: d.notas))
            f.estado = "captada"
            f.propiedadId = c.id
            cola.actualizar(f)
            estado.version += 1
            fase = .captada(direccion.nonEmpty ?? "La propiedad")
        } catch let e as ErrorApi where e.sinConexion {
            fase = .sinSenal
        } catch { estado.avisar(error) }
    }

    private func repetir() {
        foto = nil
        fase = .apuntando
    }

    private func cargarAMano() {
        cerrar()
        estado.ir(Ruta(.propiedades, AAltaPropiedad()))
    }
}

/// Los chips que aparecen mientras MIRA lee.
struct FlowChips: View {
    var items: [(String, String)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.1) { i, t in
                Label(t, systemImage: i).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(Color(hex: 0x18201D))
                    .padding(.horizontal, 12).frame(height: 36).background(Color(hex: 0xFFFDF8), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// Corregir un campo de lo leído.
struct EditorLectura: View {
    @Environment(\.dismiss) private var cerrar
    var campo: String
    @Binding var foto: FotoMira

    var body: some View {
        NavigationStack {
            Form {
                let l = Binding(get: { foto.lectura ?? LecturaMira.Datos() }, set: { foto.lectura = $0 })
                switch campo {
                case "operacion":
                    Picker("Operación", selection: Binding(get: { l.wrappedValue.operacion ?? "venta" }, set: { l.wrappedValue.operacion = $0 })) {
                        ForEach(Propiedad.operaciones, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.inline).labelsHidden()
                case "tipo":
                    Picker("Tipo", selection: Binding(get: { l.wrappedValue.tipo ?? "departamento" }, set: { l.wrappedValue.tipo = $0 })) {
                        ForEach(Propiedad.tipos, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.inline).labelsHidden()
                case "precio":
                    Picker("Moneda", selection: Binding(get: { l.wrappedValue.moneda ?? "USD" }, set: { l.wrappedValue.moneda = $0 })) {
                        Text("USD").tag("USD"); Text("ARS").tag("ARS")
                    }.pickerStyle(.segmented)
                    TextField("Precio", value: Binding(get: { l.wrappedValue.precio }, set: { l.wrappedValue.precio = $0 }), format: .number).keyboardType(.numberPad)
                    ForEach(l.wrappedValue.precioAlternativas ?? [], id: \.self) { p in
                        Button("¿Era \(Formato.plata(p, l.wrappedValue.moneda ?? "USD"))?") { l.wrappedValue.precio = p }
                    }
                case "telefono":
                    TextField("Teléfono", text: Binding(get: { l.wrappedValue.telefono ?? "" }, set: { l.wrappedValue.telefono = $0.nonEmpty })).keyboardType(.phonePad)
                default:
                    TextField("Dirección", text: Binding(get: { l.wrappedValue.direccion ?? foto.direccionGPS ?? "" }, set: { l.wrappedValue.direccion = $0.nonEmpty }))
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }
}

/// 5I Captadas: la cola sin señal, lo leído para revisar y lo ya captado.
struct Captadas: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    private let cola = ColaMira.compartida

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                let enCola = cola.fotos.filter { $0.estado == "cola" }.count
                if enCola > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.up").font(.system(size: 20)).foregroundStyle(C.texto2)
                        Text("\(Formato.cantidad(enCola, "foto en cola", "fotos en cola")) · se lee sola cuando vuelva la señal").estilo(.texto14).foregroundStyle(C.texto)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                }
                if cola.fotos.isEmpty {
                    EstadoVacio(icono: "viewfinder", titulo: "Todavía no captaste carteles",
                                texto: "Fotografiá un cartel de «Vende» y MIRA lo carga por vos.").padding(.top, 40)
                }
                ForEach(cola.fotos) { f in
                    let (texto, icono, tono) = Self.estado(f)
                    Button { abrir(f) } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let i = cola.imagen(f) { Image(uiImage: i).resizable().scaledToFill() } else { C.hundida }
                            }
                            .frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.lectura?.direccion ?? f.direccionGPS ?? "Cartel sin dirección").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                Text([f.lectura?.precio.map { Formato.plata($0, f.lectura?.moneda ?? "USD") }, Formato.hace(f.creada)].compactMap { $0 }.joined(separator: " · "))
                                    .estilo(.footnote).foregroundStyle(C.texto2)
                                Spacer(minLength: 2)
                                Label(texto, systemImage: icono).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                                    .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(10).tarjeta()
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button(role: .destructive) { cola.sacar(f) } label: { Label("Sacar de la lista", systemImage: "trash") } }
                }
                Button { estado.miraAbierta = true; cerrar() } label: {
                    Label("Captar otra", systemImage: "viewfinder").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font)
                        .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 52).background(C.accion, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .pantallaApilada("Captadas")
        .refreshable { await cola.leerPendientes(estado.api) }
        .task { await cola.leerPendientes(estado.api) }
    }

    private func abrir(_ f: FotoMira) {
        if let p = f.propiedadId { estado.abrir(AFichaPropiedad(id: p), en: .propiedades); estado.pestana = .propiedades; estado.miraAbierta = false }
    }

    static func estado(_ f: FotoMira) -> (String, String, Tono) {
        switch f.estado {
        case "cola": return ("En cola", "icloud.slash", .neutro)
        case "leida": return ("Revisá antes del alta", "exclamationmark.circle", .oro)
        case "captada": return ("Borrador", "checkmark.circle", .verde)
        case "ilegible": return ("No se pudo leer", "aqi.medium", .rojo)
        default: return (f.error ?? "Con error", "exclamationmark.triangle", .rojo)
        }
    }
}

// MARK: - Cámara y ubicación

/// La cámara trasera para MIRA (AVCaptureSession con foto).
@Observable
@MainActor
final class CamaraMira: NSObject, AVCapturePhotoCaptureDelegate {
    let sesion = AVCaptureSession()
    private let salida = AVCapturePhotoOutput()
    var permiso = AVCaptureDevice.authorizationStatus(for: .video)
    var flash = false
    private var esperando: CheckedContinuation<Data?, Never>?

    func arrancar() async {
        if permiso == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            permiso = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard permiso == .authorized, sesion.inputs.isEmpty,
              let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let entrada = try? AVCaptureDeviceInput(device: d) else { return }
        sesion.beginConfiguration()
        sesion.sessionPreset = .photo
        if sesion.canAddInput(entrada) { sesion.addInput(entrada) }
        if sesion.canAddOutput(salida) { sesion.addOutput(salida) }
        sesion.commitConfiguration()
        let s = sesion
        Task.detached { s.startRunning() }
    }

    func parar() {
        let s = sesion
        Task.detached { s.stopRunning() }
    }

    func sacar() async -> Data? {
        guard permiso == .authorized, sesion.isRunning else { return nil }
        let ajustes = AVCapturePhotoSettings()
        if salida.supportedFlashModes.contains(.on) { ajustes.flashMode = flash ? .on : .off }
        return await withCheckedContinuation { c in
            esperando = c
            salida.capturePhoto(with: ajustes, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let d = photo.fileDataRepresentation()
        Task { @MainActor in
            esperando?.resume(returning: d)
            esperando = nil
        }
    }
}

/// La vista previa de la cámara.
struct VistaCamara: UIViewRepresentable {
    var sesion: AVCaptureSession
    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var capa: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista()
        v.capa.session = sesion
        v.capa.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: Vista, context: Context) {}
}

/// La ubicación del iPhone (para ubicar el cartel y proponer la dirección).
@Observable
@MainActor
final class Ubicacion: NSObject, CLLocationManagerDelegate {
    private let gestor = CLLocationManager()
    var ultima: CLLocation?
    var direccion: String?

    func pedir() {
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if gestor.authorizationStatus == .notDetermined { gestor.requestWhenInUseAuthorization() }
        gestor.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            ultima = l
            if let p = try? await CLGeocoder().reverseGeocodeLocation(l).first {
                direccion = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ").nonEmpty
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() } }
    }
}
