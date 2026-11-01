import Foundation
import simd

/// Evens out brightness and colour between the scan photos. The camera adjusts
/// exposure and white balance as it moves, so the same wall can come out grey
/// in one photo and white in the next; each photo gets an RGB gain so that the
/// points several photos saw end up with the same colour in all of them.
enum Exposicion {
    struct Observacion {
        var foto: Int
        var color: SIMD3<Float>
    }

    /// Colour each photo saw for a sample of the mesh vertices.
    static func observaciones(_ malla: PiezaMalla, fotogramas: [Fotograma], maximo: Int = 15_000) -> [[Observacion]] {
        guard !fotogramas.isEmpty, !malla.vertices.isEmpty else { return [] }
        let inversas = fotogramas.map(\.mundoACamara)
        let posiciones = fotogramas.map(\.posicion)
        let conNormales = malla.normales.count == malla.vertices.count
        let paso = max(1, malla.vertices.count / maximo)
        var resultado: [[Observacion]] = []

        for i in stride(from: 0, to: malla.vertices.count, by: paso) {
            let v = malla.vertices[i]
            let p = SIMD3<Float>(v.0, v.1, v.2)
            let n = conNormales ? SIMD3<Float>(malla.normales[i].0, malla.normales[i].1, malla.normales[i].2) : .zero
            var vistas: [Observacion] = []
            for (k, f) in fotogramas.enumerated() {
                guard let pr = f.proyectar(p, con: inversas[k]) else { continue }
                if conNormales, simd_dot(n, simd_normalize(posiciones[k] - p)) < 0.3 { continue }
                guard f.visible(u: pr.u, v: pr.v, distancia: pr.distancia) else { continue }
                let c = f.colorCrudo(u: pr.u, v: pr.v)
                // Ignore near-black and blown-out samples: they carry no exposure information.
                guard c.min() > 8, c.max() < 250 else { continue }
                vistas.append(Observacion(foto: k, color: c))
            }
            if vistas.count >= 2 { resultado.append(vistas) }
        }
        return resultado
    }

    /// RGB gain for each photo. Solved in log space by alternating between the
    /// consensus colour of each point and each photo's offset from it, with a
    /// pull toward 1 so that photos with little overlap aren't over-corrected.
    static func ganancias(_ observaciones: [[Observacion]], fotos: Int, iteraciones: Int = 25, regularizacion: Float = 4) -> [SIMD3<Float>] {
        guard fotos > 0 else { return [] }
        var g = [SIMD3<Float>](repeating: .zero, count: fotos)
        let logs = observaciones.map { lista in lista.map { (foto: $0.foto, valor: SIMD3<Float>(log($0.color.x), log($0.color.y), log($0.color.z))) } }

        for _ in 0..<iteraciones {
            var suma = [SIMD3<Float>](repeating: .zero, count: fotos)
            var cuenta = [Float](repeating: 0, count: fotos)
            for lista in logs {
                var media = SIMD3<Float>.zero
                for o in lista { media += o.valor + g[o.foto] }
                media /= Float(lista.count)
                for o in lista {
                    suma[o.foto] += media - o.valor
                    cuenta[o.foto] += 1
                }
            }
            for k in 0..<fotos { g[k] = suma[k] / (cuenta[k] + regularizacion) }
            // Keep the overall brightness: the gains average out to 1.
            let usadas = (0..<fotos).filter { cuenta[$0] > 0 }
            if !usadas.isEmpty {
                let media = usadas.reduce(SIMD3<Float>.zero) { $0 + g[$1] } / Float(usadas.count)
                for k in usadas { g[k] -= media }
            }
        }
        return g.map { simd_clamp(SIMD3(exp($0.x), exp($0.y), exp($0.z)), SIMD3(repeating: 0.5), SIMD3(repeating: 2)) }
    }

    /// Computes and stores each photo's gain.
    static func igualar(_ fotogramas: inout [Fotograma], malla: PiezaMalla) {
        let g = ganancias(observaciones(malla, fotogramas: fotogramas), fotos: fotogramas.count)
        for k in fotogramas.indices { fotogramas[k].ganancia = g[k] }
    }
}
