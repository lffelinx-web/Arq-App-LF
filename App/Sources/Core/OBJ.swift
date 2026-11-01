import Foundation

/// One piece of a triangle mesh in world coordinates.
struct PiezaMalla {
    var vertices: [(Float, Float, Float)]
    var normales: [(Float, Float, Float)]
    /// Zero-based vertex indices, three per triangle.
    var indices: [UInt32]

    var triangulos: Int { indices.count / 3 }
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
        for v in pieza.vertices {
            s += "v \(numero(v.0)) \(numero(v.1)) \(numero(v.2))\n"
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

    /// Millimetre precision is plenty for a LiDAR scan and keeps files small.
    static func numero(_ v: Float) -> String {
        let redondeado = (Double(v) * 10000).rounded() / 10000
        return redondeado == 0 ? "0" : String(redondeado)
    }
}
