import Foundation
import simd

/// Tidies the raw ARKit mesh before texturing: welds the pieces together,
/// drops floating fragments and closes small holes.
enum LimpiezaMalla {
    static func limpiar(_ malla: PiezaMalla) -> PiezaMalla {
        let soldada = soldar(malla)
        let sinFragmentos = quitarFragmentos(soldada, minimo: max(40, soldada.triangulos / 400))
        return compactar(rellenarHuecos(sinFragmentos))
    }

    /// Merges vertices closer than `tolerancia` (metres). ARKit hands the mesh
    /// over in pieces whose borders don't share vertices, which leaves thin cracks.
    static func soldar(_ m: PiezaMalla, tolerancia: Float = 0.008) -> PiezaMalla {
        var celda: [SIMD3<Int32>: UInt32] = [:]
        celda.reserveCapacity(m.vertices.count)
        var nuevos: [(Float, Float, Float)] = []
        var sumaNormales: [SIMD3<Float>] = []
        var mapa = [UInt32](repeating: 0, count: m.vertices.count)
        let conNormales = m.normales.count == m.vertices.count

        for (i, v) in m.vertices.enumerated() {
            let clave = SIMD3<Int32>(Int32((v.0 / tolerancia).rounded()), Int32((v.1 / tolerancia).rounded()), Int32((v.2 / tolerancia).rounded()))
            let n = conNormales ? SIMD3<Float>(m.normales[i].0, m.normales[i].1, m.normales[i].2) : .zero
            if let existente = celda[clave] {
                mapa[i] = existente
                sumaNormales[Int(existente)] += n
            } else {
                let indice = UInt32(nuevos.count)
                celda[clave] = indice
                mapa[i] = indice
                nuevos.append(v)
                sumaNormales.append(n)
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(m.indices.count)
        var vistos = Set<SIMD3<UInt32>>()
        var t = 0
        while t + 2 < m.indices.count {
            let a = mapa[Int(m.indices[t])], b = mapa[Int(m.indices[t + 1])], c = mapa[Int(m.indices[t + 2])]
            t += 3
            guard a != b, b != c, a != c else { continue }
            let ordenado = [a, b, c].sorted()
            guard vistos.insert(SIMD3(ordenado[0], ordenado[1], ordenado[2])).inserted else { continue }
            indices += [a, b, c]
        }

        let normales: [(Float, Float, Float)] = conNormales ? sumaNormales.map { n in
            let largo = simd_length(n)
            let u = largo > 1e-6 ? n / largo : SIMD3<Float>(0, 1, 0)
            return (u.x, u.y, u.z)
        } : []
        return PiezaMalla(vertices: nuevos, normales: normales, indices: indices)
    }

    /// Removes connected pieces with fewer than `minimo` triangles (floating
    /// specks from reflections, people walking by, etc.). The largest piece is
    /// always kept.
    static func quitarFragmentos(_ m: PiezaMalla, minimo: Int) -> PiezaMalla {
        var padre = Array(0..<m.vertices.count)
        func raiz(_ x: Int) -> Int {
            var x = x
            while padre[x] != x {
                padre[x] = padre[padre[x]]
                x = padre[x]
            }
            return x
        }
        func unir(_ a: Int, _ b: Int) {
            let ra = raiz(a), rb = raiz(b)
            if ra != rb { padre[ra] = rb }
        }
        for t in 0..<m.triangulos {
            unir(Int(m.indices[t * 3]), Int(m.indices[t * 3 + 1]))
            unir(Int(m.indices[t * 3]), Int(m.indices[t * 3 + 2]))
        }
        var tamano: [Int: Int] = [:]
        for t in 0..<m.triangulos { tamano[raiz(Int(m.indices[t * 3])), default: 0] += 1 }

        // The largest piece always stays, however small the scan.
        let umbral = min(minimo, tamano.values.max() ?? 0)
        var resultado = m
        resultado.indices = []
        resultado.indices.reserveCapacity(m.indices.count)
        for t in 0..<m.triangulos where (tamano[raiz(Int(m.indices[t * 3]))] ?? 0) >= umbral {
            resultado.indices += [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
        }
        return resultado
    }

    /// Closes holes whose border has at most `maximoAristas` edges and
    /// `maximoPerimetro` metres, with a fan around their centre.
    static func rellenarHuecos(_ m: PiezaMalla, maximoAristas: Int = 40, maximoPerimetro: Float = 1.2) -> PiezaMalla {
        func clave(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(a) << 32 | UInt64(b) }
        var dirigidas = Set<UInt64>()
        dirigidas.reserveCapacity(m.indices.count)
        for t in 0..<m.triangulos {
            let v = [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
            for (a, b) in [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])] { dirigidas.insert(clave(a, b)) }
        }
        // A border edge has no twin running the other way.
        var siguiente: [UInt32: UInt32] = [:]
        var ambiguos = Set<UInt32>()
        for t in 0..<m.triangulos {
            let v = [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
            for (a, b) in [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])] where !dirigidas.contains(clave(b, a)) {
                // The hole runs opposite to the triangle's edge.
                if siguiente[b] != nil { ambiguos.insert(b) }
                siguiente[b] = a
            }
        }

        var resultado = m
        let conNormales = m.normales.count == m.vertices.count
        var visitados = Set<UInt32>()
        func punto(_ i: UInt32) -> SIMD3<Float> {
            let v = m.vertices[Int(i)]
            return SIMD3(v.0, v.1, v.2)
        }

        for inicio in siguiente.keys.sorted() where !visitados.contains(inicio) {
            var bucle: [UInt32] = [inicio]
            var actual = inicio
            var cerrado = false
            while bucle.count <= maximoAristas {
                guard !ambiguos.contains(actual), let proximo = siguiente[actual] else { break }
                if proximo == inicio { cerrado = true; break }
                if visitados.contains(proximo) || bucle.contains(proximo) { break }
                bucle.append(proximo)
                actual = proximo
            }
            bucle.forEach { visitados.insert($0) }
            guard cerrado, bucle.count >= 3 else { continue }
            var perimetro: Float = 0
            for i in bucle.indices { perimetro += simd_distance(punto(bucle[i]), punto(bucle[(i + 1) % bucle.count])) }
            guard perimetro <= maximoPerimetro else { continue }

            if bucle.count == 3 {
                resultado.indices += [bucle[0], bucle[1], bucle[2]]
                continue
            }
            let centro = bucle.map(punto).reduce(.zero, +) / Float(bucle.count)
            let indiceCentro = UInt32(resultado.vertices.count)
            resultado.vertices.append((centro.x, centro.y, centro.z))
            if conNormales {
                let suma = bucle.reduce(SIMD3<Float>.zero) { s, i in s + SIMD3(m.normales[Int(i)].0, m.normales[Int(i)].1, m.normales[Int(i)].2) }
                let n = simd_length(suma) > 1e-6 ? simd_normalize(suma) : SIMD3<Float>(0, 1, 0)
                resultado.normales.append((n.x, n.y, n.z))
            }
            for i in bucle.indices {
                resultado.indices += [bucle[i], bucle[(i + 1) % bucle.count], indiceCentro]
            }
        }
        return resultado
    }

    /// Drops vertices no triangle uses.
    static func compactar(_ m: PiezaMalla) -> PiezaMalla {
        var nuevo = [Int32](repeating: -1, count: m.vertices.count)
        var resultado = PiezaMalla(vertices: [], normales: [], indices: [])
        let conNormales = m.normales.count == m.vertices.count
        let conColor = m.conColor
        resultado.indices.reserveCapacity(m.indices.count)
        for i in m.indices {
            if nuevo[Int(i)] < 0 {
                nuevo[Int(i)] = Int32(resultado.vertices.count)
                resultado.vertices.append(m.vertices[Int(i)])
                if conNormales { resultado.normales.append(m.normales[Int(i)]) }
                if conColor { resultado.colores.append(m.colores[Int(i)]) }
            }
            resultado.indices.append(UInt32(nuevo[Int(i)]))
        }
        return resultado
    }
}
