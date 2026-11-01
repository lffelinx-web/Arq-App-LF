import ImageIO
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

    /// Photo-textured scene. `textura` gives each photo's image (a CGImage for the
    /// viewer, a file URL for exporting); photos it can't give stay grey.
    static func escena(_ malla: MallaTexturizada, textura: (Int32) -> Any?) -> SCNScene {
        let n = malla.esquinas
        let fuentes = [
            fuente(malla.posiciones, semantica: .vertex, cuenta: n),
            fuente(malla.normales, semantica: .normal, cuenta: n),
            fuente(malla.uvs, semantica: .texcoord, cuenta: n, componentes: 2),
        ]
        var elementos: [SCNGeometryElement] = []
        var materiales: [SCNMaterial] = []
        for grupo in malla.grupos where grupo.triangulos > 0 {
            let inicio = UInt32(grupo.inicio) * 3
            let indices = (0..<UInt32(grupo.triangulos) * 3).map { inicio + $0 }
            let datos = indices.withUnsafeBufferPointer { Data(buffer: $0) }
            elementos.append(SCNGeometryElement(data: datos, primitiveType: .triangles, primitiveCount: Int(grupo.triangulos), bytesPerIndex: 4))

            let material = SCNMaterial()
            material.isDoubleSided = !malla.orientada
            if grupo.foto >= 0, let imagen = textura(grupo.foto) {
                material.diffuse.contents = imagen
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
                material.diffuse.mipFilter = .linear
                material.lightingModel = .constant
            } else {
                material.diffuse.contents = UIColor(white: 0.67, alpha: 1)
                material.lightingModel = .blinn
            }
            materiales.append(material)
        }
        let geometria = SCNGeometry(sources: fuentes, elements: elementos)
        geometria.materials = materiales
        let escena = SCNScene()
        escena.rootNode.addChildNode(SCNNode(geometry: geometria))
        return escena
    }

    /// Loads `textura.bin` and its images. Scans from before the atlas used one
    /// image per photo (many of them), so those are shrunk to fit in the GPU.
    static func escenaTexturizada(_ url: URL) -> SCNScene? {
        guard let datos = try? Data(contentsOf: url), let malla = try? Texturizar.leer(datos) else { return nil }
        return escenaTexturizada(url, lado: malla.grupos.count <= 4 ? 4096 : 1024)
    }

    static func escenaTexturizada(_ url: URL, lado: Int) -> SCNScene? {
        guard let datos = try? Data(contentsOf: url), let malla = try? Texturizar.leer(datos) else { return nil }
        let carpeta = url.deletingLastPathComponent().appendingPathComponent(ArchivoProyecto.carpetaTextura.rawValue)
        return escena(malla) { foto in
            miniatura(carpeta.appendingPathComponent(Texturizar.nombreFoto(foto)), lado: lado)
        }
    }

    static func miniatura(_ url: URL, lado: Int) -> CGImage? {
        guard let origen = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opciones = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(origen, 0, opciones)
    }

    private static func fuente(_ valores: [Float], semantica: SCNGeometrySource.Semantic, cuenta: Int, componentes: Int = 3) -> SCNGeometrySource {
        let datos = valores.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: datos, semantic: semantica, vectorCount: cuenta, usesFloatComponents: true,
            componentsPerVector: componentes, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * componentes
        )
    }
}
