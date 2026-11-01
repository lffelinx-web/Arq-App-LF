import simd
import XCTest
@testable import ArqLF

final class Fase33Tests: XCTestCase {
    /// 8 × 8 photo from the origin looking down -Z with a 2 × 2 depth map.
    private func foto(profundidad: [Float]) -> Fotograma {
        var f = Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8,
                          rgba: [UInt8](repeating: 128, count: 256))
        f.profundidad = profundidad
        f.anchoProfundidad = 2
        f.altoProfundidad = 2
        return f
    }

    func testSaltoDeProfundidad() {
        XCTAssertEqual(foto(profundidad: [1, 1, 1, 1]).saltoProfundidad(u: 2, v: 2), 0)
        XCTAssertEqual(foto(profundidad: [1, 3, 1, 1]).saltoProfundidad(u: 2, v: 2), 2, accuracy: 1e-6)
        XCTAssertEqual(Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: []).saltoProfundidad(u: 1, v: 1), 0)
    }

    func testRechazaTriangulosConUnaEsquinaTapada() {
        let a = SIMD3<Float>(-0.2, -0.2, -1), b = SIMD3<Float>(0.2, -0.2, -1), c = SIMD3<Float>(0.2, 0.2, -1)
        let n = SIMD3<Float>(0, 0, 1)
        // Something at 0.5 m covers the left half of the view (where corner a is).
        let tapada = foto(profundidad: [0.5, 1, 0.5, 1])
        XCTAssertNil(Texturizar.puntaje(a, b, c, normal: n, foto: tapada, inversa: tapada.mundoACamara, posicion: .zero))
        // The lenient pass still accepts it when nothing else can.
        XCTAssertNotNil(Texturizar.puntaje(a, b, c, normal: n, foto: tapada, inversa: tapada.mundoACamara, posicion: .zero, estricto: false))
        let libre = foto(profundidad: [1, 1, 1, 1])
        XCTAssertNotNil(Texturizar.puntaje(a, b, c, normal: n, foto: libre, inversa: libre.mundoACamara, posicion: .zero))
    }

    func testPuntosVistos() {
        let f = foto(profundidad: [2, 2, 2, 2])
        let puntos = f.puntosVistos(paso: 1)
        XCTAssertEqual(puntos.count, 4)
        XCTAssertTrue(puntos.allSatisfy { abs($0.z + 2) < 1e-5 })
        // Top-left depth pixel lands up and to the left of the camera.
        XCTAssertLessThan(puntos[0].x, 0)
        XCTAssertGreaterThan(puntos[0].y, 0)
        XCTAssertTrue(foto(profundidad: [9, 9, 9, 9]).puntosVistos(paso: 1).isEmpty, "Más lejos que el máximo")
    }

    func testAtlasOrientaLosTriangulosSegunSusNormales() {
        // Wound clockwise as seen from +Z, but the normals say the front is +Z.
        let malla = PiezaMalla(
            vertices: [(-0.2, -0.2, -1), (0.2, 0.2, -1), (0.2, -0.2, -1)],
            normales: Array(repeating: (0, 0, 1), count: 3),
            indices: [0, 1, 2]
        )
        let fotos = [foto(profundidad: [])]
        let etiquetas: [Int32] = [0]
        let uvs = Texturizar.uvs(malla, etiquetas: etiquetas, fotogramas: fotos)
        let plan = Atlas.planificar(malla, etiquetas: etiquetas, uvFoto: uvs, fotogramas: fotos, tamanos: [SIMD2(16, 16)], lado: 64, maximoAtlas: 1)
        let p = plan.malla.posiciones
        let a = SIMD3(p[0], p[1], p[2]), b = SIMD3(p[3], p[4], p[5]), c = SIMD3(p[6], p[7], p[8])
        XCTAssertGreaterThan(simd_cross(b - a, c - a).z, 0)
        XCTAssertTrue(plan.malla.orientada)
        XCTAssertTrue(try Texturizar.leer(Texturizar.datos(plan.malla)).orientada)
    }

    func testSuavizarBordesQuitaDientesYAlisaElContorno() {
        // 10 × 3 strip of squares (60 triangles) with an extra "tooth" on top.
        var vertices: [(Float, Float, Float)] = []
        for y in 0...3 { for x in 0...10 { vertices.append((Float(x) * 0.1, Float(y) * 0.1, 0)) } }
        var indices: [UInt32] = []
        for y in 0..<3 {
            for x in 0..<10 {
                let a = UInt32(y * 11 + x), b = a + 1, c = a + 12, d = a + 11
                indices += [a, b, c, a, c, d]
            }
        }
        let punta = UInt32(vertices.count)
        vertices.append((0.55, 0.4, 0))
        indices += [38, 39, punta]
        let m = PiezaMalla(vertices: vertices, normales: [], indices: indices)
        let r = LimpiezaMalla.suavizarBordes(m)
        XCTAssertFalse(r.indices.contains(punta))
        XCTAssertEqual(r.triangulos, 60 - 2 + 0, "Se va el diente y las dos esquinas sueltas del rectángulo")
        // The outline vertices stay on the straight border.
        XCTAssertEqual(r.vertices[5].1, 0, accuracy: 1e-6)
    }
}
