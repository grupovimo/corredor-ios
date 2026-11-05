import XCTest
@testable import Corredor

final class CorredorTests: XCTestCase {
    func testRutasDeEnlaces() {
        XCTAssertEqual(Ruta(texto: "corredor://propiedad/abc")?.destino, AnyHashable(AFichaPropiedad(id: "abc")))
        XCTAssertEqual(Ruta(texto: "chat/c1")?.pestana, .mensajes)
        XCTAssertEqual(Ruta(texto: "https://corredor.com.ar/contactos/x")?.destino, AnyHashable(AFichaContacto(id: "x")))
        XCTAssertEqual(Ruta(texto: "corredor://mira")?.pestana, .mira)
        XCTAssertEqual(Ruta(texto: "/consorcios/e1")?.destino, AnyHashable(ASeccion(clave: "consorcio", id: "e1")))
    }

    func testClerkFapiDeLaClavePublicable() {
        XCTAssertEqual(Clerk.fapiDe("pk_live_Y2xlcmsuZ3J1cG92aW1vLmNvbS5hciQ")?.host, "clerk.grupovimo.com.ar")
    }

    func testSuscripcionDeLaApi() throws {
        let json = """
        {"estado":"prueba","plan":null,"ciclo":"mes","medio":null,"pruebaHasta":"2026-11-19T12:00:00Z","pagadoHasta":null,
         "vigenteHasta":"2026-11-19T12:00:00Z","diasRestantes":5,"renueva":false,"proximoCobro":null,"importe":null,"moneda":null,
         "esperando":null,"soloLectura":false,"enPrueba":true,"funciones":["ia"],"agentes":{"usados":2,"cupo":null},
         "planes":[{"id":"inicial","nombre":"Inicial","resumen":"x","agentes":1,"precioMes":29900,"precioAnio":299000,"funciones":[],
           "incluye":["1 persona"],"destacado":false,"appleMes":"ar.com.corredor.app.inicial.mes","appleAnio":"ar.com.corredor.app.inicial.anio"}],
         "mercadoPago":false,"cobros":[],"graciaDias":3}
        """
        let s = try Api.decodificador.decode(Suscripcion.self, from: Data(json.utf8))
        XCTAssertEqual(s.nombreEstado, "Prueba gratis · 5 días")
        XCTAssertTrue(s.pideAtencion)
        XCTAssertEqual(s.planes.first?.producto("anio"), "ar.com.corredor.app.inicial.anio")
        XCTAssertFalse(s.conMercadoPago)
    }
}
