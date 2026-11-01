#if canImport(RoomPlan) && !targetEnvironment(simulator)
import Combine
import Foundation
import RoomPlan
import simd
import UIKit

/// Drives Apple's RoomPlan scanner, which turns the LiDAR scan into walls,
/// doors, windows and furniture with real dimensions.
final class CuartoRoomPlan: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum Estado: Equatable {
        case listo
        case escaneando
        case procesando
        case terminado
        case error(String)
    }

    static var disponible: Bool { RoomCaptureSession.isSupported }

    let vista: RoomCaptureView
    @Published private(set) var estado: Estado = .listo
    @Published private(set) var resultado: CapturedRoom?

    override init() {
        vista = RoomCaptureView(frame: .zero)
        super.init()
        vista.delegate = self
    }

    // RoomCaptureViewDelegate inherits from NSCoding.
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) {}

    func iniciar() {
        resultado = nil
        estado = .escaneando
        vista.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Ends the scan; RoomPlan then processes it and shows the 3D result.
    func detener() {
        guard estado == .escaneando else { return }
        estado = .procesando
        vista.captureSession.stop()
    }

    func cancelar() {
        vista.captureSession.stop()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            DispatchQueue.main.async { self.estado = .error(MensajeError.texto(error)) }
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.estado = .error(MensajeError.texto(error))
            } else {
                self.resultado = processedResult
                self.estado = .terminado
            }
        }
    }

    /// Writes the USDZ model, the floor plan and RoomPlan's raw JSON into `carpeta`.
    static func guardar(_ cuarto: CapturedRoom, en carpeta: URL) throws -> PlanoPlanta {
        try cuarto.export(to: carpeta.appendingPathComponent(ArchivoProyecto.modeloUSDZ.rawValue))
        if let crudo = try? JSONEncoder().encode(cuarto) {
            try? crudo.write(to: carpeta.appendingPathComponent("roomplan.json"))
        }
        return PlanoPlanta(cuarto)
    }
}

extension PlanoPlanta {
    /// Projects RoomPlan's 3D surfaces onto the floor, seen from above.
    init(_ cuarto: CapturedRoom) {
        self.init()
        let nivelPiso = Self.nivelPiso(cuarto)

        muros = cuarto.walls.map { muro in
            let (a, b) = Self.extremos(muro.transform, ancho: muro.dimensions.x)
            return Muro(a: a, b: b, altura: Double(muro.dimensions.y))
        }

        func aberturas(_ superficies: [CapturedRoom.Surface], _ tipo: TipoAbertura) -> [Abertura] {
            superficies.map { s in
                let (a, b) = Self.extremos(s.transform, ancho: s.dimensions.x)
                let base = Double(s.transform.columns.3.y - s.dimensions.y / 2) - nivelPiso
                return Abertura(tipo: tipo, a: a, b: b, altura: Double(s.dimensions.y), elevacion: max(0, base))
            }
        }
        self.aberturas = aberturas(cuarto.doors, .puerta) + aberturas(cuarto.windows, .ventana) + aberturas(cuarto.openings, .vano)

        muebles = cuarto.objects.map { objeto in
            let t = objeto.transform
            return Mueble(
                nombre: Self.nombre(objeto.category),
                centro: Punto2D(Double(t.columns.3.x), Double(t.columns.3.z)),
                ancho: Double(objeto.dimensions.x),
                fondo: Double(objeto.dimensions.z),
                alto: Double(objeto.dimensions.y),
                angulo: atan2(Double(t.columns.0.z), Double(t.columns.0.x))
            )
        }

        pisos = cuarto.floors.compactMap { piso in
            var esquinas = piso.polygonCorners
            if esquinas.count < 3 {
                let x = piso.dimensions.x / 2, y = piso.dimensions.y / 2
                esquinas = [SIMD3(-x, -y, 0), SIMD3(x, -y, 0), SIMD3(x, y, 0), SIMD3(-x, y, 0)]
            }
            let puntos = esquinas.map { p -> Punto2D in
                let w = piso.transform * SIMD4<Float>(p.x, p.y, p.z, 1)
                return Punto2D(Double(w.x), Double(w.z))
            }
            return Geometria.area(puntos) > 0.01 ? puntos : nil
        }
    }

    /// End points of a surface whose local X axis runs along its width.
    private static func extremos(_ t: simd_float4x4, ancho: Float) -> (Punto2D, Punto2D) {
        let centro = Punto2D(Double(t.columns.3.x), Double(t.columns.3.z))
        let eje = Punto2D(Double(t.columns.0.x), Double(t.columns.0.z))
        let largo = eje.longitud
        let direccion = largo > 0 ? eje * (1 / largo) : Punto2D(1, 0)
        let mitad = Double(ancho) / 2
        return (centro - direccion * mitad, centro + direccion * mitad)
    }

    private static func nivelPiso(_ cuarto: CapturedRoom) -> Double {
        let bases = cuarto.walls.map { Double($0.transform.columns.3.y - $0.dimensions.y / 2) }
        return bases.min() ?? 0
    }

    private static let nombres: [String: String] = [
        "storage": "Almacenaje", "refrigerator": "Refrigerador", "stove": "Estufa", "bed": "Cama",
        "sink": "Lavabo", "washerDryer": "Lavadora", "toilet": "Inodoro", "bathtub": "Tina",
        "oven": "Horno", "dishwasher": "Lavavajillas", "table": "Mesa", "sofa": "Sofá",
        "chair": "Silla", "fireplace": "Chimenea", "television": "Televisión", "stairs": "Escaleras",
    ]

    private static func nombre(_ categoria: CapturedRoom.Object.Category) -> String {
        let clave = String(describing: categoria)
        return nombres[clave] ?? clave.capitalized
    }
}
#endif
