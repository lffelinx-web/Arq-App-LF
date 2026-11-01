import simd
import XCTest
@testable import ArqLF

final class TexturaTests: XCTestCase {
    /// 0.4 m square facing +Z, one metre in front of a camera at the origin.
    private let cuadro = PiezaMalla(
        vertices: [(-0.2, -0.2, -1), (0.2, -0.2, -1), (0.2, 0.2, -1), (-0.2, 0.2, -1)],
        normales: [(0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1)],
        indices: [0, 1, 2, 0, 2, 3]
    )

    private func foto(en posicion: SIMD3<Float> = .zero) -> Fotograma {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(posicion, 1)
        return Fotograma(camaraAMundo: transform, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8, rgba: [UInt8](repeating: 128, count: 8 * 8 * 4))
    }

    func testUnirDesplazaLosIndices() {
        let unida = Texturizar.unir([cuadro, cuadro])
        XCTAssertEqual(unida.vertices.count, 8)
        XCTAssertEqual(unida.normales.count, 8)
        XCTAssertEqual(Array(unida.indices.suffix(6)), [4, 5, 6, 4, 6, 7])
    }

    func testCadaTrianguloTomaLaFotoQueLoVe() {
        // The second camera is behind the square and can't see it.
        let etiquetas = Texturizar.etiquetas(cuadro, fotogramas: [foto(en: SIMD3(0, 0, -3)), foto()])
        XCTAssertEqual(etiquetas, [1, 1])
    }

    func testSinFotoQueLoVeQuedaSinTextura() {
        XCTAssertEqual(Texturizar.etiquetas(cuadro, fotogramas: [foto(en: SIMD3(0, 0, -3))]), [-1, -1])
        XCTAssertEqual(Texturizar.etiquetas(cuadro, fotogramas: []), [-1, -1])
    }

    func testConstruirAgrupaYDaUVsDentroDeLaFoto() throws {
        let m = Texturizar.construir(cuadro, fotogramas: [foto()])
        XCTAssertEqual(m.numeroTriangulos, 2)
        XCTAssertEqual(m.grupos, [.init(foto: 0, inicio: 0, triangulos: 2)])
        XCTAssertEqual(m.uvs.count, 12)
        XCTAssertTrue(m.uvs.allSatisfy { $0 > 0.4 && $0 < 0.6 })
        // First corner (-0.2, -0.2): left of centre and, being low, below it in the image.
        XCTAssertEqual(m.uvs[0], 0.45, accuracy: 1e-5)
        XCTAssertEqual(m.uvs[1], 0.55, accuracy: 1e-5)
    }

    func testBinarioIdaYVuelta() throws {
        let m = Texturizar.construir(cuadro, fotogramas: [foto()])
        XCTAssertEqual(try Texturizar.leer(Texturizar.datos(m)), m)
        XCTAssertThrowsError(try Texturizar.leer(Data("nada".utf8)))
    }

    func testOBJConMateriales() throws {
        let m = Texturizar.construir(cuadro, fotogramas: [foto()])
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }

        try Texturizar.escribirOBJ(m, en: carpeta)
        let obj = try String(contentsOf: carpeta.appendingPathComponent("modelo.obj"), encoding: .utf8)
        let mtl = try String(contentsOf: carpeta.appendingPathComponent("modelo.mtl"), encoding: .utf8)
        let lineas = obj.split(separator: "\n").map(String.init)

        XCTAssertTrue(lineas.contains("mtllib modelo.mtl"))
        XCTAssertTrue(lineas.contains("usemtl foto_0"))
        XCTAssertEqual(lineas.filter { $0.hasPrefix("v ") }.count, 6)
        XCTAssertEqual(lineas.filter { $0.hasPrefix("vt ") }.count, 6)
        XCTAssertTrue(lineas.contains("f 1/1/1 2/2/2 3/3/3"))
        XCTAssertTrue(lineas.contains("vt 0.45 0.45"), "La V del OBJ crece hacia arriba")
        XCTAssertTrue(mtl.contains("map_Kd foto_0.jpg"))
    }
}
