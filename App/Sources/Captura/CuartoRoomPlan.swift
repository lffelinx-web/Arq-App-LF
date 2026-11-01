#if canImport(RoomPlan) && !targetEnvironment(simulator)
import ARKit
import Combine
import Foundation
import RoomPlan
import simd
import UIKit

/// Drives Apple's RoomPlan scanner, which turns the LiDAR scan into walls,
/// doors, windows and furniture with real dimensions. Several rooms can be
/// scanned in a row: they share one AR session, so RoomPlan can join them.
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
    private let sesionAR = ARSession()
    @Published private(set) var estado: Estado = .listo
    /// Every room finished in this session, in order.
    @Published private(set) var cuartos: [CapturedRoom] = []

    override init() {
        vista = RoomCaptureView(frame: .zero, arSession: sesionAR)
        super.init()
        vista.delegate = self
    }

    // RoomCaptureViewDelegate inherits from NSCoding.
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) {}

    /// Starts over, discarding the rooms scanned so far.
    func iniciar() {
        cuartos = []
        estado = .escaneando
        vista.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Scans the next room keeping the same coordinates as the previous ones.
    func otroCuarto() {
        estado = .escaneando
        vista.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Ends the current room; RoomPlan then processes it and shows the 3D result.
    /// The AR session keeps running so another room can follow.
    func detener() {
        guard estado == .escaneando else { return }
        estado = .procesando
        vista.captureSession.stop(pauseARSession: false)
    }

    func cancelar() {
        vista.captureSession.stop()
        sesionAR.pause()
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
                self.cuartos.append(processedResult)
                self.estado = .terminado
            }
        }
    }

    /// Writes the USDZ model, the floor plan and RoomPlan's raw JSON into `carpeta`.
    /// Several rooms are first joined into one structure.
    static func guardar(_ cuartos: [CapturedRoom], en carpeta: URL) async throws -> PlanoPlanta {
        let usdz = carpeta.appendingPathComponent(ArchivoProyecto.modeloUSDZ.rawValue)
        let crudo = carpeta.appendingPathComponent("roomplan.json")
        if cuartos.count == 1, let cuarto = cuartos.first {
            try cuarto.export(to: usdz)
            try? JSONEncoder().encode(cuarto).write(to: crudo)
            return PlanoPlanta(cuarto)
        }
        let estructura = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: cuartos)
        try estructura.export(to: usdz)
        try? JSONEncoder().encode(estructura).write(to: crudo)
        return PlanoPlanta(estructura)
    }
}

extension PlanoPlanta {
    init(_ cuarto: CapturedRoom) {
        self.init(muros: cuarto.walls, puertas: cuarto.doors, ventanas: cuarto.windows, vanos: cuarto.openings, objetos: cuarto.objects, pisos: cuarto.floors)
    }

    init(_ estructura: CapturedStructure) {
        self.init(muros: estructura.walls, puertas: estructura.doors, ventanas: estructura.windows, vanos: estructura.openings, objetos: estructura.objects, pisos: estructura.floors)
    }

    /// Projects RoomPlan's 3D surfaces onto the floor, seen from above.
    init(
        muros: [CapturedRoom.Surface], puertas: [CapturedRoom.Surface], ventanas: [CapturedRoom.Surface],
        vanos: [CapturedRoom.Surface], objetos: [CapturedRoom.Object], pisos: [CapturedRoom.Surface]
    ) {
        self.init()
        let nivelPiso = muros.map { Double($0.transform.columns.3.y - $0.dimensions.y / 2) }.min() ?? 0

        self.muros = muros.map { muro in
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
        self.aberturas = aberturas(puertas, .puerta) + aberturas(ventanas, .ventana) + aberturas(vanos, .vano)

        self.muebles = objetos.map { objeto in
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

        self.pisos = pisos.compactMap { piso in
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
