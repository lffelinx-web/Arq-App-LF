import XCTest
@testable import ArqLF

final class ExportacionTests: XCTestCase {
    func testFormatoDeLongitudes() {
        XCTAssertEqual(Formato.longitud(2.456), "2.46 m")
        XCTAssertEqual(Formato.longitud(2.456, .centimetros), "246 cm")
        XCTAssertEqual(Formato.longitud(2.4384, .pies), "8' 0\"")
        XCTAssertEqual(Formato.longitud(1, .pies), "3' 3\"")
        XCTAssertEqual(Formato.area(12), "12.00 m²")
        XCTAssertEqual(Formato.volumen(30), "30.00 m³")
    }

    func testNombreDeArchivo() {
        XCTAssertEqual(Formato.nombreArchivo("Recámara principal"), "Recamara-principal")
        XCTAssertEqual(Formato.nombreArchivo("Sala/Comedor"), "Sala-Comedor")
        XCTAssertEqual(Formato.nombreArchivo("  "), "proyecto")
    }

    func testOBJConNormalesYVariasPiezas() throws {
        let triangulo = PiezaMalla(
            vertices: [(0, 0, 0), (1, 0, 0), (0, 1, 0)],
            normales: [(0, 0, 1), (0, 0, 1), (0, 0, 1)],
            indices: [0, 1, 2]
        )
        let sinNormales = PiezaMalla(vertices: [(0, 0, 1), (1, 0, 1), (0, 1, 1)], normales: [], indices: [0, 2, 1])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).obj")
        defer { try? FileManager.default.removeItem(at: url) }

        let totales = try OBJ.escribir([triangulo, sinNormales], en: url, nombre: "Prueba")
        XCTAssertEqual(totales.vertices, 6)
        XCTAssertEqual(totales.triangulos, 2)

        let texto = try String(contentsOf: url, encoding: .utf8)
        let lineas = texto.split(separator: "\n").map(String.init)
        XCTAssertEqual(lineas.filter { $0.hasPrefix("v ") }.count, 6)
        XCTAssertEqual(lineas.filter { $0.hasPrefix("vn ") }.count, 3)
        XCTAssertTrue(lineas.contains("f 1//1 2//2 3//3"))
        // The second piece's indices are offset by the first piece's vertices.
        XCTAssertTrue(lineas.contains("f 4 6 5"))
        XCTAssertTrue(lineas.contains("o Prueba_1"))
    }

    func testNumerosDelOBJ() {
        XCTAssertEqual(OBJ.numero(0), "0")
        XCTAssertEqual(OBJ.numero(-0.00001), "0")
        XCTAssertEqual(OBJ.numero(1.23456), "1.2346")
    }

    func testCSVDeMedidasEscapaComas() {
        let csv = CSV.medidas([Medida(nombre: "Puerta, cocina", metros: 0.9)])
        XCTAssertEqual(csv, "Nombre,Metros,Centimetros\n\"Puerta, cocina\",0.900,90.0\n")
    }
}
