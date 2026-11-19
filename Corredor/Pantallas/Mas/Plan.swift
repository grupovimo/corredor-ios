import StoreKit
import SwiftUI

/// «Tu plan», como un carrito: cómo estás hoy (y cuánto usás de cada tope), mensual o anual, los tres
/// planes como tarjetas para elegir y el ticket con lo que pagás hoy, cuándo es el primer cobro y cuánto
/// después. Bajar de plan no borra nada: el ticket dice qué queda en sólo lectura. Se paga con el
/// App Store (los precios son los de la tienda de la cuenta de Apple); la letra chica, la que pide Apple.
struct PantallaPlan: View {
    @Environment(Estado.self) private var estado
    @State private var tienda = Tienda.compartida
    @State private var ciclo = "anio"
    @State private var elegido = "inmobiliaria"
    @State private var comprando = false
    @State private var restaurando = false
    @State private var gestionar = false
    @State private var elegibleGratis: [String: Bool] = [:]
    @State private var inicializado = false
    @State private var confirmarBaja = false
    @State private var bajando = false

    private var s: Suscripcion? { estado.suscripcion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let s {
                    cabecera(s)
                    if !estado.esDuenio {
                        nota("person.badge.key", "El plan lo elige y lo paga el dueño de la inmobiliaria. Si necesitás algo que tu plan no trae, pedíselo.")
                    } else if s.conMercadoPago {
                        nota("creditcard", "Tu plan se paga con Mercado Pago. Para pasarlo al App Store, primero da de baja el débito acá abajo.")
                    } else if s.pagaAfuera {
                        nota("creditcard", s.medio == "google"
                             ? "Tu plan se paga con Google Play y se administra desde ahí. Para pasarlo al App Store, primero cancelalo en Google Play."
                             : "Tu plan se administra donde lo contrataste. Para pasarlo al App Store, primero dalo de baja ahí.")
                    }
                    Segmentado(opciones: [("mes", "Mensual"), ("anio", "Anual · 2 meses gratis")], elegido: $ciclo)
                    ForEach(s.planes) { p in tarjetaPlan(p, s) }
                    // Con otro medio no se compra acá: sin ticket ni letra chica de Apple.
                    if estado.esDuenio, !s.pagaAfuera { ticket(s) }
                    if estado.esDuenio, !s.cobros.isEmpty { cobros(s) }
                    if estado.esDuenio, s.medio == "mercadopago", s.renueva { baja(s) }
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
            uso(s).padding(.top, 6)
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
        case "prueba": return "Tenés el plan \(s.planQueRige?.nombre ?? "Inmobiliaria") gratis hasta el \(Formato.fechaLarga(s.pruebaHasta))."
        case "activa": return "Próximo cobro: \(Formato.fechaLarga(s.proximoCobro ?? s.vigenteHasta))\(s.importe.map { " · \(Formato.plata($0, s.moneda ?? "ARS"))" } ?? "")."
        case "baja": return "Tu plan no se renueva: vale hasta el \(Formato.fechaLarga(s.vigenteHasta))."
        default: return "Tu inmobiliaria está en sólo lectura."
        }
    }

    private func detalle(_ s: Suscripcion) -> String {
        switch s.estado {
        case "prueba": return "Elegí tu plan cuando quieras. Si no elegís, queda en sólo lectura 90 días para que exportes tus datos, y después se borran."
        case "activa": return s.comoSePaga
        case "baja": return "Elegí un plan para seguir sin cortes. Lo que ya pagaste no se pierde."
        default:
            let hasta = s.borraEn.map { "hasta el \(Formato.fechaLarga($0)), cuando se borra" } ?? "durante 90 días; después se borra"
            return "Todo lo tuyo sigue acá y lo podés ver y exportar \(hasta). Para volver a cargar, elegí un plan: se activa en el momento."
        }
    }

    /// Lo que usás del plan que rige: personas, propiedades activas, contratos y MIRA, con su barra (casi o
    /// en el tope: oro; pasado, después de bajar de plan: rojo).
    private func uso(_ s: Suscripcion) -> some View {
        var filas: [(String, Suscripcion.Uso)] = [("Personas que cargan", .init(usados: s.agentes.usados, tope: s.agentes.cupo))]
        if let t = s.topes {
            filas += [("Propiedades activas", t.propiedades), ("Contratos de alquiler", t.contratos), ("Carteles con MIRA este mes", t.mira)]
        }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(filas, id: \.0) { fila in
                let (nombre, u) = fila
                let lleno = u.tope.map { u.usados > $0 } ?? false
                let casi = u.tope.map { $0 > 0 && Double(u.usados) / Double($0) >= 0.85 } ?? false
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(nombre).estilo(.footnote).foregroundStyle(C.texto2)
                        Spacer(minLength: 8)
                        Text(u.tope.map { "\(u.usados) de \($0)" } ?? "\(u.usados) · sin tope")
                            .estilo(.footnote).monospacedDigit().foregroundStyle(lleno ? C.errorTinta : C.texto)
                    }
                    if let t = u.tope, t > 0 {
                        ProgressView(value: Double(min(u.usados, t)), total: Double(t))
                            .tint(lleno ? C.errorTinta : casi ? C.oroTinta : C.accion)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
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
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(p.incluye, id: \.self) { x in
                            Label { Text(x).estilo(.footnote).foregroundStyle(C.texto2) } icon: {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(C.accion)
                            }
                        }
                    }
                    .padding(.top, 8)
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
        let mas = s.deMas(plan)
        let precioTxt = precio(plan, ciclo)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Resumen").font(Estilo.total.font).foregroundStyle(C.texto)
            linea("Corredor \(plan.nombre)", ciclo == "anio" ? "anual" : "mensual", fuerte: true)
            linea("Personas que cargan", plan.agentes == 1 ? "1" : "hasta \(plan.agentes)")
            if ciclo == "anio", let doce = doceMeses(plan) { linea("12 meses × \(precio(plan, "mes"))", doce) }
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
            if mas.personas + mas.propiedades + mas.contratos > 0 {
                Label { Text(Formato.sinViudas(textoDeMas(mas))).estilo(.footnote) } icon: { Image(systemName: "info.circle") }
                    .foregroundStyle(C.oroTinta).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(C.avisoFondo, in: .rect(cornerRadius: 10))
            }
            if !s.pagaAfuera {
            Button {
                Task { await comprar(plan) }
            } label: {
                if comprando { ProgressView().tint(C.sobreAccion) } else {
                    Text(mismo ? "Es tu plan actual" : gratis != nil ? "Empezar gratis" : "Suscribirme por \(precioTxt)")
                }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(prod == nil || mismo || comprando)
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
            }
            Text(Formato.sinViudas("La suscripción se cobra a tu cuenta de Apple y se renueva sola cada \(cada) al mismo precio, salvo que la des de baja al menos 24 horas antes de que termine el período, desde Ajustes › tu nombre › Suscripciones. Al vencer, tu inmobiliaria queda en sólo lectura 90 días para que exportes tus datos; después se borran."))
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

    /// Bajar de plan no borra nada: lo que pasa el tope queda en sólo lectura hasta liberar lugar.
    private func textoDeMas(_ m: (personas: Int, propiedades: Int, contratos: Int)) -> String {
        var partes: [String] = []
        if m.personas > 0 { partes.append("\(Formato.cantidad(m.personas, "persona queda", "personas quedan")) sin cargar (pasalas a lector en Equipo)") }
        if m.propiedades > 0 { partes.append("\(Formato.cantidad(m.propiedades, "propiedad activa queda", "propiedades activas quedan")) fuera de tu web") }
        if m.contratos > 0 { partes.append("\(Formato.cantidad(m.contratos, "contrato no se cobra", "contratos no se cobran")) desde Corredor") }
        return "Con este plan no se borra nada, pero lo que pasa el tope queda en sólo lectura hasta que liberes lugar: " + partes.joined(separator: "; ") + "."
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

    /// «12 meses × $X»: lo que serían doce meses sueltos (con la tienda, su precio).
    private func doceMeses(_ p: Suscripcion.Plan) -> String? {
        if let m = producto(p, "mes") { return (m.price * 12).formatted(m.priceFormatStyle) }
        return Formato.plata(p.precioMes * 12)
    }

    // MARK: Baja del débito de Mercado Pago

    private func baja(_ s: Suscripcion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !confirmarBaja {
                Button("Dar de baja el débito") { confirmarBaja = true }.buttonStyle(BotonTexto(alto: 40, color: C.errorTinta))
            } else {
                Text(Formato.sinViudas("No se cobra más. Seguís con todo hasta el \(Formato.fechaLarga(s.vigenteHasta)); después, sólo lectura."))
                    .estilo(.footnote).foregroundStyle(C.texto)
                HStack(spacing: 10) {
                    Button("Mejor no") { confirmarBaja = false }.buttonStyle(BotonSecundario())
                    Button { Task { await darDeBaja() } } label: { if bajando { ProgressView() } else { Text("Dar de baja") } }
                        .buttonStyle(BotonDestructivo()).disabled(bajando)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }

    private func darDeBaja() async {
        bajando = true
        defer { bajando = false; confirmarBaja = false }
        do {
            try await estado.api.hacer("POST", "/v1/suscripcion/baja", [String: String]())
            // La respuesta puede ser sólo el estado: la suscripción entera se vuelve a pedir.
            await estado.cargarSuscripcion()
            if let s = estado.suscripcion {
                estado.avisar("Listo, no se renueva más. Seguís con todo hasta el \(Formato.fechaLarga(s.vigenteHasta)).")
            } else {
                estado.avisar("Listo, no se renueva más.")
            }
        } catch { estado.avisar(error) }
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
            case .listo:
                await estado.cargarSuscripcion()
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
            if try await tienda.restaurar() {
                await estado.cargarSuscripcion()
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
        case "vencida":
            guard estado.esDuenio else { return "La inmobiliaria está en sólo lectura." }
            if let b = s.borraEn { return "Estás en sólo lectura. Si no elegís un plan, el \(Formato.fechaLarga(b)) se borran tus datos." }
            return "Tu prueba terminó: estás en sólo lectura. Tus datos quedan 90 días."
        case "baja": return "Tu plan no se renueva: termina el \(Formato.dia(s.vigenteHasta))."
        default: return s.diasRestantes <= 1 ? "Hoy es el último día de tu prueba gratis." : "Te quedan \(s.diasRestantes) días de prueba gratis."
        }
    }
}
