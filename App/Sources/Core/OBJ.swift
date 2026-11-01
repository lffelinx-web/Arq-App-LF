import Foundation

/// One piece of a triangle mesh in world coordinates.
struct PiezaMalla {
    var vertices: [(Float, Float, Float)]
    var normales: [(Float, Float, Float)]
    /// Zero-based vertex indices, three per triangle.
    var indices: [UInt32]
    /// Per-vertex colour taken from the camera; empty for an uncoloured scan.
    var colores: [(UInt8, UInt8, UInt8)] = []

    var triangulos: Int { indices.count / 3 }
    var conColor: Bool { !colores.isEmpty && colores.count == vertices.count }
}

/// Writes meshes as Wavefront OBJ, which SketchUp, Blender, Revit and
/// practically every 3D tool can open.
enum OBJ {
    /// Streams the pieces to `url` so large scans don't need one giant string.
    @discardableResult
    static func escribir(_ piezas: [PiezaMalla], en url: URL, nombre: String = "ArqLF") throws -> (vertices: Int, triangulos: Int) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let archivo = try FileHandle(forWritingTo: url)
        defer { try? archivo.close() }

        try archivo.write(contentsOf: Data("# Escaneo LiDAR exportado con Arq LF\n# Unidades: metros\n".utf8))
        var base = 0
        var totalTriangulos = 0
        for (n, pieza) in piezas.enumerated() {
            try archivo.write(contentsOf: Data(texto(pieza, grupo: "\(nombre)_\(n)", base: base).utf8))
            base += pieza.vertices.count
            totalTriangulos += pieza.triangulos
        }
        return (base, totalTriangulos)
    }

    /// OBJ text for one piece. `base` is how many vertices were written before it,
    /// because OBJ indices are global and start at 1.
    static func texto(_ pieza: PiezaMalla, grupo: String, base: Int) -> String {
        var s = "o \(grupo)\n"
        s.reserveCapacity(pieza.vertices.count * 60 + pieza.indices.count * 12)
        if pieza.conColor {
            // "v x y z r g b" is the de facto vertex-colour extension (Blender, MeshLab, CloudCompare).
            for (v, c) in zip(pieza.vertices, pieza.colores) {
                s += "v \(numero(v.0)) \(numero(v.1)) \(numero(v.2)) \(canal(c.0)) \(canal(c.1)) \(canal(c.2))\n"
            }
        } else {
            for v in pieza.vertices {
                s += "v \(numero(v.0)) \(numero(v.1)) \(numero(v.2))\n"
            }
        }
        let conNormales = pieza.normales.count == pieza.vertices.count
        if conNormales {
            for n in pieza.normales {
                s += "vn \(numero(n.0)) \(numero(n.1)) \(numero(n.2))\n"
            }
        }
        var i = 0
        while i + 2 < pieza.indices.count {
            let a = Int(pieza.indices[i]) + base + 1
            let b = Int(pieza.indices[i + 1]) + base + 1
            let c = Int(pieza.indices[i + 2]) + base + 1
            s += conNormales ? "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n" : "f \(a) \(b) \(c)\n"
            i += 3
        }
        return s
    }

    static func canal(_ c: UInt8) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(c) / 255)
    }

    /// Millimetre precision is plenty for a LiDAR scan and keeps files small.
    static func numero(_ v: Float) -> String {
        let redondeado = (Double(v) * 10000).rounded() / 10000
        return redondeado == 0 ? "0" : String(redondeado)
    }
}
