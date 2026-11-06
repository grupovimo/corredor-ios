import SwiftUI

/// El consentimiento de «Corredor en tu IA» (conectar-ia/autorizar de la web): el asistente pide entrar a
/// la inmobiliaria; la persona elige qué le deja hacer y autoriza o cancela. Al decidir, vuelve al
/// asistente con la URL que arma la API. Llega por el link `…/conectar-ia/autorizar?solicitud=sol_…`.
struct AutorizarIA: View {
    @Environment(Estado.self) private var estado
    var solicitud: String
    @State private var fase: Fase = .cargando
    @State private var elegidos: Set<String> = []
    @State private var enviando: String?
    @State private var errorEnvio: String?

    enum Fase { case cargando, lista(Solicitud), ajena, vencida, error(String) }

    /// `GET /v1/ia/solicitudes/{id}` (mcp.Solicitud).
    struct Solicitud: Decodable {
        struct Cliente: Decodable { var nombre: String; var sitio: String?; var logo: String?; var verificado: Bool?; var vuelta: String? }
        struct Inmo: Decodable { var id: String?; var slug: String?; var nombre: String }
        struct Permiso: Decodable, Identifiable { var permiso: String; var titulo: String; var detalle: String; var id: String { permiso } }
        var cliente: Cliente
        var inmobiliaria: Inmo
        var rol: String?
        var habilitada: Bool?
        var pedidos: [String]?
        var permitidos: [String]?
        var permisos: [Permiso]?
        var nunca: String?
        var aviso: String?
    }

    static let iconos: [String: (String, Color)] = [
        "leer": ("eye", C.okTinta), "borradores": ("square.and.pencil", C.okTinta),
        "agendar": ("calendar", C.oroTinta), "mover": ("rectangle.split.3x1", C.oroTinta),
    ]
    static let nombres = ["agendar": "agendar visitas", "mover": "mover operaciones", "borradores": "armar borradores"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cabecera
                switch fase {
                case .cargando: EsqueletoFilas(filas: 5)
                case .lista(let s): lista(s)
                case .ajena:
                    EstadoVacio(icono: "person.crop.circle.badge.xmark", titulo: "Esta cuenta no es de esa inmobiliaria",
                                texto: "Entrá con la cuenta con la que usás Corredor en la inmobiliaria y volvé a conectar desde tu asistente.",
                                accion: ("Entrar con otra cuenta", { Task { await estado.salir() } }))
                case .vencida:
                    EstadoVacio(icono: "timer", titulo: "Esta solicitud venció o ya se usó",
                                texto: "Volvé a conectar desde tu asistente: te trae acá de nuevo.",
                                accion: ("Ir a Corredor", { estado.ir(Ruta(.inicio)) }))
                case .error(let m):
                    EstadoVacio(icono: "icloud.slash", titulo: "No pudimos traer la solicitud", texto: m,
                                accion: ("Reintentar", { Task { await cargar() } }))
                }
            }
            .padding(16)
        }
        .background(FondoApp())
        .pantallaApilada("Conectar tu IA")
        .task { await cargar() }
    }

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image("Simbolo").resizable().scaledToFit().frame(width: 48, height: 48)
                if case .lista(let s) = fase {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(C.texto3)
                    Group {
                        if let l = s.cliente.logo, let u = URL(string: l) {
                            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        } else {
                            Text(String(s.cliente.nombre.prefix(1))).font(Estilo(tamano: 20, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                        }
                    }
                    .frame(width: 48, height: 48).background(C.superficie, in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
            .accessibilityHidden(true)
            if case .lista(let s) = fase {
                Text("\(s.cliente.nombre) quiere conectarse a \(s.inmobiliaria.nombre)").estilo(.titulo3).foregroundStyle(C.texto)
                Text(Formato.sinViudas("Tu asistente pasa a saber de tus propiedades, contactos, contratos y cobros.")).estilo(.subhead).foregroundStyle(C.texto2)
            } else {
                Text("Corredor en tu IA").estilo(.titulo3).foregroundStyle(C.texto)
            }
        }
    }

    @ViewBuilder
    private func lista(_ s: Solicitud) -> some View {
        let habilitada = s.habilitada ?? false
        if !habilitada {
            Label { Text(Formato.sinViudas(s.rol == "duenio" ? "Primero habilitá Corredor en tu IA en Configuración › Integraciones." : "La dueña o el dueño tiene que habilitar Corredor en tu IA en Configuración.")).estilo(.footnote) } icon: { Image(systemName: "lock") }
                .foregroundStyle(C.avisoTinta).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(C.avisoFondo, in: .rect(cornerRadius: 14))
        }
        Text("QUÉ VA A PODER HACER").estilo(.etiqueta).foregroundStyle(C.texto2)
        VStack(spacing: 0) {
            ForEach(s.permisos ?? []) { p in permiso(p) }
            HStack(alignment: .top, spacing: 12) {
                IconoFila(icono: "lock", color: C.texto2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mandar mensajes, cobrar, liquidar, borrar").estilo(.filaLista).foregroundStyle(C.texto)
                    Text((s.nunca ?? "").replacingOccurrences(of: "^[^:]+:\\s*", with: "", options: .regularExpression)).estilo(.footnote).foregroundStyle(C.texto2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .tarjeta()
        let negados = (s.pedidos ?? []).filter { !(s.permitidos ?? []).contains($0) }
        if !negados.isEmpty {
            Text(Formato.sinViudas("También pidió \(negados.map { Self.nombres[$0] ?? $0 }.joined(separator: " y ")): \(s.rol == "duenio" ? "lo habilitás" : "lo habilita la dueña o el dueño") en Configuración."))
                .estilo(.footnote).foregroundStyle(C.texto2)
        }
        if let a = s.aviso?.nonEmpty {
            Label { Text(Formato.sinViudas(a)).estilo(.footnote) } icon: { Image(systemName: "shield") }
                .foregroundStyle(C.azulTinta).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(C.azulFondo, in: .rect(cornerRadius: 14))
        }
        let vuelta = s.cliente.vuelta ?? ""
        Group {
            if s.cliente.verificado != true {
                Text("Este asistente se registró solo: fijate que sea el que agregaste vos. Al autorizar volvés a ") + Text(vuelta).bold() + Text(".")
            } else {
                Text("Al autorizar volvés a ") + Text(vuelta).bold() + Text(". Lo desconectás cuando quieras desde Configuración.")
            }
        }
        .estilo(.footnote).foregroundStyle(C.texto2)
        if let e = errorEnvio { MensajeError(texto: e) }
        VStack(spacing: 8) {
            Button { Task { await decidir("aprobar") } } label: {
                if enviando == "aprobar" { HStack { ProgressView().tint(C.sobreAccion); Text("Conectando…") } } else { Text("Autorizar") }
            }
            .buttonStyle(BotonPrincipal()).disabled(!habilitada || enviando != nil)
            Button { Task { await decidir("rechazar") } } label: { Text("Cancelar") }
                .buttonStyle(BotonTexto()).disabled(enviando != nil)
        }
    }

    private func permiso(_ p: Solicitud.Permiso) -> some View {
        let ic = Self.iconos[p.permiso] ?? Self.iconos["leer"]!
        return HStack(alignment: .top, spacing: 12) {
            IconoFila(icono: ic.0, color: ic.1)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                Text(p.detalle).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
            if p.permiso == "leer" {
                Toggle(p.titulo, isOn: .constant(true)).labelsHidden().tint(C.ok).disabled(true).accessibilityLabel("Siempre")
            } else {
                Toggle(p.titulo, isOn: Binding(get: { elegidos.contains(p.permiso) }, set: { v in if v { elegidos.insert(p.permiso) } else { elegidos.remove(p.permiso) } }))
                    .labelsHidden().tint(C.ok)
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    private func cargar() async {
        guard solicitud.range(of: "^sol_[A-Za-z0-9_-]{10,100}$", options: .regularExpression) != nil else { fase = .vencida; return }
        fase = .cargando
        do {
            let s: Solicitud = try await estado.api.get("/v1/ia/solicitudes/\(solicitud)")
            // Lo opcional arranca prendido si lo pidió el asistente (se puede apagar); «leer» va siempre.
            elegidos = Set((s.permisos ?? []).map(\.permiso).filter { $0 != "leer" })
            fase = .lista(s)
        } catch let e as ErrorApi {
            if e.estado == 403 { fase = .ajena } else if e.estado == 404 || e.estado == 410 { fase = .vencida } else { fase = .error(e.detalle.isEmpty ? "Probá de nuevo en un rato." : e.detalle) }
        } catch { fase = .error("Probá de nuevo en un rato.") }
    }

    private func decidir(_ que: String) async {
        enviando = que
        errorEnvio = nil
        defer { enviando = nil }
        struct Cuerpo: Encodable { var permisos: [String] }
        struct Vuelta: Decodable { var redireccion: String }
        do {
            let v: Vuelta = try await estado.api.enviar("POST", "/v1/ia/solicitudes/\(solicitud)/\(que)", Cuerpo(permisos: que == "aprobar" ? Array(elegidos) : []))
            if let u = URL(string: v.redireccion) { await UIApplication.shared.open(u) }
            estado.ir(Ruta(.inicio))
        } catch let e as ErrorApi {
            errorEnvio = e.codigo == "ia_apagada" ? "La dueña o el dueño tiene que habilitar Corredor en tu IA en Configuración." : (e.detalle.isEmpty ? e.titulo : e.detalle)
        } catch { estado.avisar(error) }
    }
}
