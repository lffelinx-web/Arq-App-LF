import Foundation

/// A point on the floor plan, in metres. `x` grows to the right and `y` grows
/// toward the viewer (it is the world's Z axis seen from above).
struct Punto2D: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: Punto2D, b: Punto2D) -> Punto2D { Punto2D(a.x + b.x, a.y + b.y) }
    static func - (a: Punto2D, b: Punto2D) -> Punto2D { Punto2D(a.x - b.x, a.y - b.y) }
    static func * (a: Punto2D, k: Double) -> Punto2D { Punto2D(a.x * k, a.y * k) }

    var longitud: Double { (x * x + y * y).squareRoot() }

    func distancia(a otro: Punto2D) -> Double { (self - otro).longitud }

    static func medio(_ a: Punto2D, _ b: Punto2D) -> Punto2D { Punto2D((a.x + b.x) / 2, (a.y + b.y) / 2) }
}

/// Axis-aligned rectangle that contains a set of points.
struct Limites: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var ancho: Double { maxX - minX }
    var alto: Double { maxY - minY }

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init?(_ puntos: [Punto2D]) {
        guard let primero = puntos.first else { return nil }
        var l = Limites(minX: primero.x, minY: primero.y, maxX: primero.x, maxY: primero.y)
        for p in puntos.dropFirst() {
            l.minX = min(l.minX, p.x)
            l.minY = min(l.minY, p.y)
            l.maxX = max(l.maxX, p.x)
            l.maxY = max(l.maxY, p.y)
        }
        self = l
    }
}

enum Geometria {
    /// Area of a simple polygon (shoelace formula), always positive.
    static func area(_ poligono: [Punto2D]) -> Double {
        guard poligono.count >= 3 else { return 0 }
        var suma = 0.0
        for i in poligono.indices {
            let a = poligono[i]
            let b = poligono[(i + 1) % poligono.count]
            suma += a.x * b.y - b.x * a.y
        }
        return abs(suma) / 2
    }

    /// Perimeter of a closed polygon.
    static func perimetro(_ poligono: [Punto2D]) -> Double {
        guard poligono.count >= 2 else { return 0 }
        var total = 0.0
        for i in poligono.indices {
            total += poligono[i].distancia(a: poligono[(i + 1) % poligono.count])
        }
        return total
    }

    /// Distance between two 3D points.
    static func distancia(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dx = a.0 - b.0, dy = a.1 - b.1, dz = a.2 - b.2
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Corners of a rectangle of `ancho` × `fondo` centred on `centro` and rotated `angulo` radians.
    static func rectangulo(centro: Punto2D, ancho: Double, fondo: Double, angulo: Double) -> [Punto2D] {
        let c = cos(angulo), s = sin(angulo)
        let mitades = [(-ancho / 2, -fondo / 2), (ancho / 2, -fondo / 2), (ancho / 2, fondo / 2), (-ancho / 2, fondo / 2)]
        return mitades.map { dx, dy in Punto2D(centro.x + dx * c - dy * s, centro.y + dx * s + dy * c) }
    }
}
