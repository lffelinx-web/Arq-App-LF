import simd
import XCTest
@testable import ArqLF

final class AtlasTests: XCTestCase {
    private let cuadro = PiezaMalla(
        vertices: [(-0.2, -0.2, -1), (0.2, -0.2, -1), (0.2, 0.2, -1), (-0.2, 0.2, -1)],
        normales: Array(repeating: (0, 0, 1), count: 4),
        indices: [0, 1, 2, 0, 2, 3]
    )

    private func foto(gris: UInt8) -> Fotograma {
        Fotograma(camaraAMundo: matrix_identity_float4x4, fx: 2, fy: 2, cx: 4, cy: 4, ancho: 8, alto: 8,
                  rgba: [UInt8](repeating: gris, count: 8 * 8 * 4))
    }

    private func solida(_ c: (UInt8, UInt8, UInt8), lado: Int = 16) -> ImagenRGBA {
        var pixeles: [UInt8] = []
        for _ in 0..<(lado * lado) { pixeles += [c.0, c.1, c.2, 255] }
        return ImagenRGBA(ancho: lado, alto: lado, pixeles: pixeles)
    }

    private func centro(_ t: Atlas.Tarea) -> (Int, Int) {
        let c = (t.destino[0] + t.destino[1] + t.destino[2]) / 3
        return (Int(c.x), Int(c.y))
    }

    func testEmpaquetar() {
        let tamanos = [SIMD2(30, 20), SIMD2(30, 20), SIMD2(30, 10)]
        let u = Atlas.empaquetar(tamanos, lado: 64, maximoAtlas: 1)
        XCTAssertNotNil(u)
        XCTAssertTrue(u!.allSatisfy { $0.atlas == 0 })
        XCTAssertNil(Atlas.empaquetar(tamanos, lado: 32, maximoAtlas: 1))
        XCTAssertNotNil(Atlas.empaquetar(tamanos, lado: 32, maximoAtlas: 3))
    }

    func testParches() {
        XCTAssertEqual(Atlas.parches(cuadro, etiquetas: [0, 0]).count, 1)
        XCTAssertEqual(Atlas.parches(cuadro, etiquetas: [0, 1]).count, 2)
        XCTAssertEqual(Atlas.parches(cuadro, etiquetas: [0, -1]).count, 1)
    }

    func testHorneaLaFotoEnElAtlas() {
        let fotos = [foto(gris: 100)]
        let etiquetas: [Int32] = [0, 0]
        let uvs = Texturizar.uvs(cuadro, etiquetas: etiquetas, fotogramas: fotos)
        let plan = Atlas.planificar(cuadro, etiquetas: etiquetas, uvFoto: uvs, fotogramas: fotos, tamanos: [SIMD2(16, 16)], lado: 64, maximoAtlas: 1)
        XCTAssertEqual(plan.numeroAtlas, 1)
        XCTAssertEqual(plan.malla.numeroTriangulos, 2)
        XCTAssertEqual(plan.malla.grupos, [.init(foto: 0, inicio: 0, triangulos: 2)])
        XCTAssertTrue(plan.malla.uvs.allSatisfy { $0 > 0 && $0 < 1 })

        let imagen = Atlas.hornear(plan, atlas: 0) { _ in self.solida((200, 50, 50)) }
        let (x, y) = centro(plan.tareas[0])
        XCTAssertEqual(imagen.color(x, y), SIMD3(200, 50, 50))
    }

    func testTriangulosSinFotoUsanElColorDeVertice() {
        var malla = cuadro
        malla.colores = Array(repeating: (10, 200, 30), count: 4)
        let fotos = [foto(gris: 100)]
        let etiquetas: [Int32] = [0, -1]
        let uvs = Texturizar.uvs(malla, etiquetas: etiquetas, fotogramas: fotos)
        let plan = Atlas.planificar(malla, etiquetas: etiquetas, uvFoto: uvs, fotogramas: fotos, tamanos: [SIMD2(16, 16)], lado: 64, maximoAtlas: 1)
        let imagen = Atlas.hornear(plan, atlas: 0) { _ in self.solida((200, 50, 50)) }
        let tarea = plan.tareas.first { $0.foto < 0 }!
        let (x, y) = centro(tarea)
        XCTAssertEqual(imagen.color(x, y), SIMD3(10, 200, 30))
    }

    func testNivelaLasCosturasEntreFotos() {
        // Triangle 0 from a darker photo, triangle 1 from a brighter one.
        let fotos = [foto(gris: 100), foto(gris: 140)]
        let etiquetas: [Int32] = [0, 1]
        let uvs = Texturizar.uvs(cuadro, etiquetas: etiquetas, fotogramas: fotos)
        let d = Atlas.nivelarCosturas(cuadro, etiquetas: etiquetas, uvFoto: uvs, fotogramas: fotos)
        // Shared corners (0 and 2) meet halfway, at 120.
        XCTAssertEqual(d[Atlas.clave(0, 0)]?.x ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(d[Atlas.clave(0, 1)]?.x ?? 0, -20, accuracy: 0.01)
        XCTAssertEqual(d[Atlas.clave(2, 1)]?.y ?? 0, -20, accuracy: 0.01)
        // The correction spreads into each patch.
        XCTAssertEqual(d[Atlas.clave(1, 0)]?.x ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(d[Atlas.clave(3, 1)]?.x ?? 0, -20, accuracy: 0.01)
    }

    func testDilatarRellenaElBorde() {
        var imagen = ImagenRGBA(ancho: 4, alto: 1)
        imagen.poner(0, 0, SIMD3(90, 90, 90))
        imagen.dilatar(pasadas: 2)
        XCTAssertTrue(imagen.ocupado(2, 0))
        XCTAssertFalse(imagen.ocupado(3, 0))
        XCTAssertEqual(imagen.color(2, 0), SIMD3(90, 90, 90))
    }

    // MARK: Colour fill and cracks

    func testRellenarColorDesdeLosVecinos() {
        let tira = PiezaMalla(vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)], normales: [], indices: [0, 1, 2, 1, 3, 2])
        let colores: [(UInt8, UInt8, UInt8)] = [(200, 0, 0), (170, 170, 170), (170, 170, 170), (170, 170, 170)]
        let r = Colorear.rellenar(colores, vistos: [true, false, false, false], malla: tira)
        XCTAssertTrue(r[1] == (200, 0, 0))
        XCTAssertTrue(r[3] == (200, 0, 0))
    }

    func testRellenaRendijasLargasYDelgadas() {
        // 3 × 3 grid whose middle cell is a 1 m × 2 cm crack.
        let xs: [Float] = [0, 0.1, 1.1, 1.2], ys: [Float] = [0, 0.1, 0.12, 0.22]
        var vertices: [(Float, Float, Float)] = []
        for y in ys { for x in xs { vertices.append((x, y, 0)) } }
        var indices: [UInt32] = []
        for y in 0..<3 {
            for x in 0..<3 where !(x == 1 && y == 1) {
                let a = UInt32(y * 4 + x), b = a + 1, c = a + 5, d = a + 4
                indices += [a, b, c, a, c, d]
            }
        }
        let m = PiezaMalla(vertices: vertices, normales: [], indices: indices)
        XCTAssertEqual(LimpiezaMalla.rellenarHuecos(m).triangulos, 20)
    }
}
