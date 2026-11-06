import SwiftUI

extension Documentos {
    /// El acta de entrega o devolución como la imprime la web (14): el membrete con la matrícula, el
    /// título, la dirección y la fecha, las partes por nombre, las observaciones, la tabla de los ítems
    /// congelados al labrarla (`acta.items`: ambiente, ítem, cantidad, nota, estado —en mayúsculas si es
    /// regular o malo— y el código de la foto F-01…) y las tres firmas.
    static func actaFirmada(_ a: Acta, direccion: String, barrio: String?, inmobiliaria inmo: InmobiliariaActa?,
                            inquilino: String?, propietario: String?, firmaInmobiliaria: String, api: Api) async -> URL? {
        var nombreInmo = inmo?.nombre
        if nombreInmo == nil { nombreInmo = await inmobiliaria(api)?.nombre }
        let entrada = a.tipo != "salida"
        var lugar = direccion
        if let b = barrio?.nonEmpty { lugar += " · \(b)" }
        if let f = a.fecha.flatMap(Fecha.dia) { lugar += " · \(Formato.fechaLarga(f))" }
        var intro: [String] = []
        if let m = inmo?.matricula { intro.append(m) }
        var partes: [String] = []
        if let i = inquilino?.nonEmpty { partes.append("Inquilina/o: \(i).") }
        if let p = propietario?.nonEmpty { partes.append("Propietario: \(p).") }
        if !partes.isEmpty { intro.append(partes.joined(separator: " ")) }
        var bloques: [Documento.Bloque] = []
        if !intro.isEmpty { bloques.append(.init(titulo: nil, texto: intro.joined(separator: "\n"))) }
        if let o = a.observaciones?.nonEmpty { bloques.append(.init(titulo: "Observaciones", texto: o)) }
        let filas: [(String, String)] = Firmas.filas(a.items ?? []).map { f in
            let ojo = f.item.estado == "regular" || f.item.estado == "malo"
            let est = ojo ? Inv.nombre(f.item.estado).uppercased() : Inv.nombre(f.item.estado)
            return ("\(f.item.ambiente) · \(Firmas.textoItem(f.item))", "\(est) · \(f.codigo)")
        }
        if filas.isEmpty {
            bloques.append(.init(titulo: "Ítems", texto: "El inventario estaba vacío cuando se labró el acta."))
        } else {
            bloques.append(.init(titulo: "Ambiente · ítem — estado · foto", filas: filas))
        }
        let firmas = [("inquilino", "Inquilina/o"), ("propietario", "Propietario"), ("inmobiliaria", firmaInmobiliaria)].map { k, n in
            Documento.Firma(parte: n, nombre: a.firmas?[k]?.nombre, trazo: a.firmas?[k]?.trazo)
        }
        let d = Documento(titulo: entrada ? "Acta de entrega e inventario" : "Acta de devolución e inventario",
                          subtitulo: lugar, numero: "ACTA · \(Inv.numerica(a.fecha))", bloques: bloques, firmas: firmas,
                          pie: "Al firmar, las partes aceptan el estado de cada ambiente tal como quedó registrado, con sus fotos. Hecha con Corredor")
        return Impresor.pdf(d, inmobiliaria: nombreInmo ?? "Corredor", nombre: "Acta \(direccion)")
    }
}
