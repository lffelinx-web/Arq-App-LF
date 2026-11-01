import SceneKit
import UIKit

/// SceneKit scene for a PLY mesh, with its vertex colours when it has them.
enum EscenaMalla {
    static func escena(_ malla: PLY.Malla) -> SCNScene {
        let escena = SCNScene()
        escena.rootNode.addChildNode(nodo(malla))
        return escena
    }

    static func nodo(_ malla: PLY.Malla) -> SCNNode {
        let n = malla.numeroVertices
        var fuentes: [SCNGeometrySource] = []

        fuentes.append(fuente(malla.vertices, semantica: .vertex, cuenta: n))
        let conNormales = malla.normales.count == malla.vertices.count
        if conNormales {
            fuentes.append(fuente(malla.normales, semantica: .normal, cuenta: n))
        }
        let conColor = malla.colores.count == malla.vertices.count
        if conColor {
            fuentes.append(fuente(malla.colores.map { Float($0) / 255 }, semantica: .color, cuenta: n))
        }

        let indices = malla.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elemento = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: malla.numeroTriangulos, bytesPerIndex: 4)
        let geometria = SCNGeometry(sources: fuentes, elements: [elemento])

        let material = SCNMaterial()
        material.isDoubleSided = true
        material.diffuse.contents = conColor ? UIColor.white : UIColor(white: 0.82, alpha: 1)
        // The photo colours already carry the room's light.
        material.lightingModel = conColor ? .constant : .blinn
        geometria.materials = [material]
        return SCNNode(geometry: geometria)
    }

    private static func fuente(_ valores: [Float], semantica: SCNGeometrySource.Semantic, cuenta: Int) -> SCNGeometrySource {
        let datos = valores.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: datos, semantic: semantica, vectorCount: cuenta, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3
        )
    }
}
