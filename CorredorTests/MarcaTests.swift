import XCTest
@testable import Corredor

/// La marca propia y la estructura, parejas con el panel web (crm-inmobiliaria, rama corredor):
/// - los casos del acento son los de docs/marca-acento.json (los prueba también web/src/lib/ui/acento.spec.ts);
/// - las claves son las de docs/estructura-claves.json (las genera la API: TestClavesEstructura).
/// Si la regla o las secciones cambian allá, se copian acá y la app tiene que saber qué hacer con ellas.
@MainActor
final class MarcaTests: XCTestCase {
    static let casosAcento: [(String?, String?, Acento?)] = [
        ("#16443b", "#f2bb57", Acento(claro: 0x16443B, claroHondo: 0x133C34, oscuro: 0xF2BB57, oscuroHondo: 0xDFAC50)),
        ("#1e3a5f", nil, Acento(claro: 0x1E3A5F, claroHondo: 0x1A3354, oscuro: 0x77869E, oscuroHondo: 0x6D7B91)),
        ("#f5e6a8", nil, Acento(claro: 0x7D7756, claroHondo: 0x6E694C, oscuro: 0xF5E6A8, oscuroHondo: 0xE1D49B)),
        ("#e53935", "#ffd54f", Acento(claro: 0xD33431, claroHondo: 0xBA2E2B, oscuro: 0xFFD54F, oscuroHondo: 0xEBC449)),
        ("#000000", nil, Acento(claro: 0x000000, claroHondo: 0x000000, oscuro: 0x868686, oscuroHondo: 0x7B7B7B)),
        ("#ffffff", "#ffffff", Acento(claro: 0x6F6F6F, claroHondo: 0x626262, oscuro: 0xFFFFFF, oscuroHondo: 0xEBEBEB)),
        ("#888888", "#333333", Acento(claro: 0x737373, claroHondo: 0x656565, oscuro: 0x8E8E8E, oscuroHondo: 0x838383)),
        ("#7c2d12", "#7c2d12", Acento(claro: 0x7C2D12, claroHondo: 0x6D2810, oscuro: 0xB07F6F, oscuroHondo: 0xA27566)),
        ("azul", nil, nil),
        (nil, nil, nil),
    ]

    func testAcentoIgualAlPanel() {
        for (p, s, esperado) in Self.casosAcento {
            XCTAssertEqual(Acento.de(primario: p, secundario: s), esperado, "marca \(p ?? "-") / \(s ?? "-")")
        }
    }

    static let secciones = ["web", "configuracion", "equipo", "plan", "integraciones", "ia", "papelera", "agenda", "avisos", "buscar", "contactos", "operaciones", "reservas", "emprendimientos", "temporada", "cobranzas", "contratos", "rendiciones", "inventarios", "indices", "consorcios", "proveedores", "difusion", "respuestas", "importar", "objetivos", "informe", "revision", "actividad"]
    static let rapidas = ["captar", "propiedad", "contacto", "visita", "contrato", "cobrar", "web", "buscar", "agenda", "avisos"]

    func testConoceTodasLasSecciones() {
        XCTAssertEqual(Self.secciones.filter { Lugares.secciones[$0] == nil }, [], "Secciones de la API que la app no sabe abrir")
        XCTAssertEqual(Self.rapidas.filter { Lugares.rapidas[$0] == nil }, [], "Acciones rápidas de la API sin ícono")
    }

    /// El abanico del botón amarillo: cada acción (círculo y nombre) entra en la pantalla, arriba de la
    /// barra, y no pisa a otra, de 1 a 8 acciones y en todos los anchos de iPhone. Pasó el 5/11: las
    /// dos de las puntas quedaban debajo de la barra y no se leía su nombre.
    func testAbanicoEntraSinPisarse() {
        let t = AccionesRapidas.tamanoAccion
        for ancho in [375.0, 390, 393, 402, 414, 430, 440] {
            for alto in [540.0, 700, 800] {
                for n in 1...8 {
                    let p = AccionesRapidas.posiciones(cantidad: n, ancho: ancho, alto: alto)
                    XCTAssertEqual(p.count, n)
                    for x in p {
                        XCTAssertTrue(x.x - t.width / 2 >= 0 && x.x + t.width / 2 <= ancho && x.y - t.height / 2 >= 0 && x.y + t.height / 2 <= alto,
                                      "\(n) acciones a \(ancho)x\(alto): una queda afuera (\(x))")
                    }
                    for a in 0..<n {
                        for b in (a + 1)..<n where abs(p[a].x - p[b].x) < t.width && abs(p[a].y - p[b].y) < t.height {
                            XCTFail("\(n) acciones a \(ancho): la \(a) y la \(b) se pisan")
                        }
                    }
                }
            }
        }
    }
}
