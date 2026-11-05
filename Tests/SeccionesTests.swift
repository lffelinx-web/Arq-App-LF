import XCTest
@testable import ArqLF

final class SeccionesTests: XCTestCase {
    /// Floor of 10 cm squares from x0, `columnas` wide and 1 m deep, at height y.
    private func piso(desde x0: Float, columnas: Int, y: Float = 0) -> PiezaMalla {
        var vertices: [(Float, Float, Float)] = []
        for j in 0...10 { for i in 0...columnas { vertices.append((x0 + Float(i) * 0.1, y, Float(j) * 0.1)) } }
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

    private func plano(_ m: PiezaMalla) -> [Float] { m.vertices.flatMap { [$0.0, $0.1, $0.2] } }

    func testQuitaElTraslapeConLaSeccionAnterior() {
        let anterior = piso(desde: 0, columnas: 10)
        let ocupado = Secciones.celdas(vertices: plano(anterior), indices: anterior.indices)
        // The new section covers x 0.55…2.05, 1 cm higher and shifted by half a
        // square: its vertices don't coincide with the old ones.
        let nueva = piso(desde: 0.55, columnas: 15, y: 0.01)
        let r = LimpiezaMalla.quitarTraslape(nueva, ocupado: ocupado)
        XCTAssertLessThan(r.triangulos, nueva.triangulos)
        let xs = r.indices.map { r.vertices[Int($0)].0 }
        XCTAssertGreaterThan(xs.min() ?? 0, 0.9, "Lo que ya estaba escaneado se quita")
        XCTAssertEqual(xs.max() ?? 0, 2.05, accuracy: 1e-4, "La zona nueva se conserva")
    }

    func testNoQuitaSuperficiesSeparadas() {
        let anterior = piso(desde: 0, columnas: 10)
        let ocupado = Secciones.celdas(vertices: plano(anterior), indices: anterior.indices)
        // A table top 75 cm above the old floor stays.
        let mesa = piso(desde: 0, columnas: 10, y: 0.75)
        XCTAssertEqual(LimpiezaMalla.quitarTraslape(mesa, ocupado: ocupado).triangulos, mesa.triangulos)
    }

    func testCarpetasDeSecciones() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("Secciones-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        XCTAssertEqual(Secciones.siguiente(en: raiz), 2)
        XCTAssertEqual(Secciones.carpetas(en: raiz), [raiz])
        for n in [3, 2, 10] {
            try FileManager.default.createDirectory(at: Secciones.carpeta(n, en: raiz), withIntermediateDirectories: true)
        }
        XCTAssertEqual(Secciones.siguiente(en: raiz), 11)
        XCTAssertEqual(Secciones.carpetas(en: raiz).map(\.lastPathComponent), [raiz.lastPathComponent, "2", "3", "10"])
    }

    func testPiezaDesdePLY() throws {
        var m = piso(desde: 0, columnas: 2)
        m.colores = Array(repeating: (10, 20, 30), count: m.vertices.count)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try PLY.escribir([m], en: url)
        let r = PiezaMalla(try PLY.leer(url))
        XCTAssertEqual(r.indices, m.indices)
        XCTAssertEqual(r.vertices.count, m.vertices.count)
        XCTAssertTrue(r.vertices[5] == m.vertices[5])
        XCTAssertTrue(r.colores[3] == (10, 20, 30))
    }

    func testMasAtlasParaZonasGrandes() {
        XCTAssertEqual(Atlas.maximoAtlas(area: 40), 4)
        XCTAssertEqual(Atlas.maximoAtlas(area: 120), 6)
        XCTAssertEqual(Atlas.maximoAtlas(area: 400), 8)
        XCTAssertEqual(Atlas.area(piso(desde: 0, columnas: 10)), 1, accuracy: 1e-4)
        XCTAssertEqual(EscenaMalla.ladoVisor(atlas: 4), 4096)
        XCTAssertEqual(EscenaMalla.ladoVisor(atlas: 16), 2048)
        XCTAssertEqual(EscenaMalla.ladoVisor(atlas: 80), 1024)
    }
}
