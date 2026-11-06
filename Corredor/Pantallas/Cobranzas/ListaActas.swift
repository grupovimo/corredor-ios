import SwiftUI

/// Una propiedad de alquiler o temporada con su inventario y sus actas (web: (app)/inventarios).
struct FilaInventario: Identifiable, Hashable {
    struct ActaCorta: Hashable { var id: String; var fecha: String?; var firmas: Int }
    var id: String
    var direccion: String
    var barrio: String?
    var foto: URL?
    var items: Int
    var ambientes: Int
    var entrada: ActaCorta?
    var salida: ActaCorta?
}

/// Inventarios: las propiedades de alquiler y temporada (con o sin inventario), cada una con su foto,
/// cuántos ambientes e ítems tiene, sus actas en chips y el botón de lo que toca (Devolución, Recorrer
/// o Empezar). Vistas: Todas, Con inventario, Sin inventario y Para devolver; «Para hacer» lleva a las
/// actas con firmas pendientes.
struct ListaActas: View {
    @Environment(Estado.self) private var estado
    @State private var filas: [FilaInventario]?
    @State private var error: ErrorApi?
    @State private var vista = "todas"
    @State private var elegir = false

    private var cuenta: [String: Int] {
        let l = filas ?? []
        return ["todas": l.count, "con": l.filter { $0.items > 0 }.count, "sin": l.filter { $0.items == 0 }.count,
                "devolver": l.filter { $0.entrada != nil && $0.salida == nil }.count]
    }

    private var visibles: [FilaInventario] {
        (filas ?? []).filter { f in
            switch vista {
            case "con": return f.items > 0
            case "sin": return f.items == 0
            case "devolver": return f.entrada != nil && f.salida == nil
            default: return true
            }
        }
    }

    private var sinFirmar: [FilaInventario] {
        (filas ?? []).filter { f in (f.entrada.map { $0.firmas < 3 } ?? false) || (f.salida.map { $0.firmas < 3 } ?? false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Formato.sinViudas("Se hace caminando: un ambiente por pantalla, y el acta sale sola.")).estilo(.subhead).foregroundStyle(C.texto2)
                if filas != nil {
                    chips
                    if !sinFirmar.isEmpty { paraHacer }
                    if visibles.isEmpty {
                        EstadoVacio(icono: "checklist", titulo: vista == "devolver" ? "No hay devoluciones pendientes" : "Todavía no hay inventarios",
                                    texto: "El inventario se arma en la entrega: ambiente por ambiente, con foto y estado de cada ítem.",
                                    accion: estado.escribe ? ("Elegir una propiedad", { elegir = true }) : nil)
                            .padding(.top, 24)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(visibles) { f in fila(f) }
                        }
                    }
                } else if let error {
                    EstadoError(que: "los inventarios", error: error) { Task { await cargar() } }
                } else {
                    EsqueletoFilas(filas: 5)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Inventarios")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if estado.escribe {
                Button { elegir = true } label: { Image(systemName: "plus") }.accessibilityLabel("Elegir una propiedad")
            }
        }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $elegir) { ElegirPropiedad { estado.abrir(AInventario(id: $0.id)) } }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([("todas", "Todas"), ("con", "Con inventario"), ("sin", "Sin inventario"), ("devolver", "Para devolver")], id: \.0) { k, t in
                    let on = vista == k
                    Button { withAnimation(.snappy(duration: 0.2)) { vista = k }; Haptico.seleccion() } label: {
                        Text("\(t) · \(cuenta[k] ?? 0)")
                            .font(Estilo(tamano: 14, peso: .semibold, relativo: .footnote).font)
                            .foregroundStyle(on ? C.sobreAccion : C.texto)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(on ? C.accion : C.superficie, in: Capsule())
                    }
                    .buttonStyle(Presionable())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var paraHacer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloBloque(texto: "Para hacer")
            VStack(spacing: 0) {
                ForEach(Array(sinFirmar.prefix(5).enumerated()), id: \.element.id) { i, f in
                    let a = (f.salida.map { $0.firmas < 3 } ?? false) ? f.salida : f.entrada
                    Button { if let a { estado.abrir(AFirmas(id: "\(f.id)/\(a.id)")) } } label: {
                        HStack(spacing: 12) {
                            IconoTono(icono: "signature", tono: .oro)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.direccion).estilo(.filaLista).foregroundStyle(C.texto)
                                Text("Acta con firmas pendientes").estilo(.footnote).foregroundStyle(C.avisoTinta)
                            }
                            Spacer()
                            Chevron()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(Presionable())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                }
            }
            .tarjeta()
        }
    }

    private func fila(_ f: FilaInventario) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { estado.abrir(AInventario(id: f.id)) } label: {
                HStack(spacing: 12) {
                    Group {
                        if let u = f.foto { Foto(url: u) } else {
                            ZStack { C.hundida; Image(systemName: "camera").font(.system(size: 20)).foregroundStyle(C.texto3) }
                        }
                    }
                    .frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.direccion).estilo(.filaLista).foregroundStyle(C.texto).lineLimit(2)
                        Text(f.items > 0 ? "\(Formato.cantidad(f.ambientes, "ambiente", "ambientes")) · \(Formato.cantidad(f.items, "ítem", "ítems"))"
                             : "Sin inventario\(f.barrio.map { " · \($0)" } ?? "")")
                            .estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Presionable())
            .accessibilityLabel("Recorrer \(f.direccion)")
            chipsActas(f)
            HStack(spacing: 8) {
                if f.entrada != nil && f.salida == nil {
                    Button { estado.abrir(ADevolucion(id: f.id)) } label: { Label("Devolución", systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(BotonHundido())
                }
                if f.items > 0 {
                    Button { estado.abrir(AInventario(id: f.id)) } label: { Label("Recorrer", systemImage: "figure.walk") }.buttonStyle(BotonHundido())
                } else if estado.escribe {
                    Button { estado.abrir(AInventario(id: f.id)) } label: { Label("Empezar", systemImage: "plus") }.buttonStyle(BotonAccion())
                }
            }
        }
        .padding(14)
        .tarjeta()
    }

    @ViewBuilder private func chipsActas(_ f: FilaInventario) -> some View {
        if f.entrada != nil || f.salida != nil {
            HStack(spacing: 6) {
                if let e = f.entrada {
                    chip("Entrega \(Inv.numerica(e.fecha))\(e.firmas < 3 ? " · faltan firmas" : "")", tono: e.firmas < 3 ? .oro : .verde) {
                        estado.abrir(AFirmas(id: "\(f.id)/\(e.id)"))
                    }
                }
                if let s = f.salida {
                    chip("Devolución \(Inv.numerica(s.fecha))", tono: s.firmas < 3 ? .oro : .verde) { estado.abrir(AFirmas(id: "\(f.id)/\(s.id)")) }
                } else if f.entrada != nil {
                    chip("Sin acta de devolución", tono: .azul, nil)
                }
            }
        }
    }

    private func chip(_ t: String, tono: Tono, _ hacer: (() -> Void)?) -> some View {
        Button { hacer?() } label: {
            Text(t).font(Estilo(tamano: 12, peso: .semibold, relativo: .caption).font).foregroundStyle(tono.tinta)
                .padding(.horizontal, 10).frame(minHeight: 26).background(tono.fondo, in: Capsule())
        }
        .buttonStyle(Presionable()).disabled(hacer == nil)
    }

    /// Como la web: las propiedades de alquiler y temporada, y de cada una su inventario y sus actas,
    /// todo en paralelo (con un grupo de tareas: nada de `async let`).
    private func cargar() async {
        let q: [URLQueryItem] = [.init(name: "operacion", value: "alquiler,temporario"), .init(name: "orden", value: "actualizada"), .init(name: "limite", value: "60")]
        let props: [Propiedad]
        do {
            props = try await estado.api.get("/v1/propiedades", query: q + [.init(name: "unidades", value: "no")])
        } catch let e as ErrorApi where !e.sinConexion {
            do { props = try await estado.api.get("/v1/propiedades", query: q) } catch let e as ErrorApi { if filas == nil { error = e }; return } catch { return }
        } catch let e as ErrorApi { if filas == nil { error = e }; return } catch { return }
        let api = estado.api
        var porId: [String: FilaInventario] = [:]
        await withTaskGroup(of: FilaInventario.self) { g in
            for p in props {
                g.addTask {
                    let items: [ItemInventario] = (try? await api.get("/v1/propiedades/\(p.id)/inventario")) ?? []
                    let actas: [Acta] = (try? await api.get("/v1/propiedades/\(p.id)/actas")) ?? []
                    let e = actas.first { $0.tipo == "entrada" }
                    let s = actas.first { $0.tipo == "salida" }
                    return FilaInventario(id: p.id, direccion: p.direccion ?? p.nombre, barrio: p.barrio, foto: urlDeFoto(p.fotosUrl?.first),
                                          items: items.count, ambientes: Set(items.map(\.ambiente)).count,
                                          entrada: e.map { .init(id: $0.id, fecha: $0.fecha, firmas: $0.firmas?.count ?? 0) },
                                          salida: s.map { .init(id: $0.id, fecha: $0.fecha, firmas: $0.firmas?.count ?? 0) })
                }
            }
            for await f in g { porId[f.id] = f }
        }
        filas = props.compactMap { porId[$0.id] }
        error = nil
    }
}
