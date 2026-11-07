import SwiftUI

// Piezas que comparten las pantallas de configuración (Inmobiliaria, Equipo, Integraciones, Proveedores,
// Respuestas, Corredor en tu IA): los errores por campo de la API, la fecha relativa de la web, el avatar
// con foto y el aviso de rol.

/// Un error de la API con sus errores por campo (`issues: [{path, message}]` del problem+json).
struct ErrorCampos: Error {
    var api: ErrorApi
    var campos: [String: String]
}

extension Api {
    /// Un pedido que, si la API lo rechaza, trae también el error de cada campo (para mostrarlo debajo de
    /// él, como la web). Devuelve la respuesta cruda.
    @discardableResult
    func pedirConCampos<C: Encodable>(_ metodo: String, _ ruta: String, _ cuerpo: C?, envio: String? = nil) async throws -> Data {
        do {
            return try await pedir(metodo, ruta, cuerpo: try cuerpo.map { try Api.codificador.encode($0) }, envio: envio)
        } catch let e as ErrorApi {
            throw ErrorCampos(api: e, campos: e.campos)
        }
    }
}

extension Estado {
    /// El error de un pedido con campos: el general va al aviso de abajo; devuelve los de cada campo.
    func camposDe(_ e: Error) -> [String: String] {
        if let c = e as? ErrorCampos {
            if c.campos.isEmpty { avisar(c.api) } else { avisar(c.api.detalle.isEmpty ? c.api.titulo : c.api.detalle, ok: false) }
            return c.campos
        }
        avisar(e)
        return [:]
    }
}

/// La fecha relativa de la web (`relativa` de lib/ui/formato.ts): «recién», «hace 2 h», «en 5 días»,
/// «mañana», «ayer», o «12 nov» si está lejos.
enum Relativa {
    static func de(_ f: Date, ahora: Date = Date()) -> String {
        let seg = Int(f.timeIntervalSince(ahora).rounded())
        let futuro = seg > 0
        let a = abs(seg)
        func envolver(_ t: String) -> String { futuro ? "en \(t)" : "hace \(t)" }
        if a < 3 { return "recién" }
        if a < 60 { return envolver("\(a) s") }
        if a < 3600 { return envolver("\(a / 60) min") }
        let cal = Calendar.current
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: ahora), to: cal.startOfDay(for: f)).day ?? 0
        if a < 6 * 3600 || dias == 0 { return envolver("\(a / 3600) h") }
        if dias == 1 { return "mañana" }
        if dias == -1 { return "ayer" }
        if abs(dias) < 7 { return envolver("\(abs(dias)) días") }
        return diaMes.string(from: f)
    }

    static let diaMes: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    /// «18 nov» (la fecha corta de las licencias, `fechaCorta` de la web).
    static func corta(_ dia: String) -> String { Fecha.dia(dia).map { diaMes.string(from: $0) } ?? dia }
}

/// La foto de la persona o sus iniciales.
struct AvatarPersona: View {
    var nombre: String
    var foto: String?
    var tam: CGFloat = 40
    var body: some View {
        if let f = foto, let u = URL(string: f), f.hasPrefix("http") {
            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { AvatarIniciales(nombre: nombre, tam: tam) }
                .frame(width: tam, height: tam).clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            let (fondo, tinta) = coloresAvatar(nombre)
            AvatarIniciales(nombre: nombre, tam: tam, fondo: fondo, tinta: tinta)
        }
    }
}

/// El error de un campo, debajo de él (la API o la validación de acá).
struct ErrorDeCampo: View {
    var texto: String?
    var body: some View {
        if let t = texto?.nonEmpty { MensajeError(texto: t).padding(.top, 2) }
    }
}

/// «Tu rol es Agente: podés ver estos datos…»: el candado arriba de lo que sólo cambia el dueño.
struct AvisoRol: View {
    var texto: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock").foregroundStyle(C.texto2)
            Text(Formato.sinViudas(texto)).estilo(.footnote).foregroundStyle(C.texto2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Un ícono de color dentro de una fila de Form, para los rubros y los permisos.
struct IconoFila: View {
    var icono: String
    var color: Color
    var body: some View {
        Image(systemName: icono).font(.system(size: 17, weight: .medium)).foregroundStyle(color).frame(width: 26)
            .accessibilityHidden(true)
    }
}

/// Una confirmación de las que la web pide en una hoja roja («¿Sacás a Lara del equipo?»).
struct Confirmacion: Identifiable {
    var id = UUID()
    var titulo: String
    var texto: String
    var boton: String
    var no: String = "No"
    var hacer: () -> Void
}

extension View {
    /// La confirmación roja de la web, como diálogo del sistema.
    func confirmacion(_ c: Binding<Confirmacion?>) -> some View {
        alert(c.wrappedValue?.titulo ?? "", isPresented: Binding(get: { c.wrappedValue != nil }, set: { if !$0 { c.wrappedValue = nil } }), presenting: c.wrappedValue) { x in
            Button(x.no, role: .cancel) {}
            Button(x.boton, role: .destructive) { x.hacer() }
        } message: { x in Text(x.texto) }
    }
}
