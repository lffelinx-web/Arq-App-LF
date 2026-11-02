import XCTest
@testable import ArqLF

final class RecorteSinFotoTests: XCTestCase {
    /// 2 m × 2 m floor of 10 cm squares (two triangles each, row-major), plus
    /// optionally a loose 3 × 3 piece floating 1 m above.
    private func piso(suelta: Bool = false) -> PiezaMalla {
        var m = PiezaMalla(vertices: [], normales: [], indices: [])
        func rejilla(_ lado: Int, y: Float) {
            let base = UInt32(m.vertices.count)
            for j in 0...lado { for i in 0...lado { m.vertices.append((Float(i) * 0.1, y, Float(j) * 0.1)); m.normales.append((0, 1, 0)) } }
            let fila = UInt32(lado + 1)
            for j in 0..<lado {
                for i in 0..<lado {
                    let a = base + UInt32(j) * fila + UInt32(i), b = a + 1, c = a + fila + 1, d = a + fila
                    m.indices += [a, c, b, a, d, c]
                }
            }
        }
        rejilla(20, y: 0)
        if suelta { rejilla(3, y: 1) }
        return m
    }

    /// Triangles of the square at column i, row j.
    private func cuadro(_ i: Int, _ j: Int) -> [Int] { [(j * 20 + i) * 2, (j * 20 + i) * 2 + 1] }

    func testQuitaManchasEnLaOrillaYConservaHuecosInteriores() {
        let m = piso()
        var etiquetas = [Int32](repeating: 0, count: m.triangulos)
        // A 3 × 3 patch at the corner (the scanner's feet) and a 2 × 2 one in the middle.
        for j in 0..<3 { for i in 0..<3 { for t in cuadro(i, j) { etiquetas[t] = -1 } } }
        for j in 9..<11 { for i in 9..<11 { for t in cuadro(i, j) { etiquetas[t] = -1 } } }
        let r = LimpiezaMalla.recortarSinFoto(m, etiquetas: etiquetas)
        XCTAssertEqual(r.malla.triangulos, m.triangulos - 18)
        XCTAssertEqual(r.etiquetas.count, r.malla.triangulos)
        XCTAssertEqual(r.etiquetas.filter { $0 < 0 }.count, 8, "El hueco interior se queda")
        XCTAssertFalse(r.malla.vertices.contains { $0.0 < 0.15 && $0.2 < 0.15 }, "La esquina sin foto se va")
    }

    func testQuitaPiezasSueltasSinFoto() {
        let m = piso(suelta: true)
        var etiquetas = [Int32](repeating: 0, count: m.triangulos)
        for t in 800..<m.triangulos { etiquetas[t] = -1 }
        let r = LimpiezaMalla.recortarSinFoto(m, etiquetas: etiquetas)
        XCTAssertEqual(r.malla.triangulos, 800)
        XCTAssertFalse(r.malla.vertices.contains { $0.1 > 0.5 })
    }

    func testNoTocaNadaSiCasiTodoQuedaSinFoto() {
        let m = piso()
        var etiquetas = [Int32](repeating: -1, count: m.triangulos)
        etiquetas[400] = 3
        let r = LimpiezaMalla.recortarSinFoto(m, etiquetas: etiquetas)
        XCTAssertEqual(r.malla.triangulos, m.triangulos)
        XCTAssertEqual(r.etiquetas, etiquetas)
    }
}
