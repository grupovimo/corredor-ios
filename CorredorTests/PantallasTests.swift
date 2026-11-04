import SwiftUI
import XCTest
@testable import Corredor

/// Responde a la app con datos fijos, por ruta (lo que no está, 404).
final class ApiFalsa: URLProtocol {
    nonisolated(unsafe) static var respuestas: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let ruta = request.url?.path ?? ""
        let cuerpo = ApiFalsa.respuestas[ruta]
        let r = HTTPURLResponse(url: request.url!, statusCode: cuerpo == nil ? 404 : 200, httpVersion: nil,
                                headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((cuerpo ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Monta cada pantalla en una ventana, en Release y con la API simulada: si se cae al abrirla (como
/// el `async let` que cerraba Tu Local Web en TestFlight), salta acá y el CI imprime el reporte.
@MainActor
final class PantallasTests: XCTestCase {
    override func setUp() {
        let prop = """
        {"id": "p1", "numero": 412, "titulo": "Mendoza 2350, 5.º A", "slug": "mendoza-2350", "tipo": "departamento", "operacion": "venta",
         "estado": "disponible", "precio": 172000, "moneda": "USD", "direccion": "Mendoza 2350, 5.º A", "barrio": "Belgrano", "lat": -34.56, "lng": -58.45,
         "ambientes": 3, "banos": 1, "superficie": 74, "comodidades": ["balcón"], "fotos": [], "fotosUrl": [], "publicada": true,
         "creadaEn": "2026-11-01T10:00:00Z", "actualizadoEn": "2026-11-02T10:00:00.123456Z"}
        """
        let cita = """
        {"id": "a1", "tipo": "visita", "estado": "pendiente", "titulo": "Visita", "empiezaEn": "2026-11-12T13:00:00Z", "duracionMin": 45,
         "propiedadId": "p1", "contactoId": "c1", "contactoNombre": "Diego Fernández", "propiedadTitulo": "Arce 320, 4.º B"}
        """
        let contacto = """
        {"id": "c1", "nombre": "Valeria Gómez", "telefono": "1144712290", "tipo": "comprador", "buscaOperacion": "venta", "buscaAmbientes": 3,
         "buscaBarrios": ["Palermo", "Belgrano"], "buscaMoneda": "USD", "buscaDesde": 150000, "buscaHasta": 180000}
        """
        let operacion = """
        {"id": "o1", "titulo": "Cabildo 2100", "etapa": "reserva", "valor": 154000, "moneda": "USD", "contactoNombre": "Ana Torres",
         "propiedadTitulo": "Cabildo 2100, 8.º", "agenteNombre": "Sofía Paz", "sena": 3000, "honorariosComprador": 3,
         "checklist": [{"paso": "boleto", "titulo": "Boleto", "hecho": false}]}
        """
        let contrato = """
        {"id": "k1", "tipo": "alquiler", "estado": "vigente", "propiedadId": "p1", "contactoId": "c1", "inicio": "2024-07-01", "fin": "2027-06-30",
         "monto": 540000, "moneda": "ARS", "ajusteMeses": 6, "ajusteIndice": "icl", "diaVencimiento": 10, "propiedadTitulo": "Thames 2240",
         "contactoNombre": "Lucía Méndez", "propietarioNombre": "Sofía Paz"}
        """
        ApiFalsa.respuestas = [
            "/v1/panel": """
            {"numeros": {"citasHoy": 2, "rendicionesListas": 1}, "agendaHoy": [\(cita)],
             "sugerencias": [{"id": "s1", "estado": "pendiente", "accion": "Mandarle la ficha", "destacado": "Valeria busca 3 amb. en Belgrano. Mendoza 2350 le encaja.",
              "contactoId": "c1", "propiedadId": "p1"}],
             "objetivos": [{"id": "g1", "metrica": "operaciones", "meta": 5, "desde": "2026-11-01", "hasta": "2026-11-30", "avance": 3, "porcentaje": 60}]}
            """,
            "/v1/panel/guia": "{\"pasos\": {\"propiedad\": true}, \"propiedades\": 1}",
            "/v1/whatsapp/conversaciones": """
            [{"id": "w1", "waId": "5491144712290", "contactoNombre": "Valeria Gómez", "propiedadTitulo": "Mendoza 2350", "noLeidos": 1,
              "ultimoTexto": "¿Sigue disponible?", "ultimoMensajeEn": "2026-11-12T12:29:00Z", "enVentana": false}]
            """,
            "/v1/whatsapp/conversaciones/w1": """
            {"id": "w1", "waId": "5491144712290", "contactoNombre": "Valeria Gómez", "propiedadTitulo": "Mendoza 2350", "enVentana": false}
            """,
            "/v1/whatsapp/conversaciones/w1/mensajes": """
            [{"id": "m1", "direccion": "entrante", "tipo": "text", "texto": "¿Sigue disponible?", "estado": "recibido", "ocurrioEn": "2026-11-12T12:29:00Z"},
             {"id": "m2", "direccion": "saliente", "tipo": "text", "texto": "¡Sí!", "estado": "leido", "ocurrioEn": "2026-11-12T12:30:00Z"}]
            """,
            "/v1/whatsapp/plantillas": "[{\"nombre\": \"seguimiento_tasacion\", \"idioma\": \"es_AR\", \"parametros\": 1}]",
            "/v1/mercadolibre/preguntas": """
            [{"id": "q1", "propiedadId": "p1", "propiedad": "Thames 1820", "texto": "¿Tiene cochera?", "estado": "sin_responder",
              "creadaEn": "2026-11-12T12:12:00Z", "compradorApodo": "RODRI_84"}]
            """,
            "/v1/mercadolibre/preguntas/q1/sugerencia": "{\"sugerencia\": \"¡Hola! Sí, tiene cochera.\", \"fuentes\": [\"Tiene cochera fija\"]}",
            "/v1/contratos/deudas": """
            [{"contratoId": "k1", "propiedadTitulo": "Thames 2240", "contactoNombre": "Lucía Méndez", "moneda": "ARS", "total": 540000,
              "meses": [{"periodo": "2026-11", "esperado": 540000, "vencio": "2026-11-10"}]}]
            """,
            "/v1/avisos/contador": "{\"noLeidos\": 3, \"paraHacer\": 1}",
            "/v1/avisos": """
            {"avisos": [{"id": "v1", "tipo": "whatsapp", "titulo": "Valeria Gómez te escribió", "cuerpo": "¿Sigue disponible?", "url": "/mensajes/w1",
              "creadoEn": "2026-11-12T12:29:00Z", "acciones": [{"titulo": "Responder", "url": "/mensajes/w1"}]}]}
            """,
            "/v1/avisos/preferencias": """
            {"tipos": [{"tipo": "consulta", "nombre": "Consultas nuevas", "push": true, "mail": false}], "silencio": {"activo": true, "desde": 21, "hasta": 8, "domingos": true}}
            """,
            "/v1/equipo": "[{\"usuarioId\": \"u2\", \"nombre\": \"Martín\", \"apellido\": \"Ríos\", \"rol\": \"agente\", \"propiedades\": 12, \"telefono\": \"1155550000\"}]",
            "/v1/licencias": "[]",
            "/v1/cobranzas": """
            {"periodo": "2026-11", "cobradas": [], "pendientes": [{"contratoId": "k1", "propiedadTitulo": "Thames 2240", "contactoNombre": "Lucía Méndez",
              "monto": 540000, "moneda": "ARS", "vence": "2026-11-10", "estado": "pendiente"}], "totalCobrado": {"ARS": 1840000}, "totalPendiente": {"ARS": 540000}}
            """,
            "/v1/propiedades": "[\(prop)]",
            "/v1/propiedades/p1": prop,
            "/v1/propiedades/senales": "[{\"propiedadId\": \"p1\", \"portales\": {\"mercadolibre\": \"publicada\"}, \"interesados\": 2}]",
            "/v1/propiedades/p1/interesados": "[{\"contactoId\": \"c1\", \"nombre\": \"Valeria Gómez\", \"puntaje\": 0.9, \"visito\": false}]",
            "/v1/propiedades/p1/publicaciones": "[{\"id\": \"x1\", \"portal\": \"mercadolibre\", \"estado\": \"publicada\", \"visitasSemana\": 40, \"consultas\": 3}]",
            "/v1/propiedades/p1/inventario": "[{\"id\": \"i1\", \"ambiente\": \"Living\", \"descripcion\": \"Paredes\", \"estado\": \"bueno\"}]",
            "/v1/propiedades/p1/actas": "[]",
            "/v1/inmobiliaria": "{\"id\": \"i1\", \"nombre\": \"Luna Propiedades\", \"web\": \"https://luna.corredor.com.ar\", \"marca\": {\"frase\": \"Hola\"}}",
            "/v1/agenda": "[\(cita)]",
            "/v1/agenda/a1": cita,
            "/v1/contactos": "[\(contacto)]",
            "/v1/contactos/c1": contacto,
            "/v1/contactos/c1/notas": "[{\"id\": \"n1\", \"tipo\": \"whatsapp\", \"texto\": \"Escribió por WhatsApp\", \"ocurrioEn\": \"2026-11-12T12:28:00Z\"}]",
            "/v1/contactos/c1/propiedades": "[\(prop)]",
            "/v1/operaciones": "[\(operacion)]",
            "/v1/operaciones/o1": operacion,
            "/v1/operaciones/o1/historial": "[]",
            "/v1/contratos": "[\(contrato)]",
            "/v1/contratos/k1": contrato,
            "/v1/contratos/k1/cobros": "[{\"periodo\": \"2026-10\", \"esperado\": 540000, \"cobro\": {\"id\": \"b1\", \"periodo\": \"2026-10\", \"monto\": 540000, \"moneda\": \"ARS\", \"numero\": 482}}]",
            "/v1/contratos/k1/rendiciones": "[{\"id\": \"r1\", \"periodo\": \"2026-10\", \"moneda\": \"ARS\", \"cobrado\": 540000, \"comision\": 27000, \"neto\": 513000, \"estado\": \"pendiente\"}]",
            "/v1/contratos/k1/rendiciones/r1": "{\"id\": \"r1\", \"periodo\": \"2026-10\", \"moneda\": \"ARS\", \"cobrado\": 540000, \"comision\": 27000, \"comisionPorcentaje\": 5, \"neto\": 513000, \"estado\": \"pendiente\", \"items\": []}",
            "/v1/objetivos": "[{\"id\": \"g1\", \"metrica\": \"operaciones\", \"meta\": 5, \"avance\": 3, \"hasta\": \"2026-11-30\", \"agenteNombre\": \"Martín Ríos\"}]",
            "/v1/respuestas-guardadas": "[{\"id\": \"r1\", \"titulo\": \"Requisitos\", \"texto\": \"Garantía propietaria\"}]",
            "/v1/proveedores": "[{\"id\": \"pr1\", \"nombre\": \"Plomería Rossi\", \"rubro\": \"plomeria\", \"trabajos\": 8}]",
            "/v1/papelera": "[{\"entidad\": \"propiedad\", \"id\": \"p9\", \"titulo\": \"Soler 4120\", \"borradoEn\": \"2026-11-10T10:00:00Z\"}]",
            "/v1/indices": "[{\"codigo\": \"icl\", \"ultimoPeriodo\": \"2026-11-11\", \"ultimoValor\": 23.4567}]",
            "/v1/informe": "{\"totalVistas\": 1200, \"totalContactos\": 40, \"cerradas\": 3, \"origenes\": [{\"origen\": \"Web propia\", \"cantidad\": 12}], \"masVistas\": []}",
            "/v1/web/barrios": "[{\"nombre\": \"Palermo\", \"cantidad\": 4}]",
            "/v1/buscar": "[{\"id\": \"p1\", \"tipo\": \"propiedad\", \"titulo\": \"Mendoza 2350\"}]",
        ]
    }

    /// Dónde dejar las capturas (las sube el CI para compararlas con el handoff).
    static let capturas: URL? = {
        guard let d = ProcessInfo.processInfo.environment["CAPTURAS"] ?? (FileManager.default.fileExists(atPath: "/tmp/capturas-corredor") ? "/tmp/capturas-corredor" : nil) else { return nil }
        let u = URL(fileURLWithPath: d)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    private func montar<V: View>(_ vista: V, rol: String = "duenio", segundos: Double = 3, nombre: String = #function) {
        montarEn(vista, rol: rol, segundos: segundos, nombre: nombre, oscuro: false)
        if Self.capturas != nil { montarEn(vista, rol: rol, segundos: segundos, nombre: nombre, oscuro: true) }
    }

    private func montarEn<V: View>(_ vista: V, rol: String, segundos: Double, nombre: String, oscuro: Bool) {
        let conf = URLSessionConfiguration.ephemeral
        conf.protocolClasses = [ApiFalsa.self]
        let estado = Estado(api: Api(base: URL(string: "https://api.prueba")!, token: "x", http: URLSession(configuration: conf)))
        estado.sesion = Sesion(usuario: .init(id: "u1", email: "mariana@luna.test", nombre: "Mariana", apellido: "Luna"), inmobiliariaId: "i1", rol: rol,
                               inmobiliarias: [.init(inmobiliariaId: "i1", slug: "luna", nombre: "Luna Propiedades", rol: rol)])
        let raiz = NavigationStack { vista.destinos() }
            .environment(estado)
            .environment(estado.cola)
        let ventana = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        ventana.overrideUserInterfaceStyle = oscuro ? .dark : .light
        ventana.rootViewController = UIHostingController(rootView: raiz)
        ventana.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(segundos))
        if let dir = Self.capturas {
            let img = UIGraphicsImageRenderer(bounds: ventana.bounds).image { _ in ventana.drawHierarchy(in: ventana.bounds, afterScreenUpdates: true) }
            let n = nombre.replacingOccurrences(of: "()", with: "").replacingOccurrences(of: "test", with: "")
            try? img.pngData()?.write(to: dir.appendingPathComponent("\(n)-\(oscuro ? "oscuro" : "claro").png"))
        }
        ventana.isHidden = true
    }

    func testInicioDuena() { montar(InicioRaiz()) }
    func testInicioAgente() { montar(InicioRaiz(), rol: "agente") }
    func testInicioSinNada() {
        ApiFalsa.respuestas = ["/v1/panel": "{}"]
        montar(InicioRaiz(), rol: "agente")
    }
    func testBuscar() { montar(Buscar(texto: "Mendoza")) }
    func testAvisos() { montar(Avisos()) }
    func testConfigAvisos() { montar(ConfigAvisos()) }
    func testPerfil() { montar(Perfil()) }
    func testPropiedades() { montar(PropiedadesRaiz()) }
    func testFicha() { montar(FichaPropiedad(id: "p1")) }
    func testGaleria() { montar(Galeria(id: "p1", indice: 0)) }
    func testAlta() { montar(AltaPropiedad(editar: nil)) }
    func testAltaEditar() { montar(AltaPropiedad(editar: "p1")) }
    func testCaptadas() { montar(Captadas()) }
    func testMensajes() { montar(MensajesRaiz()) }
    func testChat() { montar(Chat(id: "w1")) }
    func testML() { montar(RespuestaML(id: "q1")) }
    func testAgenda() { montar(AgendaRaiz()) }
    func testCita() { montar(FichaCita(id: "a1")) }
    func testNuevaCita() { montar(NuevaCita()) }
    func testContactos() { montar(Contactos()) }
    func testFichaContacto() { montar(FichaContacto(id: "c1")) }
    func testOperaciones() { montar(Operaciones()) }
    func testFichaOperacion() { montar(FichaOperacion(id: "o1")) }
    func testCobranzas() { montar(Cobranzas()) }
    func testContratos() { montar(Contratos()) }
    func testFichaContrato() { montar(FichaContrato(id: "k1")) }
    func testRecibo() { montar(ReciboVista(contrato: "k1", cobro: "b1")) }
    func testRendicion() { montar(RendicionVista(contrato: "k1", id: "r1")) }
    func testAltaContrato() { montar(AltaContrato()) }
    func testInventario() { montar(Inventario(propiedad: "p1")) }
    func testFirmas() { montar(Firmas(clave: "p1/a1")) }
    func testSecciones() {
        for c in ["mas", "configuracion", "equipo", "integraciones", "respuestas", "proveedores", "objetivos", "inventarios", "rendiciones",
                  "papelera", "actividad", "revision", "informe", "indices", "web", "difusion", "consorcios", "ia", "no-existe"] {
            montar(Seccion(clave: c, id: nil), segundos: 1, nombre: "Seccion-\(c)")
        }
    }
    func testEntrada() { montar(Entrada()) }
    func testElegirInmobiliaria() { montar(ElegirInmobiliaria()) }
    func testBloqueo() { montar(Bloqueo(), segundos: 1) }
    func testPrincipal() { montar(Principal()) }
}
