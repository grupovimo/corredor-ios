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

/// 1A–1B Bienvenida: «De la consulta al contrato firmado.», Apple, Google y mail.
struct Entrada: View {
    @Environment(Estado.self) private var estado
    @State private var ocupado = false
    @State private var conMail = false
    @State private var error: String?

    var body: some View {
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
                }
                Spacer()
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
                }
                .disabled(ocupado)
                .overlay { if ocupado { ProgressView().tint(.white) } }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .sheet(isPresented: $conMail) { IngresoMail().presentationDetents([.medium, .large]) }
    }

    private func entrar(_ f: @escaping () async throws -> Void) {
        error = nil
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                try await f()
            } catch let e as Clerk.ErrorClerk where e.codigo == "cancelado" {
            } catch let e as ErrorApi {
                error = e.detalle
            } catch {
                self.error = "No pudimos entrar. Probá de nuevo."
            }
        }
    }
}

/// «Entrar con mail»: el mail y después el código de 6 números (Clerk, sin contraseña).
struct IngresoMail: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var email = ""
    @State private var codigo = ""
    @State private var intento: Clerk.IntentoMail?
    @State private var ocupado = false
    @State private var error: String?
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(intento == nil ? "Entrar con mail" : "Revisá tu mail").estilo(.titulo)
            Text(intento == nil ? "Te mandamos un código para entrar, sin contraseña." : "Escribí el código de 6 números que te mandamos a \(email).")
                .estilo(.subhead).foregroundStyle(C.texto2)
            if intento == nil {
                TextField("tu@mail.com", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .campoCorredor().focused($foco)
            } else {
                TextField("123456", text: $codigo)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                    .font(Estilo(tamano: 28, peso: .bold, relativo: .title).font).tracking(8)
                    .campoCorredor().focused($foco)
                    .onChange(of: codigo) { _, n in if n.count == 6 { enviar() } }
            }
            if let error { Text(error).estilo(.footnote).foregroundStyle(C.error) }
            Button(intento == nil ? "Mandame el código" : "Entrar") { enviar() }
                .buttonStyle(BotonPrincipal())
                .disabled(ocupado || (intento == nil ? !email.contains("@") : codigo.count < 6))
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(C.fondo)
        .onAppear { foco = true }
    }

    private func enviar() {
        error = nil
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                if let i = intento {
                    try await estado.ingresarConCodigo(i, codigo: codigo)
                    cerrar()
                } else {
                    intento = try await estado.pedirCodigo(email: email.trimmingCharacters(in: .whitespaces))
                    foco = true
                }
            } catch let e as Clerk.ErrorClerk {
                error = e.codigo.contains("code") ? "El código no es ese. Revisalo o pedí otro." : "No pudimos mandarte el código. Revisá el mail."
            } catch {
                self.error = "No pudimos entrar. Probá de nuevo."
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

/// 1C «¿Dónde trabajás hoy?»: las inmobiliarias de la persona (y la invitación nueva, si hay).
struct ElegirInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var ocupado: String?
    @State private var nombreNueva = ""
    @State private var creando = false

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
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ponele el nombre con el que te conocen. Después sumás a tu equipo.").estilo(.subhead).foregroundStyle(C.texto2)
                        TextField("Luna Propiedades", text: $nombreNueva).campoCorredor()
                        Button("Crear y entrar") {
                            creando = true
                            Task {
                                do { try await estado.crearInmobiliaria(nombre: nombreNueva) } catch { estado.avisar(error) }
                                creando = false
                            }
                        }
                        .buttonStyle(BotonPrincipal())
                        .disabled(nombreNueva.trimmingCharacters(in: .whitespaces).count < 2 || creando)
                    }
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
        .background(C.fondo.ignoresSafeArea())
    }

    static func rol(_ r: String) -> String {
        switch r {
        case "duenio": return "Dueño"
        case "agente": return "Agente"
        default: return "Lector"
        }
    }
}
