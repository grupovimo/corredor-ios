import SwiftUI

// Mandar un WhatsApp con el texto ya escrito (recordatorio, recibo, aviso de ajuste, rendición), como
// la web (lib/contratos/MensajeWhatsApp.svelte y la acción `mensaje` de lib/server/contratos.ts):
// - con el WhatsApp de la inmobiliaria conectado, sale desde Corredor (queda en la bandeja y en la
//   ficha); fuera de la ventana de 24 h, con la plantilla aprobada que sirva para eso;
// - sin WhatsApp conectado, o sin plantilla para fuera de 24 h, se abre wa.me con el texto en el
//   WhatsApp del teléfono.

/// Los textos de los mensajes y cómo se nombran los meses y los índices (lib/contratos/comun.ts).
enum TextosCobro {
    static let nombreIndice: [String: String] = ["icl": "ICL", "ipc": "IPC", "uva": "UVA", "fijo": "Fijo"]

    /// El primer nombre («Lucía Méndez» → «Lucía»). Para un comercio («Panadería Soler»), entero.
    static func primerNombre(_ n: String?) -> String {
        let t = (n ?? "").trimmingCharacters(in: .whitespaces)
        guard let p = t.split(separator: " ").first else { return "" }
        let comercio = ["panader", "caf", "kiosco", "almac", "estudio", "local", "farmac", "librer", "ferret"].contains { p.lowercased().hasPrefix($0) }
        return comercio ? t : String(p)
    }

    /// «2026-11-01» o «2026-11» → «noviembre».
    static func nombreMes(_ periodo: String) -> String {
        guard let d = Fecha.dia(String(periodo.prefix(7)) + "-01") else { return periodo }
        return Formato.mesDe(d)
    }

    /// «noviembre» si es de este año; si no, «noviembre 2025».
    static func mesConAnio(_ periodo: String, hoy: String = Formato.diaISO(Date())) -> String {
        let m = nombreMes(periodo)
        return periodo.prefix(4) == hoy.prefix(4) ? m : "\(m) \(periodo.prefix(4))"
    }

    /// «2026-11-12» → «12/11» (con el año: «12/11/26»).
    static func fechaCortita(_ f: String, anio: Bool = false) -> String {
        let p = f.prefix(10).split(separator: "-").map(String.init)
        guard p.count == 3 else { return f }
        return anio ? "\(p[2])/\(p[1])/\(p[0].suffix(2))" : "\(p[2])/\(p[1])"
    }

    static func hola(_ nombre: String?) -> String {
        let n = primerNombre(nombre)
        return "¡Hola\(n.isEmpty ? "" : " " + n)!"
    }

    static func recordatorio(nombre: String?, periodo: String, importe: Double, moneda: String, vence: String, hoy: String = Formato.diaISO(Date())) -> String {
        let mes = nombreMes(periodo)
        if vence < hoy {
            return "\(hola(nombre)) Te recordamos que el alquiler de \(mes) (\(Formato.plata(importe, moneda))) venció el \(fechaCortita(vence)). Si ya lo pagaste, avisanos y te mandamos el recibo. ¡Gracias!"
        }
        return "\(hola(nombre)) Te recordamos que el alquiler de \(mes) (\(Formato.plata(importe, moneda))) vence el \(fechaCortita(vence)). ¡Gracias!"
    }

    /// Uno solo por persona aunque deba varios meses («Recordar a todos»).
    static func recordatorioVarios(nombre: String?, meses: [String], total: Double, moneda: String) -> String {
        let nombres = meses.map(nombreMes)
        let lista = nombres.count > 1 ? nombres.dropLast().joined(separator: ", ") + " y " + (nombres.last ?? "") : (nombres.first ?? "")
        return "\(hola(nombre)) Te recordamos que tenés pendiente el alquiler de \(lista) (\(Formato.plata(total, moneda)) en total). Si ya lo pagaste, avisanos y te mandamos el recibo. ¡Gracias!"
    }

    static func sinEsquema(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    static func recibo(nombre: String?, periodo: String, url: String) -> String {
        "\(hola(nombre)) Te mandamos el recibo de \(nombreMes(periodo)): \(sinEsquema(url)). ¡Gracias!"
    }

    static func ajuste(nombre: String?, indice: String, fecha: String, desde: Double, hasta: Double, moneda: String) -> String {
        let i = nombreIndice[indice] ?? "el índice"
        return "\(hola(nombre)) Te avisamos que el \(fechaCortita(fecha)) el alquiler se ajusta por \(i): pasa de \(Formato.plata(desde, moneda)) a \(Formato.plata(hasta, moneda)). Cualquier duda, escribinos."
    }

    static func rendicion(nombre: String?, periodo: String, neto: Double, moneda: String, url: String) -> String {
        "\(hola(nombre)) Te mandamos la rendición de \(nombreMes(periodo)): \(Formato.plata(neto, moneda)). La ves acá: \(sinEsquema(url))"
    }

    /// «ICL cada 6 meses», «12 % fijo cada 4 meses», «sin ajuste».
    static func indiceCada(indice: String?, meses: Int?, porcentaje: Double?) -> String {
        guard let m = meses, m > 0 else { return "sin ajuste" }
        let cada = m == 1 ? "cada mes" : "cada \(m) meses"
        if indice == "fijo" { return "\(numero(porcentaje ?? 0)) % fijo \(cada)" }
        return "\(indice.flatMap { nombreIndice[$0] } ?? "Ajuste") \(cada)"
    }

    /// Un número con decimales sólo si los tiene («12», «1,5»).
    static func numero(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// El envío de un WhatsApp por el número de la inmobiliaria, o el wa.me de respaldo.
@MainActor
enum WhatsAppCorredor {
    struct Numero: Decodable { var conectado: Bool }
    struct Conversacion: Decodable { var id: String; var enVentana: Bool }
    struct Plantilla: Decodable { var nombre: String; var idioma: String; var categoria: String?; var parametros: Int }
    struct Contacto: Decodable { var nombre: String?; var telefono: String?; var email: String? }

    /// Para qué es el mensaje: elige la plantilla aprobada cuando la conversación está fuera de 24 h.
    static let plantillas: [String: String] = [
        "recordatorio": "recordatorio_(pago|cobro|alquiler)|cobr|pago|vencim|alquiler",
        "recibo": "recib|pago|cobr",
        "ajuste": "ajuste|aumento|actualizaci|alquiler",
        "rendicion": "rendici|liquidaci",
        "expensas": "expensa|liquidaci|consorci|recib"
    ]

    /// ¿Está conectado el WhatsApp de la inmobiliaria? (GET /v1/whatsapp/numero; si falla, no).
    static func conectado(_ api: Api) async -> Bool {
        do {
            let n: Numero = try await api.get("/v1/whatsapp/numero")
            return n.conectado
        } catch { return false }
    }

    static func waMe(_ telefono: String?, _ texto: String) -> URL? {
        let n = (telefono ?? "").filter(\.isNumber)
        var c = URLComponents(string: "https://wa.me/\(n)")
        c?.queryItems = [URLQueryItem(name: "text", value: texto)]
        return c?.url
    }

    /// Manda el texto. Devuelve el wa.me si hay que abrirlo en el teléfono (sin WhatsApp conectado o
    /// sin plantilla para fuera de 24 h); `nil` si salió desde Corredor.
    static func mandar(_ api: Api, contactoId: String, texto: String, para: String, parametros: [String]) async throws -> URL? {
        let contacto: Contacto = try await api.get("/v1/contactos/\(contactoId)")
        guard let tel = contacto.telefono?.nonEmpty else {
            throw ErrorApi(estado: 422, codigo: "sin_telefono", titulo: "Sin teléfono", detalle: "\(contacto.nombre ?? "Esta persona") no tiene teléfono cargado.")
        }
        guard await conectado(api) else { return waMe(tel, texto) }
        struct Abrir: Encodable { var contactoId: String }
        let conv: Conversacion = try await api.enviar("POST", "/v1/whatsapp/conversaciones", Abrir(contactoId: contactoId))
        if conv.enVentana {
            struct Texto: Encodable { var texto: String }
            try await api.hacer("POST", "/v1/whatsapp/conversaciones/\(conv.id)/mensajes", Texto(texto: texto))
            return nil
        }
        let todas: [Plantilla]
        do { todas = try await api.get("/v1/whatsapp/plantillas") } catch { todas = [] }
        let re = plantillas[para] ?? plantillas["recordatorio"]!
        let sirve: (Plantilla) -> Bool = { $0.nombre.range(of: re, options: .regularExpression) != nil }
        guard let p = todas.first(where: { $0.categoria?.uppercased() == "UTILITY" && sirve($0) }) ?? todas.first(where: sirve) else {
            return waMe(tel, texto)
        }
        struct Datos: Encodable { var nombre: String; var idioma: String; var parametros: [String] }
        struct Enviar: Encodable { var contactoId: String; var plantilla: Datos }
        let ps = (0..<max(0, p.parametros)).map { $0 < parametros.count ? parametros[$0] : "" }
        try await api.hacer("POST", "/v1/whatsapp/plantillas/enviar", Enviar(contactoId: contactoId, plantilla: Datos(nombre: p.nombre, idioma: p.idioma, parametros: ps)))
        return nil
    }
}

/// «Mensaje para Lucía» con el texto (se puede retocar) y «Mandar por WhatsApp». Al mandarlo queda la
/// burbuja con la hora y el tilde, y «Listo».
struct MensajeWhatsApp<Extra: View>: View {
    @Environment(Estado.self) private var estado
    var contactoId: String?
    var telefono: String?
    var nombre: String?
    @Binding var texto: String
    /// recordatorio · recibo · ajuste · rendicion (elige la plantilla fuera de 24 h).
    var para: String
    var parametros: [String] = []
    /// Lo que se lee después de mandarlo.
    var listo = "Quedó en la ficha y en la bandeja de WhatsApp."
    @Binding var enviado: Bool
    var alListo: () -> Void
    var extra: () -> Extra
    @State private var mandando = false
    @State private var porWaMe: URL?
    @State private var enviadoEn: Date?
    @State private var tel: String?
    @State private var conectado = false

    init(contactoId: String?, telefono: String?, nombre: String?, texto: Binding<String>, para: String, parametros: [String] = [],
         listo: String = "Quedó en la ficha y en la bandeja de WhatsApp.", enviado: Binding<Bool>, alListo: @escaping () -> Void,
         @ViewBuilder extra: @escaping () -> Extra) {
        self.contactoId = contactoId
        self.telefono = telefono
        self.nombre = nombre
        _texto = texto
        self.para = para
        self.parametros = parametros
        self.listo = listo
        _enviado = enviado
        self.alListo = alListo
        self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !enviado { escribir } else { mandado }
        }
        .task {
            conectado = await WhatsAppCorredor.conectado(estado.api)
            if telefono == nil, let contactoId {
                let c: WhatsAppCorredor.Contacto? = try? await estado.api.get("/v1/contactos/\(contactoId)")
                tel = c?.telefono
            }
        }
    }

    private var n: String { TextosCobro.primerNombre(nombre) }

    @ViewBuilder private var escribir: some View {
        Text("Mensaje para \(n.isEmpty ? "el contacto" : n)").estilo(.footnoteFuerte).foregroundStyle(C.texto2)
        TextField("", text: $texto, axis: .vertical)
            .lineLimit(3...8)
            .padding(.vertical, 12)
            .campoCorredor()
            .onChange(of: texto) { _, t in if t.count > 1000 { texto = String(t.prefix(1000)) } }
        Button { Task { await mandar() } } label: {
            HStack(spacing: 8) {
                if mandando { ProgressView().tint(C.sobreAccion) } else { Image(systemName: "bubble.left.fill") }
                Text(mandando ? "Mandando…" : "Mandar por WhatsApp")
            }
        }
        .buttonStyle(BotonPrincipal())
        .disabled(mandando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        extra()
    }

    @ViewBuilder private var mandado: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(texto).estilo(.subhead).foregroundStyle(C.texto).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text(enviadoEn.map { Formato.horaDe($0) } ?? "").estilo(.caption).foregroundStyle(C.texto3)
                if porWaMe == nil { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(C.azulTinta).accessibilityLabel("Enviado") }
            }
        }
        .padding(12)
        .background(C.okFondo, in: .rect(cornerRadius: 16, style: .continuous))
        Label(porWaMe == nil ? "Enviado. \(listo)" : "Lo abrimos en WhatsApp con el mensaje escrito.", systemImage: "checkmark.circle.fill")
            .estilo(.footnote).foregroundStyle(C.okTinta)
        if let porWaMe {
            Button { UIApplication.shared.open(porWaMe, options: [:], completionHandler: nil) } label: { Label("Abrir WhatsApp de nuevo", systemImage: "arrow.up.right.square") }
                .buttonStyle(BotonHundido())
        }
        Button("Listo") { alListo() }.buttonStyle(BotonPrincipal())
    }

    private func mandar() async {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let telefono = self.telefono ?? tel
        // Sin WhatsApp conectado: wa.me con el teléfono de la persona.
        if !conectado || contactoId == nil {
            guard let telefono = telefono?.nonEmpty, let u = WhatsAppCorredor.waMe(telefono, t) else {
                estado.avisar("\(n.isEmpty ? "Esta persona" : n) no tiene teléfono cargado.", ok: false)
                return
            }
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            porWaMe = u
            enviadoEn = Date()
            enviado = true
            return
        }
        mandando = true
        defer { mandando = false }
        do {
            let u = try await WhatsAppCorredor.mandar(estado.api, contactoId: contactoId!, texto: t, para: para, parametros: parametros)
            if let u { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
            porWaMe = u
            enviadoEn = Date()
            enviado = true
            Haptico.exito()
        } catch {
            let detalle = (error as? ErrorApi)?.detalle ?? "Probá de nuevo."
            estado.sugerir("No se mandó · \(detalle)", "Reintentar") { Task { await mandar() } }
        }
    }
}

extension MensajeWhatsApp where Extra == EmptyView {
    init(contactoId: String?, telefono: String?, nombre: String?, texto: Binding<String>, para: String, parametros: [String] = [],
         listo: String = "Quedó en la ficha y en la bandeja de WhatsApp.", enviado: Binding<Bool>, alListo: @escaping () -> Void) {
        self.init(contactoId: contactoId, telefono: telefono, nombre: nombre, texto: texto, para: para, parametros: parametros,
                  listo: listo, enviado: enviado, alListo: alListo, extra: { EmptyView() })
    }
}

/// Lo que hace falta para armar una hoja de WhatsApp (se usa con `.sheet(item:)`).
struct PedidoMensaje: Identifiable {
    let id = UUID()
    var titulo: String
    var descripcion: String? = nil
    var contactoId: String?
    var telefono: String? = nil
    var nombre: String?
    var texto: String
    var para: String
    var parametros: [String] = []
    var listo = "Quedó en la ficha y en la bandeja de WhatsApp."
    /// Salió el mensaje (por Corredor o abriendo wa.me): p. ej., anotar el aviso del ajuste.
    var alEnviar: (() -> Void)? = nil
}

/// Un WhatsApp con el texto armado, en una hoja: «Recordar», «Avisarle a Lucía» del ajuste, la
/// rendición al propietario. Mandarlo es el único toque: la hoja es la vista previa.
struct HojaMensajeWhatsApp: View {
    @Environment(\.dismiss) private var cerrar
    var pedido: PedidoMensaje
    @State private var texto = ""
    @State private var enviado = false
    @State private var avisado = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pedido.titulo).estilo(.tituloHojaChico).foregroundStyle(C.texto)
                    if let d = pedido.descripcion { Text(d).estilo(.texto14).foregroundStyle(C.texto2) }
                }
                MensajeWhatsApp(contactoId: pedido.contactoId, telefono: pedido.telefono, nombre: pedido.nombre, texto: $texto, para: pedido.para,
                                parametros: pedido.parametros, listo: pedido.listo, enviado: $enviado) { cerrar() }
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 16)
        }
        .background(C.superficie)
        .onAppear { texto = pedido.texto }
        .onChange(of: enviado) { _, e in
            if e && !avisado {
                avisado = true
                pedido.alEnviar?()
            }
        }
        .hojaTLW([.medium, .large])
    }
}

extension View {
    /// La hoja de WhatsApp para un pedido.
    func hojaMensaje(_ pedido: Binding<PedidoMensaje?>) -> some View {
        sheet(item: pedido) { p in HojaMensajeWhatsApp(pedido: p) }
    }
}
