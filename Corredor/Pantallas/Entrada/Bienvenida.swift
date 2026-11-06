import PhotosUI
import SwiftUI
import UserNotifications

/// La bienvenida de quien se suma a un equipo (su alta corta, la misma que el panel web en
/// /bienvenida): la foto y el WhatsApp con los que aparece en la web y en las fichas, los avisos y la
/// apariencia. Todo se puede dejar para después; al cerrarla sigue el recorrido.
struct Bienvenida: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @AppStorage("tema") private var tema = "sistema"
    @State private var enLaWeb = EnLaWeb()
    @State private var foto: PhotosPickerItem?
    @State private var subiendo = false
    @State private var whatsapp = ""
    @State private var guardado = ""
    @State private var permiso: UNAuthorizationStatus = .notDetermined
    /// Cuántas propiedades le asignaron y quién (el dueño o la dueña del equipo).
    @State private var propias = 0
    @State private var quienAsigna = ""

    /// Cómo aparece en la web de la inmobiliaria (GET/PUT /v1/perfil/web).
    struct EnLaWeb: Codable { var fotoId: String?; var enWeb = true; var presentacion: String? }

    /// «Hola, Martín. Esto es lo tuyo hoy.»
    private var saludo: String {
        let n = (estado.usuario?.nombre.nonEmpty ?? estado.usuario?.email ?? "").split(separator: " ").first.map(String.init) ?? ""
        return "Hola, \(n). Esto es lo tuyo hoy."
    }

    /// La foto subida (GET /v1/archivos/{id} da su dirección pública).
    @State private var urlFoto: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text((estado.inmobiliaria?.nombre ?? "").uppercased())
                            .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).tracking(0.6).foregroundStyle(C.oroTinta)
                        Text(saludo).estilo(.tituloPaso).foregroundStyle(C.texto)
                    }
                    PhotosPicker(selection: $foto, matching: .images) {
                        HStack(spacing: 14) {
                            Group {
                                if let u = urlFoto ?? estado.usuario?.foto.flatMap(URL.init(string:)) {
                                    // La subida o, si no subió otra, la de la cuenta.
                                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                                } else {
                                    Text(Formato.iniciales(estado.usuario?.completo ?? "C")).font(Estilo(tamano: 22, peso: .bold, relativo: .title3).font)
                                        .foregroundStyle(C.oro).frame(maxWidth: .infinity, maxHeight: .infinity).background(C.verde700)
                                }
                            }
                            .frame(width: 64, height: 64).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subiendo ? "Subiendo…" : "Tu foto").estilo(.filaLista).foregroundStyle(C.texto)
                                Text("Sale en la web y en las fichas que mandás").estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.texto3)
                        }
                        .padding(14).tarjeta()
                    }
                    .disabled(subiendo)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tu WhatsApp").estilo(.filaLista).foregroundStyle(C.texto)
                        HStack(spacing: 8) {
                            TextField("11 5555 0000", text: $whatsapp).keyboardType(.phonePad).campoCorredor()
                            Button(guardado == whatsapp && !whatsapp.isEmpty ? "Listo" : "Guardar") { Task { await guardarWhatsApp() } }
                                .buttonStyle(BotonSecundario()).fixedSize()
                                .disabled(whatsapp.trimmingCharacters(in: .whitespaces).isEmpty || guardado == whatsapp)
                        }
                        Text("Ahí te escriben por las propiedades que tenés.").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .padding(14).tarjeta()
                    if permiso != .authorized && permiso != .provisional && permiso != .ephemeral {
                        tarea("bell.badge", .oro, "Activá los avisos", "Para que no se te escape una consulta") { Task { await avisos() } }
                    }
                    if propias > 0 {
                        tarea("house", .verde, "\(quienAsigna.nonEmpty ?? "Tu equipo") te asignó \(Formato.cantidad(propias, "propiedad", "propiedades"))", "Miralas en 1 minuto") { verCartera() }
                    } else {
                        tarea("house", .verde, "Mirá la cartera", "Lo que no tiene dueño también es tuyo") { verCartera() }
                    }
                    tarea("camera", .neutro, "Probá MIRA con un cartel", "Tres toques, sin escribir") {
                        cerrar()
                        estado.miraAbierta = true
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apariencia").estilo(.filaLista).foregroundStyle(C.texto)
                        Segmentado(opciones: [("sistema", "Automático"), ("claro", "Claro"), ("oscuro", "Oscuro")], elegido: $tema)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    Button("Empezar") { Task { await empezar() } }
                        .buttonStyle(BotonPrincipal())
                    Text("Podés saltearlo: queda en tu Inicio.").estilo(.footnote).foregroundStyle(C.texto2)
                }
                .padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial)
            }
            .background(FondoApp())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Saltear") { cerrar() } } }
        }
        .task {
            struct P: Decodable { var whatsapp: String? }
            if let p: P = try? await estado.api.get("/v1/perfil") { whatsapp = p.whatsapp ?? ""; guardado = whatsapp }
            if let w: EnLaWeb = try? await estado.api.get("/v1/perfil/web") {
                enLaWeb = w
                if let id = w.fotoId, let a: Archivo = try? await estado.api.get("/v1/archivos/\(id)") { urlFoto = a.url.flatMap(URL.init(string:)) }
            }
            permiso = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            struct Prop: Decodable { var id: String }
            if let l: [Prop] = try? await estado.api.get("/v1/propiedades", query: [.init(name: "agente", value: "yo"), .init(name: "limite", value: "200")]) {
                propias = l.count
            }
            if let eq: [Miembro] = try? await estado.api.get("/v1/equipo") {
                quienAsigna = eq.first(where: { $0.rol == "duenio" && $0.usuarioId != estado.usuario?.id })?.nombre ?? ""
            }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                subiendo = true
                defer { subiendo = false; foto = nil }
                guard let d = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                do {
                    let a = try await estado.api.subir(img.achicada(1200).jpegData(compressionQuality: 0.85) ?? d, nombre: "foto.jpg", tipo: "image/jpeg", uso: "foto")
                    var w = enLaWeb
                    w.fotoId = a.id
                    try await estado.api.hacer("PUT", "/v1/perfil/web", w)
                    enLaWeb = w
                    urlFoto = a.url.flatMap(URL.init(string:))
                    Haptico.exito()
                } catch { estado.avisar(error) }
            }
        }
    }

    /// Una tarea de la bienvenida: ícono en su tono, qué es y para qué.
    private func tarea(_ icono: String, _ tono: Tono, _ titulo: String, _ detalle: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                IconoTono(icono: icono, tono: tono, tam: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).estilo(.filaLista).foregroundStyle(C.texto).multilineTextAlignment(.leading)
                    Text(detalle).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.texto3)
            }
            .padding(14).contentShape(Rectangle()).tarjeta()
        }
        .buttonStyle(Presionable())
    }

    /// Sus propiedades (Propiedades, «Mías»).
    private func verCartera() {
        cerrar()
        estado.pestana = .propiedades
    }

    /// Guarda el WhatsApp si quedó escrito sin guardar, y sigue (al recorrido).
    private func empezar() async {
        if !whatsapp.isEmpty, guardado != whatsapp { await guardarWhatsApp() }
        cerrar()
    }

    private func guardarWhatsApp() async {
        struct C: Encodable { var whatsapp: String }
        let w = whatsapp.trimmingCharacters(in: .whitespaces)
        do {
            try await estado.api.hacer("PATCH", "/v1/perfil", C(whatsapp: w))
            guardado = whatsapp
            estado.avisar("Guardamos tu WhatsApp")
        } catch { estado.avisar(error) }
    }

    private func avisos() async {
        let c = UNUserNotificationCenter.current()
        if await c.notificationSettings().authorizationStatus == .denied {
            // Ya dijo que no: sólo se cambia en Ajustes.
            if let u = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(u, options: [:], completionHandler: nil) }
            return
        }
        await estado.pedirPermisoPush()
        permiso = await c.notificationSettings().authorizationStatus
    }
}
