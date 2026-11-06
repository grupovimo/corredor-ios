import SwiftUI

/// Fondo de la entrada, el bloqueo y lo que va sobre verde: 0f3530, el patrón rr al 9 % y el grano
/// claro con el resplandor verde arriba.
struct FondoVerde: View {
    var patron = 0.09
    var body: some View {
        ZStack {
            C.verde800
            Image("Patron").resizable(resizingMode: .tile).opacity(patron)
            RadialGradient(colors: [Color(hex: 0x7FC4AD, alfa: 0.2), Color(hex: 0x0F3530, alfa: 0)],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 320)
            Image("GranoClaro").resizable(resizingMode: .tile)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// 1A–1B Bienvenida: «De la consulta al contrato firmado.», Apple, Google y mail. En modo «Creá tu
/// cuenta» (el link de crear la web) dice que es gratis los primeros 30 días.
struct Entrada: View {
    @Environment(Estado.self) private var estado
    @State private var ocupado = false
    @State private var conMail = false
    @State private var error: String?

    var body: some View {
        @Bindable var estado = estado
        ZStack {
            FondoVerde()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 24) {
                    Image("IconoRedondo").resizable().scaledToFit().frame(width: 112)
                        .clipShape(.rect(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
                        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white.opacity(0.05)).padding(-8))
                        .accessibilityLabel("Corredor")
                    (Text("De la consulta al contrato ") + Text("firmado.").foregroundColor(C.oro))
                        .font(Estilo(tamano: 36, peso: .extrabold, relativo: .largeTitle).font)
                        .tracking(-36 * 0.045)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                    if estado.ingresoAlta {
                        VStack(spacing: 4) {
                            Text("Creá tu cuenta").font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(.white)
                            Text("Gratis los primeros 30 días. Sin tarjeta.").estilo(.subhead).foregroundStyle(Color(hex: 0xCFE0D8))
                        }
                    }
                }
                Spacer()
                botones
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $conMail) { IngresoMail().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $estado.recuperarAbierto) { RecuperarAcceso(email: "").presentationDetents([.large]) }
    }

    private var botones: some View {
        VStack(spacing: 10) {
            if let error {
                Text(error).estilo(.footnote).foregroundStyle(Color(hex: 0xF29B92)).multilineTextAlignment(.center)
            }
            Button { entrar { try await estado.ingresarConApple() } } label: {
                HStack(spacing: 8) {
                    Image("LogoApple").resizable().scaledToFit().frame(height: 20)
                    Text("Continuar con Apple").font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: .rect(cornerRadius: 15, style: .continuous))
            }
            Button { entrar { try await estado.ingresarConGoogle() } } label: {
                HStack(spacing: 10) {
                    Image("LogoGoogle").resizable().scaledToFit().frame(height: 15)
                        .frame(width: 24, height: 24).background(.white, in: Circle())
                    Text("Continuar con Google").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.28)))
            }
            Button("Entrar con mail") { conMail = true }
                .font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font)
                .foregroundStyle(Color(hex: 0xCFE0D8))
                .frame(minHeight: 48)
            Text(Formato.sinViudas("¿Te invitaron? Abrí el link del mail en este teléfono y entrás directo a tu inmobiliaria."))
                .estilo(.footnote).foregroundStyle(Color(hex: 0xA9C0B7))
                .multilineTextAlignment(.center)
            PieIngreso(alta: estado.ingresoAlta) { estado.ingresoAlta = false }
                .padding(.top, 6)
        }
        .disabled(ocupado)
        .overlay { if ocupado { ProgressView().tint(.white) } }
    }

    private func entrar(_ f: @escaping () async throws -> Void) {
        error = nil
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                try await f()
            } catch {
                self.error = Self.mensaje(error, proveedor: true)
            }
        }
    }

    /// El error del ingreso dicho en palabras (los mismos mensajes que la web: nunca el código).
    static func mensaje(_ e: Error, proveedor: Bool = false) -> String {
        let api: [String: String] = [
            "cancelado": "Cancelaste el ingreso. Probá de nuevo cuando quieras.",
            "email_sin_verificar": "Tu cuenta no tiene un mail verificado.",
            "demasiados_intentos": "Hubo demasiados intentos. Probá de nuevo en unos minutos.",
            "too_many_requests": "Hubo demasiados intentos. Probá de nuevo en unos minutos.",
            "sin_sesion": "El ingreso venció o no es válido. Probá de nuevo.",
            "sin_clerk": "El ingreso no está disponible en este momento.",
            "sin_clave": "El ingreso no está disponible en este momento.",
        ]
        if let c = e as? Clerk.ErrorClerk {
            if let m = api[c.codigo] { return m }
            return proveedor ? "No pudimos conectar con Google o Apple. Probá de nuevo." : ClerkMail.mensaje(c.codigo)
        }
        if let a = e as? ErrorApi {
            if a.sinConexion { return a.detalle }
            return api[a.codigo] ?? "No pudimos completar el ingreso. Probá de nuevo."
        }
        return "No pudimos completar el ingreso. Probá de nuevo."
    }
}

/// «Al seguir aceptás los Términos y la Política de privacidad.» y, en modo alta, «¿Ya tenés cuenta? Ingresá».
struct PieIngreso: View {
    var alta: Bool
    var claro = true
    var ingresa: () -> Void = {}

    private var texto: AttributedString {
        let web = Api.web()
        let md = "Al seguir aceptás los [Términos](\(web.appendingPathComponent("terminos").absoluteString)) y la [Política de privacidad](\(web.appendingPathComponent("privacidad").absoluteString))."
        return (try? AttributedString(markdown: md)) ?? AttributedString("Al seguir aceptás los Términos y la Política de privacidad.")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(texto).estilo(.footnote).foregroundStyle(claro ? Color(hex: 0xA9C0B7) : C.texto3)
                .tint(claro ? C.oro : C.accion)
                .multilineTextAlignment(.center)
            if alta {
                HStack(spacing: 4) {
                    Text("¿Ya tenés cuenta?").estilo(.footnote).foregroundStyle(claro ? Color(hex: 0xA9C0B7) : C.texto3)
                    Button("Ingresá", action: ingresa).font(Estilo.footnoteFuerte.font).foregroundStyle(claro ? C.oro : C.accion)
                }
            } else {
                Text(Formato.sinViudas("Si es tu primera vez, se crea tu cuenta.")).estilo(.footnote).foregroundStyle(claro ? Color(hex: 0xA9C0B7) : C.texto3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// «Entrar con mail» (como la web): según la cuenta, la contraseña o un código de 6 números; si es la
/// primera vez se crea la cuenta (con código, y la contraseña si la pide). «¿No podés entrar?» lleva a
/// recuperar el acceso.
struct IngresoMail: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var email = ""
    @State private var clave = ""
    @State private var codigo = ""
    @State private var paso: ClerkMail.Paso?
    @State private var flujo = ClerkMail.configurado()
    @State private var ocupado = false
    @State private var error: String?
    @State private var recuperando = false
    @FocusState private var foco: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if paso == nil { pasoMail } else { volver; pasoActual }
                if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
                if flujo == nil {
                    Text("El ingreso no está disponible en este momento. Probá de nuevo en un rato.").estilo(.footnote).foregroundStyle(C.error)
                }
            }
            .padding(20)
        }
        .background(C.fondo)
        .onAppear { foco = true }
        .sheet(isPresented: $recuperando) { RecuperarAcceso(email: email).presentationDetents([.large]) }
    }

    private var pasoMail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(estado.ingresoAlta ? "Creá tu cuenta" : "Entrar con mail").estilo(.titulo)
            Text(estado.ingresoAlta ? "Gratis los primeros 30 días. Sin tarjeta." : "Si es tu primera vez, se crea tu cuenta.")
                .estilo(.subhead).foregroundStyle(C.texto2)
            TextField("tu@mail.com", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .campoCorredor().focused($foco)
                .onSubmit { seguir() }
            Button(ocupado ? "Un segundo…" : "Seguir") { seguir() }
                .buttonStyle(BotonPrincipal())
                .disabled(ocupado || !email.contains("@") || flujo == nil)
            PieIngreso(alta: estado.ingresoAlta, claro: false) { estado.ingresoAlta = false }
        }
    }

    private var volver: some View {
        Button { otroMail() } label: {
            Label(email, systemImage: "arrow.left").font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
        }
    }

    @ViewBuilder
    private var pasoActual: some View {
        switch paso {
        case .clave:
            Text("Tu contraseña").estilo(.filaLista).foregroundStyle(C.texto)
            SecureField("", text: $clave).textContentType(.password).campoCorredor().focused($foco).onSubmit { seguir() }
            Button(ocupado ? "Entrando…" : "Entrar") { seguir() }.buttonStyle(BotonPrincipal()).disabled(ocupado || clave.isEmpty)
            Button("¿No podés entrar?") { recuperando = true }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                .frame(maxWidth: .infinity)
        case .codigo(let alta):
            Text("Te mandamos un código a \(email). \(alta ? "Con él creamos tu cuenta." : "Escribilo para entrar.")")
                .estilo(.subhead).foregroundStyle(C.texto2)
            Text("Código").estilo(.filaLista).foregroundStyle(C.texto)
            TextField("123456", text: $codigo)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .font(Estilo(tamano: 28, peso: .bold, relativo: .title).font).tracking(8)
                .campoCorredor().focused($foco)
                .onChange(of: codigo) { _, n in
                    if n.count > 6 { codigo = String(n.prefix(6)) }
                    if n.count == 6, !ocupado { seguir() }
                }
            Button(ocupado ? "Revisando…" : alta ? "Crear mi cuenta" : "Entrar") { seguir() }
                .buttonStyle(BotonPrincipal()).disabled(ocupado || codigo.count < 6)
        case .claveNueva:
            Text("Elegí una contraseña para entrar con tu mail.").estilo(.subhead).foregroundStyle(C.texto2)
            Text("Contraseña").estilo(.filaLista).foregroundStyle(C.texto)
            SecureField("", text: $clave).textContentType(.newPassword).campoCorredor().focused($foco)
            RequisitosClave(clave: clave)
            Button("Guardar y entrar") { seguir() }.buttonStyle(BotonPrincipal()).disabled(ocupado)
        default:
            EmptyView()
        }
    }

    private func otroMail() {
        paso = nil
        clave = ""; codigo = ""; error = nil
        flujo = ClerkMail.configurado()
    }

    private func seguir() {
        guard let flujo, !ocupado else { return }
        if case .claveNueva = paso {
            let r = ClerkMail.requisitos(clave)
            if !r.largo || !r.comun { error = "La contraseña todavía no cumple los requisitos."; return }
        }
        error = nil
        ocupado = true
        let actual = paso
        let mail = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { ocupado = false }
            do {
                let sig: ClerkMail.Paso
                switch actual {
                case nil: sig = try await flujo.empezar(email: mail)
                case .clave: sig = try await flujo.entrarConClave(clave)
                case .codigo: sig = try await flujo.confirmarCodigo(codigo)
                case .claveNueva: sig = try await flujo.guardarClave(clave)
                case .listo: return
                }
                if case .listo(let token) = sig {
                    try await estado.ingresarConJWT(token)
                    cerrar()
                } else {
                    if case .claveNueva = sig { clave = "" }
                    paso = sig
                    foco = true
                }
            } catch {
                self.error = Entrada.mensaje(error)
            }
        }
    }
}

/// Los requisitos de la contraseña nueva, que se tildan solos mientras se escribe (07 · 2c).
struct RequisitosClave: View {
    var clave: String
    var distinta = false

    var body: some View {
        let r = ClerkMail.requisitos(clave)
        VStack(alignment: .leading, spacing: 6) {
            fila(r.largo, "10 caracteres o más")
            fila(r.comun, "No es una de las más usadas")
            if distinta { fila(false, "Distinta a la anterior") }
        }
        .accessibilityElement(children: .combine)
    }

    private func fila(_ ok: Bool, _ texto: String) -> some View {
        Label {
            Text(texto).estilo(.footnote).foregroundStyle(ok ? C.ok : C.texto2)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? C.ok : C.texto3)
        }
    }
}

/// Recuperar el acceso (07 · 2b) y la contraseña nueva (2c), con Clerk: un código por mail, con él la
/// contraseña nueva, se cierran las otras sesiones y se entra. Si el mail no tiene cuenta, dice lo
/// mismo (no se revela quién está registrado).
struct RecuperarAcceso: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var email: String
    @State private var codigo = ""
    @State private var clave = ""
    @State private var ver = false
    @State private var paso = "mail"
    @State private var enviado = false
    @State private var enviando = false
    @State private var error: String?
    @State private var flujo = ClerkMail.configurado()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if paso == "nueva" { nueva } else { pedir }
            }
            .padding(20)
        }
        .background(C.fondo)
    }

    @ViewBuilder
    private var pedir: some View {
        IconoTono(icono: "key", tono: .oro, tam: 56)
        Text("¿No podés entrar?").estilo(.titulo).foregroundStyle(C.texto)
        Text(Formato.sinViudas("Si entrás con Google o Apple, usá ese botón: no necesitás contraseña. Si usás mail, te mandamos un código para crear una nueva."))
            .estilo(.subhead).foregroundStyle(C.texto2)
        if paso == "mail" {
            TextField("tu@mail.com", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .campoCorredor()
            Button(enviando ? "Mandando…" : "Mandarme el código") { enviar() }
                .buttonStyle(BotonPrincipal()).disabled(enviando || flujo == nil || !email.contains("@"))
        } else {
            Text("Código que te llegó a \(email)").estilo(.filaLista).foregroundStyle(C.texto)
            TextField("123456", text: $codigo)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .font(Estilo(tamano: 28, peso: .bold, relativo: .title).font).tracking(8)
                .campoCorredor()
                .onChange(of: codigo) { _, n in if n.count > 6 { codigo = String(n.prefix(6)) } }
            Button(enviando ? "Revisando…" : "Seguir") { enviar() }
                .buttonStyle(BotonPrincipal()).disabled(enviando || codigo.count < 6)
        }
        if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
        if enviado {
            Label(Formato.sinViudas("Listo: si ese mail tiene cuenta, te llega un código en un minuto. Revisá también spam."), systemImage: "envelope.open")
                .estilo(.footnote).foregroundStyle(C.texto)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(C.avisoFondo, in: .rect(cornerRadius: 14, style: .continuous))
        }
        Button("Volver a ingresar") { cerrar() }.font(Estilo.subheadFuerte.font).foregroundStyle(C.accion).frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var nueva: some View {
        Text("Elegí una contraseña nueva").estilo(.titulo).foregroundStyle(C.texto)
        HStack(spacing: 8) {
            Group {
                if ver { TextField("", text: $clave) } else { SecureField("", text: $clave) }
            }
            .textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { ver.toggle() } label: {
                Image(systemName: ver ? "eye.slash" : "eye").foregroundStyle(C.texto2).frame(width: 44, height: 44)
            }
            .accessibilityLabel(ver ? "Ocultar la contraseña" : "Ver la contraseña")
        }
        .campoCorredor()
        RequisitosClave(clave: clave, distinta: true)
        if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
        Button(enviando ? "Guardando…" : "Guardar y entrar") { enviar() }.buttonStyle(BotonPrincipal()).disabled(enviando)
        Text("Cerramos las otras sesiones abiertas por seguridad.").estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
    }

    private func enviar() {
        guard let flujo, !enviando else { return }
        if paso == "nueva" {
            let r = ClerkMail.requisitos(clave)
            if !r.largo || !r.comun { error = "La contraseña todavía no cumple los requisitos."; return }
        }
        error = nil
        enviando = true
        Task {
            defer { enviando = false }
            do {
                switch paso {
                case "mail":
                    let hay = try await flujo.pedirRecuperar(email: email.trimmingCharacters(in: .whitespaces))
                    enviado = true
                    if hay { paso = "codigo" }
                case "codigo":
                    let sig = try await flujo.confirmarCodigo(codigo, recuperar: true)
                    if case .claveNueva = sig { paso = "nueva" }
                default:
                    let sig = try await flujo.guardarClave(clave)
                    if case .listo(let token) = sig {
                        try await estado.ingresarConJWT(token)
                        cerrar()
                    }
                }
            } catch {
                self.error = Entrada.mensaje(error)
            }
        }
    }
}

extension View {
    /// Un campo de texto del handoff: superficie, radio 12, borde línea 2, 50 de alto.
    func campoCorredor() -> some View {
        estilo(.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(C.superficie, in: .rect(cornerRadius: M.rControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: M.rControl, style: .continuous).strokeBorder(C.linea2))
    }
}

/// 1C «¿Dónde trabajás hoy?»: las inmobiliarias de la persona. Sin ninguna, crear la suya (con la
/// dirección de la web) o aceptar una invitación pegando el link.
struct ElegirInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var ocupado: String?
    @State private var pegando = false

    private static let colores: [(UInt32, UInt32)] = [(0x1E3A5F, 0xE9DCC3), (0xC9782E, 0xFFFFFF), (0x16443B, 0xF2BB57), (0x6B3FA0, 0xFFFFFF)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hola, \(estado.usuario?.nombre.isEmpty == false ? estado.usuario!.nombre : "")").estilo(.subhead).foregroundStyle(C.texto2)
                    Text(estado.sesion?.inmobiliarias.isEmpty == false ? "¿Dónde trabajás hoy?" : "Creá tu inmobiliaria")
                        .font(Estilo(tamano: 32, peso: .extrabold, relativo: .largeTitle).font).tracking(-32 * 0.035)
                        .foregroundStyle(C.texto)
                }
                if let lista = estado.sesion?.inmobiliarias, !lista.isEmpty {
                    listaInmobiliarias(lista)
                } else {
                    FormCrearInmobiliaria()
                }
                Button { pegando = true } label: {
                    Label("Aceptar una invitación", systemImage: "envelope.open").font(Estilo.subheadFuerte.font).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Text("Cambiás de inmobiliaria cuando quieras desde tu perfil.")
                    .estilo(.footnote).foregroundStyle(C.texto3)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, 8)
                Button("Salir") { Task { await estado.salir() } }.buttonStyle(BotonTexto(color: C.texto2))
            }
            .padding(.horizontal, 16)
            .padding(.top, 64)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(C.fondo.ignoresSafeArea())
        .sheet(isPresented: $pegando) { NavigationStack { PegarInvitacion() }.presentationDetents([.large]) }
    }

    private func listaInmobiliarias(_ lista: [Sesion.Membresia]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, m in
                Button {
                    ocupado = m.id
                    Task {
                        do { try await estado.elegir(m) } catch { estado.avisar(error) }
                        ocupado = nil
                    }
                } label: {
                    HStack(spacing: 12) {
                        let c = Self.colores[i % Self.colores.count]
                        Text(String(m.nombre.prefix(1)).uppercased())
                            .font(Estilo(tamano: 18, peso: .bold, relativo: .headline).font)
                            .foregroundStyle(Color(hex: c.1))
                            .frame(width: 44, height: 44)
                            .background(Color(hex: c.0), in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.nombre).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                            Text(Self.rol(m.rol)).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        if ocupado == m.id { ProgressView() } else { Chevron() }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(minHeight: 68)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
        }
        .tarjeta()
    }

    static func rol(_ r: String) -> String {
        switch r {
        case "duenio": return "Dueño"
        case "agente": return "Agente"
        default: return "Lector"
        }
    }
}

/// Crear la inmobiliaria (07 · 3C, como /empezar de la web): el nombre y la dirección de la web, que
/// se arma mientras se escribe, se puede cambiar y dice si está libre. Abajo, la web de muestra. La
/// persona queda como dueña y la sesión pasa a la nueva (sigue el alta: logo, colores, portada…).
struct FormCrearInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var nombre = ""
    @State private var slugPropio = ""
    @State private var editandoSlug = false
    @State private var disponible = "nada"
    @State private var enviando = false
    @State private var errorNombre: String?
    @State private var errorSlugApi: String?
    @State private var error: String?
    @FocusState private var focoSlug: Bool

    /// La web de las inmobiliarias (corredor.com.ar, sin app./panel./www.).
    static var dominio: String {
        let h = Api.web().host ?? "corredor.com.ar"
        for p in ["app.", "panel.", "www."] where h.hasPrefix(p) { return String(h.dropFirst(p.count)) }
        return h
    }

    /// Como `slugDe` de la web: minúsculas, sin acentos, sin «propiedades»/«inmobiliaria», sólo [a-z0-9].
    static func slugDe(_ nombre: String) -> String {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        var s = n.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
        s = s.replacingOccurrences(of: "propiedades", with: "").replacingOccurrences(of: "inmobiliaria", with: "")
        s = String(s.filter { Self.letraDeSlug($0) && $0 != "-" })
        return !n.isEmpty && !s.isEmpty ? s : "tuinmobiliaria"
    }

    /// a-z, 0-9 y el guion.
    static func letraDeSlug(_ c: Character) -> Bool {
        guard c.isASCII, let a = c.asciiValue else { return false }
        return (a >= 97 && a <= 122) || (a >= 48 && a <= 57) || a == 45
    }

    private var slug: String { slugPropio.isEmpty ? (nombre.trimmingCharacters(in: .whitespaces).isEmpty ? "" : Self.slugDe(nombre)) : slugPropio }
    private var inicial: String { nombre.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "L" }

    private var errorSlug: String? {
        errorSlugApi ?? (disponible == "tomado" ? "Esa dirección ya la usa otra inmobiliaria. Probá con otra."
            : disponible == "invalido" ? "Esa dirección no se puede usar. Probá con otra." : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Cómo se llama tu inmobiliaria?").estilo(.filaLista).foregroundStyle(C.texto)
            TextField("Luna Propiedades", text: $nombre)
                .textContentType(.organizationName)
                .campoCorredor()
                .onChange(of: nombre) { _, n in
                    if n.count > 120 { nombre = String(n.prefix(120)) }
                    errorNombre = nil
                }
            if let errorNombre { Text(errorNombre).estilo(.footnote).foregroundStyle(C.error) }
            web
            logo
            muestra
            if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
            Button { crear() } label: {
                if enviando { Text("Creando…") } else { Label("Seguir: tu logo y tu marca", systemImage: "arrow.right").labelStyle(TextoIcono()) }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(enviando || nombre.trimmingCharacters(in: .whitespaces).isEmpty || disponible == "tomado" || disponible == "invalido")
        }
        .onAppear {
            if nombre.isEmpty, let n = estado.nombreSugerido { nombre = n; estado.nombreSugerido = nil }
        }
        // «Libre»: se pregunta un ratito después de dejar de escribir.
        .task(id: slug) { await mirar(slug) }
    }

    private var web: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tu web").estilo(.filaLista).foregroundStyle(C.texto)
            HStack(spacing: 2) {
                if editandoSlug {
                    TextField("tuinmobiliaria", text: Binding(get: { slug }, set: { v in
                        slugPropio = String(v.lowercased().filter { Self.letraDeSlug($0) }.prefix(48))
                        errorSlugApi = nil
                    }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .font(Estilo.subheadFuerte.font).focused($focoSlug)
                    .onSubmit { editandoSlug = false }
                    .fixedSize()
                } else {
                    Button { editandoSlug = true; focoSlug = true } label: {
                        Text(slug.isEmpty ? "tuinmobiliaria" : slug).font(Estilo.subheadFuerte.font).foregroundStyle(C.texto).underline()
                    }
                    .accessibilityLabel("Cambiar la dirección")
                }
                Text(".\(Self.dominio)").estilo(.subhead).foregroundStyle(C.texto2).lineLimit(1)
                Spacer(minLength: 4)
                if disponible == "libre" { Label("Libre", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(C.ok) }
                else if disponible == "mirando" { ProgressView().controlSize(.small) }
            }
            .campoCorredor()
            .overlay(RoundedRectangle(cornerRadius: M.rControl, style: .continuous).strokeBorder(errorSlug == nil ? .clear : C.error))
            if let e = errorSlug { Text(e).estilo(.footnote).foregroundStyle(C.error) }
            else if disponible == "libre" { Text("Libre. Después podés usar tu dominio propio.").estilo(.footnote).foregroundStyle(C.texto2) }
        }
    }

    private var logo: some View {
        HStack(spacing: 12) {
            Text(inicial).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.oro)
                .frame(width: 48, height: 48).background(C.verde700, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("Logo").estilo(.filaLista).foregroundStyle(C.texto)
                Text("Lo subís en el paso que sigue").estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
    }

    /// La web de muestra (en el celular, chica, debajo).
    private var muestra: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(slug.isEmpty ? "tuinmobiliaria" : slug).\(Self.dominio)")
                .font(Estilo(tamano: 11, peso: .medium, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                .background(C.hundida)
            HStack(spacing: 8) {
                Text(inicial).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.oro)
                    .frame(width: 24, height: 24).background(C.verde700, in: .rect(cornerRadius: 6, style: .continuous))
                Text((nombre.nonEmpty ?? "Tu inmobiliaria").uppercased()).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font)
                    .foregroundStyle(C.texto).lineLimit(1)
            }
            .padding(10)
            LinearGradient(colors: [C.verde700, C.verde800], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 70)
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(C.linea))
        .accessibilityHidden(true)
    }

    private func mirar(_ s: String) async {
        guard !s.isEmpty else { disponible = "nada"; return }
        disponible = "mirando"
        do {
            try await Task.sleep(for: .milliseconds(350))
            struct D: Decodable { var slug: String; var valido: Bool; var libre: Bool }
            let d: D = try await estado.api.get("/v1/inmobiliarias/disponible", query: [.init(name: "slug", value: String(s.prefix(60)))])
            disponible = !d.valido ? "invalido" : d.libre ? "libre" : "tomado"
        } catch is CancellationError {
        } catch {
            // Sin señal o sin respuesta: no se dice nada (la API vuelve a mirar al crear).
            disponible = "nada"
        }
    }

    private func crear() {
        error = nil; errorNombre = nil; errorSlugApi = nil
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { errorNombre = "Poné el nombre de la inmobiliaria."; return }
        enviando = true
        Task {
            defer { enviando = false }
            do {
                try await estado.crearInmobiliaria(nombre: n, slug: slug)
            } catch let e as ErrorApi {
                // El error vuelve al campo, con lo escrito, para no tener que repetirlo.
                if e.codigo == "slug_tomado" { errorSlugApi = e.detalle; disponible = "tomado" }
                else if e.estado == 422 || e.estado == 400 { error = e.detalle.isEmpty ? e.titulo : e.detalle }
                else { estado.avisar(e) }
            } catch { estado.avisar(error) }
        }
    }
}

/// «Crear otra inmobiliaria» (desde «Tus inmobiliarias» del perfil), teniendo ya una.
struct CrearOtraInmobiliaria: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormCrearInmobiliaria()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FondoApp())
        .pantallaApilada("Creá tu inmobiliaria")
    }
}
