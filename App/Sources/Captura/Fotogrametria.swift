import Foundation

#if !targetEnvironment(simulator)
import RealityKit
#endif

/// Photos → textured 3D model, on the iPhone itself, with Apple's Object
/// Capture engine (`PhotogrammetrySession`). Works best on objects and
/// corners with plenty of texture, shot all around with lots of overlap.
@MainActor
final class Fotogrametria: ObservableObject {
    enum Estado: Equatable {
        case listo
        case preparando
        case procesando(Double)
        case terminado(URL)
        case error(String)
    }

    @Published private(set) var estado: Estado = .listo
    /// Photos the engine could not use (blurry, too similar or no matches).
    @Published private(set) var omitidas = 0
    @Published private(set) var etapa = ""

    #if !targetEnvironment(simulator)
    private var sesion: PhotogrammetrySession?
    #endif
    private var tarea: Task<Void, Never>?

    static var disponible: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return PhotogrammetrySession.isSupported
        #endif
    }

    /// Processes the photos in `carpeta` into a USDZ at `salida`.
    /// - Parameter soloObjeto: ask the engine to cut out the main object and drop the background.
    func procesar(carpeta: URL, salida: URL, soloObjeto: Bool) {
        #if targetEnvironment(simulator)
        estado = .error("La fotogrametría no está disponible en el simulador.")
        #else
        omitidas = 0
        etapa = "Analizando fotos…"
        estado = .procesando(0)
        var configuracion = PhotogrammetrySession.Configuration()
        configuracion.sampleOrdering = .unordered
        configuracion.featureSensitivity = .high
        configuracion.isObjectMaskingEnabled = soloObjeto
        do {
            let sesion = try PhotogrammetrySession(input: carpeta, configuration: configuracion)
            self.sesion = sesion
            tarea = Task { [weak self] in
                do {
                    for try await salidaSesion in sesion.outputs {
                        await self?.atender(salidaSesion)
                    }
                } catch {
                    await self?.fallo(error)
                }
            }
            try sesion.process(requests: [.modelFile(url: salida, detail: .reduced)])
        } catch {
            fallo(error)
        }
        #endif
    }

    func cancelar() {
        #if !targetEnvironment(simulator)
        sesion?.cancel()
        #endif
        tarea?.cancel()
        estado = .listo
    }

    private func fallo(_ error: Error) {
        estado = .error("No se pudo crear el modelo: \(error.localizedDescription)")
    }

    #if !targetEnvironment(simulator)
    private func atender(_ salida: PhotogrammetrySession.Output) {
        switch salida {
        case .requestProgress(_, let fraccion):
            estado = .procesando(fraccion)
            etapa = fraccion < 0.3 ? "Buscando puntos en común entre las fotos…" : fraccion < 0.7 ? "Reconstruyendo la forma…" : "Creando la textura…"
        case .requestComplete(_, let resultado):
            if case .modelFile(let url) = resultado { estado = .terminado(url) }
        case .requestError(_, let error):
            fallo(error)
        case .skippedSample, .invalidSample:
            omitidas += 1
        case .processingCancelled:
            estado = .listo
        default:
            break
        }
    }
    #endif
}
