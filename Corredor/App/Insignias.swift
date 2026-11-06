import Foundation
import Observation

/// Los números de la barra y de «Más» (lib/ui/shell/insignias.svelte.ts): mensajes y preguntas sin
/// responder, cobros atrasados, avisos y quiénes del equipo están en la calle, en un solo pedido liviano
/// (GET /v1/panel/insignias). Se piden al entrar, con cada cambio en vivo, al volver a la app y cada
/// minuto (las visitas empiezan y terminan solas).
@Observable
@MainActor
final class Insignias {
    static let compartidas = Insignias()

    struct Persona: Decodable, Hashable, Identifiable {
        var id: String
        var nombre: String
        var foto: String?
    }

    struct Respuesta: Decodable {
        var mensajes: Int?
        var preguntas: Int?
        var bandeja: Int?
        var cobranzas: Int?
        var avisos: Int?
        var paraHacer: Int?
        var enLaCalle: [Persona]?
    }

    var mensajes = 0
    var preguntas = 0
    var bandeja = 0
    var cobranzas = 0
    var avisos = 0
    var paraHacer = 0
    var enLaCalle: [Persona] = []
    /// La última vez que la API respondió (para «Todo guardado · hace X»).
    var guardadoEn: Date?
    /// Sin señal la última vez que se pidió.
    var sinRed = false

    func refrescar(_ estado: Estado) async {
        guard estado.fase == .adentro else { return }
        do {
            let r: Respuesta = try await estado.api.get("/v1/panel/insignias")
            mensajes = r.mensajes ?? 0
            preguntas = r.preguntas ?? 0
            bandeja = r.bandeja ?? (mensajes + preguntas)
            cobranzas = r.cobranzas ?? 0
            avisos = r.avisos ?? 0
            paraHacer = r.paraHacer ?? 0
            enLaCalle = r.enLaCalle ?? []
            guardadoEn = Date()
            sinRed = false
            estado.sinLeer = bandeja
            estado.avisosPendientes = avisos
        } catch let e as ErrorApi {
            sinRed = e.sinConexion
        } catch {}
    }

    func olvidar() {
        mensajes = 0; preguntas = 0; bandeja = 0; cobranzas = 0; avisos = 0; paraHacer = 0
        enLaCalle = []
        guardadoEn = nil
    }
}
