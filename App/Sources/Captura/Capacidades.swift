import ARKit
import SwiftUI
import UIKit

/// What this device can do. Everything is false in the simulator.
enum Capacidades {
    static var roomPlan: Bool {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        return CuartoRoomPlan.disponible
        #else
        return false
        #endif
    }

    static var mallaLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var realidadAumentada: Bool {
        ARWorldTrackingConfiguration.isSupported
    }
}

/// Hosts an already-created UIKit view (the AR and RoomPlan views live in
/// their controllers so the controllers can drive them directly).
struct VistaUIKit: UIViewRepresentable {
    let vista: UIView

    func makeUIView(context: Context) -> UIView { vista }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// SceneKit and UIKit helpers shared by the captures.
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

extension simd_float4x4 {
    var posicion: SIMD3<Float> { columns.3.xyz }
}

extension UIImage {
    /// Shrinks an image to fit `lado` points on its longest side.
    func reducida(a lado: CGFloat) -> UIImage {
        let escala = min(1, lado / max(size.width, size.height))
        guard escala < 1 else { return self }
        let nuevo = CGSize(width: size.width * escala, height: size.height * escala)
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: nuevo, format: formato).image { _ in draw(in: CGRect(origin: .zero, size: nuevo)) }
    }
}
