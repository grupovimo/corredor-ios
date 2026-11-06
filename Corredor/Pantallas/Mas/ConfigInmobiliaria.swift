import AuthenticationServices
import SwiftUI

// MARK: - Configuración

/// 41 Inmobiliaria: los datos (nombre, zona horaria, CBU o alias para cobrar), la marca (resumen: se edita
/// en Mi web), qué hacen y dónde, y los datos legales que la web exhibe en el pie. Los cambia sólo el dueño.
struct ConfigInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var ficha: Ficha?
    @State private var error: ErrorApi?
    @State private var nombre = ""
    @State private var cbu = ""
    @State private var zona = "America/Argentina/Buenos_Aires"
    @State private var legales: [String: String] = [:]
    @State private var guardando: String?
    @State private var guardado: String?
    @State private var campos: [String: String] = [:]

    /// `GET /v1/inmobiliaria` (inmobiliarias.Inmobiliaria).
    struct Ficha: Decodable {
        struct Perfil: Decodable { var rubros: [String]?; var zonas: [String]? }
        var id: String
        var slug: String?
        var nombre: String
        var dominio: String?
        var marca: JSONLibre?
        var zonaHoraria: String?
        var legales: [String: String?]?
        var cbu: String?
        var web: String?
        var perfil: Perfil?
    }

    static let rubros = ["ventas": "Ventas", "alquileres": "Alquileres", "temporada": "Temporada", "emprendimientos": "Emprendimientos", "consorcios": "Consorcios"]

    /// Las zonas de la Argentina, como la web. Si guardaron otra, también aparece.
    static let zonas: [(String, String)] = [
        ("America/Argentina/Buenos_Aires", "Buenos Aires (CABA y Provincia)"),
        ("America/Argentina/Cordoba", "Córdoba, Santa Fe y el centro"),
        ("America/Argentina/Mendoza", "Mendoza"),
        ("America/Argentina/Salta", "Salta"),
        ("America/Argentina/Jujuy", "Jujuy"),
        ("America/Argentina/Tucuman", "Tucumán"),
        ("America/Argentina/Catamarca", "Catamarca"),
        ("America/Argentina/La_Rioja", "La Rioja"),
        ("America/Argentina/San_Juan", "San Juan"),
        ("America/Argentina/San_Luis", "San Luis"),
        ("America/Argentina/Rio_Gallegos", "Santa Cruz"),
        ("America/Argentina/Ushuaia", "Tierra del Fuego"),
    ]

    /// Los campos legales: clave de la API, etiqueta, largo máximo y ayuda.
    static let camposLegales: [(String, String, Int, String?)] = [
        ("razonSocial", "Razón social", 160, "Como figura en AFIP."), ("cuit", "CUIT", 20, nil),
        ("corredorResponsable", "Corredor responsable", 120, nil), ("matricula", "Matrícula", 40, nil),
        ("colegio", "Colegio o jurisdicción", 160, nil),
    ]

    private var duenio: Bool { estado.esDuenio }

    var body: some View {
        Group {
            if let ficha {
                formulario(ficha)
            } else if let error {
                EstadoError(que: "los datos de la inmobiliaria", error: error) { Task { await cargar() } }
                    .frame(maxHeight: .infinity).background(FondoApp())
            } else {
                EsqueletoFilas(filas: 6).padding(16).frame(maxHeight: .infinity, alignment: .top).background(FondoApp())
            }
        }
        .pantallaApilada("Inmobiliaria")
        .task(id: estado.version) { await cargar() }
    }

    @ViewBuilder
    private func formulario(_ f: Ficha) -> some View {
        Form {
            Section {
                Text(Formato.sinViudas("Los datos de \(f.nombre): los que ve tu equipo y los que muestra tu web."))
                    .estilo(.footnote).foregroundStyle(C.texto2)
                if !duenio {
                    AvisoRol(texto: "Tu rol es \(estado.rol == "lector" ? "Lector" : "Agente"): podés ver estos datos. Los cambia el dueño o la dueña de la inmobiliaria.")
                }
            }
            .listRowBackground(Color.clear)
            datos(f)
            queHacen(f)
            marca(f)
            seccionLegales()
        }
        .scrollContentBackground(.hidden).background(FondoApp())
    }

    // MARK: Datos

    @ViewBuilder
    private func datos(_ f: Ficha) -> some View {
        Section("Datos") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Nombre de la inmobiliaria", text: $nombre).disabled(!duenio)
                    .onChange(of: nombre) { _, v in if v.count > 120 { nombre = String(v.prefix(120)) } }
                ErrorDeCampo(texto: campos["nombre"])
            }
            if let w = f.web, let u = URL(string: w) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tu web").estilo(.footnoteFuerte).foregroundStyle(C.texto2)
                    Link(destination: u) {
                        Label(w.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""), systemImage: "arrow.up.right.square")
                            .font(.footnote.monospaced())
                    }
                    Button { estado.abrir(ASeccion(clave: "web")) } label: {
                        Text("El dominio propio se conecta en ").foregroundStyle(C.texto2) + Text("Mi web").foregroundStyle(C.accion) + Text(".").foregroundStyle(C.texto2)
                    }
                    .estilo(.footnote)
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("CBU o alias para cobrar", text: $cbu, prompt: Text("luna.propiedades"))
                    .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!duenio)
                    .onChange(of: cbu) { _, v in if v.count > 22 { cbu = String(v.prefix(22)) } }
                Text("Sale en los recibos y en los recordatorios de pago.").estilo(.footnote).foregroundStyle(C.texto3)
                ErrorDeCampo(texto: campos["cbu"])
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Zona horaria", selection: $zona) {
                    ForEach(opcionesZona(f), id: \.0) { z in Text(z.1).tag(z.0) }
                }
                .disabled(!duenio)
                Text("Con ella se calcula «hoy» en la agenda, los vencimientos y los avisos.").estilo(.footnote).foregroundStyle(C.texto3)
                ErrorDeCampo(texto: campos["zonaHoraria"])
            }
            if duenio { pie("datos") { Task { await guardarDatos() } } }
        }
    }

    private func opcionesZona(_ f: Ficha) -> [(String, String)] {
        let z = f.zonaHoraria ?? ""
        if z.isEmpty || Self.zonas.contains(where: { $0.0 == z }) { return Self.zonas }
        return [(z, z)] + Self.zonas
    }

    // MARK: Qué hacen y dónde

    @ViewBuilder
    private func queHacen(_ f: Ficha) -> some View {
        Section {
            let rubros = (f.perfil?.rubros ?? []).map { Self.rubros[$0] ?? $0 }
            if rubros.isEmpty {
                Text(Formato.sinViudas("Todavía no elegiste. Mientras tanto, la app y el panel muestran todo.")).estilo(.subhead).foregroundStyle(C.texto2)
            } else {
                let zonas = f.perfil?.zonas ?? []
                Text(Formato.sinViudas(rubros.joined(separator: " · ") + (zonas.isEmpty ? "" : " · en \(zonas.joined(separator: ", "))") + ". La app y el panel muestran sólo lo que usás."))
                    .estilo(.subhead).foregroundStyle(C.texto2)
            }
            if duenio { Button("Cambiar") { estado.altaAbierta = PasoAlta(clave: "rubros") } }
        } header: { Text("Qué hacen y dónde") }
    }

    // MARK: Marca

    @ViewBuilder
    private func marca(_ f: Ficha) -> some View {
        let m = MarcaResumen(marca: f.marca, nombre: f.nombre)
        Section {
            HStack(spacing: 12) {
                if let l = m.logo {
                    AsyncImage(url: l) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 48, height: 48).background(.white).clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Logo de \(f.nombre)")
                } else {
                    Text(m.inicial).font(Estilo(tamano: 20, peso: .bold, relativo: .headline).font).foregroundStyle(m.acento)
                        .frame(width: 48, height: 48).background(m.primario, in: .rect(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 6) {
                    ForEach(Array([m.primario, m.acento, m.papel].enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 26, height: 26).overlay(Circle().strokeBorder(C.linea))
                    }
                }
                .accessibilityLabel("Colores de la web")
                Spacer()
            }
            ZStack(alignment: .bottomLeading) {
                m.primario
                if let p = m.portada { Foto(url: p) }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                Text(m.frase).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(.white).padding(12)
            }
            .frame(height: 120).clipShape(.rect(cornerRadius: 14, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            Button("Editar en Mi web") { estado.abrir(ASeccion(clave: "web")) }
        } header: { Text("Marca") }
    }

    // MARK: Legales

    @ViewBuilder
    private func seccionLegales() -> some View {
        Section {
            ForEach(Self.camposLegales, id: \.0) { k, n, max, ayuda in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField(n, text: Binding(get: { legales[k] ?? "" }, set: { legales[k] = String($0.prefix(max)) }),
                                  prompt: Text(k == "cuit" ? "30-71584209-9" : k == "colegio" ? "CUCICBA" : n))
                            .keyboardType(k == "cuit" || k == "matricula" ? .numbersAndPunctuation : .default)
                            .font(k == "cuit" ? .body.monospaced() : .body)
                        if k == "colegio", duenio {
                            Menu {
                                Button("CUCICBA") { legales["colegio"] = "CUCICBA" }
                                Button("Colegio de Martilleros y Corredores Públicos de …") { legales["colegio"] = "Colegio de Martilleros y Corredores Públicos de " }
                            } label: { Image(systemName: "chevron.down.circle") }
                            .accessibilityLabel("Sugerencias")
                        }
                    }
                    if let ayuda { Text(ayuda).estilo(.footnote).foregroundStyle(C.texto3) }
                    ErrorDeCampo(texto: campos["legales." + k] ?? campos[k])
                }
            }
            .disabled(!duenio)
            if duenio { pie("legales") { Task { await guardarLegales() } } }
        } header: { Text("Datos legales") } footer: {
            Text("Van en el pie de tu web y en los recibos. En CABA y Provincia, la matrícula es obligatoria.")
        }
    }

    /// «Guardado» y el botón, como el pie de cada tarjeta de la web.
    private func pie(_ cual: String, _ hacer: @escaping () -> Void) -> some View {
        HStack {
            if guardado == cual { Label("Guardado", systemImage: "checkmark.icloud").estilo(.footnote).foregroundStyle(C.okTinta) }
            Spacer()
            Button(action: hacer) {
                if guardando == cual { ProgressView() } else { Text("Guardar").bold() }
            }
            .disabled(guardando != nil)
        }
    }

    // MARK: Datos

    private func cargar() async {
        do {
            let f: Ficha = try await estado.api.get("/v1/inmobiliaria")
            ficha = f
            nombre = f.nombre
            cbu = f.cbu ?? ""
            zona = f.zonaHoraria?.nonEmpty ?? zona
            legales = (f.legales ?? [:]).compactMapValues { $0 }
            error = nil
        } catch let e as ErrorApi { if ficha == nil { error = e } } catch {}
    }

    /// Un CBU o CVU de 22 números, o un alias de 6 a 20 letras, números, puntos o guiones (la regla de la API).
    static func cbuValido(_ c: String) -> Bool {
        if c.range(of: "^\\d{22}$", options: .regularExpression) != nil { return true }
        return c.range(of: "^[A-Za-z0-9.-]{6,20}$", options: .regularExpression) != nil && c.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private func guardarDatos() async {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = cbu.trimmingCharacters(in: .whitespaces)
        campos = [:]
        guardado = nil
        if n.isEmpty { campos["nombre"] = "Poné el nombre de la inmobiliaria." }
        if !c.isEmpty, !Self.cbuValido(c) { campos["cbu"] = "El CBU tiene 22 números; el alias, de 6 a 20 letras, números, puntos o guiones." }
        if !campos.isEmpty { return estado.avisar(campos["cbu"] != nil ? "Revisá el CBU o alias." : "Revisá los datos.", ok: false) }
        guardando = "datos"
        defer { guardando = nil }
        struct Cuerpo: Encodable { var nombre: String; var zonaHoraria: String; var cbu: String }
        do {
            try await estado.api.pedirConCampos("PATCH", "/v1/inmobiliaria", Cuerpo(nombre: n, zonaHoraria: zona, cbu: c))
            guardado = "datos"
            estado.avisar("Guardado")
        } catch { campos = estado.camposDe(error) }
    }

    private func guardarLegales() async {
        campos = [:]
        guardado = nil
        guardando = "legales"
        defer { guardando = nil }
        struct Cuerpo: Encodable { var legales: [String: String] }
        var v: [String: String] = [:]
        for (k, _, _, _) in Self.camposLegales { v[k] = (legales[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        do {
            try await estado.api.pedirConCampos("PATCH", "/v1/inmobiliaria", Cuerpo(legales: v))
            guardado = "legales"
            estado.avisar("Guardado")
        } catch { campos = estado.camposDe(error) }
    }
}

/// La marca de la web, resumida (marcaDe de lib/sitio/marca.ts): colores con los nombres que usó cada
/// versión del editor, y los de ejemplo (Luna Propiedades) si falta algo.
struct MarcaResumen {
    var primario: Color
    var acento: Color
    var papel: Color
    var logo: URL?
    var portada: URL?
    var frase: String
    var inicial: String

    init(marca: JSONLibre?, nombre: String) {
        func texto(_ o: JSONLibre?, _ claves: [String]) -> String? {
            for k in claves { if let t = o?[k]?.texto?.nonEmpty { return t } }
            return nil
        }
        func color(_ s: String?) -> Color? { Acento.rgb(s).map { Color(hex: Acento.hex($0)) } }
        let colores = marca?["colores"]
        primario = color(texto(marca, ["colorPrimario", "primario", "primaryColor", "color"]) ?? texto(colores, ["primario"])) ?? Color(hex: 0x1E3A5F)
        acento = color(texto(marca, ["colorSecundario", "secundario", "secondaryColor", "acento", "accentColor"]) ?? texto(colores, ["secundario", "acento"])) ?? Color(hex: 0xE9DCC3)
        papel = color(texto(marca, ["colorFondo", "fondo", "papel"]) ?? texto(colores, ["fondo"])) ?? Color(hex: 0xFAF8F3)
        logo = texto(marca, ["logoUrl", "logo"]).flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil }
        portada = texto(marca, ["portadaUrl", "portada", "heroImageUrl", "foto"]).flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil }
        frase = texto(marca, ["frase", "tagline", "titulo"]) ?? "Tu próximo lugar"
        inicial = String(nombre.trimmingCharacters(in: .whitespaces).first ?? "·").uppercased()
    }
}
