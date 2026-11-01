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

    /// Bilinear colour sample.
    func color(u: Float, v: Float) -> SIMD3<Float> {
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

/// Paints mesh vertices with the photos taken during the scan: each vertex takes
/// its colour from the photo that saw it closest and most head-on.
enum Colorear {
    static let sinColor: (UInt8, UInt8, UInt8) = (170, 170, 170)

    static func colores(vertices: [(Float, Float, Float)], normales: [(Float, Float, Float)], fotogramas: [Fotograma]) -> [(UInt8, UInt8, UInt8)] {
        guard !fotogramas.isEmpty else { return [] }
        let inversas = fotogramas.map(\.mundoACamara)
        let posiciones = fotogramas.map(\.posicion)
        let conNormales = normales.count == vertices.count
        var resultado = [(UInt8, UInt8, UInt8)](repeating: sinColor, count: vertices.count)

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
            }
        }
        return resultado
    }
}
