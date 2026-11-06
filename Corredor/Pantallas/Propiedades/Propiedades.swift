import CoreLocation
import MapKit
import SwiftUI
import TipKit

/// La ficha con la hoja de «Arreglar» abierta (el error de un portal, 9C·err; la web: `?arreglar=`).
struct AArreglarPropiedad: Hashable { var id: String }
/// La ficha con la hoja de compartir abierta; con `contacto`, para mandársela a esa persona (el
/// «Mandar» de la ficha de un contacto; la web: `?compartir=whatsapp&contacto=<id>`).
struct AMandarPropiedad: Hashable { var id: String; var contacto: String? = nil }
/// La edición de una propiedad abierta en un paso («fotos», «comodidades», «portales»; la web: `?paso=`).
struct AEditarEnPaso: Hashable { var id: String; var paso: String }
/// Una reserva de venta o alquiler (la web: /reservas/[id]).
struct AReserva: Hashable { var id: String }
/// Una reserva de temporario: el check-in (la web: /temporada/reservas/[id]).
struct AReservaTemporada: Hashable { var id: String }
/// Mercado Libre (32E): preguntas, errores explicados y publicaciones.
struct AMercadoLibre: Hashable {}
/// La tarjeta de 85 × 55 mm de una propiedad, para dejar en la visita.
struct ATarjetaPropiedad: Hashable { var id: String }
/// La cartera filtrada por barrio («Más en Belgrano», desde la ficha).
struct ACartera: Hashable { var barrio: String }

extension View {
    /// Los destinos de Propiedades: ficha, galería, alta, reservas, temporada y Mercado Libre.
    func destinosPropiedades() -> some View {
        self
            .navigationDestination(for: AFichaPropiedad.self) { f in FichaPropiedad(id: f.id) }
            .navigationDestination(for: AArreglarPropiedad.self) { f in FichaPropiedad(id: f.id, arreglarAlAbrir: true) }
            .navigationDestination(for: AMandarPropiedad.self) { f in FichaPropiedad(id: f.id, compartirAlAbrir: true, compartirCon: f.contacto) }
            .navigationDestination(for: AGaleria.self) { g in Galeria(id: g.id, indice: g.indice) }
            .navigationDestination(for: AAltaPropiedad.self) { a in AltaPropiedad(editar: a.editar, borrador: a.borrador) }
            .navigationDestination(for: AEditarEnPaso.self) { a in AltaPropiedad(editar: a.id, enPaso: a.paso) }
            .navigationDestination(for: AReserva.self) { r in PantallaReserva(id: r.id) }
            .navigationDestination(for: AReservaTemporada.self) { r in CheckinTemporada(id: r.id) }
            .navigationDestination(for: AMercadoLibre.self) { _ in PantallaMercadoLibre() }
            .navigationDestination(for: ATarjetaPropiedad.self) { t in TarjetaVisita(id: t.id) }
            .navigationDestination(for: ACartera.self) { c in PropiedadesRaiz(inicial: FiltrosCartera(barrio: [c.barrio]), titulo: "Más en \(c.barrio)") }
    }
}

/// Lo que dispara una nueva carga de la cartera: un cambio (versión) o los filtros.
private struct ClaveCartera: Equatable { var version: Int; var filtros: FiltrosCartera }

/// 3A–3C Propiedades (la cartera, web 02 · 8E/8C): lista o mapa, con las vistas que son tareas arriba
/// (con su cuenta), los filtros en la API, el orden «por lo que necesita atención», la selección de
/// varias para acciones en lote y las vistas guardadas.
struct PropiedadesRaiz: View {
    @Environment(Estado.self) private var estado
    @State private var vista = 0
    @State private var filtros = FiltrosCartera()
    @State private var busqueda = ""
    @State private var props: [Propiedad]?
    @State private var senales: [String: Senal] = [:]
    @State private var resumen = ResumenCartera()
    @State private var equipo: [Miembro] = []
    @State private var emprendimientos: [EmprendimientoAPI] = []
    @State private var error: ErrorApi?
    /// La hora de la copia guardada (cuando no se pudo traer la cartera).
    @State private var copiaEn: Date?
    @State private var viendoCopia = false
    @State private var web: String?
    @State private var compartir: Propiedad?
    @State private var guardadas: [VistaGuardada] = VistaGuardada.todas()
    @State private var seleccionando = false
    @State private var marcadas: Set<String> = []
    @State private var hojaFiltros = false
    @State private var hojaPrecioVarias = false
    @State private var hojaMandarVarias = false
    @State private var hojaGuardar = false
    @State private var nombreVista = ""
    @State private var masAbierto = false
    @State private var exportando: URL?
    /// Apilada (no como pestaña): con la barra de navegación y este título.
    var titulo: String? = nil

    init(inicial: FiltrosCartera? = nil, titulo: String? = nil) {
        _filtros = State(initialValue: inicial ?? FiltrosCartera())
        self.titulo = titulo
    }

    private var esDuenioOAdmin: Bool { estado.rol == "duenio" || estado.rol == "admin" }

    var body: some View {
        Group {
            if vista == 1, let lista = filas, !lista.isEmpty {
                // El mapa no va dentro del scroll: ocupa todo el alto que queda (hasta la barra de pestañas).
                VStack(alignment: .leading, spacing: 12) {
                    encabezado
                    MapaCartera(props: lista, senales: senales, titulo: filtros.barrio.first ?? "Tu cartera") { compartir = $0 }
                        .padding(.horizontal, 16).padding(.bottom, 12)
                        .frame(maxHeight: .infinity)
                }
            } else {
                listado
            }
        }
        .modifier(MarcoCartera(titulo: titulo))
        .task(id: ClaveCartera(version: estado.version, filtros: filtros)) { await cargar() }
        .task(id: busqueda) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled, busqueda.trimmingCharacters(in: .whitespaces) != filtros.q { filtros.q = busqueda.trimmingCharacters(in: .whitespaces) }
        }
        .sheet(item: $compartir) { p in HojaCompartir(propiedad: p, web: web).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $hojaFiltros) {
            HojaFiltrosCartera(filtros: $filtros, resumen: resumen, equipo: equipo, conAgentes: esDuenioOAdmin).hojaTLW([.large])
        }
        .sheet(isPresented: $hojaPrecioVarias) {
            HojaPrecioVarias(cuantas: marcadas.count) { pct in Task { await cambiarPrecios(pct) } }.hojaTLW([.medium])
        }
        .sheet(isPresented: $hojaMandarVarias) {
            HojaMandarVarias { c in mandarA(c) }.hojaTLW([.large])
        }
        .sheet(item: Binding(get: { exportando.map { URLHoja(url: $0) } }, set: { exportando = $0?.url })) { x in
            ShareLink(item: x.url) { Label("Compartir \(x.url.lastPathComponent)", systemImage: "square.and.arrow.up") }.padding(40).presentationDetents([.height(160)])
        }
        .alert("Guardar esta vista", isPresented: $hojaGuardar) {
            TextField("Belgrano en venta", text: $nombreVista)
            Button("Cancelar", role: .cancel) { nombreVista = "" }
            Button("Guardar") { guardarVista(nombreVista); nombreVista = "" }
        } message: { Text("Queda arriba, con las demás, en este iPhone.") }
        .confirmationDialog("Propiedades", isPresented: $masAbierto, titleVisibility: .hidden) {
            Button("Descargar en Excel") { Task { await exportar() } }
            if !filtros.vacio { Button("Guardar esta vista") { hojaGuardar = true } }
            if estado.escribe { Button("Importar de Excel") { estado.abrir(ASeccion(clave: "importar")) } }
            Button("Cancelar", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if seleccionando {
                botoneraSeleccion
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
            }
        }
    }

    // MARK: Cabecera, vistas y filtros

    private var acciones: [AccionCabecera] {
        var a: [AccionCabecera] = [AccionCabecera(icono: vista == 1 ? "list.bullet" : "map", etiqueta: vista == 1 ? "Ver la lista" : "Ver el mapa") { vista = vista == 1 ? 0 : 1 }]
        if estado.escribe {
            a.append(AccionCabecera(icono: "viewfinder", etiqueta: "Captar con MIRA") { estado.miraAbierta = true })
            a.append(AccionCabecera(icono: "plus.circle", etiqueta: "Cargar propiedad") { estado.abrir(AAltaPropiedad()) })
            a.append(AccionCabecera(icono: seleccionando ? "checkmark.circle.fill" : "checkmark.circle", etiqueta: seleccionando ? "Terminar la selección" : "Seleccionar") {
                seleccionando.toggle()
                if !seleccionando { marcadas = [] }
            })
        }
        a.append(AccionCabecera(icono: "ellipsis.circle", etiqueta: "Más") { masAbierto = true })
        return a
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 12) {
            CabeceraPestana(titulo: "Propiedades", acciones: acciones)
            Buscador(placeholder: "Calle, barrio o código", texto: $busqueda).padding(.horizontal, 16)
            Segmentado(opciones: [("yo", "Mías · \(resumen.mias)"), ("libre", "Sin agente · \(resumen.sinAgente)"), ("todas", "Todas")],
                       elegido: Binding(get: { filtros.agente == "yo" || filtros.agente == "libre" ? filtros.agente! : "todas" },
                                        set: { filtros.agente = $0 == "todas" ? nil : $0 }))
                .padding(.horizontal, 16)
            chipsVistas
            if !puestos.isEmpty { chipsPuestos }
        }
    }

    private var chipsVistas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if resumen.conError > 0 || filtros.portal != nil {
                    ChipFiltro(texto: "\(resumen.conError) con error", activo: filtros.portal == "error") { filtros.portal = filtros.portal == nil ? "error" : nil }
                }
                if resumen.sinPublicar > 0 || filtros.publicada != nil {
                    ChipFiltro(texto: Formato.cantidad(resumen.sinPublicar, "borrador", "borradores"), activo: filtros.publicada == "no") { filtros.publicada = filtros.publicada == nil ? "no" : nil }
                }
                if resumen.sinVistas > 0 || filtros.sinVistas != nil {
                    ChipFiltro(texto: "Sin visitas hace 30 días · \(resumen.sinVistas)", activo: filtros.sinVistas != nil) { filtros.sinVistas = filtros.sinVistas == nil ? "30" : nil }
                }
                ForEach([("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporario")], id: \.0) { k, n in
                    ChipFiltro(texto: n, activo: filtros.operacion == [k]) { filtros.operacion = filtros.operacion == [k] ? [] : [k] }
                }
                if resumen.destacadas > 0 || filtros.destacada {
                    ChipFiltro(texto: "Fijadas · \(resumen.destacadas)", activo: filtros.destacada) { filtros.destacada.toggle() }
                }
                ForEach(guardadas) { g in
                    ChipFiltro(texto: g.nombre, activo: filtros == g.filtros) { filtros = g.filtros; busqueda = g.filtros.q }
                        .contextMenu {
                            Button(role: .destructive) { borrarVista(g) } label: { Label("Borrar la vista", systemImage: "trash") }
                        }
                }
                ChipFiltro(texto: "Filtros", activo: false) { hojaFiltros = true }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
    }

    /// Los filtros puestos, que se sacan con un toque.
    private var puestos: [(String, String)] {
        var p: [(String, String)] = []
        let ops = Dictionary(uniqueKeysWithValues: Propiedad.operaciones.map { ($0.0, $0.0 == "temporario" ? "Temporario" : $0.1) })
        let tipos = Dictionary(uniqueKeysWithValues: Propiedad.tipos.map { ($0.0, $0.1) })
        let ests = Dictionary(uniqueKeysWithValues: Propiedad.estados.map { ($0.0, $0.1) })
        if filtros.operacion.count > 1 { p.append(("operacion", filtros.operacion.map { ops[$0] ?? $0 }.joined(separator: ", "))) }
        if !filtros.tipo.isEmpty { p.append(("tipo", filtros.tipo.map { tipos[$0] ?? $0 }.joined(separator: ", "))) }
        if !filtros.estado.isEmpty { p.append(("estado", filtros.estado.map { ests[$0] ?? $0 }.joined(separator: ", "))) }
        if !filtros.barrio.isEmpty { p.append(("barrio", filtros.barrio.joined(separator: ", "))) }
        if filtros.precioDesde != nil || filtros.precioHasta != nil {
            p.append(("precio", [filtros.precioDesde.flatMap(Int.init).map { "desde \(Formato.numero($0))" },
                                 filtros.precioHasta.flatMap(Int.init).map { "hasta \(Formato.numero($0))" }].compactMap { $0 }.joined(separator: " ")))
        }
        if let a = filtros.agente, a != "yo", a != "libre" { p.append(("agente", equipo.first { $0.usuarioId == a }?.completo ?? "Agente")) }
        return p
    }

    private var chipsPuestos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(puestos, id: \.0) { k, t in
                    Button { sacar(k) } label: {
                        HStack(spacing: 4) { Text(t).lineLimit(1); Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                            .font(Estilo(tamano: 13, peso: .semibold, relativo: .footnote).font).foregroundStyle(C.sobreAccion)
                            .padding(.horizontal, 12).frame(height: 32).background(C.accion, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityLabel("Sacar el filtro \(t)")
                }
                Button("Sacar los filtros") { filtros = FiltrosCartera(); busqueda = "" }
                    .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion)
            }
            .padding(.horizontal, 16)
        }
    }

    private func sacar(_ k: String) {
        switch k {
        case "operacion": filtros.operacion = []
        case "tipo": filtros.tipo = []
        case "estado": filtros.estado = []
        case "barrio": filtros.barrio = []
        case "precio": filtros.precioDesde = nil; filtros.precioHasta = nil
        default: filtros.agente = nil
        }
    }

    // MARK: Lista

    /// Las filas, ordenadas por lo que necesita atención (y después por la última cambiada).
    private var filas: [Propiedad]? {
        guard let props else { return nil }
        let ahora = Date()
        return props.map { ($0, Cartera.prioridad($0, senales[$0.id], ahora: ahora)) }
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : (a.0.actualizadoEn ?? .distantPast) > (b.0.actualizadoEn ?? .distantPast) }
            .map(\.0)
    }

    private var listado: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                encabezado
                if let error, !viendoCopia {
                    errorCarga(error).padding(.top, 20)
                } else if let lista = filas {
                    if viendoCopia, let copiaEn {
                        HStack(spacing: 6) {
                            Image(systemName: "icloud.slash")
                            Text("Copia de las \(Formato.horaDe(copiaEn)).")
                            Button("Reintentar") { Task { await cargar() } }.fontWeight(.semibold).foregroundStyle(C.accion)
                        }
                        .estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 20)
                    }
                    if lista.isEmpty {
                        vacio.padding(.top, 30)
                    } else {
                        Text("\(Formato.numero(lista.count)) de \(Formato.numero(resumen.total)) · ordenadas por lo que necesita atención")
                            .estilo(.footnote).foregroundStyle(C.texto2).padding(.horizontal, 20)
                        if filtros.vacio, !viendoCopia { fijadas }
                        VStack(spacing: 10) {
                            TipView(ConsejoMandar()).tipBackground(C.superficie)
                            ForEach(lista) { p in fila(p) }
                            Text("Tocá el logo de WhatsApp para mandarla; mantené apretada una fila para más")
                                .estilo(.footnote).foregroundStyle(C.texto3).frame(maxWidth: .infinity).padding(.vertical, 6)
                            Text("W web · ML Mercado Libre · ZP Zonaprop · AP Argenprop · tachado = no publicada")
                                .estilo(.footnote).foregroundStyle(C.texto3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        if filtros.vacio { accesos }
                    }
                } else {
                    EsqueletoFilas(filas: 5, miniatura: 92).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable { await cargar() }
    }

    @ViewBuilder
    private var vacio: some View {
        if resumen.total == 0, filtros.vacio {
            EstadoVacio(icono: "building.2", titulo: "Así se va a ver tu primera propiedad",
                        texto: "Sacale una foto al cartel o cargala a mano.",
                        accion: estado.escribe ? ("Captar con MIRA", { estado.miraAbierta = true }) : nil,
                        secundaria: estado.escribe ? ("Cargar a mano", { estado.abrir(AAltaPropiedad()) }) : nil)
            if estado.escribe {
                Button("Importar de Excel") { estado.abrir(ASeccion(clave: "importar")) }.buttonStyle(BotonTexto()).frame(maxWidth: .infinity)
            }
        } else {
            EstadoVacio(icono: "line.3.horizontal.decrease.circle", titulo: "Ninguna propiedad con estos filtros",
                        texto: "Probá sacar alguno o buscá por calle, barrio o código.",
                        accion: ("Sacar los filtros", { filtros = FiltrosCartera(); busqueda = "" }))
        }
    }

    private func errorCarga(_ e: ErrorApi) -> some View {
        EstadoVacio(icono: "exclamationmark.triangle", titulo: "No pudimos traer la cartera",
                    texto: copiaEn.map { "Te mostramos la copia de las \(Formato.horaDe($0)). Lo que cambies se guarda y se manda al volver." }
                        ?? (e.sinConexion ? "No hay internet. Lo que cargaste está a salvo." : "Puede ser la conexión o un problema nuestro. Lo que cargaste está a salvo."),
                    accion: ("Reintentar", { Task { await cargar() } }),
                    secundaria: copiaEn != nil ? ("Ver la copia", { verCopia() }) : nil)
    }

    /// Las fijadas (destacadas), con lo que pasa en cada una.
    @ViewBuilder
    private var fijadas: some View {
        let ds = (props ?? []).filter { $0.destacada == true }.prefix(3)
        if !ds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TituloBloque(texto: "Fijadas")
                VStack(spacing: 0) {
                    ForEach(Array(ds.enumerated()), id: \.element.id) { i, p in
                        let (detalle, tono) = Self.fijada(p, senales[p.id])
                        Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                            HStack(spacing: 12) {
                                Foto(url: p.miniatura).frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((p.direccion ?? p.nombre).components(separatedBy: ",").first ?? p.nombre).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(1)
                                    if !detalle.isEmpty { Text(detalle).estilo(.footnote).foregroundStyle(tono?.tinta ?? C.texto2) }
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                    }
                }
                .tarjeta()
            }
            .padding(.horizontal, 16)
        }
    }

    static func fijada(_ p: Propiedad, _ s: Senal?) -> (String, Tono?) {
        if let v = s?.proximaVisita { return ("visita \(Senal.cuando(v))", .oro) }
        if let v = s?.venceReserva {
            let d = diasCalendario(Date(), v)
            return ("reserva vence \(d <= 0 ? "hoy" : d == 1 ? "mañana" : "en \(d) días")", .rojo)
        }
        if s?.error != nil { return ("error en un portal", .rojo) }
        if let n = s?.interesados, n > 0 { return ("\(n) interesados", nil) }
        return (p.barrio ?? "", nil)
    }

    /// Los accesos a Venta, Alquiler, Temporario y Emprendimientos (con la cuenta de unidades).
    private var accesos: some View {
        let unidades = emprendimientos.reduce(0) { $0 + ($1.unidades?.total ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Secciones")
            VStack(spacing: 0) {
                filaAcceso("Venta", "tag", "\(resumen.venta)", primera: true) { filtros.operacion = ["venta"] }
                filaAcceso("Alquiler", "key", "\(resumen.alquiler)") { filtros.operacion = ["alquiler"] }
                filaAcceso("Temporario", "beach.umbrella", "\(resumen.temporario)") { estado.abrir(ASeccion(clave: "temporada")) }
                filaAcceso("Emprendimientos", "building", unidades > 0 ? "\(emprendimientos.count) · \(unidades) unidades" : "\(emprendimientos.count)") {
                    estado.abrir(ASeccion(clave: "emprendimientos"))
                }
            }
            .tarjeta()
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func filaAcceso(_ t: String, _ i: String, _ cuenta: String, primera: Bool = false, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack(spacing: 12) {
                IconoTono(icono: i, tono: .verde, tam: 34)
                Text(t).estilo(.filaLista).foregroundStyle(C.texto)
                Spacer()
                Text(cuenta).estilo(.subhead).foregroundStyle(C.texto2)
                Chevron()
            }
            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(Presionable())
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    // MARK: Fila

    private func fila(_ p: Propiedad) -> some View {
        let s = senales[p.id]
        let mandar = AccionFila(texto: "Mandar", simbolo: "square.and.arrow.up", color: Color(hex: 0x25D366)) { compartir = p }
        let derecha: [AccionFila] = estado.escribe && !seleccionando ? [
            AccionFila(texto: p.publicada == false ? "Publicar" : "Despublicar", simbolo: p.publicada == false ? "arrow.up.circle" : "eye.slash", color: Color(hex: 0x8E8E93)) { publicar(p) },
            mandar,
        ] : seleccionando ? [] : [mandar]
        return FilaDeslizable(derecha: derecha, anchoAccion: 75) {
            Button {
                if seleccionando { marcar(p.id) } else { estado.abrir(AFichaPropiedad(id: p.id)) }
            } label: {
                FilaCartera(p: p, s: s, agente: agenteDe(p), marcada: seleccionando ? marcadas.contains(p.id) : nil)
            }
            .buttonStyle(Presionable())
            .overlay(alignment: .bottomTrailing) {
                if !seleccionando {
                    HStack(spacing: 8) {
                        if s?.error != nil, estado.escribe {
                            Button("Arreglar") { estado.abrir(AArreglarPropiedad(id: p.id)) }
                                .font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font).foregroundStyle(C.errorTinta)
                                .padding(.horizontal, 10).frame(height: 30).background(C.errorFondo, in: Capsule())
                        }
                        BotonMandar { compartir = p }
                    }
                    .padding(10)
                }
            }
        }
        .clipShape(.rect(cornerRadius: M.rTarjeta, style: .continuous))
        .sombraE2()
        .contextMenu {
            Button { compartir = p } label: { Label("Mandar la ficha", systemImage: "square.and.arrow.up") }
            if estado.escribe {
                Button { estado.abrir(AAgendaDia()) } label: { Label("Agendar visita", systemImage: "calendar.badge.plus") }
                Button { estado.abrir(AAltaPropiedad(editar: p.id)) } label: { Label("Editar", systemImage: "pencil") }
                Button { publicar(p) } label: { Label(p.publicada == false ? "Publicar" : "Despublicar", systemImage: p.publicada == false ? "arrow.up.circle" : "eye.slash") }
                Button { seleccionando = true; marcar(p.id) } label: { Label("Seleccionar", systemImage: "checkmark.circle") }
            }
        }
    }

    private func agenteDe(_ p: Propiedad) -> String? {
        guard let a = p.agenteId else { return nil }
        return equipo.first { $0.usuarioId == a }?.completo ?? "Agente"
    }

    private func marcar(_ id: String) {
        Haptico.seleccion()
        if marcadas.contains(id) { marcadas.remove(id) } else { marcadas.insert(id) }
    }

    /// El chip de estado de cada fila (3A): lo más importante que le pasa a la propiedad.
    static func chip(_ p: Propiedad, _ s: Senal?) -> (String, Tono) {
        if let a = Cartera.atencion(p, s) { return (a.0, a.1 == .neutro ? .verde : a.1) }
        let (e, t) = Cartera.estado(p)
        return (e, t)
    }

    // MARK: Selección (acciones en lote)

    private var botoneraSeleccion: some View {
        VStack(spacing: 8) {
            Text(marcadas.isEmpty ? "Tocá las propiedades para elegirlas" : Formato.cantidad(marcadas.count, "seleccionada", "seleccionadas"))
                .estilo(.subheadFuerte).foregroundStyle(C.texto)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if estado.esDuenio {
                        Menu {
                            ForEach(equipo) { m in
                                Button(m.completo) { asignar(m) }
                            }
                        } label: { Label("Asignar agente", systemImage: "person.badge.plus") }
                            .buttonStyle(BotonTonal())
                    }
                    Button { hojaPrecioVarias = true } label: { Label("Cambiar precio", systemImage: "tag") }.buttonStyle(BotonTonal())
                    Button { hojaMandarVarias = true } label: { Label("Mandar a un interesado", systemImage: "square.and.arrow.up") }.buttonStyle(BotonTonal())
                    Button { despublicarVarias() } label: { Label("Despublicar", systemImage: "eye.slash") }.buttonStyle(BotonTonal())
                    Button { marcadas = []; seleccionando = false } label: { Image(systemName: "xmark") }.buttonStyle(BotonTonal()).accessibilityLabel("Deseleccionar")
                }
            }
            .disabled(marcadas.isEmpty)
        }
    }

    private func elegidas() -> [Propiedad] { (props ?? []).filter { marcadas.contains($0.id) } }

    private func asignar(_ m: Miembro) {
        let ps = elegidas()
        struct C: Encodable {
            var agenteId: String?
            func encode(to e: Encoder) throws {
                var c = e.container(keyedBy: K.self)
                try c.encode(agenteId, forKey: .agenteId)
            }
            enum K: String, CodingKey { case agenteId }
        }
        Task {
            do {
                for p in ps { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", C(agenteId: m.usuarioId)) }
                marcadas = []
                seleccionando = false
                estado.version += 1
                let nombre = m.completo.components(separatedBy: " ").first ?? m.completo
                estado.avisar("\(ps.count == 1 ? "Asignada" : "Asignadas") a \(nombre)") {
                    Task {
                        do {
                            for p in ps { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", C(agenteId: p.agenteId)) }
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            } catch { estado.avisar(error) }
        }
    }

    private func despublicarVarias() {
        let ps = elegidas()
        struct C: Encodable { var publicada: Bool }
        Task {
            do {
                for p in ps { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", C(publicada: false)) }
                marcadas = []
                seleccionando = false
                estado.version += 1
                estado.avisar(ps.count == 1 ? "Despublicada de tu web" : "Despublicadas de tu web") {
                    Task {
                        do {
                            for p in ps { try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", C(publicada: p.publicada ?? true)) }
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            } catch { estado.avisar(error) }
        }
    }

    /// Cambia el precio en % (redondeo a la centena), con deshacer (vuelve a poner cada propiedad como estaba).
    private func cambiarPrecios(_ pct: Double) async {
        let ids = Array(marcadas)
        var viejas: [Propiedad] = []
        do {
            for id in ids {
                let p: Propiedad = try await estado.api.get("/v1/propiedades/\(id)")
                guard let precio = p.precio else { continue }
                viejas.append(p)
                var nueva = p
                nueva.precio = ((precio * (1 + pct / 100)) / 100).rounded() * 100
                try await estado.api.hacer("PUT", "/v1/propiedades/\(id)", nueva)
            }
            marcadas = []
            seleccionando = false
            estado.version += 1
            let n = viejas.count
            let verbo = pct < 0 ? (n == 1 ? "bajó" : "bajaron") : (n == 1 ? "subió" : "subieron")
            estado.avisar("\(Formato.cantidad(n, "precio", "precios")) \(verbo) \(Formato.porcentaje(abs(pct)))") {
                Task {
                    do {
                        for p in viejas { try await estado.api.hacer("PUT", "/v1/propiedades/\(p.id)", p) }
                        estado.version += 1
                    } catch { estado.avisar(error) }
                }
            }
        } catch { estado.avisar(error) }
    }

    /// Un mensaje de WhatsApp con todas las elegidas y sus links.
    private func mandarA(_ c: Contacto) {
        let ps = elegidas()
        let base = web ?? ""
        let primero = c.nombre.components(separatedBy: " ").first ?? c.nombre
        let texto = "Hola \(primero), te paso \(ps.count == 1 ? "una propiedad que te puede interesar" : "unas propiedades que te pueden interesar"):\n"
            + ps.map { "\($0.direccion ?? $0.nombre) · \($0.precioTexto)\n\(base)/propiedades/\($0.slug ?? $0.id)" }.joined(separator: "\n\n")
        Afuera.whatsapp(c.telefono, texto: texto)
        hojaMandarVarias = false
        marcadas = []
        seleccionando = false
    }

    // MARK: Vistas guardadas, copia y exportar

    private func guardarVista(_ nombre: String) {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        guardadas = guardadas.filter { $0.nombre != n } + [VistaGuardada(nombre: n, filtros: filtros)]
        VistaGuardada.guardar(guardadas)
        estado.avisar("Vista «\(n)» guardada")
    }

    private func borrarVista(_ g: VistaGuardada) {
        let antes = guardadas
        guardadas.removeAll { $0.nombre == g.nombre }
        VistaGuardada.guardar(guardadas)
        estado.avisar("Vista «\(g.nombre)» borrada") {
            guardadas = antes
            VistaGuardada.guardar(antes)
        }
    }

    private func verCopia() {
        guard let (l, _) = Guardado.leer([Propiedad].self, clave: "propiedades") else { return }
        props = l
        senales = Guardado.leer([String: Senal].self, clave: "propiedades-senales")?.0 ?? [:]
        viendoCopia = true
    }

    private func exportar() async {
        do {
            let d = try await estado.api.pedir("GET", "/v1/exportar/propiedades", query: [.init(name: "formato", value: "xlsx")])
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("propiedades-\(Formato.diaISO(Date())).xlsx")
            try d.write(to: u)
            exportando = u
        } catch { estado.avisar(error) }
    }

    /// Publicar o despublicar en la web (como el panel): despublicada queda como borrador.
    private func publicar(_ p: Propiedad) {
        let nuevo = p.publicada == false
        Task {
            struct Cuerpo: Encodable { var publicada: Bool }
            do {
                try await estado.cola.enviar("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: nuevo), etiqueta: "\(nuevo ? "Publicar" : "Despublicar") \(p.nombre)")
                estado.version += 1
                estado.avisar(nuevo ? "Publicada en tu web" : "Despublicada: quedó como borrador") {
                    Task {
                        do {
                            try await estado.api.hacer("PATCH", "/v1/propiedades/\(p.id)", Cuerpo(publicada: !nuevo))
                            estado.version += 1
                        } catch { estado.avisar(error) }
                    }
                }
            } catch { estado.avisar(error) }
        }
    }

    private func cargar() async {
        do {
            let q = filtros.query + [.init(name: "unidades", value: "no"), .init(name: "orden", value: "actualizada")]
            let l: [Propiedad] = try await estado.api.todas("/v1/propiedades", query: q)
            props = l
            error = nil
            viendoCopia = false
            if let r: ResumenCartera = try? await estado.api.get("/v1/propiedades/resumen") { resumen = r }
            // Las señales no tiran la cartera: si no vienen, la lista se ve igual.
            if let s = try? await Senal.de(l.map(\.id), api: estado.api) { senales = s }
            if filtros.vacio {
                Spotlight.indexar(propiedades: l)
                Guardado.guardar(l, clave: "propiedades")
                Guardado.guardar(senales, clave: "propiedades-senales")
            }
            if equipo.isEmpty, let e: [Miembro] = try? await estado.api.get("/v1/equipo") { equipo = e }
            if let e: [EmprendimientoAPI] = try? await estado.api.get("/v1/emprendimientos") { emprendimientos = e }
            if web == nil { web = (try? await estado.api.get("/v1/inmobiliaria") as Inmobiliaria)?.web }
        } catch let e as ErrorApi {
            error = e
            copiaEn = Guardado.leer([Propiedad].self, clave: "propiedades")?.1
        } catch {}
    }
}

/// Como pestaña, sin barra de navegación; apilada («Más en Belgrano»), con su título.
private struct MarcoCartera: ViewModifier {
    var titulo: String?
    @ViewBuilder
    func body(content: Content) -> some View {
        if let titulo { content.pantallaApilada(titulo) } else { content.pantallaRaiz() }
    }
}

/// Una tarjeta de la cartera: foto, precio con su nota, dirección, el resumen (o «captada con MIRA»),
/// las siglas de los portales, la línea de atención, los interesados y el agente.
struct FilaCartera: View {
    var p: Propiedad
    var s: Senal?
    var agente: String?
    /// En la selección: si está marcada (nil fuera de la selección).
    var marcada: Bool?

    var body: some View {
        let nota = Cartera.notaPrecio(p, s)
        HStack(alignment: .top, spacing: 12) {
            Foto(url: p.miniatura).frame(width: 92, height: 92).clipShape(.rect(cornerRadius: 13, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let marcada {
                        Image(systemName: marcada ? "checkmark.circle.fill" : "circle").font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(marcada ? C.accion : .white).background(Circle().fill(.black.opacity(marcada ? 0 : 0.25))).padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.precioTexto).font(Estilo(tamano: 17, peso: .bold, tracking: -0.01, relativo: .headline).font).foregroundStyle(C.texto)
                    if !nota.0.isEmpty { Text(nota.0).estilo(.footnote).foregroundStyle(nota.1 == .neutro ? C.texto2 : nota.1.tinta).lineLimit(1) }
                }
                Text(p.direccion ?? p.nombre).font(Estilo(tamano: 15, peso: .medium, relativo: .subheadline).font).foregroundStyle(C.texto).lineLimit(1)
                Text(p.deMira ? [p.resumen, "captada con MIRA"].filter { !$0.isEmpty }.joined(separator: " · ") : p.resumen)
                    .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(2)
                siglas.padding(.top, 2)
                if let a = Cartera.atencion(p, s) {
                    HStack(spacing: 4) {
                        if let i = a.2 { Image(systemName: i).font(.system(size: 12)) }
                        Text(a.0).lineLimit(1)
                    }
                    .font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(a.1.tinta)
                    .padding(.horizontal, 9).frame(height: 24).background(a.1.fondo, in: Capsule())
                    .padding(.trailing, 44).padding(.top, 2)
                } else {
                    let (e, t) = Cartera.estado(p)
                    Text(e).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(t.tinta)
                        .padding(.horizontal, 9).frame(height: 24).background(t.fondo, in: Capsule()).padding(.top, 2)
                }
                let inter = Cartera.interesados(s)
                Text(["Interesados: \(inter.0)", agente.map { $0.components(separatedBy: " ").first ?? $0 } ?? "Asignar"].joined(separator: " · "))
                    .font(Estilo(tamano: 12, peso: inter.1 ? .bold : .regular, relativo: .caption).font)
                    .foregroundStyle(inter.1 ? C.avisoTinta : C.texto3).lineLimit(1).padding(.trailing, 44)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(C.superficie)
        .contentShape(Rectangle())
    }

    private var siglas: some View {
        HStack(spacing: 6) {
            ForEach(PortalesCartera.todos, id: \.clave) { pt in
                let e = PortalesCartera.estado(p, s, pt.clave)
                Text(pt.sigla).font(Estilo(tamano: 11, peso: .bold, relativo: .caption2).font)
                    .strikethrough(e == "off")
                    .foregroundStyle(e == "ok" ? C.okTinta : e == "err" ? C.errorTinta : C.texto3)
                    .padding(.horizontal, 5).frame(height: 18)
                    .background(e == "ok" ? C.okFondo : e == "err" ? C.errorFondo : C.hundida, in: .rect(cornerRadius: 5))
                    .accessibilityLabel("\(pt.nombre): \(e == "ok" ? "publicada" : e == "err" ? "con error" : "no publicada")")
            }
        }
    }
}

/// Los filtros de la cartera: operación, tipo, estado, barrio (con la cuenta), precio y agente.
struct HojaFiltrosCartera: View {
    @Environment(\.dismiss) private var cerrar
    @Binding var filtros: FiltrosCartera
    var resumen: ResumenCartera
    var equipo: [Miembro]
    var conAgentes: Bool
    @State private var desde = ""
    @State private var hasta = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Operación") {
                    ForEach([("venta", "Venta"), ("alquiler", "Alquiler"), ("temporario", "Temporario")], id: \.0) { k, n in marca(n, filtros.operacion.contains(k)) { FiltrosCartera.alternar(&filtros.operacion, k) } }
                }
                Section("Tipo") {
                    ForEach(Propiedad.tipos, id: \.0) { k, n in marca(n, filtros.tipo.contains(k)) { FiltrosCartera.alternar(&filtros.tipo, k) } }
                }
                Section("Estado") {
                    ForEach(Propiedad.estados, id: \.0) { k, n in marca(n, filtros.estado.contains(k)) { FiltrosCartera.alternar(&filtros.estado, k) } }
                }
                if !resumen.barrios.isEmpty {
                    Section("Barrio") {
                        ForEach(resumen.barrios, id: \.barrio) { b in marca("\(b.barrio) · \(b.cantidad)", filtros.barrio.contains(b.barrio)) { FiltrosCartera.alternar(&filtros.barrio, b.barrio) } }
                    }
                }
                Section("Precio") {
                    TextField("Desde (100.000)", text: $desde).keyboardType(.numberPad)
                    TextField("Hasta (200.000)", text: $hasta).keyboardType(.numberPad)
                }
                if conAgentes {
                    Section("Agente") {
                        marca("Mías", filtros.agente == "yo") { filtros.agente = filtros.agente == "yo" ? nil : "yo" }
                        ForEach(equipo) { m in marca(m.completo, filtros.agente == m.usuarioId) { filtros.agente = filtros.agente == m.usuarioId ? nil : m.usuarioId } }
                        marca("Sin agente", filtros.agente == "libre") { filtros.agente = filtros.agente == "libre" ? nil : "libre" }
                    }
                }
            }
            .navigationTitle("Filtros").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sacar los filtros") { filtros = FiltrosCartera(q: filtros.q); desde = ""; hasta = "" } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Filtrar") {
                        filtros.precioDesde = desde.filter(\.isNumber).nonEmpty
                        filtros.precioHasta = hasta.filter(\.isNumber).nonEmpty
                        cerrar()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { desde = filtros.precioDesde ?? ""; hasta = filtros.precioHasta ?? "" }
        }
    }

    private func marca(_ texto: String, _ puesta: Bool, _ hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            HStack {
                Text(texto).foregroundStyle(C.texto)
                Spacer()
                if puesta { Image(systemName: "checkmark").foregroundStyle(C.accion).fontWeight(.semibold) }
            }
        }
    }
}

/// «Cambiar el precio de N»: en porcentaje (−5 baja un 5 %), redondeado a la centena.
struct HojaPrecioVarias: View {
    @Environment(\.dismiss) private var cerrar
    var cuantas: Int
    var cambiar: (Double) -> Void
    @State private var porcentaje = "-5"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grabber().frame(maxWidth: .infinity)
            Text("Cambiar el precio de \(cuantas)").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text("En porcentaje: −5 baja un 5\(Formato.fino)%. Se redondea a la centena.").estilo(.subhead).foregroundStyle(C.texto2)
            Campo(label: "Porcentaje") { TextField("-5", text: $porcentaje).keyboardType(.numbersAndPunctuation) }
            HStack {
                Button("Cancelar") { cerrar() }.buttonStyle(BotonTexto())
                Spacer()
                Button("Cambiar") {
                    let n = Double(porcentaje.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")) ?? 0
                    guard n.isFinite, n != 0 else { return }
                    cerrar()
                    cambiar(n)
                }
                .buttonStyle(BotonPrincipal())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

/// «Mandar a un interesado»: buscar el contacto; le llega por WhatsApp con el link de cada una.
struct HojaMandarVarias: View {
    @Environment(Estado.self) private var estado
    var elegir: (Contacto) -> Void
    @State private var q = ""
    @State private var contactos: [Contacto] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grabber().frame(maxWidth: .infinity)
            Text("Mandar a un interesado").estilo(.tituloHojaChico).foregroundStyle(C.texto)
            Text("Le llega por WhatsApp con el link de cada una.").estilo(.subhead).foregroundStyle(C.texto2)
            Buscador(placeholder: "Nombre o teléfono", texto: $q)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(contactos) { c in
                        Button { elegir(c) } label: {
                            HStack(spacing: 12) {
                                AvatarIniciales(nombre: c.nombre, tam: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.nombre).estilo(.filaLista).foregroundStyle(C.texto)
                                    Text(c.telefono ?? "sin teléfono").estilo(.footnote).foregroundStyle(C.texto2)
                                }
                                Spacer()
                                Image(systemName: "bubble.left.fill").foregroundStyle(C.okTinta)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(Presionable())
                        .disabled(c.telefono == nil)
                    }
                }
                .tarjeta()
            }
        }
        .padding(.horizontal, 20)
        .task(id: q) {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            contactos = ((try? await estado.api.get("/v1/contactos", query: [.init(name: "limite", value: "8"), .init(name: "q", value: q)])) as [Contacto]?) ?? []
        }
    }
}

/// Un chip de filtro (36 de alto, cápsula; el activo en Acción).
struct ChipFiltro: View {
    var texto: String
    var activo: Bool
    var hacer: () -> Void
    var body: some View {
        Button(action: { Haptico.seleccion(); hacer() }) {
            Text(texto).font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                .foregroundStyle(activo ? C.sobreAccion : C.texto)
                .padding(.horizontal, 14).frame(height: 36)
                .background(activo ? C.accion : C.superficie, in: Capsule())
                .shadow(color: activo ? .clear : C.sombra.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(Presionable())
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

/// Una foto de la API con su lugar mientras carga.
struct Foto: View {
    var url: URL?
    var body: some View {
        // Dentro de un Color.clear: la foto llena el lugar que le den y se recorta ahí, sin estirar a
        // quien la contiene (una foto suelta con scaledToFill desbordaba la pantalla).
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { f in
                    switch f {
                    case .success(let i): i.resizable().scaledToFill()
                    default: ZStack { C.hundida; Image(systemName: "photo").foregroundStyle(C.texto3) }
                    }
                }
            }
            .clipped()
        .accessibilityHidden(true)
    }
}

/// 3C El mapa de la cartera: a nivel barrio, apagado y sin lugares de interés (como el handoff), con
/// los precios como pines y la tarjeta de la elegida abajo (con «a N cuadras de vos», Mandar y
/// Ficha). Arriba, el barrio filtrado (o «Tu cartera») y cuántas están ubicadas.
struct MapaCartera: View {
    @Environment(Estado.self) private var estado
    var props: [Propiedad]
    var senales: [String: Senal]
    var titulo = "Tu cartera"
    var compartir: (Propiedad) -> Void = { _ in }
    @State private var elegida: String?
    @State private var posicion: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var ubicacion = Ubicacion()

    private var conLugar: [Propiedad] { props.filter { $0.lat != nil && $0.lng != nil } }

    var body: some View {
        let lugares = conLugar
        ZStack(alignment: .bottom) {
            Map(position: $posicion, selection: $elegida) {
                ForEach(lugares) { p in
                    Annotation(p.nombre, coordinate: CLLocationCoordinate2D(latitude: p.lat ?? 0, longitude: p.lng ?? 0)) {
                        Text(Self.corto(p)).font(Estilo(tamano: 13, peso: .bold, relativo: .footnote).font)
                            .foregroundStyle(elegida == p.id ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(elegida == p.id ? C.accion : C.superficie, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                    }
                    .annotationTitles(.hidden)
                    .tag(p.id)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .animation(.snappy, value: elegida)

            if let p = lugares.first(where: { $0.id == elegida }) {
                tarjeta(p).padding(10).transition(.move(edge: .bottom).combined(with: .opacity))
            } else if lugares.isEmpty {
                Text(Formato.sinViudas("Ninguna tiene ubicación todavía. Se ubican solas con la dirección."))
                    .estilo(.footnote).foregroundStyle(C.texto2).multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(C.superficie, in: .rect(cornerRadius: 14, style: .continuous)).padding(16)
            }
        }
        .overlay(alignment: .topLeading) {
            let sin = props.count - lugares.count
            HStack(spacing: 6) {
                Text("\(titulo) · \(Formato.cantidad(lugares.count, "propiedad", "propiedades"))")
                if sin > 0, !lugares.isEmpty { Text("· \(sin) sin ubicar").foregroundStyle(C.texto3) }
            }
            .font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.texto2)
            .padding(.horizontal, 10).frame(height: 26).background(C.superficie, in: Capsule()).sombraE1().padding(10)
        }
        .clipShape(.rect(cornerRadius: M.rDestacada, style: .continuous))
        .sombraE2()
        .onAppear { encuadrar(); ubicacion.pedir() }
        .onChange(of: props.map(\.id)) { _, _ in elegida = nil; encuadrar() }
    }

    /// Todas las propiedades a la vista, con margen, y nunca más cerca que unas 12 cuadras.
    private func encuadrar() {
        let ps = conLugar.compactMap { p -> CLLocationCoordinate2D? in
            guard let a = p.lat, let o = p.lng else { return nil }
            return CLLocationCoordinate2D(latitude: a, longitude: o)
        }
        guard let primera = ps.first else { posicion = .userLocation(fallback: .automatic); return }
        var minLat = primera.latitude, maxLat = primera.latitude, minLng = primera.longitude, maxLng = primera.longitude
        for c in ps {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let centro = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.012), longitudeDelta: max((maxLng - minLng) * 1.3, 0.012))
        posicion = .region(MKCoordinateRegion(center: centro, span: span))
    }

    /// «a 4 cuadras de vos», «a 12 km de vos» (cuadras de 100 m).
    private func cuadras(_ p: Propiedad) -> String? {
        guard let yo = ubicacion.ultima, let lat = p.lat, let lng = p.lng else { return nil }
        let m = yo.distance(from: CLLocation(latitude: lat, longitude: lng))
        if m > 5000 { return "a \(Formato.numero(Int((m / 1000).rounded()))) km de vos" }
        let c = max(1, Int((m / 100).rounded()))
        return "a \(c) \(c == 1 ? "cuadra" : "cuadras") de vos"
    }

    private func tarjeta(_ p: Propiedad) -> some View {
        HStack(spacing: 12) {
            Foto(url: p.miniatura).frame(width: 76, height: 76).clipShape(.rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.direccion ?? p.nombre).estilo(.subheadFuerte).foregroundStyle(C.texto).lineLimit(1)
                Text([p.precioTexto, p.ambientes.map { "\($0) amb" }, p.superficie.map { "\(Formato.numero(Int($0))) m²" }].compactMap { $0 }.joined(separator: " · "))
                    .estilo(.footnote).foregroundStyle(C.texto2).lineLimit(1)
                if let c = cuadras(p) { Text(c).estilo(.footnote).foregroundStyle(C.okTinta) }
                HStack(spacing: 8) {
                    Button { compartir(p) } label: { Label("Mandar", systemImage: "square.and.arrow.up") }.buttonStyle(BotonTonal(alto: 30))
                    Button("Ficha") { estado.abrir(AFichaPropiedad(id: p.id)) }.buttonStyle(BotonTonal(alto: 30))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(C.superficie, in: .rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
    }

    /// «USD 172 k», «ARS 612 k».
    static func corto(_ p: Propiedad) -> String {
        guard let n = p.precio, p.precioOculto != true else { return "Consultar" }
        let m = p.moneda ?? "USD"
        if n >= 1_000_000 { return "\(m) \(String(format: "%.1f", n / 1_000_000).replacingOccurrences(of: ".", with: ",")) M" }
        if n >= 1000 { return "\(m) \(Int(n / 1000)) k" }
        return "\(m) \(Int(n))"
    }
}

/// Mandar la ficha: el logo de WhatsApp en un círculo de 36 pt, visible en cada fila y en la tarjeta del mapa
/// (deslizar y mantener apretado siguen andando, pero no se descubren solos).
struct BotonMandar: View {
    var mandar: () -> Void
    var body: some View {
        Button(action: mandar) {
            Image("LogoWhatsApp").resizable().scaledToFit().frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(Color(hex: 0x25D366).opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(Presionable())
        .accessibilityLabel("Mandar la ficha")
    }
}
