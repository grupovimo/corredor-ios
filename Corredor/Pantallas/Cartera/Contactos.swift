import Contacts
import SwiftUI
import UniformTypeIdentifiers

/// GET /v1/contactos/resumen: los números de los filtros de la lista.
struct ResumenContactos: Codable, Hashable {
    struct Etiqueta: Codable, Hashable { var texto: String; var cuenta: Int }
    var total: Int
    var tipos: [String: Int]?
    var esperando: Int?
    var etiquetas: [Etiqueta]?
}

// MARK: - 8A Contactos

/// 8A Contactos, como la lista del panel: lo más reciente arriba, la búsqueda en el servidor
/// (nombre, teléfono o lo que busca), las listas con su número, las etiquetas, los que esperan
/// respuesta arriba con WhatsApp a un toque, y en cada fila la deuda, el «escribió por WhatsApp» o lo
/// que busca, con el «cuándo» de la derecha.
struct Contactos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Contacto]?
    @State private var esperan: [Contacto] = []
    @State private var resumen: ResumenContactos?
    @State private var q = ""
    @State private var filtro = ""
    @State private var etiqueta: String?
    /// Sólo las consultas sin dueño (desde «Tomá una consulta sin dueño» del Inicio).
    @State private var libres: Bool
    @State private var nuevo = false
    @State private var importar = false
    @State private var error: ErrorApi?
    @State private var guardadoEn: Date?

    init(libres: Bool = false) { _libres = State(initialValue: libres) }

    private static let porPagina = 60
    private var filtrado: Bool { !q.isEmpty || etiqueta != nil || libres || !filtro.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let g = guardadoEn { BannerSinConexion(guardado: g).padding(.horizontal, 16) }
                if resumen?.total != 0 { chips }
                contenido
            }
            .padding(.bottom, 30)
        }
        .searchable(text: $q, prompt: "Nombre, teléfono o lo que busca")
        .refreshable { await cargar() }
        .pantallaApilada("Contactos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if estado.escribe {
                Menu {
                    Button { nuevo = true } label: { Label("Nuevo contacto", systemImage: "person.badge.plus") }
                    Button { importar = true } label: { Label("Importar del celular o un Excel", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") } primaryAction: { nuevo = true }
                .accessibilityLabel("Contacto nuevo")
            }
        }
        .task(id: "\(estado.version)-\(q)-\(filtro)-\(etiqueta ?? "")-\(libres)") {
            if !q.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            if Task.isCancelled { return }
            await cargar()
        }
        .sheet(isPresented: $nuevo) { EditarContacto() }
        .sheet(isPresented: $importar) { ImportarContactos().hojaTLW([.medium, .large]) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TextosContacto.listas, id: \.clave) { l in
                    let n = l.clave.isEmpty ? resumen?.total : l.tipos.reduce(0) { $0 + (resumen?.tipos?[$1] ?? 0) }
                    ChipFiltro(texto: l.texto + (n.map { " \(Formato.numero($0))" } ?? ""), activo: filtro == l.clave && etiqueta == nil && !libres) {
                        filtro = l.clave
                        etiqueta = nil
                        libres = false
                    }
                }
                if let e = resumen?.esperando, e > 0 {
                    ChipFiltro(texto: "Sin respuesta \(Formato.numero(e))", activo: filtro == "sin_respuesta" && etiqueta == nil && !libres) { filtro = "sin_respuesta"; etiqueta = nil; libres = false }
                }
                if libres {
                    Button { Haptico.seleccion(); libres = false } label: {
                        Label("Sin dueño", systemImage: "xmark").labelStyle(TextoDespues()).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(C.sobreAccion).padding(.horizontal, 14).frame(height: 36).background(C.accion, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityLabel("Sin dueño. Quitar el filtro")
                    .accessibilityAddTraits(.isSelected)
                }
                ForEach((resumen?.etiquetas ?? []).prefix(8), id: \.texto) { e in
                    Button { Haptico.seleccion(); etiqueta = etiqueta == e.texto ? nil : e.texto } label: {
                        Label("\(e.texto) \(Formato.numero(e.cuenta))", systemImage: "tag").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(etiqueta == e.texto ? C.sobreAccion : C.avisoTinta)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(etiqueta == e.texto ? C.accion : C.avisoFondo, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(etiqueta == e.texto ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var contenido: some View {
        if let lista {
            if resumen?.total == 0 && !filtrado {
                EstadoVacio(icono: "person.2", titulo: "Los contactos llegan solos", texto: "Cada consulta crea el contacto con lo que busca.",
                            accion: estado.escribe ? ("Nuevo contacto", { nuevo = true }) : nil,
                            secundaria: estado.escribe ? ("Importar del celular o un Excel", { importar = true }) : nil)
                    .padding(.top, 40)
            } else if lista.isEmpty && libres && q.isEmpty {
                EstadoVacio(icono: "tray", titulo: "No quedan consultas sin dueño", texto: "Ya las tomó alguien.",
                            accion: ("Ver todos", { filtro = ""; etiqueta = nil; libres = false }))
                    .padding(.top, 30)
            } else if lista.isEmpty {
                EstadoVacio(icono: "magnifyingglass", titulo: "No hay nadie con esa búsqueda", texto: "Probá con el teléfono o un barrio.",
                            accion: ("Ver todos", { q = ""; filtro = ""; etiqueta = nil; libres = false }))
                    .padding(.top, 30)
            } else {
                if !esperan.isEmpty && !filtrado { bloqueEsperan }
                VStack(spacing: 0) {
                    ForEach(Array(lista.enumerated()), id: \.element.id) { i, c in fila(c, primera: i == 0) }
                }
                .tarjeta()
                .padding(.horizontal, 16)
                if lista.count >= Self.porPagina {
                    Text(Formato.sinViudas("Se ven los primeros 60. Buscá para ver al resto.")).estilo(.footnote).foregroundStyle(C.texto3)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
        } else if let error {
            EstadoError(que: "los contactos", error: error) { Task { await cargar() } }.padding(.top, 30)
        } else {
            EsqueletoFilas(filas: 8).padding(.horizontal, 16)
        }
    }

    /// Los que esperan respuesta, arriba y con WhatsApp a un toque.
    private var bloqueEsperan: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Esperan respuesta").estilo(.label).foregroundStyle(C.avisoTinta).padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(Array(esperan.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 12) {
                        Button { estado.abrir(AFichaContacto(id: c.id)) } label: {
                            HStack(spacing: 12) {
                                avatar(c)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text("\(c.propiedad ?? TextosContacto.detalle(c)) · \(TextosContacto.cuando(c).0)").estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        botonWhatsApp(c, lleno: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
            .padding(.horizontal, 16)
            Text("Recientes").estilo(.label).foregroundStyle(C.texto2).padding(.horizontal, 20).padding(.top, 8)
        }
    }

    private func avatar(_ c: Contacto) -> some View {
        let t = Self.tono(c.tipo)
        return Text(Formato.iniciales(c.nombre)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).foregroundStyle(t.tinta)
            .frame(width: 42, height: 42).background(t.fondo, in: Circle())
    }

    private func botonWhatsApp(_ c: Contacto, lleno: Bool) -> some View {
        Button { Task { await Self.abrirChat(c.id, estado: estado) } } label: {
            Image("LogoWhatsApp").renderingMode(.template).resizable().frame(width: 20, height: 20).foregroundStyle(lleno ? .white : C.accion)
                .frame(width: 44, height: 44).background(lleno ? Color(hex: 0x25D366) : C.hundida, in: Circle())
        }
        .accessibilityLabel("WhatsApp a \(c.nombre)")
    }

    private func fila(_ c: Contacto, primera: Bool) -> some View {
        let (cuando, tono) = TextosContacto.cuando(c)
        let detalle = TextosContacto.detalle(c).nonEmpty ?? c.telefono ?? " "
        let debe = TextosContacto.deuda(c) != nil
        return HStack(spacing: 10) {
            Button { estado.abrir(AFichaContacto(id: c.id)) } label: {
                HStack(spacing: 12) {
                    avatar(c)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(c.nombre).font(Estilo(tamano: 16, peso: .semibold, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                            Text(TextosContacto.rol(c.tipo)).estilo(.footnote).foregroundStyle(C.texto3).lineLimit(1)
                        }
                        Text(detalle).estilo(.footnote).foregroundStyle(debe ? C.errorTinta : C.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(cuando).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font)
                        .foregroundStyle(tono == .oro ? C.avisoTinta : tono == .verde ? C.okTinta : C.texto3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            if c.telefono != nil {
                Button { Afuera.llamar(c.telefono) } label: {
                    Image(systemName: "phone.fill").font(.system(size: 16)).foregroundStyle(C.accion).frame(width: 40, height: 40).background(C.hundida, in: Circle())
                }
                .accessibilityLabel("Llamar a \(c.nombre)")
                botonWhatsApp(c, lleno: false)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 54) } }
    }

    static func tono(_ t: String?) -> Tono {
        switch t {
        case "comprador": return .oro
        case "inquilino": return .azul
        case "propietario", "vendedor": return .verde
        case "garante": return .violeta
        default: return .neutro
        }
    }

    /// Abre (o crea) la conversación de WhatsApp con el contacto dentro de Corredor.
    static func abrirChat(_ contacto: String, estado: Estado) async {
        struct Cuerpo: Encodable { var contactoId: String }
        struct Conv: Decodable { var id: String }
        do {
            let x: Conv = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: contacto))
            estado.abrir(AChat(id: x.id))
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        var query: [URLQueryItem] = [.init(name: "limite", value: String(Self.porPagina))]
        if let t = q.nonEmpty { query.append(.init(name: "q", value: String(t.prefix(120)))) }
        if let e = etiqueta { query.append(.init(name: "etiqueta", value: e)) }
        if libres { query.append(.init(name: "agente", value: "libre")) }
        if filtro == "sin_respuesta" { query.append(.init(name: "esperando", value: "si")) }
        else if let l = TextosContacto.listas.first(where: { $0.clave == filtro && !$0.clave.isEmpty }) { query.append(.init(name: "tipo", value: l.tipos.joined(separator: ","))) }
        let clave = filtrado ? nil : "contactos"
        do {
            let l: [Contacto] = try await estado.api.get("/v1/contactos", query: query)
            lista = l
            error = nil
            guardadoEn = nil
            if let clave {
                Guardado.guardar(l, clave: clave)
                Spotlight.indexar(contactos: l)
            }
        } catch let e as ErrorApi {
            if e.sinConexion, let clave, let g = Guardado.leer([Contacto].self, clave: clave) { lista = g.0; guardadoEn = g.1 }
            else if lista == nil { error = e }
        } catch {}
        resumen = try? await estado.api.get("/v1/contactos/resumen")
        esperan = filtrado ? [] : ((try? await estado.api.get("/v1/contactos", query: [.init(name: "esperando", value: "si"), .init(name: "limite", value: "5")])) ?? [])
    }
}

/// «Importar del celular» (varios de la agenda del iPhone, con origen «Agenda del celular») y «Subir
/// Excel» (pasa por la importación de la API: primero se ve cuántos entran y después se confirma).
struct ImportarContactos: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var agenda = false
    @State private var archivo = false
    @State private var subiendo = false
    @State private var confirmando = false
    @State private var importando = false
    @State private var vista: Vista?

    struct Vista: Decodable { var id: String; var total: Int?; var validas: Int?; var conErrores: Int? }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("Traer tus contactos", systemImage: "square.and.arrow.down").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            if let v = vista {
                Text(Formato.sinViudas(resumen(v))).estilo(.body16).foregroundStyle(C.texto)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button("Cancelar") { vista = nil }.buttonStyle(BotonSecundario())
                    Button(confirmando ? "Importando…" : "Importar") { Task { await confirmar(v) } }
                        .buttonStyle(BotonPrincipal()).disabled((v.validas ?? 0) == 0 || confirmando)
                }
            } else {
                Text(Formato.sinViudas("Elegí varios de la agenda del iPhone o subí un Excel o CSV con nombre, teléfono y mail.")).estilo(.subhead).foregroundStyle(C.texto2)
                Button(importando ? "Importando…" : "Importar del celular") { agenda = true }.buttonStyle(BotonPrincipal()).disabled(importando)
                Button(subiendo ? "Leyendo…" : "Subir Excel") { archivo = true }.buttonStyle(BotonSecundario()).disabled(subiendo)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .sheet(isPresented: $agenda) { SelectorAgendaVarios { cs in Task { await delCelular(cs) } } }
        .fileImporter(isPresented: $archivo, allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "xlsx") ?? .data]) { r in
            if case .success(let u) = r { Task { await subir(u) } }
        }
    }

    private func resumen(_ v: Vista) -> String {
        let total = v.total ?? 0, validas = v.validas ?? 0, errores = v.conErrores ?? 0
        var t = "Leímos \(Formato.cantidad(total, "fila", "filas")): entran \(Formato.cantidad(validas, "contacto", "contactos"))"
        if errores > 0 { t += " y \(errores == 1 ? "1 fila tiene" : "\(Formato.numero(errores)) filas tienen") errores (esas no se importan)" }
        return t + "."
    }

    private func delCelular(_ cs: [CNContact]) async {
        struct Cuerpo: Encodable { var nombre: String; var telefono: String?; var email: String?; var origen = "Agenda del celular" }
        importando = true
        defer { importando = false }
        var creados = 0
        for c in cs.prefix(500) {
            let nombre = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !nombre.isEmpty else { continue }
            let mail = c.emailAddresses.first.map { String($0.value) }.flatMap { $0.contains("@") ? $0 : nil }
            do {
                try await estado.api.hacer("POST", "/v1/contactos", Cuerpo(nombre: String(nombre.prefix(120)), telefono: c.phoneNumbers.first?.value.stringValue, email: mail))
                creados += 1
            } catch {
                // El que falla (un mail raro) no frena a los demás.
            }
        }
        estado.avisar(Formato.cantidad(creados, "contacto importado", "contactos importados"))
        estado.version += 1
        if creados > 0 { cerrar() }
    }

    private func subir(_ u: URL) async {
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        subiendo = true
        defer { subiendo = false }
        do {
            let d = try Data(contentsOf: u)
            guard d.count <= 5 << 20 else { estado.avisar("El archivo pasa de 5 MB.", ok: false); return }
            let tipo = u.pathExtension.lowercased() == "csv" ? "text/csv" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            let r = try await estado.api.multipart("/v1/importaciones", query: [.init(name: "tipo", value: "contactos")], datos: d, nombre: u.lastPathComponent, tipo: tipo)
            vista = try Api.decodificador.decode(Vista.self, from: r)
        } catch { estado.avisar(Estado.texto(error, si: "No pudimos leer el archivo."), ok: false) }
    }

    private func confirmar(_ v: Vista) async {
        struct Resultado: Decodable { struct R: Decodable { var creadas: Int? }; var resultado: R? }
        confirmando = true
        defer { confirmando = false }
        do {
            let r: Resultado = try await estado.api.enviar("POST", "/v1/importaciones/\(v.id)/confirmar", JSONLibre.objeto([:]))
            estado.avisar(Formato.cantidad(r.resultado?.creadas ?? 0, "contacto importado", "contactos importados"))
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
