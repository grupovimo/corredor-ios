import AVFoundation
import CoreLocation
import PhotosUI
import SwiftUI

extension View {
    /// Los destinos de MIRA: lo captado y los borradores que mandó la IA.
    func destinosMira() -> some View {
        navigationDestination(for: ACaptadas.self) { _ in Captadas() }
            .navigationDestination(for: ARevisionIds.self) { r in RevisionIA(ids: r.ids) }
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
    /// La foto que se pidió abrir en MIRA para revisarla (desde Captadas).
    var abrir: UUID?

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

/// Lo que se revisa antes de captar (la ficha de la web: operación, tipo, precio, teléfono, dirección).
struct FormMira: Equatable {
    var operacion: String?
    var tipo: String?
    var ambientes: Int?
    var dormitorios: Int?
    var superficie: Double?
    var precio: Double?
    var moneda = "USD"
    var telefono: String?
    var inmobiliaria: String?
    var direccion = ""
    var barrio: String?
    var ciudad: String?
    var notas: String?
    /// La dirección salió del GPS (el cartel no la tenía).
    var gps = false
    var lat: Double?
    var lng: Double?
}

/// 5A–5H MIRA: la cámara a pantalla completa con el visor oro. Saca la foto y la lee (barrido); si
/// aparece una persona, se elige el recuadro del cartel y se lee sólo eso. Después, la revisión (o
/// «Leímos la mitad» para completar lo que falta), captar como borrador (el dueño directo queda como
/// contacto) y la pantalla «quedó captada». Sin señal, la foto queda en cola.
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
    @State private var f = FormMira()
    @State private var alternativas: [Double] = []
    @State private var ilegible = false
    @State private var recorte = CGRect(x: 0.07, y: 0.14, width: 0.58, height: 0.36)
    @State private var captando = false
    @State private var captada: (Propiedad, String?)?
    @AppStorage("mira-recortar") private var recortarSiempre = false
    private let cola = ColaMira.compartida

    enum Fase: Equatable { case apuntando, leyendo, persona, revisar, nolee, captada, sinSenal }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0x050807).ignoresSafeArea()
                if camara.permiso == .denied || camara.permiso == .restricted {
                    sinPermiso
                } else if fase == .persona, let foto, let i = cola.imagen(foto) {
                    VistaRecorte(imagen: i, recorte: $recorte)
                    hojaPersona
                } else if fase == .captada, let c = captada {
                    pantallaCaptada(c.0, contacto: c.1)
                } else {
                    VistaCamara(sesion: camara.sesion).ignoresSafeArea()
                    if let foto, fase != .apuntando, let i = cola.imagen(foto) {
                        // En un marco del tamaño de la pantalla: suelta, la foto (más ancha) estiraba todo el
                        // ZStack y la hoja de revisión quedaba más ancha que el teléfono.
                        Color.clear
                            .overlay { Image(uiImage: i).resizable().scaledToFill() }
                            .clipped()
                            .ignoresSafeArea()
                    }
                    visor
                    arriba
                    if fase == .apuntando || fase == .leyendo { pista; controles }
                    if fase == .leyendo { chips }
                    switch fase {
                    case .revisar, .nolee: revision
                    case .sinSenal: aviso("icloud.slash", .neutro, "Sin señal. La foto quedó en cola.", "La leemos sola cuando vuelva la señal y te avisamos. Podés seguir captando.",
                                          ("Seguir captando", repetir), ("Ver la cola", { captadas = true }))
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
            abrirPedida()
        }
        .onChange(of: cola.abrir) { _, _ in abrirPedida() }
        .onDisappear { camara.parar() }
        .onChange(of: elegida) { _, i in
            guard let i else { return }
            Task {
                do { if let d = try await i.loadTransferable(type: Data.self) { await procesar(d) } } catch { estado.avisar(error) }
                elegida = nil
            }
        }
        .sensoryFeedback(.success, trigger: fase == .revisar)
        .sheet(item: Binding(get: { editando.map { CampoAlta(id: $0) } }, set: { editando = $0?.id })) { c in
            EditorCampoMira(campo: c.id, f: $f, alternativas: alternativas).presentationDetents([.medium])
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
                botonRedondo("xmark", "Cerrar MIRA") { if fase == .apuntando { cerrar() } else { repetir() } }
                Spacer()
                HStack(spacing: 8) {
                    Visor(color: C.oro, grosor: 2).frame(width: 16, height: 16)
                    Text("MIRA").font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).tracking(0.9)
                }
                .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.45), in: Capsule())
                Spacer()
                botonRedondo(camara.flash ? "bolt.fill" : "bolt.slash", camara.flash ? "Apagar el flash" : "Prender el flash") { camara.flash.toggle() }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            Spacer()
        }
    }

    /// «Fotografiá sólo el cartel, sin personas»: tocándolo, se elige siempre el recorte del cartel.
    private var pista: some View {
        VStack {
            Group {
                if fase == .leyendo {
                    Label("Leyendo el cartel…", systemImage: "sparkles")
                } else {
                    Button { recortarSiempre.toggle(); Haptico.seleccion() } label: {
                        Label(recortarSiempre ? "Vas a elegir el recorte del cartel" : "Fotografiá sólo el cartel, sin personas",
                              systemImage: recortarSiempre ? "crop" : "person.crop.circle.badge.xmark")
                    }
                    .accessibilityAddTraits(recortarSiempre ? .isSelected : [])
                }
            }
            .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.55), in: Capsule())
            .padding(.top, 100)
            Spacer()
        }
    }

    private var chips: some View {
        VStack {
            Spacer().frame(height: 528)
            FlowChips(items: [f.operacion.map { ("tag", Formato.mayuscula($0)) }, f.precio.map { ("dollarsign", Formato.plata($0, f.moneda)) },
                              f.telefono.map { ("phone", $0) }, f.ambientes.map { ("bed.double", "\($0) amb") }].compactMap { $0 })
                .padding(.horizontal, 24)
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
                .accessibilityLabel("Elegir una foto de la galería")
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

    // MARK: Persona en la foto

    private var hojaPersona: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.xmark").font(.system(size: 22)).foregroundStyle(C.avisoTinta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apareció una persona").estilo(.headline)
                        Text(Formato.sinViudas("Para cuidar su privacidad mandamos a leer sólo el recuadro del cartel. Podés ajustarlo."))
                            .estilo(.subhead).foregroundStyle(C.texto2)
                    }
                }
                HStack(spacing: 8) {
                    Button("Sacar otra", action: repetir).buttonStyle(BotonHundido())
                    Button("Leer el recorte") { Task { await leerRecorte() } }.buttonStyle(BotonAccion())
                }
            }
            .foregroundStyle(C.texto)
            .padding(18)
            .background(C.superficie, in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }

    // MARK: Revisión

    private var precioTexto: String? {
        if let p = f.precio { return Formato.plata(p, f.moneda) }
        if !alternativas.isEmpty { return alternativas.map { Formato.plata($0, f.moneda) }.joined(separator: " o ") }
        return nil
    }

    private var tipoTexto: String? {
        guard let t = f.tipo else { return nil }
        return [Propiedad.tipos.first { $0.0 == t }?.1 ?? t, f.ambientes.map { "\($0) amb." }].compactMap { $0 }.joined(separator: " · ")
    }

    private var direccionTexto: String { [f.direccion.trimmingCharacters(in: .whitespaces).nonEmpty, f.barrio].compactMap { $0 }.joined(separator: ", ") }
    private var listoParaCaptar: Bool { f.operacion != nil && f.tipo != nil && f.direccion.trimmingCharacters(in: .whitespaces).count >= 3 && !(!alternativas.isEmpty && f.precio == nil) }
    private static let operaciones = ["venta": "Venta", "alquiler": "Alquiler", "temporario": "Temporario"]

    private var revision: some View {
        let nolee = fase == .nolee
        let dudaPrecio = !alternativas.isEmpty && f.precio == nil
        return VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(C.linea2).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    if !nolee {
                        Text("Revisá lo que leímos").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font)
                        Text("tocá para corregir").estilo(.footnote).foregroundStyle(C.texto2)
                    } else if ilegible, f.telefono == nil {
                        Text("No pudimos leer el cartel").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font)
                        Text(Formato.sinViudas("Probá con otra foto, más de frente, o completá lo que falta ahora o después.")).estilo(.footnote).foregroundStyle(C.texto2)
                    } else {
                        Text("Leímos la mitad").font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font)
                        Text(Formato.sinViudas("La foto salió movida. Tenemos \(f.telefono != nil ? "el teléfono" : "una parte"); el resto lo podés completar ahora o después."))
                            .estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
                VStack(spacing: 0) {
                    fila("operacion", "Operación", f.operacion.flatMap { Self.operaciones[$0] } ?? "Elegí", duda: f.operacion == nil, primera: true)
                    fila("tipo", "Tipo", tipoTexto ?? "Elegí", duda: f.tipo == nil)
                    fila("precio", "Precio", precioTexto ?? (nolee ? "No figura en el cartel" : "Sin precio"), duda: dudaPrecio, nota: dudaPrecio ? "No se lee bien" : nil)
                    if dudaPrecio {
                        HStack(spacing: 8) {
                            ForEach(alternativas, id: \.self) { n in
                                Button(Formato.plata(n, f.moneda)) { f.precio = n }.buttonStyle(BotonTonal(alto: 32))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.bottom, 10)
                    }
                    fila("telefono", "Teléfono", f.telefono ?? "Sin teléfono", duda: false, nota: f.telefono == nil ? nil : (f.inmobiliaria ?? "dueño directo"))
                    fila("direccion", "Dirección", direccionTexto.nonEmpty ?? "Calle y altura", duda: f.direccion.trimmingCharacters(in: .whitespaces).count < 3, nota: f.gps ? "GPS" : nil)
                }
                .background(C.hundida, in: .rect(cornerRadius: 16, style: .continuous))
                if !nolee {
                    Label("MIRA lee con Google Gemini y puede equivocarse. Revisá los datos antes de captar.", systemImage: "info.circle")
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
                Button { Task { await captar() } } label: {
                    HStack(spacing: 8) {
                        if captando { ProgressView().tint(C.sobreAccion) } else { Image(systemName: "house.badge.plus") }
                        Text(nolee ? "Captar con lo que hay" : (dudaPrecio ? "Elegí el precio para captar" : "Captar"))
                    }
                    .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font)
                    .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 54)
                    .background(C.accion.opacity(listoParaCaptar ? 1 : 0.45), in: .rect(cornerRadius: 15, style: .continuous))
                }
                .disabled(!listoParaCaptar || captando)
                Button(nolee ? "Sacar otra foto" : "Sacar de nuevo", action: repetir).font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(C.texto)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            .background(C.superficie, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
        }
        .background(Color.black.opacity(0.25))
        .ignoresSafeArea(edges: .bottom)
    }

    private func fila(_ campo: String, _ k: String, _ v: String, duda: Bool, nota: String? = nil, primera: Bool = false) -> some View {
        Button { editando = campo } label: {
            HStack(spacing: 10) {
                Text(k).estilo(.texto14).foregroundStyle(C.texto2).frame(width: 86, alignment: .leading)
                Text(v).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let nota {
                    Text(nota).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(duda ? C.avisoTinta : C.texto2)
                        .padding(.horizontal, 8).frame(height: 24).background(duda ? C.avisoFondo : C.superficie, in: Capsule())
                } else if duda {
                    Text("Revisá").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.avisoTinta)
                        .padding(.horizontal, 8).frame(height: 24).background(C.avisoFondo, in: Capsule())
                }
                Image(systemName: "pencil").foregroundStyle(C.texto3)
            }
            .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Captada

    private func pantallaCaptada(_ p: Propiedad, contacto: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "house.badge.plus").font(.system(size: 38, weight: .semibold)).foregroundStyle(Color(hex: 0x1A1405))
                        .frame(width: 96, height: 96).background(C.oro, in: Circle())
                    Text("\(p.direccion ?? "La propiedad") quedó captada").estilo(.titulo3).multilineTextAlignment(.center)
                    Text(Formato.sinViudas("Está como borrador en tu cartera, no se publica hasta que la completes.\(contacto != nil ? " El dueño directo quedó cargado como contacto." : "")"))
                        .estilo(.subhead).foregroundStyle(C.texto2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
                HStack(spacing: 12) {
                    Group {
                        if let foto, let i = cola.imagen(foto) { Image(uiImage: i).resizable().scaledToFill() } else { C.hundida }
                    }
                    .frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\([p.tipoTexto, p.ambientes.map { "\($0) amb" }].compactMap { $0 }.joined(separator: " ")) · \(Self.operaciones[p.operacion ?? ""] ?? "")").estilo(.subheadFuerte)
                        Text([p.precio.map { Formato.plata($0, p.moneda ?? "USD") } ?? "Sin precio", p.barrio].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        Text("Borrador").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2)
                            .padding(.horizontal, 8).frame(height: 22).overlay(Capsule().strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                    Spacer()
                }
                .padding(12).background(C.superficie, in: .rect(cornerRadius: 16, style: .continuous))
                if let t = f.telefono, f.inmobiliaria == nil {
                    Button { Afuera.whatsapp((t.hasPrefix("+") ? "" : "549") + t.filter(\.isNumber)) } label: { Label("Escribirle al dueño", systemImage: "bubble.left.fill") }
                        .buttonStyle(BotonAccion())
                }
                HStack(spacing: 8) {
                    Button("Completar ficha") {
                        estado.miraAbierta = false
                        estado.ir(Ruta(.propiedades, AAltaPropiedad(editar: p.id)))
                    }
                    .buttonStyle(BotonHundido())
                    Button("Captar otro", action: repetir).buttonStyle(BotonHundido())
                }
            }
            .foregroundStyle(C.texto)
            .padding(20)
        }
        .background(FondoApp())
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
            Button("Abrir Ajustes") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u, options: [:], completionHandler: nil) } }
                .font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(Color(hex: 0x1A1405))
                .padding(.horizontal, 26).frame(height: 52).background(C.oro, in: .rect(cornerRadius: 14, style: .continuous)).padding(.top, 8)
            PhotosPicker(selection: $elegida, matching: .images) { Text("Elegir una foto").font(Estilo.subheadFuerte.font).foregroundStyle(Color(hex: 0xCFE0D8)).frame(height: 44) }
            Button("Cargar a mano") { cargarAMano() }.font(Estilo.subheadFuerte.font).foregroundStyle(Color(hex: 0xCFE0D8)).frame(height: 44)
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
        let x = cola.guardar(jpg, lat: ubicacion.ultima?.coordinate.latitude, lng: ubicacion.ultima?.coordinate.longitude, direccion: ubicacion.direccion)
        foto = x
        if recortarSiempre {
            recorte = CGRect(x: 0.07, y: 0.14, width: 0.58, height: 0.36)
            fase = .persona
            return
        }
        await leer(x, recortada: false)
    }

    private func leer(_ x0: FotoMira, recortada: Bool) async {
        var x = x0
        f = FormMira()
        alternativas = []
        ilegible = false
        fase = .leyendo
        barrido = false
        try? await Task.sleep(for: .milliseconds(60))
        barrido = true
        do {
            try await MiraLector.leer(&x, api: estado.api)
            if recortada, x.estado == "persona" { x.estado = "leida" }
            cola.actualizar(x)
            foto = x
            if x.estado == "persona" {
                recorte = CGRect(x: 0.07, y: 0.14, width: 0.58, height: 0.36)
                fase = .persona
                return
            }
            await completar(x)
        } catch let e as ErrorApi where e.sinConexion {
            fase = .sinSenal
        } catch {
            estado.avisar(error)
            fase = .apuntando
        }
    }

    /// Pasa lo leído a la ficha y completa la dirección con el GPS (con barrio y ciudad) si el cartel no la tenía.
    private func completar(_ x: FotoMira) async {
        ilegible = x.estado == "ilegible"
        if let d = x.lectura {
            f.operacion = d.operacion
            f.tipo = d.tipo
            f.ambientes = d.ambientes
            f.dormitorios = d.dormitorios
            f.superficie = d.superficie
            f.precio = d.precio
            f.moneda = d.moneda ?? "USD"
            f.telefono = d.telefono
            f.inmobiliaria = d.inmobiliaria
            f.direccion = d.direccion ?? ""
            f.notas = d.notas
            let alt = d.precioAlternativas ?? []
            alternativas = alt.count >= 2 ? Array(alt.prefix(3)) : []
            if !alternativas.isEmpty { f.precio = nil }
        }
        f.lat = x.lat
        f.lng = x.lng
        if f.direccion.isEmpty, let lat = x.lat, let lng = x.lng,
           let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng)).first {
            f.direccion = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            f.barrio = p.subLocality
            f.ciudad = p.locality
            f.gps = !f.direccion.isEmpty
        }
        let faltan = [f.operacion == nil, f.precio == nil && alternativas.isEmpty, f.telefono == nil].filter { $0 }.count
        fase = ilegible || faltan >= 2 ? .nolee : .revisar
        if fase == .revisar, f.direccion.isEmpty { editando = "direccion" }
    }

    /// Recorta el recuadro del cartel, lo guarda como la foto (lo único que se manda) y lo lee.
    private func leerRecorte() async {
        guard let x = foto, let i = cola.imagen(x), let cg = i.normalizada.cgImage else { return }
        let r = CGRect(x: recorte.minX * CGFloat(cg.width), y: recorte.minY * CGFloat(cg.height),
                       width: recorte.width * CGFloat(cg.width), height: recorte.height * CGFloat(cg.height)).integral
        guard let c = cg.cropping(to: r), let d = UIImage(cgImage: c).jpegData(compressionQuality: 0.85) else { return }
        let nueva = cola.guardar(d, lat: x.lat, lng: x.lng, direccion: x.direccionGPS)
        cola.sacar(x)
        foto = nueva
        await leer(nueva, recortada: true)
    }

    /// Abre una foto de la cola ya leída (desde Captadas) para revisarla y captarla.
    private func abrirPedida() {
        guard let id = cola.abrir, let x = cola.fotos.first(where: { $0.id == id }) else { return }
        cola.abrir = nil
        foto = x
        if x.estado == "persona" {
            recorte = CGRect(x: 0.07, y: 0.14, width: 0.58, height: 0.36)
            fase = .persona
            return
        }
        f = FormMira()
        alternativas = []
        Task { await completar(x) }
    }

    private func captar() async {
        guard listoParaCaptar, !captando, var x = foto else { return }
        captando = true
        defer { captando = false }
        struct Captada: Encodable {
            var archivoId: String?
            var titulo = ""
            var tipo: String
            var operacion: String
            var precio: Double?
            var moneda: String
            var direccion: String
            var barrio: String?
            var ciudad: String?
            var lat: Double?
            var lng: Double?
            var ambientes: Int?
            var dormitorios: Int?
            var superficie: Double?
            var telefono: String?
            var inmobiliaria: String?
            var notas: String?
        }
        let envio = UUID().uuidString
        let dir = f.direccion.trimmingCharacters(in: .whitespaces)
        do {
            let c = Captada(archivoId: x.archivoId, tipo: f.tipo ?? "departamento", operacion: f.operacion ?? "venta", precio: f.precio, moneda: f.moneda,
                            direccion: dir, barrio: f.barrio, ciudad: f.ciudad, lat: f.lat, lng: f.lng, ambientes: f.ambientes, dormitorios: f.dormitorios,
                            superficie: f.superficie, telefono: f.telefono, inmobiliaria: f.inmobiliaria, notas: nil)
            var p: Propiedad = try await estado.api.conCampos("POST", "/v1/mira/propiedad", c, envio: envio, como: Propiedad.self)
            // El dueño directo (cartel sin inmobiliaria) queda como contacto, colgado de la propiedad.
            var contacto: String?
            if let t = f.telefono, f.inmobiliaria == nil {
                struct K: Encodable { var nombre: String; var telefono: String; var tipo = "propietario"; var origen = "MIRA" }
                struct Creado: Decodable { var id: String }
                do {
                    let k: Creado = try await estado.api.conCampos("POST", "/v1/contactos", K(nombre: "Dueño de \(dir)", telefono: t), envio: envio + "-c", como: Creado.self)
                    contacto = k.id
                    p.propietarioId = k.id
                    try await estado.api.hacer("PUT", "/v1/propiedades/\(p.id)", p)
                } catch {
                    // La propiedad ya está; el contacto se carga después.
                }
            }
            x.estado = "captada"
            x.propiedadId = p.id
            cola.actualizar(x)
            foto = x
            estado.version += 1
            captada = (p, contacto)
            fase = .captada
            Haptico.exito()
            let id = p.id
            let vuelta = x
            estado.avisar("Captada en tu cartera") {
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/propiedades/\(id)")
                        if let contacto {
                            do { try await estado.api.hacer("DELETE", "/v1/contactos/\(contacto)") } catch { estado.avisar(error) }
                        }
                        var y = vuelta
                        y.estado = "leida"
                        y.propiedadId = nil
                        cola.actualizar(y)
                        captada = nil
                        fase = .revisar
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch let e as ErrorConCampos {
            estado.avisar(e.campos.values.first ?? e.error.detalle, ok: false)
        } catch let e as ErrorApi where e.sinConexion {
            fase = .sinSenal
        } catch { estado.avisar(error) }
    }

    private func repetir() {
        foto = nil
        captada = nil
        f = FormMira()
        alternativas = []
        fase = .apuntando
    }

    private func cargarAMano() {
        cerrar()
        estado.ir(Ruta(.propiedades, AAltaPropiedad()))
    }
}

extension UIImage {
    /// La imagen con la orientación aplicada (para recortar sobre los píxeles que se ven).
    var normalizada: UIImage {
        if imageOrientation == .up { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// La foto con el recuadro del cartel: se mueve arrastrándolo y se agranda desde la esquina. Sólo eso
/// se manda a leer.
struct VistaRecorte: View {
    var imagen: UIImage
    @Binding var recorte: CGRect
    @State private var inicio: CGRect?

    var body: some View {
        GeometryReader { g in
            let prop = imagen.size.width / max(1, imagen.size.height)
            let ancho = min(g.size.width - 32, (g.size.height - 260) * prop)
            let alto = ancho / prop
            ZStack(alignment: .topLeading) {
                Image(uiImage: imagen).resizable().frame(width: ancho, height: alto)
                Rectangle().fill(.black.opacity(0.45)).frame(width: ancho, height: alto)
                    .mask {
                        Rectangle().overlay(alignment: .topLeading) {
                            Rectangle().frame(width: recorte.width * ancho, height: recorte.height * alto)
                                .offset(x: recorte.minX * ancho, y: recorte.minY * alto).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 6).strokeBorder(C.oro, lineWidth: 3)
                    .frame(width: recorte.width * ancho, height: recorte.height * alto)
                    .overlay(alignment: .topLeading) {
                        Text("Sólo esto se envía").font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font).foregroundStyle(Color(hex: 0x1A1405))
                            .padding(.horizontal, 6).frame(height: 20).background(C.oro, in: Capsule()).padding(6)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(C.oro).frame(width: 26, height: 26).overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.black))
                            .offset(x: 10, y: 10)
                            .gesture(DragGesture().onChanged { v in
                                let r0 = inicio ?? recorte
                                if inicio == nil { inicio = recorte }
                                recorte.size.width = min(1 - r0.minX, max(0.15, r0.width + v.translation.width / ancho))
                                recorte.size.height = min(1 - r0.minY, max(0.12, r0.height + v.translation.height / alto))
                            }.onEnded { _ in inicio = nil })
                            .accessibilityLabel("Agrandar el recuadro")
                    }
                    .offset(x: recorte.minX * ancho, y: recorte.minY * alto)
                    .gesture(DragGesture().onChanged { v in
                        let r0 = inicio ?? recorte
                        if inicio == nil { inicio = recorte }
                        recorte.origin.x = min(1 - r0.width, max(0, r0.minX + v.translation.width / ancho))
                        recorte.origin.y = min(1 - r0.height, max(0, r0.minY + v.translation.height / alto))
                    }.onEnded { _ in inicio = nil })
                    .accessibilityLabel("Recuadro del cartel: arrastralo para moverlo")
            }
            .frame(width: ancho, height: alto)
            .position(x: g.size.width / 2, y: 70 + alto / 2)
        }
        .ignoresSafeArea(edges: .bottom)
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

/// Corregir un campo de lo leído (operación, tipo con los ambientes, precio, teléfono, dirección).
struct EditorCampoMira: View {
    @Environment(\.dismiss) private var cerrar
    var campo: String
    @Binding var f: FormMira
    var alternativas: [Double]

    var body: some View {
        NavigationStack {
            Form {
                switch campo {
                case "operacion":
                    Picker("Operación", selection: Binding(get: { f.operacion ?? "venta" }, set: { f.operacion = $0 })) {
                        Text("Venta").tag("venta"); Text("Alquiler").tag("alquiler"); Text("Temporario").tag("temporario")
                    }.pickerStyle(.inline).labelsHidden()
                case "tipo":
                    Picker("Tipo", selection: Binding(get: { f.tipo ?? "departamento" }, set: { f.tipo = $0 })) {
                        ForEach(Propiedad.tipos, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Stepper(f.ambientes.map { "\($0) ambientes" } ?? "Ambientes", value: Binding(get: { f.ambientes ?? 0 }, set: { f.ambientes = $0 == 0 ? nil : $0 }), in: 0...20)
                case "precio":
                    Picker("Moneda", selection: $f.moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                    TextField("Precio", value: $f.precio, format: .number).keyboardType(.numberPad)
                    ForEach(alternativas, id: \.self) { p in
                        Button("¿Era \(Formato.plata(p, f.moneda))?") { f.precio = p; cerrar() }
                    }
                case "telefono":
                    TextField("11 5555-0000", text: Binding(get: { f.telefono ?? "" }, set: { f.telefono = $0.nonEmpty })).keyboardType(.phonePad)
                    TextField("Inmobiliaria del cartel (vacío: dueño directo)", text: Binding(get: { f.inmobiliaria ?? "" }, set: { f.inmobiliaria = $0.nonEmpty }))
                default:
                    TextField("Calle y altura", text: Binding(get: { f.direccion }, set: { f.direccion = $0; f.gps = false }))
                    TextField("Barrio", text: Binding(get: { f.barrio ?? "" }, set: { f.barrio = $0.nonEmpty }))
                    TextField("Ciudad", text: Binding(get: { f.ciudad ?? "" }, set: { f.ciudad = $0.nonEmpty }))
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }
}

/// Una captada de la bandeja (web: lib/propiedades/mira-captadas.ts).
struct CaptadaMira: Identifiable {
    var p: Propiedad
    var telefono: String?
    /// La inmobiliaria del cartel: si es de otra, queda como dato de mercado.
    var deOtra: String?
    var faltanFotos: Bool
    var contactado: Bool
    var id: String { p.id }
    var sinLlamar: Bool { deOtra == nil && telefono != nil && !contactado }

    static func nota(_ p: Propiedad, _ prefijo: String) -> String? {
        let n = p.ficha?["notasInternas"]?.texto ?? ""
        return n.components(separatedBy: "\n").first { $0.hasPrefix(prefijo) }.map { String($0.dropFirst(prefijo.count)).trimmingCharacters(in: .whitespaces) }?.nonEmpty
    }
}

/// 5I Captadas: la cola sin señal, lo leído para revisar (se abre en MIRA para captarlo) y lo captado
/// que sigue en la bandeja (sin publicar o de esta semana), con «Sin llamar» y «Faltan fotos».
struct Captadas: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    private let cola = ColaMira.compartida
    @State private var delServidor: [CaptadaMira] = []
    @State private var error: ErrorApi?
    @State private var cargado = false
    @State private var ver: String?
    @State private var meta: Int?

    private static let semana: TimeInterval = 7 * 86400

    private func traer() async {
        do {
            let l: [Propiedad] = try await estado.api.todas("/v1/propiedades", query: [.init(name: "orden", value: "actualizada")])
            let ahora = Date()
            let ms = l.filter { $0.deMira && ($0.publicada != true || ahora.timeIntervalSince($0.creadaEn ?? .distantPast) < Self.semana) }
            let s = (try? await Senal.de(ms.map(\.id), api: estado.api)) ?? [:]
            delServidor = ms.map { p in
                let x = s[p.id]
                return CaptadaMira(p: p, telefono: CaptadaMira.nota(p, "Teléfono del cartel:"), deOtra: CaptadaMira.nota(p, "Cartel de:"),
                                   faltanFotos: (p.fotos ?? []).count <= 1, contactado: (x?.interesados ?? 0) > 0 || x?.proximaVisita != nil)
            }
            error = nil
            struct Obj: Decodable { var metrica: String; var meta: Double; var desde: String; var hasta: String }
            let hoy = Formato.diaISO(Date())
            if let os: [Obj] = try? await estado.api.get("/v1/objetivos") {
                meta = os.first { $0.metrica == "propiedades_captadas" && $0.desde <= hoy && $0.hasta >= hoy }.map { Int($0.meta) }
            }
        } catch let e as ErrorApi { error = e } catch {}
        cargado = true
    }

    private var visibles: [CaptadaMira] {
        let l = delServidor
        switch ver {
        case "sin-llamar": return l.filter(\.sinLlamar)
        case "sin-fotos": return l.filter { $0.faltanFotos && $0.deOtra == nil }
        default: return l
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let estaSemana = delServidor.filter { Date().timeIntervalSince($0.p.creadaEn ?? .distantPast) < Self.semana }.count
                Text("\(estaSemana) esta semana\(meta.map { " · objetivo del mes \($0)" } ?? "")").estilo(.subhead).foregroundStyle(C.texto2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipFiltro(texto: "Todas · \(delServidor.count)", activo: ver == nil) { ver = nil }
                        ChipFiltro(texto: "Sin llamar · \(delServidor.filter(\.sinLlamar).count)", activo: ver == "sin-llamar") { ver = "sin-llamar" }
                        ChipFiltro(texto: "Faltan fotos · \(delServidor.filter { $0.faltanFotos && $0.deOtra == nil }.count)", activo: ver == "sin-fotos") { ver = "sin-fotos" }
                    }
                }
                let enCola = cola.fotos.filter { $0.estado == "cola" }.count
                if enCola > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.up").font(.system(size: 20)).foregroundStyle(C.texto2)
                        Text("\(Formato.cantidad(enCola, "foto en cola", "fotos en cola")) · se lee sola cuando vuelva la señal").estilo(.texto14).foregroundStyle(C.texto)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                }
                if ver == nil {
                    ForEach(cola.fotos.filter { $0.estado != "captada" }) { f in filaCola(f) }
                }
                if let error, delServidor.isEmpty {
                    EstadoVacio(icono: "exclamationmark.triangle", titulo: "No pudimos traer lo captado", texto: error.sinConexion ? "No hay internet." : "Probá de nuevo en un ratito.",
                                accion: ("Reintentar", { Task { await traer() } }))
                        .padding(.top, 20)
                }
                ForEach(visibles) { c in filaServidor(c) }
                if cargado, error == nil, cola.fotos.isEmpty, delServidor.isEmpty {
                    EstadoVacio(icono: "viewfinder", titulo: "Todavía no captaste carteles",
                                texto: "Fotografiá un cartel de «Vende» y MIRA lo carga por vos.",
                                accion: ("Captar con MIRA", { estado.miraAbierta = true; cerrar() }))
                        .padding(.top, 30)
                } else if cargado, !delServidor.isEmpty, visibles.isEmpty {
                    Text(ver == "sin-llamar" ? "Ya llamaste a todos." : "Todas tienen fotos.").estilo(.subhead).foregroundStyle(C.texto2).padding(.top, 10)
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
        .refreshable { await cola.leerPendientes(estado.api); await traer() }
        .task(id: estado.version) { await cola.leerPendientes(estado.api); await traer() }
    }

    private func filaServidor(_ c: CaptadaMira) -> some View {
        let p = c.p
        return HStack(spacing: 12) {
            Button { abrirFicha(p.id) } label: {
                HStack(spacing: 12) {
                    Foto(url: p.miniatura).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.direccion ?? p.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                        Text([p.precioTexto, p.barrio].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        HStack(spacing: 6) {
                            if let o = c.deOtra {
                                chip("Cartel de \(o)", .neutro)
                            } else if c.contactado {
                                chip("Dueño contactado", .verde)
                            } else if c.telefono != nil {
                                chip("Sin llamar · \(max(0, diasCalendario(p.creadaEn ?? Date(), Date()))) días", .rojo)
                            }
                            if c.faltanFotos, c.deOtra == nil { chip("Faltan fotos", .oro) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if c.sinLlamar, let t = c.telefono {
                Button { Afuera.llamar(t) } label: { Image(systemName: "phone.fill").frame(width: 44, height: 44).background(C.okFondo, in: Circle()).foregroundStyle(C.okTinta) }
                    .accessibilityLabel("Llamar al \(t)")
            }
        }
        .padding(10).tarjeta()
    }

    private func chip(_ t: String, _ tono: Tono) -> some View {
        Text(t).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta).lineLimit(1)
            .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
    }

    private func filaCola(_ f: FotoMira) -> some View {
        let (texto, icono, tono) = Self.estado(f)
        return Button { abrir(f) } label: {
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
        .buttonStyle(Presionable())
        .contextMenu { Button(role: .destructive) { cola.sacar(f) } label: { Label("Sacar de la lista", systemImage: "trash") } }
    }

    private func abrirFicha(_ id: String) {
        estado.abrir(AFichaPropiedad(id: id), en: .propiedades)
        estado.pestana = .propiedades
        estado.miraAbierta = false
    }

    /// Lo leído (o con persona, o ilegible) se abre en MIRA para revisarlo y captarlo.
    private func abrir(_ f: FotoMira) {
        if let p = f.propiedadId { abrirFicha(p); return }
        guard f.estado != "cola" else { return }
        cola.abrir = f.id
        if !estado.miraAbierta { estado.miraAbierta = true }
        cerrar()
    }

    static func estado(_ f: FotoMira) -> (String, String, Tono) {
        switch f.estado {
        case "cola": return ("En cola", "icloud.slash", .neutro)
        case "leida": return ("Revisá antes del alta", "exclamationmark.circle", .oro)
        case "persona": return ("Elegí el recorte del cartel", "crop", .oro)
        case "captada": return ("Borrador", "checkmark.circle", .verde)
        case "ilegible": return ("No se pudo leer · completalo", "aqi.medium", .rojo)
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
