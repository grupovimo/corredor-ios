import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// Los bloques del Inicio que el panel web tiene (lib/inicio/*) armados con las piezas de la app: lo
// urgente, «Tu día», la agenda de hoy, las sugerencias, cómo viene el mes, las cobranzas, el equipo,
// los primeros pasos, el próximo paso, las acciones rápidas, «Tu web» y el número caído.

// MARK: - Lo urgente

/// «Lo urgente» (de noche, «Para mañana»): cobros, consultas, reservas, preguntas y WhatsApp, cada uno con
/// su botón. Las consultas sin dueño se asignan («Asignar», la dueña) o se toman («Tomarla») ahí mismo.
struct UrgentesInicio: View {
    @Environment(Estado.self) private var estado
    var urgentes: [Urgente]
    var titulo: String
    var nuevas: Set<String>
    /// A quién se le puede dar una consulta (la dueña); nil: es para quien mira («Tomarla»).
    var personas: [(String, String)]?
    var asignar: (Urgente, (String, String)?) -> Void
    var cobrar: (CobranzaInicio) -> Void
    var recordar: (CobranzaInicio) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: titulo, cuenta: "\(urgentes.count)")
            VStack(spacing: 0) {
                ForEach(Array(urgentes.enumerated()), id: \.element.id) { i, u in
                    FilaUrgente(u: u, nueva: nuevas.contains(u.id), personas: personas, asignar: asignar, cobrar: cobrar, recordar: recordar)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }
}

struct FilaUrgente: View {
    @Environment(Estado.self) private var estado
    var u: Urgente
    var nueva: Bool
    var personas: [(String, String)]?
    var asignar: (Urgente, (String, String)?) -> Void
    var cobrar: (CobranzaInicio) -> Void
    var recordar: (CobranzaInicio) -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconoTono(icono: u.icono, tono: u.tono)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.titulo).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
                if !u.detalle.isEmpty {
                    Text(u.detalle).estilo(u.detalleTono == nil ? Estilo.footnote : Estilo.footnoteFuerte)
                        .foregroundStyle(u.detalleTono?.tinta ?? C.texto2).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            fin
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
        .frame(minHeight: 66)
        .background(nueva ? C.avisoFondo.opacity(0.6) : Color.clear)
        .animation(.easeOut(duration: 1.2), value: nueva)
        .contentShape(Rectangle())
        .onTapGesture { if let ir = u.ir { estado.abrir(ir) } }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var fin: some View {
        if let c = u.cobranza {
            HStack(spacing: 2) {
                if estado.escribe {
                    Button { recordar(c) } label: {
                        Image(systemName: "bubble.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(C.accion).frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Recordar")
                    pastilla("Registrar cobro") { cobrar(c) }
                } else {
                    Chevron()
                }
            }
        } else if u.consultaContacto != nil, estado.escribe {
            if let personas, estado.esDuenio {
                Menu {
                    Section("Asignar a") {
                        ForEach(personas, id: \.0) { p in Button { asignar(u, p) } label: { Label(p.1, systemImage: "person") } }
                    }
                } label: { etiquetaPastilla("Asignar") }
            } else {
                pastilla("Tomarla") { asignar(u, nil) }
            }
        } else if u.tipo == .reserva {
            pastilla("Ver la reserva") { if let ir = u.ir { estado.abrir(ir) } }
        } else if u.tipo == .whatsapp || u.tipo == .pregunta || u.tipo == .consulta {
            pastilla("Responder") { if let ir = u.ir { estado.abrir(ir) } }
        } else {
            Chevron()
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let c = u.cobranza, estado.escribe {
            Button { recordar(c) } label: { Label("Recordar", systemImage: "bubble.left") }
            Button { cobrar(c) } label: { Label("Registrar cobro", systemImage: "dollarsign.circle") }
        }
        if let ir = u.ir { Button { estado.abrir(ir) } label: { Label("Abrir", systemImage: "arrow.up.right") } }
    }

    private func pastilla(_ t: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) { etiquetaPastilla(t) }.buttonStyle(Presionable())
    }

    private func etiquetaPastilla(_ t: String) -> some View {
        Text(t).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
            .foregroundStyle(C.accion).lineLimit(1)
            .padding(.horizontal, 12).frame(height: 34)
            .background(C.hundida, in: Capsule())
            .frame(minHeight: 44)
    }
}

/// El error de un bloque solo (7C «Error parcial»): el resto del Inicio se ve igual.
struct ErrorBloque: View {
    var titulo: String
    var texto: String?
    var salida: (String, () -> Void)?
    var reintentar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconoTono(icono: "exclamationmark.triangle", tono: .rojo)
            VStack(alignment: .leading, spacing: 6) {
                Text(titulo).estilo(.filaLista).foregroundStyle(C.texto)
                if let texto { Text(Formato.sinViudas(texto)).estilo(.footnote).foregroundStyle(C.texto2) }
                HStack(spacing: 16) {
                    Button("Reintentar", action: reintentar).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                    if let salida { Button(salida.0, action: salida.1).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion) }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14).tarjeta()
    }
}

// MARK: - Número caído

/// «WhatsApp se desconectó a las 9:12», por qué (lo que dijo Meta) y la salida (el dueño reconecta).
struct NumeroCaidoInicio: View {
    @Environment(Estado.self) private var estado
    var numero: NumeroWhatsApp

    private var cuando: String {
        guard let f = numero.estadoEn else { return "" }
        let d = CuentasInicio.diasEntre(f, Date())
        return d == 0 ? "a las \(Formato.horaDe(f))" : d == 1 ? "ayer a las \(Formato.horaDe(f))" : "el \(Formato.fechaLarga(f))"
    }

    private var pieza: (icono: String, titulo: String, texto: String, boton: String, oro: Bool) {
        let c = cuando
        switch numero.estado {
        case "restringido":
            return ("nosign", "Meta restringió el WhatsApp\(c.isEmpty ? "" : " " + c)",
                    "Lo que mandes no sale hasta que Meta lo resuelva; lo que te escriban entra igual.", "Revisar", false)
        case "limitado":
            let desde = c.isEmpty ? "" : " desde " + (c.hasPrefix("a las") ? String(c.dropFirst(2)).trimmingCharacters(in: .whitespaces) : c)
            return ("speedometer", "WhatsApp está limitado\(desde)",
                    "Por ahora salen menos mensajes por día. Contestá a tiempo y sin repetir plantillas para que vuelva a la normalidad.", "Ver el número", true)
        default:
            return ("link", "WhatsApp se desconectó\(c.isEmpty ? "" : " " + c)",
                    "Los mensajes que lleguen mientras tanto no se pierden: entran cuando reconectes.", "Reconectar", false)
        }
    }

    var body: some View {
        let p = pieza
        HStack(alignment: .top, spacing: 12) {
            IconoTono(icono: p.icono, tono: p.oro ? .oro : .rojo)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                Text(Formato.sinViudas("\(numero.estadoMotivo.map { "\($0) " } ?? "")\(p.texto)")).estilo(.footnote).foregroundStyle(C.texto2)
                if estado.esDuenio {
                    Button(p.boton) { estado.abrir(ASeccion(clave: "integraciones")) }
                        .buttonStyle(BotonAccion()).frame(maxWidth: 180).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background((p.oro ? Tono.oro : Tono.rojo).fondo, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tu día y la agenda

/// «Tu día» (de noche, «Quedó pendiente de hoy»): las citas de hoy con su casilla.
struct TuDiaInicio: View {
    var titulo: String
    var citas: [Cita]
    var hechas: Set<String>
    var tildar: (Cita, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: titulo)
            VStack(spacing: 0) {
                ForEach(Array(citas.enumerated()), id: \.element.id) { i, c in
                    let hecha = hechas.contains(c.id)
                    Button { tildar(c, !hecha) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: hecha ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22, weight: .medium)).foregroundStyle(hecha ? C.accion : C.texto3)
                            if !hecha { Text(CuentasInicio.horaCorta(c.empiezaEn)).estilo(.subheadFuerte).foregroundStyle(C.texto).monospacedDigit() }
                            Text(c.titulo ?? c.donde).estilo(.filaLista).foregroundStyle(hecha ? C.texto3 : C.texto)
                                .strikethrough(hecha).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if !hecha { Image(systemName: c.icono).foregroundStyle(C.texto3) }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(hecha ? .isSelected : [])
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }
}

/// «Hoy en la agenda del equipo» / «Hoy en tu agenda» (de noche, mañana): hora, qué y quién; la que
/// viene enseguida, resaltada con «en 25 min».
struct AgendaHoyInicio: View {
    @Environment(Estado.self) private var estado
    var titulo: String
    var citas: [Cita]

    private var proxima: String? { citas.first { $0.estado == "pendiente" && $0.empiezaEn > Date() }?.id }

    private func que(_ c: Cita) -> String {
        guard let p = c.propiedadTitulo else { return c.titulo ?? c.donde }
        let extra = c.contactoNombre.map { " con \($0)" } ?? (c.lugar.flatMap { l in l.contains(p) || p.contains(l) ? nil : " · \(l)" } ?? "")
        return "\(c.tipoTexto) \(p)\(extra)"
    }

    private func quien(_ c: Cita) -> String {
        guard let n = c.agenteNombre?.nonEmpty else { return "Sin asignar" }
        let nombre = c.agenteId == estado.usuario?.id ? "Vos" : (n.split(separator: " ").first.map(String.init) ?? n)
        let falta = c.empiezaEn.timeIntervalSinceNow
        let cuando = c.id == proxima && falta > 0 && falta <= 3600 ? " · \(CuentasInicio.relativa(c.empiezaEn))" : ""
        return nombre + cuando
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TituloBloque(texto: titulo)
                Spacer()
                Button("Ver agenda") { estado.abrir(AAgendaDia()) }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
            }
            VStack(spacing: 0) {
                ForEach(Array(citas.enumerated()), id: \.element.id) { i, c in
                    let ya = c.id == proxima
                    HStack(alignment: .top, spacing: 12) {
                        Text(Formato.horaDe(c.empiezaEn)).estilo(.subheadFuerte).foregroundStyle(ya ? C.avisoTinta : C.texto).monospacedDigit()
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(que(c)).estilo(.filaLista).foregroundStyle(c.estado == "hecha" ? C.texto3 : C.texto)
                                .strikethrough(c.estado == "hecha").lineLimit(2)
                            HStack(spacing: 6) {
                                if let n = c.agenteNombre?.nonEmpty { AvatarIniciales(nombre: n, tam: 22) }
                                Text(quien(c)).estilo(.footnote).foregroundStyle(ya ? C.avisoTinta : C.texto2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(ya ? C.avisoFondo.opacity(0.5) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { estado.abrir(ACita(id: c.id)) }
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }
}

// MARK: - Próxima visita

/// La tarjeta verde de la próxima visita: la foto (y cuántas tiene), quién, qué busca y el precio;
/// «Cómo llegar», WhatsApp y llamar. De noche es la primera de mañana, con «Confirmar por WhatsApp».
struct TarjetaProximaVisita: View {
    @Environment(\.colorScheme) private var esquema
    @Environment(Estado.self) private var estado
    var p: ProximaVisita
    var noche = false

    private var cita: Cita { p.cita }
    private var quien: String { cita.contactoNombre ?? "" }

    private var que: String {
        let op = p.operacion == "venta" ? "compra" : p.operacion == "alquiler" ? "quiere alquilar" : ""
        return [quien.nonEmpty, op.nonEmpty, p.precio.map { Formato.plata($0, p.moneda ?? "ARS") }].compactMap { $0 }.joined(separator: " · ")
    }

    private var kicker: String {
        if noche { return "Primera visita · mañana \(CuentasInicio.horaCorta(cita.empiezaEn))" }
        let falta = CuentasInicio.relativa(cita.empiezaEn)
        return "Próxima visita · \(falta.hasPrefix("en") ? falta + " · " : "")\(CuentasInicio.horaCorta(cita.empiezaEn))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let f = p.foto, !noche {
                Foto(url: urlDeFoto(f, ancho: 800)).frame(height: 150).clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if p.fotos > 1 {
                            Label("\(p.fotos)", systemImage: "photo.on.rectangle").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font)
                                .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.5), in: Capsule()).padding(8)
                        }
                    }
                    .padding(.bottom, 8)
            }
            Label(kicker, systemImage: noche ? "calendar" : "clock")
                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.oro)
            Text(cita.propiedadTitulo ?? cita.titulo ?? cita.donde).font(Estilo(tamano: 24, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(.white)
                .padding(.top, 4)
            if !que.isEmpty { Text(que).estilo(.subhead).foregroundStyle(Color(hex: 0xCFE0D8)) }
            botones.padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // De noche, grafito con el borde oro (propuesta A): el verde lleno teñía todo el Inicio.
        .background {
            if esquema == .dark {
                RoundedRectangle(cornerRadius: M.rDestacada, style: .continuous).fill(C.superficie)
                    .overlay(RoundedRectangle(cornerRadius: M.rDestacada, style: .continuous).strokeBorder(C.oro.opacity(0.4), lineWidth: 1))
            } else {
                FondoTarjetaVerde()
            }
        }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE3()
        .onTapGesture { estado.abrir(ACita(id: cita.id)) }
    }

    @ViewBuilder
    private var botones: some View {
        HStack(spacing: 8) {
            if noche {
                if p.telefono != nil {
                    botonOro("Confirmar por WhatsApp", "bubble.left.fill") {
                        let nombre = quien.split(separator: " ").first.map { " " + $0 } ?? ""
                        Afuera.whatsapp(p.telefono, texto: "Hola\(nombre), te confirmo la visita de mañana a las \(CuentasInicio.horaCorta(cita.empiezaEn)) en \(cita.propiedadTitulo ?? cita.titulo ?? "").")
                    }
                }
            } else {
                botonOro("Cómo llegar", "location.fill") { Afuera.mapas(p.direccion ?? cita.lugar ?? cita.propiedadTitulo ?? "") }
                Button { llegando() } label: {
                    HStack(spacing: 6) {
                        Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 18, height: 18)
                        Text("Estoy llegando").font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.22)))
                }
                .accessibilityLabel("WhatsApp a \(quien): estoy llegando")
            }
            if p.telefono != nil {
                Button { Afuera.llamar(p.telefono) } label: {
                    Image(systemName: "phone.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.12), in: .rect(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.22)))
                }
                .accessibilityLabel("Llamar a \(quien)")
            }
        }
    }

    private func botonOro(_ t: String, _ icono: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Label(t, systemImage: icono)
                .font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Color(hex: 0x1A1405))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(LinearGradient(stops: [.init(color: Color(hex: 0xF7CB73), location: 0), .init(color: Color(hex: 0xF2BB57), location: 0.55),
                                                   .init(color: Color(hex: 0xE9AD44), location: 1)], startPoint: .top, endPoint: .bottom),
                            in: .rect(cornerRadius: 13, style: .continuous))
        }
    }

    private func llegando() {
        if let t = p.telefono {
            let nombre = quien.split(separator: " ").first.map(String.init) ?? ""
            Afuera.whatsapp(t, texto: "Hola \(nombre), estoy llegando a \(cita.donde).")
        } else {
            estado.avisar("La visita no tiene un contacto con teléfono.", ok: false)
        }
    }
}

// MARK: - Sugerencias

/// «Encontramos por vos» (o «3 sugerencias de hoy»): cada una con su botón, que la aplica y lleva a
/// la cosa, y la cruz para descartarla (con «Deshacer»).
struct SugerenciasInicio: View {
    var sugerencias: [SugerenciaInicio]
    var aplicar: (SugerenciaInicio) -> Void
    var descartar: (SugerenciaInicio) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(sugerencias.count > 1 ? "\(sugerencias.count) sugerencias de hoy" : "Encontramos por vos", systemImage: "sparkles")
                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
            ForEach(Array(sugerencias.enumerated()), id: \.element.id) { i, s in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        frase(s).font(Estilo(tamano: 16, peso: .regular, relativo: .body).font).foregroundStyle(C.texto)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { descartar(s) } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(C.texto2).frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Descartar")
                    }
                    Button { aplicar(s) } label: {
                        Text(s.boton.0).font(Estilo(tamano: 15, peso: .semibold, relativo: .subheadline).font)
                            .foregroundStyle(i == 0 ? C.sobreAccion : C.accion).padding(.horizontal, 16).frame(height: 44)
                            .background(i == 0 ? C.accion : C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(Presionable())
                }
                if i < sugerencias.count - 1 { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.avisoFondo, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
    }

    /// «{accion} **{destacado}**. {motivo}.»
    private func frase(_ s: SugerenciaInicio) -> Text {
        var t = Text(s.accion.map { $0 + " " } ?? "")
        if let d = s.destacado?.nonEmpty { t = t + Text(d).bold() + Text(".") }
        if let m = s.motivo?.nonEmpty { t = t + Text(" " + m + (m.hasSuffix(".") ? "" : ".")) }
        return t
    }
}

// MARK: - Cómo viene el mes

/// «Cómo viene noviembre»: cada objetivo con su barra y la raya de dónde debería ir hoy, el ritmo y los
/// días hábiles que quedan. Sin objetivos, los cierres del mes.
struct ComoVieneInicio: View {
    @Environment(Estado.self) private var estado
    var ritmos: [RitmoInicio]
    var cerradas: Int

    private func cifra(_ r: RitmoInicio) -> String { r.moneda.map { Formato.plata(r.avance, $0) } ?? Formato.numero(Int(r.avance)) }

    var body: some View {
        let habiles = CuentasInicio.diasHabilesRestantes()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cómo viene \(Formato.mesDe(Date()))").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                Spacer()
                Text("quedan \(Formato.cantidad(habiles, "día hábil", "días hábiles"))").estilo(.footnote).foregroundStyle(C.texto2)
            }
            if ritmos.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Cierres").estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Spacer()
                    Text(Formato.numero(cerradas)).font(Estilo(tamano: 20, peso: .bold, relativo: .title3).font).foregroundStyle(C.texto)
                    Text("este mes").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            ForEach(Array(ritmos.enumerated()), id: \.element.id) { i, r in fila(r, primera: i == 0) }
            Button(estado.esDuenio ? (ritmos.isEmpty ? "Poner los objetivos del mes" : "Ver objetivos por agente") : "Ver tus objetivos") {
                estado.abrir(ASeccion(clave: "objetivos"))
            }
            .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
        }
        .padding(16)
        .tarjeta()
    }

    private func fila(_ r: RitmoInicio, primera: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(r.nombre).estilo(.subheadFuerte).foregroundStyle(C.texto)
                Spacer()
                Text(cifra(r)).font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                Text("de \(Formato.numero(Int(r.meta)))").estilo(.footnote).foregroundStyle(C.texto2)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.hundida)
                    Capsule().fill(!r.adelante && r.moneda == nil ? C.errorTinta : C.accion).frame(width: g.size.width * r.ancho / 100)
                    Rectangle().fill(C.texto).frame(width: 2, height: 14).offset(x: g.size.width * r.raya / 100 - 1)
                }
            }
            .frame(height: 10)
            if r.moneda == nil {
                if r.adelante {
                    Label("Adelante del ritmo\(primera ? " · la raya marca dónde deberían ir hoy" : "")", systemImage: "chart.line.uptrend.xyaxis")
                        .estilo(.footnote).foregroundStyle(C.okTinta)
                } else {
                    Label("Atrás del ritmo: \(r.falta == 1 ? "falta 1" : "faltan \(Formato.numero(r.falta))") para ir al día", systemImage: "chart.line.downtrend.xyaxis")
                        .estilo(.footnote).foregroundStyle(C.errorTinta)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cobranzas del mes

/// «Cobranzas de noviembre»: cuánto se cobró de lo que hay que cobrar (en la moneda de la mayoría de
/// los alquileres), quién debe, qué vence, las rendiciones listas para mandar o «Todo cobrado».
struct CobranzasMesInicio: View {
    @Environment(Estado.self) private var estado
    var cobradas: [CobranzaInicio]
    var pendientes: [CobranzaInicio]
    var rendiciones: (Int, PanelInicio.Rendicion?)?

    private var moneda: String {
        var n: [String: Int] = [:]
        for c in cobradas + pendientes { n[c.moneda, default: 0] += 1 }
        return n.max { $0.value < $1.value }?.key ?? "ARS"
    }

    private func suma(_ cs: [CobranzaInicio]) -> Double { cs.filter { $0.moneda == moneda }.reduce(0) { $0 + $1.monto } }

    var body: some View {
        let cobrado = suma(cobradas)
        let atrasadas = pendientes.filter { $0.estado == "atrasado" }
        let deben = suma(atrasadas)
        let total = cobrado + suma(pendientes)
        let prox = pendientes.filter { $0.estado == "pendiente" }.sorted { $0.vence < $1.vence }
        let primero = prox.first?.vence
        let n = primero.map { p in prox.filter { $0.vence == p }.count } ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Button { estado.abrir(ACobranzas()) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cobranzas de \(Formato.mesDe(Date()))").font(Estilo(tamano: 17, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Formato.plata(cobrado, moneda)).font(Estilo(tamano: 22, peso: .extrabold, relativo: .title2).font).foregroundStyle(C.texto)
                        Text("cobrado de \(Formato.numero(Int(total)))").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            Capsule().fill(Color(hex: 0x2F9E6F)).frame(width: total > 0 ? g.size.width * cobrado / total : 0)
                            if deben > 0 { Capsule().fill(C.errorTinta).frame(width: total > 0 ? g.size.width * deben / total : 0) }
                            Spacer(minLength: 0)
                        }
                        .background(C.hundida, in: Capsule())
                    }
                    .frame(height: 10)
                }
            }
            .buttonStyle(Presionable())
            VStack(spacing: 0) {
                if !atrasadas.isEmpty {
                    fila("exclamationmark.circle", .rojo, "\(Formato.cantidad(atrasadas.count, "inquilino debe", "inquilinos deben")) \(Formato.plata(deben, moneda))", "Ver quién") { estado.abrir(ACobranzas()) }
                }
                if let primero {
                    fila("clock", .neutro, "\(Formato.numero(n)) \(n == 1 ? "vence" : "vencen") el \(CuentasInicio.elDia(primero))", "Avisar") { estado.abrir(ACobranzas()) }
                }
                if let rd = rendiciones, rd.0 > 0 {
                    fila("doc.text", .neutro, "\(Formato.cantidad(rd.0, "rendición lista", "rendiciones listas")) para mandar", "Revisar") {
                        if let p = rd.1 { estado.abrir(ARendicion(contrato: p.contratoId, id: p.id)) } else { estado.abrir(ASeccion(clave: "rendiciones")) }
                    }
                }
                if atrasadas.isEmpty && primero == nil && (rendiciones?.0 ?? 0) == 0 {
                    fila("checkmark.circle", .verde, "Todo cobrado", "Ver") { estado.abrir(ACobranzas()) }
                }
            }
        }
        .padding(16)
        .tarjeta()
    }

    private func fila(_ icono: String, _ tono: Tono, _ texto: String, _ boton: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 10) {
                Image(systemName: icono).foregroundStyle(tono == .neutro ? C.texto2 : tono.tinta)
                Text(texto).estilo(.subhead).foregroundStyle(C.texto).frame(maxWidth: .infinity, alignment: .leading)
                Text(boton).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
            }
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
    }
}

// MARK: - El equipo hoy

/// «El equipo hoy»: qué tiene cada uno (citas por tipo, mensajes sin responder o la licencia) y desde
/// cuándo; «al día» si no debe nada.
struct EquipoHoyInicio: View {
    var personas: [PersonaHoy]

    static let nombres: [String: (String, String)] = ["visita": ("visita", "visitas"), "llamado": ("llamado", "llamados"), "firma": ("firma", "firmas"),
                                                      "tasacion": ("tasación", "tasaciones"), "otro": ("cita", "citas")]
    static let ausente: [String: String] = ["licencia": "de licencia", "vacaciones": "de vacaciones", "enfermedad": "de licencia por enfermedad", "tramite": "de trámite"]

    private func que(_ p: PersonaHoy) -> String {
        if let l = p.licencia { return Self.ausente[l.tipo] ?? "de licencia" }
        if p.sinResponder > 0 { return Formato.cantidad(p.sinResponder, "mensaje sin responder", "mensajes sin responder") }
        let citas = p.citas.map { t, n in Formato.cantidad(n, (Self.nombres[t] ?? ("cita", "citas")).0, (Self.nombres[t] ?? ("cita", "citas")).1) }
        return citas.isEmpty ? "sin citas hoy" : citas.joined(separator: " y ")
    }

    private func vuelve(_ d: String) -> String {
        let p = d.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return "" }
        let mesHoy = Formato.calendario.component(.month, from: Date())
        return p[1] == mesHoy ? "vuelve el \(p[2])" : "vuelve el \(p[2])/\(p[1])"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "El equipo hoy")
            VStack(spacing: 0) {
                ForEach(Array(personas.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        AvatarIniciales(nombre: p.nombre, tam: 36, fondo: p.licencia == nil ? C.hundida : Tono.rojo.fondo, tinta: p.licencia == nil ? C.texto : Tono.rojo.tinta)
                        (Text(p.nombre).bold() + Text(" · " + que(p)))
                            .estilo(.subhead).foregroundStyle(C.texto).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let l = p.licencia {
                            Text(vuelve(l.vuelve)).estilo(.footnote).foregroundStyle(C.texto2)
                        } else if p.sinResponder > 0, let d = p.desde {
                            Text(Formato.hace(d)).estilo(.footnoteFuerte).foregroundStyle(C.avisoTinta)
                        } else {
                            Text("al día").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        if p.telefono != nil {
                            Button { Afuera.whatsapp(p.telefono) } label: {
                                Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 40, height: 44)
                            }
                            .accessibilityLabel("WhatsApp con \(p.nombre)")
                        }
                    }
                    .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
                    .frame(minHeight: 56)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }
}

// MARK: - Primeros pasos y el próximo paso

/// «Primeros pasos»: todos, con el avance («2/7»), tachados los hechos y el botón del que sigue.
/// «Ocultar» lo guarda en la API; al completarlo se va solo, con «¡Listo! Corredor ya está andando».
struct PrimerosPasos: View {
    var pasos: [PasoInicio]
    var hacer: (PasoInicio) -> Void
    var ocultar: (Bool) -> Void
    @State private var ido = false

    var body: some View {
        let hechos = pasos.filter(\.hecho).count
        let completo = !pasos.isEmpty && hechos == pasos.count
        let siguiente = pasos.firstIndex { !$0.hecho }
        Group {
            if completo && !ido {
                HStack(spacing: 12) {
                    IconoTono(icono: "party.popper", tono: .oro, tam: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¡Listo! Corredor ya está andando").estilo(.filaLista).foregroundStyle(C.texto)
                        Text(Formato.sinViudas("Completaste los primeros pasos.")).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).background(C.crema, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
                .task {
                    try? await Task.sleep(for: .seconds(6))
                    ido = true
                    ocultar(true)
                }
            } else if !completo {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(C.linea, lineWidth: 5)
                            Circle().trim(from: 0, to: CGFloat(hechos) / CGFloat(max(1, pasos.count)))
                                .stroke(C.accion, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text("\(hechos)/\(pasos.count)").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto)
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Primeros pasos").estilo(.filaLista).foregroundStyle(C.texto).accessibilityAddTraits(.isHeader)
                            Text(hechos == 0 ? "Arrancá por el primero" : "Te \(pasos.count - hechos == 1 ? "falta 1" : "faltan \(pasos.count - hechos)")")
                                .estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer(minLength: 0)
                        Button("Ocultar") { ocultar(false) }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).frame(minHeight: 44)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(pasos.enumerated()), id: \.element.id) { i, p in
                            filaPaso(p, ahora: i == siguiente)
                                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                }
                .padding(16)
                .background(C.crema, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func filaPaso(_ p: PasoInicio, ahora: Bool) -> some View {
        if p.hecho {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(C.accion)
                Text(p.texto).strikethrough().estilo(.subhead).foregroundStyle(C.texto3)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        } else {
            Button { hacer(p) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle").foregroundStyle(ahora ? C.accion : C.texto3)
                    Text(p.texto).estilo(ahora ? Estilo.subheadFuerte : Estilo.subhead).foregroundStyle(C.texto)
                    Spacer(minLength: 0)
                    Text(p.boton).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
        }
    }
}

/// «Para hacer» cuando no hay nada urgente (de noche, «Para mañana»): el próximo paso útil.
struct ProximoPasoInicio: View {
    var proximos: [ProximoInicio]
    var noche: Bool
    var hacer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: noche ? "Para mañana" : "Para hacer", cuenta: noche ? "nada urgente" : "nada urgente hoy")
            VStack(spacing: 0) {
                ForEach(Array(proximos.enumerated()), id: \.element.id) { i, p in
                    Button { hacer(p.clave) } label: {
                        HStack(spacing: 12) {
                            IconoTono(icono: p.icono, tono: i == 0 ? .oro : .verde)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                                Text(p.detalle).estilo(.footnote).foregroundStyle(C.texto2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(p.boton).font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                            Chevron()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 62).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
                if let s = proximos.first?.secundario {
                    Button(s) { hacer("importar") }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                }
            }
            .tarjeta()
        }
    }
}

/// Las acciones rápidas, siempre a la vista: en grilla de tres, ordenadas por lo que la persona más usa.
struct AccionesInicio: View {
    var acciones: [AccionInicio]
    var hacer: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(acciones) { a in
                Button { hacer(a.clave) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: a.icono).font(.system(size: 21, weight: .medium))
                            .foregroundStyle(a.clave == "captar" ? Color(hex: 0x1A1405) : C.accion)
                            .frame(width: 48, height: 48)
                            .background(a.clave == "captar" ? C.oro : C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                        Text(a.texto).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92).padding(.vertical, 6)
                    .tarjeta(16)
                }
                .buttonStyle(Presionable())
                .accessibilityLabel(a.clave == "web" ? "Ver mi web (se abre aparte)" : a.texto)
            }
        }
    }
}

// MARK: - Tu web

/// El link de la web de la inmobiliaria, siempre a mano: copiar, WhatsApp, compartir y el código QR para
/// la vidriera o la tarjeta.
struct CompartirWebInicio: View {
    @Environment(Estado.self) private var estado
    var web: String
    var nombre: String
    var alAbrir: () -> Void
    @State private var verQR = false

    private var url: URL? { URL(string: web) }
    private var dominio: String { web.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") }
    private var mensaje: String { "Mirá las propiedades de \(nombre.nonEmpty ?? "la inmobiliaria"): \(web)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconoTono(icono: "globe", tono: .verde, tam: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu web").estilo(.filaLista).foregroundStyle(C.texto)
                    Button {
                        alAbrir()
                        if let url { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
                    } label: {
                        Text(dominio).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(C.accion).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                Button { withAnimation(.snappy) { verQR.toggle() } } label: {
                    Image(systemName: "qrcode").font(.system(size: 22, weight: .medium)).foregroundStyle(C.accion).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Ver el código QR")
            }
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = web
                    Haptico.exito()
                    estado.avisar("Copiaste el link de tu web")
                } label: { Label("Copiar link", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(BotonAccion())
                Button { Afuera.whatsapp(nil, texto: mensaje) } label: { Label("WhatsApp", systemImage: "bubble.left").frame(maxWidth: .infinity) }
                    .buttonStyle(BotonHundido())
                if let url {
                    ShareLink(item: url, subject: Text(nombre), message: Text("Mirá las propiedades de \(nombre)")) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(C.texto)
                            .frame(width: 48, height: 44).background(C.hundida, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("Compartir")
                }
            }
            if verQR, let qr = CodigoQR.imagen(web) {
                HStack(alignment: .center, spacing: 14) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 132, height: 132)
                        .padding(6).background(.white, in: .rect(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Código QR de \(dominio)")
                        .contextMenu {
                            ShareLink(item: Image(uiImage: qr), preview: SharePreview("QR de \(dominio)", image: Image(uiImage: qr))) { Label("Compartir el QR", systemImage: "square.and.arrow.up") }
                        }
                    Text(Formato.sinViudas("Para la vidriera, las tarjetas o el cartel: lo escanean con la cámara y entran a tu web."))
                        .estilo(.footnote).foregroundStyle(C.texto2)
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .tarjeta()
    }
}

/// El código QR de un texto (CoreImage), nítido para imprimir.
enum CodigoQR {
    static func imagen(_ texto: String, escala: CGFloat = 10) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(texto.utf8)
        f.correctionLevel = "M"
        guard let salida = f.outputImage?.transformed(by: CGAffineTransform(scaleX: escala, y: escala)),
              let cg = CIContext().createCGImage(salida, from: salida.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
