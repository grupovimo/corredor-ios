import AVFoundation
import Speech
import SwiftUI

// Lo común de inventarios, actas y devolución (web: lib/propiedades/inv-estados.ts): los destinos
// propios, los modelos chicos que se leen de otras áreas, la comparación de la devolución con la
// entrega y la nota de voz por ítem.

/// La recorrida forzada a un modo (web: /inventarios/<id>?tipo=entrega|devolucion).
struct ARecorrida: Hashable { var id: String; var tipo: String }
/// La devolución comparada con la entrega (web: /inventarios/<id>/devolucion).
struct ADevolucion: Hashable { var id: String }

extension View {
    /// Los destinos nuevos de inventarios (se encadena en `destinosCobranzas()`).
    func destinosInventarios() -> some View {
        self
            .navigationDestination(for: ARecorrida.self) { r in Inventario(propiedad: r.id, tipoPedido: r.tipo) }
            .navigationDestination(for: ADevolucion.self) { d in Devolucion(propiedad: d.id) }
    }
}

/// Un contacto, con lo que necesitan el acta y la devolución (GET /v1/contactos/{id}).
struct ContactoActa: Codable, Hashable {
    var id: String
    var nombre: String
    var telefono: String?
}

/// La inmobiliaria con sus datos legales (GET /v1/inmobiliaria): el membrete del acta lleva la matrícula.
struct InmobiliariaActa: Codable {
    struct Legales: Codable { var matricula: String?; var colegio: String?; var corredorResponsable: String? }
    var nombre: String?
    var legales: Legales?

    /// «Mat. CUCICBA 1234», como la web.
    var matricula: String? {
        guard let m = legales?.matricula?.nonEmpty else { return nil }
        return ["Mat.", legales?.colegio?.nonEmpty, m].compactMap { $0 }.joined(separator: " ")
    }
}

/// Un link para firmar desde el celular (GET …/actas/{acta}/links; sin el token).
struct LinkFirma: Codable, Identifiable, Hashable {
    var id: String
    var parte: String
    var venceEn: Date
    var estado: String
    var url: String?
}

/// Lo elegido en «¿Quién paga?» para un cambio (GET/PUT …/actas/{entrada}/devolucion).
struct DecisionDevolucion: Codable, Hashable {
    var quien: String
    var importe: Double?
}

enum Inv {
    /// Nombre de cada estado (NOMBRE_ESTADO de la web).
    static func nombre(_ e: String) -> String {
        ItemInventario.estados.first { $0.0 == e }?.1 ?? e
    }

    /// Los tres botones de la recorrida: nuevo y muy bueno cuentan como «Bueno».
    static func grupo(_ e: String) -> String { e == "regular" || e == "malo" ? e : "bueno" }

    static let rango: [String: Int] = ["nuevo": 4, "muy_bueno": 3, "bueno": 2, "regular": 1, "malo": 0]

    /// «12/03/2026», como `fechaNumerica` de la web.
    static func numerica(_ s: String?) -> String {
        let p = (s ?? "").prefix(10).split(separator: "-")
        guard p.count == 3 else { return s ?? "" }
        return "\(p[2])/\(p[1])/\(p[0])"
    }

    static func numerica(_ f: Date) -> String {
        let c = Formato.calendario.dateComponents([.day, .month, .year], from: f)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    static func primerNombre(_ n: String?) -> String { n?.split(separator: " ").first.map(String.init) ?? "" }

    /// «Cocina · mesada de granito».
    static func rotulo(_ ambiente: String, _ descripcion: String) -> String {
        let d = descripcion.prefix(1).lowercased() + descripcion.dropFirst()
        return "\(ambiente) · \(d)"
    }

    static func ambientes(_ items: [String]) -> [String] {
        var vistos: [String] = []
        for a in items where !vistos.contains(a) { vistos.append(a) }
        return vistos
    }

    /// Lo que cambió entre la entrega y hoy (`comparar` de la web).
    struct Cambio: Identifiable, Hashable {
        var clave: String
        var ambiente: String
        var descripcion: String
        var entrega: Acta.Item?
        var hoy: Acta.Item?
        /// Bajó un escalón hasta «regular»: lo normal es que sea desgaste por uso.
        var desgaste: Bool
        /// Empeoró (o falta / bajó la cantidad): lo que se discute.
        var empeoro: Bool
        var id: String { clave }
    }

    static func clave(_ ambiente: String, _ descripcion: String) -> String {
        "\(ambiente.trimmingCharacters(in: .whitespaces).lowercased())|\(descripcion.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    static func comparar(_ entrega: [Acta.Item], _ hoy: [Acta.Item]) -> [Cambio] {
        var antes: [(String, Acta.Item)] = []
        for i in entrega { let k = clave(i.ambiente, i.descripcion); if !antes.contains(where: { $0.0 == k }) { antes.append((k, i)) } }
        var ahora: [String: Acta.Item] = [:]
        var ordenAhora: [String] = []
        for i in hoy { let k = clave(i.ambiente, i.descripcion); if ahora[k] == nil { ahora[k] = i; ordenAhora.append(k) } }
        var out: [Cambio] = []
        for (k, a) in antes {
            let b = ahora[k]
            if let b, b.estado == a.estado, (b.cantidad ?? 1) == (a.cantidad ?? 1) { continue }
            let caida = b.map { (rango[a.estado] ?? 2) - (rango[$0.estado] ?? 2) } ?? 99
            let desgaste = b != nil && (b?.cantidad ?? 1) == (a.cantidad ?? 1) && caida == 1 && b?.estado == "regular"
            let empeoro = b == nil || caida > 0 || (b?.cantidad ?? 1) < (a.cantidad ?? 1)
            out.append(Cambio(clave: k, ambiente: a.ambiente, descripcion: a.descripcion, entrega: a, hoy: b, desgaste: desgaste, empeoro: empeoro))
        }
        let claves = Set(antes.map(\.0))
        for k in ordenAhora where !claves.contains(k) {
            if let b = ahora[k] {
                out.append(Cambio(clave: k, ambiente: b.ambiente, descripcion: b.descripcion, entrega: nil, hoy: b, desgaste: false, empeoro: false))
            }
        }
        func peso(_ c: Cambio) -> Int { c.empeoro ? (c.desgaste ? 1 : 2) : 0 }
        // Lo que más empeoró, primero (estable, como el sort de JS).
        return out.enumerated().sorted { x, y in
            peso(x.element) != peso(y.element) ? peso(x.element) > peso(y.element) : x.offset < y.offset
        }.map(\.element)
    }

    /// Un ítem vivo como queda en un acta.
    static func comoActa(_ i: ItemInventario) -> Acta.Item {
        Acta.Item(ambiente: i.ambiente, descripcion: i.descripcion, cantidad: i.cantidad ?? 1, estado: i.estado, notas: i.notas, fotos: i.fotos, fotosUrl: i.fotosUrl)
    }

    /// Un error en el aviso de abajo, con «Reintentar».
    @MainActor static func errorConReintento(_ estado: Estado, _ e: Error, _ reintentar: @escaping () -> Void) {
        estado.avisar(e)
        if estado.aviso?.ok == false { estado.aviso?.accion = ("Reintentar", reintentar) }
    }
}

/// La nota de voz de un ítem (web: inv-voz.svelte.ts): se graba el audio y a la vez se transcribe en
/// el iPhone; al terminar devuelve el texto, el archivo .m4a y los segundos.
@Observable
@MainActor
final class NotaDeVoz {
    var grabando = false
    var texto = ""
    var segundos = 0
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var archivo: AVAudioFile?
    private var url: URL?
    private var desde = Date()
    private var reloj: Task<Void, Never>?
    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-AR"))

    /// Arranca a grabar. Devuelve el error para mostrar si no se pudo.
    func empezar() async -> String? {
        guard !grabando else { return nil }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return "No hay permiso para usar el micrófono." }
        let voz: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        let sesion = AVAudioSession.sharedInstance()
        do {
            try sesion.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return "No encontramos un micrófono." }
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("nota-\(UUID().uuidString).m4a")
        let f = try? AVAudioFile(forWriting: u, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: formato.sampleRate,
                                                           AVNumberOfChannelsKey: formato.channelCount, AVEncoderBitRateKey: 32000])
        archivo = f
        url = f == nil ? nil : u
        var p: SFSpeechAudioBufferRecognitionRequest?
        if voz == .authorized, reconocedor?.isAvailable == true {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            p = r
        }
        pedido = p
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
            p?.append(buffer)
            try? f?.write(from: buffer)
        }
        motor.prepare()
        do { try motor.start() } catch {
            entrada.removeTap(onBus: 0)
            return "No encontramos un micrófono."
        }
        texto = ""
        segundos = 0
        desde = Date()
        grabando = true
        Haptico.impacto()
        if let p {
            tarea = reconocedor?.recognitionTask(with: p) { r, _ in
                Task { @MainActor in if let r { self.texto = r.bestTranscription.formattedString } }
            }
        }
        reloj = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self.segundos = Int(Date().timeIntervalSince(self.desde))
            }
        }
        return nil
    }

    /// Termina y devuelve lo grabado (el audio sólo si duró algo).
    func terminar() async -> (texto: String, audio: URL?, segundos: Int) {
        guard grabando else { return ("", nil, 0) }
        motor.stop()
        motor.inputNode.removeTap(onBus: 0)
        pedido?.endAudio()
        reloj?.cancel()
        grabando = false
        let s = max(1, Int(Date().timeIntervalSince(desde).rounded()))
        // Un momento para que llegue lo último de la transcripción.
        try? await Task.sleep(for: .milliseconds(400))
        tarea?.cancel()
        archivo = nil
        let dur = Date().timeIntervalSince(desde)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (texto.trimmingCharacters(in: .whitespacesAndNewlines), dur > 1.2 ? url : nil, s)
    }

    /// «0:12».
    static func duracion(_ s: Int) -> String { "\(s / 60):\(String(format: "%02d", s % 60))" }
}
