import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Corredor en tu IA

/// Corredor en tu IA: las IA conectadas (Claude, ChatGPT), qué pueden hacer y el link para conectar.
struct CorredorEnTuIA: View {
    @Environment(Estado.self) private var estado
    @State private var conexiones: [Conexion] = []
    @State private var ajustes: Ajustes?
    /// `GET /v1/ia/ajustes`: lo que eligió la dueña, el link para pegar y el aviso de la Ley 25.326 (texto).
    struct Ajustes: Codable { var habilitado: Bool?; var agendar: Bool?; var mover: Bool?; var url: String?; var aviso: String? }
    /// `GET /v1/ia/conexiones`: de quién es, con qué asistente y qué permisos le dio.
    struct Conexion: Codable, Identifiable {
        var id: String
        var usuarioId: String?
        var personaNombre: String?
        var rol: String?
        var cliente: String?
        var permisos: [String]?
        var creadaEn: Date?
        var usadaEn: Date?
    }

    var body: some View {
        Form {
            Section(footer: Text("Agregá Corredor como conector en Claude o ChatGPT con este link. Lo que tu IA quiera cambiar te llega a Revisión.")) {
                if let u = ajustes?.url {
                    HStack { Text(u).font(.footnote.monospaced()); Spacer(); Button { UIPasteboard.general.string = u; estado.avisar("Link copiado") } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copiar el link") }
                }
            }
            if estado.esDuenio, ajustes != nil {
                Section("Qué puede hacer") {
                    Toggle("Prendido", isOn: bind(\.habilitado))
                    Toggle("Mover operaciones sin pedir permiso", isOn: bind(\.mover))
                    Toggle("Agendar visitas sin pedir permiso", isOn: bind(\.agendar))
                }
            }
            Section("Conectadas") {
                if conexiones.isEmpty { Text("Todavía no conectaste ninguna.").foregroundStyle(C.texto2) }
                ForEach(conexiones) { c in
                    VStack(alignment: .leading) {
                        Text(c.cliente ?? "IA").estilo(.filaLista)
                        Text(Self.detalle(c)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions { Button("Desconectar", role: .destructive) { Task { await desconectar(c) } } }
                }
            }
            if let a = ajustes?.aviso?.nonEmpty {
                Section { Text(a).estilo(.footnote).foregroundStyle(C.texto2) }
            }
            Section { Button("Revisión de la IA") { estado.abrir(ASeccion(clave: "revision")) } }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Corredor en tu IA")
        .task(id: estado.version) { await cargar() }
    }

    /// «Martín (agente) · leer + borradores + agendar · usada hace 2 h».
    static func detalle(_ c: Conexion) -> String {
        var partes: [String] = []
        if let n = c.personaNombre?.nonEmpty { partes.append(c.rol.map { "\(n) (\(ElegirInmobiliaria.rol($0).lowercased()))" } ?? n) }
        if let p = c.permisos, !p.isEmpty { partes.append(p.joined(separator: " + ")) }
        partes.append(c.usadaEn.map { "usada \(Formato.hace($0))" } ?? "todavía sin usar")
        return partes.joined(separator: " · ")
    }

    /// Cada interruptor guarda al toque; si la API dice que no, vuelve a como estaba.
    private func bind(_ k: WritableKeyPath<Ajustes, Bool?>) -> Binding<Bool> {
        Binding(get: { ajustes?[keyPath: k] ?? false }, set: { v in
            guard let antes = ajustes else { return }
            ajustes?[keyPath: k] = v
            Task { await guardar(antes: antes) }
        })
    }

    private func guardar(antes: Ajustes) async {
        guard let a = ajustes else { return }
        // El PUT lleva sólo lo que se elige (la URL y el aviso los pone la API).
        struct Cuerpo: Encodable { var habilitado: Bool; var agendar: Bool; var mover: Bool }
        do {
            let nuevos: Ajustes = try await estado.api.enviar("PUT", "/v1/ia/ajustes", Cuerpo(habilitado: a.habilitado ?? false, agendar: a.agendar ?? false, mover: a.mover ?? false))
            ajustes = nuevos
        } catch {
            ajustes = antes
            estado.avisar(error)
        }
    }

    private func desconectar(_ c: Conexion) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/ia/conexiones/\(c.id)")
            estado.avisar("Desconectaste \(c.cliente ?? "la IA")")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func cargar() async {
        ajustes = try? await estado.api.get("/v1/ia/ajustes")
        if let l: [Conexion] = try? await estado.api.get("/v1/ia/conexiones") { conexiones = l }
    }
}
