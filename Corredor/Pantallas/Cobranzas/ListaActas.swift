import AuthenticationServices
import SwiftUI

/// Todas las actas de entrega y devolución.
struct ListaActas: View {
    @Environment(Estado.self) private var estado
    @State private var actas: [Acta] = []
    @State private var elegir = false

    var body: some View {
        List {
            if actas.isEmpty { Text("Hacé la recorrida de una propiedad y firmala acá mismo.").foregroundStyle(C.texto2) }
            ForEach(actas) { a in
                Button { if let p = a.propiedadId { estado.abrir(AFirmas(id: "\(p)/\(a.id)")) } } label: {
                    VStack(alignment: .leading) {
                        Text(a.propiedadTitulo ?? "Acta").estilo(.filaLista).foregroundStyle(C.texto)
                        Text("\(a.tipoTexto) · \(a.fecha.flatMap(Fecha.dia).map { Formato.diaCompleto($0) } ?? "") · \(a.firmas?.count ?? 0) de 3 firmas").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Actas de entrega")
        .toolbar { if estado.escribe { Button { elegir = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva recorrida") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $elegir) { ElegirPropiedad { estado.abrir(AInventario(id: $0.id)) } }
    }

    /// Como la web (/inventarios): `GET /v1/actas` exige un contrato, así que se recorren las propiedades
    /// en alquiler y temporada y se juntan sus actas, de la más nueva a la más vieja.
    private func cargar() async {
        let props: [Propiedad] = (try? await estado.api.get("/v1/propiedades", query: [.init(name: "operacion", value: "alquiler,temporario"),
                                                                                      .init(name: "orden", value: "actualizada"),
                                                                                      .init(name: "limite", value: "60")])) ?? []
        var todas: [Acta] = []
        for p in props {
            let l: [Acta] = (try? await estado.api.get("/v1/propiedades/\(p.id)/actas")) ?? []
            todas += l.map { var a = $0; if a.propiedadId == nil { a.propiedadId = p.id }; if a.propiedadTitulo == nil { a.propiedadTitulo = p.nombre }; return a }
        }
        actas = todas.sorted { ($0.fecha ?? "") > ($1.fecha ?? "") }
    }
}
