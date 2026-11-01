import Foundation

/// Spreadsheet-friendly exports (Excel and Numbers open them directly).
enum CSV {
    static func medidas(_ medidas: [Medida]) -> String {
        var filas = ["Nombre,Metros,Centimetros"]
        for m in medidas {
            filas.append("\(campo(m.nombre)),\(numero(m.metros)),\(numero(m.metros * 100, decimales: 1))")
        }
        return filas.joined(separator: "\n") + "\n"
    }

    static func plano(_ plano: PlanoPlanta) -> String {
        var filas = ["Elemento,Tipo,Largo/Ancho (m),Alto (m),Fondo (m),Elevacion (m),Area (m2)"]
        for (i, muro) in plano.muros.enumerated() {
            filas.append("Muro \(i + 1),Muro,\(numero(muro.longitud)),\(numero(muro.altura)),,,\(numero(muro.area))")
        }
        for tipo in TipoAbertura.allCases {
            for (i, a) in plano.aberturas.filter({ $0.tipo == tipo }).enumerated() {
                filas.append("\(tipo.nombre) \(i + 1),\(tipo.nombre),\(numero(a.ancho)),\(numero(a.altura)),,\(numero(a.elevacion)),\(numero(a.ancho * a.altura))")
            }
        }
        for m in plano.muebles {
            filas.append("\(campo(m.nombre)),Mueble,\(numero(m.ancho)),\(numero(m.alto)),\(numero(m.fondo)),,")
        }
        filas.append("Piso,Total,,,,,\(numero(plano.area))")
        filas.append("Perimetro,Total,\(numero(plano.perimetro)),,,,")
        filas.append("Muros sin huecos,Total,,,,,\(numero(plano.areaMurosNeta))")
        return filas.joined(separator: "\n") + "\n"
    }

    static func numero(_ v: Double, decimales: Int = 3) -> String {
        String(format: "%.\(decimales)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    /// Quotes a text field when it contains a comma, quote or line break.
    static func campo(_ texto: String) -> String {
        guard texto.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return texto }
        return "\"" + texto.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
