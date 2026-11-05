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

/// 7A–7B Agenda: la semana arriba (con puntos por cita), el día con la hora actual en rojo o la semana
/// entera, y el «+» para una visita o una tarea nueva.
struct AgendaRaiz: View {
    @Environment(Estado.self) private var estado
    var diaInicial: Date? = nil
    var apilada = false
    @State private var vista = 0
    @State private var dia = Date()
    @State private var citas: [Cita]?
    @State private var error: ErrorApi?
    @State private var nueva = false
    @State private var soloMias = true

    private var lunes: Date {
        let c = Calendar(identifier: .iso8601)
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dia)) ?? dia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Siempre con su cabecera (fecha, título y «Hoy»): desde el 5/11 se abre apilada desde el
                // Inicio y desde «Más»; la barra de arriba queda sólo para volver.
                CabeceraPestana(sobre: Formato.mayuscula(Formato.diaCompleto(dia)), titulo: "Agenda",
                                acciones: [AccionCabecera(icono: "calendar.badge.clock", etiqueta: "Hoy") { withAnimation { dia = Date() } }])
                VStack(alignment: .leading, spacing: 14) {
                    Segmentado(opciones: [(0, "Día"), (1, "Semana")], elegido: $vista)
                    semana
                    if estado.esDuenio {
                        Toggle("Sólo mi agenda", isOn: $soloMias).estilo(.subhead).tint(Color(hex: 0x2F9E6F))
                    }
                    if let citas {
                        let visibles = citas.filter { !soloMias || !estado.esDuenio || $0.agenteId == nil || $0.agenteId == estado.usuario?.id }
                        if vista == 0 { vistaDia(visibles) } else { vistaSemana(visibles) }
                    } else if let error {
                        EstadoError(que: "la agenda", error: error) { Task { await cargar() } }
                    } else {
                        EsqueletoFilas(filas: 4)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 90)
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
                .accessibilityLabel("Nueva visita o tarea")
                .padding(.trailing, 20).padding(.bottom, 20)
            }
        }
        .task(id: "\(estado.version)-\(Formato.diaISO(lunes))-\(vista)") { await cargar() }
        .onAppear { if let diaInicial { dia = diaInicial } }
        .sheet(isPresented: $nueva) { NuevaCita(dia: dia).presentationDetents([.large]) }
    }

    private var semana: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: lunes)!
                let elegido = Calendar.current.isDate(d, inSameDayAs: dia)
                let n = (citas ?? []).filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: d) }.count
                Button { withAnimation(.snappy) { dia = d } } label: {
                    VStack(spacing: 4) {
                        Text(Self.letra(d)).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto3)
                        Text("\(Calendar.current.component(.day, from: d))").font(Estilo(tamano: 17, peso: .semibold, relativo: .headline).font)
                            .foregroundStyle(elegido ? C.sobreAccion : (Calendar.current.isDateInToday(d) ? C.accion : C.texto))
                            .frame(width: 38, height: 38).background(elegido ? C.accion : .clear, in: Circle())
                        HStack(spacing: 3) {
                            ForEach(0..<min(n, 3), id: \.self) { _ in Circle().fill(elegido ? C.accion : C.texto3).frame(width: 5, height: 5) }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Formato.diaCompleto(d)), \(Formato.cantidad(n, "cita", "citas"))")
            }
        }
        .gesture(DragGesture().onEnded { g in
            let dias = g.translation.width < -40 ? 7 : (g.translation.width > 40 ? -7 : 0)
            if dias != 0 { withAnimation { dia = Calendar.current.date(byAdding: .day, value: dias, to: dia)! } }
        })
    }

    @ViewBuilder
    private func vistaDia(_ l: [Cita]) -> some View {
        let delDia = l.filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: dia) }.sorted { $0.empiezaEn < $1.empiezaEn }
        VStack(spacing: 10) {
            if delDia.isEmpty {
                EstadoVacio(icono: "calendar.badge.checkmark", titulo: "Día libre", texto: "Agendá una visita y le avisamos al interesado por WhatsApp.",
                            accion: estado.escribe ? ("Nueva visita", { nueva = true }) : nil).padding(.top, 30)
            }
            ForEach(delDia) { c in
                if Calendar.current.isDateInToday(dia), c == delDia.first(where: { $0.empiezaEn > Date() }) { lineaAhora }
                filaCita(c)
            }
            if Calendar.current.isDateInToday(dia), !delDia.isEmpty, delDia.allSatisfy({ $0.empiezaEn <= Date() }) { lineaAhora }
        }
    }

    private var lineaAhora: some View {
        HStack(spacing: 8) {
            Text(Formato.horaDe(Date())).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(Color(hex: 0xE5484D))
            Capsule().fill(Color(hex: 0xE5484D)).frame(height: 2)
        }
        .accessibilityLabel("Ahora")
    }

    private func filaCita(_ c: Cita) -> some View {
        let tono = Self.tono(c)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formato.horaDe(c.empiezaEn)).font(Estilo(tamano: 15, peso: .bold, relativo: .subheadline).font).foregroundStyle(C.texto)
                Text(Formato.horaDe(c.terminaEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
            }
            .frame(width: 44, alignment: .leading).padding(.top, 12)
            Button { estado.abrir(ACita(id: c.id)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(c.tipoTexto) · \(c.donde)", systemImage: c.icono).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono)
                    Text([c.contactoNombre.map { "Con \($0)" }, c.agenteNombre.map { estado.esDuenio ? $0 : nil } ?? nil, c.estado == "hecha" ? "Hecha" : nil]
                        .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? (c.titulo ?? ""))
                        .estilo(.texto14).foregroundStyle(C.texto2).multilineTextAlignment(.leading)
                    if c.tipo == "visita" && c.terminaEn > Date() && Calendar.current.isDateInToday(c.empiezaEn) {
                        HStack(spacing: 8) {
                            Button { Afuera.mapas(c.lugar ?? c.propiedadTitulo ?? "") } label: {
                                Label("Cómo llegar", systemImage: "location.fill").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                                    .foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44).background(C.hundida, in: .rect(cornerRadius: 12))
                            }
                            Button { llegando(c) } label: {
                                Text("Estoy llegando").font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                                    .foregroundStyle(Color(hex: 0x0B3D1F)).frame(maxWidth: .infinity, minHeight: 44).background(Color(hex: 0x25D366), in: .rect(cornerRadius: 12))
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
                .opacity(c.estado == "cancelada" ? 0.5 : 1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func vistaSemana(_ l: [Cita]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: lunes)!
                let delDia = l.filter { Calendar.current.isDate($0.empiezaEn, inSameDayAs: d) }.sorted { $0.empiezaEn < $1.empiezaEn }
                VStack(alignment: .leading, spacing: 6) {
                    Text(Formato.mayuscula(Formato.diaCompleto(d))).estilo(.label).foregroundStyle(C.texto2).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        if delDia.isEmpty {
                            Text("Libre").estilo(.texto14).foregroundStyle(C.texto3).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        }
                        ForEach(delDia) { c in
                            Button { estado.abrir(ACita(id: c.id)) } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Self.tono(c)).frame(width: 8, height: 8)
                                    Text(Formato.horaDe(c.empiezaEn)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).frame(width: 44, alignment: .leading)
                                    Text("\(c.tipoTexto) · \(c.donde)").estilo(.texto14).lineLimit(1)
                                    Spacer()
                                }
                                .foregroundStyle(C.texto).padding(.horizontal, 14).frame(minHeight: 46)
                                .overlay(alignment: .bottom) { Rectangle().fill(C.linea).frame(height: 0.5) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .tarjeta(16)
                }
            }
        }
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

    private func llegando(_ c: Cita) {
        guard let id = c.contactoId else { return estado.avisar("La visita no tiene un contacto cargado.", ok: false) }
        Task {
            struct C: Decodable { var nombre: String?; var telefono: String? }
            let x: C? = try? await estado.api.get("/v1/contactos/\(id)")
            Afuera.whatsapp(x?.telefono, texto: "Hola \(x?.nombre?.split(separator: " ").first.map(String.init) ?? ""), estoy llegando a \(c.donde).")
        }
    }

    private func cargar() async {
        let desde = Calendar.current.date(byAdding: .day, value: -1, to: lunes)!
        let hasta = Calendar.current.date(byAdding: .day, value: 8, to: lunes)!
        do {
            citas = try await estado.api.get("/v1/agenda", query: [.init(name: "desde", value: Formato.diaISO(desde)), .init(name: "hasta", value: Formato.diaISO(hasta)),
                                                                  .init(name: "limite", value: "500")])
            error = nil
        } catch let e as ErrorApi { if citas == nil { error = e } } catch {}
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
            cuando = Calendar.current.date(from: c) ?? Date()
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
        .buttonStyle(.plain)
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
        }
        let t = esTarea == 1 ? "otro" : tipo
        let tit = esTarea == 1 ? titulo : "\(Cita.tipos.first { $0.0 == t }?.1 ?? "Visita") · \(prop?.nombre ?? lugar)"
        let c = Cuerpo(tipo: t, estado: editar?.estado ?? "pendiente", titulo: tit, empiezaEn: cuando, duracionMin: duracion, propiedadId: prop?.id, contactoId: con?.id,
                       lugar: lugar.nonEmpty, notas: notas.nonEmpty, recordar: avisar && esTarea == 0, agenteId: editar?.agenteId ?? estado.usuario?.id)
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
                            if let n: Nuevo = try? await estado.api.enviar("POST", "/v1/contactos", Cuerpo(nombre: q, tipo: tipo)) {
                                alElegir(Resultado(id: n.id, tipo: "contacto", titulo: n.nombre))
                                cerrar()
                            }
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
        .buttonStyle(.plain)
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
                Task { try? await estado.api.hacer("PATCH", "/v1/agenda/\(id)", Cuerpo(estado: antes)); estado.version += 1 }
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
            try? await estado.api.hacer("DELETE", "/v1/agenda/\(id)")
            estado.version += 1
        }
        cerrar()
        estado.avisar("Cita borrada") { tarea.cancel() }
    }
}
