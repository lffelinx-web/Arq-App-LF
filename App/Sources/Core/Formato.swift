import Foundation

/// Measurement units the user can pick in Ajustes.
enum Unidad: String, CaseIterable, Codable, Identifiable {
    case metros
    case centimetros
    case pies

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .metros: return "Metros"
        case .centimetros: return "Centímetros"
        case .pies: return "Pies y pulgadas"
        }
    }
}

enum Formato {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// A length in metres written in the chosen unit ("2.45 m", "245 cm", "8' 0\"").
    static func longitud(_ metros: Double, _ unidad: Unidad = .metros) -> String {
        switch unidad {
        case .metros:
            return String(format: "%.2f m", locale: posix, metros)
        case .centimetros:
            return String(format: "%.0f cm", locale: posix, metros * 100)
        case .pies:
            let pulgadasTotales = (metros / 0.0254).rounded()
            let pies = Int(pulgadasTotales / 12)
            let pulgadas = Int(pulgadasTotales) - pies * 12
            return "\(pies)' \(pulgadas)\""
        }
    }

    /// An area in square metres written in the chosen unit.
    static func area(_ metros2: Double, _ unidad: Unidad = .metros) -> String {
        switch unidad {
        case .metros, .centimetros:
            return String(format: "%.2f m²", locale: posix, metros2)
        case .pies:
            return String(format: "%.1f ft²", locale: posix, metros2 * 10.7639)
        }
    }

    /// A volume in cubic metres.
    static func volumen(_ metros3: Double, _ unidad: Unidad = .metros) -> String {
        switch unidad {
        case .metros, .centimetros:
            return String(format: "%.2f m³", locale: posix, metros3)
        case .pies:
            return String(format: "%.1f ft³", locale: posix, metros3 * 35.3147)
        }
    }

    static func fecha(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: fecha)
    }

    /// A file-system friendly version of a project name.
    static func nombreArchivo(_ texto: String) -> String {
        let permitido = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let limpio = texto.folding(options: [.diacriticInsensitive], locale: posix)
            .unicodeScalars.map { permitido.contains($0) ? Character($0) : "-" }
        let resultado = String(limpio).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        return resultado.isEmpty ? "proyecto" : resultado
    }
}
