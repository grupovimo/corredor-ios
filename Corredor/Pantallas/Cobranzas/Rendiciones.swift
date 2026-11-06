import AuthenticationServices
import SwiftUI

/// Las rendiciones listas para hacer este mes: los alquileres con el mes cobrado que todavía no tienen
/// rendición. Como la web, cada una lleva al contrato; «Armar» la crea y abre (el dueño la emite).
struct RendicionesListas: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Lista] = []
    @State private var armando: String?

    /// `GET /v1/rendiciones/listas`: un cobro sin rendir (no es una rendición todavía: no tiene id).
    struct Lista: Codable, Identifiable, Hashable {
        var contratoId: String
        var periodo: String
        var propiedadTitulo: String?
        var propietarioNombre: String?
        var cobrado: Double?
        var moneda: String?
        var id: String { contratoId + periodo }
        /// «AAAA-MM» (la API manda el primer día del mes).
        var mes: String { String(periodo.prefix(7)) }
    }

    var body: some View {
        List {
            if lista.isEmpty { Text("Se arman solas con lo cobrado. Acá aparecen cuando están listas.").foregroundStyle(C.texto2) }
            ForEach(lista) { r in
                Button { estado.abrir(AFichaContrato(id: r.contratoId)) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.propiedadTitulo ?? "Contrato").estilo(.filaLista).foregroundStyle(C.texto)
                            Text([r.propietarioNombre, Formato.mayuscula(ReciboVista.mes(r.mes))].compactMap { $0 }.joined(separator: " · "))
                                .estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Text(Formato.plata(r.cobrado ?? 0, r.moneda ?? "ARS")).fontWeight(.semibold).foregroundStyle(C.texto)
                    }
                }
                .disabled(armando != nil)
                .swipeActions { if estado.escribe { Button("Armar") { Task { await armar(r) } }.tint(C.accion) } }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Rendiciones")
        .refreshable { await cargar() }
        .task(id: estado.version) { await cargar() }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/rendiciones/listas")) ?? [] }

    /// Arma la rendición de ese mes y la abre.
    private func armar(_ r: Lista) async {
        armando = r.id
        defer { armando = nil }
        struct Cuerpo: Encodable { var periodo: String }
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/contratos/\(r.contratoId)/rendiciones", Cuerpo(periodo: r.mes))
            estado.abrir(ARendicion(contrato: r.contratoId, id: n.id))
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}
