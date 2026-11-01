import Foundation

enum TipoProyecto: String, Codable, CaseIterable {
    /// RoomPlan scan: parametric walls, doors, windows and furniture.
    case cuarto
    /// Raw LiDAR mesh of any space or object.
    case malla
    /// Point-to-point measurements.
    case medidas

    var nombre: String {
        switch self {
        case .cuarto: return "Cuarto"
        case .malla: return "Malla 3D"
        case .medidas: return "Medidas"
        }
    }

    var icono: String {
        switch self {
        case .cuarto: return "square.split.bottomrightquarter"
        case .malla: return "cube.transparent"
        case .medidas: return "ruler"
        }
    }
}

/// A point-to-point measurement taken in AR.
struct Medida: Codable, Hashable, Identifiable {
    var id = UUID()
    var nombre: String
    var metros: Double
}

/// Files a project can have inside its folder.
enum ArchivoProyecto: String, CaseIterable {
    case modeloUSDZ = "modelo.usdz"
    case mallaOBJ = "malla.obj"
    case plano = "plano.json"
    case miniatura = "miniatura.jpg"
    case foto = "foto.jpg"
}

/// Metadata saved as `proyecto.json` in each project folder.
struct Proyecto: Codable, Hashable, Identifiable {
    var id = UUID()
    var nombre: String
    var tipo: TipoProyecto
    var fecha = Date()
    var notas = ""
    var medidas: [Medida] = []
    /// Number of triangles for mesh scans, shown in the details.
    var triangulos: Int = 0
    var vertices: Int = 0
}
