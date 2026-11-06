import SwiftUI

/// `GET /v1/mercadolibre`: la cuenta conectada.
struct ConexionML: Codable {
    var disponible: Bool?
    var conectada: Bool
    var apodo: String?
    var reautorizar: Bool?
    var preguntasSinResponder: Int?
}

/// Una pregunta de Mercado Libre para la lista (GET /v1/mercadolibre/preguntas).
struct PreguntaListaML: Codable, Identifiable, Hashable {
    var id: String
    var propiedadId: String?
    var propiedad: String?
    var texto: String
    var estado: String?
    var creadaEn: Date?
    var compradorApodo: String?
    var visitasSemana: Int?
}

/// Cómo se arregla un error de Mercado Libre (web: lib/mercadolibre/modelo.ts `arregloDe`): un número
/// de la ficha acá mismo, o ir a la ficha a cargar lo que falta.
struct ArregloML {
    var falta: String
    var porque: String
    var campo: String?
    var etiqueta: String?
    var enFicha: String?

    static func de(_ error: String?) -> ArregloML {
        let e = (error ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        func hay(_ p: String) -> Bool { e.range(of: p, options: .regularExpression) != nil }
        if hay("superficie|total_area|covered_area|m2|metros") {
            return ArregloML(falta: "la superficie total", porque: "Es obligatoria para publicar en Mercado Libre.", campo: "superficie", etiqueta: "m² totales")
        }
        if hay("ambientes|rooms") { return ArregloML(falta: "los ambientes", porque: "Mercado Libre los pide para esta categoría.", campo: "ambientes", etiqueta: "Ambientes") }
        if hay("dormitorio|bedrooms") { return ArregloML(falta: "los dormitorios", porque: "Mercado Libre los pide para esta categoría.", campo: "dormitorios", etiqueta: "Dormitorios") }
        if hay("bano|full_bathrooms|bathrooms") { return ArregloML(falta: "los baños", porque: "Mercado Libre los pide para esta categoría.", campo: "banos", etiqueta: "Baños") }
        if hay("precio|price") { return ArregloML(falta: "el precio", porque: "Mercado Libre no publica sin precio.", campo: "precio", etiqueta: "Precio") }
        if hay("foto|picture") { return ArregloML(falta: "una foto", porque: "Mercado Libre no publica avisos sin fotos.", enFicha: "Cargar fotos") }
        if hay("ubicacion|direccion|location|address|lat") {
            return ArregloML(falta: "la ubicación", porque: "Mercado Libre necesita la dirección y el barrio.", enFicha: "Completar la dirección")
        }
        if hay("titulo|title") { return ArregloML(falta: "un título más claro", porque: "Mercado Libre rechazó el título.", enFicha: "Cambiar el título") }
        if hay("bloque|moderad|infraccion|forbidden|under_review") {
            return ArregloML(falta: "una revisión de Mercado Libre", porque: "El aviso quedó en revisión; se resuelve en Mercado Libre.")
        }
        return ArregloML(falta: "un dato del aviso", porque: "Revisá la ficha y volvé a publicar.", enFicha: "Revisar la ficha")
    }

    /// «+12 %», «−8 %» contra la semana anterior.
    static func variacion(_ semana: Int?, _ anterior: Int?) -> (String, Bool)? {
        guard let s = semana, let a = anterior, a > 0 else { return nil }
        let p = Int((Double(s - a) / Double(a) * 100).rounded())
        return ("\(p > 0 ? "+" : p < 0 ? "−" : "")\(abs(p))\u{00A0}%", p >= 0)
    }

    static let estados: [String: (String, Tono)] = ["publicada": ("Activa", .verde), "pausada": ("Pausada", .oro), "finalizada": ("Finalizada", .neutro),
                                                    "error": ("Con error", .rojo), "pendiente": ("Publicando", .azul)]
}

/// 32E Mercado Libre: «¿quién está esperando y qué publicación tiene un problema?». Las preguntas sin
/// responder (cada una abre la respuesta armada), los errores explicados con el dato que falta cargado
/// ahí mismo («Guardar y publicar»), y las publicaciones ordenadas por las visitas de la semana.
struct PantallaMercadoLibre: View {
    @Environment(Estado.self) private var estado
    @State private var conexion: ConexionML?
    @State private var preguntas: [PreguntaListaML] = []
    @State private var pubs: [PublicacionLista] = []
    @State private var resumen: ResumenPublicaciones?
    @State private var fichas: [String: Propiedad] = [:]
    @State private var equipo: [Miembro] = []
    @State private var error: ErrorApi?
    @State private var valores: [String: String] = [:]
    @State private var arreglando: Set<String> = []
    @State private var erroresCampo: [String: String] = [:]

    private var errores: [PublicacionLista] { pubs.filter { $0.estado == "error" } }
    private var publicaciones: [PublicacionLista] {
        pubs.filter { $0.estado != "error" }.sorted { ($0.visitasSemana ?? $0.visitas ?? 0, $0.visitas ?? 0) > ($1.visitasSemana ?? $1.visitas ?? 0, $1.visitas ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = conexion {
                    if !c.conectada { desconectada(c) } else { conectada(c) }
                } else if let error {
                    EstadoError(que: "Mercado Libre", error: error) { Task { await cargar() } }.padding(.top, 40)
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Mercado Libre")
        .task(id: estado.version) { await cargar() }
    }

    private func desconectada(_ c: ConexionML) -> some View {
        EstadoVacio(icono: "storefront", titulo: c.reautorizar == true ? "Hay que volver a conectar Mercado Libre" : "Las preguntas de Mercado Libre van a entrar acá",
                    texto: "Las preguntas llegan con la respuesta armada.",
                    accion: estado.esDuenio && c.disponible != false ? ("Conectar Mercado Libre", { estado.abrir(ASeccion(clave: "integraciones")) })
                        : ("Ver integraciones", { estado.abrir(ASeccion(clave: "integraciones")) }))
            .padding(.top, 30)
    }

    @ViewBuilder
    private func conectada(_ c: ConexionML) -> some View {
        let activas = pubs.filter { $0.estado == "publicada" }.count
        let pausadas = pubs.filter { $0.estado == "pausada" }.count
        Text("Cuenta \(c.apodo ?? "") · \(Formato.cantidad(activas, "publicación activa", "publicaciones activas"))").estilo(.subhead).foregroundStyle(C.texto2)
        cifras(activas: activas, pausadas: pausadas)
        // Preguntas
        TituloBloque(texto: "Preguntas sin responder", cuenta: preguntas.isEmpty ? nil : "\(preguntas.count)")
        if preguntas.isEmpty {
            HStack(spacing: 10) {
                IconoTono(icono: "checkmark.bubble", tono: .verde, tam: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No hay preguntas esperando").estilo(.filaLista).foregroundStyle(C.texto)
                    Text("Las preguntas entran acá con la respuesta armada.").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(preguntas.enumerated()), id: \.element.id) { i, q in filaPregunta(q, primera: i == 0) }
            }
            .tarjeta()
        }
        // Errores
        if !errores.isEmpty {
            TituloBloque(texto: "Con error", cuenta: "\(errores.count)")
            ForEach(errores) { x in tarjetaError(x) }
        }
        // Publicaciones
        TituloBloque(texto: "Publicaciones", cuenta: "\(publicaciones.count)")
        if publicaciones.isEmpty {
            Text("Cada propiedad se publica desde su ficha.").estilo(.footnote).foregroundStyle(C.texto2)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(publicaciones.enumerated()), id: \.element.id) { i, x in filaPublicacion(x, primera: i == 0) }
            }
            .tarjeta()
        }
    }

    private func cifras(activas: Int, pausadas: Int) -> some View {
        let ml = resumen?.portales?.first { $0.portal == "mercadolibre" }
        let vieja = preguntas.compactMap(\.creadaEn).min()
        let variacion = ArregloML.variacion(ml?.visitasSemana, ml?.visitasSemanaAnterior)
        let total = pubs.reduce(0) { $0 + ($1.visitas ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Cifra(etiqueta: "Sin responder", valor: "\(preguntas.count)")
                Cifra(etiqueta: "Con error", valor: "\(errores.count)")
                Cifra(etiqueta: "Activas", valor: "\(activas)")
                Cifra(etiqueta: "Pausadas", valor: "\(pausadas)")
            }
            if let vieja { Text("La más vieja: \(Formato.hace(vieja))").estilo(.footnote).foregroundStyle(C.avisoTinta) }
            if let s = ml?.visitasSemana {
                HStack(spacing: 6) {
                    Text("\(Formato.numero(s)) visitas a publicaciones esta semana").estilo(.footnoteFuerte).foregroundStyle(C.texto)
                    if let v = variacion { Text(v.0).estilo(.footnoteFuerte).foregroundStyle(v.1 ? C.okTinta : C.errorTinta) }
                }
            } else if total > 0 {
                Text("\(Formato.numero(total)) visitas a publicaciones en total").estilo(.footnoteFuerte).foregroundStyle(C.texto)
            }
        }
    }

    private func lineaPregunta(_ q: PreguntaListaML) -> String {
        let f = q.propiedadId.flatMap { fichas[$0] }
        let agente = f?.agenteId.flatMap { a in equipo.first { $0.usuarioId == a }?.completo.components(separatedBy: " ").first }
        let visitas = q.visitasSemana ?? pubs.first { $0.propiedadId == q.propiedadId }?.visitasSemana
        let total = pubs.first { $0.propiedadId == q.propiedadId }?.visitas
        return [f?.ambientes.map { "\($0) amb" }, f?.superficie.map { "\(Formato.numero(Int($0))) m²" }, agente,
                visitas.map { "\(Formato.numero($0)) visitas esta semana" } ?? total.map { "\(Formato.numero($0)) visitas" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func filaPregunta(_ q: PreguntaListaML, primera: Bool) -> some View {
        let f = q.propiedadId.flatMap { fichas[$0] }
        return Button { estado.abrir(APreguntaML(id: q.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Foto(url: f?.miniatura).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text([f?.titulo ?? q.propiedad ?? "Publicación", f?.precio.flatMap { p in f?.precioOculto == true ? nil : Formato.plata(p, f?.moneda ?? "USD") }]
                        .compactMap { $0 }.joined(separator: " · ")).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    let l = lineaPregunta(q)
                    if !l.isEmpty { Text(l).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1) }
                    Text("«\(q.texto)»\(q.compradorApodo.map { " · usuario \($0)" } ?? "")").estilo(.subhead).foregroundStyle(C.texto).lineLimit(3)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    if let c = q.creadaEn { Text(Formato.hace(c)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                    Text("Responder").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.accion)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func tarjetaError(_ x: PublicacionLista) -> some View {
        let a = ArregloML.de(x.error)
        let corto = (x.propiedad ?? "La propiedad").components(separatedBy: ",").first ?? ""
        let partes = a.falta.split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconoTono(icono: "exclamationmark.circle", tono: .rojo, tam: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(corto) no se publicó").estilo(.filaLista).foregroundStyle(C.texto)
                    Text("Mercado Libre dice: \(x.error ?? "")").font(.system(size: 12, design: .monospaced)).foregroundStyle(C.texto2).lineLimit(3)
                }
            }
            (Text("Falta \(partes.first ?? "") ") + Text(partes.count > 1 ? partes[1] : "").bold() + Text(". \(a.porque)")).estilo(.subhead).foregroundStyle(C.texto)
            if let campo = a.campo, estado.escribe {
                HStack(spacing: 8) {
                    TextField(a.etiqueta ?? "", text: Binding(get: { valores[x.propiedadId] ?? "" }, set: { valores[x.propiedadId] = $0 }))
                        .keyboardType(.decimalPad).estilo(.body16).padding(.horizontal, 12).frame(height: 44)
                        .background(C.superficie, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(erroresCampo[x.propiedadId] != nil ? C.error : C.linea2, lineWidth: 1))
                    Button(arreglando.contains(x.propiedadId) ? "Publicando…" : "Guardar y publicar") { Task { await arreglar(x, campo: campo) } }
                        .buttonStyle(BotonTonal(alto: 44)).disabled((valores[x.propiedadId] ?? "").isEmpty || arreglando.contains(x.propiedadId))
                }
                if let e = erroresCampo[x.propiedadId] { MensajeError(texto: e) }
            } else if let f = a.enFicha, estado.escribe {
                Button(f) { estado.abrir(f == "Cargar fotos" ? AnyHashable(AEditarEnPaso(id: x.propiedadId, paso: "fotos")) : AnyHashable(AAltaPropiedad(editar: x.propiedadId))) }
                    .buttonStyle(BotonTonal())
            }
        }
        .padding(14).tarjeta()
    }

    private func filaPublicacion(_ x: PublicacionLista, primera: Bool) -> some View {
        let (t, tono) = ArregloML.estados[x.estado] ?? (x.estado.capitalized, .neutro)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(x.propiedad ?? "Publicación").estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                Text(x.visitasSemana.map { "\(Formato.numero($0)) visitas esta semana" } ?? "\(Formato.numero(x.visitas ?? 0)) visitas")
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            Text(t).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
            if let u = x.url.flatMap(URL.init(string:)) {
                Link(destination: u) { Image(systemName: "arrow.up.right.square").foregroundStyle(C.accion) }.accessibilityLabel("Ver en Mercado Libre")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture { estado.abrir(AFichaPropiedad(id: x.propiedadId)) }
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    /// Guarda el número en la ficha (PUT con la propiedad entera) y vuelve a publicar.
    private func arreglar(_ x: PublicacionLista, campo: String) async {
        let v = Double((valores[x.propiedadId] ?? "").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
        guard v > 0 else { erroresCampo[x.propiedadId] = "Poné un número."; return }
        arreglando.insert(x.propiedadId)
        erroresCampo[x.propiedadId] = nil
        defer { arreglando.remove(x.propiedadId) }
        struct R: Decodable { var estado: String? }
        do {
            var p: Propiedad = try await estado.api.get("/v1/propiedades/\(x.propiedadId)")
            switch campo {
            case "superficie": p.superficie = v
            case "cubierta": p.cubierta = v
            case "ambientes": p.ambientes = Int(v)
            case "dormitorios": p.dormitorios = Int(v)
            case "banos": p.banos = Int(v)
            default: p.precio = v
            }
            try await estado.api.hacer("PUT", "/v1/propiedades/\(p.id)", p)
            let raw = try await estado.api.pedir("POST", "/v1/propiedades/\(p.id)/publicaciones/mercadolibre")
            let r = try? Api.decodificador.decode(R.self, from: raw)
            if r?.estado == "error" { estado.avisar("Se guardó, pero Mercado Libre todavía no lo acepta", ok: false) }
            else { estado.avisar("\(p.direccion ?? "La propiedad") se publicó en Mercado Libre") }
            estado.version += 1
        } catch let e as ErrorApi {
            erroresCampo[x.propiedadId] = e.detalle.isEmpty ? "No se publicó. Probá de nuevo." : e.detalle
        } catch {
            erroresCampo[x.propiedadId] = "No se publicó. Probá de nuevo."
        }
    }

    private func cargar() async {
        do {
            let c: ConexionML = try await estado.api.get("/v1/mercadolibre")
            conexion = c
            error = nil
            guard c.conectada else { return }
            preguntas = ((try? await estado.api.get("/v1/mercadolibre/preguntas", query: [.init(name: "estado", value: "sin_responder"), .init(name: "limite", value: "100")])) ?? [PreguntaListaML]())
                .sorted { ($0.creadaEn ?? .distantPast) < ($1.creadaEn ?? .distantPast) }
            pubs = (try? await estado.api.get("/v1/publicaciones", query: [.init(name: "portal", value: "mercadolibre"), .init(name: "limite", value: "500")])) ?? []
            resumen = try? await estado.api.get("/v1/publicaciones/resumen")
            if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
            for id in Set(preguntas.compactMap(\.propiedadId)) where fichas[id] == nil {
                if let p: Propiedad = try? await estado.api.get("/v1/propiedades/\(id)") { fichas[id] = p }
            }
        } catch let e as ErrorApi { error = e } catch {}
    }
}
