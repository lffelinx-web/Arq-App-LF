import Foundation

enum TipoProyecto: String, Codable, CaseIterable {
    /// RoomPlan scan: parametric walls, doors, windows and furniture.
    case cuarto
    /// Raw LiDAR mesh of any space or object.
    case malla
    /// Point-to-point measurements.
    case medidas
    /// Photogrammetry model made from library photos ("Fotos a 3D").
    case objeto

    var nombre: String {
        switch self {
        case .cuarto: return "Cuarto"
        case .malla: return "Malla 3D"
        case .medidas: return "Medidas"
        case .objeto: return "Objeto 3D"
        }
    }

    var icono: String {
        switch self {
        case .cuarto: return "square.split.bottomrightquarter"
        case .malla: return "cube.transparent"
        case .medidas: return "ruler"
        case .objeto: return "photo.stack"
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
    case mallaPLY = "malla.ply"
    /// Textured mesh for the viewer; its photos and the OBJ/MTL live in `textura/`.
    case texturaBIN = "textura.bin"
    case carpetaTextura = "textura"
    case plano = "plano.json"
    case miniatura = "miniatura.jpg"
    case foto = "foto.jpg"
    /// ARKit world map, so more sections can be scanned later in the same coordinates.
    case mapa = "mapa.arworldmap"
    /// All sections together, written when the project has more than one.
    case completoUSDZ = "modelo-completo.usdz"
    case completoPLY = "malla-completa.ply"
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
    /// Optional so projects saved by earlier versions still load.
    var fotos: Int?
    var cuartos: Int?
    /// Sections of a large-space scan (nil or 1 for a single scan).
    var secciones: Int?
}
