import XCTest
@testable import Corredor

final class CorredorTests: XCTestCase {
    func testRutasDeEnlaces() {
        XCTAssertEqual(Ruta(texto: "corredor://propiedad/abc")?.destino, AnyHashable(AFichaPropiedad(id: "abc")))
        XCTAssertEqual(Ruta(texto: "chat/c1")?.pestana, .mensajes)
        XCTAssertEqual(Ruta(texto: "https://corredor.com.ar/contactos/x")?.destino, AnyHashable(AFichaContacto(id: "x")))
        XCTAssertEqual(Ruta(texto: "corredor://mira")?.pestana, .mira)
        XCTAssertEqual(Ruta(texto: "/consorcios/e1")?.destino, AnyHashable(ASeccion(clave: "consorcios", id: "e1")))
    }

    func testClerkFapiDeLaClavePublicable() {
        XCTAssertEqual(Clerk.fapiDe("pk_live_Y2xlcmsuZ3J1cG92aW1vLmNvbS5hciQ")?.host, "clerk.grupovimo.com.ar")
    }
}
