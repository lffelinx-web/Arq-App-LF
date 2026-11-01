import simd
import XCTest
@testable import ArqLF

final class Fase35Tests: XCTestCase {
    private let cuadro = PiezaMalla(
        vertices: [(-0.2, -0.2, -1), (0.2, -0.2, -1), (0.2, 0.2, -1), (-0.2, 0.2, -1)],
        normales: Array(repeating: (0, 0, 1), count: 4),
        indices: [0, 1, 2, 0, 2, 3]
    )

    private func foto(z: Float, color: (UInt8, UInt8, UInt8)) -> Fotograma {
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(0, 0, z, 1)
        var rgba = [UInt8]()
        for _ in 0..<64 { rgba += [color.0, color.1, color.2, 255] }
        return Fotograma(camaraAMundo: t, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: rgba)
    }

    func testConsistenciaDescartaLaFotoQueVeOtraCosa() {
        // The closest photo (best score) saw a yellow chair leg in front of the grey floor.
        let fotos = [foto(z: 0, color: (128, 128, 128)), foto(z: 0.3, color: (130, 128, 126)), foto(z: -0.5, color: (255, 220, 0))]
        let etiquetas = Texturizar.etiquetas(cuadro, fotogramas: fotos)
        XCTAssertFalse(etiquetas.contains(2))
        XCTAssertTrue(etiquetas.allSatisfy { $0 == 0 || $0 == 1 })
    }

    func testConsistenciaConPocasFotosNoDescartaNada() {
        let lista: [(foto: Int32, puntaje: Float)] = [(0, 1), (1, 0.5)]
        let r = Texturizar.consistentes(lista, colores: [SIMD3(0, 0, 0), SIMD3(255, 255, 255)])
        XCTAssertEqual(r.map(\.foto), [0, 1])
    }

    func testEscalasPorDensidadIgualanLaResolucion() {
        // Same rectangle size, but the second patch was shot 4 × closer (4 × the pixels per metre).
        let s = Atlas.escalasPorDensidad(areas: [100, 100], densidades: [10, 40], capacidad: 100)
        XCTAssertEqual(s[0] / s[1], 4, accuracy: 0.05)
        XCTAssertLessThanOrEqual(100 * s[0] * s[0] + 100 * s[1] * s[1], 100.5)
        XCTAssertEqual(s[0], 0.97, accuracy: 0.01)
        // With room to spare nothing shrinks.
        XCTAssertEqual(Atlas.escalasPorDensidad(areas: [100, 100], densidades: [10, 40], capacidad: 1000), [1, 1])
    }

    func testDensidad() {
        // A 0.4 m square covering 40 × 40 photo pixels: 100 px per metre.
        let uvs: [Float] = [0, 0, 0.4, 0, 0.4, 0.4, 0, 0, 0.4, 0.4, 0, 0.4]
        let d = Atlas.densidad([0, 1], malla: cuadro, uvFoto: uvs, tamano: SIMD2(100, 100))
        XCTAssertEqual(d, 100, accuracy: 0.5)
    }
}
