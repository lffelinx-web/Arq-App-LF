import Foundation
import simd

/// A photo taken while scanning, with what is needed to project 3D points onto it.
struct Fotograma {
    /// Camera pose (camera → world), as ARKit gives it.
    var camaraAMundo: simd_float4x4
    /// Intrinsics already scaled to `ancho` × `alto`.
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var ancho: Int
    var alto: Int
    /// RGBA, row 0 at the top.
    var rgba: [UInt8]
    /// LiDAR depth in metres, aligned with the photo; empty if unavailable.
    var profundidad: [Float] = []
    var anchoProfundidad = 0
    var altoProfundidad = 0
    /// Full-resolution JPEG of this photo, used as texture.
    var archivo: URL?
    /// RGB gain that evens this photo's exposure with the others (see `Exposicion`).
    var ganancia = SIMD3<Float>(repeating: 1)
    /// Sharpness (variance of the Laplacian); blurry photos score low.
    var nitidez: Float = 1

    var mundoACamara: simd_float4x4 { camaraAMundo.inverse }
    var posicion: SIMD3<Float> { SIMD3(camaraAMundo.columns.3.x, camaraAMundo.columns.3.y, camaraAMundo.columns.3.z) }

    /// Pixel position and distance of a world point. ARKit's camera looks down -Z
    /// with +Y up, while image rows grow downward.
    func proyectar(_ p: SIMD3<Float>, con inversa: simd_float4x4) -> (u: Float, v: Float, distancia: Float)? {
        let c = inversa * SIMD4<Float>(p, 1)
        let distancia = -c.z
        guard distancia > 0.05 else { return nil }
        let u = fx * c.x / distancia + cx
        let v = -fy * c.y / distancia + cy
        guard u >= 0, v >= 0, u < Float(ancho - 1), v < Float(alto - 1) else { return nil }
        return (u, v, distancia)
    }

    /// Whether the LiDAR saw this point (nothing closer in front of it).
    func visible(u: Float, v: Float, distancia: Float) -> Bool {
        guard anchoProfundidad > 0, altoProfundidad > 0, profundidad.count == anchoProfundidad * altoProfundidad else { return true }
        let x = min(anchoProfundidad - 1, Int(u * Float(anchoProfundidad) / Float(ancho)))
        let y = min(altoProfundidad - 1, Int(v * Float(altoProfundidad) / Float(alto)))
        let medida = profundidad[y * anchoProfundidad + x]
        guard medida.isFinite, medida > 0 else { return true }
        return abs(medida - distancia) < 0.05 + 0.03 * distancia
    }

    /// Depth jump around a pixel (largest minus smallest LiDAR depth in a 3 × 3
    /// window). Large on object outlines, where the photo mixes object and background.
    func saltoProfundidad(u: Float, v: Float) -> Float {
        guard anchoProfundidad > 0, altoProfundidad > 0, profundidad.count == anchoProfundidad * altoProfundidad else { return 0 }
        let cx = min(anchoProfundidad - 1, max(0, Int(u * Float(anchoProfundidad) / Float(ancho))))
        let cy = min(altoProfundidad - 1, max(0, Int(v * Float(altoProfundidad) / Float(alto))))
        var menor = Float.greatestFiniteMagnitude, mayor: Float = 0
        for y in max(0, cy - 1)...min(altoProfundidad - 1, cy + 1) {
            for x in max(0, cx - 1)...min(anchoProfundidad - 1, cx + 1) {
                let d = profundidad[y * anchoProfundidad + x]
                guard d.isFinite, d > 0 else { continue }
                menor = min(menor, d)
                mayor = max(mayor, d)
            }
        }
        return mayor > menor ? mayor - menor : 0
    }

    /// World points the LiDAR measured in this photo, on a grid every `paso`
    /// depth pixels and up to `maximo` metres away. Used for the live coverage guide.
    func puntosVistos(paso: Int = 8, maximo: Float = 3.5) -> [SIMD3<Float>] {
        guard anchoProfundidad > 0, altoProfundidad > 0, profundidad.count == anchoProfundidad * altoProfundidad else { return [] }
        var puntos: [SIMD3<Float>] = []
        for y in stride(from: paso / 2, to: altoProfundidad, by: max(1, paso)) {
            for x in stride(from: paso / 2, to: anchoProfundidad, by: max(1, paso)) {
                let d = profundidad[y * anchoProfundidad + x]
                guard d.isFinite, d > 0.1, d < maximo else { continue }
                let u = (Float(x) + 0.5) / Float(anchoProfundidad) * Float(ancho)
                let v = (Float(y) + 0.5) / Float(altoProfundidad) * Float(alto)
                let local = SIMD4<Float>((u - cx) / fx * d, -(v - cy) / fy * d, -d, 1)
                let w = camaraAMundo * local
                puntos.append(SIMD3(w.x, w.y, w.z))
            }
        }
        return puntos
    }

    /// Colour with the exposure gain applied.
    func color(u: Float, v: Float) -> SIMD3<Float> {
        colorCrudo(u: u, v: v) * ganancia
    }

    /// Bilinear colour sample, as the camera took it.
    func colorCrudo(u: Float, v: Float) -> SIMD3<Float> {
        let x0 = Int(u), y0 = Int(v)
        let fx = u - Float(x0), fy = v - Float(y0)
        func pixel(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let i = (y * ancho + x) * 4
            return SIMD3(Float(rgba[i]), Float(rgba[i + 1]), Float(rgba[i + 2]))
        }
        let arriba = pixel(x0, y0) * (1 - fx) + pixel(x0 + 1, y0) * fx
        let abajo = pixel(x0, y0 + 1) * (1 - fx) + pixel(x0 + 1, y0 + 1) * fx
        return arriba * (1 - fy) + abajo * fy
    }
}

extension Fotograma {
    /// Variance of the Laplacian of the grey image, the usual focus/blur measure.
    static func nitidez(rgba: [UInt8], ancho: Int, alto: Int) -> Float {
        guard ancho > 2, alto > 2, rgba.count >= ancho * alto * 4 else { return 0 }
        func gris(_ x: Int, _ y: Int) -> Float {
            let i = (y * ancho + x) * 4
            return 0.299 * Float(rgba[i]) + 0.587 * Float(rgba[i + 1]) + 0.114 * Float(rgba[i + 2])
        }
        var suma: Double = 0, sumaCuadrados: Double = 0
        var n: Double = 0
        for y in 1..<(alto - 1) {
            for x in 1..<(ancho - 1) {
                let l = Double(4 * gris(x, y) - gris(x - 1, y) - gris(x + 1, y) - gris(x, y - 1) - gris(x, y + 1))
                suma += l
                sumaCuadrados += l * l
                n += 1
            }
        }
        let media = suma / n
        return Float(sumaCuadrados / n - media * media)
    }
}

/// Paints mesh vertices with the photos taken during the scan: each vertex takes
/// its colour from the photo that saw it closest and most head-on.
enum Colorear {
    static let sinColor: (UInt8, UInt8, UInt8) = (170, 170, 170)

    static func colores(vertices: [(Float, Float, Float)], normales: [(Float, Float, Float)], fotogramas: [Fotograma]) -> [(UInt8, UInt8, UInt8)] {
        coloresYVistos(vertices: vertices, normales: normales, fotogramas: fotogramas).colores
    }

    /// Spreads colour from the vertices some photo saw to the ones none did,
    /// across the mesh's edges, so unseen corners take their surroundings' colour.
    static func rellenar(_ colores: [(UInt8, UInt8, UInt8)], vistos: [Bool], malla: PiezaMalla) -> [(UInt8, UInt8, UInt8)] {
        guard colores.count == malla.vertices.count, vistos.contains(true) else { return colores }
        var vecinos = [[UInt32]](repeating: [], count: malla.vertices.count)
        for t in 0..<malla.triangulos {
            let v = [malla.indices[t * 3], malla.indices[t * 3 + 1], malla.indices[t * 3 + 2]]
            for a in v { for b in v where a != b { vecinos[Int(a)].append(b) } }
        }
        var resultado = colores
        var listo = vistos
        var pendientes = (0..<colores.count).filter { !listo[$0] }
        while !pendientes.isEmpty {
            var nuevos: [(Int, (UInt8, UInt8, UInt8))] = []
            for i in pendientes {
                var suma = SIMD3<Float>.zero
                var n: Float = 0
                for o in vecinos[i] where listo[Int(o)] {
                    let c = resultado[Int(o)]
                    suma += SIMD3(Float(c.0), Float(c.1), Float(c.2))
                    n += 1
                }
                if n > 0 {
                    let m = suma / n
                    nuevos.append((i, (UInt8(clamping: Int(m.x.rounded())), UInt8(clamping: Int(m.y.rounded())), UInt8(clamping: Int(m.z.rounded())))))
                }
            }
            // Pieces no photo touched at all keep the neutral grey.
            if nuevos.isEmpty { break }
            for (i, c) in nuevos {
                resultado[i] = c
                listo[i] = true
            }
            pendientes = pendientes.filter { !listo[$0] }
        }
        return resultado
    }

    /// Vertex colours and whether any photo saw each vertex.
    static func coloresYVistos(vertices: [(Float, Float, Float)], normales: [(Float, Float, Float)], fotogramas: [Fotograma]) -> (colores: [(UInt8, UInt8, UInt8)], vistos: [Bool]) {
        guard !fotogramas.isEmpty else { return ([], []) }
        let inversas = fotogramas.map(\.mundoACamara)
        let posiciones = fotogramas.map(\.posicion)
        let conNormales = normales.count == vertices.count
        var resultado = [(UInt8, UInt8, UInt8)](repeating: sinColor, count: vertices.count)
        var vistos = [Bool](repeating: false, count: vertices.count)

        for i in vertices.indices {
            let v = vertices[i]
            let p = SIMD3<Float>(v.0, v.1, v.2)
            let n = conNormales ? SIMD3<Float>(normales[i].0, normales[i].1, normales[i].2) : .zero
            var mejor: Float = 0
            var elegido: (Int, Float, Float)?
            for (k, f) in fotogramas.enumerated() {
                guard let proyeccion = f.proyectar(p, con: inversas[k]) else { continue }
                let (u, vv, d) = (proyeccion.u, proyeccion.v, proyeccion.distancia)
                var frontal: Float = 1
                if conNormales {
                    frontal = simd_dot(n, simd_normalize(posiciones[k] - p))
                    if frontal < 0.15 { continue }
                }
                guard f.visible(u: u, v: vv, distancia: d) else { continue }
                // Prefer the image centre, where the lens is sharpest.
                let bordeX = min(u, Float(f.ancho) - u) / Float(f.ancho)
                let bordeY = min(vv, Float(f.alto) - vv) / Float(f.alto)
                let centro = min(1, 4 * min(bordeX, bordeY) + 0.2)
                let puntaje = frontal * centro / max(d, 0.3)
                if puntaje > mejor {
                    mejor = puntaje
                    elegido = (k, u, vv)
                }
            }
            if let elegido {
                let c = fotogramas[elegido.0].color(u: elegido.1, v: elegido.2)
                resultado[i] = (UInt8(clamping: Int(c.x.rounded())), UInt8(clamping: Int(c.y.rounded())), UInt8(clamping: Int(c.z.rounded())))
                vistos[i] = true
            }
        }
        return (resultado, vistos)
    }
}
