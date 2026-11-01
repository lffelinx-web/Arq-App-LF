import Foundation

/// Binary PLY with normals and vertex colours. It is compact, keeps the colour
/// (Blender, MeshLab and CloudCompare read it) and the app's viewer loads it back.
enum PLY {
    struct Malla {
        var vertices: [Float] = []   // x, y, z
        var normales: [Float] = []   // nx, ny, nz
        var colores: [UInt8] = []    // r, g, b
        var indices: [UInt32] = []   // three per triangle

        var numeroVertices: Int { vertices.count / 3 }
        var numeroTriangulos: Int { indices.count / 3 }
    }

    enum ErrorPLY: Error {
        case formato(String)
    }

    /// Joins the pieces into one mesh and writes it to `url`.
    @discardableResult
    static func escribir(_ piezas: [PiezaMalla], en url: URL) throws -> (vertices: Int, triangulos: Int) {
        let totalVertices = piezas.reduce(0) { $0 + $1.vertices.count }
        let totalTriangulos = piezas.reduce(0) { $0 + $1.triangulos }
        let conNormales = piezas.allSatisfy { $0.normales.count == $0.vertices.count }
        let conColor = piezas.allSatisfy(\.conColor)

        var cabecera = "ply\nformat binary_little_endian 1.0\ncomment Arq LF, unidades: metros\n"
        cabecera += "element vertex \(totalVertices)\nproperty float x\nproperty float y\nproperty float z\n"
        if conNormales { cabecera += "property float nx\nproperty float ny\nproperty float nz\n" }
        if conColor { cabecera += "property uchar red\nproperty uchar green\nproperty uchar blue\n" }
        cabecera += "element face \(totalTriangulos)\nproperty list uchar uint vertex_indices\nend_header\n"

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let archivo = try FileHandle(forWritingTo: url)
        defer { try? archivo.close() }
        try archivo.write(contentsOf: Data(cabecera.utf8))

        for pieza in piezas {
            var datos = Data()
            datos.reserveCapacity(pieza.vertices.count * 27)
            for i in pieza.vertices.indices {
                let v = pieza.vertices[i]
                agregar(&datos, v.0); agregar(&datos, v.1); agregar(&datos, v.2)
                if conNormales {
                    let n = pieza.normales[i]
                    agregar(&datos, n.0); agregar(&datos, n.1); agregar(&datos, n.2)
                }
                if conColor {
                    let c = pieza.colores[i]
                    datos.append(contentsOf: [c.0, c.1, c.2])
                }
            }
            try archivo.write(contentsOf: datos)
        }

        var base: UInt32 = 0
        for pieza in piezas {
            var datos = Data()
            datos.reserveCapacity(pieza.triangulos * 13)
            var i = 0
            while i + 2 < pieza.indices.count {
                datos.append(3)
                agregar(&datos, pieza.indices[i] + base)
                agregar(&datos, pieza.indices[i + 1] + base)
                agregar(&datos, pieza.indices[i + 2] + base)
                i += 3
            }
            try archivo.write(contentsOf: datos)
            base += UInt32(pieza.vertices.count)
        }
        return (totalVertices, totalTriangulos)
    }

    /// Reads a binary little-endian PLY made of float/uchar vertex properties and
    /// triangle faces (what `escribir` produces, and most LiDAR apps too).
    static func leer(_ url: URL) throws -> Malla {
        let datos = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let fin = datos.range(of: Data("end_header\n".utf8)) else { throw ErrorPLY.formato("Sin cabecera") }
        guard let cabecera = String(data: datos[..<fin.lowerBound], encoding: .ascii) else { throw ErrorPLY.formato("Cabecera ilegible") }
        guard cabecera.contains("binary_little_endian") else { throw ErrorPLY.formato("Solo PLY binario") }

        var numeroVertices = 0, numeroCaras = 0
        var propiedades: [(nombre: String, bytes: Int)] = []
        var tipoConteo = 1, tipoIndice = 4
        var elemento = ""
        for linea in cabecera.split(separator: "\n") {
            let partes = linea.split(separator: " ").map(String.init)
            guard let primera = partes.first else { continue }
            if primera == "element", partes.count >= 3 {
                elemento = partes[1]
                if elemento == "vertex" { numeroVertices = Int(partes[2]) ?? 0 }
                if elemento == "face" { numeroCaras = Int(partes[2]) ?? 0 }
            } else if primera == "property", elemento == "vertex", partes.count >= 3 {
                propiedades.append((partes[2], bytes(partes[1])))
            } else if primera == "property", elemento == "face", partes.count >= 5, partes[1] == "list" {
                tipoConteo = bytes(partes[2])
                tipoIndice = bytes(partes[3])
            }
        }

        let paso = propiedades.reduce(0) { $0 + $1.bytes }
        func posicion(_ nombre: String) -> Int? {
            var desplazamiento = 0
            for p in propiedades {
                if p.nombre == nombre { return desplazamiento }
                desplazamiento += p.bytes
            }
            return nil
        }
        guard let px = posicion("x"), let py = posicion("y"), let pz = posicion("z") else { throw ErrorPLY.formato("Sin posiciones") }
        let pn = [posicion("nx"), posicion("ny"), posicion("nz")]
        let pc = [posicion("red"), posicion("green"), posicion("blue")]
        let conNormales = pn.allSatisfy { $0 != nil }
        let conColor = pc.allSatisfy { $0 != nil }

        var malla = Malla()
        malla.vertices.reserveCapacity(numeroVertices * 3)
        if conNormales { malla.normales.reserveCapacity(numeroVertices * 3) }
        if conColor { malla.colores.reserveCapacity(numeroVertices * 3) }
        malla.indices.reserveCapacity(numeroCaras * 3)

        try datos.withUnsafeBytes { (crudo: UnsafeRawBufferPointer) in
            var cursor = fin.upperBound - datos.startIndex
            guard cursor + numeroVertices * paso <= crudo.count else { throw ErrorPLY.formato("Archivo incompleto") }
            for _ in 0..<numeroVertices {
                malla.vertices.append(flotante(crudo, cursor + px))
                malla.vertices.append(flotante(crudo, cursor + py))
                malla.vertices.append(flotante(crudo, cursor + pz))
                if conNormales { for p in pn { malla.normales.append(flotante(crudo, cursor + p!)) } }
                if conColor { for p in pc { malla.colores.append(crudo[cursor + p!]) } }
                cursor += paso
            }
            for _ in 0..<numeroCaras {
                guard cursor + tipoConteo <= crudo.count else { throw ErrorPLY.formato("Caras incompletas") }
                let n = Int(entero(crudo, cursor, tipoConteo))
                cursor += tipoConteo
                guard cursor + n * tipoIndice <= crudo.count else { throw ErrorPLY.formato("Caras incompletas") }
                var poligono: [UInt32] = []
                for k in 0..<n { poligono.append(entero(crudo, cursor + k * tipoIndice, tipoIndice)) }
                cursor += n * tipoIndice
                // Fan-triangulate quads and larger polygons.
                if n >= 3 {
                    for k in 1..<(n - 1) { malla.indices.append(contentsOf: [poligono[0], poligono[k], poligono[k + 1]]) }
                }
            }
        }
        return malla
    }

    private static func bytes(_ tipo: String) -> Int {
        switch tipo {
        case "char", "uchar", "int8", "uint8": return 1
        case "short", "ushort", "int16", "uint16": return 2
        case "double", "float64": return 8
        default: return 4
        }
    }

    private static func flotante(_ crudo: UnsafeRawBufferPointer, _ i: Int) -> Float {
        Float(bitPattern: UInt32(entero(crudo, i, 4)))
    }

    private static func entero(_ crudo: UnsafeRawBufferPointer, _ i: Int, _ tamano: Int) -> UInt32 {
        var valor: UInt32 = 0
        for k in 0..<min(tamano, 4) { valor |= UInt32(crudo[i + k]) << (8 * UInt32(k)) }
        return valor
    }

    private static func agregar(_ datos: inout Data, _ v: Float) { agregar(&datos, v.bitPattern) }

    private static func agregar(_ datos: inout Data, _ v: UInt32) {
        datos.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)])
    }
}
