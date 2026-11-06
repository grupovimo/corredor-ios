import AuthenticationServices
import SwiftUI

extension View {
    /// Lo que el handoff no dibuja y el panel sí tiene: una sección por clave (ver `ASeccion`).
    func destinosSecciones() -> some View {
        navigationDestination(for: ASeccion.self) { s in Seccion(clave: s.clave, id: s.id) }
    }
}

/// Elige la pantalla de cada sección. Lo no dibujado se arma con las piezas del handoff (tarjetas,
/// filas, chips, hojas), nunca con diseño nuevo.
struct Seccion: View {
    var clave: String
    var id: String?

    var body: some View {
        switch clave {
        case "mas": MasRaiz()
        case "plan", "suscripcion": PantallaPlan()
        case "configuracion", "inmobiliaria": ConfigInmobiliaria()
        case "equipo": Equipo()
        case "integraciones", "whatsapp", "mercadolibre": Integraciones()
        case "respuestas": RespuestasGuardadas()
        case "proveedores": Proveedores()
        case "objetivos": Objetivos()
        case "inventarios": ListaActas()
        case "actas": if let id { Inventario(propiedad: id) }
        case "rendiciones": RendicionesListas()
        case "papelera": Papelera()
        case "actividad": Actividad()
        case "revision": RevisionIA()
        case "informe": Informe()
        case "indices": Indices()
        case "vistas": if let id { VistasPropiedad(propiedad: id) }
        case "tarifas": if let id { TarifasTemporada(propiedad: id) }
        case "web", "plantillas", "editor": MiWeb()
        case "difusion": Portales()
        case "emprendimientos": Emprendimientos()
        case "emprendimiento": if let id { FichaEmprendimiento(id: id) }
        case "temporada": Temporada()
        case "reservas": Reservas()
        case "consorcios": Consorcios()
        case "consorcio": if let id { FichaConsorcio(id: id) }
        case "envios": if let id { FichasMandadas(propiedad: id) }
        case "grabaciones": if let id { Grabaciones(propiedad: id) }
        case "reservas-propiedad": if let id { Reservas(ruta: "/v1/propiedades/\(id)/reservas") }
        case "importar": Importar()
        case "documentos-propiedad": if let id { DocumentosLista(de: "propiedad", id: id) }
        case "documentos-contrato": if let id { DocumentosLista(de: "contrato", id: id) }
        case "bienes": if let id { BienesConsorcio(consorcio: id) }
        case "reglamento": if let id { ReglamentoConsorcio(consorcio: id) }
        case "ia": CorredorEnTuIA()
        case "firma": FirmaYSesiones()
        default: EstadoVacio(icono: "questionmark.folder", titulo: "No encontramos esta sección").frame(maxHeight: .infinity).background(FondoApp())
        }
    }
}

// MARK: - Todo

// MARK: - Lista genérica

/// Una lista de lo que devuelva la API (cualquier forma): toma el título, el detalle y la fecha de los
/// campos habituales. Para secciones de consulta (actividad, vistas, portales).
struct ListaGenerica: View {
    @Environment(Estado.self) private var estado
    var titulo: String
    var ruta: String
    var icono: String
    var vacio: String
    var acciones: ((JSONLibre) -> [(String, () -> Void)])? = nil
    @State private var items: [JSONLibre]?
    @State private var error: ErrorApi?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let items {
                    if items.isEmpty { EstadoVacio(icono: icono, titulo: vacio).padding(.top, 50) }
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                            HStack(alignment: .top, spacing: 12) {
                                IconoTono(icono: icono, tono: .verde, tam: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.titulo(x)).estilo(.filaLista).foregroundStyle(C.texto)
                                    if let d = Self.detalle(x) { Text(d).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(3) }
                                    if let f = Self.fecha(x) { Text(Formato.cuando(f)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3) }
                                    if let a = acciones?(x), !a.isEmpty {
                                        HStack { ForEach(a, id: \.0) { t, h in Button(t, action: h).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion) } }.padding(.top, 4)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { abrir(x) }
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                } else if let error {
                    EstadoError(que: titulo.lowercased(), error: error) { Task { await cargar() } }
                } else { EsqueletoFilas(filas: 6) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada(titulo)
        .navigationBarTitleDisplayMode(.large)
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async {
        do {
            let d = try await estado.api.pedir("GET", ruta, query: [.init(name: "limite", value: "200")])
            let j = try Api.decodificador.decode(JSONLibre.self, from: d)
            if case .lista(let l) = j { items = l }
            else if case .objeto(let o) = j, let l = o.values.first(where: { if case .lista = $0 { return true }; return false }), case .lista(let x) = l { items = x }
            else { items = [] }
            error = nil
        } catch let e as ErrorApi { error = e } catch { items = [] }
    }

    private func abrir(_ x: JSONLibre) {
        if let p = x["propiedadId"]?.texto { estado.abrir(AFichaPropiedad(id: p)) }
        else if let c = x["contactoId"]?.texto { estado.abrir(AFichaContacto(id: c)) }
        else if let c = x["contratoId"]?.texto { estado.abrir(AFichaContrato(id: c)) }
    }

    static func titulo(_ x: JSONLibre) -> String {
        for k in ["titulo", "nombre", "descripcion", "propiedadTitulo", "propiedad", "texto", "accion", "codigo", "portal"] { if let t = x[k]?.texto?.nonEmpty { return t } }
        return "—"
    }

    static func detalle(_ x: JSONLibre) -> String? {
        let partes = ["detalle", "contactoNombre", "estado", "entidad", "autorNombre", "agenteNombre", "direccion", "barrio", "motivo"].compactMap { x[$0]?.texto?.nonEmpty }
        return partes.isEmpty ? nil : partes.prefix(3).joined(separator: " · ")
    }

    static func fecha(_ x: JSONLibre) -> Date? {
        for k in ["ocurrioEn", "creadoEn", "creadaEn", "borradoEn", "actualizadoEn", "en", "fecha"] { if let t = x[k]?.texto, let f = Fecha.iso(t) ?? Fecha.dia(t) { return f } }
        return nil
    }
}

/// Un título y un texto (respuestas guardadas, notas).
struct EditorTexto: View {
    @Environment(\.dismiss) private var cerrar
    @State var titulo: String
    @State var texto: String
    var guardar: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $titulo)
                TextField("Texto", text: $texto, axis: .vertical).lineLimit(5...14)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(titulo, texto); cerrar() }.disabled(titulo.isEmpty || texto.isEmpty) }
            }
        }
    }
}

struct URLHoja: Identifiable { var url: URL; var id: String { url.absoluteString } }
