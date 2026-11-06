import SwiftUI

// MARK: - Expensas

/// Expensas: los meses liquidados (y el que se está cargando) con su total, y el detalle del elegido:
/// cada unidad con su recibo (A4 para imprimir y link público) y mandarlos por mail o por WhatsApp.
struct PestanaExpensasConsorcio: View {
    @Environment(Estado.self) private var estado
    var c: ConsorcioAPI
    var periodos: [PeriodoAPI]
    @State private var elegido: String?
    @State private var ficha: PeriodoAPI?
    @State private var error: ErrorApi?
    @State private var mandando = false
    @State private var porWhatsApp = false
    @State private var imprimiendo: String?
    @State private var previo: ArchivoPrevio?

    private static let estados: [String: (String, Tono)] = ["borrador": ("Cargando gastos", .oro), "liquidada": ("Liquidada", .verde), "cerrada": ("Cerrada", .neutro)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if periodos.isEmpty {
                EstadoVacio(icono: "doc.text", titulo: "Todavía no liquidaste expensas",
                            texto: "Cada mes cargás los gastos, mirás cómo se reparten y emitís. Acá quedan los meses liquidados con el recibo de cada unidad.",
                            accion: estado.escribe ? ("Liquidar \(Cons.nombreMes(Cons.aLiquidar(periodos).periodo))", { estado.abrir(ALiquidarConsorcio(consorcio: c.id)) }) : nil)
            } else {
                meses
                if let ficha { detalle(ficha) } else if let error {
                    EstadoError(que: "el período", error: error) { Task { await cargar() } }
                } else if elegidoID != nil { EsqueletoFilas(filas: 4) }
            }
        }
        .task(id: "\(estado.version)-\(elegidoID ?? "")") { await cargar() }
        .vistaPrevia($previo)
    }

    /// El elegido o, si no, el último liquidado.
    private var elegidoID: String? { elegido ?? periodos.first { $0.estado != "borrador" }?.id }

    private var meses: some View {
        BloqueConsorcio(titulo: "Meses") {
            ForEach(Array(periodos.enumerated()), id: \.element.id) { i, p in
                let e = Self.estados[p.estado] ?? (p.estado, Tono.neutro)
                Button {
                    if p.estado == "borrador" { estado.abrir(ALiquidarConsorcio(consorcio: c.id, periodo: p.periodo)) } else { elegido = p.id }
                } label: {
                    RenglonConsorcio(primero: i == 0) {
                        DosLineasConsorcio(titulo: Cons.mesConAnio(p.periodo), detalle: p.estado == "borrador" ? "\(Formato.plata(p.cargado ?? 0)) cargados" : Formato.plata(p.total ?? 0))
                        ChipConsorcio(texto: e.0, tono: e.1)
                        Chevron()
                    }
                    .background(elegidoID == p.id ? C.hundida : Color.clear)
                }
                .buttonStyle(Presionable())
                .accessibilityAddTraits(elegidoID == p.id ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func detalle(_ f: PeriodoAPI) -> some View {
        let ls = (f.liquidaciones ?? []).sorted { Cons.porUnidad($0.unidad, $1.unidad) }
        let gastos = f.gastos?.count ?? 0
        BloqueConsorcio(titulo: "\(Cons.mesConAnio(f.periodo)) · \(Formato.plata(f.total ?? 0))", accion: ("Imprimir", { Task { await imprimir(f, unidad: nil) } })) {
            RenglonConsorcio(primero: true) {
                Text("\(Cons.plural(ls.count, "unidad", "unidades")) · \(Cons.plural(gastos, "gasto", "gastos"))\((f.fondoTotal ?? 0) > 0 ? " · fondo \(Formato.plata(f.fondoTotal ?? 0))" : "")")
                    .estilo(.footnote).foregroundStyle(C.texto2)
            }
            if estado.escribe {
                RenglonConsorcio {
                    Button { Task { await whatsapp(f) } } label: { Label(porWhatsApp ? "Mandando…" : "Por WhatsApp", systemImage: "bubble.left") }.disabled(porWhatsApp)
                    Spacer()
                    Button { Task { await enviar(f) } } label: { Label(mandando ? "Mandando…" : "Mandar por mail", systemImage: "envelope") }.disabled(mandando)
                }
                .font(Estilo.footnoteFuerte.font).foregroundStyle(C.accion).buttonStyle(.borderless)
            }
            ForEach(ls) { l in fila(f, l) }
            if f.estado == "liquidada" && estado.escribe {
                RenglonConsorcio {
                    Button("Cerrar el período") { Task { await cerrarPeriodo(f) } }.font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto2).buttonStyle(.borderless)
                }
            }
        }
    }

    private func fila(_ f: PeriodoAPI, _ l: LiquidacionExpensas) -> some View {
        RenglonConsorcio {
            Text(l.unidad).font(Estilo.filaLista.font).foregroundStyle(C.texto).frame(minWidth: 44, alignment: .leading)
            DosLineasConsorcio(titulo: l.propietario ?? "Sin propietario", detalle: [l.telefono, l.email].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty ?? "sin contacto · va impresa")
            Text(Cons.cifra(l.total)).font(Estilo.footnoteFuerte.font).foregroundStyle(C.texto)
            if estado.escribe {
                Button { Task { await link(l) } } label: { Image(systemName: "link").frame(width: 34, height: 34) }
                    .accessibilityLabel("Copiar el link del recibo de \(l.unidad)").buttonStyle(.borderless)
            }
            Button { Task { await imprimir(f, unidad: l.unidadId) } } label: {
                if imprimiendo == l.unidadId { ProgressView().frame(width: 34, height: 34) } else { Image(systemName: "printer").frame(width: 34, height: 34) }
            }
            .accessibilityLabel("Imprimir el recibo de \(l.unidad)").buttonStyle(.borderless)
        }
    }

    private func cargar() async {
        guard let id = elegidoID else { ficha = nil; return }
        do {
            ficha = try await estado.api.get("/v1/consorcios/\(c.id)/periodos/\(id)")
            error = nil
        } catch let e as ErrorApi {
            error = e
            ficha = nil
        } catch {}
    }

    private func enviar(_ f: PeriodoAPI) async {
        mandando = true
        defer { mandando = false }
        do {
            let r: EnvioMailExpensas = try await estado.api.enviar("POST", "/v1/consorcios/\(c.id)/periodos/\(f.id)/enviar", [String: String]())
            let sin = r.sinEmail ?? []
            estado.avisar("\(Cons.plural(r.encolados, "recibo sale", "recibos salen")) por mail\(sin.isEmpty ? "" : " · \(sin.count) sin mail (\(sin.joined(separator: ", ")))")")
        } catch {
            let t = (error as? ErrorApi)?.detalle ?? "Probá de nuevo."
            estado.sugerir("No se mandaron · \(t)", "Reintentar") { Task { await enviar(f) } }
        }
    }

    private func whatsapp(_ f: PeriodoAPI) async {
        porWhatsApp = true
        defer { porWhatsApp = false }
        do {
            let w = try await ConsorcioWhatsApp.liquidaciones(estado.api, consorcio: c.id, periodo: f.id)
            if w.sinWhatsApp && w.enviadas == 0 {
                estado.sugerir("Conectá el WhatsApp de la inmobiliaria para mandarlas por ahí", "Conectar", ASeccion(clave: "integraciones"))
                return
            }
            let faltan = w.sinTelefono + w.fallidas
            estado.avisar("\(Cons.plural(w.enviadas, "recibo sale", "recibos salen")) por WhatsApp\(faltan.isEmpty ? "" : " · \(faltan.count) sin WhatsApp (\(faltan.joined(separator: ", ")))")")
        } catch {
            estado.sugerir("No se mandaron · WhatsApp no respondió. Probá de nuevo en un rato.", "Reintentar") { Task { await whatsapp(f) } }
        }
    }

    private func link(_ l: LiquidacionExpensas) async {
        do {
            let r: LinkConsorcio = try await estado.api.enviar("POST", "/v1/consorcios/\(c.id)/liquidaciones/\(l.id)/link", [String: String]())
            Cons.copiar(r.url)
            estado.avisar("Link del recibo de \(l.unidad) copiado.")
        } catch { estado.avisar(error) }
    }

    private func imprimir(_ f: PeriodoAPI, unidad: String?) async {
        imprimiendo = unidad ?? "todas"
        defer { imprimiendo = nil }
        do {
            let u = try await Documentos.expensas(consorcio: c.id, periodo: f.id, unidad: unidad, api: estado.api)
            previo = ArchivoPrevio(url: u)
        } catch { estado.avisar(error) }
    }

    private func cerrarPeriodo(_ f: PeriodoAPI) async {
        do {
            try await estado.api.hacer("POST", "/v1/consorcios/\(c.id)/periodos/\(f.id)/cerrar")
            estado.avisar("Período cerrado")
            estado.version += 1
        } catch { estado.avisar(error) }
    }
}
