// Prueba de Object Capture (PhotogrammetrySession) en una Mac de GitHub Actions.
// Uso: objectcapture <carpeta de fotos> <salida.usdz> [reduced|medium|full]
import Foundation
import RealityKit

@main
struct Principal {
    static func main() async {
        let argumentos = CommandLine.arguments
        guard PhotogrammetrySession.isSupported else {
            print("OBJECT_CAPTURE=no-soportado")
            exit(2)
        }
        print("OBJECT_CAPTURE=soportado")
        guard argumentos.count >= 3 else { exit(0) }
        let entrada = URL(fileURLWithPath: argumentos[1], isDirectory: true)
        let salida = URL(fileURLWithPath: argumentos[2])
        let nivel = argumentos.count > 3 ? argumentos[3] : "medium"
        let detalle: PhotogrammetrySession.Request.Detail = nivel == "full" ? .full : (nivel == "reduced" ? .reduced : .medium)
        var configuracion = PhotogrammetrySession.Configuration()
        configuracion.sampleOrdering = .unordered
        configuracion.featureSensitivity = .normal
        let inicio = Date()
        do {
            let sesion = try PhotogrammetrySession(input: entrada, configuration: configuracion)
            try sesion.process(requests: [.modelFile(url: salida, detail: detalle)])
            var ultimo = -1
            for try await mensaje in sesion.outputs {
                switch mensaje {
                case .requestProgress(_, let fraccion):
                    let porcentaje = Int(fraccion * 100)
                    if porcentaje / 5 != ultimo / 5 {
                        ultimo = porcentaje
                        print("Progreso \(porcentaje)% · \(Int(Date().timeIntervalSince(inicio))) s")
                    }
                case .requestComplete:
                    print("Modelo listo en \(Int(Date().timeIntervalSince(inicio))) s")
                case .requestError(_, let error):
                    print("Error: \(error)")
                    exit(1)
                case .invalidSample(let id, let razon):
                    print("Foto \(id) no válida: \(razon)")
                case .skippedSample(let id):
                    print("Foto \(id) omitida")
                case .automaticDownsampling:
                    print("Object Capture redujo las fotos por falta de memoria")
                case .processingCancelled:
                    print("Cancelado")
                    exit(1)
                case .processingComplete:
                    exit(0)
                default:
                    break
                }
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }
}
