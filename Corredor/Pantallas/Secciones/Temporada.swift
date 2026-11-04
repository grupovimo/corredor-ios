import SwiftUI

// Temporada y emprendimientos: no los dibuja el handoff; se arman con sus piezas.

struct ReservaTemporada: Codable, Identifiable, Hashable {
    var id: String
    var propiedadId: String?
    var propiedadTitulo: String?
    var contactoId: String?
    var contactoNombre: String?
    var huespedNombre: String?
    var huespedTelefono: String?
    var huespedes: Int?
    var entrada: String
    var salida: String
    var estado: String?
    var monto: Double?
    var moneda: String?
    var sena: Double?
    var saldo: Double?
    var noches: Int?
    var notas: String?
    var quien: String { huespedNombre ?? contactoNombre ?? "Huésped" }
}

/// Temporada: las reservas por fecha de entrada (hoy, próximas, pasadas), con check-in, saldo y WhatsApp.
struct Temporada: View {
    @Environment(Estado.self) private var estado
    @State private var reservas: [ReservaTemporada]?
    @State private var filtro = 0
    @State private var nueva = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Segmentado(opciones: [(0, "Próximas"), (1, "Adentro"), (2, "Pasadas")], elegido: $filtro)
                if let reservas {
                    let hoy = Formato.diaISO(Date())
                    let l = reservas.filter {
                        switch filtro {
                        case 0: return $0.entrada >= hoy
                        case 1: return $0.entrada <= hoy && $0.salida >= hoy
                        default: return $0.salida < hoy
                        }
                    }
                    if l.isEmpty { EstadoVacio(icono: "beach.umbrella", titulo: "No hay reservas acá", accion: estado.escribe ? ("Nueva reserva", { nueva = true }) : nil).padding(.top, 30) }
                    VStack(spacing: 0) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, r in fila(r, primera: i == 0) }
                    }
                    .tarjeta()
                } else { EsqueletoFilas(filas: 5) }
            }
            .padding(16)
        }
        .refreshable { await cargar() }
        .pantallaApilada("Temporada")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nueva = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nueva reserva") } }
        .task(id: estado.version) { await cargar() }
        .sheet(isPresented: $nueva) { NuevaReservaTemporada() }
    }

    private func fila(_ r: ReservaTemporada, primera: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.quien).estilo(.filaLista).foregroundStyle(C.texto)
                Text("\(r.propiedadTitulo ?? "") · \(Self.rango(r)) · \(Formato.cantidad(r.huespedes ?? 1, "persona", "personas"))").estilo(.footnote).foregroundStyle(C.texto2)
                if let s = r.saldo, s > 0 { Text("Saldo \(Formato.plata(s, r.moneda ?? "ARS"))").font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(C.errorTinta) }
            }
            Spacer()
            Menu {
                Button { Afuera.whatsapp(r.huespedTelefono) } label: { Label("WhatsApp", systemImage: "bubble.left") }
                if estado.escribe {
                    Button { Task { await checkin(r) } } label: { Label("Hacer el check-in", systemImage: "key") }
                    Button { Task { await poner(r, "confirmada") } } label: { Label("Confirmar", systemImage: "checkmark") }
                    Button(role: .destructive) { Task { await poner(r, "cancelada") } } label: { Label("Cancelar", systemImage: "xmark") }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(C.accion) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(C.linea).frame(height: 0.5) } }
    }

    static func rango(_ r: ReservaTemporada) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d MMM"
        return "\(Fecha.dia(r.entrada).map { f.string(from: $0) } ?? r.entrada) al \(Fecha.dia(r.salida).map { f.string(from: $0) } ?? r.salida)"
    }

    private func cargar() async {
        reservas = ((try? await estado.api.get("/v1/temporada/reservas", query: [.init(name: "limite", value: "500")])) ?? [ReservaTemporada]()).sorted { $0.entrada < $1.entrada }
    }

    private func checkin(_ r: ReservaTemporada) async {
        struct C: Encodable { var saldo: Double?; var deposito: Double? }
        do {
            try await estado.api.hacer("PUT", "/v1/temporada/reservas/\(r.id)/checkin", C(saldo: r.saldo, deposito: nil))
            Haptico.exito()
            estado.avisar("Check-in de \(r.quien) hecho")
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func poner(_ r: ReservaTemporada, _ e: String) async {
        struct C: Encodable { var estado: String }
        do {
            try await estado.api.hacer("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: e))
            estado.avisar(e == "cancelada" ? "Reserva cancelada" : "Reserva confirmada") {
                Task { try? await estado.api.hacer("PATCH", "/v1/temporada/reservas/\(r.id)", C(estado: r.estado ?? "pendiente")); await cargar() }
            }
            await cargar()
        } catch { estado.avisar(error) }
    }
}

/// Una reserva de temporada nueva: la propiedad, el huésped, las fechas, el monto y la seña.
struct NuevaReservaTemporada: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var prop: Propiedad?
    @State private var nombre = ""
    @State private var telefono = ""
    @State private var huespedes = 2
    @State private var entrada = Date()
    @State private var salida = Date().addingTimeInterval(7 * 86400)
    @State private var monto: Double?
    @State private var sena: Double?
    @State private var moneda = "USD"
    @State private var elegir = false

    var body: some View {
        NavigationStack {
            Form {
                Button { elegir = true } label: { LabeledContent("Propiedad", value: prop?.nombre ?? "Elegí") }
                TextField("Huésped", text: $nombre)
                TextField("Teléfono", text: $telefono).keyboardType(.phonePad)
                Stepper("\(huespedes) personas", value: $huespedes, in: 1...30)
                DatePicker("Entrada", selection: $entrada, displayedComponents: .date)
                DatePicker("Salida", selection: $salida, in: entrada..., displayedComponents: .date)
                Picker("Moneda", selection: $moneda) { Text("USD").tag("USD"); Text("ARS").tag("ARS") }.pickerStyle(.segmented)
                TextField("Total", value: $monto, format: .number).keyboardType(.decimalPad)
                TextField("Seña", value: $sena, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Reserva de temporada").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reservar") {
                        Task {
                            struct C: Encodable {
                                var propiedadId: String?; var huespedNombre: String; var huespedTelefono: String?; var huespedes: Int
                                var entrada: String; var salida: String; var estado = "confirmada"; var monto: Double?; var moneda: String; var sena: Double?
                            }
                            do {
                                try await estado.api.hacer("POST", "/v1/temporada/reservas", C(propiedadId: prop?.id, huespedNombre: nombre, huespedTelefono: telefono.nonEmpty, huespedes: huespedes,
                                                                                              entrada: Formato.diaISO(entrada), salida: Formato.diaISO(salida), monto: monto, moneda: moneda, sena: sena))
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                    .disabled(prop == nil || nombre.isEmpty)
                }
            }
            .sheet(isPresented: $elegir) { ElegirPropiedad { prop = $0; moneda = $0.moneda ?? moneda } }
        }
    }
}

struct EmprendimientoAPI: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var tipo: String?
    var estado: String?
    var descripcion: String?
    var direccion: String?
    var barrio: String?
    var avance: Double?
    var entrega: String?
    var desarrolladora: String?
    var precioDesde: Double?
    var moneda: String?
    var fotosUrl: [String]?
    var unidades: [Propiedad]?
}

/// Emprendimientos: la lista y, en cada uno, el avance, la entrega y sus unidades (con su estado).
struct Emprendimientos: View {
    @Environment(Estado.self) private var estado
    @State private var lista: [EmprendimientoAPI]?
    @State private var nuevo = false
    @State private var nombre = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let lista {
                    if lista.isEmpty { EstadoVacio(icono: "building", titulo: "Todavía no hay emprendimientos", accion: estado.escribe ? ("Cargar emprendimiento", { nuevo = true }) : nil).padding(.top, 40) }
                    ForEach(lista) { e in
                        NavigationLink(value: ASeccion(clave: "emprendimiento", id: e.id)) {
                            HStack(spacing: 12) {
                                Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.nombre).font(Estilo(tamano: 16, peso: .bold, relativo: .body).font).foregroundStyle(C.texto)
                                    Text([e.barrio, e.precioDesde.map { "desde \(Formato.plata($0, e.moneda ?? "USD"))" }].compactMap { $0 }.joined(separator: " · ")).estilo(.footnote).foregroundStyle(C.texto2)
                                    if let a = e.avance { ProgressView(value: a / 100).tint(C.oro).padding(.top, 4) }
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(10).tarjeta()
                        }
                        .buttonStyle(.plain)
                    }
                } else { EsqueletoFilas(filas: 3, miniatura: 72) }
            }
            .padding(16)
        }
        .pantallaApilada("Emprendimientos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { if estado.escribe { Button { nuevo = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuevo emprendimiento") } }
        .task(id: estado.version) { lista = (try? await estado.api.get("/v1/emprendimientos")) ?? lista ?? [] }
        .alert("Emprendimiento nuevo", isPresented: $nuevo) {
            TextField("Nombre", text: $nombre)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") {
                Task {
                    struct C: Encodable { var nombre: String; var tipo = "edificio"; var estado = "en_pozo" }
                    try? await estado.api.hacer("POST", "/v1/emprendimientos", C(nombre: nombre))
                    nombre = ""
                    estado.version += 1
                }
            }
        }
    }
}

/// Un emprendimiento: avance, entrega, desarrolladora y las unidades (cada una abre su ficha).
struct FichaEmprendimiento: View {
    @Environment(Estado.self) private var estado
    var id: String
    @State private var e: EmprendimientoAPI?
    @State private var unidades: [Propiedad] = []

    var body: some View {
        ScrollView {
            if let e {
                VStack(alignment: .leading, spacing: 16) {
                    Foto(url: e.fotosUrl?.first.flatMap(URL.init(string:))).frame(height: 200).clipShape(.rect(cornerRadius: M.rDestacada))
                    Text(e.nombre).estilo(.titulo).foregroundStyle(C.texto)
                    Text([e.direccion, e.barrio, e.desarrolladora].compactMap { $0 }.joined(separator: " · ")).estilo(.subhead).foregroundStyle(C.texto2)
                    if let a = e.avance {
                        TarjetaAvance(titulo: "Avance de obra", cifra: "\(Int(a)) %", avance: a / 100, degrade: [Color(hex: 0xE9AD44), Color(hex: 0xF2BB57)],
                                      pie: e.entrega.map { "Entrega: \($0)" } ?? "Sin fecha de entrega")
                    }
                    if let d = e.descripcion { Text(d).estilo(.body16).foregroundStyle(C.texto) }
                    TituloBloque(texto: "Unidades", cuenta: "\(unidades.count)")
                    VStack(spacing: 0) {
                        ForEach(Array(unidades.enumerated()), id: \.element.id) { i, p in
                            Button { estado.abrir(AFichaPropiedad(id: p.id)) } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(p.nombre).estilo(.filaLista).foregroundStyle(C.texto); Text(p.resumen).estilo(.footnote).foregroundStyle(C.texto2) }
                                    Spacer()
                                    let (chip, tono) = PropiedadesRaiz.chip(p, nil)
                                    Text(chip).font(Estilo(tamano: 12, peso: .bold, relativo: .caption).font).foregroundStyle(tono.tinta)
                                        .padding(.horizontal, 9).frame(height: 24).background(tono.fondo, in: Capsule())
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(C.linea).frame(height: 0.5) } }
                        }
                    }
                    .tarjeta()
                }
                .padding(16)
            } else { ProgressView().padding(.top, 60) }
        }
        .pantallaApilada(e?.nombre ?? "Emprendimiento")
        .task(id: estado.version) {
            e = try? await estado.api.get("/v1/emprendimientos/\(id)")
            unidades = (try? await estado.api.get("/v1/emprendimientos/\(id)/unidades")) ?? e?.unidades ?? []
        }
    }
}
