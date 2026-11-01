import ModelIO
import SceneKit
import SceneKit.ModelIO
import SwiftUI

/// Orbit viewer for the USDZ/OBJ models.
struct Visor3D: View {
    let url: URL
    @State private var escena: SCNScene?
    @State private var fallo = false

    var body: some View {
        ZStack {
            Tema.fondo
            if let escena {
                VistaEscena(escena: escena)
            } else if fallo {
                Label("No se pudo abrir el modelo", systemImage: "exclamationmark.triangle").foregroundStyle(Tema.apagado)
            } else {
                ProgressView("Cargando modelo…")
            }
        }
        .task(id: url) {
            let origen = url
            let cargada = await Task.detached(priority: .userInitiated) { Self.cargar(origen) }.value
            escena = cargada
            fallo = cargada == nil
        }
    }

    nonisolated static func cargar(_ url: URL) -> SCNScene? {
        let escena: SCNScene?
        if url.pathExtension.lowercased() == "obj" {
            escena = SCNScene(mdlAsset: MDLAsset(url: url))
        } else {
            escena = try? SCNScene(url: url, options: nil)
        }
        guard let escena else { return nil }
        // LiDAR meshes come without materials; give them a soft clay look.
        escena.rootNode.enumerateHierarchy { nodo, _ in
            guard let geometria = nodo.geometry else { return }
            for material in geometria.materials where material.diffuse.contents == nil {
                material.diffuse.contents = UIColor(white: 0.82, alpha: 1)
            }
            if geometria.materials.isEmpty {
                let material = SCNMaterial()
                material.diffuse.contents = UIColor(white: 0.82, alpha: 1)
                material.isDoubleSided = true
                geometria.materials = [material]
            }
        }
        return escena
    }
}

private struct VistaEscena: UIViewRepresentable {
    let escena: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let vista = SCNView()
        vista.backgroundColor = UIColor(hex: 0x12161C)
        vista.allowsCameraControl = true
        vista.autoenablesDefaultLighting = true
        vista.antialiasingMode = .multisampling4X
        vista.defaultCameraController.interactionMode = .orbitTurntable
        vista.defaultCameraController.inertiaEnabled = true
        vista.scene = escena
        return vista
    }

    func updateUIView(_ vista: SCNView, context: Context) {
        if vista.scene !== escena { vista.scene = escena }
    }
}
