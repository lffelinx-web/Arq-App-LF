import Foundation
import simd

/// Straightens walls, floor and ceiling. ARKit's on-device model labels every
/// mesh face (wall, floor, ceiling, table, seat, window, door); the faces of each
/// large flat region are fitted to one plane (vertical for walls, horizontal for
/// floor and ceiling) and the vertices near it are snapped onto it. Where two
/// planes meet, the shared vertices end up on both, so corners come out straight.
enum Planos {
    /// `ARMeshClassification` raw values.
    static let ninguna: UInt8 = 0
    static let pared: UInt8 = 1
    static let piso: UInt8 = 2
    static let techo: UInt8 = 3

    struct Plano: Equatable {
        var normal: SIMD3<Float>
        var distancia: Float
        var vertices: [UInt32]
        var clase: UInt8
    }

    /// - Parameters:
    ///   - tolerancia: only vertices this close to the plane are moved, so things
    ///     standing against a wall (boxes, a switch) keep their shape.
    ///   - areaMinima: smaller regions are left alone.
    static func regularizar(_ m: PiezaMalla, tolerancia: Float = 0.08, areaMinima: Float = 0.3) -> PiezaMalla {
        guard m.conClases, m.triangulos > 0 else { return m }
        let planos = detectar(m, areaMinima: areaMinima)
        guard !planos.isEmpty else { return m }

        var r = m
        func punto(_ i: Int) -> SIMD3<Float> { SIMD3(r.vertices[i].0, r.vertices[i].1, r.vertices[i].2) }
        // Alternating projections: a vertex on two or three planes converges to their edge or corner.
        for _ in 0..<4 {
            for plano in planos {
                for v in plano.vertices {
                    let i = Int(v)
                    let p = punto(i)
                    let desvio = simd_dot(plano.normal, p) - plano.distancia
                    guard abs(desvio) < tolerancia else { continue }
                    let q = p - plano.normal * desvio
                    r.vertices[i] = (q.x, q.y, q.z)
                }
            }
        }
        return recalcularNormales(revertirVolteados(original: m, nueva: r), referencia: m)
    }

    /// Snapping can fold a thin triangle over (or squash it to nothing), which
    /// shows as a see-through crack. Those triangles get their corners back
    /// where they were; a few passes catch neighbours that fold in turn.
    static func revertirVolteados(original m: PiezaMalla, nueva: PiezaMalla, pasadas: Int = 3) -> PiezaMalla {
        var r = nueva
        func normal(_ malla: PiezaMalla, _ t: Int) -> SIMD3<Float> {
            let p = (0..<3).map { k -> SIMD3<Float> in
                let v = malla.vertices[Int(malla.indices[t * 3 + k])]
                return SIMD3(v.0, v.1, v.2)
            }
            return simd_cross(p[1] - p[0], p[2] - p[0])
        }
        for _ in 0..<pasadas {
            var cambios = 0
            for t in 0..<m.triangulos {
                let antes = normal(m, t), ahora = normal(r, t)
                let largoAntes = simd_length(antes), largoAhora = simd_length(ahora)
                guard largoAntes > 1e-10 else { continue }
                let volteado = largoAhora < largoAntes * 0.05 || simd_dot(antes, ahora) / (largoAntes * max(largoAhora, 1e-12)) < 0.2
                guard volteado else { continue }
                for k in 0..<3 {
                    let i = Int(m.indices[t * 3 + k])
                    if r.vertices[i] != m.vertices[i] {
                        r.vertices[i] = m.vertices[i]
                        cambios += 1
                    }
                }
            }
            if cambios == 0 { break }
        }
        return r
    }

    /// Flat regions of wall, floor and ceiling and the plane of each.
    static func detectar(_ m: PiezaMalla, areaMinima: Float = 0.3, angulo: Float = 35) -> [Plano] {
        let t = m.triangulos
        var clase = [UInt8](repeating: ninguna, count: t)
        var normal = [SIMD3<Float>](repeating: .zero, count: t)
        var area = [Float](repeating: 0, count: t)
        let conNormales = m.normales.count == m.vertices.count
        for k in 0..<t {
            let i = (0..<3).map { Int(m.indices[k * 3 + $0]) }
            let c = i.map { m.clases[$0] }
            clase[k] = c[0] == c[1] || c[0] == c[2] ? c[0] : (c[1] == c[2] ? c[1] : ninguna)
            let p = i.map { SIMD3<Float>(m.vertices[$0].0, m.vertices[$0].1, m.vertices[$0].2) }
            var n = simd_cross(p[1] - p[0], p[2] - p[0])
            area[k] = simd_length(n) / 2
            guard area[k] > 1e-9 else { continue }
            n = simd_normalize(n)
            if conNormales {
                let suma = i.reduce(SIMD3<Float>.zero) { $0 + SIMD3(m.normales[$1].0, m.normales[$1].1, m.normales[$1].2) }
                if simd_dot(n, suma) < 0 { n = -n }
            }
            normal[k] = n
        }

        let vecinos = Texturizar.vecindad(m)
        let coseno = cos(angulo * .pi / 180)
        var visitado = [Bool](repeating: false, count: t)
        var planos: [Plano] = []

        for semilla in 0..<t where !visitado[semilla] && [pared, piso, techo].contains(clase[semilla]) && area[semilla] > 0 {
            var region: [Int] = []
            var pila = [semilla]
            visitado[semilla] = true
            var suma = SIMD3<Float>.zero
            var superficie: Float = 0
            while let k = pila.popLast() {
                region.append(k)
                suma += normal[k] * area[k]
                superficie += area[k]
                let media = simd_normalize(suma)
                for v in vecinos[k] {
                    let u = Int(v)
                    guard !visitado[u], clase[u] == clase[semilla], area[u] > 0, simd_dot(normal[u], media) > coseno else { continue }
                    visitado[u] = true
                    pila.append(u)
                }
            }
            guard superficie >= areaMinima, simd_length(suma) > 1e-9 else { continue }
            let media = simd_normalize(suma)

            var unicos = Set<UInt32>()
            for k in region { for j in 0..<3 { unicos.insert(m.indices[k * 3 + j]) } }
            let vertices = unicos.sorted()

            // Walls are vertical, floor and ceiling horizontal (ARKit's Y points up).
            let n: SIMD3<Float>
            if clase[semilla] == pared {
                guard abs(media.y) < 0.35 else { continue }
                n = normalPared(vertices.map { m.vertices[Int($0)] }, aproximada: simd_normalize(SIMD3(media.x, 0, media.z)))
            } else {
                guard abs(media.y) > 0.85 else { continue }
                n = SIMD3(0, media.y > 0 ? 1 : -1, 0)
            }
            let distancias = vertices.map { v -> Float in
                let p = m.vertices[Int(v)]
                return simd_dot(n, SIMD3(p.0, p.1, p.2))
            }.sorted()
            // Median: robust to the odd vertex that strays off the surface.
            let d = distancias[distancias.count / 2]
            planos.append(Plano(normal: n, distancia: d, vertices: vertices, clase: clase[semilla]))
        }
        return planos
    }

    /// Horizontal normal of a wall by least squares: the wall's direction is the
    /// main axis of its points seen from above (PCA), which is much steadier
    /// than averaging noisy face normals. Falls back to `aproximada` when the
    /// region is too narrow to tell.
    static func normalPared(_ puntos: [(Float, Float, Float)], aproximada: SIMD3<Float>) -> SIMD3<Float> {
        guard puntos.count >= 3 else { return aproximada }
        let n = Float(puntos.count)
        let mx = puntos.reduce(0) { $0 + $1.0 } / n
        let mz = puntos.reduce(0) { $0 + $1.2 } / n
        var sxx: Float = 0, szz: Float = 0, sxz: Float = 0
        for p in puntos {
            let dx = p.0 - mx, dz = p.2 - mz
            sxx += dx * dx
            szz += dz * dz
            sxz += dx * dz
        }
        // Eigenvalues of the 2 × 2 covariance: a thin, long cloud is a clear wall line.
        let traza = sxx + szz
        let raiz = ((sxx - szz) * (sxx - szz) + 4 * sxz * sxz).squareRoot()
        let mayor = (traza + raiz) / 2, menor = (traza - raiz) / 2
        guard mayor > 1e-9, menor / mayor < 0.25 else { return aproximada }
        let angulo = 0.5 * atan2(2 * sxz, sxx - szz)
        var normal = SIMD3<Float>(-sin(angulo), 0, cos(angulo))
        if simd_dot(normal, aproximada) < 0 { normal = -normal }
        return normal
    }

    /// Area-weighted vertex normals, keeping each face on the side its original
    /// normals pointed to.
    static func recalcularNormales(_ m: PiezaMalla, referencia: PiezaMalla) -> PiezaMalla {
        guard referencia.normales.count == referencia.vertices.count else { return m }
        var suma = [SIMD3<Float>](repeating: .zero, count: m.vertices.count)
        for k in 0..<m.triangulos {
            let i = (0..<3).map { Int(m.indices[k * 3 + $0]) }
            let p = i.map { SIMD3<Float>(m.vertices[$0].0, m.vertices[$0].1, m.vertices[$0].2) }
            var n = simd_cross(p[1] - p[0], p[2] - p[0])
            let original = i.reduce(SIMD3<Float>.zero) { $0 + SIMD3(referencia.normales[$1].0, referencia.normales[$1].1, referencia.normales[$1].2) }
            if simd_dot(n, original) < 0 { n = -n }
            for j in i { suma[j] += n }
        }
        var r = m
        r.normales = suma.enumerated().map { j, s in
            if simd_length(s) > 1e-9 {
                let n = simd_normalize(s)
                return (n.x, n.y, n.z)
            }
            return referencia.normales[j]
        }
        return r
    }
}
