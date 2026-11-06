import SwiftUI

/// Un movimiento del historial (GET /v1/actividad?entidad=propiedad&entidadId=).
struct RegistroActividad: Codable, Identifiable, Hashable {
    var id: Int
    var actorNombre: String?
    var accion: String
    var creadoEn: Date?

    static let acciones = ["crear": "La cargó", "editar": "Editó la ficha", "duplicar": "La duplicó", "soltar": "La dejó libre",
                           "borrar": "La mandó a la papelera", "restaurar": "La sacó de la papelera", "enviar_ficha": "Mandó la ficha"]
}

/// Una persona de la pestaña Interesados: de una operación abierta, con lo que pasa con ella.
struct PersonaFicha: Identifiable {
    var id: String
    var nombre: String
    var detalle: String
    var tono: Tono
    var responder: Bool
    var contactoId: String?
}

/// 3D Ficha de una propiedad (web 02 · 9E/9C): las fotos, el estado, el precio y lo que pasó con él,
/// los datos, dónde está publicada (con arreglar el error de un portal), las vistas por día, la gente
/// (interesados, visitas, reservas, documentos, historial), el propietario y la barra al pulgar.
/// Cada parte que no llega queda vacía: la ficha no se cae entera.
struct FichaPropiedad: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var id: String
    /// Abrir con la hoja de «Arreglar» del portal con error.
    var arreglarAlAbrir = false
    /// Abrir con la hoja de compartir (y, con `compartirCon`, esa persona arriba).
    var compartirAlAbrir = false
    var compartirCon: String? = nil

    @State private var p: Propiedad?
    @State private var senal: Senal?
    @State private var pubs: [PublicacionPortal] = []
    @State private var vistas: VistasPropiedad.Respuesta?
    @State private var interesados: [Interesado] = []
    @State private var operaciones: [Operacion] = []
    @State private var citas: [Cita] = []
    @State private var reservas: [ReservaAPI] = []
    @State private var historial: [RegistroActividad] = []
    @State private var propietario: Contacto?
    @State private var destinatario: Contacto?
    @State private var contratos: [ContratoAPI] = []
    @State private var documentos = 0
    @State private var web: String?
    @State private var error: ErrorApi?
    @State private var compartir = false
    @State private var agendar = false
    @State private var reservar = false
    @State private var arreglando: PublicacionPortal?
    @State private var portalEnUso: String?
    @State private var pestana = "interesados"
    @State private var todos = false
    @State private var cambiarEstado = false
    @State private var previo: ArchivoPrevio?
    @State private var yaAbrio = false
    @State private var fotoActual = 0

    private var lector: Bool { !estado.escribe }
    private var link: String { "\(web ?? "")/propiedades/\(p?.slug ?? id)" }

    var body: some View {
        Group {
            if let p { contenido(p) } else if let error {
                EstadoError(que: "la propiedad", error: error) { Task { await cargar() } }.frame(maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(FondoApp())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $compartir) {
            if let p {
                HojaCompartir(propiedad: p, web: web, interesados: buscan, destinatario: destinatario).presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $agendar) { if let p { NuevaCita(propiedad: p).presentationDetents([.large]) } }
        .sheet(isPresented: $reservar) {
            if let p {
                NuevaReservaVenta(propiedadId: p.id, titulo: (p.direccion ?? p.nombre).components(separatedBy: ",").first ?? p.nombre, moneda: p.moneda ?? "USD") { r in
                    estado.abrir(AReserva(id: r.id))
                }
            }
        }
        .sheet(item: $arreglando) { x in
            if let p { HojaArreglar(propiedad: p, pub: x, otros: otrosPortales(x.portal)).hojaTLW([.medium, .large]) }
        }
        .vistaPrevia($previo)
        .userActivity("ar.com.corredor.app.propiedad", isActive: p != nil) { a in
            a.title = p?.nombre
            a.userInfo = ["id": id]
            a.isEligibleForSearch = true
            a.isEligibleForPrediction = true
        }
    }

    // MARK: Contenido

    private func contenido(_ p: Propiedad) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                heroe(p)
                VStack(alignment: .leading, spacing: 18) {
                    cabeza(p)
                    if let v = proximaVisita { tarjetaVisita(v, p) }
                    if !datos(p).isEmpty { cuatroDatos(p) }
                    if !(p.comodidades ?? []).isEmpty { comodidades(p) }
                    if let d = p.descripcion?.nonEmpty { Text(d).estilo(.body16).foregroundStyle(C.texto).lineLimit(8) }
                    if !contratos.isEmpty { negocio }
                    publicada(p)
                    vistasPorDia(p)
                    if lector {
                        HStack(alignment: .top, spacing: 12) {
                            IconoTono(icono: "lock", tono: .neutro)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tu rol es Lector").estilo(.subheadFuerte).foregroundStyle(C.texto)
                                Text(Formato.sinViudas("Podés verla y compartirla, pero el precio y el estado los cambia el agente o la dueña."))
                                    .estilo(.footnote).foregroundStyle(C.texto2)
                            }
                        }
                        .padding(14).tarjeta()
                    }
                    gente(p)
                    tarjetaPropietario(p)
                    if estado.escribe { acciones(p) }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 120)
                .background(FondoApp().clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)))
                .padding(.top, -22)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { botonesArriba(p) }
        .overlay(alignment: .bottom) { barra(p) }
        .refreshable { await cargar() }
    }

    @ViewBuilder
    private func heroe(_ p: Propiedad) -> some View {
        let fotos = p.fotosUrl ?? []
        if fotos.isEmpty {
            Button { if estado.escribe { estado.abrir(AEditarEnPaso(id: p.id, paso: "fotos")) } } label: {
                VStack(spacing: 8) {
                    Image(systemName: "camera.badge.plus").font(.system(size: 34))
                    Text("Sumá fotos").estilo(.subheadFuerte)
                    Text("Sin fotos no sale en los portales").estilo(.footnote).foregroundStyle(C.texto2)
                }
                .foregroundStyle(C.accion).frame(maxWidth: .infinity).frame(height: 300).background(C.hundida)
            }
            .buttonStyle(Presionable())
        } else {
            TabView(selection: $fotoActual) {
                ForEach(Array(fotos.enumerated()), id: \.offset) { i, f in
                    Button { estado.abrir(AGaleria(id: p.id, indice: i)) } label: { Foto(url: URL(string: f)) }
                        .buttonStyle(Presionable()).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: fotos.count > 1 ? .automatic : .never))
            .frame(height: 380)
            .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                            .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.35), location: 1)],
                                    startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
            .overlay(alignment: .bottomTrailing) {
                Label("\(fotoActual + 1) / \(fotos.count)", systemImage: "photo.on.rectangle").font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font)
                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 26)
                    .background(.black.opacity(0.55), in: Capsule()).padding(.trailing, 16).padding(.bottom, 34)
            }
            .accessibilityLabel("Ver las fotos")
        }
    }

    private func cabeza(_ p: Propiedad) -> some View {
        let (est, tono) = Cartera.estado(p)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(est).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                    .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                Text("\(p.operacion == "temporario" ? "Temporario" : Formato.mayuscula(p.operacionTexto)) · \(p.tipoTexto)").estilo(.footnote).foregroundStyle(C.texto2)
            }
            if let a = Cartera.atencion(p, senal), a.1 != .neutro {
                Text(a.0).estilo(.footnoteFuerte).foregroundStyle(a.1.tinta)
            }
            Text(p.direccion ?? p.nombre).estilo(.titulo3).foregroundStyle(C.texto)
            if let l = lugar(p).nonEmpty { Text(l).estilo(.subhead).foregroundStyle(C.texto2) }
            Text(p.precioTexto).font(Estilo(tamano: 30, peso: .extrabold, tracking: -0.03, relativo: .title).font).foregroundStyle(C.texto)
            if let e = p.expensas, e > 0 { Text("expensas \(Formato.plata(e, "ARS"))").estilo(.footnote).foregroundStyle(C.texto2) }
            if let l = lineaPrecio(p) { Text(l).estilo(.footnoteFuerte).foregroundStyle(C.okTinta) }
            Text(cargada(p)).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
        }
    }

    private func lugar(_ p: Propiedad) -> String {
        [p.barrio, p.ciudad.flatMap { $0 != p.barrio && $0 != "CABA" ? $0 : nil }].compactMap { $0 }.joined(separator: " · ")
    }

    /// «bajó de 180.000 hace 3 días».
    private func lineaPrecio(_ p: Propiedad) -> String? {
        guard let antes = senal?.precioAnterior, let ahora = p.precio, let f = senal?.precioCambio, antes != ahora else { return nil }
        return "\(antes > ahora ? "bajó" : "subió") de \(Formato.numero(Int(antes))) \(Formato.hace(f))"
    }

    /// «LP-0412 · cargada por Ana el 12/10».
    private func cargada(_ p: Propiedad) -> String {
        let fecha = p.creadaEn.map { f -> String in
            let c = Formato.calendario.dateComponents([.day, .month], from: f)
            return String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
        } ?? ""
        let por = senal?.cargadaPor.map { "por \($0.components(separatedBy: " ").first ?? $0) " } ?? ""
        return [senal?.codigo, "cargada \(por)el \(fecha)"].compactMap { $0 }.joined(separator: " · ")
    }

    private var visitasProp: [Cita] { citas.filter { $0.tipo == "visita" && $0.estado != "cancelada" } }
    private var abiertas: [Operacion] { operaciones.filter { $0.etapa != "cierre" } }
    private var proximaVisita: Cita? {
        visitasProp.filter { $0.estado == "pendiente" && $0.empiezaEn > Date().addingTimeInterval(-7200) }.sorted { $0.empiezaEn < $1.empiezaEn }.first
    }

    private func tarjetaVisita(_ v: Cita, _ p: Propiedad) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(C.avisoTinta)
            VStack(alignment: .leading, spacing: 1) {
                Text("Visita \(Senal.cuando(v.empiezaEn))").estilo(.subheadFuerte).foregroundStyle(C.texto)
                Text(v.contactoNombre ?? v.titulo ?? "").estilo(.footnote).foregroundStyle(C.texto2)
            }
            Spacer()
            Button("Confirmar") { Task { await confirmarVisita(v, p) } }.buttonStyle(BotonTonal())
        }
        .padding(14).background(C.avisoFondo, in: .rect(cornerRadius: M.rTarjeta, style: .continuous))
    }

    private func confirmarVisita(_ v: Cita, _ p: Propiedad) async {
        var tel: String?
        if let c = v.contactoId { tel = (try? await estado.api.get("/v1/contactos/\(c)") as Contacto)?.telefono }
        Afuera.whatsapp(tel, texto: "Te confirmo la visita \(Senal.cuando(v.empiezaEn)) en \(p.direccion ?? p.nombre).")
    }

    /// Los cuatro datos con su detalle: «3 amb. · 2 dormitorios», «120 m² · 95 cubiertos», «2 baños · 1 cochera», «A estrenar · al frente».
    private func datos(_ p: Propiedad) -> [(String, String, String)] {
        var d: [(String, String, String)] = []
        if let a = p.ambientes, a > 0 { d.append(("door.left.hand.open", "\(a) amb.", p.dormitorios.map { Formato.cantidad($0, "dormitorio", "dormitorios") } ?? "")) }
        if let s = p.superficie ?? p.cubierta {
            let det = p.superficie != nil && p.cubierta != nil ? "\(Formato.numero(Int(p.cubierta ?? 0))) cubiertos" : p.superficie != nil ? "totales" : "cubiertos"
            d.append(("ruler", "\(Formato.numero(Int(s))) m²", det))
        }
        if let b = p.banos, b > 0 { d.append(("bathtub", Formato.cantidad(b, "baño", "baños"), p.cocheras.map { Formato.cantidad($0, "cochera", "cocheras") } ?? "")) }
        if let a = p.antiguedad {
            let disp = p.ficha?["unidad"]?["disposicion"]?.texto.map { "al \($0)" } ?? ""
            d.append(("calendar", a == 0 ? "A estrenar" : "\(a) \(a == 1 ? "año" : "años")", disp))
        }
        return d
    }

    private func cuatroDatos(_ p: Propiedad) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(datos(p), id: \.1) { icono, valor, detalle in
                HStack(spacing: 10) {
                    Image(systemName: icono).font(.system(size: 19)).foregroundStyle(C.okTinta).frame(width: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(valor).estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1).minimumScaleFactor(0.8)
                        if !detalle.isEmpty { Text(detalle).font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto2).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).frame(minHeight: 58).tarjeta(14)
            }
        }
    }

    private func comodidades(_ p: Propiedad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloBloque(texto: "Comodidades")
                if estado.escribe { Button("Editar") { estado.abrir(AEditarEnPaso(id: p.id, paso: "comodidades")) }.estilo(.subheadFuerte).foregroundStyle(C.accion) }
            }
            ChipsComodidades(textos: p.comodidades ?? [])
        }
    }

    // MARK: Dónde está publicada

    private struct FilaPortal: Identifiable {
        var clave: String
        var nombre: String
        /// ok · err · off · pausa
        var estado: String
        var detalle: String
        var pub: PublicacionPortal?
        var id: String { clave }
    }

    private func portales(_ p: Propiedad) -> [FilaPortal] {
        PortalesCartera.todos.map { pt in
            if pt.clave == "web" {
                return FilaPortal(clave: "web", nombre: pt.nombre, estado: p.publicada == true ? "ok" : "off",
                                  detalle: p.publicada == true ? link.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") : "No publicada")
            }
            guard let x = pubs.first(where: { $0.portal == pt.clave }), x.estado != "finalizada", x.estado != "pendiente" else {
                return FilaPortal(clave: pt.clave, nombre: pt.nombre, estado: "off", detalle: "No publicada", pub: pubs.first { $0.portal == pt.clave })
            }
            if x.estado == "error" { return FilaPortal(clave: pt.clave, nombre: pt.nombre, estado: "err", detalle: "No la publicó · \(x.actualizadoEn.map { Formato.hace($0) } ?? "")", pub: x) }
            if x.estado == "pausada" { return FilaPortal(clave: pt.clave, nombre: pt.nombre, estado: "pausa", detalle: "Pausada", pub: x) }
            let det: String
            if pt.clave == "mercadolibre" {
                let n = senal?.sinResponder ?? 0
                det = "Activa" + (n > 0 ? " · \(Formato.cantidad(n, "pregunta sin responder", "preguntas sin responder"))" : "")
            } else {
                det = "En el feed · actualizada \((x.sincronizadaEn ?? x.actualizadoEn).map { Formato.hace($0) } ?? "")"
            }
            return FilaPortal(clave: pt.clave, nombre: pt.nombre, estado: "ok", detalle: det, pub: x)
        }
    }

    private func otrosPortales(_ portal: String) -> [String] {
        guard let p else { return [] }
        return portales(p).filter { $0.estado == "ok" && $0.clave != portal }.map { $0.clave == "web" ? "tu web" : $0.nombre }
    }

    private var semana: Int {
        let desde = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return (vistas?.dias ?? []).filter { (Fecha.dia($0.dia) ?? .distantPast) > desde }.reduce(0) { $0 + $1.cantidad }
    }

    private func publicada(_ p: Propiedad) -> some View {
        let filas = portales(p)
        return VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Dónde está publicada", cuenta: Formato.cantidad(semana, "vista", "vistas") + " esta semana")
            Text("Publicada en \(filas.filter { $0.estado == "ok" }.count) de 4").estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(filas.enumerated()), id: \.element.id) { i, x in filaPortal(x, p, primera: i == 0) }
            }
            .tarjeta()
        }
    }

    private func filaPortal(_ x: FilaPortal, _ p: Propiedad, primera: Bool) -> some View {
        HStack(spacing: 12) {
            LogoPortal(portal: x.clave).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(x.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                Text(x.detalle).estilo(.footnote).foregroundStyle(x.estado == "err" ? C.errorTinta : C.texto2).lineLimit(2)
            }
            Spacer()
            if portalEnUso == x.clave { ProgressView() } else if !lector {
                switch x.estado {
                case "ok" where x.clave == "web":
                    Button("Copiar link") { UIPasteboard.general.string = link; estado.avisar("Link copiado. Pegalo donde quieras mandarlo.") }.estilo(.footnoteFuerte).foregroundStyle(C.accion)
                case "ok" where x.clave == "mercadolibre" && (senal?.sinResponder ?? 0) > 0:
                    Button("Responder") { estado.abrir(AMercadoLibre()) }.estilo(.footnoteFuerte).foregroundStyle(C.accion)
                case "ok":
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(C.okTinta)
                case "err":
                    Button("Arreglar") { arreglando = x.pub }
                        .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.errorTinta)
                        .padding(.horizontal, 10).frame(height: 30).background(C.errorFondo, in: Capsule())
                default:
                    Button("Publicar") { Task { await publicar(x.clave, p) } }.buttonStyle(BotonTonal(alto: 30))
                }
            } else if x.estado == "ok" {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(C.okTinta)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
        .contentShape(Rectangle())
        .contextMenu {
            if estado.escribe, x.estado == "ok" {
                if x.clave == "web" {
                    Button { Task { await despublicarWeb(p) } } label: { Label("Despublicar de tu web", systemImage: "eye.slash") }
                } else {
                    Button { Task { await pausar(x.clave) } } label: { Label("Pausar en \(x.nombre)", systemImage: "pause.circle") }
                    Button(role: .destructive) { Task { await sacarDe(x.clave) } } label: { Label("Sacar de \(x.nombre)", systemImage: "xmark.circle") }
                }
            }
            if let u = x.pub?.url.flatMap(URL.init(string:)) { Link(destination: u) { Label("Ver el aviso", systemImage: "safari") } }
        }
    }

    // MARK: Vistas por día

    /// Las últimas dos semanas (13 días), con la marca del cambio de precio.
    private var barras: (dias: [(String, Int)], max: Int, corte: Int) {
        let por = Dictionary((vistas?.dias ?? []).map { ($0.dia, $0.cantidad) }, uniquingKeysWith: +)
        var dias: [(String, Int)] = []
        for i in stride(from: 12, through: 0, by: -1) {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let k = Formato.diaISO(d)
            dias.append((k, por[k] ?? 0))
        }
        let corte = senal?.precioCambio.map { Formato.diaISO($0) }
        let i = corte.flatMap { c in dias.firstIndex { $0.0 >= c } } ?? -1
        return (dias, max(1, dias.map(\.1).max() ?? 1), p.flatMap { lineaPrecio($0) } != nil ? i : -1)
    }

    private var subaVistas: Int? {
        let b = barras
        guard b.corte > 0 else { return nil }
        let antes = b.dias[..<b.corte], despues = b.dias[b.corte...]
        let a = Double(antes.reduce(0) { $0 + $1.1 }) / Double(antes.count)
        let d = Double(despues.reduce(0) { $0 + $1.1 }) / Double(despues.count)
        return a > 0 && d > a ? Int(((d - a) / a * 100).rounded()) : nil
    }

    private func vistasPorDia(_ p: Propiedad) -> some View {
        let b = barras
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloBloque(texto: "Vistas por día")
                if let s = subaVistas { Text("+\(s)\(Formato.fino)% desde que bajó el precio").estilo(.footnoteFuerte).foregroundStyle(C.okTinta) }
            }
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(b.dias.enumerated()), id: \.offset) { i, d in
                        if i == b.corte, i > 0 { Rectangle().fill(C.oro).frame(width: 2, height: 90) }
                        RoundedRectangle(cornerRadius: 3).fill(b.corte > 0 && i >= b.corte ? C.okTinta : C.accion.opacity(0.55))
                            .frame(maxWidth: .infinity).frame(height: max(4, CGFloat(d.1) / CGFloat(b.max) * 90))
                    }
                }
                .frame(height: 90, alignment: .bottom)
                .accessibilityElement().accessibilityLabel("Vistas en la web de los últimos 13 días: \(Formato.cantidad(b.dias.reduce(0) { $0 + $1.1 }, "vista", "vistas"))")
                HStack {
                    Text("hace 2 semanas")
                    Spacer()
                    if b.corte > 0, let l = lineaPrecio(p) { Text(l.hasPrefix("bajó") ? "bajó a \(p.precioTexto)" : "subió a \(p.precioTexto)").foregroundStyle(C.avisoTinta); Spacer() }
                    Text("hoy")
                }
                .font(Estilo(tamano: 12, peso: .regular, relativo: .caption).font).foregroundStyle(C.texto3)
            }
            .padding(14).tarjeta()
            Button("Ver las vistas de 90 días") { estado.abrir(ASeccion(clave: "vistas", id: p.id)) }.estilo(.footnoteFuerte).foregroundStyle(C.accion).padding(.horizontal, 4)
        }
    }

    // MARK: La gente

    private var personas: [PersonaFicha] {
        var out: [PersonaFicha] = []
        let ahora = Date()
        for o in abiertas {
            let c = visitasProp.first { $0.contactoId != nil && $0.contactoId == o.contactoId }
            let nombre = o.contactoNombre ?? o.titulo ?? "Interesado"
            if let c, c.estado == "pendiente", c.empiezaEn > ahora.addingTimeInterval(-7200) {
                out.append(PersonaFicha(id: o.id, nombre: nombre, detalle: "Visita \(Senal.cuando(c.empiezaEn))", tono: .oro, responder: false, contactoId: o.contactoId))
            } else if let c, c.estado == "hecha" {
                out.append(PersonaFicha(id: o.id, nombre: nombre, detalle: "Visitó el \(ReservaAPI.corta(Formato.diaISO(c.empiezaEn)))\(c.notas.map { " · «\($0)»" } ?? "")", tono: .neutro, responder: false, contactoId: o.contactoId))
            } else if o.etapa == "nuevo" {
                out.append(PersonaFicha(id: o.id, nombre: nombre, detalle: "Escribió \(o.creadaEn.map { Formato.hace($0) } ?? "") · sin responder", tono: .rojo, responder: true, contactoId: o.contactoId))
            } else {
                out.append(PersonaFicha(id: o.id, nombre: nombre, detalle: "Última novedad \(o.actualizadoEn.map { Formato.hace($0) } ?? "")", tono: .neutro, responder: false, contactoId: o.contactoId))
            }
        }
        let orden: (Tono) -> Int = { $0 == .oro ? 0 : $0 == .rojo ? 1 : 3 }
        return out.sorted { orden($0.tono) < orden($1.tono) }
    }

    /// Los que buscan algo así y no tienen una operación con esta propiedad.
    private var buscan: [Interesado] { interesados.filter { i in !abiertas.contains { $0.contactoId == i.contactoId } } }

    private func resumenBusca(_ p: Propiedad) -> String {
        [p.barrio, p.ambientes.map { "\($0) amb" }, p.precio.map { "hasta \(Formato.plata((($0 * 1.05) / 1000).rounded(.up) * 1000, p.moneda ?? "USD"))" }]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private func gente(_ p: Propiedad) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipFiltro(texto: "Interesados\(abiertas.isEmpty ? "" : " \(abiertas.count)")", activo: pestana == "interesados") { pestana = "interesados" }
                    ChipFiltro(texto: "Visitas\(visitasProp.isEmpty ? "" : " \(visitasProp.count)")", activo: pestana == "visitas") { pestana = "visitas" }
                    ChipFiltro(texto: "Reservas\(reservas.isEmpty ? "" : " \(reservas.count)")", activo: pestana == "reservas") { pestana = "reservas" }
                    ChipFiltro(texto: "Docs\(documentos == 0 ? "" : " \(documentos)")", activo: pestana == "docs") { pestana = "docs" }
                    ChipFiltro(texto: "Historial", activo: pestana == "historial") { pestana = "historial" }
                }
            }
            VStack(spacing: 0) { pestanaGente(p) }.tarjeta()
        }
    }

    @ViewBuilder
    private func pestanaGente(_ p: Propiedad) -> some View {
        switch pestana {
        case "visitas":
            if visitasProp.isEmpty {
                vacia("Sin visitas todavía.", accion: estado.escribe ? ("Agendá la primera", { agendar = true }) : nil)
            } else {
                ForEach(Array(visitasProp.enumerated()), id: \.element.id) { i, c in
                    filaPersona(c.contactoNombre ?? c.titulo ?? "Visita",
                                "\(c.estado == "hecha" ? "Visitó" : "Visita") \(Senal.cuando(c.empiezaEn))\(c.notas.map { " · «\($0)»" } ?? "")", .neutro, primera: i == 0) {
                        estado.abrir(ACita(id: c.id))
                    }
                }
            }
        case "reservas":
            if reservas.isEmpty {
                vacia("Sin reservas.", accion: estado.escribe ? ("Reservar", { reservar = true }) : nil)
            } else {
                ForEach(Array(reservas.enumerated()), id: \.element.id) { i, r in
                    Button { estado.abrir(AReserva(id: r.id)) } label: { FilaReserva(r: r) }.buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
        case "docs":
            filaPersona("Documentos", documentos == 0 ? "Autorización, escritura, planos" : Formato.cantidad(documentos, "documento", "documentos"), .neutro, primera: true) {
                estado.abrir(ASeccion(clave: "documentos-propiedad", id: p.id))
            }
        case "historial":
            if historial.isEmpty { vacia("Sin movimientos todavía.") } else {
                ForEach(Array(historial.enumerated()), id: \.element.id) { i, h in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RegistroActividad.acciones[h.accion] ?? h.accion).estilo(.filaLista).foregroundStyle(C.texto)
                        Text("\(h.actorNombre ?? "Corredor") · \(h.creadoEn.map { Formato.hace($0) } ?? "")").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
        default:
            let ps = personas
            if ps.isEmpty { vacia("Todavía nadie preguntó. Las consultas aparecen acá.") }
            ForEach(Array((todos ? ps : Array(ps.prefix(3))).enumerated()), id: \.element.id) { i, x in
                HStack(spacing: 12) {
                    AvatarIniciales(nombre: x.nombre, tam: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                        Text(x.detalle).font(Estilo(tamano: 13, peso: x.tono == .neutro ? .regular : .semibold, relativo: .footnote).font)
                            .foregroundStyle(x.tono == .neutro ? C.texto2 : x.tono.tinta).lineLimit(2)
                    }
                    Spacer()
                    if x.responder {
                        Button("Responder") { abrirPersona(x) }.buttonStyle(BotonTonal(alto: 30))
                    } else {
                        Button { abrirPersona(x) } label: { Image(systemName: "bubble.left").frame(width: 36, height: 36).background(C.hundida, in: .rect(cornerRadius: 10)) }
                            .accessibilityLabel("Escribirle a \(x.nombre)")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
            }
            if !buscan.isEmpty {
                HStack(spacing: 12) {
                    IconoTono(icono: "sparkles", tono: .violeta, tam: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Formato.cantidad(buscan.count, "contacto busca algo así", "contactos buscan algo así")).estilo(.filaLista).foregroundStyle(C.texto)
                        Text(resumenBusca(p)).estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer()
                    Button("Mandarles") { compartir = true }.buttonStyle(BotonTonal(alto: 30))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
            if ps.count > 3 {
                Button(todos ? "Ver menos" : "Ver los \(ps.count)") { todos.toggle() }
                    .estilo(.subheadFuerte).foregroundStyle(C.accion).frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
            }
        }
    }

    private func abrirPersona(_ x: PersonaFicha) {
        if let c = x.contactoId { estado.abrir(AFichaContacto(id: c)) } else { estado.abrir(AFichaOperacion(id: x.id)) }
    }

    private func vacia(_ t: String, accion: (String, () -> Void)? = nil) -> some View {
        HStack(spacing: 4) {
            Text(t).estilo(.footnote).foregroundStyle(C.texto2)
            if let accion { Button(accion.0, action: accion.1).estilo(.footnoteFuerte).foregroundStyle(C.accion) }
            Spacer()
        }
        .padding(14)
    }

    private func filaPersona(_ t: String, _ d: String, _ tono: Tono, primera: Bool, _ ir: @escaping () -> Void) -> some View {
        Button(action: ir) {
            HStack(spacing: 12) {
                AvatarIniciales(nombre: t, tam: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                    Text(d).estilo(.footnote).foregroundStyle(tono == .neutro ? C.texto2 : tono.tinta).lineLimit(2)
                }
                Spacer()
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Propietario

    private var resumenSemana: String {
        let visitasSemana = visitasProp.filter { let d = diasCalendario($0.empiezaEn, Date()); return d >= 0 && d <= 7 }.count
        return "\(Formato.cantidad(semana, "vista", "vistas")), \(Formato.cantidad(visitasSemana, "visita", "visitas")), \(Formato.cantidad(abiertas.count, "consulta", "consultas"))"
    }

    private func tarjetaPropietario(_ p: Propiedad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Propietario")
            VStack(alignment: .leading, spacing: 0) {
                if let d = propietario {
                    HStack(spacing: 12) {
                        AvatarIniciales(nombre: d.nombre, tam: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                            Text(d.telefono ?? d.email ?? "Sin teléfono cargado").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        Button { if d.telefono != nil { Afuera.whatsapp(d.telefono) } else { estado.abrir(AFichaContacto(id: d.id)) } } label: {
                            Image(systemName: "bubble.left").frame(width: 36, height: 36).background(C.hundida, in: .rect(cornerRadius: 10))
                        }
                        .accessibilityLabel("Escribirle a \(d.nombre)")
                    }
                    .padding(14)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").foregroundStyle(C.azulTinta)
                        Text("Mandale el resumen de la semana: \(resumenSemana).").estilo(.footnote).foregroundStyle(C.texto)
                        Spacer(minLength: 4)
                        Button("Mandar") {
                            Afuera.whatsapp(d.telefono, texto: "Hola \(d.nombre.components(separatedBy: " ").first ?? d.nombre), te paso cómo vino \(p.direccion ?? p.nombre) esta semana: \(resumenSemana). \(link)")
                        }
                        .estilo(.footnoteFuerte).foregroundStyle(C.azulTinta)
                    }
                    .padding(12).background(C.azulFondo, in: .rect(cornerRadius: 12)).padding([.horizontal, .bottom], 10)
                } else {
                    HStack(spacing: 4) {
                        Text("Sin propietario cargado.").estilo(.footnote).foregroundStyle(C.texto2)
                        if estado.escribe { Button("Sumalo desde la ficha") { estado.abrir(AAltaPropiedad(editar: p.id)) }.estilo(.footnoteFuerte).foregroundStyle(C.accion) }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .tarjeta()
        }
    }

    // MARK: Arriba y abajo

    private func botonesArriba(_ p: Propiedad) -> some View {
        HStack(spacing: 8) {
            circulo("chevron.left", "Volver") { cerrar() }
            Spacer()
            if estado.escribe {
                circulo("pencil", "Editar") { estado.abrir(AAltaPropiedad(editar: p.id)) }
                circulo(p.destacada == true ? "pin.fill" : "pin", p.destacada == true ? "Desfijar" : "Fijar en el lateral") { fijar(p) }
            }
            circulo("square.and.arrow.up", "Compartir") { compartir = true }
            Menu {
                if estado.escribe {
                    Button { estado.abrir(AAltaPropiedad(editar: p.id)) } label: { Label("Editar", systemImage: "pencil") }
                    if p.operacion != "temporario" { Button { reservar = true } label: { Label("Reservar", systemImage: "bookmark") } }
                    Button { fijar(p) } label: { Label(p.destacada == true ? "Desfijar" : "Fijar en el lateral", systemImage: "pin") }
                }
                Button { estado.abrir(ASeccion(clave: "actas", id: p.id)) } label: { Label("Inventario y actas", systemImage: "checklist") }
                if let r = senal?.reserva?.id { Button { estado.abrir(AReserva(id: r)) } label: { Label("Reserva", systemImage: "bookmark.fill") } }
                Button { Task { if let u = await FichaImpresa.a4(p, api: estado.api) { previo = ArchivoPrevio(url: u) } } } label: { Label("Ficha para imprimir", systemImage: "printer") }
                Button { estado.abrir(ATarjetaPropiedad(id: p.id)) } label: { Label("Tarjeta para la visita", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                if let b = p.barrio { Button { estado.abrir(ACartera(barrio: b)) } label: { Label("Más en \(b)", systemImage: "mappin.and.ellipse") } }
                if estado.escribe {
                    Button { Task { await duplicar(p) } } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { Task { await borrar(p) } } label: { Label("Mandar a la papelera", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.ultraThinMaterial.opacity(0.9), in: Circle())
                    .background(Color(white: 0.08, opacity: 0.45), in: Circle())
            }
            .accessibilityLabel("Más")
        }
        .padding(.horizontal, 16)
    }

    private func circulo(_ icono: String, _ etiqueta: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: icono).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.ultraThinMaterial.opacity(0.9), in: Circle())
                .background(Color(white: 0.08, opacity: 0.45), in: Circle())
        }
        .accessibilityLabel(etiqueta)
    }

    private func barra(_ p: Propiedad) -> some View {
        HStack(spacing: 8) {
            Button { compartir = true } label: {
                HStack(spacing: 8) {
                    Image("LogoWhatsApp").renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20)
                    Text("Mandar a un interesado").font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).lineLimit(1).minimumScaleFactor(0.85)
                }
                .foregroundStyle(Color(hex: 0x0B3D1F))
                .frame(maxWidth: .infinity, minHeight: 52).background(Color(hex: 0x25D366), in: .rect(cornerRadius: 14, style: .continuous))
            }
            if estado.escribe { cuadrado("calendar", "Agendar visita") { agendar = true } }
            if let t = propietario?.telefono { cuadrado("phone", "Llamar al propietario") { Afuera.llamar(t) } }
            if estado.escribe { cuadrado("camera", "Sumar fotos") { estado.abrir(AEditarEnPaso(id: p.id, paso: "fotos")) } }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    private func cuadrado(_ icono: String, _ etiqueta: String, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            Image(systemName: icono).font(.system(size: 19, weight: .semibold)).foregroundStyle(C.texto)
                .frame(width: 52, height: 52).background(C.hundida, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(etiqueta)
    }

    // MARK: Más

    @ViewBuilder
    private func acciones(_ p: Propiedad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Más")
            VStack(spacing: 0) {
                filaAccion("arrow.triangle.2.circlepath", "Cambiar el estado") { cambiarEstado = true }
                if p.operacion == "temporario" || p.tambienTemporario == true { filaAccion("calendar.badge.clock", "Tarifas y disponibilidad") { estado.abrir(ASeccion(clave: "tarifas", id: p.id)) } }
                filaAccion("paperplane", "A quién se la mandaste") { estado.abrir(ASeccion(clave: "envios", id: p.id)) }
                filaAccion("waveform", "Recorridas dictadas") { estado.abrir(ASeccion(clave: "grabaciones", id: p.id)) }
                filaAccion("plus.square.on.square", "Duplicar") { Task { await duplicar(p) } }
                filaAccion("trash", "Mandar a la papelera", rojo: true) { Task { await borrar(p) } }
            }
            .tarjeta()
        }
        .confirmationDialog("Estado de la propiedad", isPresented: $cambiarEstado) {
            ForEach(Propiedad.estados, id: \.0) { k, n in
                Button(n) { Task { await ponerEstado(p, k) } }
            }
        }
    }

    private func filaAccion(_ icono: String, _ texto: String, rojo: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 19)).foregroundStyle(rojo ? C.error : C.accion).frame(width: 24)
                Text(texto).estilo(.body16).foregroundStyle(rojo ? C.error : C.texto)
                Spacer()
                if !rojo { Chevron() }
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { Rectangle().fill(C.linea).frame(height: 0.5) }
    }

    /// Su contrato vigente, para no tener que buscarlo en otra pestaña.
    private var negocio: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Contrato")
            VStack(spacing: 0) {
                ForEach(Array(contratos.enumerated()), id: \.element.id) { i, k in
                    filaPersona("Contrato con \(k.contactoNombre ?? "el inquilino")",
                                [k.monto.map { Formato.plata($0, k.moneda ?? "ARS") }, k.fin.flatMap(Fecha.dia).map { "hasta \(Formato.mesDe($0)) \(String(Calendar.current.component(.year, from: $0)))" }]
                                    .compactMap { $0 }.joined(separator: " · "), .neutro, primera: i == 0) { estado.abrir(AFichaContrato(id: k.id)) }
                }
            }
            .tarjeta()
        }
    }

    // MARK: Cargar y cambiar

    private func cargar() async {
        do {
            let x: Propiedad = try await estado.api.get("/v1/propiedades/\(id)")
            p = x
            error = nil
        } catch let e as ErrorApi { error = e; return } catch { return }
        // El resto no tira la ficha: lo que no llega queda vacío.
        senal = (try? await Senal.de([id], api: estado.api))?[id]
        pubs = (try? await estado.api.get("/v1/propiedades/\(id)/publicaciones")) ?? []
        vistas = try? await estado.api.get("/v1/propiedades/\(id)/vistas")
        interesados = (try? await estado.api.get("/v1/propiedades/\(id)/interesados", query: [.init(name: "sinVisita", value: "si"), .init(name: "limite", value: "20")])) ?? []
        operaciones = (try? await estado.api.get("/v1/operaciones", query: [.init(name: "propiedad", value: id), .init(name: "limite", value: "50")])) ?? []
        citas = (try? await estado.api.get("/v1/agenda", query: [.init(name: "propiedad", value: id), .init(name: "rango", value: "todas"), .init(name: "limite", value: "50")])) ?? []
        reservas = (try? await estado.api.get("/v1/propiedades/\(id)/reservas")) ?? []
        historial = (try? await estado.api.get("/v1/actividad", query: [.init(name: "entidad", value: "propiedad"), .init(name: "entidadId", value: id), .init(name: "limite", value: "20")])) ?? []
        if let pid = p?.propietarioId { propietario = try? await estado.api.get("/v1/contactos/\(pid)") } else { propietario = nil }
        if let c = compartirCon, destinatario == nil { destinatario = try? await estado.api.get("/v1/contactos/\(c)") }
        contratos = ((try? await estado.api.get("/v1/contratos", query: [.init(name: "propiedad", value: id)])) ?? [ContratoAPI]())
            .filter { $0.estado != "rescindido" && $0.estado != "finalizado" }
        if let d: [JSONLibre] = try? await estado.api.get("/v1/documentos", query: [.init(name: "propiedad", value: id)]) { documentos = d.count }
        if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        if !yaAbrio {
            yaAbrio = true
            if compartirAlAbrir { compartir = true }
            if arreglarAlAbrir { arreglando = pubs.first { $0.estado == "error" } }
        }
    }

    /// Fijar o desfijar, con aviso y deshacer.
    private func fijar(_ p: Propiedad) {
        struct Cuerpo: Encodable { var destacada: Bool }
        let nueva = !(p.destacada ?? false)
        self.p?.destacada = nueva
        Haptico.seleccion()
        Task {
            do {
                try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(destacada: nueva), etiqueta: "Fijar \(p.nombre)")
                estado.version += 1
                estado.avisar(nueva ? "Fijada en el lateral" : "Desfijada") {
                    Task {
                        do { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(destacada: !nueva)); estado.version += 1 }
                        catch { estado.avisar(error) }
                    }
                }
            } catch { self.p?.destacada = !nueva; estado.avisar(error) }
        }
    }

    private func ponerEstado(_ p: Propiedad, _ nuevo: String) async {
        struct Cuerpo: Encodable { var estado: String }
        let antes = p.estado ?? "disponible"
        do {
            try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: nuevo), etiqueta: "Estado de \(p.nombre)")
            estado.version += 1
            estado.avisar("Quedó \(Propiedad.estados.first { $0.0 == nuevo }?.1.lowercased() ?? nuevo)") {
                Task {
                    do { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(estado: antes)); estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    /// Publicar en un portal (o en la web), con deshacer: saca la publicación (o la despublica).
    private func publicar(_ portal: String, _ p: Propiedad) async {
        struct Cuerpo: Encodable { var publicada: Bool }
        portalEnUso = portal
        defer { portalEnUso = nil }
        let nombre = PublicacionPortal.nombres[portal] ?? portal
        do {
            if portal == "web" { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: true)) }
            else { try await estado.api.hacer("POST", "/v1/propiedades/\(p.id)/publicaciones/\(portal)") }
            estado.version += 1
            estado.avisar("Publicada en \(nombre)") {
                Task {
                    do {
                        if portal == "web" { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: false)) }
                        else { try await estado.api.hacer("DELETE", "/v1/propiedades/\(p.id)/publicaciones/\(portal)") }
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func despublicarWeb(_ p: Propiedad) async {
        struct Cuerpo: Encodable { var publicada: Bool }
        do {
            try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: false))
            estado.version += 1
            estado.avisar("Despublicada de tu web") {
                Task {
                    do { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: true)); estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func pausar(_ portal: String) async {
        portalEnUso = portal
        defer { portalEnUso = nil }
        do {
            try await estado.api.hacer("POST", "/v1/propiedades/\(id)/publicaciones/\(portal)/pausar")
            estado.version += 1
            estado.avisar("Pausada en \(PublicacionPortal.nombres[portal] ?? portal)") {
                Task {
                    do { try await estado.api.hacer("POST", "/v1/propiedades/\(id)/publicaciones/\(portal)"); estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func sacarDe(_ portal: String) async {
        portalEnUso = portal
        defer { portalEnUso = nil }
        do {
            try await estado.api.hacer("DELETE", "/v1/propiedades/\(id)/publicaciones/\(portal)")
            estado.version += 1
            estado.avisar("Sacada de \(PublicacionPortal.nombres[portal] ?? portal)") {
                Task {
                    do { try await estado.api.hacer("POST", "/v1/propiedades/\(id)/publicaciones/\(portal)"); estado.version += 1 }
                    catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    private func duplicar(_ p: Propiedad) async {
        struct Nueva: Decodable { var id: String }
        do {
            let n: Nueva = try await estado.api.enviar("POST", "/v1/propiedades/\(p.id)/duplicar", [String: String]())
            estado.version += 1
            estado.sugerir("Duplicada sin publicar", "Ver", AFichaPropiedad(id: n.id))
        } catch { estado.avisar(error) }
    }

    /// A la papelera al toque; «Deshacer» la restaura de la papelera (la web hace lo mismo).
    private func borrar(_ p: Propiedad) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/propiedades/\(p.id)")
            estado.version += 1
            cerrar()
            let id = p.id
            estado.avisar("\((p.direccion ?? p.nombre).components(separatedBy: ",").first ?? p.nombre) fue a la papelera") {
                Task {
                    do {
                        try await estado.api.hacer("POST", "/v1/papelera/propiedad/\(id)/restaurar")
                        estado.version += 1
                        estado.abrir(AFichaPropiedad(id: id))
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }
}

/// Chips que bajan de renglón (las comodidades).
struct ChipsComodidades: View {
    var textos: [String]
    var body: some View {
        FlujoLayout(espacio: 6) {
            ForEach(textos, id: \.self) { t in
                Text(t).font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.texto)
                    .padding(.horizontal, 10).frame(height: 30).background(C.superficie, in: Capsule())
                    .overlay(Capsule().strokeBorder(C.linea2, lineWidth: 1))
            }
        }
    }
}

/// Un layout que acomoda las vistas de izquierda a derecha y baja de renglón cuando no entran.
struct FlujoLayout: Layout {
    var espacio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            alto = max(alto, t.height)
        }
        return CGSize(width: min(maxX, ancho), height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}
