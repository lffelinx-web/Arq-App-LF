import Foundation

/// Floor plan as DXF (AutoCAD R12 ASCII), which AutoCAD, Revit, ArchiCAD,
/// SketchUp, LibreCAD and QCAD open. Units are metres, one layer per element type.
enum DXF {
    enum Capa: String, CaseIterable {
        case muros = "MUROS"
        case puertas = "PUERTAS"
        case ventanas = "VENTANAS"
        case vanos = "VANOS"
        case muebles = "MUEBLES"
        case piso = "PISO"
        case cotas = "COTAS"

        /// AutoCAD Color Index.
        var color: Int {
            switch self {
            case .muros: return 7
            case .puertas: return 3
            case .ventanas: return 5
            case .vanos: return 8
            case .muebles: return 9
            case .piso: return 30
            case .cotas: return 1
            }
        }
    }

    static func texto(_ plano: PlanoPlanta, unidad: Unidad = .metros) -> String {
        var e = Escritor()

        e.par(0, "SECTION"); e.par(2, "HEADER")
        e.par(9, "$ACADVER"); e.par(1, "AC1009")
        e.par(9, "$INSUNITS"); e.par(70, "6")
        e.par(0, "ENDSEC")

        e.par(0, "SECTION"); e.par(2, "TABLES")
        e.par(0, "TABLE"); e.par(2, "LTYPE"); e.par(70, "1")
        e.par(0, "LTYPE"); e.par(2, "CONTINUOUS"); e.par(70, "0"); e.par(3, "Solid line"); e.par(72, "65"); e.par(73, "0"); e.par(40, "0.0")
        e.par(0, "ENDTAB")
        e.par(0, "TABLE"); e.par(2, "LAYER"); e.par(70, "\(Capa.allCases.count)")
        for capa in Capa.allCases {
            e.par(0, "LAYER"); e.par(2, capa.rawValue); e.par(70, "0"); e.par(62, "\(capa.color)"); e.par(6, "CONTINUOUS")
        }
        e.par(0, "ENDTAB")
        e.par(0, "ENDSEC")

        e.par(0, "SECTION"); e.par(2, "ENTITIES")
        for piso in plano.pisos { e.poligono(piso, capa: .piso) }
        for muro in plano.muros { e.linea(muro.a, muro.b, capa: .muros) }
        for a in plano.aberturas {
            switch a.tipo {
            case .puerta:
                e.linea(a.a, a.b, capa: .puertas)
                // Door swing: quarter circle around the hinge.
                let angulo = atan2(-(a.b.y - a.a.y), a.b.x - a.a.x) * 180 / .pi
                e.arco(centro: a.a, radio: a.ancho, desde: angulo, hasta: angulo + 90, capa: .puertas)
            case .ventana:
                e.linea(a.a, a.b, capa: .ventanas)
            case .vano:
                e.linea(a.a, a.b, capa: .vanos)
            }
        }
        for m in plano.muebles { e.poligono(m.esquinas, capa: .muebles) }
        for muro in plano.muros where muro.longitud > 0.05 {
            let medio = Punto2D.medio(muro.a, muro.b)
            var angulo = atan2(-(muro.b.y - muro.a.y), muro.b.x - muro.a.x) * 180 / .pi
            if angulo > 90 { angulo -= 180 } else if angulo < -90 { angulo += 180 }
            e.texto(Formato.longitud(muro.longitud, unidad), en: medio, altura: 0.08, angulo: angulo, capa: .cotas)
        }
        e.par(0, "ENDSEC")
        e.par(0, "EOF")
        return e.salida
    }

    /// Accumulates group-code/value pairs. The plan's Y grows toward the viewer,
    /// so it is flipped to keep the drawing the same way up in CAD.
    private struct Escritor {
        var salida = ""

        mutating func par(_ codigo: Int, _ valor: String) {
            salida += "\(codigo)\n\(valor)\n"
        }

        mutating func punto(_ p: Punto2D, _ base: Int = 10) {
            par(base, n(p.x)); par(base + 10, n(-p.y)); par(base + 20, "0.0")
        }

        mutating func linea(_ a: Punto2D, _ b: Punto2D, capa: Capa) {
            par(0, "LINE"); par(8, capa.rawValue)
            punto(a, 10); punto(b, 11)
        }

        mutating func poligono(_ puntos: [Punto2D], capa: Capa) {
            guard puntos.count >= 2 else { return }
            for i in puntos.indices { linea(puntos[i], puntos[(i + 1) % puntos.count], capa: capa) }
        }

        mutating func arco(centro: Punto2D, radio: Double, desde: Double, hasta: Double, capa: Capa) {
            par(0, "ARC"); par(8, capa.rawValue)
            punto(centro)
            par(40, n(radio)); par(50, n(desde)); par(51, n(hasta))
        }

        mutating func texto(_ contenido: String, en p: Punto2D, altura: Double, angulo: Double, capa: Capa) {
            par(0, "TEXT"); par(8, capa.rawValue)
            punto(p)
            par(40, n(altura)); par(1, contenido.replacingOccurrences(of: "²", with: "2")); par(50, n(angulo))
            // Centre the text on the point.
            par(72, "1"); par(73, "2")
            punto(p, 11)
        }

        private func n(_ v: Double) -> String {
            String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), abs(v) < 0.00005 ? 0 : v)
        }
    }
}
