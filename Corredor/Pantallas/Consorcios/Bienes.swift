import PhotosUI
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Bienes del consorcio

struct BienAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var categoria: String?
    var ubicacion: String?
    var cantidad: Int?
    var estado: String?
    var proximoService: String?
    var responsable: String?
    var notas: String?

    static let categorias = [("matafuego", "Matafuego"), ("ascensor", "Ascensor"), ("bomba", "Bomba"), ("tanque", "Tanque"), ("luminaria", "Luminaria"),
                             ("motor", "Motor"), ("mobiliario", "Mobiliario"), ("herramienta", "Herramienta"), ("otro", "Otro")]
    static let estados = [("ok", "En orden"), ("a_revisar", "A revisar"), ("vencido", "Vencido"), ("baja", "De baja")]
}

/// Los bienes del edificio (matafuegos, ascensores, bombas…) con su estado y el próximo service.
struct BienesConsorcio: View {
    @Environment(Estado.self) private var estado
    var consorcio: String
    @State private var lista: [BienAPI] = []
    @State private var editando: BienAPI?

    var body: some View {
        List {
            if lista.isEmpty {
                EstadoVacio(icono: "fire.extinguisher", titulo: "Sin bienes cargados", texto: "Matafuegos, ascensores, bombas: con su próximo service, te avisamos antes.",
                            accion: estado.escribe ? ("Sumar un bien", { editando = BienAPI(id: "", nombre: "", categoria: "matafuego", cantidad: 1, estado: "ok") }) : nil)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(lista) { b in
                Button { editando = b } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(b.nombre + (b.cantidad.map { $0 > 1 ? " × \($0)" : "" } ?? "")).estilo(.filaLista).foregroundStyle(C.texto)
                            Text([b.ubicacion, b.proximoService.map { "service: \($0)" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        let t: Tono = b.estado == "vencido" ? .rojo : b.estado == "a_revisar" ? .oro : b.estado == "baja" ? .neutro : .verde
                        Text(BienAPI.estados.first { $0.0 == b.estado }?.1 ?? "En orden").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(t.tinta)
                            .padding(.horizontal, 9).frame(height: 24).background(t.fondo, in: Capsule())
                    }
                }
                .swipeActions { if estado.escribe { Button("Borrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/consorcios/\(consorcio)/bienes/\(b.id)"); await cargar() } catch { estado.avisar(error) } } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Bienes")
        .toolbar { if estado.escribe { Button { editando = BienAPI(id: "", nombre: "", categoria: "matafuego", cantidad: 1, estado: "ok") } label: { Image(systemName: "plus") }.accessibilityLabel("Sumar") } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { b in
            NavigationStack { FormBien(b: b) { x in Task { await guardar(x) } } }
        }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/consorcios/\(consorcio)/bienes")) ?? [] }

    private func guardar(_ b: BienAPI) async {
        struct C: Encodable { var nombre: String; var categoria: String; var ubicacion: String?; var cantidad: Int; var estado: String; var proximoService: String?; var responsable: String?; var notas: String? }
        let c = C(nombre: b.nombre, categoria: b.categoria ?? "otro", ubicacion: b.ubicacion?.nonEmpty, cantidad: b.cantidad ?? 1, estado: b.estado ?? "ok",
                  proximoService: b.proximoService, responsable: b.responsable?.nonEmpty, notas: b.notas?.nonEmpty)
        do {
            if b.id.isEmpty { try await estado.api.hacer("POST", "/v1/consorcios/\(consorcio)/bienes", c) } else { try await estado.api.hacer("PUT", "/v1/consorcios/\(consorcio)/bienes/\(b.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormBien: View {
    @Environment(\.dismiss) private var cerrar
    @State var b: BienAPI
    var guardar: (BienAPI) -> Void
    var body: some View {
        Form {
            TextField("Nombre", text: $b.nombre)
            Picker("Categoría", selection: Binding(get: { b.categoria ?? "otro" }, set: { b.categoria = $0 })) { ForEach(BienAPI.categorias, id: \.0) { Text($0.1).tag($0.0) } }
            TextField("Dónde está", text: Binding(get: { b.ubicacion ?? "" }, set: { b.ubicacion = $0 }))
            Stepper("Cantidad: \(b.cantidad ?? 1)", value: Binding(get: { b.cantidad ?? 1 }, set: { b.cantidad = $0 }), in: 1...500)
            Picker("Estado", selection: Binding(get: { b.estado ?? "ok" }, set: { b.estado = $0 })) { ForEach(BienAPI.estados, id: \.0) { Text($0.1).tag($0.0) } }
            DatePicker("Próximo service", selection: Binding(get: { b.proximoService.flatMap(Fecha.dia) ?? Date() }, set: { b.proximoService = Formato.diaISO($0) }), displayedComponents: .date)
            TextField("Responsable", text: Binding(get: { b.responsable ?? "" }, set: { b.responsable = $0 }))
            TextField("Notas", text: Binding(get: { b.notas ?? "" }, set: { b.notas = $0 }), axis: .vertical)
        }
        .navigationTitle(b.id.isEmpty ? "Bien nuevo" : b.nombre).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(b); cerrar() }.disabled(b.nombre.isEmpty) }
        }
    }
}
