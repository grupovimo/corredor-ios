import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Corredor en tu IA

/// 43b Corredor en tu IA: el dueño la habilita y elige lo opcional (agendar, mover); todos ven la
/// dirección para pegar en su asistente, las conexiones (cada uno las suyas, el dueño todas) con
/// «Desconectar», lo que hizo la IA hoy y qué se le puede pedir.
struct CorredorEnTuIA: View {
    @Environment(Estado.self) private var estado
    @State private var conexiones: [Conexion] = []
    @State private var hoy: [AccionIA] = []
    @State private var ajustes: Ajustes?
    @State private var error: ErrorApi?
    @State private var sacando: Set<String> = []

    /// `GET /v1/ia/ajustes`: lo que eligió la dueña, el link para pegar y el aviso de la Ley 25.326 (texto).
    struct Ajustes: Codable { var habilitado: Bool?; var agendar: Bool?; var mover: Bool?; var url: String?; var aviso: String? }
    /// `GET /v1/ia/conexiones`: de quién es, con qué asistente y qué permisos le dio.
    struct Conexion: Codable, Identifiable {
        var id: String
        var usuarioId: String?
        var personaNombre: String?
        var rol: String?
        var cliente: String?
        var permisos: [String]?
        var creadaEn: Date?
        var usadaEn: Date?
    }
    /// `GET /v1/ia/registro` (mcp.Accion): una entrada de lo que hizo la IA.
    struct AccionIA: Codable, Identifiable {
        var id: Int
        var personaNombre: String?
        var cliente: String?
        var herramienta: String?
        var resultado: String?
        var detalle: String?
        var creadoEn: Date
    }

    static let pedidos = [
        "«¿Quién busca 3 ambientes en Belgrano hasta 180 mil y todavía no vio Mendoza 2350?»",
        "«Resumime cómo vino octubre para mandárselo a mi socio.»",
        "«Escribí la descripción de Soler 4120 con lo que anoté en la visita.»",
        "«¿Qué inquilinos deben más de un mes en el consorcio de Cabildo?»",
    ]

    private var duenio: Bool { estado.esDuenio }
    private var habilitado: Bool { ajustes?.habilitado ?? false }

    var body: some View {
        Group {
            if let ajustes { contenido(ajustes) } else if let error {
                EstadoError(que: "Corredor en tu IA", error: error) { Task { await cargar() } }.frame(maxHeight: .infinity).background(FondoApp())
            } else {
                EsqueletoFilas(filas: 6).padding(16).frame(maxHeight: .infinity, alignment: .top).background(FondoApp())
            }
        }
        .pantallaApilada("Corredor en tu IA")
        .task(id: estado.version) { await cargar() }
    }

    @ViewBuilder
    private func contenido(_ a: Ajustes) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conectá Corredor a tu IA").estilo(.titulo3).foregroundStyle(C.texto)
                    Text(Formato.sinViudas("Tu asistente pasa a saber de tus propiedades, contactos, contratos y cobros.")).estilo(.footnote).foregroundStyle(C.texto2)
                }
                .listRowBackground(Color.clear)
            }
            Section { habilitar }
            pasos(a)
            if let aviso = a.aviso?.nonEmpty {
                Section {
                    Label { Text(Formato.sinViudas(aviso)).estilo(.footnote).foregroundStyle(C.texto2) } icon: { Image(systemName: "shield").foregroundStyle(C.azulTinta) }
                }
            }
            conectados
            registro
            Section("Qué le podés pedir") {
                ForEach(Self.pedidos, id: \.self) { p in Text(p).estilo(.subhead).foregroundStyle(C.texto) }
                Text(Formato.sinViudas("Las respuestas usan los datos de Corredor en ese momento; si algo no está cargado, la IA lo dice en vez de inventarlo."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            Section { Button("Revisión de la IA") { estado.abrir(ASeccion(clave: "revision")) } }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .refreshable { await cargar() }
    }

    private var habilitar: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: habilitado ? "checkmark.circle.fill" : "power").font(.system(size: 20))
                .foregroundStyle(habilitado ? C.okTinta : C.texto2)
            VStack(alignment: .leading, spacing: 2) {
                Text(habilitado ? "Habilitada para tu inmobiliaria" : "Apagada para tu inmobiliaria").estilo(.filaLista).foregroundStyle(C.texto)
                Text(Formato.sinViudas(habilitado ? "Cada persona conecta su asistente con su propia cuenta y ve sólo lo que su rol permite."
                                       : duenio ? "Prendela para que tu equipo pueda conectar su asistente." : "La prende el dueño o la dueña de la inmobiliaria."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
            Toggle("Habilitar Corredor en tu IA", isOn: bind(\.habilitado) { $0 ? "Corredor en tu IA, habilitada" : "Corredor en tu IA, apagada" })
                .labelsHidden().tint(C.ok).disabled(!duenio)
        }
    }

    @ViewBuilder
    private func pasos(_ a: Ajustes) -> some View {
        Section {
            paso(1, "Copiá la dirección de tu servidor")
            if let u = a.url {
                HStack {
                    Image(systemName: "server.rack").foregroundStyle(C.okTinta)
                    Text(u).font(.footnote.monospaced()).foregroundStyle(C.texto).lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = u
                        estado.avisar("Dirección copiada. Pegala en tu asistente.")
                    } label: { Label("Copiar", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless).disabled(!habilitado)
                }
            }
            paso(2, "Pegala en tu asistente como «conector» o «servidor MCP»")
            Text(Formato.sinViudas("Te va a pedir que entres a Corredor y autorices. Usás tu cuenta de siempre: Google, Apple o mail."))
                .estilo(.footnote).foregroundStyle(C.texto2)
            paso(3, "Elegí qué puede hacer")
            permiso("eye", C.okTinta, "Leer cartera, contactos, agenda y contratos", "sólo lo que tu rol ve", prendido: .constant(true), bloqueado: true)
            permiso("square.and.pencil", C.okTinta, "Armar borradores", "mensajes, propiedades, notas · vos los revisás y mandás", prendido: .constant(true), bloqueado: true)
            permiso("calendar", C.oroTinta, "Agendar visitas", "con deshacer, como si lo hicieras vos",
                    prendido: bind(\.agendar) { $0 ? "La IA puede agendar visitas" : "La IA ya no agenda visitas" }, bloqueado: !duenio || !habilitado)
            permiso("rectangle.split.3x1", C.oroTinta, "Mover operaciones del tablero", "con deshacer, como si lo hicieras vos",
                    prendido: bind(\.mover) { $0 ? "La IA puede mover operaciones" : "La IA ya no mueve operaciones" }, bloqueado: !duenio || !habilitado)
            HStack(alignment: .top, spacing: 12) {
                IconoFila(icono: "lock", color: C.texto2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mandar mensajes, cobrar, liquidar, borrar").estilo(.filaLista).foregroundStyle(C.texto)
                    Text("nunca desde la IA: siempre lo confirma una persona en Corredor").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            if !duenio {
                Text(Formato.sinViudas("Lo opcional lo elige el dueño o la dueña. Al conectar, vos elegís qué le das a tu asistente."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
        }
        .opacity(habilitado ? 1 : 0.6)
    }

    private func paso(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(n == 3 ? C.accion : C.sobreAccion)
                .frame(width: 24, height: 24).background(n == 3 ? Color.clear : C.accion, in: Circle())
                .overlay(Circle().strokeBorder(C.accion, lineWidth: n == 3 ? 1.5 : 0))
            Text(t).estilo(.filaLista).foregroundStyle(C.texto)
        }
    }

    private func permiso(_ icono: String, _ color: Color, _ t: String, _ d: String, prendido: Binding<Bool>, bloqueado: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconoFila(icono: icono, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                Text(d).estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer(minLength: 0)
            Toggle(t, isOn: prendido).labelsHidden().tint(C.ok).disabled(bloqueado)
        }
    }

    // MARK: Conectados y registro

    private var conectados: some View {
        let personas = Set(conexiones.compactMap(\.usuarioId)).count
        return Section {
            if conexiones.isEmpty {
                Text(Formato.sinViudas("Cuando alguien conecte su asistente, aparece acá con lo que le dio y cuándo lo usó.")).estilo(.footnote).foregroundStyle(C.texto2)
            }
            ForEach(conexiones) { c in
                HStack(spacing: 12) {
                    AvatarPersona(nombre: c.personaNombre ?? "", tam: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Self.primerNombre(c.personaNombre)) · \(c.cliente ?? "IA")\(c.rol == "lector" ? " (lector)" : "")").estilo(.filaLista).foregroundStyle(C.texto)
                        Text(Self.detalle(c)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer(minLength: 0)
                    Button("Desconectar") { Task { await desconectar(c) } }
                        .buttonStyle(.borderless).foregroundStyle(C.errorTinta).disabled(sacando.contains(c.id))
                }
            }
        } header: {
            HStack { Text("Conectados"); Spacer(); Text(personas > 0 ? Formato.cantidad(personas, "persona", "personas") : "nadie todavía") }
        }
    }

    private var registro: some View {
        Section {
            if hoy.isEmpty {
                Text(Formato.sinViudas("Hoy no la usó nadie. Todo lo que haga queda acá y en Actividad.")).estilo(.footnote).foregroundStyle(C.texto2)
            }
            ForEach(hoy) { x in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Formato.horaDe(x.creadoEn)).font(.footnote.monospacedDigit()).foregroundStyle(C.texto3)
                    (Text(x.detalle ?? x.herramienta ?? "") + Text(x.personaNombre.map { " · \(Self.primerNombre($0))" } ?? "").bold())
                        .estilo(.footnote).foregroundStyle(x.resultado == "ok" ? C.texto : C.errorTinta)
                }
            }
        } header: {
            HStack {
                Text("Lo que hizo la IA hoy")
                Spacer()
                Button("Ver todo") { estado.abrir(ASeccion(clave: "actividad", id: "ia")) }.textCase(nil)
            }
        }
    }

    static func primerNombre(_ s: String?) -> String { s?.split(separator: " ").first.map(String.init) ?? s ?? "" }

    /// «leer + borradores + agendar · usado hoy».
    static func detalle(_ c: Conexion) -> String {
        let permisos = (c.permisos ?? []).joined(separator: " + ")
        let usada: String
        if let u = c.usadaEn {
            usada = Calendar.current.isDateInToday(u) ? "usado hoy" : "usado \(Relativa.de(u))"
        } else { usada = "todavía sin usar" }
        return permisos.isEmpty ? usada : "\(permisos) · \(usada)"
    }

    // MARK: Guardar

    /// Cada interruptor guarda al toque, con «Deshacer» (vuelve a los valores de antes).
    private func bind(_ k: WritableKeyPath<Ajustes, Bool?>, _ texto: @escaping (Bool) -> String) -> Binding<Bool> {
        Binding(get: { ajustes?[keyPath: k] ?? false }, set: { v in
            guard let antes = ajustes else { return }
            var despues = antes
            despues[keyPath: k] = v
            ajustes = despues
            Task { await guardar(despues, antes: antes, texto: texto(v)) }
        })
    }

    private struct Cuerpo: Encodable {
        var habilitado: Bool; var agendar: Bool; var mover: Bool
        init(_ a: Ajustes) { habilitado = a.habilitado ?? false; agendar = a.agendar ?? false; mover = a.mover ?? false }
    }

    private func guardar(_ a: Ajustes, antes: Ajustes, texto: String) async {
        do {
            let nuevos: Ajustes = try await estado.api.enviar("PUT", "/v1/ia/ajustes", Cuerpo(a))
            ajustes = nuevos
            estado.avisar(texto) {
                Task {
                    do {
                        let v: Ajustes = try await estado.api.enviar("PUT", "/v1/ia/ajustes", Cuerpo(antes))
                        ajustes = v
                    } catch { estado.avisar(error) }
                }
            }
        } catch {
            ajustes = antes
            let e = error as? ErrorApi
            estado.avisar("No se guardó · \(e.map { $0.detalle.isEmpty ? $0.titulo : $0.detalle } ?? "Probá de nuevo.")", ok: false)
        }
    }

    private func desconectar(_ c: Conexion) async {
        sacando.insert(c.id)
        defer { sacando.remove(c.id) }
        do {
            try await estado.api.hacer("DELETE", "/v1/ia/conexiones/\(c.id)")
            estado.avisar("Desconectaste \(c.cliente ?? "la IA") de \(Self.primerNombre(c.personaNombre))")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        do {
            let a: Ajustes = try await estado.api.get("/v1/ia/ajustes")
            ajustes = a
            error = nil
        } catch let e as ErrorApi { if ajustes == nil { error = e }; return } catch { return }
        if let l: [Conexion] = try? await estado.api.get("/v1/ia/conexiones") { conexiones = l }
        if let r: [AccionIA] = try? await estado.api.get("/v1/ia/registro", query: [.init(name: "desde", value: Formato.diaISO(Date())), .init(name: "limite", value: "6")]) { hoy = r }
    }
}
