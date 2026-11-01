import Foundation

/// A wall seen from above: a segment with a height.
struct Muro: Codable, Hashable, Identifiable {
    var id = UUID()
    var a: Punto2D
    var b: Punto2D
    var altura: Double

    var longitud: Double { a.distancia(a: b) }
    var area: Double { longitud * altura }
}

enum TipoAbertura: String, Codable, CaseIterable {
    case puerta
    case ventana
    case vano

    var nombre: String {
        switch self {
        case .puerta: return "Puerta"
        case .ventana: return "Ventana"
        case .vano: return "Vano"
        }
    }
}

/// A door, window or opening, drawn over the wall it belongs to.
struct Abertura: Codable, Hashable, Identifiable {
    var id = UUID()
    var tipo: TipoAbertura
    var a: Punto2D
    var b: Punto2D
    var altura: Double
    /// Height of the bottom edge above the floor (the sill for windows).
    var elevacion: Double = 0

    var ancho: Double { a.distancia(a: b) }
}

/// A detected piece of furniture or fixture, as a rotated box.
struct Mueble: Codable, Hashable, Identifiable {
    var id = UUID()
    var nombre: String
    var centro: Punto2D
    var ancho: Double
    var fondo: Double
    var alto: Double
    var angulo: Double

    var esquinas: [Punto2D] { Geometria.rectangulo(centro: centro, ancho: ancho, fondo: fondo, angulo: angulo) }
}

/// Everything needed to draw and quote a floor plan, independent of RoomPlan
/// so it can be saved as JSON, tested and drawn anywhere.
struct PlanoPlanta: Codable, Hashable {
    var muros: [Muro] = []
    var aberturas: [Abertura] = []
    var muebles: [Mueble] = []
    /// Floor outlines; a multi-room scan can have several.
    var pisos: [[Punto2D]] = []

    var vacio: Bool { muros.isEmpty && pisos.isEmpty }

    /// Floor area. Uses the detected floor polygons, falling back to the
    /// rectangle that bounds the walls if RoomPlan did not report a floor.
    var area: Double {
        let pisosArea = pisos.reduce(0) { $0 + Geometria.area($1) }
        if pisosArea > 0 { return pisosArea }
        guard let l = Limites(muros.flatMap { [$0.a, $0.b] }) else { return 0 }
        return l.ancho * l.alto
    }

    /// Sum of the floor outlines' perimeters, or of the wall lengths without a floor.
    var perimetro: Double {
        let p = pisos.reduce(0) { $0 + Geometria.perimetro($1) }
        return p > 0 ? p : muros.reduce(0) { $0 + $1.longitud }
    }

    var alturaPromedio: Double {
        guard !muros.isEmpty else { return 0 }
        return muros.reduce(0) { $0 + $1.altura } / Double(muros.count)
    }

    var volumen: Double { area * alturaPromedio }

    /// Wall surface without doors and windows, handy for paint estimates.
    var areaMurosNeta: Double {
        let bruta = muros.reduce(0) { $0 + $1.area }
        let huecos = aberturas.reduce(0) { $0 + $1.ancho * $1.altura }
        return max(0, bruta - huecos)
    }

    var limites: Limites? {
        Limites(muros.flatMap { [$0.a, $0.b] } + pisos.flatMap { $0 } + muebles.flatMap(\.esquinas))
    }

    func cuenta(_ tipo: TipoAbertura) -> Int { aberturas.filter { $0.tipo == tipo }.count }
}
