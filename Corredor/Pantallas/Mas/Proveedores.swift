import AuthenticationServices
import SwiftUI

/// 44 Proveedores (plomeros, electricistas…): los comparten todos los consorcios, cada uno con los
/// trabajos que hizo. Cargan y corrigen el dueño y los agentes; borra el dueño; el lector sólo mira.
struct Proveedores: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Prov]?
    @State private var error: ErrorApi?
    @State private var editando: Prov?

    /// `GET /v1/proveedores` (consorcios.Proveedor).
    struct Prov: Codable, Identifiable, Hashable {
        var id: String; var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String?
        var trabajos: Int?; var edificios: Int?
    }

    /// Rubro → texto, ícono y color (los del 44: plomería azul, electricidad oro, el resto gris).
    static let rubros: [(String, String, String, Color)] = [
        ("plomeria", "Plomería", "drop", C.azulTinta), ("electricidad", "Electricidad", "bolt", C.oroTinta),
        ("gas", "Gas", "flame", C.errorTinta), ("herreria", "Herrería", "door.garage.closed", C.texto2),
        ("pintura", "Pintura", "paintbrush", C.violetaTinta), ("limpieza", "Limpieza", "sparkles", C.okTinta),
        ("ascensores", "Ascensores", "arrow.up.arrow.down.square", C.texto2), ("cerrajeria", "Cerrajería", "key", C.texto2),
        ("albanileria", "Albañilería", "hammer", C.texto2), ("jardineria", "Jardinería", "leaf", C.okTinta),
        ("otro", "Otro", "wrench.and.screwdriver", C.texto2),
    ]

    static func rubro(_ p: Prov) -> (String, String, String, Color) {
        rubros.first { $0.0 == (p.rubro ?? "").lowercased() } ?? rubros[rubros.count - 1]
    }

    /// «falta CUIT» (en rojo), «sin trabajos todavía» o «8 trabajos · 2 edificios».
    static func detalle(_ p: Prov) -> (String, Bool) {
        if p.cuit?.nonEmpty == nil { return ("falta CUIT", true) }
        let t = p.trabajos ?? 0
        if t == 0 { return ("sin trabajos todavía", false) }
        let e = p.edificios ?? 0
        return (Formato.cantidad(t, "trabajo", "trabajos") + (e > 1 ? " · \(e) edificios" : ""), false)
    }

    var body: some View {
        Group {
            if let lista {
                if lista.isEmpty { vacio } else { listado(lista) }
            } else if let error {
                EstadoError(que: "los proveedores", error: error) { Task { await cargar() } }
            } else { EsqueletoFilas(filas: 6).padding(16).frame(maxHeight: .infinity, alignment: .top) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoApp())
        .pantallaApilada("Proveedores")
        .toolbar { if estado.escribe { Button { editando = Prov(id: "", nombre: "") } label: { Label("Nuevo", systemImage: "plus") } } }
        .task(id: estado.version) { await cargar() }
        .sheet(item: $editando) { p in FormProveedor(p: p) { await cargar() } }
    }

    private var vacio: some View {
        let accion: (String, () -> Void)? = estado.escribe ? ("Cargar el primero", { editando = Prov(id: "", nombre: "") }) : nil
        return VStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach([("Plomería Rossi", "8 trabajos · 2 edificios"), ("Electricidad Peralta", "5 trabajos")], id: \.0) { t, d in
                    HStack { Text(t).estilo(.filaLista); Spacer(); Text(d).estilo(.footnote) }
                        .foregroundStyle(C.texto3).padding(14)
                }
            }
            .tarjeta().opacity(0.5).padding(.horizontal, 16)
            EstadoVacio(icono: "wrench.and.screwdriver", titulo: "Todavía no cargaste proveedores",
                        texto: "Plomeros, electricistas, cerrajeros: los cargás una vez y los usás en todos los consorcios.",
                        accion: accion)
        }
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func listado(_ l: [Prov]) -> some View {
        List {
            Section {
                Text("Los comparten todos tus consorcios. Cada uno, con los trabajos que hizo.").estilo(.footnote).foregroundStyle(C.texto2)
            }
            .listRowBackground(Color.clear)
            ForEach(l) { p in
                let r = Self.rubro(p)
                let d = Self.detalle(p)
                HStack(spacing: 12) {
                    Button { editando = p } label: {
                        HStack(spacing: 12) {
                            IconoFila(icono: r.2, color: r.3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                Text(d.0).estilo(.footnote).foregroundStyle(d.1 ? C.errorTinta : C.texto2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver \(p.nombre)")
                    if p.telefono?.nonEmpty != nil {
                        Button { Afuera.whatsapp(p.telefono) } label: { Image("LogoWhatsApp").resizable().frame(width: 22, height: 22).frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Escribirle a \(p.nombre) por WhatsApp")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await cargar() }
    }

    private func cargar() async {
        do {
            lista = try await estado.api.get("/v1/proveedores", query: [.init(name: "limite", value: "500")])
            error = nil
        } catch let e as ErrorApi { if lista == nil { error = e } } catch {}
    }
}

/// La hoja de un proveedor (nuevo o editar): nombre, rubro, CUIT, teléfono, mail y notas, con el error de
/// cada campo. El lector la ve bloqueada; borrar es del dueño y se confirma.
struct FormProveedor: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State var p: Proveedores.Prov
    var alGuardar: () async -> Void
    @State private var campos: [String: String] = [:]
    @State private var guardando = false
    @State private var confirmar: Confirmacion?

    private var nuevo: Bool { p.id.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !nuevo { Section { Text(Proveedores.detalle(p).0).estilo(.footnote).foregroundStyle(Proveedores.detalle(p).1 ? C.errorTinta : C.texto2) } }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Nombre", text: $p.nombre).onChange(of: p.nombre) { _, v in if v.count > 160 { p.nombre = String(v.prefix(160)) } }
                        ErrorDeCampo(texto: campos["nombre"])
                    }
                    Picker("Rubro", selection: Binding(get: { (p.rubro ?? "").lowercased() }, set: { p.rubro = $0 })) {
                        Text("Sin rubro").tag("")
                        ForEach(Proveedores.rubros, id: \.0) { r in Text(r.1).tag(r.0) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("CUIT", text: texto(\.cuit), prompt: Text("20-12345678-9")).keyboardType(.numbersAndPunctuation)
                        Text("Para los comprobantes de las expensas.").estilo(.footnote).foregroundStyle(C.texto3)
                        ErrorDeCampo(texto: campos["cuit"])
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Teléfono o WhatsApp", text: texto(\.telefono)).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        ErrorDeCampo(texto: campos["telefono"])
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Mail", text: texto(\.email)).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        ErrorDeCampo(texto: campos["email"])
                    }
                    TextField("Notas", text: texto(\.notas), axis: .vertical).lineLimit(3...6)
                }
                .disabled(!estado.escribe)
                if !nuevo, estado.esDuenio {
                    Section {
                        Button("Borrar", role: .destructive) {
                            confirmar = Confirmacion(titulo: "¿Borrás a \(p.nombre)?", texto: "Los trabajos y gastos que ya tiene quedan, pero sin proveedor. No vuelve a la lista.",
                                                     boton: "Borrar") { Task { await borrar() } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(FondoApp())
            .navigationTitle(nuevo ? "Proveedor nuevo" : p.nombre).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                if estado.escribe {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await guardar() } } label: { if guardando { ProgressView() } else { Text("Guardar") } }.disabled(guardando)
                    }
                }
            }
            .confirmacion($confirmar)
        }
    }

    private func texto(_ k: WritableKeyPath<Proveedores.Prov, String?>) -> Binding<String> {
        Binding(get: { p[keyPath: k] ?? "" }, set: { p[keyPath: k] = $0 })
    }

    private func guardar() async {
        campos = [:]
        let nombre = p.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if nombre.isEmpty { campos["nombre"] = "Poné el nombre del proveedor."; return }
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var nombre: String; var cuit: String?; var rubro: String?; var telefono: String?; var email: String?; var notas: String? }
        func n(_ s: String?) -> String? { s?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
        let c = Cuerpo(nombre: nombre, cuit: n(p.cuit), rubro: n(p.rubro), telefono: n(p.telefono), email: n(p.email), notas: n(p.notas))
        do {
            if nuevo { try await estado.api.pedirConCampos("POST", "/v1/proveedores", c, envio: UUID().uuidString) }
            else { try await estado.api.pedirConCampos("PUT", "/v1/proveedores/\(p.id)", c) }
            estado.avisar(nuevo ? "Proveedor cargado" : "Proveedor guardado")
            await alGuardar()
            cerrar()
        } catch { campos = estado.camposDe(error) }
    }

    private func borrar() async {
        do {
            try await estado.api.hacer("DELETE", "/v1/proveedores/\(p.id)")
            estado.avisar("\(p.nombre) ya no está en tus proveedores")
            await alGuardar()
            cerrar()
        } catch { estado.avisar(error) }
    }
}
