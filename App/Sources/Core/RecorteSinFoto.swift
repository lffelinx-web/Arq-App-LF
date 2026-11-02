import Foundation
import simd

extension LimpiezaMalla {
    /// Drops what no photo saw well enough to texture, where it looks like
    /// leftovers rather than part of the room: patches hanging off the edge of
    /// the scan (the scanner's own legs and feet, things seen only edge-on) and
    /// loose pieces without any photo. Untextured holes surrounded by texture
    /// stay, so the floor doesn't open up; they get the neighbours' colour.
    ///
    /// - Parameters:
    ///   - etiquetas: photo for each triangle, -1 when none (`Texturizar.etiquetas`).
    ///   - orilla: a patch goes when at least this share of its outline is open edge.
    ///   - areaMaxima: larger patches (a whole ceiling nobody photographed) keep their shape.
    ///   - minimo: loose pieces with fewer triangles go too.
    static func recortarSinFoto(
        _ m: PiezaMalla, etiquetas: [Int32], orilla: Float = 0.3, areaMaxima: Float = 2, minimo: Int = 40
    ) -> (malla: PiezaMalla, etiquetas: [Int32]) {
        let n = m.triangulos
        guard n > 0, etiquetas.count == n, etiquetas.contains(where: { $0 >= 0 }) else { return (m, etiquetas) }
        let vecinos = Texturizar.vecindad(m)
        func clave(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        var usos: [UInt64: Int] = [:]
        usos.reserveCapacity(m.indices.count)
        for t in 0..<n {
            let v = (m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2])
            for (a, b) in [(v.0, v.1), (v.1, v.2), (v.2, v.0)] { usos[clave(a, b), default: 0] += 1 }
        }
        func abiertas(_ t: Int) -> Int {
            let v = (m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2])
            return [(v.0, v.1), (v.1, v.2), (v.2, v.0)].filter { usos[clave($0.0, $0.1)] == 1 }.count
        }
        func area(_ t: Int) -> Float {
            let p = (0..<3).map { k -> SIMD3<Float> in
                let v = m.vertices[Int(m.indices[t * 3 + k])]
                return SIMD3(v.0, v.1, v.2)
            }
            return simd_length(simd_cross(p[1] - p[0], p[2] - p[0])) / 2
        }

        var conservar = [Bool](repeating: true, count: n)

        // 1. Untextured patches mostly bounded by the edge of the scan.
        var visto = [Bool](repeating: false, count: n)
        for semilla in 0..<n where etiquetas[semilla] < 0 && !visto[semilla] {
            var region: [Int] = []
            var pila = [semilla]
            visto[semilla] = true
            var abierto = 0, contacto = 0
            var superficie: Float = 0
            while let t = pila.popLast() {
                region.append(t)
                abierto += abiertas(t)
                superficie += area(t)
                for v in vecinos[t] {
                    let u = Int(v)
                    if etiquetas[u] >= 0 { contacto += 1; continue }
                    guard !visto[u] else { continue }
                    visto[u] = true
                    pila.append(u)
                }
            }
            guard abierto > 0, superficie <= areaMaxima, Float(abierto) >= orilla * Float(abierto + contacto) else { continue }
            for t in region { conservar[t] = false }
        }

        // 2. Loose pieces left without any photo, or too small to matter.
        visto = conservar.map { !$0 }
        var piezas: [(triangulos: [Int], conFoto: Bool)] = []
        for semilla in 0..<n where !visto[semilla] {
            var region: [Int] = []
            var pila = [semilla]
            visto[semilla] = true
            var conFoto = false
            while let t = pila.popLast() {
                region.append(t)
                if etiquetas[t] >= 0 { conFoto = true }
                for v in vecinos[t] where !visto[Int(v)] {
                    visto[Int(v)] = true
                    pila.append(Int(v))
                }
            }
            piezas.append((region, conFoto))
        }
        let mayor = piezas.map(\.triangulos.count).max() ?? 0
        for pieza in piezas where !pieza.conFoto || (pieza.triangulos.count < minimo && pieza.triangulos.count < mayor) {
            for t in pieza.triangulos { conservar[t] = false }
        }

        // Something is off (photos missing?) if most of the scan would go.
        let quedan = conservar.filter { $0 }.count
        guard quedan > 0, quedan * 2 >= n else { return (m, etiquetas) }
        guard quedan < n else { return (m, etiquetas) }

        var r = m
        r.indices = []
        r.indices.reserveCapacity(quedan * 3)
        var nuevas: [Int32] = []
        nuevas.reserveCapacity(quedan)
        for t in 0..<n where conservar[t] {
            r.indices += [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
            nuevas.append(etiquetas[t])
        }
        return (compactar(r), nuevas)
    }
}
