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
        {"id": "p1", "numero": 412, "titulo": "Mendoza 2350, 5.º A", "slug": "mendoza-2350", "tipo": "departamento", "operacion": "venta", "estado": "disponible",
         "precio": 172000, "moneda": "USD", "direccion": "Mendoza 2350, 5.º A", "barrio": "Belgrano", "lat": -34.56, "lng": -58.45, "ambientes": 3, "banos": 1,
         "superficie": 74, "comodidades": ["balcón"], "fotos": [], "fotosUrl": [], "publicada": true, "creadaEn": "2026-11-01T10:00:00Z", "actualizadoEn": "2026-11-02T10:00:00.123456Z",
         "agenteId": "u1", "ficha": {"temporario": {"checkIn": "14:00", "checkOut": "10:00", "deposito": 100000, "moneda": "ARS"}}}
        """
        let cita = """
        {"id": "a1", "tipo": "visita", "estado": "pendiente", "titulo": "Visita", "empiezaEn": "2026-11-12T13:00:00Z", "duracionMin": 45, "propiedadId": "p1",
         "contactoId": "c1", "contactoNombre": "Diego Fernández", "propiedadTitulo": "Arce 320, 4.º B", "lugar": null, "agenteId": "u1", "agenteNombre": "Sofía Paz",
         "recordar": true, "recordadoEn": null, "creadaEn": "2026-11-10T10:00:00Z", "actualizadoEn": "2026-11-10T10:00:00Z"}
        """
        let contacto = """
        {"id": "c1", "nombre": "Valeria Gómez", "telefono": "1144712290", "tipo": "comprador", "buscaOperacion": "venta", "buscaAmbientes": 3, "buscaBarrios": ["Palermo",
         "Belgrano"], "buscaMoneda": "USD", "buscaDesde": 150000, "buscaHasta": 180000, "origen": "web", "buscaDetalles": ["Con balcón"], "etiquetas": ["Con crédito"],
         "creadoEn": "2026-11-01T10:00:00Z", "email": "valeria@correo.test", "agenteId": "u1", "actividadEn": "2026-11-12T11:00:00Z", "esperaDesde": null, "proximaCitaEn": null,
         "proximaCitaTitulo": null, "propiedad": "Mendoza 2350", "debe": []}
        """
        let operacion = """
        {"id": "o1", "titulo": "Cabildo 2100", "etapa": "reserva", "valor": 154000, "moneda": "USD", "contactoNombre": "Ana Torres", "propiedadTitulo": "Cabildo 2100, 8.º",
         "agenteNombre": "Sofía Paz", "sena": 3000, "honorariosComprador": 3, "checklist": {"dominio": {"en": "2026-11-10T12:00:00Z", "por": "u1"}}, "adjuntos": [],
         "propiedadOperacion": "venta", "contactoId": "c1", "propiedadId": "p1", "agenteId": "u1", "orden": 1, "propiedadBarrio": "Belgrano", "propiedadFotoId": null,
         "senaVenceEl": null, "proximaCita": {"tipo": "visita", "titulo": "Visita · Mendoza 2350", "empiezaEn": "2026-11-12T20:30:00Z", "estado": "pendiente"},
         "ultimaCita": null, "reserva": null, "propietarioId": "c9", "propietarioNombre": "Jorge Ruiz", "propietarioTelefono": "+5491155550000", "contactoTelefono": "+5491144712290",
         "creadaEn": "2026-11-01T10:00:00Z"}
        """
        let contrato = """
        {"id": "k1", "tipo": "alquiler", "estado": "vigente", "propiedadId": "p1", "contactoId": "c1", "inicio": "2024-07-01", "fin": "2027-06-30", "monto": 540000,
         "moneda": "ARS", "ajusteMeses": 6, "ajusteIndice": "icl", "diaVencimiento": 10, "propiedadTitulo": "Thames 2240", "contactoNombre": "Lucía Méndez", "propietarioNombre": "Sofía Paz",
         "deposito": 480000, "comision": 5, "punitorioDiario": 0.5, "agenteId": null}
        """
        let conv = """
        {"id": "w1", "waId": "5491144712290", "contactoNombre": "Valeria Gómez", "propiedadTitulo": "Mendoza 2350", "noLeidos": 1, "ultimoTexto": "¿Sigue disponible?",
         "ultimoMensajeEn": "2026-11-12T12:29:00Z", "enVentana": false, "esperando": true, "archivada": false, "propiedadPorCodigo": false, "creadaEn": "2026-11-10T10:00:00Z",
         "actualizadoEn": "2026-11-12T12:00:00Z"}
        """
        let reserva = """
        {"id": "r1", "propiedadId": "p1", "contactoId": "c1", "interesadoNombre": null, "interesadoTelefono": null, "sena": 2000, "senaMoneda": "USD", "reservadaEl": "2026-11-01",
         "venceEl": "2026-11-07", "venceHora": "18:00", "notas": null, "operacionId": "o1", "estado": "activa", "cerradaEl": null, "motivoCierre": null, "contactoNombre": "Diego Funes",
         "propiedadNumero": 412, "propiedadTitulo": "Mendoza 2350", "vencida": false, "reciboNumero": null, "creadaPor": "u1", "creadoEn": "2026-11-01T10:00:00Z",
         "actualizadoEn": "2026-11-01T10:00:00Z"}
        """
        let consorcio = """
        {"id": "e1", "nombre": "Consorcio Cabildo 2620", "direccion": "Av. Cabildo 2620, Belgrano", "cuit": "30-55912873-9", "modoExpensas": "prorrateo", "fondoTipo": "ninguno",
         "fondoValor": 0.0, "interesMensual": 3, "notas": null, "agenteId": null, "cbu": null, "diaVencimiento": 10, "diaSegundoVencimiento": 20, "fotoId": null,
         "fotoUrl": null, "reglamentoEn": null, "metricas": {"unidades": 2, "deudores": 1, "saldoAdeudado": 85000.0, "novedadesAbiertas": 1, "trabajosPendientes": 1,
         "trabajosVencidos": 0, "servicesPorVencer": 0}, "creadoEn": "2026-10-01T12:00:00Z", "actualizadoEn": "2026-11-01T12:00:00Z"}
        """
        ApiFalsa.respuestas = [
            "/v1/panel": """
            {"numeros": {"citasHoy": 2, "rendicionesListas": 1, "primeraRendicion": {"id": "r1", "contratoId": "k1"}}, "agendaHoy": [{"id": "a1", "tipo": "visita",
             "estado": "pendiente", "titulo": "Visita", "empiezaEn": "2026-11-12T13:00:00Z", "duracionMin": 45, "propiedadId": "p1", "contactoId": "c1", "contactoNombre": "Diego Fernández",
             "propiedadTitulo": "Arce 320, 4.º B"}], "sugerencias": [{"id": "s1", "estado": "pendiente", "accion": "Mandarle la ficha", "destacado": "Valeria busca 3 amb. en Belgrano. Mendoza 2350 le encaja.",
             "contactoId": "c1", "propiedadId": "p1", "agenteId": "u1"}], "objetivos": [{"id": "g1", "metrica": "operaciones_cerradas", "meta": 5, "desde": "2026-11-01",
             "hasta": "2026-11-30", "avance": 3, "porcentaje": 60, "agenteId": "u1", "agenteNombre": "Sofía Paz"}]}
            """,
            "/v1/panel/guia": """
            {"tourVisto": true, "pasosOcultos": false, "pasos": {"datos": true, "propiedad": true, "web": false, "whatsapp": true, "equipo": false, "avisos": false,
             "portales": false}, "usos": {"captar": 3, "propiedad": 1, "contacto": 0, "visita": 2, "cobro": 0}, "contratos": 1, "propiedades": 4, "contactos": 2, "alta": {"pasos": [{"clave": "logo",
             "titulo": "Subí el logo", "texto": "", "obligatorio": true, "peso": 20, "hecho": true}], "completo": 80, "faltan": ["portada"], "minimoListo": true, "terminada": false}}
            """,
            "/v1/whatsapp/conversaciones": "[\(conv)]",
            "/v1/whatsapp/conversaciones/w1": conv,
            "/v1/whatsapp/conversaciones/w1/mensajes": """
            [{"id": "m1", "conversacionId": "w1", "direccion": "entrante", "tipo": "texto", "texto": "¿Puede ser el sábado a las 11?", "plantilla": null, "mediaTipo": null,
             "archivoId": null, "archivoUrl": null, "estado": "recibido", "error": null, "autorId": null, "ocurrioEn": "2026-11-12T12:20:00Z"}, {"id": "m2", "conversacionId": "w1",
             "direccion": "saliente", "tipo": "texto", "texto": "¡Sí!", "plantilla": null, "mediaTipo": null, "archivoId": null, "archivoUrl": null, "estado": "leido",
             "error": null, "autorId": "u1", "ocurrioEn": "2026-11-12T12:30:00Z"}]
            """,
            "/v1/whatsapp/plantillas": """
            [{"nombre": "retomar_consulta", "idioma": "es_AR", "categoria": "MARKETING", "cuerpo": "Hola {{1}}, soy {{2}} de la inmobiliaria.", "parametros": 2, "usos": 3}]
            """,
            "/v1/mercadolibre/preguntas": """
            [{"id": "q1", "propiedadId": "p1", "propiedad": "Thames 1820", "texto": "¿Tiene cochera?", "estado": "sin_responder", "creadaEn": "2026-11-12T12:12:00Z",
             "compradorApodo": "RODRI_84", "visitasSemana": 40}]
            """,
            "/v1/mercadolibre/preguntas/q1/sugerencia": "{\"sugerencia\": \"¡Hola! Sí, tiene cochera.\", \"fuentes\": [\"Tiene cochera fija\"]}",
            "/v1/contratos/deudas": """
            [{"contratoId": "k1", "propiedadTitulo": "Gorriti 4820", "contactoId": "c1", "contactoNombre": "Lucía Méndez", "agenteId": null, "moneda": "ARS", "punitorioDiario": 0.5,
             "meses": [{"periodo": "2026-10-01", "vence": "2026-10-10", "esperado": 520000, "estimado": false, "estado": "atrasado", "cobro": null}], "total": 520000,
             "estimado": false}]
            """,
            "/v1/avisos/contador": "{\"noLeidos\": 3, \"paraHacer\": 1}",
            "/v1/avisos": """
            {"avisos": [{"id": "v1", "tipo": "whatsapp", "titulo": "Valeria Gómez te escribió", "cuerpo": "¿Sigue disponible?", "url": "/mensajes/w1", "datos": {},
             "accionable": true, "hecho": false, "hechoEn": null, "leido": false, "leidoEn": null, "creadoEn": "2026-11-12T12:29:00Z", "acciones": [{"accion": "responder",
             "titulo": "Responder", "url": "/mensajes/w1"}]}], "siguiente": null, "noLeidos": 1, "paraHacer": 1}
            """,
            "/v1/avisos/preferencias": """
            {"tipos": [{"tipo": "consulta", "nombre": "Consultas nuevas", "push": true, "mail": false, "sinPush": false}], "silencio": {"activo": true, "desde": 21,
             "hasta": 8, "domingos": true}}
            """,
            "/v1/equipo": """
            [{"usuarioId": "u2", "email": "martin@luna.com.ar", "nombre": "Martín", "apellido": "Ríos", "foto": null, "telefono": "+5491155550000", "whatsapp": null,
             "rol": "agente", "desde": "2026-01-10T12:00:00Z", "propiedades": 12, "barrios": ["Palermo", "Belgrano"], "avisosPush": true}]
            """,
            "/v1/licencias": """
            [{"id": "l1", "usuarioId": "u1", "usuarioNombre": "Lara Gómez", "tipo": "vacaciones", "desde": "2026-11-10", "hasta": "2026-11-20", "nota": null, "creadoEn": "2026-11-01T10:00:00Z"}]
            """,
            "/v1/cobranzas": """
            {"periodo": "2026-11-01", "cobradas": [], "pendientes": [{"contratoId": "k1", "propiedadTitulo": "Thames 2240", "contactoNombre": "Lucía Méndez", "monto": 540000,
             "moneda": "ARS", "vence": "2026-11-10", "estado": "pendiente", "agenteId": null}], "totalCobrado": {"ARS": 1840000}, "totalPendiente": {"ARS": 540000},
             "totalComision": {"ARS": 92000}}
            """,
            "/v1/propiedades": "[\(prop)]",
            "/v1/propiedades/p1": prop,
            "/v1/propiedades/senales": "[{\"propiedadId\": \"p1\", \"portales\": {\"mercadolibre\": \"publicada\"}, \"interesados\": 2}]",
            "/v1/propiedades/p1/interesados": "[{\"contactoId\": \"c1\", \"nombre\": \"Valeria Gómez\", \"puntaje\": 0.9, \"visito\": false}]",
            "/v1/propiedades/p1/publicaciones": "[{\"id\": \"x1\", \"portal\": \"mercadolibre\", \"estado\": \"publicada\", \"visitasSemana\": 40, \"consultas\": 3}]",
            "/v1/propiedades/p1/inventario": """
            [{"id": "i1", "propiedadId": "p1", "ambiente": "Living", "descripcion": "Paredes", "cantidad": 1, "estado": "bueno", "notas": null, "fotos": [], "fotosUrl": [],
             "creadoEn": "2026-11-01T12:00:00Z", "actualizadoEn": "2026-11-01T12:00:00Z"}]
            """,
            "/v1/propiedades/p1/actas": """
            [{"id": "a1", "propiedadId": "p1", "contratoId": "k1", "tipo": "entrada", "fecha": "2026-11-01", "items": [{"ambiente": "Living", "descripcion": "Paredes",
             "cantidad": 1, "estado": "bueno", "notas": null, "fotos": [], "fotosUrl": []}], "observaciones": null, "creadaPor": "u1", "creadoEn": "2026-11-01T12:00:00Z",
             "firmas": {}}]
            """,
            "/v1/contratos/k1/ajuste": """
            {"indice": "icl", "base": 480000, "vigente": 540000, "vigenteEstimado": false, "ultimoAjuste": "2026-08-01", "proximo": {"fecha": "2027-02-01", "monto": 610000},
             "cronograma": [{"fecha": "2026-08-01", "monto": 540000, "factor": 1.125, "futuro": false, "estimado": false}, {"fecha": "2027-02-01", "monto": 610000,
             "factor": 1.13, "futuro": true, "estimado": true}], "faltanDatos": false, "indiceUltimoPeriodo": "2026-11-11", "avisos": {"inquilino": "2026-11-05T14:02:11.123456Z"}}
            """,
            "/v1/rendiciones/listas": """
            [{"contratoId": "k1", "periodo": "2026-10-01", "propiedadTitulo": "Mendoza 2350", "propietarioNombre": "Lucía Méndez", "cobrado": 540000, "moneda": "ARS"}]
            """,
            "/v1/actividad": """
            [{"id": 101, "actorTipo": "usuario", "actorId": "u1", "actorNombre": "Sofía Paz", "accion": "mover", "entidad": "operacion", "entidadId": "o1", "antes": {"etapa": "visita"},
             "despues": {"etapa": "reserva"}, "creadoEn": "2026-11-12T10:41:00Z", "entidadTitulo": "Mendoza 2350"}]
            """,
            "/v1/inmobiliaria": ##"""
            {"id": "i1", "slug": "luna", "nombre": "Luna Propiedades", "web": "https://luna.corredor.com.ar", "marca": {"frase": "Hola", "colorPrimario": "#1e3a5f"},
             "legales": {"razonSocial": null, "cuit": null, "corredorResponsable": null, "matricula": "1234", "colegio": "CUCICBA"}}
            """##,
            "/v1/agenda": "[\(cita)]",
            "/v1/agenda/a1": cita,
            "/v1/contactos": "[\(contacto)]",
            "/v1/contactos/c1": contacto,
            "/v1/contactos/c1/notas": "[{\"id\": \"n1\", \"tipo\": \"nota\", \"texto\": \"Busca con balcón\", \"ocurrioEn\": \"2026-11-11T15:00:00Z\", \"autorId\": \"u1\"}]",
            "/v1/contactos/c1/propiedades": """
            [{"propiedadId": "p1", "titulo": "Mendoza 2350, 5.º A", "direccion": "Mendoza 2350, 5.º A", "barrio": "Belgrano", "precio": 172000, "moneda": "USD", "fotoId": null,
             "estado": "visita", "visitaEn": null, "operacionId": null, "puntaje": null, "enviadaEn": null, "reservaVenceEl": null}]
            """,
            "/v1/operaciones": "[\(operacion)]",
            "/v1/operaciones/o1": operacion,
            "/v1/operaciones/o1/historial": """
            [{"id": "e1", "tipo": "etapa", "texto": null, "datos": {"desde": "visita", "hasta": "reserva"}, "autorId": "u1", "autorNombre": "Sofía Paz", "creadoEn": "2026-11-11T15:00:00Z"},
             {"id": "e2", "tipo": "nota", "texto": "Firmó la reserva", "datos": {}, "autorId": "u1", "autorNombre": "Sofía Paz", "creadoEn": "2026-11-11T16:00:00Z"}]
            """,
            "/v1/contratos": "[\(contrato)]",
            "/v1/contratos/k1": contrato,
            "/v1/contratos/k1/cobros": """
            [{"periodo": "2026-10", "esperado": 540000, "cobro": {"id": "b1", "periodo": "2026-10", "monto": 540000, "moneda": "ARS", "numero": 482}}]
            """,
            "/v1/contratos/k1/rendiciones": """
            [{"id": "r1", "periodo": "2026-10", "moneda": "ARS", "cobrado": 540000, "comision": 27000, "neto": 513000, "estado": "pendiente"}]
            """,
            "/v1/contratos/k1/rendiciones/r1": """
            {"id": "r1", "periodo": "2026-10", "moneda": "ARS", "cobrado": 540000, "comision": 27000, "comisionPorcentaje": 5, "neto": 513000, "estado": "pendiente",
             "items": []}
            """,
            "/v1/objetivos": """
            [{"id": "ob1", "agenteId": "u1", "agenteNombre": "Sofía Paz", "metrica": "visitas_hechas", "meta": 20, "desde": "2026-11-01", "hasta": "2026-11-30", "avance": 8,
             "porcentaje": 40, "creadoEn": "2026-11-01T10:00:00Z"}]
            """,
            "/v1/respuestas-guardadas": """
            [{"id": "r1", "titulo": "Requisitos para alquilar", "texto": "Hola {nombre}, pedimos garantía propietaria o seguro de caución.", "usos": 12, "creadaPor": null,
             "actualizadoEn": "2026-11-01T12:00:00Z"}]
            """,
            "/v1/proveedores": """
            [{"id": "pr1", "nombre": "Plomería Rossi", "cuit": "20-12345678-9", "rubro": "plomeria", "telefono": "+5491144443333", "email": null, "notas": null, "creadoEn": "2026-10-01T12:00:00Z",
             "trabajos": 8, "edificios": 2}]
            """,
            "/v1/papelera": """
            [{"entidad": "propiedad", "id": "p9", "titulo": "Soler 4120", "detalle": "Venta · Palermo", "borradoEn": "2026-11-10T10:00:00Z", "borradoPor": "Sofía Paz"}]
            """,
            "/v1/indices": "[{\"codigo\": \"icl\", \"ultimoPeriodo\": \"2026-11-11\", \"ultimoValor\": 23.4567, \"actualizadoEn\": \"2026-11-12T10:30:00Z\"}]",
            "/v1/informe": """
            {"dias": 12, "masVistas": [{"propiedadId": "p1", "titulo": "Mendoza 2350", "vistas": 42}], "totalVistas": 120, "origenes": [{"origen": "web", "cantidad": 5}],
             "totalContactos": 9, "embudo": [{"etapa": "nuevo", "cantidad": 4}], "cerradas": 2, "diasPromedioCierre": 38, "honorarios": [{"moneda": "USD", "monto": 11200}],
             "caidas": 1, "motivoCaida": "Precio"}
            """,
            "/v1/web/barrios": "[{\"nombre\": \"Palermo\", \"cantidad\": 4}]",
            "/v1/panel/estructura": ##"""
            {"partes": [{"clave": "inmobiliaria", "titulo": "Mi inmobiliaria", "grupos": [{"titulo": "", "items": [{"clave": "web", "nombre": "Mi web", "palabras": ["logo"]},
             {"clave": "configuracion", "nombre": "Datos de la inmobiliaria", "palabras": []}, {"clave": "plan", "nombre": "Tu plan", "palabras": []}]}]}, {"clave": "herramientas",
             "titulo": "Herramientas", "grupos": [{"titulo": "Alquileres", "items": [{"clave": "cobranzas", "nombre": "Cobranzas", "palabras": ["cobrar"]}, {"clave": "contratos",
             "nombre": "Contratos", "palabras": []}]}]}], "rapidas": [{"clave": "captar", "nombre": "Captar"}, {"clave": "propiedad", "nombre": "Propiedad"}, {"clave": "contacto",
             "nombre": "Contacto"}, {"clave": "visita", "nombre": "Visita"}, {"clave": "contrato", "nombre": "Contrato"}, {"clave": "cobrar", "nombre": "Cobrar"},
             {"clave": "web", "nombre": "Mi web"}], "alta": {"pasos": [{"clave": "nombre", "titulo": "Nombre y dirección", "texto": "Un texto corto.", "obligatorio": true,
             "peso": 10, "hecho": true}, {"clave": "logo", "titulo": "Tu logo", "texto": "Un texto corto.", "obligatorio": true, "peso": 15, "hecho": true}, {"clave": "marca",
             "titulo": "Colores y frase", "texto": "Un texto corto.", "obligatorio": false, "peso": 10, "hecho": false}, {"clave": "portada", "titulo": "Foto de portada",
             "texto": "Un texto corto.", "obligatorio": false, "peso": 10, "hecho": false}, {"clave": "contacto", "titulo": "Contacto", "texto": "Un texto corto.",
             "obligatorio": true, "peso": 15, "hecho": true}, {"clave": "legales", "titulo": "Datos legales", "texto": "Un texto corto.", "obligatorio": false, "peso": 10,
             "hecho": false}, {"clave": "rubros", "titulo": "Qué hacen y dónde", "texto": "Un texto corto.", "obligatorio": false, "peso": 10, "hecho": false}, {"clave": "arranque",
             "titulo": "Tu primera propiedad", "texto": "Un texto corto.", "obligatorio": false, "peso": 10, "hecho": false}, {"clave": "publicar", "titulo": "Así quedó tu web",
             "texto": "Un texto corto.", "obligatorio": false, "peso": 10, "hecho": false}], "completo": 40, "faltan": ["marca", "portada", "legales", "rubros", "arranque",
             "publicar"], "minimoListo": true, "terminada": false}, "rubros": ["alquileres"], "escondido": true, "marca": {"logoUrl": null, "colorPrimario": "#e53935",
             "colorSecundario": "#ffd54f"}}
            """##,
            "/v1/web/borrador": ##"""
            {"marca": {"frase": "Hola", "whatsapp": "1155550000", "colorPrimario": "#e53935"}, "hayBorrador": true, "en": "2026-11-05T21:00:00.000000Z"}
            """##,
            "/v1/web/previa": "{\"token\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}",
            "/v1/buscar": """
            [{"tipo": "propiedad", "id": "p1", "titulo": "Mendoza 2350", "subtitulo": "Belgrano · venta"}, {"tipo": "contacto", "id": "c1", "titulo": "Lucía Méndez",
             "subtitulo": null}, {"tipo": "reserva", "id": "r1", "titulo": "Mendoza 2350", "subtitulo": "Seña USD 2.000"}]
            """,
            "/v1/panel/insignias": """
            {"mensajes": 2, "preguntas": 1, "bandeja": 3, "cobranzas": 1, "avisos": 4, "paraHacer": 2, "enLaCalle": [{"id": "u2", "nombre": "Martín Ríos", "foto": null}]}
            """,
            "/v1/clima": "{\"zona\": \"Belgrano\", \"temperatura\": 22, \"codigo\": 1}",
            "/v1/whatsapp/numero": """
            {"conectado": true, "telefono": "+54 11 3392-0071", "appPropia": false, "estado": "desconectado", "estadoMotivo": "Meta cerró la sesión.", "estadoEn": "2026-11-06T12:12:00Z"}
            """,
            "/v1/whatsapp/conversaciones/cuentas": "{\"esperando\": 1, \"mias\": 0, \"sinDueno\": 1, \"fueraDeVentana\": 0, \"noLeidas\": 1, \"todas\": 3}",
            "/v1/mercadolibre": "{\"disponible\": true, \"conectada\": true, \"apodo\": \"LUNAPROP\", \"reautorizar\": false, \"preguntasSinResponder\": 2}",
            "/v1/contratos/vencimientos": """
            [{"contratoId": "k1", "tipo": "ajuste", "fecha": "2026-11-20", "dias": 14, "monto": 610000, "moneda": "ARS", "contrato": {"id": "k1", "propiedadTitulo": "Mendoza 2350",
             "contactoNombre": "Lucía Méndez", "ajusteIndice": "icl"}, "avisados": ["inquilino"]}]
            """,
            "/v1/cobranzas/atrasadas": """
            [{"contratoId": "k1", "periodo": "2026-10-01", "vence": "2026-10-10", "monto": 520000, "moneda": "ARS", "estimado": false, "propiedadTitulo": "Gorriti 4820",
             "contactoId": "c1", "contactoNombre": "Lucía Méndez", "agenteId": null, "punitorioDiario": 0.5}]
            """,
            "/v1/propiedades/resumen": """
            {"total": 12, "venta": 7, "alquiler": 4, "temporario": 1, "conError": 0, "sinPublicar": 2, "sinVistas": 1, "sinAgente": 0, "mias": 5, "destacadas": 1,
             "borradores": 1, "barrios": [{"barrio": "Belgrano", "cantidad": 4}]}
            """,
            "/v1/propiedades/p1/actas/a1": """
            {"id": "a1", "propiedadId": "p1", "contratoId": "k1", "tipo": "entrada", "fecha": "2026-11-01", "items": [{"ambiente": "Living", "descripcion": "Paredes",
             "cantidad": 1, "estado": "bueno", "notas": null, "fotos": [], "fotosUrl": []}], "observaciones": null, "creadaPor": "u1", "creadoEn": "2026-11-01T12:00:00Z",
             "firmas": {}}
            """,
            "/v1/propiedades/p1/actas/a1/links": """
            [{"id": "l1", "parte": "inquilino", "venceEn": "2026-11-13T12:00:00Z", "revocadoEn": null, "usadoEn": null, "creadoEn": "2026-11-06T12:00:00Z", "estado": "vigente"}]
            """,
            "/v1/propiedades/p1/actas/a1/devolucion": "{\"Living|paredes\": {\"quien\": \"inquilino\", \"importe\": 15000}}",
            "/v1/propiedades/p1/vistas": "{\"total\": 42, \"dias\": [{\"dia\": \"2026-11-05\", \"cantidad\": 6}, {\"dia\": \"2026-11-06\", \"cantidad\": 9}]}",
            "/v1/propiedades/p1/reservas": "[\(reserva)]",
            "/v1/propiedades/p1/tarifas": """
            [{"id": "t1", "propiedadId": "p1", "nombre": "Temporada alta", "desde": "2026-12-15", "hasta": "2027-02-28", "precio": 120000, "moneda": "ARS", "periodo": "noche",
             "nochesMinimas": 3}]
            """,
            "/v1/contratos/k1/rendiciones/r1/imprimir": """
            {"inmobiliaria": {"nombre": "Inmobiliaria Sur", "marca": null}, "periodo": "2026-11-01", "moneda": "ARS", "propiedadTitulo": "Gorriti 4820", "propiedadDireccion": "Gorriti 4820",
             "propietario": "Juan Pérez", "inquilino": "Lucía Méndez", "cobrado": 540000, "comisionPorcentaje": 5, "comision": 27000, "items": [{"id": "i1", "descripcion": "Canilla",
             "monto": 15000, "creadoEn": "2026-11-02T12:00:00Z", "archivoId": null}], "gastos": 15000, "neto": 498000, "estado": "pendiente", "notas": null, "pagadoEl": "2026-11-08",
             "proximo": {"indice": "icl", "fecha": "2027-02-01", "monto": 610000, "estimado": true}, "numero": null}
            """,
            "/v1/ia/registro": """
            [{"id": 7, "conexionId": "x1", "usuarioId": "u1", "personaNombre": "Sofía Paz", "cliente": "Claude", "herramienta": "buscar_propiedades", "permiso": "leer",
             "resultado": "ok", "detalle": "Buscó propiedades en Belgrano", "cantidad": 3, "entidad": null, "entidadId": null, "argumentos": {}, "duracionMs": 120,
             "creadoEn": "2026-11-12T10:30:00Z"}]
            """,
            "/v1/ia/solicitudes/sol_abcdefghijklmn": """
            {"cliente": {"nombre": "Claude", "sitio": "https://claude.ai", "logo": null, "verificado": true, "vuelta": "claude.ai"}, "inmobiliaria": {"id": "i1", "slug": "luna",
             "nombre": "Luna Propiedades"}, "rol": "duenio", "habilitada": true, "pedidos": ["borradores", "agendar"], "permitidos": ["leer", "borradores", "agendar"],
             "permisos": [{"permiso": "leer", "titulo": "Leer cartera, contactos, agenda y contratos", "detalle": "sólo lo que tu rol ve"}, {"permiso": "borradores",
             "titulo": "Armar borradores", "detalle": "mensajes, propiedades, notas · vos los revisás y mandás"}, {"permiso": "agendar", "titulo": "Agendar visitas",
             "detalle": "con deshacer, como si lo hicieras vos"}], "nunca": "Mandar mensajes, cobrar, liquidar, borrar: nunca desde la IA, siempre lo confirma una persona en Corredor.",
             "aviso": "Tus datos se tratan según la Ley 25.326.", "venceEn": "2026-11-06T20:00:00Z"}
            """,
            "/v1/inmobiliaria/dominio": """
            {"dominio": "lunapropiedades.com.ar", "verificado": false, "web": "https://luna.corredor.com.ar", "registros": [{"tipo": "CNAME", "nombre": "www", "valor": "luna.corredor.com.ar"}],
             "registro": null}
            """,
            "/v1/contactos/resumen": """
            {"total": 12, "tipos": {"comprador": 5, "propietario": 3}, "esperando": 1, "etiquetas": [{"texto": "Con crédito", "cuenta": 2}]}
            """,
            "/v1/contactos/deudas": """
            [{"contratoId": "k1", "contactoId": "c2", "contactoNombre": "Lucía Méndez", "telefono": null, "propiedadTitulo": "Mendoza 2350", "periodo": "2026-11",
             "vence": "2026-11-10"}]
            """,
            "/v1/sugerencias": """
            [{"id": "s1", "estado": "pendiente", "accion": "Mandarle la ficha", "destacado": "Valeria busca 3 amb. en Belgrano. Mendoza 2350 le encaja.", "contactoId": "c1",
             "propiedadId": "p1", "agenteId": "u1"}]
            """,
            "/v1/indices/icl": "[{\"periodo\": \"2026-08-01\", \"valor\": 21.35}, {\"periodo\": \"2026-11-05\", \"valor\": 24.1}]",
            "/v1/informe/mensual": """
            {"mes": "2026-10", "anterior": "2026-09", "actual": {"consultas": 40, "visitas": 18, "reservas": 3, "cierres": 2, "captaciones": 4, "caidas": 1, "honorarios": {"USD": 11200}},
             "mesAnterior": {"consultas": 35, "visitas": 15, "reservas": 2, "cierres": 1, "captaciones": 5, "caidas": 0, "honorarios": {"USD": 6000}}, "inmobiliaria": "Corredor Demo",
             "serie": [{"mes": "2026-10", "monto": 11200}], "moneda": "USD", "equipo": [{"id": "u1", "nombre": "Sofía Paz", "rol": "agente", "captadas": 2, "visitas": 9,
             "cierres": 2, "honorarios": {"USD": 11200}}], "caidas": [{"motivo": "Precio", "cantidad": 1}], "rendiciones": {"cantidad": 3, "emitidas": 2, "neto": {"ARS": 1500000},
             "comision": {"ARS": 120000}, "pendientes": 1}}
            """,
            "/v1/documentos": """
            [{"id": "d1", "archivoId": "a1", "nombre": "Contrato firmado.pdf", "tipo": "application/pdf", "bytes": 120000, "subidoPor": "u1", "creadoEn": "2026-11-01T12:00:00Z",
             "url": "/v1/archivos/a1/contenido"}]
            """,
            "/v1/borradores": """
            [{"id": "b1", "actualizadoEn": "2026-11-06T12:00:00Z", "datos": {"paso": 1, "datos": {"operacion": "alquiler", "tipo": "departamento", "direccion": "Gorriti 4820",
             "barrio": "Palermo", "precio": 540000, "moneda": "ARS", "ambientes": 3, "fotos": [{"id": "f1", "url": "https://api.corredor.test/publico/archivos/i1/f1"}],
             "descripcion": "", "titulo": "", "tituloPropio": false, "comodidades": [], "sugeridas": [], "publicar": {"web": true, "mercadolibre": true, "zonaprop": true,
             "argenprop": false}, "propiedad": {"id": "p1", "nombre": "Gorriti 4820"}, "inicio": "2026-12-01", "meses": 36, "monto": 540000, "indice": "icl", "ajusteMeses": 6,
             "documentos": []}}}]
            """,
            "/v1/reservas": "[\(reserva)]",
            "/v1/reservas/r1": reserva,
            "/v1/temporada/reservas/r1": """
            {"id": "r1", "propiedadId": "p1", "contactoId": "c1", "huespedNombre": "Diego Funes", "huespedTelefono": "+5491144440000", "huespedes": 3, "entrada": "2026-12-20",
             "salida": "2026-12-27", "estado": "confirmada", "monto": 700000, "moneda": "ARS", "sena": 200000, "notas": null, "propiedadNumero": 412, "propiedadTitulo": "Mendoza 2350",
             "contactoNombre": "Diego Funes", "noches": 7, "saldo": 500000, "creadaPor": "u1", "creadoEn": "2026-11-01T10:00:00Z", "actualizadoEn": "2026-11-01T10:00:00Z",
             "checkin": {"saldo": false, "deposito": false, "inventario": false, "dni": []}, "llavesEn": null, "motivo": "huesped"}
            """,
            "/v1/temporada/calendario": """
            {"desde": "2026-12-01", "hasta": "2026-12-31", "dias": 31, "propiedades": [{"id": "p1", "numero": 412, "titulo": "Mendoza 2350", "nochesOcupadas": 7, "ocupacion": 0.23,
             "reservas": [{"id": "r1", "entrada": "2026-12-20", "salida": "2026-12-27", "estado": "confirmada", "huesped": "Diego Funes", "motivo": "huesped"}]}]}
            """,
            "/v1/publicaciones": """
            [{"id": "x1", "propiedadId": "p1", "propiedad": "Mendoza 2350", "portal": "mercadolibre", "estado": "publicada", "url": "https://articulo.mercadolibre.com.ar/MLA-1",
             "error": null, "visitas": 120, "visitasSemana": 40, "consultas": 3, "publicadaEn": "2026-11-01T10:00:00Z"}]
            """,
            "/v1/publicaciones/resumen": """
            {"portales": [{"portal": "mercadolibre", "activos": 4, "pausados": 0, "conError": 0, "pendientes": 1, "visitas": 120, "visitasSemana": 40, "visitasSemanaAnterior": 32,
             "feed": null, "leidoEn": null}], "difundibles": 4, "faltan": [], "reservadas": 1, "webVisitasSemana": 80, "webVisitasSemanaAnterior": 70}
            """,
            "/v1/revision": """
            [{"id": "b1", "estado": "pendiente", "tipo": "mensaje", "canal": "whatsapp", "asunto": null, "texto": "Hola Valeria, te paso la ficha de Mendoza 2350.",
             "motivo": "Busca 3 ambientes en Belgrano", "contactoId": "c1", "propiedadId": "p1", "operacionId": null, "contratoId": null, "contactoNombre": "Valeria Gómez",
             "propiedadTitulo": "Mendoza 2350", "deLaIA": true, "creadoEn": "2026-11-06T10:00:00Z", "resueltoEn": null}]
            """,
            "/v1/emprendimientos": """
            [{"id": "m1", "slug": "torre-arce", "nombre": "Torre Arce", "masterplanUrl": null, "tipo": "edificio", "estado": "en_obra", "descripcion": null, "direccion": "Arce 300",
             "barrio": "Las Cañitas", "avance": 60, "entrega": "2027-12", "desarrolladora": "Arce SA", "precioDesde": 120000, "moneda": "USD", "publicado": true, "fotosUrl": [],
             "unidades": {"total": 24, "disponibles": 10, "reservadas": 4, "vendidas": 10}}]
            """,
            "/v1/web/versiones": """
            [{"id": "v1", "creadaEn": "2026-11-05T21:00:00Z", "autor": "Mariana Luna", "desdeId": null, "plantilla": "clasica", "marca": {"frase": "Hola"}}]
            """,
            "/v1/invitaciones": """
            [{"id": "inv1", "email": "lara@gmail.com", "rol": "agente", "venceEn": "2026-11-12T12:00:00Z", "creadaEn": "2026-11-05T12:00:00Z"}]
            """,
            "/v1/invitaciones/vista": """
            {"inmobiliaria": "Luna Propiedades", "invita": "Lucía Méndez", "rol": "agente", "email": "martin@lunaprop.com.ar", "venceEn": "2026-11-13T12:00:00Z"}
            """,
            "/v1/inmobiliarias/disponible": "{\"slug\": \"luna\", \"valido\": true, \"libre\": true}",
            "/v1/perfil": """
            {"usuarioId": "u1", "email": "martin@lunaprop.com.ar", "nombre": "Martín", "apellido": "Ríos", "foto": null, "telefono": "+54 9 11 4823-1190", "whatsapp": null,
             "rol": "agente", "desde": "2026-01-10T12:00:00Z", "propiedades": 0, "barrios": null, "avisosPush": false}
            """,
            "/v1/perfil/web": "{\"fotoId\": null, \"enWeb\": true, \"presentacion\": \"Palermo y Belgrano\"}",
            "/v1/perfil/firma": "{\"texto\": null, \"activa\": false, \"sugerida\": \"Martín · Luna Propiedades\"}",
            "/v1/auth/sesiones": """
            [{"id": "a1b2c3d4e5f60718", "actual": true, "agente": "Corredor/1 CFNetwork/1 Darwin/25", "ip": "190.1.1.1", "creadaEn": "2026-11-01T12:00:00Z", "vistoEn": "2026-11-06T12:00:00Z"},
             {"id": "0f1e2d3c4b5a6978", "actual": false, "agente": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/130.0 Safari/537.36", "ip": null, "creadaEn": "2026-10-20T12:00:00Z",
             "vistoEn": "2026-11-05T09:00:00Z"}]
            """,
            "/v1/consorcios": "[\(consorcio)]",
            "/v1/consorcios/e1": """
            {"id": "e1", "nombre": "Consorcio Cabildo 2620", "direccion": "Av. Cabildo 2620, Belgrano", "cuit": "30-55912873-9", "modoExpensas": "prorrateo", "fondoTipo": "ninguno",
             "fondoValor": 0.0, "interesMensual": 3, "notas": null, "agenteId": null, "cbu": null, "diaVencimiento": 10, "diaSegundoVencimiento": 20, "fotoId": null,
             "fotoUrl": null, "reglamentoEn": null, "metricas": {"unidades": 2, "deudores": 1, "saldoAdeudado": 85000.0, "novedadesAbiertas": 1, "trabajosPendientes": 1,
             "trabajosVencidos": 0, "servicesPorVencer": 0}, "creadoEn": "2026-10-01T12:00:00Z", "actualizadoEn": "2026-11-01T12:00:00Z", "columnas": [{"id": "col1",
             "nombre": "General", "metodo": "coeficiente", "porDefecto": true, "orden": 0}]}
            """,
            "/v1/consorcios/alertas": """
            [{"consorcioId": "e1", "consorcio": "Consorcio Cabildo 2620", "tipo": "morosidad", "texto": "1 unidad con deuda", "monto": 85000.0}]
            """,
            "/v1/consorcios/e1/periodos": """
            [{"id": "p1", "periodo": "2026-10", "estado": "liquidada", "gastosTotal": 820000.0, "fondoTotal": 0.0, "total": 820000.0, "liquidadoEn": "2026-11-02T12:00:00Z",
             "notas": null, "cargado": 820000.0, "creadoEn": "2026-10-01T12:00:00Z"}, {"id": "p2", "periodo": "2026-11", "estado": "borrador", "gastosTotal": 0.0,
             "fondoTotal": 0.0, "total": 0.0, "liquidadoEn": null, "notas": null, "cargado": 310000.0, "creadoEn": "2026-11-01T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/periodos/p1": """
            {"id": "p1", "periodo": "2026-10", "estado": "liquidada", "gastosTotal": 820000.0, "fondoTotal": 0.0, "total": 820000.0, "liquidadoEn": "2026-11-02T12:00:00Z",
             "notas": null, "cargado": 820000.0, "creadoEn": "2026-10-01T12:00:00Z", "gastos": [{"id": "g1", "descripcion": "Abono ascensor", "tipo": "ordinaria",
             "monto": 310000.0, "columnaId": null, "proveedorId": "pr1", "documentoId": null, "fecha": "2026-11-03", "columna": null, "proveedor": "Plomería Rossi",
             "proveedorRubro": "plomeria", "creadoEn": "2026-11-03T12:00:00Z"}], "liquidaciones": [{"id": "l1", "periodoId": "p1", "periodo": "2026-10", "unidadId": "u1",
             "unidad": "1.º A", "propietario": "Raquel Oviedo", "email": "r@x.com", "propietarioId": "c1", "telefono": "+5491155550000", "desglose": [{"columnaId": "col1",
             "columna": "General", "base": 820000.0, "coeficiente": 0.5, "monto": 410000.0}], "subtotal": 410000.0, "fondo": 0.0, "total": 410000.0, "creadaEn": "2026-11-02T12:00:00Z"}]}
            """,
            "/v1/consorcios/e1/periodos/p2": """
            {"id": "p2", "periodo": "2026-11", "estado": "borrador", "gastosTotal": 0.0, "fondoTotal": 0.0, "total": 0.0, "liquidadoEn": null, "notas": null, "cargado": 310000.0,
             "creadoEn": "2026-11-01T12:00:00Z", "gastos": [{"id": "g1", "descripcion": "Abono ascensor", "tipo": "ordinaria", "monto": 310000.0, "columnaId": null,
             "proveedorId": "pr1", "documentoId": null, "fecha": "2026-11-03", "columna": null, "proveedor": "Plomería Rossi", "proveedorRubro": "plomeria", "creadoEn": "2026-11-03T12:00:00Z"}],
             "liquidaciones": []}
            """,
            "/v1/consorcios/e1/periodos/p2/prorrateo": """
            {"unidades": [{"unidadId": "u1", "desglose": [], "subtotal": 155000.0, "fondo": 0.0, "total": 155000.0}], "gastosTotal": 310000.0, "fondoTotal": 0.0, "total": 310000.0}
            """,
            "/v1/consorcios/e1/unidades": """
            [{"id": "u1", "etiqueta": "1.º A", "piso": null, "tipo": "departamento", "propietarioId": "c1", "inquilinoId": null, "notas": null, "expensaFija": 0.0,
             "coeficientes": {"col1": 50}, "propietario": "Raquel Oviedo", "inquilino": null, "propietarioEmail": "r@x.com", "propietarioTelefono": "+5491155550000",
             "saldo": 85000.0, "creadaEn": "2026-10-01T12:00:00Z", "actualizadaEn": "2026-10-01T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/unidades/u1/cuenta": """
            {"unidad": "1.º A", "saldo": 85000.0, "impagoDesde": "2026-10-02", "interesEstimado": 2550.0, "movimientos": [{"id": "m1", "fecha": "2026-10-02", "tipo": "cargo",
             "monto": 85000.0, "notas": "Expensas 10/2026", "periodoId": "p1", "creadoEn": "2026-10-02T12:00:00Z"}]}
            """,
            "/v1/consorcios/e1/deudores": """
            [{"unidadId": "u1", "unidad": "1.º A", "propietario": "Raquel Oviedo", "saldo": 85000.0, "impagoDesde": "2026-10-02", "dias": 35, "interesEstimado": 2550.0}]
            """,
            "/v1/consorcios/e1/trabajos": """
            [{"id": "t1", "unidadId": "u1", "estado": "pendiente", "prioridad": "alta", "titulo": "Filtración en cochera", "descripcion": "Gotea desde el lunes", "presupuesto": null,
             "costoReal": null, "responsable": null, "proveedorId": "pr1", "proveedor": "Plomería Rossi", "proveedorRubro": "plomeria", "proveedorTelefono": "+5491144440000",
             "unidad": "1.º A", "venceEl": null, "hechoEl": null, "adjuntos": [], "creadoEn": "2026-11-03T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/trabajos/t1": """
            {"id": "t1", "unidadId": "u1", "estado": "pendiente", "prioridad": "alta", "titulo": "Filtración en cochera", "descripcion": "Gotea desde el lunes", "presupuesto": null,
             "costoReal": null, "responsable": null, "proveedorId": "pr1", "proveedor": "Plomería Rossi", "proveedorRubro": "plomeria", "proveedorTelefono": "+5491144440000",
             "unidad": "1.º A", "venceEl": null, "hechoEl": null, "adjuntos": [{"archivoId": "a1", "nombre": "foto.jpg", "tipo": "image/jpeg", "bytes": 1000, "url": "/v1/archivos/a1/contenido"}],
             "creadoEn": "2026-11-03T12:00:00Z"}
            """,
            "/v1/consorcios/e1/novedades": """
            [{"id": "n1", "unidadId": null, "bienId": null, "tipo": "aviso", "estado": "abierto", "titulo": "Corte de agua el jueves", "descripcion": null, "costo": null,
             "responsable": "Ana", "ocurrioEl": "2026-11-04", "resueltoEl": null, "creadoEn": "2026-11-04T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/empleados": """
            [{"id": "em1", "nombre": "Rubén Sosa", "documento": "20-12345678-9", "categoria": "Encargado permanente con vivienda", "ingreso": "2015-03-01", "basico": 950000.0,
             "horario": null, "notas": null, "creadoEn": "2026-01-01T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/sueldos": """
            [{"id": "r1", "empleadoId": "em1", "empleado": "Rubén Sosa", "periodo": "2026-10", "notas": null, "basico": 950000.0, "antiguedad": 104500.0, "otrosRemunerativos": 0.0,
             "bruto": 1054500.0, "deducciones": [{"nombre": "Jubilación", "tasa": 11, "monto": 115995.0}], "deduccionesTotal": 115995.0, "neto": 938505.0, "sac": 87875.0,
             "creadoEn": "2026-11-01T12:00:00Z"}]
            """,
            "/v1/sueldos/escalas": """
            [{"id": "s1", "categoria": "Encargado permanente con vivienda", "basico": 950000.0, "vigenteDesde": "2026-10-01", "notas": null, "creadaEn": "2026-10-01T12:00:00Z"}]
            """,
            "/v1/consorcios/e1/reglamento": "{\"guardadoEn\": null, \"sinCambios\": true, \"cambios\": []}",
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
        // En la escena del simulador (sin escena, drawHierarchy devuelve la captura en negro).
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let ventana = escena.map { UIWindow(windowScene: $0) } ?? UIWindow()
        ventana.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        ventana.overrideUserInterfaceStyle = oscuro ? .dark : .light
        ventana.rootViewController = UIHostingController(rootView: raiz)
        ventana.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(segundos))
        if let dir = Self.capturas {
            let img = UIGraphicsImageRenderer(bounds: ventana.bounds).image { c in
                if !ventana.drawHierarchy(in: ventana.bounds, afterScreenUpdates: true) { ventana.layer.render(in: c.cgContext) }
            }
            let n = nombre.replacingOccurrences(of: "()", with: "").replacingOccurrences(of: "test", with: "")
            try? img.pngData()?.write(to: dir.appendingPathComponent("\(n)-\(oscuro ? "oscuro" : "claro").png"))
        }
        ventana.isHidden = true
    }

    /// Toda la navegación: cada destino apilado con `estado.abrir` (como lo hace la app, en `AnyHashable`)
    /// tiene que mostrar su pantalla y no el placeholder de SwiftUI. Así se rompió el 5/11: el destino
    /// se apilaba como `AnyHashable` y ninguna pila lo encontraba.
    func testNavegacionTotal() {
        let conf = URLSessionConfiguration.ephemeral
        conf.protocolClasses = [ApiFalsa.self]
        let estado = Estado(api: Api(base: URL(string: "https://api.prueba")!, token: "x", http: URLSession(configuration: conf)))
        estado.sesion = Sesion(usuario: .init(id: "u1", email: "mariana@luna.test", nombre: "Mariana", apellido: "Luna"), inmobiliariaId: "i1", rol: "duenio",
                               inmobiliarias: [.init(inmobiliariaId: "i1", slug: "luna", nombre: "Luna Propiedades", rol: "duenio")])
        estado.fase = .adentro
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let ventana = escena.map { UIWindow(windowScene: $0) } ?? UIWindow()
        ventana.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        ventana.rootViewController = UIHostingController(rootView: Principal().environment(estado).environment(estado.cola))
        ventana.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        let claves = ["mas", "configuracion", "equipo", "integraciones", "respuestas", "proveedores", "objetivos", "inventarios", "rendiciones",
                      "papelera", "actividad", "revision", "informe", "indices", "web", "difusion", "emprendimientos", "temporada", "reservas",
                      "consorcios", "importar", "ia", "firma", "plan", "suscripcion", "inmobiliaria", "whatsapp", "mercadolibre", "plantillas",
                      "editor", "invitaciones", "empezar"]
        let conId = ["vistas", "tarifas", "emprendimiento", "consorcio", "envios", "grabaciones", "reservas-propiedad", "documentos-propiedad",
                     "documentos-contrato", "bienes", "reglamento", "actas", "invitacion"]
        var destinos: [(String, AnyHashable)] = [
            ("FichaPropiedad", AFichaPropiedad(id: "p1")), ("Galeria", AGaleria(id: "p1")), ("AltaPropiedad", AAltaPropiedad()),
            ("Captadas", ACaptadas()), ("Chat", AChat(id: "c1")), ("PreguntaML", APreguntaML(id: "m1")), ("Agenda", AAgendaDia()),
            ("Cita", ACita(id: "ci1")), ("Contactos", AContactos()), ("FichaContacto", AFichaContacto(id: "k1")), ("Operaciones", AOperaciones()),
            ("FichaOperacion", AFichaOperacion(id: "o1")), ("Cobranzas", ACobranzas()), ("Contratos", AContratos()),
            ("FichaContrato", AFichaContrato(id: "t1")), ("Recibo", ARecibo(contrato: "t1", cobro: "b1")), ("Rendicion", ARendicion(contrato: "t1", id: "r1")),
            ("Inventario", AInventario(id: "p1")), ("Firmas", AFirmas(id: "a1")), ("Avisos", AAvisos()), ("ConfigAvisos", AConfigAvisos()),
            ("Perfil", APerfil()), ("Buscar", ABuscar(texto: "Mendoza")),
        ]
        // Los de la tanda 2 (propiedades, cobranzas, inventarios, consorcios y secciones con id).
        let nuevos: [(String, AnyHashable)] = [
            ("AltaPropiedad-borrador", AAltaPropiedad(borrador: "b1")), ("AvisoResponder", AAvisos(aviso: "v1", responder: "responder")),
            ("ArreglarPropiedad", AArreglarPropiedad(id: "p1")), ("MandarPropiedad", AMandarPropiedad(id: "p1", contacto: "c1")),
            ("EditarEnPaso", AEditarEnPaso(id: "p1", paso: "fotos")), ("Reserva", AReserva(id: "r1")), ("ReservaTemporada", AReservaTemporada(id: "r1")),
            ("MercadoLibre", AMercadoLibre()), ("TarjetaPropiedad", ATarjetaPropiedad(id: "p1")), ("Cartera", ACartera(barrio: "Belgrano")),
            ("RevisionIds", ARevisionIds(ids: "b1")), ("RegistrarCobro", ARegistrarCobro(contrato: "k1")),
            ("RecordarMes", ARecordarMes(contrato: "k1", periodo: "2026-11")), ("ContratosFiltro", AContratosFiltro(vista: "ajustan")),
            ("AltaContrato", AAltaContrato(borrador: "b1")), ("RendicionVista", ARendicionVista(contrato: "k1", id: "r1")),
            ("Recorrida", ARecorrida(id: "p1", tipo: "devolucion")), ("Devolucion", ADevolucion(id: "p1")),
            ("LiquidarConsorcio", ALiquidarConsorcio(consorcio: "e1")), ("TrabajoConsorcio", ATrabajoConsorcio(consorcio: "e1", id: "t1")),
            ("FichaConsorcioEn", AFichaConsorcioEn(id: "e1", pestana: "unidades", pedido: "deben")),
            ("Seccion-tarjeta-agente", ASeccion(clave: "tarjeta-agente", id: "u2")),
            ("Seccion-autorizar-ia", ASeccion(clave: "autorizar-ia", id: "sol_abcdefghijklmn")),
            // ACarteraAgente no va: lo registra Equipo en su propio body, no `destinos()`.
        ]
        destinos += nuevos
        destinos += claves.map { ("Seccion-\($0)", AnyHashable(ASeccion(clave: $0))) }
        destinos += conId.map { ("Seccion-\($0)", AnyHashable(ASeccion(clave: $0, id: "x1"))) }

        var rotos: [String] = []
        for (nombre, d) in destinos {
            estado.pilas = [:]
            estado.pestana = .inicio
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let antes = PantallasMostradas.cuenta
            // Si se cae (como el CALayer en ciclo del 6/11), el log dice en cuál.
            print("NAVEGACION abre \(nombre)")
            estado.abrir(d)
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            if PantallasMostradas.cuenta == antes { rotos.append(nombre) }
        }
        ventana.isHidden = true
        XCTAssertEqual(rotos, [], "Estos destinos no muestran su pantalla (¿placeholder de SwiftUI?): \(rotos)")
    }

    /// El mapa a nivel barrio con tres propiedades (no a nivel edificio, sin lugares de interés).
    func testMapa() throws {
        let json = """
        [{"id": "p1", "titulo": "Mendoza 2350, 5.º A", "precio": 172000, "moneda": "USD", "lat": -34.5627, "lng": -58.4563},
         {"id": "p2", "titulo": "Thames 2240", "precio": 611800, "moneda": "ARS", "lat": -34.5870, "lng": -58.4250},
         {"id": "p3", "titulo": "Gorriti 5530", "precio": 340000, "moneda": "USD", "lat": -34.5850, "lng": -58.4380}]
        """
        let props = try Api.decodificador.decode([Propiedad].self, from: Data(json.utf8))
        montar(MapaCartera(props: props, senales: [:]).frame(height: 600).padding(16), segundos: 4)
    }

    func testInicioDuena() { montar(InicioRaiz()) }
    func testInicioAgente() { montar(InicioRaiz(), rol: "agente") }
    func testInicioSinNada() {
        ApiFalsa.respuestas = ["/v1/panel": "{}"]
        montar(InicioRaiz(), rol: "agente")
    }
    func testBuscar() { montar(BuscarTodo(texto: "Mendoza")) }
    func testAvisos() { montar(Avisos()) }
    func testConfigAvisos() { montar(ConfigAvisos()) }
    /// APerfil abre MiPerfil (el viejo `Perfil` ya no está).
    func testPerfil() { montar(MiPerfil()) }
    func testPropiedades() { montar(PropiedadesRaiz()) }
    func testFicha() { montar(FichaPropiedad(id: "p1")) }
    func testGaleria() { montar(Galeria(id: "p1", indice: 0)) }
    func testAlta() { montar(AltaPropiedad(editar: nil)) }
    func testAltaEditar() { montar(AltaPropiedad(editar: "p1")) }
    func testCaptadas() { montar(Captadas()) }
    func testMensajes() { montar(MensajesRaiz()) }
    func testChat() { montar(Chat(id: "w1")) }
    func testML() { montar(RespuestaML(id: "q1")) }
    func testAgenda() { montar(AgendaRaiz(apilada: true)) }
    func testMas() { montar(MasRaiz()) }
    /// «Más» con la estructura de la API ya cargada (Mi inmobiliaria, Herramientas, el porcentaje).
    func testMasConEstructura() { montar(MasConEstructura()) }
    /// El alta en cada paso (los da la API: los mismos que el panel).
    func testAltaInmobiliaria() {
        for paso in ["logo", "marca", "portada", "contacto", "legales", "rubros", "arranque", "publicar"] {
            montar(AltaInmobiliaria(inicial: paso), segundos: 1.5, nombre: "Alta-\(paso)")
        }
    }
    func testMiWeb() { montar(MiWeb(), segundos: 2) }
    /// La bienvenida de quien se suma a un equipo (foto, WhatsApp, avisos y apariencia).
    func testBienvenida() { montar(Bienvenida(), rol: "agente") }
    func testMasAgente() { montar(MasRaiz(), rol: "agente") }
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
                  "papelera", "actividad", "revision", "informe", "indices", "web", "difusion", "consorcios", "ia", "importar", "no-existe",
                  "plan", "suscripcion", "inmobiliaria", "whatsapp", "mercadolibre", "plantillas", "editor", "invitaciones", "empezar",
                  "emprendimientos", "temporada", "reservas", "firma"] {
            montar(Seccion(clave: c, id: nil), segundos: 1, nombre: "Seccion-\(c)")
        }
        // Las que cuelgan de una propiedad, un contrato, un consorcio o un emprendimiento.
        for c in ["documentos-propiedad", "documentos-contrato", "bienes", "reglamento", "envios", "grabaciones", "reservas-propiedad", "emprendimiento", "consorcio"] {
            montar(Seccion(clave: c, id: "x1"), segundos: 1, nombre: "Seccion-\(c)")
        }
        // Las de la tanda 2, con ids que la API simulada conoce.
        for (c, id) in [("actas", "p1"), ("tarjeta-agente", "u2"), ("autorizar-ia", "sol_abcdefghijklmn"), ("invitacion", "tok_abcdefghijklmnopqrstuv"),
                        ("consorcio", "e1"), ("vistas", "p1"), ("tarifas", "p1"), ("reservas-propiedad", "p1"), ("actividad", "ia")] {
            montar(Seccion(clave: c, id: id), segundos: 1, nombre: "Seccion-\(c)-\(id)")
        }
    }
    func testEntrada() { montar(Entrada()) }
    func testElegirInmobiliaria() { montar(ElegirInmobiliaria()) }
    func testBloqueo() { montar(Bloqueo(), segundos: 1) }
    func testPrincipal() { montar(Principal()) }

    // MARK: Tanda 2: pantallas y hojas nuevas

    /// Lo que la API simulada responde en `ruta`, leído con el modelo de la app.
    private func respuesta<T: Decodable>(_ ruta: String, _ tipo: T.Type = T.self) throws -> T {
        let json = try XCTUnwrap(ApiFalsa.respuestas[ruta], "La API simulada no tiene \(ruta)")
        return try Api.decodificador.decode(T.self, from: Data(json.utf8))
    }

    // Propiedades, MIRA, temporada (parte 1)
    func testAltaBorrador() { montar(AltaPropiedad(editar: nil, borrador: "b1")) }
    func testAltaEnPaso() { montar(AltaPropiedad(editar: "p1", enPaso: "fotos")) }
    func testFichaArreglar() { montar(FichaPropiedad(id: "p1", arreglarAlAbrir: true)) }
    func testFichaMandar() { montar(FichaPropiedad(id: "p1", compartirAlAbrir: true, compartirCon: "c1")) }
    func testReserva() { montar(PantallaReserva(id: "r1")) }
    func testCheckinTemporada() { montar(CheckinTemporada(id: "r1")) }
    func testMercadoLibre() { montar(PantallaMercadoLibre()) }
    func testTarjetaVisita() { montar(TarjetaVisita(id: "p1")) }
    func testCarteraBarrio() { montar(PropiedadesRaiz(inicial: FiltrosCartera(barrio: ["Belgrano"]), titulo: "Más en Belgrano")) }
    func testRevisionIds() { montar(RevisionIA(ids: "b1")) }

    // Mensajes, agenda, contactos, operaciones, avisos (parte 2)
    func testAltaRapidaCita() { montar(AltaRapidaCita(alFormulario: {})) }
    func testLicenciasAgenda() { montar(LicenciasAgenda()) }
    func testImportarContactos() { montar(ImportarContactos()) }
    func testSeCayo() { montar(SeCayo(propiedad: "Mendoza 2350", contacto: "Valeria", alElegir: { _ in })) }
    func testPlataOperacion() throws {
        let o = try respuesta("/v1/operaciones/o1", Operacion.self)
        montar(PlataOperacion(o: o, agente: "Sofía"))
    }
    func testVincularPropiedad() { montar(VincularPropiedad(tiene: true, alElegir: { _ in })) }
    func testGuardarNumero() {
        montar(GuardarNumero(waId: "5491144712290", nombre: "", tipo: "comprador", guardar: { _, _ in true }))
    }
    func testGuardarRespuesta() { montar(GuardarRespuesta(texto: "Hola", alGuardar: { _ in })) }
    func testHojaResponderAviso() throws {
        let pagina = try respuesta("/v1/avisos", PaginaAvisos.self)
        let aviso = try XCTUnwrap(pagina.avisos.first)
        let accion = AvisoCentro.Accion(accion: "responder", titulo: "Responder", entrada: "texto")
        montar(HojaResponderAviso(aviso: aviso, accion: accion, mandar: { _ in nil }))
    }
    func testHorarioSilencio() { montar(HorarioSilencio(desde: 21, hasta: 8, domingos: true, guardar: { _, _, _ in })) }
    func testEditarMetas() {
        montar(EditarMetas(desde: "2026-11-01", hasta: "2026-11-30", mes: "noviembre", agentes: [], filas: [:], equipo: [], honorarios: nil))
    }
    func testEditarContacto() throws {
        let c = try respuesta("/v1/contactos/c1", Contacto.self)
        montar(EditarContacto(contacto: c, soloBusca: true))
    }
    func testNuevoContacto() { montar(EditarContacto()) }

    // Cobranzas y contratos (parte 3)
    func testRegistrarCobro() { montar(Cobranzas(registrar: true, contrato: "k1")) }
    func testContratosAjustan() { montar(Contratos(vista: "ajustan")) }
    func testFichaContratoRecordar() { montar(FichaContrato(id: "k1", recordar: "2026-11")) }
    func testRenovarContrato() { montar(AltaContrato(renovar: "k1")) }
    func testAltaContratoBorrador() { montar(AltaContratoPantalla(destino: AAltaContrato(borrador: "b1"))) }
    func testRendicionPropietario() { montar(RendicionVista(contrato: "k1", id: "r1", verComoPropietario: true)) }
    func testHojaCobro() {
        montar(HojaCobro(item: ACobrar(contratoId: "k1", contactoId: "c1", nombre: "Lucía Méndez", propiedad: "Gorriti 4820", periodo: "2026-11-01",
                                       esperado: 540000, moneda: "ARS", vence: "2026-11-10", punitorioDiario: 0.5)))
    }
    func testRecordarATodos() { montar(RecordarATodos(deudores: [])) }
    func testHojaMensajeWhatsApp() {
        montar(HojaMensajeWhatsApp(pedido: PedidoMensaje(titulo: "Recordarle a Lucía", contactoId: "c1", nombre: "Lucía Méndez",
                                                         texto: "¡Hola Lucía!", para: "recordatorio")))
    }

    // Consorcios (parte 3b)
    func testConsorcios() { montar(Consorcios()) }
    func testFichaConsorcio() {
        for p in ["resumen", "unidades", "expensas", "trabajos", "proveedores", "personal", "novedades"] {
            montar(FichaConsorcio(id: "e1", pestanaInicial: p), segundos: 1.5, nombre: "FichaConsorcio-\(p)")
        }
    }
    func testLiquidarConsorcio() { montar(LiquidarConsorcio(consorcio: "e1")) }
    func testTrabajoConsorcio() { montar(FichaTrabajoConsorcio(consorcio: "e1", id: "t1")) }

    // Inventarios y actas (parte 3c)
    func testListaActas() { montar(ListaActas()) }
    func testRecorridaDevolucion() { montar(Inventario(propiedad: "p1", tipoPedido: "devolucion")) }
    func testDevolucion() { montar(Devolucion(propiedad: "p1")) }

    // Inicio, Más y cuenta (partes 4, 4a y 4b)
    func testTusInmobiliarias() { montar(TusInmobiliarias()) }
    func testTarjetaAgente() { montar(TarjetaAgente(usuario: "u2")) }
    func testAutorizarIA() { montar(AutorizarIA(solicitud: "sol_abcdefghijklmn")) }
    func testCarteraAgente() { montar(CarteraAgente(usuario: "u2", nombre: "Martín Ríos")) }
    func testVerInvitacion() { montar(VerInvitacion(token: "tok_abcdefghijklmnopqrstuv"), rol: "agente") }
    func testPegarInvitacion() { montar(PegarInvitacion()) }
    func testCrearOtraInmobiliaria() { montar(CrearOtraInmobiliaria()) }
    func testMiPerfilAgente() { montar(MiPerfil(), rol: "agente") }
    func testFirmaYSesiones() { montar(FirmaYSesiones()) }
    func testRecuperarAcceso() { montar(RecuperarAcceso(email: "")) }
    func testIngresoMail() { montar(IngresoMail()) }
}

/// «Más» con la estructura cargada (como queda después de entrar).
private struct MasConEstructura: View {
    @Environment(Estado.self) private var estado
    var body: some View {
        MasRaiz().task { await estado.cargarEstructura() }
    }
}
