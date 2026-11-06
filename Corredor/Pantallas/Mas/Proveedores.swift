import AuthenticationServices
import SwiftUI

/// Proveedores (plomeros, electricistas…): los comparten todos los consorcios.
struct Proveedores: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Prov] = []
    @State private var editando: Prov?

    struct Prov: Codable, Identifiable, Hashable {
        var id: String; var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String?; var trabajos: Int?
    }

    var body: some View {
        List {
            if lista.isEmpty { Text("Los cargás una vez y los usás en todos los consorcios.").foregroundStyle(C.texto2) }
            ForEach(lista) { p in
                HStack {
                    Button { editando = p } label: {
                        VStack(alignment: .leading) { Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto); Text([p.rubro?.capitalized, p.trabajos.map { Formato.cantidad($0, "trabajo", "trabajos") }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                    Spacer()
                    if p.telefono != nil { Button { Afuera.whatsapp(p.telefono) } label: { Image("LogoWhatsApp").resizable().frame(width: 22, height: 22) }.buttonStyle(Presionable()) }
                }
                .swipeActions { if estado.esDuenio { Button("Borrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/proveedores/\(p.id)"); await cargar() } catch { estado.avisar(error) } } } } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Proveedores")
        .toolbar { if estado.escribe { Button { editando = Prov(id: "", nombre: "") } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo") } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { p in
            NavigationStack {
                FormProveedor(p: p) { x in Task { await guardar(x) } }
            }
        }
    }

    private func cargar() async { lista = (try? await estado.api.todas("/v1/proveedores", query: [])) ?? [] }

    private func guardar(_ p: Prov) async {
        struct Cuerpo: Encodable { var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String? }
        let c = Cuerpo(nombre: p.nombre, cuit: p.cuit?.nonEmpty, rubro: p.rubro?.nonEmpty, telefono: p.telefono?.nonEmpty, email: p.email?.nonEmpty, notas: p.notas?.nonEmpty)
        do {
            if p.id.isEmpty { try await estado.api.hacer("POST", "/v1/proveedores", c) } else { try await estado.api.hacer("PUT", "/v1/proveedores/\(p.id)", c) }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

struct FormProveedor: View {
    @Environment(\.dismiss) private var cerrar
    @State var p: Proveedores.Prov
    var guardar: (Proveedores.Prov) -> Void
    var body: some View {
        Form {
            TextField("Nombre", text: $p.nombre)
            Picker("Rubro", selection: Binding(get: { p.rubro ?? "" }, set: { p.rubro = $0 })) {
                Text("Sin rubro").tag("")
                ForEach(["plomeria", "electricidad", "gas", "herreria", "pintura", "limpieza", "ascensores", "cerrajeria", "albanileria", "jardineria", "otro"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            TextField("CUIT", text: Binding(get: { p.cuit ?? "" }, set: { p.cuit = $0 })).keyboardType(.numbersAndPunctuation)
            TextField("Teléfono o WhatsApp", text: Binding(get: { p.telefono ?? "" }, set: { p.telefono = $0 })).keyboardType(.phonePad)
            TextField("Mail", text: Binding(get: { p.email ?? "" }, set: { p.email = $0 })).keyboardType(.emailAddress)
            TextField("Notas", text: Binding(get: { p.notas ?? "" }, set: { p.notas = $0 }), axis: .vertical)
        }
        .navigationTitle(p.id.isEmpty ? "Proveedor nuevo" : p.nombre).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(p); cerrar() }.disabled(p.nombre.isEmpty) }
        }
    }
}
