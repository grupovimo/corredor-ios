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
         "planes":[{"id":"agente","nombre":"Agente","resumen":"x","agentes":1,"precioMes":24900,"precioAnio":249000,"funciones":[],
           "incluye":["1 persona"],"destacado":false,"appleMes":"ar.com.corredor.app.agente.mes","appleAnio":"ar.com.corredor.app.agente.anio"}],
         "mercadoPago":false,"cobros":[],"graciaDias":3}
        """
        let s = try Api.decodificador.decode(Suscripcion.self, from: Data(json.utf8))
        XCTAssertEqual(s.nombreEstado, "Prueba gratis · 5 días")
        XCTAssertTrue(s.pideAtencion)
        XCTAssertEqual(s.planes.first?.producto("anio"), "ar.com.corredor.app.agente.anio")
        // Una API de antes de los topes no los manda: no rompe.
        XCTAssertNil(s.topes)
        XCTAssertEqual(s.deMas(s.planes[0]).personas, 1)
        XCTAssertFalse(s.conMercadoPago)
        XCTAssertFalse(s.pagaAfuera)
    }

    /// El ticket de la compra en la tienda: Apple y Google dejan las personas extra en 0, así que no se
    /// cuentan (Equipo con 3 extras pagadas por Mercado Pago y 15 que cargan: 3 quedan sin cargar).
    func testDeMasSinExtrasEnLaTienda() throws {
        let json = """
        {"estado":"baja","plan":"equipo","ciclo":"mes","medio":"mercadopago","pruebaHasta":"2026-10-01T12:00:00Z","pagadoHasta":"2026-12-01T12:00:00Z",
         "vigenteHasta":"2026-12-01T12:00:00Z","diasRestantes":12,"renueva":false,"soloLectura":false,"enPrueba":false,"personasExtra":3,
         "agentes":{"usados":15,"cupo":15},"planVigente":"equipo",
         "topes":{"propiedades":{"usados":36,"tope":null},"contratos":{"usados":3,"tope":null},"mira":{"usados":0,"tope":null}},
         "planes":[{"id":"agente","nombre":"Agente","resumen":"x","agentes":1,"propiedades":30,"contratos":15,"mira":100,"precioMes":24900,"precioAnio":249000,
           "incluye":[],"destacado":false,"appleMes":"a.mes","appleAnio":"a.anio"},
          {"id":"equipo","nombre":"Equipo","resumen":"x","agentes":12,"personaExtraMes":7900,"precioMes":119900,"precioAnio":1199000,
           "incluye":[],"destacado":false,"appleMes":"e.mes","appleAnio":"e.anio"}],
         "mercadoPago":true,"cobros":[]}
        """
        let s = try Api.decodificador.decode(Suscripcion.self, from: Data(json.utf8))
        let equipo = s.planes[1]
        XCTAssertEqual(s.deMas(equipo).personas, 0)
        XCTAssertEqual(s.deMas(equipo, conExtras: false).personas, 3)
        // Bajar a Agente: 6 propiedades de más; el carrito lo dice.
        XCTAssertEqual(s.deMas(s.planes[0]).propiedades, 6)
        XCTAssertNil(s.textoFuera)
        XCTAssertNil(s.topeLleno("propiedades"))
        XCTAssertEqual(s.topeLleno("personas")?.tope, 15)
    }

    func testDiaDeConsorciosEnHoraArgentina() {
        // Cargado el 17 a las 22:30 en Buenos Aires: en UTC ya es el 18.
        XCTAssertEqual(Cons.diaLocal("2026-11-18T01:30:00.123456789Z"), "2026-11-17")
        XCTAssertEqual(Cons.diaLocal("2026-11-17T22:30:00-03:00"), "2026-11-17")
        XCTAssertEqual(Cons.diaLocal("2026-11-18"), "2026-11-18")
    }

    func testClaveDeOchoCaracteres() {
        XCTAssertTrue(ClerkMail.requisitos("casa1234").largo)
        XCTAssertFalse(ClerkMail.requisitos("casa123").largo)
        XCTAssertFalse(ClerkMail.requisitos("12345678").comun)
        XCTAssertFalse(ClerkMail.requisitos("password").comun)
    }

    func testIngresoConCuentaBorrada() {
        let e = ErrorApi(estado: 409, codigo: "cuenta_borrada", titulo: "Cuenta borrada",
                         detalle: "Borraste tu cuenta el 10/11. Escribinos a hola@corredor.com.ar para recuperarla.")
        XCTAssertEqual(Entrada.mensaje(e), e.detalle)
    }
}
