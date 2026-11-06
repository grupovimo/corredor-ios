import AuthenticationServices
import SwiftUI

/// 42E Equipo: los roles explicados en palabras, las personas con su rol (el dueño lo cambia ahí mismo,
/// con «Deshacer») y su cartera, las invitaciones pendientes con «Reenviar», invitar con el link y las
/// licencias.
struct Equipo: View {
    @Environment(Estado.self) private var estado
    @State private var equipo: [Miembro] = []
    @State private var invitaciones: [Invitacion] = []
    @State private var licencias: [Licencia] = []
    @State private var cargado = false
    @State private var error: ErrorApi?
    @State private var invitando = false
    @State private var verLicencias = false
    @State private var confirmar: Confirmacion?
    /// El rol elegido mientras se guarda (como la web: se ve al toque).
    @State private var rolesEnCurso: [String: String] = [:]

    /// `GET /v1/invitaciones` (equipo.Invitacion).
    struct Invitacion: Codable, Identifiable { var id: String; var email: String; var rol: String; var venceEn: Date?; var creadaEn: Date?; var link: String? }

    static let nombreRol: [String: String] = ["duenio": "Dueño", "agente": "Agente", "lector": "Lector"]
    static let roles: [(String, String, String)] = [
        ("duenio", "Dueño", "Ve y cambia todo: cobranzas, rendiciones, equipo, web e integraciones."),
        ("agente", "Agente", "Su cartera y lo que no tiene dueño. Registra cobros; no emite rendiciones."),
        ("lector", "Lector", "Ve y descarga sin modificar. Para el contador o un socio."),
    ]

    private var yo: String { estado.usuario?.id ?? "" }

    static func nombre(_ m: Miembro) -> String { m.completo }
    static func nombreCorto(_ m: Miembro) -> String { m.nombre?.nonEmpty ?? m.email ?? "" }

    /// «12 propiedades · Palermo y Belgrano», «Administra todo», «Ve y descarga».
    static func cartera(_ m: Miembro) -> String {
        if m.rol == "duenio" { return "Administra todo" }
        if m.rol == "lector" { return "Ve y descarga" }
        let n = m.propiedades ?? 0
        if n == 0 { return "Sin propiedades asignadas" }
        let b = m.barrios ?? []
        let barrios = b.count == 2 ? "\(b[0]) y \(b[1])" : b.first
        return Formato.cantidad(n, "propiedad", "propiedades") + (barrios.map { " · \($0)" } ?? "")
    }

    private var detalle: String {
        Formato.cantidad(equipo.count, "persona", "personas")
            + (invitaciones.isEmpty ? "" : " · " + Formato.cantidad(invitaciones.count, "invitación pendiente", "invitaciones pendientes"))
    }

    var body: some View {
        Group {
            if cargado { lista } else if let error {
                EstadoError(que: "el equipo", error: error) { Task { await cargar() } }.frame(maxHeight: .infinity).background(FondoApp())
            } else {
                EsqueletoFilas(filas: 5).padding(16).frame(maxHeight: .infinity, alignment: .top).background(FondoApp())
            }
        }
        .pantallaApilada("Equipo")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { verLicencias = true } label: { Text(licencias.isEmpty ? "Licencias" : "Licencias · \(licencias.count)") }
                if estado.esDuenio { Button { invitando = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Invitar") }
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $invitando) { InvitarAlEquipo { await cargar() } }
        .sheet(isPresented: $verLicencias) {
            LicenciasEquipo(licencias: licencias, equipo: equipo) { await cargar() }
        }
        .confirmacion($confirmar)
        .navigationDestination(for: ACarteraAgente.self) { c in CarteraAgente(usuario: c.usuario, nombre: c.nombre) }
    }

    private var lista: some View {
        List {
            Section {
                Text(detalle).estilo(.footnote).foregroundStyle(C.texto2)
                ForEach(Self.roles, id: \.0) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.1).estilo(.filaLista).foregroundStyle(r.0 == "duenio" ? C.okTinta : C.texto)
                        Text(Formato.sinViudas(r.2)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
            }
            Section("Personas") {
                ForEach(equipo) { m in fila(m) }
            }
            if !invitaciones.isEmpty {
                Section("Invitaciones pendientes") {
                    ForEach(invitaciones) { i in filaInvitacion(i) }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .refreshable { await cargar() }
    }

    @ViewBuilder
    private func fila(_ m: Miembro) -> some View {
        let rol = rolesEnCurso[m.usuarioId] ?? m.rol ?? "agente"
        HStack(spacing: 12) {
            AvatarPersona(nombre: Self.nombre(m), foto: m.foto, tam: 40)
            VStack(alignment: .leading, spacing: 1) {
                (Text(Self.nombre(m)) + Text(m.usuarioId == yo ? " · vos" : "").foregroundStyle(C.texto3)).estilo(.filaLista).foregroundStyle(C.texto)
                if let e = m.email { Text(e).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1) }
                Text("\(Self.nombreRol[rol] ?? "Agente") · \(Self.cartera(m))").estilo(.footnote).foregroundStyle(C.texto3)
                if m.rol == "agente", (m.propiedades ?? 0) > 0 {
                    Button("Ver cartera") { estado.abrir(ACarteraAgente(usuario: m.usuarioId, nombre: Self.nombre(m))) }
                        .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).buttonStyle(.borderless).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Menu {
                if estado.esDuenio && m.usuarioId != yo {
                    Picker("Rol de \(Self.nombre(m))", selection: Binding(get: { rol }, set: { r in Task { await cambiarRol(m, r) } })) {
                        Text("Dueño").tag("duenio"); Text("Agente").tag("agente"); Text("Lector").tag("lector")
                    }
                }
                if m.rol != "lector" {
                    Button { estado.abrir(ASeccion(clave: "tarjeta-agente", id: m.usuarioId)) } label: { Label("Tarjeta para imprimir", systemImage: "person.text.rectangle") }
                }
                if let t = m.telefono { Button { Afuera.whatsapp(t) } label: { Label("WhatsApp", systemImage: "message") } }
                if estado.esDuenio && m.usuarioId != yo {
                    Divider()
                    Button(role: .destructive) { pedirSacar(m) } label: { Label("Sacar del equipo…", systemImage: "person.badge.minus") }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(C.accion).frame(width: 44, height: 44) }
            .accessibilityLabel("Más acciones de \(Self.nombre(m))")
        }
    }

    @ViewBuilder
    private func filaInvitacion(_ i: Invitacion) -> some View {
        HStack(spacing: 12) {
            Text("?").font(Estilo(tamano: 15, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto3)
                .frame(width: 40, height: 40).overlay(Circle().strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.5, dash: [3])))
            VStack(alignment: .leading, spacing: 1) {
                Text(i.email).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                Text([i.venceEn.map { "vence \(Relativa.de($0))" }, Self.nombreRol[i.rol]].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                if let c = i.creadaEn { Text("Invitación enviada \(Relativa.de(c))").estilo(.footnote).foregroundStyle(C.texto3) }
                HStack(spacing: 16) {
                    Button("Cancelar") { Task { await cancelar(i) } }.foregroundStyle(C.errorTinta)
                    Button("Reenviar") { Task { await reenviar(i.email, i.rol) } }.foregroundStyle(C.oroTinta)
                    if let l = i.link.flatMap(URL.init(string:)) { ShareLink(item: l) { Label("Compartir", systemImage: "square.and.arrow.up") } }
                }
                .font(Estilo.footnoteFuerte.font).buttonStyle(.borderless).padding(.top, 4)
            }
        }
    }

    // MARK: Acciones

    private func cargar() async {
        do {
            let e: [Miembro] = try await estado.api.get("/v1/equipo")
            equipo = e
            if estado.esDuenio { invitaciones = (try? await estado.api.get("/v1/invitaciones")) ?? [] }
            let hoy = Formato.diaISO(Date())
            licencias = (try? await estado.api.get("/v1/licencias", query: [.init(name: "desde", value: hoy), .init(name: "hasta", value: Formato.diaISO(Date().addingTimeInterval(180 * 86400)))])) ?? []
            cargado = true
            error = nil
        } catch let e as ErrorApi { if !cargado { error = e } } catch {}
    }

    private func cambiarRol(_ m: Miembro, _ r: String) async {
        struct Cuerpo: Encodable { var rol: String }
        let antes = rolesEnCurso[m.usuarioId] ?? m.rol ?? "agente"
        guard r != antes else { return }
        rolesEnCurso[m.usuarioId] = r
        do {
            try await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: r))
            await cargar()
            rolesEnCurso[m.usuarioId] = nil
            estado.avisar("\(Self.nombreCorto(m)) ahora es \(Self.nombreRol[r] ?? r)") {
                Task {
                    do { try await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: antes)); await cargar() } catch { estado.avisar(error) }
                }
            }
        } catch {
            rolesEnCurso[m.usuarioId] = nil
            estado.avisar(error)
        }
    }

    /// Sacar del equipo no vuelve solo (hay que invitarla de nuevo): se confirma.
    private func pedirSacar(_ m: Miembro) {
        confirmar = Confirmacion(titulo: "¿Sacás a \(Self.nombreCorto(m)) del equipo?",
                                 texto: "Deja de entrar a la inmobiliaria y lo que tenía asignado queda sin agente. Para que vuelva, la tenés que invitar de nuevo.",
                                 boton: "Sacar del equipo", no: "No, dejarla") { Task { await sacar(m) } }
    }

    private func sacar(_ m: Miembro) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/equipo/\(m.usuarioId)")
            estado.avisar("\(Self.nombreCorto(m)) ya no está en el equipo. Lo suyo quedó sin agente.")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func reenviar(_ email: String, _ rol: String) async {
        struct Cuerpo: Encodable { var email: String; var rol: String }
        do {
            try await estado.api.hacer("POST", "/v1/invitaciones", Cuerpo(email: email, rol: rol))
            estado.avisar("Invitación reenviada a \(email)")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func cancelar(_ i: Invitacion) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/invitaciones/\(i.id)")
            await cargar()
            estado.avisar("Invitación a \(i.email) cancelada") { Task { await reenviar(i.email, i.rol) } }
        } catch { estado.avisar(error) }
    }
}

// MARK: - Invitar

/// «Invitar al equipo»: el mail y el rol (con lo que ve cada uno). Después, el link para copiar o mandar
/// por WhatsApp («vale 7 días»).
struct InvitarAlEquipo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var alInvitar: () async -> Void
    @State private var mail = ""
    @State private var rol = "agente"
    @State private var enviando = false
    @State private var campos: [String: String] = [:]
    @State private var link: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Formato.sinViudas("Le llega un mail con el link. También podés copiarlo y mandarlo por WhatsApp.")).estilo(.footnote).foregroundStyle(C.texto2)
                }
                .listRowBackground(Color.clear)
                if let link { listo(link) } else { formulario }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle("Invitar al equipo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if link != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await invitar() } } label: { if enviando { ProgressView() } else { Text("Mandar invitación") } }
                            .disabled(enviando || mail.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var formulario: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Mail", text: $mail, prompt: Text("nombre@gmail.com"))
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.emailAddress)
                ErrorDeCampo(texto: campos["email"])
            }
        } header: { Text("Mail") }
        Section {
            Segmentado(opciones: [("agente", "Agente"), ("lector", "Lector"), ("duenio", "Dueño")], elegido: $rol)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            Text(Formato.sinViudas(Equipo.roles.first { $0.0 == rol }?.2 ?? "")).estilo(.footnote).foregroundStyle(C.texto2)
        } header: { Text("Rol") }
    }

    @ViewBuilder
    private func listo(_ link: String) -> some View {
        Section {
            Label("Invitación lista. El link vale 7 días.", systemImage: "checkmark.circle.fill").foregroundStyle(C.okTinta)
            Text(link).font(.footnote.monospaced()).foregroundStyle(C.texto).textSelection(.enabled)
            Button {
                UIPasteboard.general.string = link
                estado.avisar("Link copiado. Mandalo por WhatsApp.")
            } label: { Label("Copiar", systemImage: "doc.on.doc") }
            Button { Afuera.whatsapp(nil, texto: link) } label: { Label("Mandar por WhatsApp", systemImage: "message") }
            if let u = URL(string: link) { ShareLink(item: u) { Label("Compartir", systemImage: "square.and.arrow.up") } }
        }
    }

    private func invitar() async {
        let m = mail.trimmingCharacters(in: .whitespaces).lowercased()
        campos = [:]
        guard m.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil else {
            campos["email"] = "No parece un mail."
            return
        }
        enviando = true
        defer { enviando = false }
        struct Cuerpo: Encodable { var email: String; var rol: String }
        do {
            let d = try await estado.api.pedirConCampos("POST", "/v1/invitaciones", Cuerpo(email: m, rol: rol), envio: UUID().uuidString)
            let i = try Api.decodificador.decode(Equipo.Invitacion.self, from: d)
            link = i.link ?? ""
            await alInvitar()
        } catch { campos = estado.camposDe(error) }
    }
}

// MARK: - Licencias

/// «Licencias y ausencias»: quién falta y hasta cuándo (lo que el Inicio muestra en «El equipo hoy»).
/// Cada uno carga la suya; el dueño, la de cualquiera. Quitar es al toque, con «Deshacer».
struct LicenciasEquipo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var licencias: [Licencia]
    var equipo: [Miembro]
    var alCambiar: () async -> Void
    @State private var quitadas: Set<String> = []
    @State private var quien = ""
    @State private var tipo = "licencia"
    @State private var desde = Date()
    @State private var hasta = Date()
    @State private var guardando = false
    @State private var error: String?

    static let tipos: [(String, String)] = [("licencia", "Licencia"), ("vacaciones", "Vacaciones"), ("enfermedad", "Enfermedad"), ("tramite", "Trámite")]
    static let nombre: [String: String] = ["licencia": "De licencia", "vacaciones": "De vacaciones", "enfermedad": "Por enfermedad", "tramite": "Trámite"]

    private var yo: String { estado.usuario?.id ?? "" }
    private var visibles: [Licencia] { licencias.filter { !quitadas.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Formato.sinViudas("Quién falta y hasta cuándo. El Inicio lo muestra en «El equipo hoy».")).estilo(.footnote).foregroundStyle(C.texto2)
                }
                .listRowBackground(Color.clear)
                if !visibles.isEmpty {
                    Section("Las que siguen") { ForEach(visibles) { l in fila(l) } }
                }
                Section("Cargar una") {
                    if estado.esDuenio {
                        Picker("Quién", selection: $quien) {
                            ForEach(equipo.filter { $0.rol != "lector" || $0.usuarioId == yo }) { m in
                                Text(m.usuarioId == yo ? "\(m.completo) (vos)" : m.completo).tag(m.usuarioId)
                            }
                        }
                    }
                    Segmentado(opciones: Self.tipos, elegido: $tipo).listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    DatePicker("Desde", selection: $desde, displayedComponents: .date)
                    DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
                    ErrorDeCampo(texto: error)
                }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle("Licencias y ausencias").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await guardar() } } label: { if guardando { ProgressView() } else { Text("Cargar") } }.disabled(guardando)
                }
            }
        }
        .onAppear { quien = yo }
    }

    private func fila(_ l: Licencia) -> some View {
        HStack(spacing: 12) {
            AvatarIniciales(nombre: l.usuarioNombre ?? "", tam: 36, fondo: C.errorFondo, tinta: C.errorTinta)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.usuarioId == yo ? "Vos" : (l.usuarioNombre ?? "")).estilo(.filaLista).foregroundStyle(C.texto)
                Text("\(Self.nombre[l.tipo ?? ""] ?? "De licencia") · \(l.desde == l.hasta ? "el \(Relativa.corta(l.desde))" : "del \(Relativa.corta(l.desde)) al \(Relativa.corta(l.hasta))")")
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            if estado.esDuenio || l.usuarioId == yo {
                Button("Quitar") { Task { await quitar(l) } }.buttonStyle(.borderless).foregroundStyle(C.accion)
            }
        }
    }

    private struct Cuerpo: Encodable { var usuarioId: String; var tipo: String; var desde: String; var hasta: String; var nota: String? }

    private func guardar() async {
        let d = Formato.diaISO(desde), h = Formato.diaISO(hasta)
        if h < d { error = "La vuelta tiene que ser después de la salida."; return }
        error = nil
        guardando = true
        defer { guardando = false }
        let usuario = estado.esDuenio ? (quien.isEmpty ? yo : quien) : yo
        do {
            let l: Licencia = try await estado.api.enviar("POST", "/v1/licencias", Cuerpo(usuarioId: usuario, tipo: tipo, desde: d, hasta: h))
            await alCambiar()
            estado.version += 1
            let quienTexto = l.usuarioId == yo ? "Quedaste" : "\((l.usuarioNombre ?? "").split(separator: " ").first.map(String.init) ?? "") queda"
            estado.avisar("\(quienTexto) \((Self.nombre[l.tipo ?? ""] ?? "De licencia").lowercased()) hasta el \(Relativa.corta(l.hasta))") {
                Task {
                    do { try await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)"); estado.version += 1 } catch { estado.avisar("No se guardó", ok: false) }
                }
            }
            cerrar()
        } catch let e as ErrorApi { error = e.detalle.isEmpty ? e.titulo : e.detalle } catch { estado.avisar(error) }
    }

    private func quitar(_ l: Licencia) async {
        quitadas.insert(l.id)
        do {
            try await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)")
            estado.version += 1
            estado.avisar("Quitaste la licencia de \(l.usuarioId == yo ? "vos" : ((l.usuarioNombre ?? "").split(separator: " ").first.map(String.init) ?? ""))") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/licencias", Cuerpo(usuarioId: l.usuarioId, tipo: l.tipo ?? "licencia", desde: l.desde, hasta: l.hasta, nota: l.nota))
                        estado.version += 1
                    } catch { estado.avisar("No se guardó", ok: false) }
                    quitadas.remove(l.id)
                }
            }
        } catch {
            quitadas.remove(l.id)
            estado.avisar(error)
        }
    }
}

// MARK: - Cartera de un agente

/// «Ver cartera» de un agente: sus propiedades (GET /v1/propiedades?agente=).
struct ACarteraAgente: Hashable { var usuario: String; var nombre: String }

struct CarteraAgente: View {
    @Environment(Estado.self) private var estado
    var usuario: String
    var nombre: String
    @State private var props: [Propiedad]?
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let props {
                    if props.isEmpty {
                        EstadoVacio(icono: "house", titulo: "Sin propiedades asignadas").padding(.top, 50)
                    }
                    ForEach(props) { p in
                        Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                            HStack(spacing: 12) {
                                Foto(url: p.miniatura).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.precioTexto).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(p.nombre).estilo(.footnote).foregroundStyle(C.texto).lineLimit(1)
                                    Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).tarjeta()
                        }
                        .buttonStyle(Presionable())
                    }
                } else if let error {
                    EstadoError(que: "la cartera", error: error) { Task { await cargar() } }.padding(.top, 40)
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .background(FondoApp())
        .pantallaApilada("Cartera de \(nombre.split(separator: " ").first.map(String.init) ?? nombre)")
        .refreshable { await cargar() }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        do {
            props = try await estado.api.todas("/v1/propiedades", query: [.init(name: "agente", value: usuario)])
            error = nil
        } catch let e as ErrorApi { if props == nil { error = e } } catch {}
    }
}
