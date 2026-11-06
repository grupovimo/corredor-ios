import EventKit
import SwiftUI

extension View {
    /// Los destinos de la Agenda: un día y una cita.
    func destinosAgenda() -> some View {
        self
            .navigationDestination(for: AAgendaDia.self) { d in AgendaRaiz(diaInicial: d.dia.flatMap(Fecha.dia), apilada: true) }
            .navigationDestination(for: ACita.self) { c in FichaCita(id: c.id) }
    }
}

/// Lo que va como franja arriba del día (y punto en la tira): vencimientos y ajustes de contratos,
/// cobros vencidos y licencias del equipo.
struct FranjaAgenda: Identifiable, Hashable {
    var id: String
    var dia: String
    var texto: String
    var largo: String?
    var tono: Tono
    var icono: String
    var contrato: String?
    var licencia = false
    var accion = "Ver"
    /// El mes (AAAA-MM) del cobro vencido: «Recordar» abre ese recordatorio.
    var recordar: String? = nil
}

/// Un vencimiento o ajuste de un contrato (GET /v1/contratos/vencimientos).
struct VencimientoContrato: Decodable {
    var contratoId: String
    var tipo: String
    var fecha: String
    var contrato: JSONLibre?
}

/// Un mes de alquiler vencido y sin cobrar (GET /v1/contactos/deudas).
struct DeudaContacto: Decodable {
    var contratoId: String
    var contactoId: String
    var contactoNombre: String
    var periodo: String
    var vence: String
}

/// 7A–7B Agenda, como la del panel: el día (con las franjas de vencimientos, cobros y licencias, las
/// tareas con tilde y las visitas con «Ir» y el chat), la semana o el mes; mía o del equipo; y el alta
/// rápida escrita como se dice.
struct AgendaRaiz: View {
    @Environment(Estado.self) private var estado
    var diaInicial: Date? = nil
    var apilada = false
    @State private var vista = "dia"
    @State private var de = "equipo"
    @State private var dia = Date()
    @State private var citas: [Cita]?
    @State private var franjas: [FranjaAgenda] = []
    @State private var error: ErrorApi?
    @State private var nueva = false
    @State private var licencias = false

    private var lunes: Date { Self.lunes(de: dia) }

    static func lunes(de d: Date) -> Date {
        let c = Calendar(identifier: .iso8601)
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
    }

    /// El período a la vista: la semana, o el mes con sus semanas de borde.
    private var periodo: (Date, Date) {
        if vista == "mes" {
            let cal = Calendar.current
            let primero = cal.date(from: cal.dateComponents([.year, .month], from: dia)) ?? dia
            let ultimo = cal.date(byAdding: DateComponents(month: 1, day: -1), to: primero) ?? dia
            return (Self.lunes(de: primero), cal.date(byAdding: .day, value: 6, to: Self.lunes(de: ultimo)) ?? ultimo)
        }
        return (lunes, Calendar.current.date(byAdding: .day, value: 6, to: lunes) ?? lunes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CabeceraPestana(sobre: Self.tituloDia(dia), titulo: "Agenda", acciones: acciones)
                VStack(alignment: .leading, spacing: 14) {
                    Segmentado(opciones: [("dia", "Día"), ("semana", "Semana"), ("mes", "Mes")], elegido: $vista)
                    Segmentado(opciones: [("mia", "Mía"), ("equipo", "Equipo")], elegido: $de)
                    if vista != "mes" { semana }
                    if let citas {
                        let visibles = citas.filter { $0.estado != "cancelada" }
                        switch vista {
                        case "mes": vistaMes(visibles)
                        case "semana": vistaSemana(visibles); GraficoVisitasSemanas()
                        default: vistaDia(visibles)
                        }
                    } else if let error {
                        EstadoError(que: "la agenda", error: error) { Task { await cargar() } }
                    } else {
                        EsqueletoFilas(filas: 4)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 80)
        }
        .refreshable { await cargar() }
        .background(FondoApp())
        .toolbar(apilada ? .visible : .hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if estado.escribe {
                Button { nueva = true } label: {
                    Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(C.sobreAccion)
                        .frame(width: 58, height: 58).background(C.accion, in: Circle()).sombraE3()
                }
                .accessibilityLabel("Agendar")
                .padding(.trailing, 20).padding(.bottom, 20)
            }
        }
        .task(id: "\(estado.version)-\(Formato.diaISO(periodo.0))-\(vista)-\(de)") { await cargar() }
        .onAppear { if let diaInicial { dia = diaInicial } }
        .sheet(isPresented: $nueva) { NuevaCita(dia: dia).presentationDetents([.large]) }
        .sheet(isPresented: $licencias) { LicenciasAgenda().hojaTLW([.large]) }
    }

    private var acciones: [AccionCabecera] {
        var a = [AccionCabecera(icono: "chevron.left", etiqueta: "Anterior") { mover(-1) },
                 AccionCabecera(icono: "chevron.right", etiqueta: "Siguiente") { mover(1) }]
        if !Calendar.current.isDateInToday(dia) { a.append(AccionCabecera(icono: "calendar.badge.clock", etiqueta: "Hoy") { withAnimation { dia = Date() } }) }
        a.append(AccionCabecera(icono: "beach.umbrella", etiqueta: "Licencias y ausencias") { licencias = true })
        return a
    }

    private func mover(_ n: Int) {
        let cal = Calendar.current
        withAnimation(.snappy) {
            switch vista {
            case "mes": dia = cal.date(byAdding: .month, value: n, to: dia) ?? dia
            case "semana": dia = cal.date(byAdding: .day, value: 7 * n, to: dia) ?? dia
            default: dia = cal.date(byAdding: .day, value: n, to: dia) ?? dia
            }
        }
    }

    private func franjasDe(_ d: Date) -> [FranjaAgenda] {
        let k = Formato.diaISO(d)
        return franjas.filter { $0.dia == k }
    }

    private var semana: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: lunes)!
                let elegido = Calendar.current.isDate(d, inSameDayAs: dia)
                let n = (citas ?? []).filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: d) && $0.estado != "cancelada" }.count
                let vence = franjasDe(d).contains { !$0.licencia }
                Button { withAnimation(.snappy) { dia = d } } label: {
                    VStack(spacing: 4) {
                        Text(Self.letra(d)).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto3)
                        Text("\(Calendar.current.component(.day, from: d))").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font)
                            .foregroundStyle(elegido ? C.sobreAccion : (Calendar.current.isDateInToday(d) ? C.accion : C.texto))
                            .frame(width: 38, height: 38).background(elegido ? C.accion : .clear, in: Circle())
                        HStack(spacing: 3) {
                            ForEach(0..<min(n, 3), id: \.self) { _ in Circle().fill(elegido ? C.accion : C.texto3).frame(width: 5, height: 5) }
                            if vence { Circle().fill(C.error).frame(width: 5, height: 5) }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(Presionable())
                .accessibilityLabel("\(Formato.diaCompleto(d)), \(Formato.cantidad(n, "cita", "citas"))\(vence ? ", con vencimientos" : "")")
            }
        }
        .gesture(DragGesture().onEnded { g in
            let dias = g.translation.width < -40 ? 7 : (g.translation.width > 40 ? -7 : 0)
            if dias != 0 { withAnimation { dia = Calendar.current.date(byAdding: .day, value: dias, to: dia)! } }
        })
    }

    private func franja(_ f: FranjaAgenda) -> some View {
        Button {
            if f.licencia { licencias = true } else if let c = f.contrato, let mes = f.recordar { estado.abrir(ARecordarMes(contrato: c, periodo: mes)) } else if let c = f.contrato { estado.abrir(AFichaContrato(id: c)) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: f.icono).font(.system(size: 16, weight: .semibold))
                Text(f.largo ?? f.texto).estilo(.subheadFuerte).frame(maxWidth: .infinity, alignment: .leading)
                Text(f.accion).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
            }
            .foregroundStyle(f.tono.tinta)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(f.tono.fondo, in: .rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(Presionable())
    }

    @ViewBuilder
    private func vistaDia(_ l: [Cita]) -> some View {
        let delDia = l.filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: dia) }.sorted { $0.empiezaEn < $1.empiezaEn }
        VStack(spacing: 10) {
            ForEach(franjasDe(dia)) { franja($0) }
            if delDia.isEmpty {
                EstadoVacio(icono: "calendar.badge.checkmark", titulo: Calendar.current.isDateInToday(dia) ? "Hoy no hay nada agendado" : "Nada agendado",
                            texto: "Escribí «visita Mendoza 2350 con Valeria a las 17:30».",
                            accion: estado.escribe ? ("Agendar", { nueva = true }) : nil).padding(.top, 20)
            }
            ForEach(delDia) { c in
                if Calendar.current.isDateInToday(dia), c == delDia.first(where: { $0.empiezaEn > Date() }) { lineaAhora }
                filaCita(c)
            }
            if Calendar.current.isDateInToday(dia), !delDia.isEmpty, delDia.allSatisfy({ $0.empiezaEn <= Date() }) { lineaAhora }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            if abs(g.translation.width) > 70 && abs(g.translation.width) > abs(g.translation.height) { mover(g.translation.width < 0 ? 1 : -1) }
        })
    }

    private var lineaAhora: some View {
        HStack(spacing: 8) {
            Text(Formato.horaDe(Date())).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(Color(hex: 0xE5484D))
            Capsule().fill(Color(hex: 0xE5484D)).frame(height: 2)
        }
        .accessibilityLabel("Ahora")
    }

    static func esTarea(_ c: Cita) -> Bool { !["visita", "firma", "tasacion"].contains(c.tipo ?? "") }

    private func quien(_ c: Cita) -> String {
        c.agenteId != nil && c.agenteId == estado.usuario?.id ? "Vos" : (c.agenteNombre.map { Charla.primerNombre($0) } ?? "Sin agente")
    }

    /// «en 2 h», «en 40 min».
    static func falta(_ f: Date) -> String {
        let s = Int(f.timeIntervalSinceNow)
        return s < 3600 ? "en \(max(1, s / 60))\(Formato.fino)min" : "en \(s / 3600)\(Formato.fino)h"
    }

    @ViewBuilder
    private func filaCita(_ c: Cita) -> some View {
        if Self.esTarea(c) { filaTarea(c) } else { bloque(c) }
    }

    /// Una tarea: el tilde se marca y desmarca desde la lista, con Deshacer.
    private func filaTarea(_ c: Cita) -> some View {
        let hecha = c.estado == "hecha"
        return HStack(alignment: .center, spacing: 12) {
            Text(Formato.horaDe(c.empiezaEn)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 12) {
                Button { Task { await tildar(c) } } label: {
                    Image(systemName: hecha ? "checkmark.square.fill" : "square").font(.system(size: 24)).foregroundStyle(hecha ? Color(hex: 0x2F9E6F) : C.texto3)
                }
                .disabled(!estado.escribe)
                .accessibilityLabel("Hecho: \(c.titulo ?? "")")
                .accessibilityAddTraits(hecha ? .isSelected : [])
                Button { estado.abrir(ACita(id: c.id)) } label: {
                    Text((c.titulo ?? c.tipoTexto) + (c.agenteId != estado.usuario?.id && c.agenteNombre != nil ? " · \(quien(c))" : ""))
                        .estilo(.body16).foregroundStyle(hecha ? C.texto3 : C.texto).strikethrough(hecha)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }
                .buttonStyle(Presionable())
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(C.superficie, in: .rect(cornerRadius: 16, style: .continuous))
            .sombraE2()
        }
    }

    /// Una visita, firma o tasación: con propiedad, quién, «confirmada» o «en 2 h»; si está por empezar
    /// (menos de 3 h), «Ir» y el chat de WhatsApp dentro de Corredor.
    private func bloque(_ c: Cita) -> some View {
        let tono = Self.tono(c)
        let falta = c.empiezaEn.timeIntervalSinceNow
        let prox = falta > 0 && falta < 3 * 3600
        let nombre = ["visita": "Visita", "firma": "Firma", "tasacion": "Tasación"][c.tipo ?? ""] ?? ""
        let titulo = c.propiedadTitulo.map { "\(nombre) \($0)" } ?? (c.titulo ?? c.tipoTexto)
        let q = quien(c)
        let detalle = [c.contactoNombre, q != "Vos" ? q : nil, prox ? Self.falta(c.empiezaEn) : (c.estado == "hecha" ? "hecha" : (c.recordar == true ? "confirmada" : nil))]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formato.horaDe(c.empiezaEn)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                Text(Formato.horaDe(c.terminaEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
            }
            .frame(width: 44, alignment: .leading).padding(.top, 12)
            VStack(alignment: .leading, spacing: 4) {
                Button { estado.abrir(ACita(id: c.id)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(titulo, systemImage: c.icono).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).foregroundStyle(tono)
                        if !detalle.isEmpty { Text(detalle).estilo(.texto14).foregroundStyle(C.texto2).multilineTextAlignment(.leading) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                if prox {
                    HStack(spacing: 8) {
                        Button { Afuera.mapas(c.lugar ?? c.propiedadTitulo ?? "") } label: {
                            Label("Ir", systemImage: "location.fill").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                                .foregroundStyle(C.sobreAccion).frame(maxWidth: .infinity, minHeight: 44).background(C.accion, in: .rect(cornerRadius: 12))
                        }
                        if let x = c.contactoId {
                            Button { Task { await abrirChat(x) } } label: {
                                Image(systemName: "bubble.left.fill").font(.system(size: 17)).foregroundStyle(C.accion)
                                    .frame(width: 48, height: 44).background(C.hundida, in: .rect(cornerRadius: 12))
                            }
                            .accessibilityLabel("WhatsApp a \(c.contactoNombre ?? "")")
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.superficie)
            .overlay(alignment: .leading) { Rectangle().fill(tono).frame(width: 4) }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .sombraE2()
            .opacity(c.estado == "hecha" ? 0.7 : 1)
        }
    }

    /// Tocar un evento de la semana lleva al contacto o a la operación (o al día).
    private func abrirEvento(_ c: Cita) {
        if let x = c.contactoId { estado.abrir(AFichaContacto(id: x)) }
        else if let o = c.operacionId { estado.abrir(AFichaOperacion(id: o)) }
        else { withAnimation { dia = c.empiezaEn; vista = "dia" } }
    }

    @ViewBuilder
    private func vistaSemana(_ l: [Cita]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: lunes)!
                let delDia = l.filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: d) }.sorted { $0.empiezaEn < $1.empiezaEn }
                VStack(alignment: .leading, spacing: 6) {
                    Button { withAnimation { dia = d; vista = "dia" } } label: {
                        Text(Formato.mayuscula(Formato.diaCompleto(d))).estilo(.label).foregroundStyle(Calendar.current.isDateInToday(d) ? C.accion : C.texto2).padding(.horizontal, 4)
                    }
                    .buttonStyle(Presionable())
                    ForEach(franjasDe(d)) { franja($0) }
                    VStack(spacing: 0) {
                        if delDia.isEmpty {
                            Text("Libre").estilo(.texto14).foregroundStyle(C.texto3).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        }
                        ForEach(delDia) { c in
                            Button { abrirEvento(c) } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Self.tono(c)).frame(width: 8, height: 8)
                                    Text(Formato.horaDe(c.empiezaEn)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).frame(width: 44, alignment: .leading)
                                    Text("\(c.titulo ?? c.tipoTexto) · \(c.contactoNombre ?? quien(c))").estilo(.texto14).lineLimit(1).strikethrough(c.estado == "hecha")
                                    Spacer()
                                }
                                .foregroundStyle(C.texto).padding(.horizontal, 14).frame(minHeight: 46)
                                .overlay(alignment: .bottom) { Rectangle().fill(C.linea).frame(height: 0.5) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(Presionable())
                            .contextMenu { Button { estado.abrir(ACita(id: c.id)) } label: { Label("Ver la cita", systemImage: "calendar") } }
                        }
                    }
                    .tarjeta(16)
                }
            }
        }
    }

    /// El mes: las semanas que lo cubren, con hasta 3 citas por día, «y N más» y el primer vencimiento.
    @ViewBuilder
    private func vistaMes(_ l: [Cita]) -> some View {
        let semanas: [[Date]] = semanasDelMes
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["L", "M", "M", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, x in
                    Text(x).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto3).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            ForEach(Array(semanas.enumerated()), id: \.offset) { _, sem in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(sem, id: \.self) { d in celdaMes(d, l) }
                }
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
        .tarjeta(16)
    }

    private var semanasDelMes: [[Date]] {
        let cal = Calendar.current
        let p = periodo
        let dias = max(0, cal.dateComponents([.day], from: p.0, to: p.1).day ?? 0)
        return stride(from: 0, through: dias, by: 7).map { s in (0..<7).compactMap { cal.date(byAdding: .day, value: s + $0, to: p.0) } }
    }

    private func celdaMes(_ d: Date, _ l: [Cita]) -> some View {
        let cal = Calendar.current
        let cs = l.filter { cal.isDate($0.empiezaEn, inSameDayAs: d) }.sorted { $0.empiezaEn < $1.empiezaEn }
        let fuera = !cal.isDate(d, equalTo: dia, toGranularity: .month)
        let v = franjasDe(d).first { !$0.licencia }
        return Button { withAnimation { dia = d; vista = "dia" } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cal.component(.day, from: d))").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                    .foregroundStyle(cal.isDateInToday(d) ? C.sobreAccion : (fuera ? C.texto3 : C.texto))
                    .frame(width: 22, height: 22).background(cal.isDateInToday(d) ? C.accion : .clear, in: Circle())
                if let v {
                    Text(v.texto).font(Estilo(tamano: 9, peso: .bold, relativo: .caption2).font).foregroundStyle(v.tono.tinta).lineLimit(1)
                        .padding(.horizontal, 3).background(v.tono.fondo, in: .rect(cornerRadius: 3))
                }
                ForEach(cs.prefix(3)) { c in
                    Text("\(Formato.horaDe(c.empiezaEn)) \(c.propiedadTitulo.map { String($0.split(separator: ",").first ?? "") } ?? (c.titulo ?? ""))")
                        .font(Estilo(tamano: 9, peso: .semibold, relativo: .caption2).font).foregroundStyle(Self.tono(c)).lineLimit(1)
                }
                if cs.count > 3 { Text("y \(cs.count - 3) más").font(Estilo(tamano: 9, peso: .regular, relativo: .caption2).font).foregroundStyle(C.texto3) }
                Spacer(minLength: 0)
            }
            .padding(3).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .opacity(fuera ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .accessibilityLabel("\(Formato.diaCompleto(d)), \(Formato.cantidad(cs.count, "cita", "citas"))")
    }

    static func tono(_ c: Cita) -> Color {
        switch c.tipo {
        case "visita": return C.oroTinta
        case "tasacion": return C.violetaTinta
        case "firma": return C.okTinta
        case "llamado": return C.azulTinta
        default: return C.texto2
        }
    }

    static func letra(_ d: Date) -> String {
        ["Do", "Lu", "Ma", "Mi", "Ju", "Vi", "Sá"][Calendar.current.component(.weekday, from: d) - 1]
    }

    static func nombreDia(_ d: Date) -> String {
        ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"][Calendar.current.component(.weekday, from: d) - 1]
    }

    /// «Hoy, jueves 12», «Mañana, viernes 13», «Ayer, miércoles 11» o «sábado 14».
    static func tituloDia(_ d: Date) -> String {
        let cal = Calendar.current
        let base = "\(nombreDia(d)) \(cal.component(.day, from: d))"
        if cal.isDateInToday(d) { return "Hoy, \(base)" }
        if cal.isDateInTomorrow(d) { return "Mañana, \(base)" }
        if cal.isDateInYesterday(d) { return "Ayer, \(base)" }
        return base
    }

    private func abrirChat(_ contacto: String) async {
        struct Cuerpo: Encodable { var contactoId: String }
        struct Conv: Decodable { var id: String }
        do {
            let x: Conv = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones", Cuerpo(contactoId: contacto))
            estado.abrir(AChat(id: x.id))
        } catch { estado.avisar(error) }
    }

    private func tildar(_ c: Cita) async {
        struct Cuerpo: Encodable { var estado: String }
        let nuevo = c.estado == "hecha" ? "pendiente" : "hecha"
        if let i = citas?.firstIndex(where: { $0.id == c.id }) { citas?[i].estado = nuevo }
        do {
            try await estado.cola.enviar("PATCH", "/v1/agenda/\(c.id)", Cuerpo(estado: nuevo), etiqueta: "Tarea \(nuevo == "hecha" ? "hecha" : "pendiente")")
            if nuevo == "hecha" {
                Haptico.exito()
                estado.avisar("Hecho · \(c.titulo ?? "")") {
                    Task {
                        do {
                            try await estado.api.hacer("PATCH", "/v1/agenda/\(c.id)", Cuerpo(estado: "pendiente"))
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            }
            estado.version += 1
        } catch {
            if let i = citas?.firstIndex(where: { $0.id == c.id }) { citas?[i].estado = c.estado }
            estado.avisar(error)
        }
    }

    private func cargar() async {
        let (desde, hasta) = periodo
        let d = Formato.diaISO(desde), h = Formato.diaISO(hasta)
        do {
            var q: [URLQueryItem] = [.init(name: "desde", value: d), .init(name: "hasta", value: h), .init(name: "limite", value: "500")]
            if de == "mia" { q.append(.init(name: "agente", value: "yo")) }
            citas = try await estado.api.get("/v1/agenda", query: q)
            error = nil
        } catch let e as ErrorApi { if citas == nil { error = e } } catch {}
        await cargarFranjas(d, h)
    }

    /// Vencimientos y ajustes de contratos, cobros vencidos y licencias del equipo.
    private func cargarFranjas(_ desde: String, _ hasta: String) async {
        var f: [FranjaAgenda] = []
        let vencs: [VencimientoContrato] = (try? await estado.api.get("/v1/contratos/vencimientos", query: [.init(name: "dias", value: "120")])) ?? []
        for v in vencs where v.fecha >= desde && v.fecha <= hasta {
            let calle = v.contrato?["propiedadTitulo"]?.texto.map { " " + String($0.split(separator: ",").first ?? "") } ?? ""
            let vence = v.tipo == "vencimiento"
            f.append(FranjaAgenda(id: v.contratoId + v.tipo + v.fecha, dia: v.fecha, texto: vence ? "Vence alquiler\(calle)" : "Ajuste\(calle)",
                                  tono: vence ? .rojo : .azul, icono: vence ? "calendar.badge.exclamationmark" : "chart.line.uptrend.xyaxis", contrato: v.contratoId))
        }
        let deudas: [DeudaContacto] = (try? await estado.api.get("/v1/contactos/deudas", query: [.init(name: "desde", value: desde), .init(name: "hasta", value: hasta)])) ?? []
        for d in deudas {
            let apellido = d.contactoNombre.split(separator: " ").last.map(String.init) ?? d.contactoNombre
            f.append(FranjaAgenda(id: "cobro" + d.contratoId + d.periodo, dia: d.vence, texto: "Cobro \(apellido) vencido", largo: "Cobro de \(d.contactoNombre) vencido",
                                  tono: .rojo, icono: "dollarsign.circle", contrato: d.contratoId, accion: "Recordar",
                                  recordar: String(d.periodo.prefix(7))))
        }
        let hoy = Formato.diaISO(Date())
        let hasta60 = Formato.diaISO(Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date())
        let lics: [Licencia] = (try? await estado.api.get("/v1/licencias", query: [.init(name: "desde", value: min(desde, hoy)), .init(name: "hasta", value: max(hasta, hasta60))])) ?? []
        let ausente = ["licencia": "de licencia", "vacaciones": "de vacaciones", "enfermedad": "de licencia", "tramite": "de trámite"]
        for l in lics {
            var d = max(l.desde, desde)
            var vueltas = 0
            while d <= l.hasta && d <= hasta && vueltas < 400 {
                let quien = l.usuarioId == estado.usuario?.id ? "Vos" : Charla.primerNombre(l.usuarioNombre)
                f.append(FranjaAgenda(id: "licencia" + l.id + d, dia: d, texto: "\(quien) \(ausente[l.tipo ?? ""] ?? "de licencia")", tono: .neutro, icono: "beach.umbrella", licencia: true))
                d = Entender.sumar(d, 1)
                vueltas += 1
            }
        }
        franjas = f
    }
}

/// 7C Nueva visita o tarea: propiedad, con quién, día, la rueda de la hora y «Avisarle por WhatsApp».
struct NuevaCita: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var propiedad: Propiedad? = nil
    var contacto: (id: String, nombre: String)? = nil
    var dia: Date = Date()
    var editar: Cita? = nil
    /// La operación a la que queda vinculada (desde la ficha de la operación).
    var operacion: String? = nil
    /// La hora ya elegida («HH:mm»), si viene de otro lado.
    var hora: String? = nil
    /// Visita, tarea o recordatorio, para el alta rápida.
    var clase = "visita"

    /// Sin `editar`, el alta rápida escrita como se dice; «Elegir campo por campo» pasa al formulario.
    @State private var formulario = false

    @State private var tipo = "visita"
    @State private var esTarea = 0
    @State private var prop: Propiedad?
    @State private var con: Resultado?
    @State private var cuando = Date()
    @State private var duracion = 60
    @State private var titulo = ""
    @State private var lugar = ""
    @State private var notas = ""
    @State private var avisar = true
    @State private var calendario = false
    @State private var eligiendoProp = false
    @State private var eligiendoCon = false
    @State private var guardando = false

    var body: some View {
        if editar == nil && !formulario {
            AltaRapidaCita(propiedadPrevia: propiedad, contactoPrevio: contacto?.id, operacion: operacion,
                           diaPrevio: Formato.diaISO(dia), horaPrevia: hora, clasePrevia: clase) { formulario = true }
        } else {
            formularioCompleto
        }
    }

    private var formularioCompleto: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Segmentado(opciones: [(0, "Visita"), (1, "Tarea")], elegido: $esTarea)
                    if esTarea == 0 {
                        Picker("Tipo", selection: $tipo) { ForEach(Cita.tipos.filter { $0.0 != "otro" }, id: \.0) { Text($0.1).tag($0.0) } }
                            .pickerStyle(.segmented)
                    } else {
                        TextField("Qué hay que hacer", text: $titulo).campoCorredor()
                    }
                    VStack(spacing: 0) {
                        fila("Propiedad", prop?.nombre ?? "Elegí la propiedad", primera: true) { eligiendoProp = true }
                        fila("Con", con?.titulo ?? contacto?.nombre ?? "Elegí el contacto") { eligiendoCon = true }
                        HStack {
                            Text("Día").estilo(.subhead).foregroundStyle(C.texto2).frame(width: 90, alignment: .leading)
                            DatePicker("", selection: $cuando, displayedComponents: .date).labelsHidden()
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
                    }
                    .background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                    DatePicker("Hora", selection: $cuando, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity).frame(height: 170)
                        .background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
                    Picker("Duración", selection: $duracion) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text($0 < 60 ? "\($0) min" : "\($0 / 60) h\($0 % 60 > 0 ? " \($0 % 60)" : "")").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if prop == nil { TextField("Lugar (si no es en una propiedad)", text: $lugar).campoCorredor() }
                    TextField("Notas", text: $notas, axis: .vertical).lineLimit(2...5).campoCorredor()
                    if esTarea == 0 && (con != nil || contacto != nil) {
                        Toggle(isOn: $avisar) {
                            HStack(spacing: 12) {
                                Image("LogoWhatsApp").resizable().frame(width: 22, height: 22)
                                Text("Avisarle a \((con?.titulo ?? contacto?.nombre ?? "").split(separator: " ").first.map(String.init) ?? "") por WhatsApp").estilo(.subhead)
                            }
                        }
                        .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 4)
                    }
                    Toggle(isOn: $calendario) {
                        Label("Sumarla al calendario del iPhone", systemImage: "calendar").estilo(.subhead)
                    }
                    .tint(Color(hex: 0x2F9E6F)).padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .background(C.superficie)
            .navigationTitle(editar == nil ? "Nueva" : "Editar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editar == nil ? "Agendar" : "Guardar") { Task { await guardar() } }.fontWeight(.bold).disabled(guardando)
                }
            }
            .sheet(isPresented: $eligiendoProp) { ElegirPropiedad { prop = $0 } }
            .sheet(isPresented: $eligiendoCon) { ElegirContacto { con = $0 } }
        }
        .onAppear {
            prop = propiedad
            if let contacto { con = Resultado(id: contacto.id, tipo: "contacto", titulo: contacto.nombre) }
            var c = Calendar.current.dateComponents([.year, .month, .day], from: dia)
            let ahora = Calendar.current.dateComponents([.hour], from: Date())
            c.hour = min(20, (ahora.hour ?? 9) + 1)
            if let h = hora?.split(separator: ":").compactMap({ Int($0) }), h.count == 2 { c.hour = h[0]; c.minute = h[1] }
            cuando = Calendar.current.date(from: c) ?? Date()
            if clase != "visita" { esTarea = 1 }
            if let e = editar {
                tipo = e.tipo ?? "visita"
                esTarea = e.tipo == "otro" ? 1 : 0
                titulo = e.titulo ?? ""
                cuando = e.empiezaEn
                duracion = e.duracionMin ?? 60
                lugar = e.lugar ?? ""
                notas = e.notas ?? ""
                avisar = e.recordar ?? false
                if let p = e.contactoId { con = Resultado(id: p, tipo: "contacto", titulo: e.contactoNombre ?? "") }
            }
        }
        .task {
            if let e = editar, let p = e.propiedadId { prop = try? await estado.api.get("/v1/propiedades/\(p)") }
        }
    }

    private func fila(_ l: String, _ v: String, primera: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 10) {
                Text(l).estilo(.subhead).foregroundStyle(C.texto2).frame(width: 90, alignment: .leading)
                Text(v).font(Estilo(tamano: 16, peso: .medium, relativo: .body).font).foregroundStyle(C.texto).lineLimit(1)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        struct Cuerpo: Encodable {
            var tipo: String
            var estado = "pendiente"
            var titulo: String
            var empiezaEn: Date
            var duracionMin: Int
            var propiedadId: String?
            var contactoId: String?
            var lugar: String?
            var notas: String?
            var recordar: Bool
            var agenteId: String?
            var operacionId: String?
        }
        let t = esTarea == 1 ? "otro" : tipo
        let tit = esTarea == 1 ? titulo : "\(Cita.tipos.first { $0.0 == t }?.1 ?? "Visita") · \(prop?.nombre ?? lugar)"
        let c = Cuerpo(tipo: t, estado: editar?.estado ?? "pendiente", titulo: tit, empiezaEn: cuando, duracionMin: duracion, propiedadId: prop?.id, contactoId: con?.id,
                       lugar: lugar.nonEmpty, notas: notas.nonEmpty, recordar: avisar && esTarea == 0, agenteId: editar?.agenteId ?? prop?.agenteId ?? estado.usuario?.id,
                       operacionId: editar?.operacionId ?? operacion)
        do {
            if let e = editar {
                try await estado.cola.enviar("PUT", "/v1/agenda/\(e.id)", c, etiqueta: "Cambios en \(tit)")
            } else {
                let subio = try await estado.cola.enviar("POST", "/v1/agenda", c, etiqueta: tit)
                let quien = (con?.titulo ?? "").split(separator: " ").first.map(String.init)
                estado.avisar(!subio ? "En cola · se agenda cuando vuelva la señal" : (avisar && quien != nil ? "Visita agendada · le avisamos a \(quien!)" : "Agendada"))
            }
            if calendario { await sumarAlCalendario(tit) }
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }

    private func sumarAlCalendario(_ titulo: String) async {
        let tienda = EKEventStore()
        guard (try? await tienda.requestWriteOnlyAccessToEvents()) == true else { return }
        let e = EKEvent(eventStore: tienda)
        e.title = titulo
        e.startDate = cuando
        e.endDate = cuando.addingTimeInterval(Double(duracion * 60))
        e.location = prop?.direccion ?? lugar.nonEmpty
        e.calendar = tienda.defaultCalendarForNewEvents
        try? tienda.save(e, span: .thisEvent)
    }
}

/// Elegir un contacto (o cargarlo nuevo con el nombre escrito).
struct ElegirContacto: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var tipo = "interesado"
    var alElegir: (Resultado) -> Void
    @State private var q = ""
    @State private var res: [Resultado] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(res) { r in
                    Button { alElegir(r); cerrar() } label: {
                        VStack(alignment: .leading) { Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto); if let s = r.subtitulo { Text(s).estilo(.footnote).foregroundStyle(C.texto2) } }
                    }
                }
                if q.count >= 2 {
                    Button {
                        Task {
                            struct Cuerpo: Encodable { var nombre: String; var tipo: String }
                            struct Nuevo: Decodable { var id: String; var nombre: String }
                            do {
                                let n: Nuevo = try await estado.api.enviar("POST", "/v1/contactos", Cuerpo(nombre: q, tipo: tipo))
                                alElegir(Resultado(id: n.id, tipo: "contacto", titulo: n.nombre))
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    } label: { Label("Cargar «\(q)» como contacto nuevo", systemImage: "person.badge.plus") }
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nombre o teléfono")
            .navigationTitle("Elegí el contacto").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .task(id: q) {
                try? await Task.sleep(for: .milliseconds(200))
                if q.count >= 2 {
                    res = (try? await estado.api.get("/v1/buscar", query: [.init(name: "tipo", value: "contacto"), .init(name: "q", value: q)])) ?? []
                } else {
                    struct Ct: Decodable { var id: String; var nombre: String; var telefono: String? }
                    let l: [Ct] = (try? await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "30")])) ?? []
                    res = l.map { Resultado(id: $0.id, tipo: "contacto", titulo: $0.nombre, subtitulo: $0.telefono) }
                }
            }
        }
    }
}

/// La ficha de una cita: cuándo, dónde, con quién; confirmar, marcar hecha, editar, cancelar o borrar.
struct FichaCita: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    @State private var c: Cita?
    @State private var editando = false

    var body: some View {
        ScrollView {
            if let c {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(c.tipoTexto, systemImage: c.icono).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(AgendaRaiz.tono(c))
                        Text(c.donde).estilo(.titulo).foregroundStyle(C.texto)
                        Text("\(Formato.mayuscula(Formato.diaCompleto(c.empiezaEn))) · \(Formato.horaDe(c.empiezaEn)) a \(Formato.horaDe(c.terminaEn))").estilo(.body16).foregroundStyle(C.texto2)
                        Text(Self.estadoTexto(c.estado)).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.okTinta)
                            .padding(.horizontal, 9).frame(height: 24).background(C.okFondo, in: Capsule()).padding(.top, 4)
                    }
                    VStack(spacing: 0) {
                        if let p = c.propiedadId { enlace("house", c.propiedadTitulo ?? "Propiedad", primera: true) { estado.abrir(AFichaPropiedad(id: p)) } }
                        if let x = c.contactoId { enlace("person", c.contactoNombre ?? "Contacto", primera: c.propiedadId == nil) { estado.abrir(AFichaContacto(id: x)) } }
                        if let o = c.operacionId { enlace("rectangle.split.3x1", "La operación", primera: false) { estado.abrir(AFichaOperacion(id: o)) } }
                        enlace("location", "Cómo llegar", primera: c.propiedadId == nil && c.contactoId == nil) { Afuera.mapas(c.lugar ?? c.propiedadTitulo ?? "") }
                    }
                    .tarjeta()
                    if let n = c.notas?.nonEmpty { Text(n).estilo(.body16).foregroundStyle(C.texto).padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta() }
                    if estado.escribe {
                        VStack(spacing: 8) {
                            if c.estado != "hecha" { Button("Marcar como hecha") { Task { await poner("hecha") } }.buttonStyle(BotonAccion()) }
                            else { Button("Volver a pendiente") { Task { await poner("pendiente") } }.buttonStyle(BotonHundido()) }
                            if c.estado == "pendiente" || c.estado == nil {
                                Button("Estoy llegando") { llegando(c) }.buttonStyle(BotonHundido())
                            }
                            Button("Editar") { editando = true }.buttonStyle(BotonHundido())
                            if c.estado != "cancelada" { Button("Cancelar la cita") { Task { await poner("cancelada") } }.buttonStyle(BotonTexto(color: C.error)) }
                        }
                    }
                }
                .padding(16)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada("Cita")
        .toolbar {
            if estado.escribe {
                Button(role: .destructive) { borrar() } label: { Image(systemName: "trash") }.accessibilityLabel("Borrar")
            }
        }
        .task(id: estado.version) { c = try? await estado.api.get("/v1/agenda/\(id)") }
        .sheet(isPresented: $editando) { if let c { NuevaCita(editar: c) } }
    }

    static func estadoTexto(_ e: String?) -> String {
        ["pendiente": "Pendiente", "hecha": "Hecha", "cancelada": "Cancelada"][e ?? ""] ?? "Pendiente"
    }

    private func enlace(_ i: String, _ t: String, primera: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: i).foregroundStyle(C.accion).frame(width: 24)
                Text(t).estilo(.body16).foregroundStyle(C.texto)
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func poner(_ nuevo: String) async {
        struct Cuerpo: Encodable { var estado: String }
        let antes = c?.estado ?? "pendiente"
        do {
            try await estado.cola.enviar("PATCH", "/v1/agenda/\(id)", Cuerpo(estado: nuevo), etiqueta: "Cita \(Self.estadoTexto(nuevo).lowercased())")
            estado.version += 1
            if nuevo == "hecha" { Haptico.exito() }
            estado.avisar("Cita \(Self.estadoTexto(nuevo).lowercased())") {
                Task {
                    do {
                        try await estado.api.hacer("PATCH", "/v1/agenda/\(id)", Cuerpo(estado: antes))
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func llegando(_ c: Cita) {
        guard let id = c.contactoId else { return estado.avisar("La visita no tiene un contacto cargado.", ok: false) }
        Task {
            struct Ct: Decodable { var nombre: String?; var telefono: String? }
            let x: Ct? = try? await estado.api.get("/v1/contactos/\(id)")
            Afuera.whatsapp(x?.telefono, texto: "Hola \(x?.nombre?.split(separator: " ").first.map(String.init) ?? ""), estoy llegando a \(c.donde).")
        }
    }

    private func borrar() {
        let tarea = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            do {
                try await estado.api.hacer("DELETE", "/v1/agenda/\(id)")
                estado.version += 1
            } catch { estado.avisar(error) }
        }
        cerrar()
        estado.avisar("Cita borrada") { tarea.cancel() }
    }
}
