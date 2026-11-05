import XCTest

/// Recorridos de punta a punta (como Playwright en la web): la app de verdad, en el simulador de GitHub,
/// contra la API grabada (PruebasUI/api). Tocan cada pestaña, cada acceso, cada fila de «Más», cada ficha
/// y sus secciones, cada hoja de alta, el «+», el buscador y el perfil. Si algo no abre, se cae o muestra
/// «No encontramos esta sección», falla con la captura de ese momento; los recorridos siguen igual, así
/// una corrida muestra todo lo roto. Cada pantalla deja su captura (artefacto «recorridos» del CI).
///
/// No tocan lo que sale de la app (llamar, WhatsApp, mail, mapas) ni lo que borra.
final class Recorridos: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-ModoPruebaUI", "YES", "-CorredorApi", "http://127.0.0.1:8787", "-CorredorToken", "prueba",
                                "-AppleLanguages", "(es)", "-AppleLocale", "es_AR"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hoy"].waitForExistence(timeout: 20), "La app no entró al Inicio con la sesión de prueba")
    }

    // MARK: Inicio

    func testInicio() {
        foto("inicio")
        for acceso in ["Agenda", "Contactos", "Operaciones", "Cobranzas", "Contratos"] {
            abrirYVolver(acceso, en: "inicio")
        }
        // Las cifras de la dueña llevan a su sección.
        abrirYVolver("Cobrado del mes", en: "inicio-cifra")
        abrirYVolver("Visitas", en: "inicio-cifra")
        // Avisos y buscar, en la cabecera.
        tocarBoton("Avisos"); esperarPantalla("avisos"); volver()
        tocarBoton("Buscar")
        let campo = app.textFields.firstMatch
        if campo.waitForExistence(timeout: 5) {
            campo.tap(); campo.typeText("expensas")
            foto("buscar-expensas")
            if tocarTexto("Consorcios") { esperarPantalla("buscar-consorcios"); volver() }
        }
        cerrarHojaOVolver()
        // «+»: cada cosa que se puede cargar abre su alta.
        for opcion in ["Propiedad", "Contacto", "Visita", "Operación", "Contrato de alquiler", "Cobro"] {
            tocarBoton("Cargar")
            if app.buttons[opcion].waitForExistence(timeout: 5) {
                app.buttons[opcion].tap()
                esperarPantalla("cargar-\(opcion)")
                cerrarHojaOVolver()
            } else {
                XCTFail("El «+» no ofrece «\(opcion)»"); foto("falla-cargar-\(opcion)")
                cerrarHojaOVolver()
            }
        }
        // Para aprobar: ver el detalle de una sugerencia.
        if desplazarHasta(app.buttons["Ver detalle"]) { app.buttons["Ver detalle"].firstMatch.tap(); esperarPantalla("sugerencia-detalle"); volver() }
        // Las cifras que cambian de pestaña.
        abrirYVolver("Consultas", en: "inicio-cifra", cambiaDePestana: true)
    }

    // MARK: Propiedades

    func testPropiedades() {
        pestana("Propiedades")
        foto("propiedades-lista")
        for filtro in ["Venta", "Alquiler", "Temporada", "Mías", "Borradores", "Con error", "Todas"] {
            if tocarTexto(filtro) { foto("propiedades-filtro-\(filtro)") }
        }
        // Mandar desde la lista (el logo de WhatsApp).
        if app.buttons["Mandar la ficha"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Mandar la ficha"].firstMatch.tap(); foto("propiedades-mandar"); cerrarHojaOVolver()
        } else { XCTFail("No se ve el botón para mandar la ficha en la lista") }
        // La ficha y todo lo que cuelga de ella.
        if tocarTexto("Mendoza 2350, 5.º A") {
            esperarPantalla("ficha")
            for s in ["Inventario y actas", "Vistas y consultas", "A quién se la mandaste", "Recorridas dictadas", "Documentos", "Reservas", "Editar la propiedad"] {
                abrirYVolver(s, en: "ficha")
            }
            if tocarBoton("Cambiar el estado") || tocarTexto("Cambiar el estado") { foto("ficha-estado"); cerrarHojaOVolver() }
            if tocarBoton("Mandar por WhatsApp") { foto("ficha-mandar"); cerrarHojaOVolver() }
            if tocarBoton("Agendar") { foto("ficha-agendar"); cerrarHojaOVolver() }
            volver()
        } else { XCTFail("No se pudo abrir la ficha desde la lista") }
        // Una propiedad en alquiler (su contrato en «Negocio»).
        if tocarTexto("Thames 2240") {
            esperarPantalla("ficha-alquilada")
            if desplazarHasta(app.staticTexts["Negocio"]) { foto("ficha-negocio") }
            volver()
        }
        // El mapa: precios como pines y la tarjeta de la elegida.
        if tocarTexto("Mapa") {
            sleep(3); foto("propiedades-mapa")
            let pin = app.staticTexts["USD 172 k"]
            if pin.waitForExistence(timeout: 8) { pin.tap(); sleep(1); foto("mapa-elegida") } else { XCTFail("El mapa no muestra los precios") }
            tocarTexto("Lista")
        }
        // Alta nueva.
        tocarBoton("Nueva propiedad"); esperarPantalla("alta-propiedad"); cerrarHojaOVolver()
    }

    // MARK: Mensajes y MIRA

    func testMensajesYMira() {
        pestana("Mensajes")
        foto("mensajes")
        // Los filtros llevan su cuenta al lado («Pendientes 2»): se buscan por cómo empiezan.
        for f in ["Pendientes", "Míos", "Sin dueño", "Todos"] {
            let e = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", f)).firstMatch
            if e.waitForExistence(timeout: 3) { e.tap(); foto("mensajes-\(f)") } else { XCTFail("Falta el filtro «\(f)» en Mensajes") }
        }
        if tocarBoton("Mensaje nuevo") { foto("mensaje-nuevo"); cerrarHojaOVolver() }
        tocarBoton("MIRA: fotografiar un cartel")
        sleep(2); foto("mira")
        if app.buttons["Cerrar MIRA"].waitForExistence(timeout: 5) { app.buttons["Cerrar MIRA"].tap() } else { XCTFail("MIRA no tiene cómo cerrarse") }
        XCTAssertEqual(app.state, .runningForeground, "La app se cerró en MIRA")
    }

    // MARK: Más: cada sección

    static let secciones = ["Agenda", "Avisos", "Buscar en todo", "Contactos", "Operaciones", "Reservas", "Emprendimientos", "Temporada",
                            "Cobranzas", "Contratos", "Rendiciones", "Actas de entrega", "Índices", "Consorcios", "Mi web", "Portales",
                            "Respuestas guardadas", "Importar la cartera", "Objetivos", "Informe", "Revisión de la IA", "Actividad",
                            "Inmobiliaria", "Equipo y permisos", "Integraciones", "Proveedores", "Corredor en tu IA", "Papelera"]

    func testMasCadaSeccion() {
        pestana("Más")
        foto("mas")
        for s in Self.secciones {
            pestana("Más")
            abrirYVolver(s, en: "mas")
        }
        // El buscador de secciones.
        pestana("Más")
        let campo = app.textFields["Buscar una sección"]
        if campo.waitForExistence(timeout: 5) {
            campo.tap(); campo.typeText("excel"); foto("mas-buscar-excel")
            XCTAssertTrue(app.staticTexts["Importar la cartera"].waitForExistence(timeout: 3), "«excel» no encuentra Importar la cartera")
            app.buttons["Borrar lo escrito"].firstMatch.tap()
        }
        // «Potenciá tu negocio».
        if desplazarHasta(app.buttons["Activar"]) { app.buttons["Activar"].firstMatch.tap(); esperarPantalla("potencia"); volver() }
    }

    func testPerfilYRecorrido() {
        pestana("Más")
        tocarBoton("Tu perfil")
        esperarPantalla("perfil")
        for s in ["Contratos y cobranzas", "Actas de entrega", "Objetivo del mes", "Avisos", "Firma y sesiones abiertas",
                  "Configuración, consorcios e informes"] { abrirYVolver(s, en: "perfil") }
        volver()
        pestana("Más")
        if desplazarHasta(app.buttons["Ver el recorrido de nuevo"]) {
            app.buttons["Ver el recorrido de nuevo"].tap()
            for i in 0..<8 {
                foto("recorrido-\(i + 1)")
                if app.buttons["Siguiente"].exists { app.buttons["Siguiente"].tap() } else if app.buttons["Empezar"].exists { app.buttons["Empezar"].tap(); break } else { break }
            }
        }
    }

    // MARK: Fichas que se abren desde las secciones

    func testFichas() {
        // Contacto.
        pestana("Más"); abrir("Contactos")
        if tocarTexto("Valeria Gómez") {
            esperarPantalla("ficha-contacto")
            if tocarBoton("Agendar") { foto("contacto-agendar"); cerrarHojaOVolver() }
            if tocarBoton("Más acciones") { foto("contacto-menu"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() }
            volver()
        } else { XCTFail("No abre la ficha del contacto") }
        volver()
        // Operación.
        pestana("Más"); abrir("Operaciones")
        if tocarTexto("Venta Mendoza 2350") || tocarTexto("Valeria Gómez") { esperarPantalla("ficha-operacion"); volver() } else { XCTFail("No abre la operación") }
        volver()
        // Contrato: cobrar, documentos, inventario, PDF y renovar.
        pestana("Más"); abrir("Contratos")
        if tocarTexto("Thames 2240") {
            esperarPantalla("ficha-contrato")
            for s in ["Documentos", "Inventario y actas"] { abrirYVolver(s, en: "contrato") }
            if tocarBoton("Renovar") { esperarPantalla("contrato-renovar"); cerrarHojaOVolver() }
            if tocarBoton("Ver o imprimir el contrato") { sleep(2); foto("contrato-pdf"); cerrarHojaOVolver() }
            volver()
        } else { XCTFail("No abre la ficha del contrato") }
        volver()
        // Consorcio y sus pestañas.
        pestana("Más"); abrir("Consorcios")
        if tocarTexto("Cabildo 2620") {
            esperarPantalla("ficha-consorcio")
            for t in ["Unidades", "Expensas", "Deudores", "Trabajos", "Novedades", "Personal"] { if tocarTexto(t) { foto("consorcio-\(t)") } }
            for s in ["Bienes del edificio", "Reglamento"] {
                if tocarBoton("Más acciones"), app.buttons[s].waitForExistence(timeout: 3) {
                    app.buttons[s].tap(); esperarPantalla("consorcio-\(s)"); volver()
                } else { XCTFail("El consorcio no ofrece «\(s)»"); foto("falla-consorcio-\(s)") }
            }
            volver()
        } else { XCTFail("No abre la ficha del consorcio") }
        volver()
        // Emprendimiento.
        pestana("Más"); abrir("Emprendimientos")
        if tocarTexto("Bosque Azul") {
            esperarPantalla("ficha-emprendimiento")
            if desplazarHasta(app.buttons["Crear lotes en serie"]) { app.buttons["Crear lotes en serie"].tap(); foto("lotes"); cerrarHojaOVolver() }
            volver()
        } else { XCTFail("No abre el emprendimiento") }
        volver()
        // Agenda y una visita.
        pestana("Más"); abrir("Agenda")
        tocarTexto("Semana"); foto("agenda-semana"); tocarTexto("Día")
        if tocarTexto("Visita Mendoza 2350") { esperarPantalla("cita"); volver() }
        volver()
    }

    // MARK: Ayudantes

    private func pestana(_ nombre: String) {
        let b = app.buttons[nombre].firstMatch
        if b.waitForExistence(timeout: 5) { b.tap() } else { XCTFail("No está la pestaña «\(nombre)»") }
        // Volver a la raíz de la pestaña (tocarla de nuevo vacía su pila).
        if app.navigationBars.buttons.firstMatch.exists { b.tap() }
        sleep(1)
    }

    @discardableResult
    private func tocarTexto(_ t: String) -> Bool {
        let e = app.staticTexts[t].firstMatch
        guard desplazarHasta(e) else { return false }
        e.tap()
        return true
    }

    @discardableResult
    private func tocarBoton(_ t: String) -> Bool {
        let e = app.buttons[t].firstMatch
        guard desplazarHasta(e) else { return false }
        e.tap()
        return true
    }

    /// Desplaza la pantalla hasta que el elemento se pueda tocar.
    @discardableResult
    private func desplazarHasta(_ e: XCUIElement) -> Bool {
        if e.waitForExistence(timeout: 3), e.isHittable { return true }
        for _ in 0..<8 {
            app.swipeUp(velocity: .slow)
            if e.exists, e.isHittable { return true }
        }
        for _ in 0..<10 {
            app.swipeDown(velocity: .fast)
            if e.exists, e.isHittable { return true }
        }
        return false
    }

    private func abrir(_ t: String) {
        if !(tocarTexto(t) || tocarBoton(t)) { XCTFail("No se encuentra «\(t)»"); foto("falla-no-esta-\(t)"); return }
        esperarPantalla(t)
    }

    /// Abre, verifica y vuelve (si no abre o muestra un error, falla con captura y sigue).
    private func abrirYVolver(_ t: String, en donde: String, cambiaDePestana: Bool = false) {
        if !(tocarTexto(t) || tocarBoton(t)) { XCTFail("[\(donde)] No se encuentra «\(t)»"); foto("falla-\(donde)-no-esta-\(t)"); return }
        esperarPantalla("\(donde)-\(t)")
        if !cambiaDePestana { volver() }
    }

    /// Lo que tiene que pasar al abrir cualquier pantalla: la app sigue viva y no muestra errores.
    private func esperarPantalla(_ nombre: String) {
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "[\(nombre)] La app se cerró")
        if app.state != .runningForeground { app.launch(); return }
        if app.staticTexts["No encontramos esta sección"].exists { XCTFail("[\(nombre)] Sección inexistente") }
        if app.staticTexts["No pudimos cargar"].exists || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'No pudimos cargar'")).count > 0 {
            XCTFail("[\(nombre)] Error al cargar")
        }
        foto(nombre)
    }

    private func volver() {
        let atras = app.navigationBars.buttons.element(boundBy: 0)
        if atras.exists, atras.isHittable { atras.tap(); sleep(1); return }
        cerrarHojaOVolver()
    }

    private func cerrarHojaOVolver() {
        for b in ["Cancelar", "Cerrar", "Listo", "Saltear"] where app.buttons[b].firstMatch.exists && app.buttons[b].firstMatch.isHittable {
            app.buttons[b].firstMatch.tap(); sleep(1); return
        }
        let atras = app.navigationBars.buttons.element(boundBy: 0)
        if atras.exists, atras.isHittable { atras.tap(); sleep(1); return }
        app.swipeDown(velocity: .fast); sleep(1)
    }

    private func foto(_ nombre: String) {
        let captura = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: captura)
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["RECORRIDOS"] {
            let limpio = nombre.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? captura.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name.split(separator: " ").last?.dropLast() ?? "")-\(limpio).png"))
        }
    }
}
