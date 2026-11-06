import AuthenticationServices
import SwiftUI

/// Objetivos del mes: los de cada persona con su avance; el dueño los carga.
struct Objetivos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [Objetivo] = []
    @State private var nuevo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if lista.isEmpty { EstadoVacio(icono: "flag", titulo: "Sin objetivos este mes", texto: "Ponele una meta a cada persona y seguí el avance.", accion: estado.esDuenio ? ("Cargar objetivo", { nuevo = true }) : nil).padding(.top, 40) }
                ForEach(lista) { o in
                    TarjetaObjetivo(o: o)
                        .overlay(alignment: .topTrailing) {
                            if let n = o.agenteNombre { Text(n).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2).padding(10) }
                        }
                        .contextMenu { if estado.esDuenio { Button("Borrar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/objetivos/\(o.id)"); await cargar() } catch { estado.avisar(error) } } } } }
                }
            }
            .padding(16)
        }
        .pantallaApilada("Objetivos")
        .toolbar { if estado.esDuenio { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo objetivo") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nuevo) { NuevoObjetivo().presentationDetents([.medium]) }
    }

    private func cargar() async { lista = (try? await estado.api.get("/v1/objetivos")) ?? [] }
}

struct NuevoObjetivo: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var equipo: [Miembro] = []
    @State private var quien = ""
    @State private var metrica = "operaciones_cerradas"
    @State private var meta = 5.0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quién", selection: $quien) { Text("Toda la inmobiliaria").tag(""); ForEach(equipo) { Text($0.completo).tag($0.usuarioId) } }
                Picker("Qué", selection: $metrica) { ForEach(Objetivo.metricas.keys.sorted(), id: \.self) { Text(Objetivo.metricas[$0]!.1.capitalized).tag($0) } }
                Stepper("Meta: \(Int(meta))", value: $meta, in: 1...1000)
            }
            .navigationTitle("Objetivo del mes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cargar") {
                        Task {
                            let cal = Calendar.current
                            let ini = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
                            let fin = cal.date(byAdding: DateComponents(month: 1, day: -1), to: ini)!
                            struct Cuerpo: Encodable { var agenteId: String?; var metrica: String; var meta: Double; var desde: String; var hasta: String }
                            do {
                                try await estado.api.hacer("POST", "/v1/objetivos", Cuerpo(agenteId: quien.nonEmpty, metrica: metrica, meta: meta, desde: Formato.diaISO(ini), hasta: Formato.diaISO(fin)))
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
            .task { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
        }
    }
}
