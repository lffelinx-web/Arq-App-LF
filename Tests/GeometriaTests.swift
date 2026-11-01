import XCTest
@testable import ArqLF

final class GeometriaTests: XCTestCase {
    func testAreaDeRectangulo() {
        let cuarto = [Punto2D(0, 0), Punto2D(4, 0), Punto2D(4, 3), Punto2D(0, 3)]
        XCTAssertEqual(Geometria.area(cuarto), 12, accuracy: 1e-9)
        XCTAssertEqual(Geometria.perimetro(cuarto), 14, accuracy: 1e-9)
    }

    func testAreaNoDependeDelSentido() {
        let horario = [Punto2D(0, 0), Punto2D(0, 3), Punto2D(4, 3), Punto2D(4, 0)]
        XCTAssertEqual(Geometria.area(horario), 12, accuracy: 1e-9)
    }

    func testAreaDeFormaEnL() {
        let l = [Punto2D(0, 0), Punto2D(4, 0), Punto2D(4, 2), Punto2D(2, 2), Punto2D(2, 4), Punto2D(0, 4)]
        XCTAssertEqual(Geometria.area(l), 12, accuracy: 1e-9)
    }

    func testPoligonoDegenerado() {
        XCTAssertEqual(Geometria.area([Punto2D(0, 0), Punto2D(1, 1)]), 0)
        XCTAssertEqual(Geometria.perimetro([]), 0)
    }

    func testRectanguloRotado() {
        let esquinas = Geometria.rectangulo(centro: Punto2D(1, 1), ancho: 2, fondo: 1, angulo: .pi / 2)
        XCTAssertEqual(Geometria.area(esquinas), 2, accuracy: 1e-9)
        let l = Limites(esquinas)!
        XCTAssertEqual(l.ancho, 1, accuracy: 1e-9)
        XCTAssertEqual(l.alto, 2, accuracy: 1e-9)
    }

    func testDistancia3D() {
        XCTAssertEqual(Geometria.distancia((0, 0, 0), (1, 2, 2)), 3, accuracy: 1e-9)
    }
}
