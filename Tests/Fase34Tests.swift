import XCTest
@testable import ArqLF

final class Fase34Tests: XCTestCase {
    /// Grid of `ancho` × `alto` squares of 10 cm starting at (x0, y0).
    private func rejilla(ancho: Int, alto: Int, x0: Float = 0, y0: Float = 0, base: UInt32 = 0) -> PiezaMalla {
        var vertices: [(Float, Float, Float)] = []
        for y in 0...alto { for x in 0...ancho { vertices.append((x0 + Float(x) * 0.1, y0 + Float(y) * 0.1, 0)) } }
        var indices: [UInt32] = []
        let fila = UInt32(ancho + 1)
        for y in 0..<alto {
            for x in 0..<ancho {
                let a = base + UInt32(y) * fila + UInt32(x), b = a + 1, c = a + fila + 1, d = a + fila
                indices += [a, b, c, a, c, d]
            }
        }
        return PiezaMalla(vertices: vertices, normales: [], indices: indices)
    }

    func testAbrirQuitaLaminasDelgadasYConservaLoGrande() {
        let grande = rejilla(ancho: 10, alto: 10)
        // A loose strip one square wide and eight long, away from the grid.
        let tira = rejilla(ancho: 8, alto: 1, x0: 2, y0: 2, base: UInt32(grande.vertices.count))
        let m = PiezaMalla(vertices: grande.vertices + tira.vertices, normales: [], indices: grande.indices + tira.indices)
        XCTAssertEqual(m.triangulos, 216)

        let r = LimpiezaMalla.abrir(m)
        let primerVerticeTira = UInt32(grande.vertices.count)
        XCTAssertFalse(r.indices.contains { $0 >= primerVerticeTira }, "La tira suelta desaparece")
        XCTAssertGreaterThanOrEqual(r.triangulos, 190, "La zona grande se conserva casi completa")
    }

    func testAbrirNoBorraUnaMallaQueEsTodaDelgada() {
        let tira = rejilla(ancho: 8, alto: 1)
        XCTAssertEqual(LimpiezaMalla.abrir(tira).triangulos, tira.triangulos)
    }
}
