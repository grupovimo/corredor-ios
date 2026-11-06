import SwiftUI

/// Lo que se ve del link de una invitación antes de aceptarla (GET /v1/invitaciones/vista?token=).
struct VistaInvitacion: Decodable, Equatable {
    var inmobiliaria: String
    var invita: String?
    var rol: String
    var email: String
    var venceEn: Date
}

/// El link de una invitación (07 · 4C, como /invitacion/<token> de la web): quién invita, a qué
/// inmobiliaria, con qué rol y qué va a ver, a qué mail es y cuándo vence. Abrirla no la consume: se
/// acepta con el botón. «No soy yo» sale y vuelve a entrar con la cuenta invitada, sin perderla.
struct VerInvitacion: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var token: String
    @State private var vista: VistaInvitacion?
    @State private var errorCarga: String?
    @State private var error: String?
    @State private var enviando = false
    @State private var pegando = false

    /// Qué ve cada rol (lo que dice la invitación antes de aceptar).
    static func queVe(_ rol: String, invita: String) -> String {
        switch rol {
        case "duenio": return "Vas a ver toda la inmobiliaria: la cartera, el equipo, las cobranzas y la configuración."
        case "lector": return "Vas a poder mirar la cartera y la agenda, sin cambiar nada."
        default: return "Vas a ver tu cartera y lo que no tiene dueño. Las cobranzas y la configuración las maneja \(invita)."
        }
    }

    static func tokenValido(_ t: String) -> Bool {
        t.range(of: "^[A-Za-z0-9_-]{20,100}$", options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let v = vista { contenido(v) }
                else if let errorCarga { fallo(errorCarga) }
                else { EsqueletoFilas(filas: 3) }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(FondoApp())
        .navigationTitle("Invitación")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if estado.invitacionAbierta != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrarTodo() } }
            }
        }
        .task { await cargar() }
        .navigationDestination(isPresented: $pegando) { PegarInvitacion() }
    }

    @ViewBuilder
    private func contenido(_ v: VistaInvitacion) -> some View {
        let quien = v.invita?.nonEmpty ?? "Alguien del equipo"
        let primero = quien.split(separator: " ").first.map(String.init) ?? quien
        HStack(spacing: -10) {
            Text(Formato.iniciales(quien)).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.oro)
                .frame(width: 60, height: 60).background(C.verde700, in: Circle())
                .overlay(Circle().stroke(C.fondo, lineWidth: 3))
            Text(String(v.inmobiliaria.prefix(1)).uppercased()).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.texto)
                .frame(width: 60, height: 60).background(C.hundida, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.fondo, lineWidth: 3))
        }
        .accessibilityHidden(true)
        Text(Formato.sinViudas("\(quien) te invitó a \(v.inmobiliaria)")).estilo(.titulo).foregroundStyle(C.texto)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.text.rectangle").foregroundStyle(C.accion).frame(width: 24)
                (Text("Rol: ") + Text(ElegirInmobiliaria.rol(v.rol)).bold()).estilo(.body16).foregroundStyle(C.texto)
            }
            .padding(14)
            Rectangle().fill(C.linea).frame(height: 0.5)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye").foregroundStyle(C.accion).frame(width: 24)
                Text(Formato.sinViudas(Self.queVe(v.rol, invita: primero))).estilo(.subhead).foregroundStyle(C.texto)
            }
            .padding(14)
        }
        .tarjeta()
        HStack(spacing: 4) {
            Text("Entrás como \(estado.usuario?.email ?? "") ·").estilo(.footnote).foregroundStyle(C.texto2)
            Button("no soy yo") { Task { await estado.otraCuenta(invitacion: token) } }
                .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
        }
        if (estado.usuario?.email ?? "").lowercased() != v.email.lowercased() {
            (Text("La invitación es para ") + Text(v.email).bold() + Text(". Si es otra cuenta tuya, entrá con esa."))
                .estilo(.footnote).foregroundStyle(C.avisoTinta)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(C.avisoFondo, in: .rect(cornerRadius: 14, style: .continuous))
        }
        if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
        Button(enviando ? "Entrando…" : "Aceptar y entrar") { aceptar() }
            .buttonStyle(BotonPrincipal()).disabled(enviando)
        Text("La invitación vence el \(Self.diaMes(v.venceEn)).").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func fallo(_ texto: String) -> some View {
        IconoTono(icono: "link.badge.plus", tono: .rojo, tam: 56)
        Text("No pudimos abrir la invitación").estilo(.titulo).foregroundStyle(C.texto)
        Text(Formato.sinViudas(texto)).estilo(.subhead).foregroundStyle(C.texto2)
        Button("Pegar otro link") { pegando = true }.buttonStyle(BotonPrincipal())
        Button("Ir a Corredor") { cerrarTodo() }.buttonStyle(BotonSecundario())
    }

    /// «12/11» (día y mes, como la web).
    static func diaMes(_ f: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: f)
        return String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
    }

    private func cargar() async {
        guard Self.tokenValido(token) else {
            errorCarga = "El link de la invitación no es válido. Pedile a quien te invitó que te mande otro."
            return
        }
        do {
            vista = try await estado.api.get("/v1/invitaciones/vista", query: [.init(name: "token", value: token)])
            errorCarga = nil
        } catch let e as ErrorApi where e.estado > 0 && e.estado < 500 {
            errorCarga = e.detalle.isEmpty ? e.titulo : e.detalle
        } catch let e as ErrorApi {
            errorCarga = e.detalle
        } catch {
            errorCarga = "Algo salió mal. Probá de nuevo."
        }
    }

    private func aceptar() {
        error = nil
        enviando = true
        Task {
            defer { enviando = false }
            do {
                try await estado.aceptarInvitacion(token)
                cerrarTodo()
                // Quien se suma a un equipo pasa por la bienvenida antes del Inicio (como la web), cuando
                // ya se cerró esta hoja (dos presentaciones juntas, SwiftUI deja de mostrar la segunda).
                try? await Task.sleep(for: .milliseconds(700))
                estado.bienvenidaAbierta = true
            } catch let e as ErrorApi {
                error = e.detalle.isEmpty ? e.titulo : e.detalle
            } catch {
                self.error = "Algo salió mal. Probá de nuevo."
            }
        }
    }

    /// En la hoja de un link, la cierra; apilada (desde «Pegar el link»), vuelve.
    private func cerrarTodo() {
        if estado.invitacionAbierta != nil { estado.invitacionAbierta = nil } else { cerrar() }
    }
}

/// «Aceptar una invitación» (como /invitaciones de la web): pegar el link que llegó por mail. Muestra
/// de qué inmobiliaria es antes de entrar. Sirve con o sin inmobiliaria.
struct PegarInvitacion: View {
    @Environment(\.dismiss) private var cerrar
    @State private var link = ""
    @State private var error: String?
    @State private var token: String?

    /// El token del link (`…/invitacion/<token>`) o el token solo.
    static func token(de link: String) -> String? {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = l.range(of: "(?:^|/invitacion/)([A-Za-z0-9_-]{20,100})/?(?:[?#].*)?$", options: .regularExpression) else { return nil }
        var t = String(l[r])
        if let i = t.range(of: "/invitacion/") { t = String(t[i.upperBound...]) }
        if let i = t.firstIndex(where: { $0 == "?" || $0 == "#" }) { t = String(t[..<i]) }
        if t.hasSuffix("/") { t.removeLast() }
        return VerInvitacion.tokenValido(t) ? t : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IconoTono(icono: "envelope", tono: .verde, tam: 56)
                Text("Aceptar una invitación").estilo(.titulo).foregroundStyle(C.texto)
                Text(Formato.sinViudas("Pegá el link que te llegó por mail. Te mostramos de qué inmobiliaria es antes de entrar."))
                    .estilo(.subhead).foregroundStyle(C.texto2)
                HStack(spacing: 8) {
                    TextField("corredor.com.ar/invitacion/…", text: $link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .onSubmit { ver() }
                    PasteButton(payloadType: String.self) { t in
                        if let x = t.first { link = x; ver() }
                    }
                    .labelStyle(.iconOnly).buttonBorderShape(.capsule)
                }
                .campoCorredor()
                .overlay(RoundedRectangle(cornerRadius: M.rControl, style: .continuous).strokeBorder(error == nil ? .clear : C.error))
                if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
                Button("Ver la invitación") { ver() }.buttonStyle(BotonPrincipal()).disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Volver a Corredor") { cerrar() }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(FondoApp())
        .navigationTitle("Invitación")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $token) { t in VerInvitacion(token: t) }
    }

    private func ver() {
        guard let t = Self.token(de: link) else {
            error = "Ese link no parece de una invitación. Copialo entero del mail."
            return
        }
        error = nil
        token = t
    }
}
