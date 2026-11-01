import ARKit
import AVFoundation
import SwiftUI

/// Shows the capture screen only once the camera is authorised. Without this,
/// ARKit and RoomPlan just show a black screen when access was denied.
struct ConPermisoCamara<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido
    @Environment(\.dismiss) private var cerrar
    @Environment(\.openURL) private var abrirURL
    @Environment(\.scenePhase) private var fase
    @State private var estado = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch estado {
            case .authorized:
                contenido
            case .notDetermined:
                Color.black.ignoresSafeArea()
                    .task {
                        let permitido = await AVCaptureDevice.requestAccess(for: .video)
                        estado = permitido ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
                    }
            default:
                sinPermiso
            }
        }
        .onChange(of: fase) {
            if fase == .active { estado = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private var sinPermiso: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(Tema.acento)
            Text("Arq LF no tiene acceso a la cámara")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(estado == .restricted
                 ? "El acceso a la cámara está restringido en este iPhone (Tiempo en pantalla o un perfil de administración)."
                 : "Para escanear y medir, activa la cámara en Ajustes → Arq LF → Cámara.")
                .font(.subheadline)
                .foregroundStyle(Tema.apagado)
                .multilineTextAlignment(.center)
            if estado == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    abrirURL(url)
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                        .font(.headline)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Tema.acento, in: Capsule())
                        .foregroundStyle(Tema.fondo)
                }
            }
            Button("Cerrar") { cerrar() }
                .foregroundStyle(Tema.apagado)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fondo.ignoresSafeArea())
    }
}

/// ARKit and RoomPlan errors in plain Spanish.
enum MensajeError {
    static func texto(_ error: Error) -> String {
        if let ar = error as? ARError {
            switch ar.code {
            case .cameraUnauthorized:
                return "Sin permiso de cámara. Actívalo en Ajustes → Arq LF."
            case .worldTrackingFailed:
                return "Se perdió el seguimiento. Toca Repetir y mueve el iPhone despacio con buena luz."
            case .sensorUnavailable, .sensorFailed:
                return "La cámara o el LiDAR no están disponibles. Cierra otras apps que usen la cámara y vuelve a intentar."
            case .unsupportedConfiguration:
                return "Este dispositivo no admite este tipo de escaneo."
            default:
                break
            }
        }
        let original = error.localizedDescription
        if original.localizedCaseInsensitiveContains("world tracking") {
            return "Se perdió el seguimiento. Revisa el permiso de cámara, toca Repetir y mueve el iPhone despacio con buena luz."
        }
        return original
    }
}
