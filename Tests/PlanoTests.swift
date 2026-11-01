import XCTest
@testable import ArqLF

final class PlanoTests: XCTestCase {
    /// A 4 × 3 m room, 2.5 m high, with one door and one window.
    private func cuarto() -> PlanoPlanta {
        let esquinas = [Punto2D(0, 0), Punto2D(4, 0), Punto2D(4, 3), Punto2D(0, 3)]
        var plano = PlanoPlanta()
        plano.muros = (0..<4).map { Muro(a: esquinas[$0], b: esquinas[($0 + 1) % 4], altura: 2.5) }
        plano.pisos = [esquinas]
        plano.aberturas = [
            Abertura(tipo: .puerta, a: Punto2D(1, 0), b: Punto2D(1.9, 0), altura: 2.1),
            Abertura(tipo: .ventana, a: Punto2D(4, 1), b: Punto2D(4, 2.2), altura: 1.2, elevacion: 0.9),
        ]
        plano.muebles = [Mueble(nombre: "Cama", centro: Punto2D(2, 2), ancho: 1.4, fondo: 1.9, alto: 0.5, angulo: 0)]
        return plano
    }

    func testResumen() {
        let p = cuarto()
        XCTAssertEqual(p.area, 12, accuracy: 1e-9)
        XCTAssertEqual(p.perimetro, 14, accuracy: 1e-9)
        XCTAssertEqual(p.alturaPromedio, 2.5, accuracy: 1e-9)
        XCTAssertEqual(p.volumen, 30, accuracy: 1e-9)
        XCTAssertEqual(p.areaMurosNeta, 35 - 0.9 * 2.1 - 1.2 * 1.2, accuracy: 1e-9)
        XCTAssertEqual(p.cuenta(.puerta), 1)
        XCTAssertEqual(p.cuenta(.ventana), 1)
    }

    func testAreaSinPisoUsaLosMuros() {
        var p = cuarto()
        p.pisos = []
        XCTAssertEqual(p.area, 12, accuracy: 1e-9)
        XCTAssertEqual(p.perimetro, 14, accuracy: 1e-9)
    }

    func testCodificacionIdaYVuelta() throws {
        let p = cuarto()
        let datos = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(PlanoPlanta.self, from: datos), p)
    }

    func testCSVDelPlano() {
        let csv = CSV.plano(cuarto())
        XCTAssertTrue(csv.hasPrefix("Elemento,"))
        XCTAssertTrue(csv.contains("Muro 1,Muro,4.000,2.500,,,10.000"))
        XCTAssertTrue(csv.contains("Ventana 1,Ventana,1.200,1.200,,0.900,1.440"))
        XCTAssertTrue(csv.contains("Piso,Total,,,,,12.000"))
    }

    func testAlmacenGuardaYCarga() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: raiz) }
        let almacen = Almacen(raiz: raiz)
        var proyecto = Proyecto(nombre: "Sala", tipo: .cuarto)
        proyecto.medidas = [Medida(nombre: "Ancho", metros: 3.2)]
        try almacen.guardar(proyecto)
        try almacen.guardar(cuarto(), de: proyecto)

        let otro = Almacen(raiz: raiz)
        XCTAssertEqual(otro.proyectos.count, 1)
        XCTAssertEqual(otro.proyectos.first?.nombre, "Sala")
        XCTAssertEqual(otro.proyectos.first?.medidas.first?.metros, 3.2)
        XCTAssertEqual(otro.plano(de: proyecto)?.muros.count, 4)
        XCTAssertEqual(otro.nombreSugerido(.cuarto), "Cuarto 2")

        otro.eliminar(proyecto)
        XCTAssertTrue(otro.proyectos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: otro.carpeta(proyecto).path))
    }
}
