import Foundation
import WidgetKit

// En vivo: el mismo stream que usa el panel web (GET /v1/eventos, Server-Sent Events). Cada cambio de
// la inmobiliaria (una consulta que entra, un cobro, una visita que se mueve, lo que carga otro del
// equipo) sube `version` y las pantallas abiertas se vuelven a pedir; el evento «avisos» trae el número
// de la campana. Corre mientras la app está adelante y adentro: Principal lo arranca con la escena
// activa y la tarea se cancela sola al ir al fondo o al salir.

extension Api {
    /// Abre el stream de eventos: las líneas del cuerpo, tal como llegan.
    func eventos() async throws -> URLSession.AsyncBytes {
        var r = URLRequest(url: base.appendingPathComponent("/v1/eventos"), timeoutInterval: 90)
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, resp) = try await http.bytes(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ErrorApi.desconocido }
        return bytes
    }
}

extension Estado {
    /// Escucha hasta que se cancela la tarea; si se corta, reconecta (3 s, y más espaciado si falla seguido).
    func escucharEnVivo() async {
        var espera: Double = 3
        while !Task.isCancelled {
            do {
                let lineas = try await api.eventos()
                // Cada evento de la API es «event: x» + una sola línea «data: {…}» (`lines` no entrega las
                // líneas vacías que los separan): se despacha al llegar el data. Los latidos («: latido») se ignoran.
                var evento = "message"
                for try await linea in lineas.lines {
                    if Task.isCancelled { break }
                    if linea.hasPrefix("event:") {
                        evento = linea.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    } else if linea.hasPrefix("data:") {
                        recibir(evento, linea.dropFirst(5).trimmingCharacters(in: .whitespaces))
                        evento = "message"
                    }
                }
                espera = 3
            } catch is CancellationError {
                break
            } catch {
                espera = min(espera * 2, 60)
            }
            enVivo = false
            try? await Task.sleep(for: .seconds(espera))
        }
        enVivo = false
    }

    private func recibir(_ evento: String, _ datos: String) {
        switch evento {
        case "listo":
            // Recién conectado (o reconectado): lo que haya cambiado mientras tanto se vuelve a pedir.
            if !enVivo { enVivo = true; cambio() }
        case "avisos":
            struct A: Decodable { var noLeidos: Int?; var paraHacer: Int? }
            if let a = try? JSONDecoder().decode(A.self, from: Data(datos.utf8)), let n = a.noLeidos { avisosPendientes = n }
            cambio()
        case "cambio", "resync":
            // La marca (logo, colores) o el alta cambiaron (se publicó la web, se completó un paso):
            // la estructura se vuelve a pedir enseguida, así el acento y el porcentaje quedan al día.
            struct C: Decodable { var tabla: String?; var op: String?; var id: String? }
            let c = try? JSONDecoder().decode(C.self, from: Data(datos.utf8))
            if evento == "resync" || c?.tabla == "inmobiliarias" {
                Task { await cargarEstructura() }
            }
            // Otra persona movió una operación: «Sofía pasó Mendoza 2350 a Visita · recién», con «Ver».
            if c?.tabla == "operaciones", c?.op == "update", let id = c?.id { Task { await avisarMovida(id) } }
            cambio()
        default:
            break
        }
    }

    /// La última movida de la operación (operaciones/[id]/movida del panel): quién la pasó y a qué etapa,
    /// si fue un cambio de etapa del último minuto y no lo hizo quien mira.
    private func avisarMovida(_ id: String) async {
        struct Evento: Decodable {
            struct Datos: Decodable { var hasta: String? }
            var tipo: String?
            var datos: Datos?
            var autorId: String?
            var autorNombre: String?
            var creadoEn: Date?
        }
        struct Op: Decodable { var titulo: String?; var propiedadTitulo: String? }
        guard let historial: [Evento] = try? await api.get("/v1/operaciones/\(id)/historial"), let e = historial.first,
              e.tipo == "etapa", let hasta = e.datos?.hasta, let autor = e.autorId, autor != usuario?.id,
              let en = e.creadoEn, Date().timeIntervalSince(en) <= 60,
              let op: Op = try? await api.get("/v1/operaciones/\(id)") else { return }
        let quien = (e.autorNombre ?? "").split(separator: " ").first.map(String.init) ?? ""
        let que = (op.propiedadTitulo ?? op.titulo ?? "").split(separator: ",").first.map(String.init) ?? ""
        sugerir("\(quien) pasó \(que) a \(Operacion.etapaTexto(hasta)) · recién", "Ver", AFichaOperacion(id: id))
    }

    /// Junta los cambios que llegan seguidos (una importación, un lote de cobros) en una sola recarga.
    private func cambio() {
        guard recargaVivo == nil else { return }
        recargaVivo = Task {
            try? await Task.sleep(for: .milliseconds(400))
            version += 1
            WidgetCenter.shared.reloadAllTimelines()
            recargaVivo = nil
        }
    }
}
