import StoreKit
import SwiftUI

/// «Tu plan», como un carrito: cómo estás hoy, mensual o anual, los tres planes como tarjetas para
/// elegir y el ticket con lo que pagás hoy, cuándo es el primer cobro y cuánto después. Se paga con el
/// App Store (los precios son los de la tienda de la cuenta de Apple); la letra chica, la que pide Apple.
struct PantallaPlan: View {
    @Environment(Estado.self) private var estado
    @State private var tienda = Tienda.compartida
    @State private var ciclo = "anio"
    @State private var elegido = "profesional"
    @State private var comprando = false
    @State private var restaurando = false
    @State private var gestionar = false
    @State private var elegibleGratis: [String: Bool] = [:]
    @State private var inicializado = false

    private var s: Suscripcion? { estado.suscripcion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let s {
                    cabecera(s)
                    if !estado.esDuenio {
                        nota("person.badge.key", "El plan lo elige y lo paga el dueño de la inmobiliaria. Si necesitás algo que tu plan no trae, pedíselo.")
                    } else if s.conMercadoPago {
                        nota("creditcard", "Tu plan se paga con Mercado Pago. Lo cambiás o lo das de baja desde ahí.")
                    }
                    Segmentado(opciones: [("mes", "Mensual"), ("anio", "Anual · 2 meses gratis")], elegido: $ciclo)
                    ForEach(s.planes) { p in tarjetaPlan(p, s) }
                    if estado.esDuenio, !s.conMercadoPago { ticket(s) }
                    if estado.esDuenio, !s.cobros.isEmpty { cobros(s) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.25), value: elegido)
            .animation(.snappy(duration: 0.25), value: ciclo)
        }
        .pantallaApilada("Tu plan")
        .manageSubscriptionsSheet(isPresented: $gestionar)
        .task(id: s?.planes.count) {
            guard let s else { await estado.cargarSuscripcion(); return }
            if !inicializado {
                inicializado = true
                if let p = s.esperando ?? s.plan { elegido = p; ciclo = s.ciclo }
            }
            await tienda.cargar(s.planes.flatMap { [$0.appleMes, $0.appleAnio] })
            for p in tienda.productos.values {
                if let sub = p.subscription { elegibleGratis[p.id] = await sub.isEligibleForIntroOffer }
            }
        }
        .refreshable { await estado.cargarSuscripcion() }
    }

    // MARK: Cómo estás hoy

    private func cabecera(_ s: Suscripcion) -> some View {
        let tono: Tono = s.estado == "vencida" ? .rojo : (s.estado == "prueba" && s.diasRestantes <= 3) ? .oro : .verde
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.nombreEstado).estilo(.caption).foregroundStyle(tono.tinta)
                .padding(.horizontal, 10).padding(.vertical, 4).background(tono.fondo, in: .capsule)
            Text(titulo(s)).font(Estilo.titulo3.font).foregroundStyle(C.texto).fixedSize(horizontal: false, vertical: true)
            Text(Formato.sinViudas(detalle(s))).estilo(.footnote).foregroundStyle(C.texto2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "person.2").foregroundStyle(C.texto3)
                Text(personas(s)).estilo(.footnote).foregroundStyle(C.texto2)
            }
            .padding(.top, 2)
            if s.medio == "apple", s.renueva, estado.esDuenio {
                Button("Administrar la suscripción") { gestionar = true }.buttonStyle(BotonTonal()).padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(tono.tinta).frame(width: 4) }
        .tarjeta()
        .clipShape(.rect(cornerRadius: M.rTarjeta, style: .continuous))
    }

    private func titulo(_ s: Suscripcion) -> String {
        switch s.estado {
        case "prueba": return "Tenés todo Corredor gratis hasta el \(Formato.fechaLarga(s.pruebaHasta))."
        case "activa": return "Próximo cobro: \(Formato.fechaLarga(s.proximoCobro ?? s.vigenteHasta))."
        case "baja": return "Tu plan no se renueva: vale hasta el \(Formato.fechaLarga(s.vigenteHasta))."
        default: return "Tu inmobiliaria está en sólo lectura."
        }
    }

    private func detalle(_ s: Suscripcion) -> String {
        switch s.estado {
        case "prueba": return "Elegí tu plan cuando quieras. Si no elegís, después queda en sólo lectura: nada se borra."
        case "activa": return s.medio == "apple" ? "Se cobra a tu cuenta de Apple." : "Se debita solo."
        case "baja": return "Elegí un plan para seguir sin cortes."
        default: return "Todo lo tuyo sigue acá y lo podés ver. Para volver a cargar, elegí un plan: se activa en el momento."
        }
    }

    private func personas(_ s: Suscripcion) -> String {
        if let c = s.agentes.cupo { return "\(s.agentes.usados) de \(c) \(c == 1 ? "persona" : "personas") que cargan" }
        return Formato.cantidad(s.agentes.usados, "persona carga", "personas cargan")
    }

    private func nota(_ icono: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono).foregroundStyle(C.texto3)
            Text(Formato.sinViudas(texto)).estilo(.footnote).foregroundStyle(C.texto2).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Los planes

    private func producto(_ p: Suscripcion.Plan, _ c: String) -> Product? { tienda.productos[p.producto(c)] }

    /// El precio de la tienda (USD en la Argentina, según la cuenta de Apple); sin la tienda, el de lista.
    private func precio(_ p: Suscripcion.Plan, _ c: String) -> String {
        producto(p, c)?.displayPrice ?? Formato.plata(p.precio(c))
    }

    private func ahorro(_ p: Suscripcion.Plan) -> String? {
        if let m = producto(p, "mes"), let a = producto(p, "anio") {
            let x = m.price * 12 - a.price
            return x > 0 ? x.formatted(m.priceFormatStyle) : nil
        }
        return Formato.plata(p.precioMes * 12 - p.precioAnio)
    }

    private func porMes(_ p: Suscripcion.Plan) -> String {
        if let a = producto(p, "anio") { return (a.price / 12).formatted(a.priceFormatStyle.precision(.fractionLength(0...2))) }
        return Formato.plata((p.precioAnio / 12).rounded())
    }

    private func tarjetaPlan(_ p: Suscripcion.Plan, _ s: Suscripcion) -> some View {
        let on = elegido == p.id
        let actual = s.plan == p.id && !s.soloLectura
        return Button {
            elegido = p.id
            Haptico.seleccion()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(on ? C.accion : C.linea2, lineWidth: on ? 6 : 2).frame(width: 20, height: 20)
                    }
                    Text(p.nombre).font(Estilo.total.font).foregroundStyle(C.texto)
                    if actual { chip("Tu plan", .verde) } else if p.destacado { chip("El más elegido", .oro) }
                    Spacer(minLength: 0)
                }
                Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(precio(p, ciclo)).font(Estilo.montoMeta.font).foregroundStyle(C.texto)
                        .contentTransition(.numericText())
                    Text(ciclo == "anio" ? "/año" : "/mes").estilo(.footnote).foregroundStyle(C.texto3)
                }
                if ciclo == "anio" {
                    Text("Equivale a \(porMes(p)) por mes\(ahorro(p).map { " · ahorrás \($0)" } ?? "")").estilo(.caption).foregroundStyle(C.texto3)
                }
                if on {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(p.incluye, id: \.self) { x in
                            Label { Text(x).estilo(.footnote).foregroundStyle(C.texto2) } icon: {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(C.accion)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.superficie, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: M.rTarjeta, style: .continuous).strokeBorder(on ? C.accion : C.linea, lineWidth: on ? 2 : 1))
            .sombraE2()
        }
        .buttonStyle(Presionable())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chip(_ t: String, _ tono: Tono) -> some View {
        Text(t).estilo(.caption).foregroundStyle(tono.tinta).padding(.horizontal, 8).padding(.vertical, 3).background(tono.fondo, in: .capsule)
    }

    // MARK: El ticket

    private func ticket(_ s: Suscripcion) -> some View {
        let plan = s.planes.first { $0.id == elegido } ?? s.planes[0]
        let prod = producto(plan, ciclo)
        let gratis = prod.flatMap { p -> Product.SubscriptionOffer? in
            guard elegibleGratis[p.id] == true, let o = p.subscription?.introductoryOffer, o.paymentMode == .freeTrial else { return nil }
            return o
        }
        let primerCobro = gratis.map { o in Calendar.current.date(byAdding: o.period.unit.componente, value: o.period.value, to: .now) ?? .now } ?? .now
        let cada = ciclo == "anio" ? "año" : "mes"
        let mismo = s.plan == plan.id && s.ciclo == ciclo && s.renueva && !s.soloLectura
        let sobran = plan.agentes > 0 ? max(0, s.agentes.usados - plan.agentes) : 0
        let precioTxt = precio(plan, ciclo)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Resumen").font(Estilo.total.font).foregroundStyle(C.texto)
            linea("Corredor \(plan.nombre)", ciclo == "anio" ? "anual" : "mensual", fuerte: true)
            linea("Personas que cargan", plan.agentes == 0 ? "sin tope" : plan.agentes == 1 ? "1" : "hasta \(plan.agentes)")
            if ciclo == "anio", let a = ahorro(plan) { linea("2 meses de regalo", "−\(a)", tono: C.okTinta) }
            linea("Total por \(cada)", precioTxt, fuerte: true)
            Rayita()
            HStack(alignment: .firstTextBaseline) {
                Text("Hoy pagás").font(Estilo.headline.font).foregroundStyle(C.texto)
                Spacer()
                Text(gratis != nil ? (prod.map { Decimal(0).formatted($0.priceFormatStyle) } ?? "0") : precioTxt)
                    .font(Estilo.montoMeta.font).foregroundStyle(C.texto).contentTransition(.numericText())
            }
            if let g = gratis {
                Label { Text(Formato.sinViudas("\(g.period.texto) gratis: el primer cobro es el \(Formato.fechaLarga(primerCobro)).")).estilo(.footnote) } icon: { Image(systemName: "gift") }
                    .foregroundStyle(C.okTinta).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(C.okFondo, in: .rect(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 8) {
                dato("Primer cobro", gratis == nil ? "Hoy · \(precioTxt)" : "\(Formato.fechaLarga(primerCobro)) · \(precioTxt)")
                dato("Después", "\(precioTxt) cada \(cada)")
                dato("Medio de pago", "Tu cuenta de Apple (App Store)")
            }
            if sobran > 0 {
                Label { Text(Formato.sinViudas("Hoy cargan \(s.agentes.usados) personas y este plan es para \(Formato.cantidad(plan.agentes, "persona", "personas")). Pasá \(Formato.cantidad(sobran, "persona", "personas")) a lector en Equipo o elegí un plan más grande.")).estilo(.footnote) } icon: { Image(systemName: "person.2") }
                    .foregroundStyle(C.oroTinta).padding(10).background(C.avisoFondo, in: .rect(cornerRadius: 10))
            }
            Button {
                Task { await comprar(plan) }
            } label: {
                if comprando { ProgressView().tint(C.sobreAccion) } else {
                    Text(mismo ? "Es tu plan actual" : gratis != nil ? "Empezar gratis" : "Suscribirme por \(precioTxt)")
                }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(prod == nil || mismo || sobran > 0 || comprando)
            .padding(.top, 4)
            if prod == nil, !tienda.cargando {
                Text(Formato.sinViudas("Pronto vas a poder elegir tu plan desde el iPhone. Mientras, seguís usando Corredor como hasta ahora."))
                    .estilo(.caption).foregroundStyle(C.texto3)
            }
            Button {
                Task { await restaurar() }
            } label: {
                if restaurando { ProgressView() } else { Text("Restaurar compras") }
            }
            .buttonStyle(BotonTexto(alto: 40))
            Text(Formato.sinViudas("La suscripción se cobra a tu cuenta de Apple y se renueva sola cada \(cada) al mismo precio, salvo que la des de baja al menos 24 horas antes de que termine el período, desde Ajustes › tu nombre › Suscripciones. Al vencer, tu inmobiliaria queda en sólo lectura y nada se borra."))
                .estilo(.caption).foregroundStyle(C.texto3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Términos de uso", destination: Api.web().appending(path: "terminos"))
                Link("Privacidad", destination: Api.web().appending(path: "privacidad"))
            }
            .estilo(.caption)
            .tint(C.primarioTexto)
        }
        .padding(18)
        .tarjeta()
    }

    private func linea(_ a: String, _ b: String, fuerte: Bool = false, tono: Color? = nil) -> some View {
        HStack {
            Text(a)
            Spacer(minLength: 8)
            Text(b).monospacedDigit()
        }
        .font(fuerte ? Estilo.fila.font : Estilo.subhead.font)
        .foregroundStyle(tono ?? (fuerte ? C.texto : C.texto2))
    }

    private func dato(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).estilo(.caption).foregroundStyle(C.texto3)
            Text(v).estilo(.footnote).foregroundStyle(C.texto)
        }
    }

    // MARK: Pagos

    private func cobros(_ s: Suscripcion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Tus pagos")
            VStack(spacing: 0) {
                ForEach(Array(s.cobros.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 12) {
                        Image(systemName: c.medio == "apple" ? "apple.logo" : "creditcard").foregroundStyle(C.texto3).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.detalle).estilo(.footnote).foregroundStyle(C.texto).lineLimit(2)
                            Text(Formato.dia(c.creadoEn)).estilo(.caption).foregroundStyle(C.texto3)
                        }
                        Spacer(minLength: 8)
                        if let x = c.importe { Text(Formato.plata(x, c.moneda ?? "ARS")).estilo(.footnote).monospacedDigit().foregroundStyle(C.texto) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5).padding(.leading, 48) } }
                }
            }
            .tarjeta()
        }
    }

    // MARK: Comprar

    private func comprar(_ plan: Suscripcion.Plan) async {
        guard let p = producto(plan, ciclo), let inmo = estado.sesion?.inmobiliariaId else { return }
        comprando = true
        defer { comprando = false }
        do {
            switch try await tienda.comprar(p, inmobiliaria: inmo) {
            case .listo(let s):
                estado.suscripcion = s
                Haptico.exito()
                estado.avisar("¡Listo! Tu plan \(plan.nombre) quedó activo.")
            case .pendiente:
                estado.avisar("La compra quedó pendiente de aprobación. Cuando se apruebe, tu plan se activa solo.")
            case .cancelada:
                break
            }
        } catch {
            estado.avisar(error)
        }
    }

    private func restaurar() async {
        restaurando = true
        defer { restaurando = false }
        do {
            if let s = try await tienda.restaurar() {
                estado.suscripcion = s
                estado.avisar("Listo, recuperamos tu plan.")
            } else {
                estado.avisar("No encontramos compras de Corredor en esta cuenta de Apple.", ok: false)
            }
        } catch {
            estado.avisar(error)
        }
    }
}

/// La línea punteada del ticket.
private struct Rayita: View {
    var body: some View {
        Line().stroke(C.linea2, style: StrokeStyle(lineWidth: 1, dash: [4, 4])).frame(height: 1)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            return p
        }
    }
}

extension Product.SubscriptionPeriod.Unit {
    var componente: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        @unknown default: return .day
        }
    }
}

extension Product.SubscriptionPeriod {
    /// «14 días», «1 mes».
    var texto: String {
        switch unit {
        case .day: return value == 1 ? "1 día" : "\(value) días"
        case .week: return value == 1 ? "1 semana" : "\(value) semanas"
        case .month: return value == 1 ? "1 mes" : "\(value) meses"
        case .year: return value == 1 ? "1 año" : "\(value) años"
        @unknown default: return "\(value)"
        }
    }
}

/// La franja de la suscripción en el Inicio y en «Más»: la última semana de prueba, el plan que no se
/// renueva o el sólo lectura, con el botón a «Tu plan».
struct AvisoPlan: View {
    @Environment(Estado.self) private var estado

    var body: some View {
        if let s = estado.suscripcion, s.pideAtencion {
            let vencida = s.estado == "vencida"
            let tono: Tono = vencida ? .rojo : s.diasRestantes <= 3 || s.estado == "baja" ? .oro : .verde
            Button { estado.abrir(ASeccion(clave: "plan")) } label: {
                HStack(spacing: 12) {
                    Image(systemName: vencida ? "lock" : "hourglass").font(.body.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(texto(s)).estilo(.subheadFuerte).fixedSize(horizontal: false, vertical: true)
                        Text(estado.esDuenio ? (s.estado == "baja" ? "Renovar" : "Elegí tu plan") : "Ver los planes").estilo(.footnote).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(tono.tinta)
                .padding(14)
                .background(tono.fondo, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(Presionable())
        }
    }

    private func texto(_ s: Suscripcion) -> String {
        switch s.estado {
        case "vencida": return estado.esDuenio ? "Tu prueba terminó: estás en sólo lectura. Todo sigue acá." : "La inmobiliaria está en sólo lectura."
        case "baja": return "Tu plan no se renueva: termina el \(Formato.dia(s.vigenteHasta))."
        default: return s.diasRestantes <= 1 ? "Hoy es el último día de tu prueba gratis." : "Te quedan \(s.diasRestantes) días de prueba gratis."
        }
    }
}
