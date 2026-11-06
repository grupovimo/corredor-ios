import AuthenticationServices
import SwiftUI

/// Equipo: las personas con su rol (el dueño lo cambia con «Deshacer»), invitar por link, las
/// invitaciones pendientes y las licencias.
struct Equipo: View {
    @Environment(Estado.self) private var estado
    @State private var equipo: [Miembro] = []
    @State private var invitaciones: [Invitacion] = []
    @State private var licencias: [Licencia] = []
    @State private var invitando = false
    @State private var mail = ""
    @State private var rol = "agente"
    @State private var licencia = false

    struct Invitacion: Codable, Identifiable { var id: String; var email: String; var rol: String; var venceEn: Date?; var link: String? }

    var body: some View {
        List {
            Section("Personas") {
                ForEach(equipo) { m in
                    HStack(spacing: 12) {
                        Text(Formato.iniciales(m.completo)).font(Estilo(tamano: 14, peso: .bold, relativo: .footnote).font).frame(width: 40, height: 40).background(C.hundida, in: Circle())
                        VStack(alignment: .leading) {
                            Text(m.completo).estilo(.filaLista)
                            Text("\(ElegirInmobiliaria.rol(m.rol ?? "")) · \(Formato.cantidad(m.propiedades ?? 0, "propiedad", "propiedades"))").estilo(.footnote).foregroundStyle(C.texto2)
                        }
                        Spacer()
                        if estado.esDuenio && m.usuarioId != estado.usuario?.id {
                            Menu {
                                ForEach(["duenio", "agente", "lector"], id: \.self) { r in
                                    Button(ElegirInmobiliaria.rol(r)) { Task { await cambiarRol(m, r) } }
                                }
                                Divider()
                                Button("Sacar del equipo", role: .destructive) { Task { await sacar(m) } }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(C.accion) }.accessibilityLabel("Más acciones")
                        }
                    }
                }
            }
            if !invitaciones.isEmpty {
                Section("Invitaciones pendientes") {
                    ForEach(invitaciones) { i in
                        HStack {
                            VStack(alignment: .leading) { Text(i.email).estilo(.filaLista); Text(ElegirInmobiliaria.rol(i.rol)).estilo(.footnote).foregroundStyle(C.texto2) }
                            Spacer()
                            if let l = i.link.flatMap(URL.init(string:)) { ShareLink(item: l) { Image(systemName: "square.and.arrow.up") } }
                        }
                        .swipeActions { Button("Anular", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/invitaciones/\(i.id)"); await cargar() } catch { estado.avisar(error) } } } }
                    }
                }
            }
            Section("Licencias y ausencias") {
                ForEach(licencias) { l in
                    VStack(alignment: .leading) {
                        Text("\(l.usuarioNombre ?? "") · \(l.tipo?.capitalized ?? "Licencia")").estilo(.filaLista)
                        Text("Del \(Fecha.dia(l.desde).map { Formato.diaCompleto($0) } ?? l.desde) al \(Fecha.dia(l.hasta).map { Formato.diaCompleto($0) } ?? l.hasta)").estilo(.footnote).foregroundStyle(C.texto2)
                    }
                    .swipeActions { Button("Quitar", role: .destructive) { Task { do { try await estado.api.hacer("DELETE", "/v1/licencias/\(l.id)"); await cargar() } catch { estado.avisar(error) } } } }
                }
                Button { licencia = true } label: { Label("Cargar una licencia", systemImage: "plus") }
            }
        }
        .scrollContentBackground(.hidden).background(FondoApp())
        .pantallaApilada("Equipo")
        .toolbar { if estado.esDuenio { Button { invitando = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Invitar") } }
        .task(id: estado.version) { await cargar() }
        .alert("Invitar a alguien", isPresented: $invitando) {
            TextField("Mail", text: $mail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Como agente") { rol = "agente"; Task { await invitar() } }
            Button("Como lector") { rol = "lector"; Task { await invitar() } }
            Button("Como dueño") { rol = "duenio"; Task { await invitar() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Le llega un mail con el link para entrar.") }
        .sheet(isPresented: $licencia) { NuevaLicencia(equipo: equipo).presentationDetents([.medium]) }
    }

    private func cargar() async {
        equipo = (try? await estado.api.get("/v1/equipo")) ?? []
        if estado.esDuenio { invitaciones = (try? await estado.api.get("/v1/invitaciones")) ?? [] }
        let hoy = Formato.diaISO(Date())
        licencias = (try? await estado.api.get("/v1/licencias", query: [.init(name: "desde", value: hoy), .init(name: "hasta", value: Formato.diaISO(Date().addingTimeInterval(180 * 86400)))])) ?? []
    }

    private func invitar() async {
        struct Cuerpo: Encodable { var email: String; var rol: String }
        do {
            let i: Invitacion = try await estado.api.enviar("POST", "/v1/invitaciones", Cuerpo(email: mail, rol: rol))
            estado.avisar("Invitación mandada a \(mail)")
            mail = ""
            if let l = i.link { UIPasteboard.general.string = l }
            await cargar()
        } catch { estado.avisar(error) }
    }

    private func cambiarRol(_ m: Miembro, _ r: String) async {
        struct Cuerpo: Encodable { var rol: String }
        let antes = m.rol ?? "agente"
        do {
            try await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: r))
            await cargar()
            estado.avisar("\(m.nombre ?? "") ahora es \(ElegirInmobiliaria.rol(r).lowercased())") {
                Task { do { try await estado.api.hacer("PATCH", "/v1/equipo/\(m.usuarioId)", Cuerpo(rol: antes)); await cargar() } catch { estado.avisar(error) } }
            }
        } catch { estado.avisar(error) }
    }

    private func sacar(_ m: Miembro) async {
        do {
            try await estado.api.hacer("DELETE", "/v1/equipo/\(m.usuarioId)")
            estado.avisar("\(m.completo) ya no está en el equipo")
            await cargar()
        } catch { estado.avisar(error) }
    }
}

/// Cargar una licencia o ausencia (la propia; el dueño, la de cualquiera).
struct NuevaLicencia: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    var equipo: [Miembro]
    @State private var quien = ""
    @State private var tipo = "vacaciones"
    @State private var desde = Date()
    @State private var hasta = Date().addingTimeInterval(7 * 86400)

    var body: some View {
        NavigationStack {
            Form {
                if estado.esDuenio {
                    Picker("Quién", selection: $quien) { ForEach(equipo) { Text($0.completo).tag($0.usuarioId) } }
                }
                Picker("Tipo", selection: $tipo) { Text("Vacaciones").tag("vacaciones"); Text("Licencia").tag("licencia"); Text("Enfermedad").tag("enfermedad"); Text("Trámite").tag("tramite") }
                DatePicker("Desde", selection: $desde, displayedComponents: .date)
                DatePicker("Hasta", selection: $hasta, in: desde..., displayedComponents: .date)
            }
            .navigationTitle("Licencia").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cargar") {
                        Task {
                            struct Cuerpo: Encodable { var usuarioId: String; var tipo: String; var desde: String; var hasta: String }
                            do {
                                try await estado.api.hacer("POST", "/v1/licencias", Cuerpo(usuarioId: quien.isEmpty ? (estado.usuario?.id ?? "") : quien, tipo: tipo, desde: Formato.diaISO(desde), hasta: Formato.diaISO(hasta)))
                                estado.version += 1
                                cerrar()
                            } catch { estado.avisar(error) }
                        }
                    }
                }
            }
        }
        .onAppear { quien = estado.usuario?.id ?? "" }
    }
}
