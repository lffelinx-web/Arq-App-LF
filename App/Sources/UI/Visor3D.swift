import ModelIO
import SceneKit
import SceneKit.ModelIO
import SwiftUI

/// Orbit viewer for the USDZ, PLY and OBJ models. Several files (the
/// sections of a large scan) are shown together.
struct Visor3D: View {
    let urls: [URL]
    @State private var escena: SCNScene?
    @State private var fallo = false

    var body: some View {
        ZStack {
            Color(hex: 0x4A4F57)
            if let escena {
                VistaEscena(escena: escena)
            } else if fallo {
                Label("No se pudo abrir el modelo", systemImage: "exclamationmark.triangle").foregroundStyle(Tema.apagado)
            } else {
                ProgressView("Cargando modelo…")
            }
        }
        .task(id: urls) {
            let origen = urls
            let cargada = await Task.detached(priority: .userInitiated) { Self.cargar(origen) }.value
            escena = cargada
            fallo = cargada == nil
        }
    }

    /// All the files in one scene. Texture images share one memory budget, so
    /// many sections get smaller copies of their atlases.
    nonisolated static func cargar(_ urls: [URL]) -> SCNScene? {
        guard urls.count > 1 else { return urls.first.flatMap { cargar($0, lado: nil) } }
        let atlas = urls.reduce(0) { suma, url in
            guard url.pathExtension.lowercased() == "bin", let datos = try? Data(contentsOf: url), let malla = try? Texturizar.leer(datos) else { return suma }
            return suma + malla.grupos.count
        }
        let lado = EscenaMalla.ladoVisor(atlas: atlas)
        let escena = SCNScene()
        for url in urls {
            cargar(url, lado: lado)?.rootNode.childNodes.forEach { escena.rootNode.addChildNode($0) }
        }
        return escena.rootNode.childNodes.isEmpty ? nil : escena
    }

    nonisolated static func cargar(_ url: URL, lado: Int?) -> SCNScene? {
        let escena: SCNScene?
        let extension_ = url.pathExtension.lowercased()
        if extension_ == "bin" {
            escena = lado.map { EscenaMalla.escenaTexturizada(url, lado: $0) } ?? EscenaMalla.escenaTexturizada(url)
        } else if extension_ == "ply" {
            escena = (try? PLY.leer(url)).map(EscenaMalla.escena)
        } else if extension_ == "obj" {
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
        // Neutral grey: unscanned gaps read as "nothing here" instead of black holes.
        vista.backgroundColor = UIColor(hex: 0x4A4F57)
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
