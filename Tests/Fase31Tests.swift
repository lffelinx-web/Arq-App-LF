import simd
import XCTest
@testable import ArqLF

final class Fase31Tests: XCTestCase {
    // MARK: Mesh cleanup

    func testSoldarUnePiezasSeparadas() {
        // Two triangles sharing an edge, but as ARKit pieces: the shared corners
        // are duplicated and 1 mm apart.
        let m = PiezaMalla(
            vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1.001, 0, 0), (1, 1, 0), (0, 1.001, 0)],
            normales: Array(repeating: (0, 0, 1), count: 6),
            indices: [0, 1, 2, 3, 4, 5]
        )
        let soldada = LimpiezaMalla.soldar(m)
        XCTAssertEqual(soldada.vertices.count, 4)
        XCTAssertEqual(soldada.triangulos, 2)
        XCTAssertEqual(soldada.normales.count, 4)
    }

    func testSoldarQuitaTriangulosDegeneradosYRepetidos() {
        let m = PiezaMalla(
            vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0.001, 0, 0)],
            normales: [],
            indices: [0, 1, 2, 0, 3, 1, 2, 0, 1]
        )
        XCTAssertEqual(LimpiezaMalla.soldar(m).triangulos, 1)
    }

    func testQuitarFragmentosSueltos() {
        let m = PiezaMalla(
            vertices: [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (5, 5, 5), (6, 5, 5), (5, 6, 5)],
            normales: [],
            indices: [0, 1, 2, 0, 2, 3, 4, 5, 6]
        )
        let limpia = LimpiezaMalla.compactar(LimpiezaMalla.quitarFragmentos(m, minimo: 2))
        XCTAssertEqual(limpia.triangulos, 2)
        XCTAssertEqual(limpia.vertices.count, 4)
    }

    /// 4 × 4 grid with 20 cm squares and the middle square missing.
    private func rejillaConHueco() -> PiezaMalla {
        var vertices: [(Float, Float, Float)] = []
        for y in 0..<4 { for x in 0..<4 { vertices.append((Float(x) * 0.2, Float(y) * 0.2, 0)) } }
        var indices: [UInt32] = []
        for y in 0..<3 {
            for x in 0..<3 where !(x == 1 && y == 1) {
                let a = UInt32(y * 4 + x), b = a + 1, c = a + 5, d = a + 4
                indices += [a, b, c, a, c, d]
            }
        }
        return PiezaMalla(vertices: vertices, normales: Array(repeating: (0, 0, 1), count: 16), indices: indices)
    }

    func testRellenaHuecosPequenosPeroNoElBorde() {
        let m = rejillaConHueco()
        XCTAssertEqual(m.triangulos, 16)
        let rellena = LimpiezaMalla.rellenarHuecos(m)
        // The 80 cm hole gets a 4-triangle fan; the 2.4 m outer border is left alone.
        XCTAssertEqual(rellena.triangulos, 20)
        XCTAssertEqual(rellena.vertices.count, 17)
        let centro = rellena.vertices[16]
        XCTAssertEqual(centro.0, 0.3, accuracy: 1e-5)
        XCTAssertEqual(centro.1, 0.3, accuracy: 1e-5)
    }

    func testLimpiarConservaUnaMallaSana() {
        let limpia = LimpiezaMalla.limpiar(rejillaConHueco())
        XCTAssertEqual(limpia.triangulos, 20)
        XCTAssertEqual(limpia.vertices.count, 17)
    }

    // MARK: Exposure

    func testGananciasIgualanUnaFotoMasClara() {
        let observaciones: [[Exposicion.Observacion]] = (0..<50).map { i in
            let base = SIMD3<Float>(40 + Float(i), 50, 60)
            return [.init(foto: 0, color: base), .init(foto: 1, color: base * 2)]
        }
        let g = Exposicion.ganancias(observaciones, fotos: 3)
        let razon = g[0] / g[1]
        XCTAssertGreaterThan(razon.x, 1.7)
        XCTAssertLessThan(razon.x, 2.1)
        XCTAssertEqual(razon.x, razon.z, accuracy: 0.05)
        // Brightness is kept: the gains of the photos that overlap average to 1.
        XCTAssertEqual((g[0].x * g[1].x).squareRoot(), 1, accuracy: 0.02)
        // A photo with no overlap keeps its colours.
        XCTAssertEqual(g[2], SIMD3<Float>(repeating: 1))
    }

    func testColorAplicaLaGanancia() {
        var f = Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: [UInt8](repeating: 100, count: 256))
        f.ganancia = SIMD3(1.5, 1, 0.5)
        XCTAssertEqual(f.color(u: 3, v: 3), SIMD3(150, 100, 50))
        XCTAssertEqual(f.colorCrudo(u: 3, v: 3), SIMD3(100, 100, 100))
    }

    // MARK: Sharpness

    func testNitidez() {
        let liso = [UInt8](repeating: 128, count: 16 * 16 * 4)
        XCTAssertEqual(Fotograma.nitidez(rgba: liso, ancho: 16, alto: 16), 0, accuracy: 1e-3)
        var ajedrez = [UInt8]()
        for y in 0..<16 { for x in 0..<16 { let v: UInt8 = (x + y) % 2 == 0 ? 0 : 255; ajedrez += [v, v, v, 255] } }
        XCTAssertGreaterThan(Fotograma.nitidez(rgba: ajedrez, ancho: 16, alto: 16), 1000)
    }

    // MARK: Labelling

    func testSuavizadoUneTriangulosVecinosEnUnaFoto() {
        let cuadro = PiezaMalla(
            vertices: [(-0.2, -0.2, -1), (0.2, -0.2, -1), (0.2, 0.2, -1), (-0.2, 0.2, -1)],
            normales: Array(repeating: (0, 0, 1), count: 4),
            indices: [0, 1, 2, 0, 2, 3]
        )
        func foto(_ x: Float) -> Fotograma {
            var t = matrix_identity_float4x4
            t.columns.3 = SIMD4(x, 0, 0, 1)
            return Fotograma(camaraAMundo: t, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: [UInt8](repeating: 128, count: 256))
        }
        // Each triangle is a little closer to a different camera.
        let fotos = [foto(-0.05), foto(0.05)]
        let sinSuavizar = Texturizar.etiquetas(cuadro, fotogramas: fotos, pasadas: 0)
        XCTAssertEqual(sinSuavizar, [1, 0])
        let suavizadas = Texturizar.etiquetas(cuadro, fotogramas: fotos)
        XCTAssertEqual(suavizadas[0], suavizadas[1])
    }
}
