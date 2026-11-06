import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 6B–6C Chat de WhatsApp, como la conversación del panel (mensajes/[id]): la propiedad por la que
/// pregunta, los mensajes con los días, las visitas agendadas y la marca del vínculo; las respuestas
/// sugeridas con los datos de la ficha, los turnos libres del agente, las respuestas guardadas con «/»,
/// adjuntos con epígrafe y, fuera de las 24 h, las plantillas aprobadas con sus datos. Desde acá se
/// toma, se pasa a otro agente, se guarda el número como contacto y se crea la operación.
struct Chat: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var conv: Conversacion?
    @State private var mensajes: [MensajeWA] = []
    @State private var enviados: [MensajeWA] = []
    @State private var ocultos: Set<String> = []
    @State private var texto = ""
    @State private var chip: String?
    @State private var adjunto: Archivo?
    @State private var subiendo = false
    @State private var plantillas: [PlantillaWA] = []
    @State private var respuestas: [RespuestaGuardada] = []
    @State private var ficha: Propiedad?
    @State private var interesados: Int?
    @State private var contacto: Contacto?
    @State private var visitas: [Cita] = []
    @State private var turnos: [Date] = []
    @State private var equipo: [Miembro] = []
    @State private var web: String?
    @State private var abiertaR = false
    @State private var guardandoR = false
    @State private var vincular = false
    @State private var guardarContacto = false
    @State private var plantilla: String?
    @State private var parametros: [String] = []
    @State private var otra = false
    @State private var mandandoPlantilla = false
    @State private var fotos = false
    @State private var foto: PhotosPickerItem?
    @State private var camara = false
    @State private var archivos = false
    @State private var grabadora = Grabadora()
    @State private var previo: ArchivoPrevio?
    @State private var altoFuera: CGFloat = 160
    @State private var errorCarga: ErrorApi?

    private var nombre: String { conv?.quien ?? "" }
    private var primero: String { conv?.sinNombre == false ? Charla.primerNombre(nombre) : "" }
    private var agente: String? { conv?.agenteNombre.map { Charla.primerNombre($0) } }

    private var todos: [MensajeWA] {
        let ids = Set(mensajes.map(\.id))
        return (mensajes + enviados.filter { !ids.contains($0.id) }).filter { !ocultos.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let c = conv {
                tarjetaPropiedad(c).padding(.horizontal, 12).padding(.top, 10)
                charla
            } else if let e = errorCarga {
                EstadoError(que: "la conversación", error: e) { Task { await cargar() } }.frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let c = conv {
                if c.enVentana == true {
                    sugerenciasYTurnos(c)
                    if abiertaR { panelRespuestas }
                    entrada
                } else {
                    fueraDeVentana(c)
                }
            }
        }
        .background(FondoApp())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { barra }
        .task(id: estado.version) { await cargar() }
        .task {
            // Respaldo: en vivo los mensajes llegan por el stream; si está caído, se consulta cada 8 s.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                if !estado.enVivo { await cargarMensajes() }
            }
        }
        .onChange(of: texto) { _, t in
            if t.hasPrefix("/") && !abiertaR { abiertaR = true } else if !t.hasPrefix("/") && abiertaR && !guardable && !t.isEmpty { abiertaR = false }
        }
        .photosPicker(isPresented: $fotos, selection: $foto, matching: .any(of: [.images, .videos]))
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                do {
                    if let d = try await i.loadTransferable(type: Data.self) {
                        let esVideo = i.supportedContentTypes.contains { $0.conforms(to: .movie) }
                        if esVideo { await subir(d, nombre: "video.mp4", tipo: "video/mp4") }
                        else { await subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "foto.jpg", tipo: "image/jpeg") }
                    }
                } catch { estado.avisar(error) }
                foto = nil
            }
        }
        .sheet(isPresented: $camara) { Camara { d in Task { await subir(d, nombre: "foto.jpg", tipo: "image/jpeg") } }.ignoresSafeArea() }
        .fileImporter(isPresented: $archivos, allowedContentTypes: [.jpeg, .png, .pdf, .mpeg4Movie, .audio]) { r in
            if case .success(let u) = r { Task { await subirArchivo(u) } }
        }
        .sheet(isPresented: $vincular) {
            VincularPropiedad(tiene: conv?.propiedadId != nil) { p in
                Task { await cambiar(.objeto(["propiedadId": p.map { .texto($0.id) } ?? .nulo]),
                                     p.map { "Vinculada a \($0.titulo)" } ?? "Se desvinculó la propiedad",
                                     deshacer: .objeto(["propiedadId": conv?.propiedadId.map { .texto($0) } ?? .nulo])) }
            }
            .hojaTLW([.large])
        }
        .sheet(isPresented: $guardarContacto) {
            GuardarNumero(waId: conv?.waId ?? "", nombre: conv?.nombre?.nonEmpty ?? "", tipo: ficha?.operacion == "alquiler" ? "inquilino" : "comprador") { n, t in
                await crearContacto(n, t)
            }
            .hojaTLW([.medium])
        }
        .sheet(isPresented: $guardandoR) {
            GuardarRespuesta(texto: texto.trimmingCharacters(in: .whitespacesAndNewlines)) { r in respuestas.append(r) }.hojaTLW([.medium])
        }
        .vistaPrevia($previo)
    }

    // MARK: Cabecera

    @ToolbarContentBuilder
    private var barra: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { if let c = conv?.contactoId { estado.abrir(AFichaContacto(id: c)) } } label: {
                HStack(spacing: 8) {
                    if conv?.sinNombre == true {
                        Text("+54").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.azulTinta)
                            .frame(width: 34, height: 34).background(C.azulFondo, in: Circle())
                    } else {
                        Text(Formato.iniciales(nombre)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).foregroundStyle(C.texto)
                            .frame(width: 34, height: 34).background(C.hundida, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .headline).font).foregroundStyle(C.texto).lineLimit(1)
                        Text(subtitulo).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1)
                    }
                }
            }
            .buttonStyle(Presionable())
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { Afuera.llamar(conv?.waId.map { "+" + $0 }) } label: { Image(systemName: "phone") }
                .accessibilityLabel("Llamar a \(nombre)")
            if estado.escribe, let c = conv {
                if c.agenteId == nil {
                    Button("Tomar") { Task { await pasar(estado.usuario?.id, "vos") } }.fontWeight(.semibold)
                }
                Menu { menuAcciones(c) } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Más acciones")
            }
        }
    }

    /// Tipo de contacto, origen, «sin dueño» y la ventana de 24 h.
    private var subtitulo: String {
        guard let c = conv else { return "" }
        let s = Charla.subtitulo(tipo: contacto?.tipo, origen: contacto?.origen, primero: primero, sinDueno: c.agenteId == nil)
        let v = c.ventanaRestante().map { "ventana abierta \($0)" } ?? (c.ultimoEntranteEn != nil ? "ventana cerrada" : nil)
        let quien = c.agenteId == nil ? nil : agente.map { "de \($0)" }
        return [s.nonEmpty ?? quien, v].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func menuAcciones(_ c: Conversacion) -> some View {
        if let x = c.contactoId {
            Button { estado.abrir(AFichaContacto(id: x)) } label: { Label("Ver contacto", systemImage: "person") }
        } else {
            Button { guardarContacto = true } label: { Label("Guardar como contacto", systemImage: "person.badge.plus") }
        }
        if let o = c.operacionId {
            Button { estado.abrir(AFichaOperacion(id: o)) } label: { Label("Ver la operación", systemImage: "rectangle.split.3x1") }
        } else {
            Button { Task { await crearOperacion() } } label: { Label("Crear operación", systemImage: "rectangle.split.3x1") }
        }
        Menu {
            ForEach(equipo.filter { $0.rol != "lector" && $0.usuarioId != c.agenteId }) { p in
                Button(p.usuarioId == estado.usuario?.id ? "\(p.completo) (vos)" : p.completo) { Task { await pasar(p.usuarioId, p.completo) } }
            }
            if c.agenteId != nil {
                Button { Task { await pasar(nil, "") } } label: { Label("Dejarla sin dueño", systemImage: "person.slash") }
            }
        } label: { Label("Pasársela a otro agente", systemImage: "arrow.left.arrow.right") }
        Button { vincular = true } label: { Label(c.propiedadId == nil ? "Vincular a una propiedad" : "Cambiar la propiedad", systemImage: "link") }
        Divider()
        Button { Task { await archivar() } } label: { Label("Archivar", systemImage: "archivebox") }
    }

    @ViewBuilder
    private func tarjetaPropiedad(_ c: Conversacion) -> some View {
        if ficha != nil || c.propiedadTitulo != nil {
            HStack(spacing: 10) {
                Button { if let p = c.propiedadId { estado.abrir(AFichaPropiedad(id: p)) } } label: {
                    HStack(spacing: 10) {
                        Foto(url: ficha?.miniatura).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.propiedadTitulo ?? ficha?.nombre ?? "").estilo(.label).foregroundStyle(C.texto).lineLimit(1)
                            if let f = ficha {
                                Text([Charla.resumenFicha(f).components(separatedBy: " · ").first?.nonEmpty, f.barrio].compactMap { $0 }.joined(separator: " · "))
                                    .font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1)
                                Text([Propiedad.estados.first { $0.0 == f.estado }?.1.lowercased(), interesados.flatMap { $0 > 0 ? Formato.cantidad($0, "interesado", "interesados") : nil }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                if estado.escribe {
                    Button("Cambiar") { vincular = true }
                        .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                        .foregroundStyle(C.accion).padding(.horizontal, 10).frame(height: 32).background(C.hundida, in: Capsule())
                }
            }
            .padding(8).tarjeta(14)
        } else if estado.escribe {
            Button { vincular = true } label: {
                Label("Vincular a una propiedad", systemImage: "link").estilo(.label).foregroundStyle(C.accion)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(C.linea2, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            }
            .buttonStyle(Presionable())
        }
    }

    // MARK: La charla

    private enum Item: Identifiable {
        case dia(String, String), msj(MensajeWA), vinculo(String), visita(String, String)
        var id: String {
            switch self {
            case .dia(let i, _), .visita(let i, _): return i
            case .msj(let m): return m.id
            case .vinculo: return "vinc"
            }
        }
    }

    /// Días, burbujas, el vínculo con la propiedad y las visitas agendadas, en orden.
    private var linea: [Item] {
        var out: [Item] = []
        var pendientes = visitas.sorted { ($0.creadaEn ?? $0.empiezaEn) < ($1.creadaEn ?? $1.empiezaEn) }
        var ultimoDia = ""
        var vinculo = false
        let cal = Formato.calendario
        func ponerDia(_ f: Date) {
            let t = cal.isDateInToday(f) ? "Hoy" : cal.isDateInYesterday(f) ? "Ayer" : Formato.fechaLarga(f)
            if t != ultimoDia { ultimoDia = t; out.append(.dia("d\(f.timeIntervalSince1970)", t)) }
        }
        func ponerVisitas(hasta: Date?) {
            while let v = pendientes.first, hasta == nil || (v.creadaEn ?? v.empiezaEn) <= hasta! {
                pendientes.removeFirst()
                ponerDia(v.creadaEn ?? v.empiezaEn)
                let t = "Visita agendada: \(Charla.diaHora(v.empiezaEn).replacingOccurrences(of: " · ", with: ", "))"
                    + (v.propiedadTitulo.map { " · \($0)" } ?? "") + (v.agenteNombre.map { " · \(Charla.primerNombre($0))" } ?? "")
                out.append(.visita("v" + v.id, t))
            }
        }
        for m in todos {
            ponerVisitas(hasta: m.ocurrioEn)
            ponerDia(m.ocurrioEn)
            out.append(.msj(m))
            if !vinculo, let p = conv?.propiedadTitulo, !m.saliente {
                vinculo = true
                out.append(.vinculo("Vinculada a \(p)\(conv?.propiedadPorCodigo == true ? " por el código del aviso" : "")"))
            }
        }
        ponerVisitas(hasta: nil)
        return out
    }

    private var charla: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(linea) { it in item(it).id(it.id) }
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(.horizontal, 12).padding(.vertical, 14)
            }
            .onChange(of: todos.count) { _, _ in withAnimation { lector.scrollTo("fin", anchor: .bottom) } }
            .onAppear { lector.scrollTo("fin", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func item(_ it: Item) -> some View {
        switch it {
        case .dia(_, let t):
            Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(C.texto2)
                .padding(.horizontal, 10).frame(height: 24).background(C.hundida, in: Capsule()).padding(.vertical, 4)
        case .vinculo(let t):
            Label(t, systemImage: "link").font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
        case .visita(_, let t):
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(C.oro)
                Text(t).estilo(.texto14).foregroundStyle(C.texto)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(C.avisoFondo, in: .rect(cornerRadius: 12))
        case .msj(let m):
            burbuja(m)
        }
    }

    private func burbuja(_ m: MensajeWA) -> some View {
        let sal = m.saliente
        return HStack {
            if sal { Spacer(minLength: 60) }
            VStack(alignment: sal ? .trailing : .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 6) {
                    contenido(m)
                    pie(m)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(sal ? Color.tema(0xDCEBE3, 0x1F3B33) : C.superficie,
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: sal ? 18 : 6, bottomTrailingRadius: sal ? 6 : 18, topTrailingRadius: 18, style: .continuous))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: sal ? 18 : 6, bottomTrailingRadius: sal ? 6 : 18, topTrailingRadius: 18, style: .continuous)
                    .strokeBorder(m.estado == "fallido" ? C.error : .clear, lineWidth: 1))
                .sombraE1()
                if m.estado == "fallido" && estado.escribe {
                    HStack(spacing: 4) {
                        Button("Reintentar") { Task { await reintentar(m) } }
                        Text("·").foregroundStyle(C.texto3)
                        Button("Borrar") { Task { await borrar(m) } }
                    }
                    .font(Estilo.footnoteFuerte.font).foregroundStyle(C.error)
                    if let e = m.error?.nonEmpty { Text(e).estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.trailing) }
                }
            }
            if !sal { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func contenido(_ m: MensajeWA) -> some View {
        let tipo = m.tipo ?? "texto"
        if let a = m.archivoId, tipo == "imagen" || m.mediaTipo?.hasPrefix("image/") == true {
            Button { Task { await abrir(a, nombre: "foto-\(a).jpg") } } label: {
                ImagenArchivo(id: a).frame(width: 220, height: 220).clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(Presionable())
            .accessibilityLabel(m.texto ?? "Foto")
        } else if let a = m.archivoId, tipo == "audio" {
            AudioArchivo(id: a)
        } else if let a = m.archivoId {
            Button { Task { await abrir(a, nombre: tipo == "video" ? "video-\(a).mp4" : "documento-\(a)\(m.mediaTipo == "application/pdf" ? ".pdf" : "")") } } label: {
                Label(tipo == "video" ? "Video" : "Documento", systemImage: tipo == "video" ? "film" : "doc.text")
                    .estilo(.subheadFuerte).foregroundStyle(C.accion)
            }
            .buttonStyle(Presionable())
        } else if tipo != "texto" && tipo != "plantilla" && m.texto?.nonEmpty == nil {
            Text(tipo == "ubicacion" ? "Ubicación" : tipo == "sticker" ? "Sticker" : "Mensaje que WhatsApp no deja ver acá")
                .estilo(.body16).italic().foregroundStyle(C.texto3)
        }
        if let t = m.texto?.nonEmpty {
            Text(t).estilo(.body16).foregroundStyle(C.texto).textSelection(.enabled)
        } else if let p = m.plantilla?.nombre {
            Text("Plantilla: \(p)").estilo(.body16).foregroundStyle(C.texto)
        }
    }

    private func pie(_ m: MensajeWA) -> some View {
        HStack(spacing: 4) {
            if m.tipo == "plantilla" { Text("plantilla ·") }
            if m.estado == "fallido" {
                Text("no salió")
                Image(systemName: "exclamationmark.circle.fill")
            } else {
                Text(Formato.horaDe(m.ocurrioEn))
                if m.saliente { tilde(m.estado) }
            }
        }
        .font(Estilo(tamano: 11, peso: .regular, relativo: .caption2).font)
        .foregroundStyle(m.estado == "fallido" ? C.error : C.texto3)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func tilde(_ e: String?) -> some View {
        switch e {
        case "pendiente": Image(systemName: "clock").accessibilityLabel("pendiente")
        case "enviado": Image(systemName: "checkmark").accessibilityLabel("enviado")
        case "entregado", "leido":
            HStack(spacing: -5) { Image(systemName: "checkmark"); Image(systemName: "checkmark") }
                .foregroundStyle(e == "leido" ? C.azulTinta : C.texto3)
                .accessibilityElement().accessibilityLabel(e == "leido" ? "leído" : "entregado")
        default: EmptyView()
        }
    }

    // MARK: Escribir

    private struct Sugerida: Identifiable { var id: String; var texto: String; var icono: String; var valor: String?; var agendar: Date? = nil }

    /// Lo que se propone contestar: agendar el día que propuso el cliente (si todavía no hay una visita
    /// cerca), «Sigue disponible + precio», «Mandar la ficha» y «Proponer visita».
    private var sugerencias: [Sugerida] {
        guard let c = conv, c.enVentana == true else { return [] }
        var xs: [Sugerida] = []
        let ultimo = todos.last { !$0.saliente }
        if let t = ultimo?.texto, let f = Charla.fechaPropuesta(t), c.propiedadId != nil,
           !visitas.contains(where: { abs($0.empiezaEn.timeIntervalSince(f)) < 3600 }) {
            return [Sugerida(id: "agendar", texto: "Agendar \(Charla.diaHora(f))", icono: "calendar.badge.checkmark", valor: nil, agendar: f)]
        }
        guard c.esperando == true else { return xs }
        if let f = ficha {
            if let s = Charla.sugerenciaDisponible(primero, f) { xs.append(Sugerida(id: "disponible", texto: "Sigue disponible + precio", icono: "sparkles", valor: s)) }
            if let fi = Charla.textoFicha(primero, f, web: web) { xs.append(Sugerida(id: "ficha", texto: "Mandar la ficha", icono: "house", valor: fi)) }
        }
        if let pr = Charla.textoPropuesta(primero, turnos) { xs.append(Sugerida(id: "visita", texto: "Proponer visita", icono: "calendar", valor: pr)) }
        return xs
    }

    @ViewBuilder
    private func sugerenciasYTurnos(_ c: Conversacion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !turnos.isEmpty && estado.escribe {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(agente.map { "\($0) tiene libre" } ?? "Vos tenés libre").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2)
                        ForEach(turnos, id: \.self) { t in
                            Button(Charla.diaHora(t)) {
                                chip = "visita"
                                let p = Charla.diaHora(t).components(separatedBy: " · ")
                                texto = "\(primero.isEmpty ? "¿" : primero + ", ¿")te queda bien el \(p[0]) a las \(p.count > 1 ? p[1] : "") para verlo?"
                            }
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.accion)
                            .padding(.horizontal, 10).frame(height: 30).background(C.hundida, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            if estado.escribe {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sugerencias) { s in
                            chipBoton(s.texto, s.icono, activo: chip == s.id, fuerte: s.agendar != nil) { usar(s) }
                        }
                        chipBoton("Respuestas guardadas /", "bolt", activo: abiertaR || chip == "guardada", fuerte: false) { abrirRespuestas() }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.top, 6)
    }

    private func chipBoton(_ t: String, _ i: String, activo: Bool, fuerte: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Label(t, systemImage: i).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                .foregroundStyle(fuerte ? C.sobreAccion : (activo ? C.accion : C.texto))
                .padding(.horizontal, 10).frame(height: 32)
                .background(fuerte ? C.accion : (activo ? C.crema : C.hundida), in: Capsule())
        }
        .buttonStyle(Presionable())
    }

    private func usar(_ s: Sugerida) {
        if let f = s.agendar { Task { await agendar(f) }; return }
        chip = s.id
        texto = s.valor ?? ""
    }

    private var guardable: Bool { !texto.hasPrefix("/") && texto.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 }
    private var filtradas: [RespuestaGuardada] { Array(Charla.filtrar(respuestas, texto.hasPrefix("/") ? String(texto.dropFirst()) : "").prefix(6)) }

    private func abrirRespuestas() {
        if abiertaR { abiertaR = false; if texto == "/" { texto = "" }; return }
        if texto.trimmingCharacters(in: .whitespaces).isEmpty { texto = "/" }
        abiertaR = true
    }

    private var panelRespuestas: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filtradas) { r in
                Button { usarRespuesta(r) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                        Text(Charla.completarRespuesta(r.texto, primero)).estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
            }
            if filtradas.isEmpty {
                Text(Formato.sinViudas(respuestas.isEmpty ? "Todavía no hay respuestas guardadas. Escribí un mensaje y guardalo para usarlo con una «/»." : "Ninguna coincide."))
                    .estilo(.footnote).foregroundStyle(C.texto2).padding(14)
            }
            if guardable {
                Button { abiertaR = false; guardandoR = true } label: {
                    Label("Guardar este mensaje como respuesta", systemImage: "plus").estilo(.subheadFuerte).foregroundStyle(C.accion)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14).contentShape(Rectangle())
                }
                .buttonStyle(Presionable())
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
        .frame(maxHeight: 280)
        .tarjeta(16)
        .padding(.horizontal, 12).padding(.top, 6)
    }

    private func usarRespuesta(_ r: RespuestaGuardada) {
        abiertaR = false
        chip = "guardada"
        texto = Charla.completarRespuesta(r.texto, primero)
        Task { try? await estado.api.hacer("POST", "/v1/respuestas-guardadas/\(r.id)/uso") }
    }

    private var entrada: some View {
        VStack(spacing: 6) {
            if let a = adjunto {
                HStack(spacing: 8) {
                    Image(systemName: (a.tipo ?? "").hasPrefix("image/") ? "photo" : "doc.text").foregroundStyle(C.accion)
                    Text(a.nombre ?? "Adjunto").estilo(.footnote).foregroundStyle(C.texto).lineLimit(1)
                    Spacer()
                    Button { adjunto = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.texto3) }
                        .accessibilityLabel("Sacar el adjunto")
                }
                .padding(.horizontal, 12).frame(height: 36).background(C.hundida, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 12)
            }
            if estado.escribe {
                HStack(spacing: 6) {
                    Menu {
                        Button { fotos = true } label: { Label("Fotos y videos", systemImage: "photo.on.rectangle") }
                        Button { camara = true } label: { Label("Sacar una foto", systemImage: "camera") }
                        Button { archivos = true } label: { Label("Un archivo (PDF, video, audio)", systemImage: "doc") }
                    } label: {
                        Image(systemName: subiendo ? "hourglass" : "paperclip").font(.system(size: 22)).foregroundStyle(C.accion).frame(width: 40, height: 40)
                    }
                    .disabled(subiendo)
                    .accessibilityLabel("Adjuntar un archivo")
                    TextField("Escribí un mensaje", text: $texto, axis: .vertical).estilo(.body16).lineLimit(1...6)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(C.superficie, in: .rect(cornerRadius: 19))
                        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(C.linea2, lineWidth: 0.5))
                        .accessibilityLabel("Mensaje para \(nombre)")
                    if texto.isEmpty && adjunto == nil {
                        Image(systemName: grabadora.grabando ? "waveform" : "mic").font(.system(size: 22)).foregroundStyle(grabadora.grabando ? C.error : C.accion)
                            .frame(width: 40, height: 40)
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !grabadora.grabando { grabadora.empezar() } }
                                .onEnded { _ in
                                    if let u = grabadora.terminar() { Task { await mandarNotaDeVoz(u) } }
                                })
                            .accessibilityLabel("Nota de voz: mantené apretado para grabar")
                    } else {
                        Button { Task { await mandar() } } label: {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(C.sobreAccion)
                                .frame(width: 36, height: 36).background(C.accion, in: Circle())
                        }
                        .disabled(subiendo || (texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && adjunto == nil))
                        .accessibilityLabel("Enviar")
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Fuera de la ventana

    private var aprobadas: [PlantillaWA] { plantillas.filter { $0.nombre != "recordatorio_visita" } }
    private var elegida: PlantillaWA? { aprobadas.first { $0.nombre == plantilla } }
    private var completa: Bool { elegida != nil && parametros.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    private func fueraDeVentana(_ c: Conversacion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 18)).foregroundStyle(C.avisoTinta)
                    Text(Formato.sinViudas(c.ultimoEntranteEn.map {
                        "\(primero.isEmpty ? nombre : primero) escribió hace \(max(0, Int(Date().timeIntervalSince($0)) / 3600)) h. WhatsApp sólo deja retomar con una plantilla aprobada; cuando conteste, podés escribir libre."
                    } ?? "Todavía no escribió. WhatsApp sólo deja empezar con una plantilla aprobada; cuando conteste, podés escribir libre."))
                    .estilo(.texto14).foregroundStyle(C.texto)
                }
                if c.esperando != true && !otra && todos.last?.saliente == true {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass").foregroundStyle(C.avisoTinta)
                        Text("Plantilla enviada · esperando respuesta.").estilo(.subheadFuerte).foregroundStyle(C.texto)
                        Spacer()
                        if !aprobadas.isEmpty && estado.escribe { Button("Mandar otra") { otra = true }.estilo(.subheadFuerte).foregroundStyle(C.accion) }
                    }
                } else if !aprobadas.isEmpty && estado.escribe {
                    ForEach(aprobadas) { p in tarjetaPlantilla(p) }
                    if let e = elegida, (e.parametros ?? 0) > 0 {
                        ForEach(parametros.indices, id: \.self) { i in
                            Etiquetado(i == 0 ? "Nombre" : i == 1 ? "Quién escribe" : "Dato \(i + 1)") {
                                TextField("", text: $parametros[i]).campoCorredor()
                            }
                        }
                    }
                    Button(mandandoPlantilla ? "Mandando…" : "Mandar plantilla") { Task { await mandarPlantilla() } }
                        .buttonStyle(BotonPrincipal())
                        .disabled(!completa || mandandoPlantilla)
                } else if aprobadas.isEmpty {
                    Text("Todavía no hay plantillas aprobadas en Meta.").estilo(.footnote).foregroundStyle(C.texto2)
                }
            }
            .padding(14)
            .background(GeometryReader { g in
                Color.clear.onAppear { altoFuera = g.size.height }.onChange(of: g.size.height) { _, h in altoFuera = h }
            })
        }
        .frame(height: min(380, altoFuera))
        .background(C.avisoFondo, in: .rect(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 16)
    }

    private func tarjetaPlantilla(_ p: PlantillaWA) -> some View {
        let on = plantilla == p.nombre
        return Button { elegirPlantilla(p) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Charla.nombrePlantilla(p.nombre)).estilo(.subheadFuerte).foregroundStyle(C.texto)
                    Spacer()
                    Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? C.accion : C.texto3)
                }
                if let cu = p.cuerpo { Text(on ? Charla.completar(cu, parametros) : cu).estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.leading) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(C.superficie, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? C.accion : .clear, lineWidth: 1.5))
        }
        .buttonStyle(Presionable())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func elegirPlantilla(_ p: PlantillaWA) {
        plantilla = p.nombre
        let yo = Charla.primerNombre(estado.usuario?.nombre)
        parametros = (0..<(p.parametros ?? 0)).map { i in i == 0 ? primero : i == 1 ? yo : "" }
    }

    // MARK: Datos

    private func cargar() async {
        let c: Conversacion
        do {
            c = try await estado.api.get("/v1/whatsapp/conversaciones/\(id)")
            errorCarga = nil
        } catch let e as ErrorApi {
            if conv == nil { errorCarga = e }
            return
        } catch { return }
        let cambio = conv?.id != c.id
        conv = c
        if cambio { texto = BorradorChat.textos.removeValue(forKey: c.id) ?? ""; chip = nil; adjunto = nil }
        await cargarMensajes()
        if (c.noLeidos ?? 0) > 0 { try? await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/leida") }
        if let p = c.propiedadId {
            ficha = try? await estado.api.get("/v1/propiedades/\(p)")
            let l: [JSONLibre]? = try? await estado.api.get("/v1/propiedades/\(p)/interesados", query: [.init(name: "limite", value: "100")])
            interesados = l?.count
        } else { ficha = nil; interesados = nil }
        if let x = c.contactoId {
            contacto = try? await estado.api.get("/v1/contactos/\(x)")
            let v: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "contacto", value: x), .init(name: "rango", value: "todas"), .init(name: "limite", value: "200")])) ?? []
            visitas = v.filter { $0.tipo == "visita" && $0.estado != "cancelada" }
        } else { contacto = nil; visitas = [] }
        if let quien = c.agenteId ?? estado.usuario?.id {
            let hoy = Date()
            let en10 = Formato.calendario.date(byAdding: .day, value: 10, to: hoy) ?? hoy
            let agenda: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "agente", value: quien), .init(name: "desde", value: Formato.diaISO(hoy)),
                                                                                  .init(name: "hasta", value: Formato.diaISO(en10)), .init(name: "limite", value: "500")])) ?? []
            turnos = Charla.turnosLibres(agenda.filter { $0.estado != "cancelada" })
        }
        if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
        if web == nil { web = await Documentos.inmobiliaria(estado.api)?.web }
        if c.enVentana != true && plantillas.isEmpty { plantillas = (try? await estado.api.get("/v1/whatsapp/plantillas")) ?? [] }
        if respuestas.isEmpty { respuestas = (try? await estado.api.get("/v1/respuestas-guardadas")) ?? [] }
    }

    private func cargarMensajes() async {
        if let m: [MensajeWA] = try? await estado.api.get("/v1/whatsapp/conversaciones/\(id)/mensajes", query: [.init(name: "limite", value: "200")]) {
            mensajes = m.sorted { $0.ocurrioEn < $1.ocurrioEn }
            let ids = Set(mensajes.map(\.id))
            enviados = enviados.filter { !ids.contains($0.id) && ($0.local ? $0.estado != "enviado" : true) }
        }
    }

    private func local(_ t: String?, adjunto a: Archivo?) -> MensajeWA {
        MensajeWA(id: "tmp-\(UUID().uuidString)", conversacionId: id, direccion: "saliente",
                  tipo: a.map { ($0.tipo ?? "").hasPrefix("image/") ? "imagen" : "documento" } ?? "texto",
                  texto: t?.nonEmpty, mediaTipo: a?.tipo, archivoId: nil, estado: "pendiente", autorId: estado.usuario?.id, ocurrioEn: Date())
    }

    private func marcar(_ tmp: String, fallo: String) {
        if let i = enviados.firstIndex(where: { $0.id == tmp }) { enviados[i].estado = "fallido"; enviados[i].error = fallo }
    }

    private func mandar() async {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = adjunto
        guard !t.isEmpty || a != nil, !subiendo else { return }
        let tmp = local(t, adjunto: a)
        enviados.append(tmp)
        texto = ""
        chip = nil
        adjunto = nil
        do {
            if let a {
                struct Cuerpo: Encodable { var texto: String; var archivoId: String }
                let m: MensajeWA = try await estado.api.enviar("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(texto: t, archivoId: a.id))
                enviados.removeAll { $0.id == tmp.id }
                enviados.append(m)
            } else {
                struct Cuerpo: Encodable { var texto: String }
                let subio = try await estado.cola.enviar("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(texto: t), etiqueta: "Mensaje a \(nombre)")
                if subio { enviados.removeAll { $0.id == tmp.id } } else { estado.avisar("Sin señal: lo que escribas sale cuando vuelva.") }
            }
            await cargarMensajes()
        } catch {
            marcar(tmp.id, fallo: Estado.texto(error, si: "No salió"))
            if let e = error as? ErrorApi, e.codigo == "fuera_de_ventana" { await cargar() }
        }
    }

    private func reintentar(_ m: MensajeWA) async {
        if m.local {
            ocultos.insert(m.id)
            texto = m.texto ?? ""
            await mandar()
            return
        }
        do {
            try await estado.api.hacer("POST", "/v1/whatsapp/mensajes/\(m.id)/reintentar")
            await cargarMensajes()
        } catch { estado.avisar(error) }
    }

    private func borrar(_ m: MensajeWA) async {
        ocultos.insert(m.id)
        if m.local { return }
        do {
            try await estado.api.hacer("DELETE", "/v1/whatsapp/mensajes/\(m.id)")
            await cargarMensajes()
        } catch {
            ocultos.remove(m.id)
            estado.avisar("No se borró", ok: false)
        }
    }

    private func subir(_ d: Data, nombre: String, tipo: String) async {
        subiendo = true
        defer { subiendo = false }
        do { adjunto = try await estado.api.subir(d, nombre: nombre, tipo: tipo, uso: "adjunto") } catch { estado.avisar(error) }
    }

    private func subirArchivo(_ u: URL) async {
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        do {
            let d = try Data(contentsOf: u)
            let tipo = UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            await subir(d, nombre: u.lastPathComponent, tipo: tipo)
        } catch { estado.avisar("No se pudo subir", ok: false) }
    }

    private func mandarNotaDeVoz(_ u: URL) async {
        do {
            let d = try Data(contentsOf: u)
            let a = try await estado.api.subir(d, nombre: "nota.m4a", tipo: "audio/mp4", uso: "audio")
            struct Cuerpo: Encodable { var texto = ""; var archivoId: String }
            try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes", Cuerpo(archivoId: a.id))
            await cargarMensajes()
        } catch { estado.avisar(error) }
    }

    private func mandarPlantilla() async {
        guard let p = elegida, completa else { return }
        struct Datos: Encodable { var nombre: String; var idioma: String; var parametros: [String] }
        struct Cuerpo: Encodable { var plantilla: Datos }
        mandandoPlantilla = true
        defer { mandandoPlantilla = false }
        do {
            try await estado.api.hacer("POST", "/v1/whatsapp/conversaciones/\(id)/mensajes",
                                       Cuerpo(plantilla: Datos(nombre: p.nombre, idioma: p.idioma ?? "es_AR", parametros: parametros.map { $0.trimmingCharacters(in: .whitespaces) })))
            plantilla = nil
            otra = false
            estado.avisar("Plantilla enviada a \(primero.isEmpty ? nombre : primero) · esperando respuesta")
            await cargar()
        } catch {
            estado.avisarReintentar(Estado.texto(error, si: "No salió")) { Task { await mandarPlantilla() } }
        }
    }

    /// Un cambio en la conversación (dueño, propiedad, contacto, operación), con su Deshacer.
    private func cambiar(_ cuerpo: JSONLibre, _ aviso: String, deshacer: JSONLibre?) async {
        do {
            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", cuerpo)
            if let deshacer {
                estado.avisar(aviso) {
                    Task {
                        do {
                            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", deshacer)
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            } else { estado.avisar(aviso) }
            estado.version += 1
        } catch { estado.avisar(Estado.texto(error, si: "No se guardó"), ok: false) }
    }

    private func pasar(_ quien: String?, _ n: String) async {
        let t = quien.map { $0 == estado.usuario?.id ? "La conversación es tuya" : "Se la pasaste a \(Charla.primerNombre(n))" } ?? "Quedó sin dueño"
        await cambiar(.objeto(["agenteId": quien.map { .texto($0) } ?? .nulo]), t, deshacer: .objeto(["agenteId": conv?.agenteId.map { .texto($0) } ?? .nulo]))
    }

    private func archivar() async {
        do {
            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", JSONLibre.objeto(["archivada": .bool(true)]))
            estado.version += 1
            estado.avisar("Conversación archivada") {
                Task {
                    do {
                        try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", JSONLibre.objeto(["archivada": .bool(false)]))
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    /// Guarda el número como contacto (con el teléfono, origen whatsapp y el agente) y lo vincula.
    private func crearContacto(_ n: String, _ tipo: String) async -> Bool {
        guard let c = conv else { return false }
        struct Cuerpo: Encodable { var nombre: String; var tipo: String; var telefono: String; var origen = "whatsapp"; var agenteId: String? }
        struct Nuevo: Decodable { var id: String }
        do {
            let x: Nuevo = try await estado.api.enviar("POST", "/v1/contactos", Cuerpo(nombre: n, tipo: tipo, telefono: "+" + (c.waId ?? ""), agenteId: c.agenteId))
            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", JSONLibre.objeto(["contactoId": .texto(x.id)]))
            estado.sugerir("\(n) quedó en Contactos", "Ver", AFichaContacto(id: x.id))
            estado.version += 1
            return true
        } catch {
            estado.avisar(Estado.texto(error, si: "No se guardó"), ok: false)
            return false
        }
    }

    /// La operación de esta charla: contacto · propiedad, en Contactado, con el precio de la ficha.
    private func crearOperacion() async {
        guard let c = conv else { return }
        struct Cuerpo: Encodable {
            var titulo: String; var etapa = "contactado"; var valor: Double; var moneda: String
            var contactoId: String?; var propiedadId: String?; var agenteId: String?
        }
        struct Nueva: Decodable { var id: String }
        let titulo = [c.contactoNombre ?? c.nombre?.nonEmpty, c.propiedadTitulo].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Consulta por WhatsApp"
        do {
            let o: Nueva = try await estado.api.enviar("POST", "/v1/operaciones", Cuerpo(titulo: titulo, valor: ficha?.precio ?? 0, moneda: ficha?.moneda ?? "USD",
                                                                                        contactoId: c.contactoId, propiedadId: c.propiedadId, agenteId: c.agenteId))
            try await estado.api.hacer("PATCH", "/v1/whatsapp/conversaciones/\(id)", JSONLibre.objeto(["operacionId": .texto(o.id)]))
            estado.sugerir("Operación creada en Contactado", "Ver", AFichaOperacion(id: o.id))
            estado.version += 1
        } catch { estado.avisar(Estado.texto(error, si: "No se creó"), ok: false) }
    }

    /// Agenda la visita que propuso el cliente y deja escrita la confirmación.
    private func agendar(_ f: Date) async {
        guard let c = conv else { return }
        struct Cuerpo: Encodable {
            var tipo = "visita"; var estado = "pendiente"; var titulo: String; var empiezaEn: Date; var duracionMin = 60
            var propiedadId: String?; var contactoId: String?; var operacionId: String?; var agenteId: String?; var recordar: Bool
        }
        do {
            try await estado.api.hacer("POST", "/v1/agenda", Cuerpo(titulo: c.propiedadTitulo.map { "Visita · \($0)" } ?? "Visita", empiezaEn: f,
                                                                     propiedadId: c.propiedadId, contactoId: c.contactoId, operacionId: c.operacionId,
                                                                     agenteId: c.agenteId, recordar: c.contactoId != nil))
            let d = Charla.diaHora(f)
            estado.sugerir("Visita agendada: \(d)", "Ver", AAgendaDia(dia: Formato.diaISO(f)))
            let p = d.components(separatedBy: " · ")
            texto = "Listo\(primero.isEmpty ? "" : " " + primero), te espero el \(p[0]) a las \(p.count > 1 ? p[1] : "")\(c.propiedadTitulo.map { " en \($0)" } ?? ""). Te mando la ubicación."
            estado.version += 1
        } catch { estado.avisar(Estado.texto(error, si: "No se agendó"), ok: false) }
    }

    private func abrir(_ archivo: String, nombre: String) async {
        do {
            let u = try await ArchivosSesion.archivo(archivo, nombre: nombre, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

/// Lo que otra pantalla deja escrito para mandar en una charla (la ficha que se manda desde un contacto).
@MainActor
enum BorradorChat {
    static var textos: [String: String] = [:]
}

/// Una nota de voz de /v1/archivos (se baja con la sesión antes de escucharla).
struct AudioArchivo: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var url: URL?

    var body: some View {
        Group {
            if let url { AudioMensaje(url: url) } else { ProgressView().frame(width: 196, height: 30) }
        }
        .task(id: id) { url = try? await ArchivosSesion.archivo(id, nombre: "audio-\(id).m4a", api: estado.api) }
    }
}

/// Vincular la charla a una propiedad: la búsqueda del servidor (calle, barrio o código) y Desvincular.
struct VincularPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var tiene: Bool
    /// La elegida (id y título), o nil para desvincular.
    var alElegir: (Resultado?) -> Void
    @State private var q = ""
    @State private var res: [Resultado] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("Vincular a una propiedad", systemImage: "link").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Buscador(placeholder: "Calle, barrio o código…", texto: $q)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(res.enumerated()), id: \.element.id) { i, x in
                        Button { alElegir(x); cerrar() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "house").foregroundStyle(C.accion).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.titulo).estilo(.filaLista).foregroundStyle(C.texto)
                                    if let s = x.subtitulo { Text(s).estilo(.footnote).foregroundStyle(C.texto2) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                    if q.trimmingCharacters(in: .whitespaces).count >= 2 && res.isEmpty {
                        Text("No encontramos nada con «\(q)».").estilo(.subhead).foregroundStyle(C.texto2).padding(16)
                    }
                }
                .tarjeta()
            }
            HStack(spacing: 10) {
                if tiene { Button("Desvincular") { alElegir(nil); cerrar() }.buttonStyle(BotonTexto(color: C.error)) }
                Button("Cerrar") { cerrar() }.buttonStyle(BotonSecundario())
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .task(id: q) {
            let t = q.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2 else { res = []; return }
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            let r: [Resultado] = (try? await estado.api.get("/v1/buscar", query: [.init(name: "q", value: t)])) ?? []
            res = Array(r.filter { $0.tipo == "propiedad" }.prefix(8))
        }
    }
}

/// «Guardar como contacto»: el nombre y qué busca, con el número de la charla.
struct GuardarNumero: View {
    @Environment(\.dismiss) private var cerrar
    var waId: String
    @State var nombre: String
    @State var tipo: String
    var guardar: (String, String) async -> Bool
    @State private var creando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("Guardar como contacto", systemImage: "person.badge.plus").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text("Con el número +\(waId).").estilo(.subhead).foregroundStyle(C.texto2)
            Etiquetado("Nombre") { TextField("", text: $nombre).campoCorredor().textContentType(.name) }
            Etiquetado("Busca") {
                Picker("Busca", selection: $tipo) {
                    Text("Comprar").tag("comprador"); Text("Alquilar").tag("inquilino"); Text("Vender").tag("vendedor"); Text("Es propietario").tag("propietario")
                }
                .pickerStyle(.segmented)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button(creando ? "Guardando…" : "Guardar") {
                    Task {
                        creando = true
                        let ok = await guardar(nombre.trimmingCharacters(in: .whitespaces), tipo)
                        creando = false
                        if ok { cerrar() }
                    }
                }
                .buttonStyle(BotonPrincipal())
                .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || creando)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

/// «Guardar como respuesta»: el nombre corto de lo escrito, para usarlo con una «/».
struct GuardarRespuesta: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var texto: String
    var alGuardar: (RespuestaGuardada) -> Void
    @State private var titulo = ""
    @State private var guardando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Label("Guardar como respuesta", systemImage: "bolt").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text(Formato.sinViudas("La ve todo el equipo. Escribí «/» en un mensaje para usarla.")).estilo(.subhead).foregroundStyle(C.texto2)
            Etiquetado("Nombre") { TextField("", text: $titulo).campoCorredor().autocorrectionDisabled() }
            Text("Corto, para encontrarla: «Horarios», «Requisitos».").estilo(.footnote).foregroundStyle(C.texto3)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonSecundario())
                Button("Guardar") { Task { await guardar() } }.buttonStyle(BotonPrincipal())
                    .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty || guardando)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func guardar() async {
        struct Cuerpo: Encodable { var titulo: String; var texto: String }
        guardando = true
        defer { guardando = false }
        do {
            let r: RespuestaGuardada = try await estado.api.enviar("POST", "/v1/respuestas-guardadas", Cuerpo(titulo: titulo.trimmingCharacters(in: .whitespaces), texto: texto))
            alGuardar(r)
            estado.avisar("Quedó en las respuestas guardadas: \(r.titulo)")
            cerrar()
        } catch { estado.avisar(Estado.texto(error, si: "No se guardó"), ok: false) }
    }
}
