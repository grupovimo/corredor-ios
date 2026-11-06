import AuthenticationServices
import SwiftUI

// MARK: - Configuración

/// Inmobiliaria: nombre, zona horaria, CBU o alias, y los datos legales del pie y los recibos.
struct ConfigInmobiliaria: View {
    @Environment(Estado.self) private var estado
    @State private var nombre = ""
    @State private var cbu = ""
    @State private var zona = "America/Argentina/Buenos_Aires"
    @State private var legales: [String: String] = [:]
    @State private var guardando = false
    @State private var rubrosTexto = ""

    private static let camposLegales = [("razonSocial", "Razón social"), ("cuit", "CUIT"), ("corredorResponsable", "Corredor responsable"), ("matricula", "Matrícula"), ("colegio", "Colegio")]

    var body: some View {
        Form {
            Section("Datos") {
                TextField("Nombre de la inmobiliaria", text: $nombre)
                TextField("CBU o alias para cobrar", text: $cbu).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Zona horaria", selection: $zona) {
                    ForEach(["America/Argentina/Buenos_Aires", "America/Argentina/Cordoba", "America/Argentina/Mendoza", "America/Argentina/Salta", "America/Argentina/Ushuaia"], id: \.self) {
                        Text($0.replacingOccurrences(of: "America/Argentina/", with: "").replacingOccurrences(of: "_", with: " ")).tag($0)
                    }
                }
            }
            Section(header: Text("Datos legales"), footer: Text("Van en el pie de tu web y en los recibos. En CABA y Provincia, la matrícula es obligatoria.")) {
                ForEach(Self.camposLegales, id: \.0) { k, n in
                    TextField(n, text: Binding(get: { legales[k] ?? "" }, set: { legales[k] = $0 }))
                        .keyboardType(k == "cuit" || k == "matricula" ? .numbersAndPunctuation : .default)
                }
            }
            Section(header: Text("Qué hacen y dónde"), footer: Text("Así la app te muestra sólo lo que usás.")) {
                Button { estado.altaAbierta = PasoAlta(clave: "rubros") } label: {
                    LabeledContent("Rubros y zonas", value: rubrosTexto)
                }
            }
            Section { Button("Mi web: logo, colores y dominio") { estado.abrir(ASeccion(clave: "web")) } }
        }
        .disabled(!estado.esDuenio)
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Inmobiliaria")
        .toolbar { if estado.esDuenio { Button("Guardar") { Task { await guardar() } }.disabled(guardando) } }
        .task {
            struct P: Decodable { var rubros: [String]?; var zonas: [String]? }
            struct I: Decodable { var nombre: String?; var cbu: String?; var zonaHoraria: String?; var legales: [String: String?]?; var perfil: P? }
            if let i: I = try? await estado.api.get("/v1/inmobiliaria") {
                let nombres = ["ventas": "Ventas", "alquileres": "Alquileres", "temporada": "Temporada", "emprendimientos": "Emprendimientos", "consorcios": "Consorcios"]
                let r = (i.perfil?.rubros ?? []).compactMap { nombres[$0] }
                rubrosTexto = r.isEmpty ? "Sin elegir" : r.joined(separator: ", ")
                nombre = i.nombre ?? ""
                cbu = i.cbu ?? ""
                zona = i.zonaHoraria ?? zona
                legales = (i.legales ?? [:]).compactMapValues { $0 }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable { var nombre: String; var cbu: String; var zonaHoraria: String; var legales: [String: String] }
        do {
            try await estado.api.hacer("PATCH", "/v1/inmobiliaria", Cuerpo(nombre: nombre, cbu: cbu.trimmingCharacters(in: .whitespaces), zonaHoraria: zona, legales: legales))
            estado.avisar("Guardado")
        } catch { estado.avisar(error) }
    }
}
