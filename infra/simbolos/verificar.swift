// Verifica que cada Image(systemName: "…") / systemImage: "…" de la app exista en SF Symbols.
// Un nombre que no existe no dibuja nada (sin error ni aviso): así salieron vacíos el botón «Captar»
// de MIRA y el círculo de «quedó captada» (house.badge.plus). Uso: swift infra/simbolos/verificar.swift Corredor
import AppKit
import Foundation

let raiz = CommandLine.arguments.dropFirst().first ?? "Corredor"
// Lo que sigue a systemName:/systemImage:/icono: en el renglón (también los ternarios «x ? "a" : "b"»).
let patron = try! NSRegularExpression(pattern: #"(?:systemName|systemImage|icono):\s*([^\n]*)"#)
let literal = try! NSRegularExpression(pattern: #""([a-z0-9]+(?:\.[a-z0-9]+)*)""#)
var faltan: [String: [String]] = [:]
let fm = FileManager.default
let e = fm.enumerator(atPath: raiz)!
while let f = e.nextObject() as? String {
    guard f.hasSuffix(".swift"), let s = try? String(contentsOfFile: raiz + "/" + f, encoding: .utf8) else { continue }
    for m in patron.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
        var resto = String(s[Range(m.range(at: 1), in: s)!])
        // Hasta el cierre de la expresión (un «{» abre otra cosa).
        if let i = resto.firstIndex(of: "{") { resto = String(resto[..<i]) }
        for l in literal.matches(in: resto, range: NSRange(resto.startIndex..., in: resto)) {
            let n = String(resto[Range(l.range(at: 1), in: resto)!])
            // Un ícono es lo primero o una rama de un ternario («x ? "a" : "b"»); lo demás (comparaciones,
            // argumentos como contains("pdf") o clave: "web") no.
            let crudo = String(resto[..<Range(l.range, in: resto)!.lowerBound])
            let antes = crudo.trimmingCharacters(in: .whitespaces)
            guard antes.isEmpty || antes.hasSuffix("?") || crudo.hasSuffix(" : ") || antes.hasSuffix("??") else { continue }
            if NSImage(systemSymbolName: n, accessibilityDescription: nil) == nil { faltan[n, default: []].append(f) }
        }
    }
}
if faltan.isEmpty { print("SF Symbols: todos existen"); exit(0) }
for (n, fs) in faltan.sorted(by: { $0.key < $1.key }) { print("no existe: \(n) — \(Set(fs).sorted().joined(separator: ", "))") }
exit(1)
