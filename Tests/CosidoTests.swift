import simd
import XCTest
@testable import ArqLF

final class CosidoTests: XCTestCase {
    /// Floor strip of 10 cm squares from x0 to x0 + ancho·0.1, 1 m deep.
    private func tira(desde x0: Float, columnas: Int) -> PiezaMalla {
        var vertices: [(Float, Float, Float)] = []
        for j in 0...10 { for i in 0...columnas { vertices.append((x0 + Float(i) * 0.1, 0, Float(j) * 0.1)) } }
        var indices: [UInt32] = []
        let fila = UInt32(columnas + 1)
        for j in 0..<10 {
            for i in 0..<columnas {
                let a = UInt32(j) * fila + UInt32(i), b = a + 1, c = a + fila + 1, d = a + fila
                indices += [a, c, b, a, d, c]
            }
        }
        return PiezaMalla(vertices: vertices, normales: Array(repeating: (0, 1, 0), count: vertices.count), indices: indices)
    }

    private func piezas(_ m: PiezaMalla) -> Int {
        var padre = Array(0..<m.vertices.count)
        func raiz(_ x: Int) -> Int { var x = x; while padre[x] != x { x = padre[x] }; return x }
        for t in 0..<m.triangulos {
            let a = raiz(Int(m.indices[t * 3])), b = raiz(Int(m.indices[t * 3 + 1])), c = raiz(Int(m.indices[t * 3 + 2]))
            padre[b] = a; padre[raiz(c)] = a
        }
        return Set(m.indices.map { raiz(Int($0)) }).count
    }

    func testCoseUnaRendijaDelgada() {
        let a = tira(desde: 0, columnas: 5), b = tira(desde: 0.515, columnas: 5)
        let unida = Texturizar.unir([a, b])
        XCTAssertEqual(piezas(unida), 2)
        let r = LimpiezaMalla.coserBordes(unida)
        XCTAssertEqual(r.triangulos, unida.triangulos, "No se pierde ningún triángulo")
        XCTAssertEqual(piezas(r), 1, "Las dos piezas quedan cosidas")
        // The seam sits halfway across the crack.
        let usados = Set(r.indices.map(Int.init))
        let enCostura = usados.map { r.vertices[$0].0 }.filter { $0 > 0.45 && $0 < 0.56 }
        XCTAssertFalse(enCostura.isEmpty)
        for x in enCostura { XCTAssertEqual(x, 0.5075, accuracy: 1e-4) }
    }

    func testNoCoseHuecosAnchos() {
        let unida = Texturizar.unir([tira(desde: 0, columnas: 5), tira(desde: 0.55, columnas: 5)])
        let r = LimpiezaMalla.coserBordes(unida)
        XCTAssertEqual(piezas(r), 2)
        XCTAssertEqual(r.indices, unida.indices)
    }

    func testCerrarRendijasConservaMallaSinRendijas() {
        let m = tira(desde: 0, columnas: 10)
        let r = LimpiezaMalla.cerrarRendijas(m)
        XCTAssertEqual(r.triangulos, m.triangulos)
        XCTAssertEqual(r.vertices.count, m.vertices.count)
    }

    func testRevierteTriangulosVolteados() {
        let m = tira(desde: 0, columnas: 3)
        var nueva = m
        // Push one vertex across its neighbours so its triangles fold over.
        nueva.vertices[15] = (0.0, 0, 0.0)
        nueva.vertices[1] = (0.105, 0, 0.0)
        let r = Planos.revertirVolteados(original: m, nueva: nueva)
        XCTAssertTrue(r.vertices[15] == m.vertices[15], "El vértice que volteó triángulos regresa")
        XCTAssertTrue(r.vertices[1] == nueva.vertices[1], "Un ajuste pequeño se conserva")
    }
}
