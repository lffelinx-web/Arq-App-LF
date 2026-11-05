import Foundation
import simd

/// Large spaces (a church, a warehouse) are scanned in sections that share one
/// coordinate system: each new section starts from the ARKit world map saved by
/// the previous ones, so all of them line up. Every section keeps its own photos
/// and texture atlas, which keeps the texture sharp however big the whole gets.
///
/// The first section lives in the project folder as a normal scan; the others in
/// `secciones/2`, `secciones/3`…
enum Secciones {
    /// Size of the cells used to find what earlier sections already cover.
    static let celda: Float = 0.03

    /// Cells touched by the surface of the triangles (sampled finer than a cell,
    /// so big triangles count all along, not just at their corners).
    static func celdas(vertices: [Float], indices: [UInt32], celda: Float = celda) -> Set<SIMD3<Int32>> {
        var resultado = Set<SIMD3<Int32>>()
        resultado.reserveCapacity(indices.count)
        func punto(_ i: UInt32) -> SIMD3<Float> {
            let k = Int(i) * 3
            return SIMD3(vertices[k], vertices[k + 1], vertices[k + 2])
        }
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = punto(indices[t]), b = punto(indices[t + 1]), c = punto(indices[t + 2])
            let lado = max(simd_distance(a, b), simd_distance(b, c), simd_distance(c, a))
            let n = min(64, max(1, Int((lado / (celda * 0.7)).rounded(.up))))
            for i in 0...n {
                for j in 0...(n - i) {
                    let u = Float(i) / Float(n), v = Float(j) / Float(n)
                    resultado.insert(clave(a + (b - a) * u + (c - a) * v, celda: celda))
                }
            }
        }
        return resultado
    }

    static func celdas(_ ply: PLY.Malla, celda: Float = celda) -> Set<SIMD3<Int32>> {
        celdas(vertices: ply.vertices, indices: ply.indices, celda: celda)
    }

    static func clave(_ p: SIMD3<Float>, celda: Float = celda) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / celda).rounded(.down)), Int32((p.y / celda).rounded(.down)), Int32((p.z / celda).rounded(.down)))
    }

    /// Folder of section `numero` (1 is the project folder itself).
    static func carpeta(_ numero: Int, en proyecto: URL) -> URL {
        numero <= 1 ? proyecto : proyecto.appendingPathComponent("secciones", isDirectory: true).appendingPathComponent("\(numero)", isDirectory: true)
    }

    /// Folders of every section saved so far, in order.
    static func carpetas(en proyecto: URL) -> [URL] {
        let fm = FileManager.default
        let dentro = proyecto.appendingPathComponent("secciones", isDirectory: true)
        let numeros = ((try? fm.contentsOfDirectory(atPath: dentro.path)) ?? []).compactMap(Int.init).filter { $0 > 1 }.sorted()
        return [proyecto] + numeros.map { carpeta($0, en: proyecto) }
    }

    static func siguiente(en proyecto: URL) -> Int {
        let fm = FileManager.default
        let dentro = proyecto.appendingPathComponent("secciones", isDirectory: true)
        let numeros = ((try? fm.contentsOfDirectory(atPath: dentro.path)) ?? []).compactMap(Int.init)
        return max(1, numeros.max() ?? 1) + 1
    }
}

extension LimpiezaMalla {
    /// Drops the triangles that earlier sections already cover (the area walked
    /// over again to pick up the position), so surfaces aren't doubled. A triangle
    /// goes when its three corners are within about one cell of earlier geometry.
    static func quitarTraslape(_ m: PiezaMalla, ocupado: Set<SIMD3<Int32>>, celda: Float = Secciones.celda) -> PiezaMalla {
        guard !ocupado.isEmpty, m.triangulos > 0 else { return m }
        var cerca = [Bool](repeating: false, count: m.vertices.count)
        for i in m.vertices.indices {
            let v = m.vertices[i]
            let c = Secciones.clave(SIMD3(v.0, v.1, v.2), celda: celda)
            busqueda: for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 where ocupado.contains(c &+ SIMD3(Int32(dx), Int32(dy), Int32(dz))) {
                        cerca[i] = true
                        break busqueda
                    }
                }
            }
        }
        var r = m
        r.indices = []
        r.indices.reserveCapacity(m.indices.count)
        for t in 0..<m.triangulos {
            let a = Int(m.indices[t * 3]), b = Int(m.indices[t * 3 + 1]), c = Int(m.indices[t * 3 + 2])
            if cerca[a] && cerca[b] && cerca[c] { continue }
            r.indices += [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
        }
        guard r.indices.count < m.indices.count else { return m }
        // Slivers left along the overlap edge go too.
        return compactar(quitarFragmentos(r, minimo: 30))
    }
}

extension PiezaMalla {
    /// A mesh read back from a PLY.
    init(_ ply: PLY.Malla) {
        let n = ply.numeroVertices
        vertices = (0..<n).map { (ply.vertices[$0 * 3], ply.vertices[$0 * 3 + 1], ply.vertices[$0 * 3 + 2]) }
        normales = ply.normales.count == ply.vertices.count ? (0..<n).map { (ply.normales[$0 * 3], ply.normales[$0 * 3 + 1], ply.normales[$0 * 3 + 2]) } : []
        indices = ply.indices
        colores = ply.colores.count == ply.vertices.count ? (0..<n).map { (ply.colores[$0 * 3], ply.colores[$0 * 3 + 1], ply.colores[$0 * 3 + 2]) } : []
        clases = []
    }
}

extension Atlas {
    /// More texture images for bigger sections, so a long nave gets as many
    /// pixels per metre as a small room.
    static func maximoAtlas(area: Float) -> Int {
        area <= 60 ? 4 : (area <= 150 ? 6 : 8)
    }

    /// Surface of the mesh in square metres.
    static func area(_ m: PiezaMalla) -> Float {
        var total: Float = 0
        for t in 0..<m.triangulos {
            let p = (0..<3).map { k -> SIMD3<Float> in
                let v = m.vertices[Int(m.indices[t * 3 + k])]
                return SIMD3(v.0, v.1, v.2)
            }
            total += simd_length(simd_cross(p[1] - p[0], p[2] - p[0])) / 2
        }
        return total
    }
}
