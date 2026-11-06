import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Documentos

struct DocumentoAPI: Codable, Identifiable, Hashable {
    var id: String
    var archivoId: String?
    var nombre: String
    var tipo: String?
    var bytes: Int?
    var subidoPor: String?
    var creadoEn: Date?
    var url: String?
}

/// Los documentos de un contrato o de una propiedad: verlos, subir un PDF o una foto, y borrarlos.
struct DocumentosLista: View {
    @Environment(Estado.self) private var estado
    /// «contrato» o «propiedad».
    var de: String
    var id: String
    @State private var lista: [DocumentoAPI] = []
    @State private var cargado = false
    @State private var error: ErrorApi?
    @State private var eligiendo = false
    @State private var foto: PhotosPickerItem?
    @State private var previo: ArchivoPrevio?
    @State private var subiendo = false
    @State private var escaneando = false

    var body: some View {
        List {
            if estado.escribe {
                TipView(ConsejoEscanear()).tipBackground(C.superficie).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if let error, lista.isEmpty {
                EstadoError(que: "los documentos", error: error) { Task { await cargar() } }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if !cargado {
                EsqueletoFilas(filas: 3).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if lista.isEmpty {
                EstadoVacio(icono: "folder", titulo: "Sin documentos", texto: "El contrato firmado, el DNI, la escritura, los planos: todo a mano.",
                            accion: estado.escribe ? ("Subir un PDF", { eligiendo = true }) : nil)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(lista) { d in
                Button { Task { await abrir(d) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.tipo?.contains("pdf") == true ? "doc.richtext" : "photo").foregroundStyle(C.azulTinta).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(d.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                            Text([d.subidoPor, d.creadoEn.map { Formato.cuando($0) }, d.bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
                                .compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                    }
                }
                .swipeActions { if estado.escribe { Button("Sacar", role: .destructive) { Task { await sacar(d) } } } }
            }
            if subiendo { ProgressView() }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Documentos")
        .toolbar {
            if estado.escribe {
                Menu {
                    if VNDocumentCameraViewController.isSupported {
                        Button { escaneando = true } label: { Label("Escanear con la cámara", systemImage: "doc.viewfinder") }
                    }
                    Button { eligiendo = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                    PhotosPicker(selection: $foto, matching: .images) { Label("Una foto", systemImage: "photo") }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Sumar")
            }
        }
        .task(id: estado.version) { await cargar() }
        .vistaPrevia($previo)
        .fullScreenCover(isPresented: $escaneando) {
            EscanerDocumentos { pdf in Task { await subir(pdf, nombre: "Escaneo \(Formato.diaISO(Date())).pdf", tipo: "application/pdf") } }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $eligiendo, allowedContentTypes: [.pdf, .image]) { r in
            if case .success(let u) = r {
                Task {
                    let acceso = u.startAccessingSecurityScopedResource()
                    defer { if acceso { u.stopAccessingSecurityScopedResource() } }
                    do {
                        let d = try Data(contentsOf: u)
                        await subir(d, nombre: u.lastPathComponent, tipo: u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
                    } catch { estado.avisar(error) }
                }
            }
        }
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                do {
                    if let d = try await i.loadTransferable(type: Data.self) { await subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "Foto.jpg", tipo: "image/jpeg") }
                } catch { estado.avisar(error) }
                foto = nil
            }
        }
    }

    private func cargar() async {
        do {
            lista = try await estado.api.get("/v1/documentos", query: [.init(name: de, value: id)])
            error = nil
        } catch let e as ErrorApi { error = e } catch {}
        cargado = true
    }

    /// Sacar va a la papelera al toque, con deshacer (se vuelve a sumar el mismo archivo).
    private func sacar(_ d: DocumentoAPI) async {
        struct C: Encodable { var archivoId: String; var nombre: String; var contratoId: String?; var propiedadId: String? }
        do {
            try await estado.api.hacer("DELETE", "/v1/documentos/\(d.id)")
            lista.removeAll { $0.id == d.id }
            estado.avisar("Sacaste «\(d.nombre)»") {
                Task {
                    guard let a = d.archivoId else { return }
                    do {
                        try await estado.api.hacer("POST", "/v1/documentos", C(archivoId: a, nombre: d.nombre, contratoId: de == "contrato" ? id : nil, propiedadId: de == "propiedad" ? id : nil))
                        await cargar()
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func subir(_ datos: Data, nombre: String, tipo: String) async {
        guard datos.count <= 25 << 20 else { estado.avisar("El archivo pasa de 25 MB.", ok: false); return }
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(datos, nombre: nombre, tipo: tipo, uso: "documento")
            struct C: Encodable { var archivoId: String; var nombre: String; var contratoId: String?; var propiedadId: String? }
            try await estado.api.hacer("POST", "/v1/documentos", C(archivoId: a.id, nombre: nombre, contratoId: de == "contrato" ? id : nil, propiedadId: de == "propiedad" ? id : nil))
            await cargar()
        } catch { estado.avisar(error) }
    }

    /// Lo baja con la sesión de la app y lo muestra con la vista previa (compartir, imprimir).
    private func abrir(_ d: DocumentoAPI) async {
        guard let a = d.archivoId else { return }
        do {
            let datos = try await estado.api.pedir("GET", "/v1/archivos/\(a)/contenido")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(d.nombre)
            try datos.write(to: u)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

/// El escáner de documentos del iPhone (VisionKit): recorta y endereza cada hoja; al terminar, las
/// páginas salen en un solo PDF.
struct EscanerDocumentos: UIViewControllerRepresentable {
    var listo: (Data) -> Void
    @Environment(\.dismiss) private var cerrar

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController()
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, VNDocumentCameraViewControllerDelegate {
        let padre: EscanerDocumentos
        init(_ padre: EscanerDocumentos) { self.padre = padre }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
            let pdf = UIGraphicsPDFRenderer(bounds: a4).pdfData { ctx in
                for i in 0..<scan.pageCount {
                    ctx.beginPage()
                    let img = scan.imageOfPage(at: i)
                    let escala = min(a4.width / img.size.width, a4.height / img.size.height)
                    let tam = CGSize(width: img.size.width * escala, height: img.size.height * escala)
                    img.draw(in: CGRect(x: (a4.width - tam.width) / 2, y: (a4.height - tam.height) / 2, width: tam.width, height: tam.height))
                }
            }
            if scan.pageCount > 0 { padre.listo(pdf) }
            padre.cerrar()
        }

        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { padre.cerrar() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { padre.cerrar() }
    }
}
