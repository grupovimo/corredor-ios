import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Importar la cartera

struct ImportacionAPI: Codable {
    struct Nota: Codable, Hashable { var campo: String?; var mensaje: String }
    struct Fila: Codable, Hashable { var fila: Int; var datos: [String: JSONLibre]?; var errores: [Nota]?; var avisos: [Nota]? }
    struct Resultado: Codable { var creadas: Int?; var yaEstaban: Int?; var conErrores: Int? }
    /// Cada columna del archivo y el campo de Corredor que se reconoció (nil: no se usa).
    struct Columna: Codable, Hashable { var columna: String; var campo: String?; var ejemplo: String? }
    var id: String
    var tipo: String?
    var archivo: String?
    var estado: String?
    var columnas: [Columna]?
    var total: Int?
    var validas: Int?
    var conErrores: Int?
    var conAvisos: Int?
    var filas: [Fila]?
    var resultado: Resultado?
}

/// Traer la cartera de otro sistema: un Excel o CSV de propiedades o contactos. Primero la vista
/// previa (cuántas entran, avisos y errores por fila); después se traen, sin publicar.
struct Importar: View {
    @Environment(Estado.self) private var estado
    @State private var tipo = "propiedades"
    @State private var eligiendo = false
    @State private var subiendo = false
    @State private var imp: ImportacionAPI?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = imp?.resultado {
                    EstadoVacio(icono: "checkmark.circle", titulo: "Listo: \(Formato.cantidad(r.creadas ?? 0, tipo == "contactos" ? "contacto nuevo" : "propiedad nueva", tipo == "contactos" ? "contactos nuevos" : "propiedades nuevas"))",
                                texto: [(r.yaEstaban ?? 0) > 0 ? "\(r.yaEstaban!) ya estaban" : nil, (r.conErrores ?? 0) > 0 ? "\(r.conErrores!) con errores quedaron afuera" : nil].compactMap { $0 }.joined(separator: " · ").nonEmpty,
                                accion: ("Ver la cartera", { estado.pestana = tipo == "contactos" ? .inicio : .propiedades; if tipo == "contactos" { estado.abrir(AContactos()) } }))
                        .padding(.top, 30)
                } else if let i = imp {
                    HStack(spacing: 8) {
                        Cifra(etiqueta: "Entran", valor: "\(i.validas ?? 0)")
                        Cifra(etiqueta: "Con avisos", valor: "\(i.conAvisos ?? 0)")
                        Cifra(etiqueta: "Con errores", valor: "\(i.conErrores ?? 0)")
                    }
                    if let c = i.columnas?.filter({ $0.campo != nil }).map(\.columna), !c.isEmpty {
                        Text("Reconocimos: \(c.joined(separator: ", "))").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array((i.filas ?? []).filter { !($0.errores ?? []).isEmpty || !($0.avisos ?? []).isEmpty }.prefix(60).enumerated()), id: \.offset) { n, f in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Fila \(f.fila) · \(ListaGenerica.titulo(.objeto(f.datos ?? [:])))").estilo(.filaLista).foregroundStyle(C.texto)
                                ForEach(f.errores ?? [], id: \.self) { e in Label(e.mensaje, systemImage: "xmark.circle").estilo(.footnote).foregroundStyle(C.errorTinta) }
                                ForEach(f.avisos ?? [], id: \.self) { e in Label(e.mensaje, systemImage: "exclamationmark.triangle").estilo(.footnote).foregroundStyle(C.avisoTinta) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { if n > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                    Button("Traer \(Formato.cantidad(i.validas ?? 0, tipo == "contactos" ? "contacto" : "propiedad", tipo == "contactos" ? "contactos" : "propiedades"))") { Task { await confirmar(i) } }
                        .buttonStyle(BotonPrincipal()).disabled((i.validas ?? 0) == 0 || subiendo)
                    Button("Elegir otro archivo") { imp = nil; eligiendo = true }.buttonStyle(BotonTexto())
                } else {
                    Segmentado(opciones: [("propiedades", "Propiedades"), ("contactos", "Contactos")], elegido: $tipo)
                    EstadoVacio(icono: "tablecells", titulo: "Traé tu cartera", texto: "Un Excel o un CSV de tu sistema anterior. Primero ves cómo queda y después se trae, sin publicar.",
                                accion: (subiendo ? "Leyendo…" : "Elegir el archivo", { eligiendo = true }),
                                secundaria: ("O captá en la calle con MIRA", { estado.miraAbierta = true }))
                        .padding(.top, 20)
                }
            }
            .padding(16)
        }
        .pantallaApilada("Importar")
        .fileImporter(isPresented: $eligiendo, allowedContentTypes: [.commaSeparatedText, .spreadsheet, .data]) { r in
            if case .success(let u) = r { Task { await subir(u) } }
        }
    }

    private func subir(_ u: URL) async {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u) else { return }
        subiendo = true
        defer { subiendo = false }
        do {
            let r = try await estado.api.multipart("/v1/importaciones", query: [.init(name: "tipo", value: tipo)], datos: d, nombre: u.lastPathComponent,
                                                   tipo: u.pathExtension.lowercased() == "csv" ? "text/csv" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            imp = try Api.decodificador.decode(ImportacionAPI.self, from: r)
        } catch { estado.avisar(error) }
    }

    private func confirmar(_ i: ImportacionAPI) async {
        subiendo = true
        defer { subiendo = false }
        do {
            imp = try await estado.api.enviar("POST", "/v1/importaciones/\(i.id)/confirmar", [String: String]())
            estado.version += 1
            Haptico.exito()
        } catch { estado.avisar(error) }
    }
}
