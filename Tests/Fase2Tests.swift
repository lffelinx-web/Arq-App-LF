import simd
import XCTest
@testable import ArqLF

final class Fase2Tests: XCTestCase {
    private func temporal(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    // MARK: PLY

    func testPLYIdaYVueltaConColorYVariasPiezas() throws {
        let a = PiezaMalla(
            vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0)],
            normales: [(0, 0, 1), (0, 0, 1), (0, 0, 1)],
            indices: [0, 1, 2],
            colores: [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
        )
        let b = PiezaMalla(
            vertices: [(0, 0, 2), (1, 0, 2), (0, 1, 2)],
            normales: [(0, 1, 0), (0, 1, 0), (0, 1, 0)],
            indices: [0, 2, 1],
            colores: [(10, 20, 30), (40, 50, 60), (70, 80, 90)]
        )
        let url = temporal("ply")
        defer { try? FileManager.default.removeItem(at: url) }

        let totales = try PLY.escribir([a, b], en: url)
        XCTAssertEqual(totales.vertices, 6)
        XCTAssertEqual(totales.triangulos, 2)

        let malla = try PLY.leer(url)
        XCTAssertEqual(malla.numeroVertices, 6)
        XCTAssertEqual(malla.numeroTriangulos, 2)
        XCTAssertEqual(Array(malla.vertices[9..<12]), [0, 0, 2])
        XCTAssertEqual(Array(malla.normales[9..<12]), [0, 1, 0])
        XCTAssertEqual(Array(malla.colores[0..<3]), [255, 0, 0])
        XCTAssertEqual(Array(malla.colores[15..<18]), [70, 80, 90])
        // The second piece's indices are shifted by the first piece's vertices.
        XCTAssertEqual(malla.indices, [0, 1, 2, 3, 5, 4])
    }

    func testPLYSinColor() throws {
        let pieza = PiezaMalla(vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0)], normales: [], indices: [0, 1, 2])
        let url = temporal("ply")
        defer { try? FileManager.default.removeItem(at: url) }
        try PLY.escribir([pieza], en: url)
        let malla = try PLY.leer(url)
        XCTAssertTrue(malla.colores.isEmpty)
        XCTAssertTrue(malla.normales.isEmpty)
        XCTAssertEqual(malla.indices, [0, 1, 2])
    }

    func testOBJConColor() {
        let pieza = PiezaMalla(vertices: [(0, 0, 0)], normales: [], indices: [], colores: [(255, 0, 51)])
        XCTAssertTrue(OBJ.texto(pieza, grupo: "g", base: 0).contains("v 0 0 0 1.000 0.000 0.200\n"))
    }

    // MARK: DXF

    func testDXFTieneCapasYEntidades() {
        let esquinas = [Punto2D(0, 0), Punto2D(4, 0), Punto2D(4, 3), Punto2D(0, 3)]
        var plano = PlanoPlanta()
        plano.muros = (0..<4).map { Muro(a: esquinas[$0], b: esquinas[($0 + 1) % 4], altura: 2.5) }
        plano.aberturas = [Abertura(tipo: .puerta, a: Punto2D(1, 0), b: Punto2D(1.9, 0), altura: 2.1)]
        let dxf = DXF.texto(plano)
        let lineas = dxf.split(separator: "\n").map(String.init)

        XCTAssertTrue(dxf.hasPrefix("0\nSECTION\n"))
        XCTAssertTrue(dxf.hasSuffix("0\nEOF\n"))
        for capa in DXF.Capa.allCases { XCTAssertTrue(lineas.contains(capa.rawValue), capa.rawValue) }
        XCTAssertEqual(lineas.filter { $0 == "LINE" }.count, 5)
        XCTAssertEqual(lineas.filter { $0 == "ARC" }.count, 1)
        XCTAssertEqual(lineas.filter { $0 == "TEXT" }.count, 4)
        XCTAssertTrue(lineas.contains("4.00 m"))
        // Group codes and values alternate, so the line count is even.
        XCTAssertEqual(lineas.count % 2, 0)
        // Y is flipped: the wall at y = 3 is drawn at y = -3.
        XCTAssertTrue(lineas.contains("-3.0000"))
    }

    // MARK: Colour projection

    /// 8 × 8 photo from a camera at the origin looking down -Z.
    private func fotograma(color: (UInt8, UInt8, UInt8), profundidad: Float? = nil) -> Fotograma {
        var rgba = [UInt8]()
        for _ in 0..<64 { rgba += [color.0, color.1, color.2, 255] }
        var f = Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: rgba)
        if let profundidad {
            f.profundidad = [profundidad]
            f.anchoProfundidad = 1
            f.altoProfundidad = 1
        }
        return f
    }

    func testProyeccionSigueLaConvencionDeARKit() {
        let f = fotograma(color: (0, 0, 0))
        let p = f.proyectar(SIMD3(0.5, 0.5, -1), con: f.mundoACamara)
        XCTAssertEqual(p?.u ?? -1, 5, accuracy: 1e-5)
        XCTAssertEqual(p?.v ?? -1, 3, accuracy: 1e-5, "+Y sube en el mundo y baja en filas de imagen")
        XCTAssertEqual(p?.distancia ?? -1, 1, accuracy: 1e-5)
        XCTAssertNil(f.proyectar(SIMD3(0, 0, 1), con: f.mundoACamara), "Detrás de la cámara")
    }

    func testColoreaConLaFotoQueVeElPunto() {
        let colores = Colorear.colores(
            vertices: [(0, 0, -1), (0, 0, 1)],
            normales: [(0, 0, 1), (0, 0, 1)],
            fotogramas: [fotograma(color: (200, 10, 20))]
        )
        XCTAssertTrue(colores[0] == (200, 10, 20))
        XCTAssertTrue(colores[1] == Colorear.sinColor)
    }

    func testPuntoTapadoNoTomaColor() {
        // The LiDAR saw something at 0.5 m, so the point at 1 m is hidden.
        let colores = Colorear.colores(vertices: [(0, 0, -1)], normales: [], fotogramas: [fotograma(color: (200, 10, 20), profundidad: 0.5)])
        XCTAssertTrue(colores[0] == Colorear.sinColor)
    }

    func testEligeLaFotoMasCercana() {
        let lejos = fotograma(color: (255, 0, 0))
        var cerca = fotograma(color: (0, 255, 0))
        cerca.camaraAMundo.columns.3 = SIMD4(0, 0, -0.5, 1)
        let colores = Colorear.colores(vertices: [(0, 0, -1.5)], normales: [(0, 0, 1)], fotogramas: [lejos, cerca])
        XCTAssertTrue(colores[0] == (0, 255, 0))
    }
}
