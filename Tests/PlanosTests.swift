import simd
import XCTest
@testable import ArqLF

final class PlanosTests: XCTestCase {
    /// 2 m × 2 m grid of 10 cm squares. `punto` maps grid (a, b) to 3D.
    private func rejilla(clase: UInt8, normal: (Float, Float, Float), punto: (Float, Float, Int) -> (Float, Float, Float)) -> PiezaMalla {
        var vertices: [(Float, Float, Float)] = []
        for j in 0...20 { for i in 0...20 { vertices.append(punto(Float(i) * 0.1, Float(j) * 0.1, j * 21 + i)) } }
        var indices: [UInt32] = []
        for j in 0..<20 {
            for i in 0..<20 {
                let a = UInt32(j * 21 + i), b = a + 1, c = a + 22, d = a + 21
                indices += [a, b, c, a, c, d]
            }
        }
        return PiezaMalla(vertices: vertices, normales: Array(repeating: normal, count: vertices.count), indices: indices,
                          clases: Array(repeating: clase, count: vertices.count))
    }

    /// Deterministic ±2 cm noise.
    private func ruido(_ k: Int) -> Float { 0.02 * sin(Float(k) * 1.7) }

    func testAplanaElPisoYConservaLoQueSobresale() {
        var m = rejilla(clase: Planos.piso, normal: (0, 1, 0)) { x, z, k in (x, ruido(k), z) }
        // A box corner 30 cm above the floor stays where it is.
        m.vertices[220] = (1, 0.3, 1)
        let r = Planos.regularizar(m)
        let alturas = r.vertices.enumerated().filter { $0.offset != 220 }.map(\.element.1)
        XCTAssertLessThan((alturas.max() ?? 1) - (alturas.min() ?? 0), 1e-4, "El piso queda plano")
        XCTAssertEqual(r.vertices[220].1, 0.3, accuracy: 1e-6)
        // Normals point up.
        XCTAssertGreaterThan(r.normales[10].1, 0.99)
    }

    func testAplanaUnaParedVertical() {
        let m = rejilla(clase: Planos.pared, normal: (0, 0, 1)) { x, y, k in (x, y, -2 + ruido(k)) }
        let planos = Planos.detectar(m)
        XCTAssertEqual(planos.count, 1)
        XCTAssertEqual(planos[0].normal.z, 1, accuracy: 1e-5)
        XCTAssertEqual(planos[0].normal.y, 0, accuracy: 1e-6)
        let r = Planos.regularizar(m)
        // Every point ends up on one vertical plane (within 0.1 mm)...
        let n = Planos.detectar(r)[0]
        let residuos = r.vertices.map { abs(simd_dot(n.normal, SIMD3($0.0, $0.1, $0.2)) - n.distancia) }
        XCTAssertLessThan(residuos.max() ?? 1, 1e-4)
        // ...and the least-squares fit keeps it facing the right way (under 0.05°).
        XCTAssertLessThan(abs(n.normal.x), 0.001)
        XCTAssertEqual(n.normal.y, 0, accuracy: 1e-6)
    }

    func testNormalDeParedPorMinimosCuadrados() {
        // Points along a wall turned 30° about the vertical, with ±1 cm of noise.
        let a: Float = .pi / 6
        let puntos: [(Float, Float, Float)] = (0..<200).map { k in
            let t = Float(k) * 0.01, ruido = 0.01 * sin(Float(k) * 2.3)
            return (t * cos(a) - ruido * sin(a), Float(k % 7) * 0.3, t * sin(a) + ruido * cos(a))
        }
        let n = Planos.normalPared(puntos, aproximada: SIMD3(0, 0, 1))
        XCTAssertEqual(n.x, -sin(a), accuracy: 0.01)
        XCTAssertEqual(n.z, cos(a), accuracy: 0.01)
    }

    func testSinClasificacionNoSeToca() {
        var m = rejilla(clase: Planos.ninguna, normal: (0, 1, 0)) { x, z, k in (x, ruido(k), z) }
        XCTAssertEqual(Planos.regularizar(m).vertices.map(\.1), m.vertices.map(\.1))
        m.clases = []
        XCTAssertEqual(Planos.regularizar(m).vertices.map(\.1), m.vertices.map(\.1))
    }

    func testLasClasesSobrevivenLaLimpieza() {
        let m = rejilla(clase: Planos.piso, normal: (0, 1, 0)) { x, z, _ in (x, 0, z) }
        let unida = Texturizar.unir([m, m])
        XCTAssertEqual(unida.clases.count, unida.vertices.count)
        let limpia = LimpiezaMalla.limpiar(unida)
        XCTAssertTrue(limpia.conClases)
        XCTAssertTrue(limpia.clases.allSatisfy { $0 == Planos.piso })
    }

    func testPersonasNoSePintan() {
        var f = Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8,
                          rgba: [UInt8](repeating: 128, count: 256))
        let a = SIMD3<Float>(-0.2, -0.2, -1), b = SIMD3<Float>(0.2, -0.2, -1), c = SIMD3<Float>(0.2, 0.2, -1)
        XCTAssertNotNil(Texturizar.puntaje(a, b, c, normal: SIMD3(0, 0, 1), foto: f, inversa: f.mundoACamara, posicion: .zero))
        // Someone standing in the middle of the photo.
        f.personas = (0..<64).map { i in (i % 8 >= 3 && i % 8 <= 5) ? 1 : 0 }
        XCTAssertTrue(f.esPersona(u: 4, v: 4))
        XCTAssertFalse(f.esPersona(u: 0.5, v: 0.5))
        XCTAssertNil(Texturizar.puntaje(a, b, c, normal: SIMD3(0, 0, 1), foto: f, inversa: f.mundoACamara, posicion: .zero))
    }
}
