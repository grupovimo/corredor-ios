import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 9C Ficha de la operación, como la del panel (18b): «¿qué falta para cerrar?». La etapa como una
/// línea que se toca para pasar a cualquiera (con Deshacer); «Para pasar a Cierre» según sea venta o
/// alquiler; las dos partes; la seña y los honorarios (editables); los adjuntos; el historial con
/// comentarios; «Se cayó» y «Reabrir».
struct FichaOperacion: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var o: Operacion?
    @State private var error: ErrorApi?
    @State private var historial: [EventoOperacion] = []
    @State private var adjuntos: [Archivo] = []
    @State private var visitas = 0
    @State private var proxima: Cita?
    @State private var contacto: Contacto?
    @State private var equipo: [Miembro] = []
    @State private var comentario = ""
    @State private var previo: ArchivoPrevio?
    @State private var haciendoContrato = false
    @State private var editarPlata = false
    @State private var cayendo = false
    @State private var agendar = false
    @State private var subiendo = false
    @State private var fotos = false
    @State private var foto: PhotosPickerItem?
    @State private var archivos = false

    private var puedeMover: Bool { estado.escribe }
    private var nombres: [String: String] { Dictionary(equipo.map { ($0.usuarioId, $0.completo) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        ScrollView {
            if let o {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(o)
                    if o.caidaEn != nil { caida(o) }
                    linea(o)
                    if let p = proxima { tarjetaProxima(p) }
                    if o.caidaEn == nil { paraCerrar(o) }
                    partes(o)
                    honorarios(o)
                    adjuntosVista(o)
                    historialVista
                    if o.etapa == "cierre" && o.propiedadOperacion == "alquiler" {
                        Button("Hacer el contrato") { haciendoContrato = true }.buttonStyle(BotonHundido())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else if let error {
                EstadoError(que: "la operación", error: error) { Task { await cargar() } }.padding(.top, 40)
            } else { EsqueletoFilas(filas: 5).padding(16) }
        }
        .pantallaApilada("Operación")
        .toolbar { if let o { Menu { menu(o) } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Más") } }
        .sheet(isPresented: $haciendoContrato) { AltaContrato(operacion: id) }
        .sheet(isPresented: $editarPlata) { if let o { PlataOperacion(o: o, agente: o.agenteNombre.map { Charla.primerNombre($0) }).hojaTLW([.large]) } }
        .sheet(isPresented: $cayendo) {
            if let o { SeCayo(propiedad: String(o.nombre.split(separator: ",").first ?? ""), contacto: o.contactoNombre) { m in Task { await caer(m) } }.hojaTLW([.medium, .large]) }
        }
        .sheet(isPresented: $agendar) {
            if let o { NuevaCita(contacto: o.contactoId.map { (id: $0, nombre: o.contactoNombre ?? "") }, operacion: o.id).presentationDetents([.large]) }
        }
        .photosPicker(isPresented: $fotos, selection: $foto, matching: .images)
        .onChange(of: foto) { _, i in
            guard let i else { return }
            Task {
                do {
                    if let d = try await i.loadTransferable(type: Data.self) { await subir(UIImage(data: d)?.jpegData(compressionQuality: 0.85) ?? d, nombre: "foto.jpg", tipo: "image/jpeg") }
                } catch { estado.avisar(error) }
                foto = nil
            }
        }
        .fileImporter(isPresented: $archivos, allowedContentTypes: [.pdf, .image, .data]) { r in if case .success(let u) = r { Task { await subirArchivo(u) } } }
        .vistaPrevia($previo)
        .task(id: estado.version) { await cargar() }
    }

    @ViewBuilder
    private func menu(_ o: Operacion) -> some View {
        if let c = o.contactoId { Button { estado.abrir(AFichaContacto(id: c)) } label: { Label("Ver el contacto", systemImage: "person") } }
        if let p = o.propiedadId { Button { estado.abrir(AFichaPropiedad(id: p)) } label: { Label("Ver la propiedad", systemImage: "house") } }
        if puedeMover { Button { agendar = true } label: { Label("Agendar visita", systemImage: "calendar") } }
        if puedeMover && o.caidaEn == nil { Button(role: .destructive) { cayendo = true } label: { Label("Se cayó", systemImage: "heart.slash") } }
    }

    // MARK: Partes de la ficha

    private func cabecera(_ o: Operacion) -> some View {
        let cal = Formato.calendario
        let dias = o.creadaEn.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: Date())).day ?? 0 } ?? 0
        let tipo = ["venta": "Venta", "alquiler": "Alquiler", "temporario": "Temporario"][o.propiedadOperacion ?? ""]
        let sub = [tipo, o.agenteNombre, dias <= 0 ? "abierta hoy" : "abierta hace \(Formato.cantidad(dias, "día", "días"))"].compactMap { $0 }.joined(separator: " · ")
        let hc = o.honorariosComprador, hv = o.honorariosVendedor
        let extra = [o.propiedadPrecio.flatMap { $0 != o.valor ? "pedía \(Formato.numero(Int($0)))" : nil },
                     hc != nil || hv != nil ? "honorarios \(hc.map { Formato.porcentaje($0) } ?? "—") + \(hv.map { Formato.porcentaje($0) } ?? "—")" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            Foto(url: urlFotoPropiedad(o.propiedadFotoId, api: estado.api.base, inmobiliaria: estado.sesion?.inmobiliariaId))
                .frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(sub).estilo(.footnote).foregroundStyle(C.texto2)
                Text("\(String(o.nombre.split(separator: ",").first ?? ""))\(o.contactoNombre.map { " → \($0)" } ?? "")")
                    .font(Estilo(tamano: 22, peso: .bold, tracking: -0.02, relativo: .title2).font).foregroundStyle(C.texto)
                Text((o.valor ?? 0) > 0 ? Formato.plata(o.valor ?? 0, o.moneda ?? "USD") : "Sin oferta").estilo(.headline).foregroundStyle(C.texto)
                if !extra.isEmpty { Text(extra).estilo(.footnote).foregroundStyle(C.texto2) }
            }
        }
    }

    private func caida(_ o: Operacion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.slash.fill").foregroundStyle(C.errorTinta)
            Text("Se cayó el \(o.caidaEn.map { FichaContacto.diaMes($0) } ?? "") · \(o.caidaMotivo ?? "")").estilo(.subheadFuerte).foregroundStyle(C.errorTinta)
            Spacer()
            if puedeMover { Button("Reabrir") { Task { await reabrir() } }.buttonStyle(BotonTonal()) }
        }
        .padding(12).background(C.errorFondo, in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// La etapa como una línea: tocar otra etapa la pasa ahí (con Deshacer).
    private func linea(_ o: Operacion) -> some View {
        let actual = Operacion.columna(o.etapa)
        let iconos = ["sparkle", "calendar", "bookmark", "hands.sparkles"]
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(Operacion.columnas.enumerated()), id: \.offset) { i, c in
                Button { Task { await aEtapa(i) } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: i < actual ? "checkmark" : iconos[i])
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(i < actual ? C.sobreAccion : (i == actual ? Color(hex: 0x1A1405) : C.texto3))
                            .frame(width: 30, height: 30).background(i < actual ? C.accion : (i == actual ? C.oro : C.hundida), in: Circle())
                        Text(c.texto + extraEtapa(i, o)).font(Estilo(tamano: 11, peso: i == actual ? .bold : .medium, relativo: .caption2).font)
                            .foregroundStyle(i <= actual ? C.texto : C.texto3).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(Presionable())
                .disabled(!puedeMover || o.caidaEn != nil || i == actual)
                .accessibilityLabel(i == actual ? "\(c.texto), etapa actual" : "Pasar a \(c.texto)")
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 8).tarjeta()
    }

    /// «Visita · 2», «Reserva · seña USD 3.000».
    private func extraEtapa(_ i: Int, _ o: Operacion) -> String {
        guard i == Operacion.columna(o.etapa) else { return "" }
        if Operacion.columnas[i].clave == "visita" && visitas > 0 { return " · \(visitas)" }
        if Operacion.columnas[i].clave == "reserva" { return " · \(o.nota().0)" }
        return ""
    }

    private func tarjetaProxima(_ p: Cita) -> some View {
        Button { estado.abrir(ACita(id: p.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 24)).foregroundStyle(C.avisoTinta)
                VStack(alignment: .leading) {
                    Text("Próximo paso").font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.avisoTinta)
                    Text("\(p.tipoTexto) · \(Formato.diaCompleto(p.empiezaEn)), \(Formato.horaDe(p.empiezaEn))").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                }
                Spacer()
            }
            .padding(14).background(C.avisoFondo, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(Presionable())
    }

    private func paraCerrar(_ o: Operacion) -> some View {
        let pasos = o.pasosCierre(etiquetas: contacto?.etiquetas ?? [])
        let actual = pasos.firstIndex { !$0.hecho }
        return VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: Operacion.columna(o.etapa) == 3 ? "Para cerrar" : "Para pasar a Cierre", cuenta: "\(pasos.filter(\.hecho).count) de \(pasos.count)")
            VStack(spacing: 0) {
                ForEach(Array(pasos.enumerated()), id: \.element.clave) { i, p in paso(p, ahora: i == actual, primera: i == 0) }
            }
            .tarjeta()
        }
    }

    private func paso(_ p: Operacion.Paso, ahora: Bool, primera: Bool) -> some View {
        HStack(spacing: 12) {
            Button { Task { await marcar(p) } } label: {
                Image(systemName: p.hecho ? "checkmark.square.fill" : "square").font(.system(size: 24))
                    .foregroundStyle(p.hecho ? Color(hex: 0x2F9E6F) : C.texto3)
            }
            .disabled(!puedeMover || p.auto)
            .accessibilityLabel(p.texto)
            .accessibilityAddTraits(p.hecho ? .isSelected : [])
            Text(p.texto).estilo(.body16).foregroundStyle(p.hecho ? C.texto3 : C.texto).strikethrough(p.hecho).fontWeight(ahora ? .semibold : .regular)
            Spacer(minLength: 4)
            if p.clave == "sena" && !p.hecho && puedeMover {
                Button("Cargar seña") { editarPlata = true }.buttonStyle(BotonTonal())
            } else if ahora, let l = p.llamar {
                Button { Afuera.llamar(l.telefono) } label: { Label(l.texto, systemImage: "phone.fill") }.buttonStyle(BotonTonal())
            } else if let d = p.detalle {
                Text(d).estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(ahora ? C.avisoFondo.opacity(0.6) : Color.clear)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func partes(_ o: Operacion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Las partes")
            VStack(spacing: 0) {
                if let n = o.contactoNombre {
                    let rol = o.propiedadOperacion == "venta" ? "parte compradora" : contacto.map { TextosContacto.rol($0.tipo).lowercased() }
                    parte(n, [rol, contacto?.etiquetas?.first?.lowercased()].compactMap { $0 }.joined(separator: " · "), primera: true,
                          abrir: o.contactoId) {
                        if let c = o.contactoId {
                            Button { Task { await Contactos.abrirChat(c, estado: estado) } } label: {
                                Image(systemName: "bubble.left.fill").foregroundStyle(C.accion).frame(width: 40, height: 40).background(C.hundida, in: Circle())
                            }
                            .accessibilityLabel("WhatsApp a \(n)")
                        }
                    }
                }
                if let n = o.propietarioNombre {
                    parte(n, TextosContacto.rol("propietario").lowercased(), primera: o.contactoNombre == nil,
                          abrir: o.propietarioId) {
                        if let t = o.propietarioTelefono {
                            Button { Afuera.llamar(t) } label: {
                                Image(systemName: "phone.fill").foregroundStyle(C.accion).frame(width: 40, height: 40).background(C.hundida, in: Circle())
                            }
                            .accessibilityLabel("Llamar a \(n)")
                        }
                    }
                }
                if o.contactoNombre == nil && o.propietarioNombre == nil {
                    Text("Sin partes cargadas todavía.").estilo(.subhead).foregroundStyle(C.texto3).padding(16)
                }
            }
            .tarjeta()
        }
    }

    private func parte<Fin: View>(_ n: String, _ d: String, primera: Bool, abrir: String?, @ViewBuilder fin: () -> Fin) -> some View {
        HStack(spacing: 12) {
            Button { if let abrir { estado.abrir(AFichaContacto(id: abrir)) } } label: {
                HStack(spacing: 12) {
                    AvatarIniciales(nombre: n, tam: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n).estilo(.filaLista).foregroundStyle(C.texto)
                        if !d.isEmpty { Text(d).estilo(.footnote).foregroundStyle(C.texto2) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            fin()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    private func honorarios(_ o: Operacion) -> some View {
        let base = o.valor ?? 0
        let deC = o.honorariosComprador.map { base * $0 / 100 }
        let deV = o.honorariosVendedor.map { base * $0 / 100 }
        let paraAgente = o.comisionAgente.map { ((deC ?? 0) + (deV ?? 0)) * $0 / 100 }
        let m = o.moneda ?? "USD"
        return Button { editarPlata = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("HONORARIOS").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).tracking(0.5).foregroundStyle(C.okTinta)
                if deC != nil || deV != nil {
                    filaPlata("Comprador \(o.honorariosComprador.map { Formato.porcentaje($0) } ?? "—")", deC.map { Formato.plata($0, m) } ?? "—")
                    filaPlata("Vendedor \(o.honorariosVendedor.map { Formato.porcentaje($0) } ?? "—")", deV.map { Formato.plata($0, m) } ?? "—")
                    if let pa = paraAgente {
                        filaPlata("Para \(o.agenteNombre.map { Charla.primerNombre($0) } ?? "el agente") (\(Formato.porcentaje(o.comisionAgente ?? 0)))", Formato.plata(pa, m), fuerte: true)
                    }
                } else {
                    Text("Cargá los porcentajes para ver cuánto queda").estilo(.subhead).foregroundStyle(C.texto2)
                }
                if let s = o.sena { filaPlata("Seña", Formato.plata(s, o.senaMoneda ?? m)) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(C.okFondo, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(Presionable())
        .disabled(!puedeMover)
    }

    private func filaPlata(_ l: String, _ v: String, fuerte: Bool = false) -> some View {
        HStack {
            Text(l).fontWeight(fuerte ? .bold : .regular)
            Spacer()
            Text(v).fontWeight(.bold)
        }
        .estilo(.body16).foregroundStyle(C.texto)
    }

    private func adjuntosVista(_ o: Operacion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Adjuntos · \(adjuntos.count)")
            VStack(spacing: 0) {
                ForEach(Array(adjuntos.enumerated()), id: \.element.id) { i, a in
                    HStack {
                        Button { Task { await abrir(a) } } label: {
                            Label(a.nombre ?? "Documento", systemImage: "doc.text").estilo(.body16).foregroundStyle(C.texto)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        if puedeMover {
                            Button { Task { await quitar(a) } } label: { Image(systemName: "trash").foregroundStyle(C.error) }.accessibilityLabel("Quitar \(a.nombre ?? "el adjunto")")
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
                if puedeMover {
                    Menu {
                        Button { fotos = true } label: { Label("Una foto", systemImage: "photo") }
                        Button { archivos = true } label: { Label("Un archivo (PDF)", systemImage: "doc") }
                    } label: {
                        Label(subiendo ? "Subiendo…" : "Subir: reserva firmada, DNI, informes", systemImage: "paperclip").estilo(.subheadFuerte).foregroundStyle(C.accion)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .disabled(subiendo)
                    .overlay(alignment: .top) { if !adjuntos.isEmpty { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    private var historialVista: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Historial")
            VStack(alignment: .leading, spacing: 10) {
                if puedeMover {
                    HStack {
                        TextField("Comentá algo para el equipo…", text: $comentario, axis: .vertical).estilo(.body16)
                        if !comentario.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Comentar") { Task { await comentar() } }.buttonStyle(BotonTonal())
                        }
                    }
                }
                ForEach(historial) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(FichaContacto.diaMes(n.creadoEn)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3).frame(width: 40, alignment: .leading)
                        Text(n.frase(nombres: nombres)).estilo(.subhead).foregroundStyle(n.tipo == "nota" ? C.texto : C.texto2)
                    }
                }
                if historial.isEmpty { Text("Todavía no pasó nada.").estilo(.texto14).foregroundStyle(C.texto3) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).tarjeta()
        }
    }

    // MARK: Datos

    private func cargar() async {
        do {
            o = try await estado.api.get("/v1/operaciones/\(id)")
            error = nil
        } catch let e as ErrorApi { if o == nil { error = e }; return } catch { return }
        historial = ((try? await estado.api.get("/v1/operaciones/\(id)/historial")) ?? [EventoOperacion]()).sorted { $0.creadoEn > $1.creadoEn }
        var l: [Archivo] = []
        for a in o?.adjuntos ?? [] { if let x: Archivo = try? await estado.api.get("/v1/archivos/\(a)") { l.append(x) } }
        adjuntos = l
        let citas: [Cita] = (try? await estado.api.get("/v1/agenda", query: [.init(name: "operacion", value: id), .init(name: "rango", value: "todas"), .init(name: "limite", value: "50")])) ?? []
        visitas = citas.filter { $0.tipo == "visita" && $0.estado != "cancelada" }.count
        proxima = citas.filter { $0.estado == "pendiente" && $0.empiezaEn > Date() }.min { $0.empiezaEn < $1.empiezaEn }
        if let c = o?.contactoId { contacto = try? await estado.api.get("/v1/contactos/\(c)") }
        if equipo.isEmpty { equipo = (try? await estado.api.get("/v1/equipo")) ?? [] }
    }

    private func aEtapa(_ i: Int) async {
        guard let o, puedeMover, o.caidaEn == nil, i != Operacion.columna(o.etapa) else { return }
        let destino = Operacion.columnas[i]
        let antes = o.etapa
        struct Cuerpo: Encodable { var etapa: String; var desde: String? }
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/mover", Cuerpo(etapa: destino.clave, desde: antes))
            Haptico.impacto()
            if destino.clave == "cierre" && o.propiedadOperacion == "alquiler" {
                estado.sugerir("Llegó al cierre: armá el contrato", "Hacer contrato") { haciendoContrato = true }
            } else {
                estado.avisar("\(o.nombre) pasó a \(destino.texto)") {
                    Task {
                        do {
                            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/mover", Cuerpo(etapa: antes, desde: nil))
                            estado.avisar("Listo, volvió a su etapa")
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            }
            estado.version += 1
        } catch {
            estado.avisar(error)
            await cargar()
        }
    }

    private func marcar(_ p: Operacion.Paso) async {
        guard !p.auto else { return }
        struct Cuerpo: Encodable { var paso: String; var hecho: Bool }
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/checklist", Cuerpo(paso: p.clave, hecho: !p.hecho))
            Haptico.impacto()
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func comentar() async {
        struct Cuerpo: Encodable { var texto: String }
        let t = comentario.trimmingCharacters(in: .whitespacesAndNewlines)
        comentario = ""
        do {
            try await estado.cola.enviar("POST", "/v1/operaciones/\(id)/notas", Cuerpo(texto: String(t.prefix(2000))), etiqueta: "Comentario en la operación")
            await cargar()
        } catch { comentario = t; estado.avisar(error) }
    }

    private func caer(_ motivo: String) async {
        struct Cuerpo: Encodable { var motivo: String }
        let n = o?.nombre ?? "La operación"
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/caer", Cuerpo(motivo: motivo))
            estado.avisar("\(n) se cayó · \(motivo.lowercased())") { Task { await reabrir() } }
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func reabrir() async {
        do {
            try await estado.api.hacer("POST", "/v1/operaciones/\(id)/reabrir")
            estado.avisar("Volvió al tablero")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func ponerAdjuntos(_ ids: [String]) async throws {
        struct Cuerpo: Encodable { var adjuntos: [String] }
        try await estado.api.hacer("PUT", "/v1/operaciones/\(id)/adjuntos", Cuerpo(adjuntos: ids))
    }

    private func subir(_ d: Data, nombre: String, tipo: String) async {
        subiendo = true
        defer { subiendo = false }
        do {
            let a = try await estado.api.subir(d, nombre: nombre, tipo: tipo, uso: "adjunto")
            try await ponerAdjuntos((o?.adjuntos ?? []) + [a.id])
            estado.avisar("Adjunto subido")
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    private func subirArchivo(_ u: URL) async {
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        do {
            let d = try Data(contentsOf: u)
            await subir(d, nombre: u.lastPathComponent, tipo: UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
        } catch { estado.avisar("No se pudo subir", ok: false) }
    }

    private func quitar(_ a: Archivo) async {
        let antes = o?.adjuntos ?? []
        do {
            try await ponerAdjuntos(antes.filter { $0 != a.id })
            estado.avisar("Adjunto quitado") {
                Task {
                    do {
                        try await ponerAdjuntos(antes)
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
            estado.version += 1
        } catch { estado.avisar(error) }
    }

    /// Lo baja con la sesión de la app y lo muestra con la vista previa.
    private func abrir(_ a: Archivo) async {
        do {
            let u = try await ArchivosSesion.archivo(a.id, nombre: a.nombre?.nonEmpty ?? "documento-\(a.id)", api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }
}

/// «Seña y honorarios»: la seña, hasta cuándo vale la reserva (si no, 7 días) y los porcentajes.
struct PlataOperacion: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var o: Operacion
    var agente: String?
    @State private var sena = ""
    @State private var conVence = false
    @State private var vence = Date()
    @State private var hc = ""
    @State private var hv = ""
    @State private var ca = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Seña (\(o.moneda ?? "USD"))", text: $sena).keyboardType(.numberPad)
                    Toggle("La reserva vence", isOn: $conVence)
                    if conVence { DatePicker("Vence el", selection: $vence, displayedComponents: .date) }
                } footer: { if !conVence { Text("Si no la ponés, en 7 días") } }
                Section("Honorarios") {
                    TextField("Comprador (%)", text: $hc).keyboardType(.decimalPad)
                    TextField("Vendedor (%)", text: $hv).keyboardType(.decimalPad)
                    TextField("Para \(agente ?? "el agente") (% de los honorarios)", text: $ca).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Seña y honorarios").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await guardar() } }.disabled(guardando) }
            }
        }
        .onAppear {
            sena = o.sena.map { Formato.numero(Int($0)) } ?? ""
            hc = o.honorariosComprador.map { Formato.porcentaje($0).replacingOccurrences(of: "\(Formato.fino)%", with: "") } ?? ""
            hv = o.honorariosVendedor.map { Formato.porcentaje($0).replacingOccurrences(of: "\(Formato.fino)%", with: "") } ?? ""
            ca = o.comisionAgente.map { Formato.porcentaje($0).replacingOccurrences(of: "\(Formato.fino)%", with: "") } ?? ""
            if let v = o.senaVenceEl, let f = Fecha.dia(v) { vence = f; conVence = true }
        }
    }

    private func numero(_ s: String) -> JSONLibre {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let n = Double(t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }) else { return .nulo }
        return .numero(n)
    }

    private func porcentaje(_ s: String) -> JSONLibre {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let n = Double(t.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }) else { return .nulo }
        return .numero(n)
    }

    private func guardar() async {
        var cuerpo: [String: JSONLibre] = ["honorariosComprador": porcentaje(hc), "honorariosVendedor": porcentaje(hv), "comisionAgente": porcentaje(ca)]
        let s = numero(sena)
        cuerpo["sena"] = s
        if case .numero = s { cuerpo["senaMoneda"] = .texto(o.senaMoneda ?? o.moneda ?? "USD") }
        // La fecha va sólo si la tocaron (o si sacan la seña): si no, al cargarla la API pone 7 días.
        let antes = o.senaVenceEl
        let ahora = conVence ? Formato.diaISO(vence) : nil
        if s == .nulo || ahora != antes { cuerpo["senaVenceEl"] = ahora.map { .texto($0) } ?? .nulo }
        guardando = true
        defer { guardando = false }
        do {
            try await estado.api.hacer("PATCH", "/v1/operaciones/\(o.id)", JSONLibre.objeto(cuerpo))
            estado.avisar("Guardado")
            estado.version += 1
            cerrar()
        } catch { estado.avisar(error) }
    }
}
