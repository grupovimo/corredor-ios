import AppIntents
import SwiftUI
import TipKit
import UserNotifications

// MARK: - 2C Búsqueda global

/// 2C Buscar: propiedades, contactos, contratos y operaciones por grupos, mientras se escribe.
struct Buscar: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var texto: String
    @State private var resultados: [Resultado] = []
    @State private var buscando = false
    @FocusState private var foco: Bool

    private static let grupos: [(String, String, String)] = [
        ("propiedad", "Propiedades", "building.2"), ("contacto", "Contactos", "person"), ("contrato", "Contratos", "doc.text"),
        ("operacion", "Operaciones", "rectangle.split.3x1"), ("emprendimiento", "Emprendimientos", "building"),
        ("consorcio", "Consorcios", "building.columns"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(C.texto3)
                    TextField("Calle, persona, contrato…", text: $texto).estilo(.body).focused($foco)
                        .submitLabel(.search).autocorrectionDisabled()
                    if !texto.isEmpty {
                        Button { texto = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }
                            .accessibilityLabel("Borrar")
                    }
                }
                .padding(.horizontal, 10).frame(height: 38)
                .background(C.hundida, in: .rect(cornerRadius: 11, style: .continuous))
                Button("Cancelar") { cerrar() }.font(Estilo.body.font).foregroundStyle(C.accion)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Secciones y acciones («cobrar», «expensas», «dominio»): lo que la app hace, también se busca.
                    let f = MasRaiz.normal(texto)
                    let secciones = f.count < 2 ? [] : MasRaiz.grupos(duenio: estado.esDuenio, avisos: 0).flatMap(\.1).filter { MasRaiz.coincide($0, f) }
                    if !secciones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EN LA APP").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                                .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(secciones.prefix(6).enumerated()), id: \.element.id) { i, it in
                                    Button { estado.abrir(it.destino) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: it.icono).font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 24)
                                            Text(it.texto).estilo(.filaLista).foregroundStyle(C.texto)
                                            Spacer()
                                            Chevron()
                                        }
                                        .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                                    }
                                    .buttonStyle(Presionable())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                }
                            }
                            .tarjeta(16)
                        }
                    }
                    ForEach(Self.grupos, id: \.0) { tipo, titulo, icono in
                        let items = resultados.filter { $0.tipo == tipo }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(titulo.uppercased()).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                                    .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                                        Button { abrir(x) } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.accion).frame(width: 24)
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(x.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                                                    if let d = x.subtitulo { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                                                }
                                                Spacer()
                                                Chevron()
                                            }
                                            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
                                        }
                                        .buttonStyle(Presionable())
                                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                                    }
                                }
                                .tarjeta(16)
                            }
                        }
                    }
                    if !buscando && texto.count >= 2 && resultados.isEmpty {
                        EstadoVacio(icono: "magnifyingglass", titulo: "No encontramos «\(texto)»", texto: "Probá con la calle, el apellido o el código.")
                            .padding(.top, 30)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { foco = true }
        .task(id: texto) {
            guard texto.count >= 2 else { resultados = []; return }
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }
            buscando = true
            resultados = (try? await estado.api.get("/v1/buscar", query: [.init(name: "q", value: texto)])) ?? []
            buscando = false
        }
    }

    private func abrir(_ x: Resultado) {
        switch x.tipo {
        case "propiedad": estado.abrir(AFichaPropiedad(id: x.id))
        case "contacto": estado.abrir(AFichaContacto(id: x.id))
        case "contrato": estado.abrir(AFichaContrato(id: x.id))
        case "operacion": estado.abrir(AFichaOperacion(id: x.id))
        default: estado.abrir(ASeccion(clave: x.tipo + "s", id: x.id))
        }
    }
}

// MARK: - 12A Avisos

/// 12A Avisos (con el segmentado «Avisos · Configurar»): por día, con su acción directa.
struct Avisos: View {
    @Environment(Estado.self) private var estado
    @State private var seg = 0
    @State private var avisos: [AvisoCentro]?
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Segmentado(opciones: [(0, "Avisos"), (1, "Configurar")], elegido: $seg)
                if seg == 1 {
                    ConfigAvisos.Contenido()
                } else if let avisos {
                    if avisos.isEmpty {
                        EstadoVacio(icono: "bell", titulo: "Estás al día", texto: "Acá te avisamos de consultas, cobros, visitas y cambios en tus operaciones.")
                            .padding(.top, 40)
                    }
                    ForEach(grupos(avisos), id: \.0) { titulo, lista in
                        Text(titulo.uppercased()).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                            .tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(lista.enumerated()), id: \.element.id) { i, a in fila(a, primera: i == 0) }
                        }
                        .tarjeta()
                    }
                } else if let error {
                    EstadoError(que: "tus avisos", error: error) { Task { await cargar() } }
                } else {
                    EsqueletoFilas(filas: 6)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Avisos")
        .toolbar {
            if seg == 0, avisos?.contains(where: { $0.leidoEn == nil }) == true {
                Button("Marcar leídos") {
                    Task {
                        try? await estado.api.hacer("POST", "/v1/avisos/leidos")
                        await cargar()
                    }
                }
            }
        }
        .task(id: estado.version) { await cargar() }
    }

    private func fila(_ a: AvisoCentro, primera: Bool) -> some View {
        let (icono, tono) = Self.icono(a.tipo)
        let accion = a.acciones?.first
        return HStack(alignment: .top, spacing: 12) {
            IconoTono(icono: icono, tono: tono, tam: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(a.titulo ?? "").font(Estilo(tamano: 15, peso: a.leidoEn == nil ? .bold : .semibold, relativo: .subheadline).font)
                        .foregroundStyle(C.texto).frame(maxWidth: .infinity, alignment: .leading)
                    Text(a.creadoEn.map { Formato.horaDe($0) } ?? "").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
                }
                if let c = a.cuerpo { Text(c).estilo(.texto14).foregroundStyle(C.texto2) }
                if let accion, a.hechoEn == nil {
                    Button(accion.titulo ?? "Ver") { Task { await hacer(a, accion) } }
                        .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.accion)
                        .padding(.horizontal, 14).frame(height: 34).background(C.hundida, in: Capsule())
                        .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contentShape(Rectangle())
        .onTapGesture { abrir(a) }
        .swipeActions { Button("Leído") { Task { try? await estado.api.hacer("POST", "/v1/avisos/\(a.id)/leido"); await cargar() } }.tint(C.verde700) }
    }

    private func abrir(_ a: AvisoCentro) {
        Task { try? await estado.api.hacer("POST", "/v1/avisos/\(a.id)/leido") }
        if let u = a.url, let r = Ruta(texto: u) { estado.ir(r) }
    }

    /// Una acción del aviso: si trae método y ruta se hace acá (con «Deshacer» si se puede); si no, se abre.
    private func hacer(_ a: AvisoCentro, _ x: AvisoCentro.Accion) async {
        if let m = x.metodo, let r = x.ruta {
            do {
                _ = try await estado.api.pedir(m, r.hasPrefix("/v1") ? r : "/v1" + r)
                try? await estado.api.hacer("POST", "/v1/avisos/\(a.id)/hecho")
                estado.avisar(x.titulo.map { "\($0) · listo" } ?? "Listo")
                await cargar()
            } catch { estado.avisar(error) }
        } else if let u = x.url ?? a.url, let r = Ruta(texto: u) {
            estado.ir(r)
        }
    }

    private func cargar() async {
        do {
            struct Lista: Decodable { var avisos: [AvisoCentro] }
            let l: Lista = try await estado.api.get("/v1/avisos", query: [.init(name: "limite", value: "100")])
            avisos = l.avisos
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
    }

    private func grupos(_ l: [AvisoCentro]) -> [(String, [AvisoCentro])] {
        let cal = Calendar.current
        var hoy: [AvisoCentro] = [], ayer: [AvisoCentro] = [], antes: [AvisoCentro] = []
        for a in l {
            let f = a.creadoEn ?? Date()
            if cal.isDateInToday(f) { hoy.append(a) } else if cal.isDateInYesterday(f) { ayer.append(a) } else { antes.append(a) }
        }
        return [("Hoy", hoy), ("Ayer", ayer), ("Antes", antes)].filter { !$0.1.isEmpty }
    }

    static func icono(_ tipo: String?) -> (String, Tono) {
        switch tipo {
        case "whatsapp": return ("bubble.left", .verde)
        case "mercadolibre": return ("storefront", .oro)
        case "consulta", "tasacion": return ("envelope", .verde)
        case "visita": return ("calendar", .oro)
        case "cobro": return ("dollarsign.circle", .rojo)
        case "operacion": return ("arrow.left.arrow.right", .azul)
        case "mira": return ("viewfinder", .oro)
        default: return ("bell", .neutro)
        }
    }
}

// MARK: - 12B Configurar avisos

/// 12B Configurar avisos: por tipo, push y mail, y el silencio de la noche.
struct ConfigAvisos: View {
    var body: some View {
        ScrollView { Contenido().padding(.horizontal, 16).padding(.vertical, 8) }
            .pantallaApilada("Configurar avisos")
    }

    struct Vista: Codable {
        struct Canales: Codable, Hashable { var tipo: String; var nombre: String?; var push: Bool; var mail: Bool; var sinPush: Bool? }
        struct Silencio: Codable { var activo: Bool; var desde: Int; var hasta: Int; var domingos: Bool }
        var tipos: [Canales]
        var silencio: Silencio
    }

    struct Contenido: View {
        @Environment(Estado.self) private var estado
        @State private var v: Vista?
        @State private var permiso: UNAuthorizationStatus?

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                if permiso == .denied {
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                        Label("Los avisos están apagados en el iPhone. Tocá para prenderlos.", systemImage: "bell.slash")
                            .estilo(.subheadFuerte).foregroundStyle(C.avisoTinta).padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(C.avisoFondo, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                }
                if let v {
                    VStack(spacing: 0) {
                        ForEach(Array(v.tipos.enumerated()), id: \.element.tipo) { i, c in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.nombre ?? c.tipo).font(Estilo(tamano: 16, peso: .medium, relativo: .body).font).foregroundStyle(C.texto)
                                    Text(c.sinPush == true ? "Sólo por mail" : (c.mail ? "Al iPhone y por mail" : "Al iPhone")).estilo(.footnote).foregroundStyle(C.texto2)
                                }
                                Spacer()
                                if c.sinPush != true {
                                    Toggle("", isOn: Binding(get: { c.push }, set: { cambiar(i) { $0.push = $1 }($0) })).labelsHidden().tint(Color(hex: 0x2F9E6F))
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 60)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                            .contextMenu {
                                Button(c.mail ? "No mandarlo por mail" : "Mandarlo también por mail") { cambiar(i) { $0.mail = $1 }(!c.mail) }
                            }
                        }
                    }
                    .tarjeta()
                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(get: { v.silencio.activo }, set: { n in self.v?.silencio.activo = n; guardar() })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Silencio de noche").font(Estilo(tamano: 16, peso: .medium, relativo: .body).font).foregroundStyle(C.texto)
                                Text("De \(v.silencio.desde) a \(v.silencio.hasta) h\(v.silencio.domingos ? " y los domingos" : "")").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                        }
                        .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 14).frame(minHeight: 60)
                    }
                    .tarjeta()
                } else {
                    EsqueletoFilas(filas: 6)
                }
            }
            .task {
                permiso = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                v = try? await estado.api.get("/v1/avisos/preferencias")
            }
        }

        private func cambiar(_ i: Int, _ f: @escaping (inout Vista.Canales, Bool) -> Void) -> (Bool) -> Void {
            { valor in
                guard v != nil, v!.tipos.indices.contains(i) else { return }
                f(&v!.tipos[i], valor)
                guardar()
            }
        }

        private func guardar() {
            guard let v else { return }
            Task {
                do { try await estado.api.hacer("PUT", "/v1/avisos/preferencias", v) } catch { estado.avisar(error) }
            }
        }
    }
}

// MARK: - 13A Perfil

/// 13A Perfil: datos propios, inmobiliarias, Face ID, accesos, lo que antes «quedaba en la web» (ahora
/// todo nativo, en «Todo») y borrar la cuenta, como pide Apple.
struct Perfil: View {
    @Environment(Estado.self) private var estado
    @AppStorage("tema") private var tema = "sistema"
    @State private var faceID = false
    @State private var editando = false
    @State private var borrando = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TipView(ConsejoSiri()).tipBackground(C.superficie)
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline).frame(maxWidth: .infinity)
                Button { editando = true } label: {
                    HStack(spacing: 14) {
                        Text(Formato.iniciales(estado.usuario?.completo ?? "")).font(Estilo(tamano: 22, peso: .bold, relativo: .title2).font)
                            .foregroundStyle(C.oro).frame(width: 60, height: 60).background(C.verde700, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(estado.usuario?.completo ?? "").font(Estilo(tamano: 19, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                            Text(estado.usuario?.email ?? "").estilo(.texto14).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Chevron()
                    }
                    .padding(14).tarjeta()
                }
                .buttonStyle(Presionable())

                VStack(alignment: .leading, spacing: 6) {
                    Text("INMOBILIARIAS").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.5).foregroundStyle(C.texto2).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array((estado.sesion?.inmobiliarias ?? []).enumerated()), id: \.element.id) { i, m in
                            Button {
                                guard m.id != estado.sesion?.inmobiliariaId else { return }
                                Task {
                                    do {
                                        try await estado.elegir(m)
                                        estado.avisar("Estás en \(m.nombre) como \(ElegirInmobiliaria.rol(m.rol).lowercased())")
                                    } catch { estado.avisar(error) }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(m.nombre.prefix(1))).font(Estilo.headline.font).foregroundStyle(C.texto)
                                        .frame(width: 36, height: 36).background(C.hundida, in: .rect(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(m.nombre).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto)
                                        Text(ElegirInmobiliaria.rol(m.rol)).estilo(.footnote).foregroundStyle(C.texto2)
                                    }
                                    Spacer()
                                    if m.id == estado.sesion?.inmobiliariaId { Image(systemName: "checkmark").foregroundStyle(C.accion) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58).contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                }

                VStack(spacing: 0) {
                    Toggle(isOn: $faceID) {
                        Label { Text("Desbloquear con Face ID").estilo(.body16) } icon: { Image(systemName: "faceid").foregroundStyle(C.accion) }
                    }
                    .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 14).frame(minHeight: 54)
                    .onChange(of: faceID) { _, n in estado.conFaceID = n }
                    filaTema
                    ForEach(Self.accesos, id: \.1) { icono, texto, destino in
                        Rectangle().fill(C.linea).frame(height: 0.5)
                        fila(icono, texto) { estado.abrir(destino) }
                    }
                }
                .tarjeta()

                VStack(spacing: 0) {
                    Button("Cerrar sesión") { Task { await estado.salir() } }
                        .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    Rectangle().fill(C.linea).frame(height: 0.5)
                    Button("Borrar mi cuenta") { borrando = true }
                        .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.error)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .tarjeta()
                Text(Formato.sinViudas("Al borrar tu cuenta se eliminan tus datos personales. Las operaciones y contratos quedan en la inmobiliaria."))
                    .estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Text("Corredor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .pantallaApilada("Perfil")
        .onAppear { faceID = estado.conFaceID }
        .sheet(isPresented: $editando) { EditarPerfil().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $borrando) { BorrarCuenta().presentationDetents([.medium]) }
    }

    private static let accesos: [(String, String, AnyHashable)] = [
        ("person.2", "Contactos", AContactos()), ("rectangle.split.3x1", "Operaciones", AOperaciones()),
        ("doc.text", "Contratos y cobranzas", ACobranzas()), ("checklist", "Actas de entrega", ASeccion(clave: "inventarios")),
        ("flag", "Objetivo del mes", ASeccion(clave: "objetivos")), ("bell", "Avisos", AAvisos()),
        ("signature", "Firma y sesiones abiertas", ASeccion(clave: "firma")),
        ("gearshape", "Configuración, consorcios e informes", ASeccion(clave: "mas")),
    ]

    private var filaTema: some View {
        VStack(spacing: 0) {
            Rectangle().fill(C.linea).frame(height: 0.5)
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                Text("Apariencia").estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Picker("Apariencia", selection: $tema) {
                    Text("Como el iPhone").tag("sistema"); Text("Claro").tag("claro"); Text("Oscuro").tag("oscuro")
                }
                .pickerStyle(.menu).tint(C.texto2)
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
        }
    }

    private func fila(_ icono: String, _ texto: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 24)
                Text(texto).estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
    }
}

/// Teléfono y WhatsApp propios (salen en la web y en las fichas que mandás).
struct EditarPerfil: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var telefono = ""
    @State private var whatsapp = ""
    @State private var guardando = false

    struct Datos: Codable { var telefono: String?; var whatsapp: String? }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tus datos").estilo(.titulo)
            Text("Tu nombre y tu mail vienen de tu cuenta de Apple, Google o tu mail. El teléfono sale en tu web y en las fichas.")
                .estilo(.subhead).foregroundStyle(C.texto2)
            Etiquetado("Teléfono") { TextField("+54 9 11 4823-1190", text: $telefono).keyboardType(.phonePad).campoCorredor() }
            Etiquetado("WhatsApp") { TextField("+54 9 11 4823-1190", text: $whatsapp).keyboardType(.phonePad).campoCorredor() }
            Button("Guardar") {
                guardando = true
                Task {
                    do {
                        try await estado.api.hacer("PATCH", "/v1/perfil", Datos(telefono: telefono.nonEmpty, whatsapp: whatsapp.nonEmpty))
                        estado.avisar("Guardado")
                        cerrar()
                    } catch { estado.avisar(error) }
                    guardando = false
                }
            }
            .buttonStyle(BotonPrincipal()).disabled(guardando)
            Spacer()
        }
        .padding(20)
        .background(C.fondo)
        .task {
            if let d: Datos = try? await estado.api.get("/v1/perfil") {
                telefono = d.telefono ?? ""
                whatsapp = d.whatsapp ?? ""
            }
        }
    }
}

/// Borrar la cuenta (lo pide Apple): se confirma escribiendo BORRAR.
struct BorrarCuenta: View {
    @Environment(Estado.self) private var estado
    @State private var texto = ""
    @State private var borrando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Borrás tu cuenta?").estilo(.titulo)
            Text(Formato.sinViudas("Se eliminan tu nombre, tu mail, tu teléfono y tus sesiones. Las operaciones, contratos y conversaciones quedan en la inmobiliaria, sin tu nombre. Esto no se puede deshacer."))
                .estilo(.subhead).foregroundStyle(C.texto2)
            Link("Términos y privacidad", destination: Api.web().appendingPathComponent("terminos")).font(Estilo.subheadFuerte.font)
            TextField("Escribí BORRAR", text: $texto).textInputAutocapitalization(.characters).campoCorredor()
            Button("Borrar mi cuenta") {
                borrando = true
                Task {
                    do {
                        try await estado.api.hacer("DELETE", "/v1/auth/cuenta")
                        await estado.salir()
                    } catch { estado.avisar(error) }
                    borrando = false
                }
            }
            .buttonStyle(BotonDestructivo()).disabled(texto != "BORRAR" || borrando)
            Spacer()
        }
        .padding(20)
        .background(C.fondo)
    }
}
