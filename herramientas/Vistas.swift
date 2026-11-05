// Renderiza vistas de un modelo (USDZ u OBJ) a PNG y, si se pide, lo convierte a USDZ.
// Uso: vistas <modelo> <carpeta de salida> [convertir.usdz]
import AppKit
import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

let argumentos = CommandLine.arguments
let modelo = URL(fileURLWithPath: argumentos[1])
let carpeta = URL(fileURLWithPath: argumentos[2], isDirectory: true)
try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

let escena: SCNScene
if modelo.pathExtension.lowercased() == "obj" {
    let asset = MDLAsset(url: modelo)
    asset.loadTextures()
    escena = SCNScene(mdlAsset: asset)
} else {
    escena = try SCNScene(url: modelo, options: nil)
}
escena.rootNode.enumerateHierarchy { nodo, _ in
    for material in nodo.geometry?.materials ?? [] {
        material.lightingModel = .constant
        material.isDoubleSided = true
    }
}
if argumentos.count > 3 {
    let ok = escena.write(to: URL(fileURLWithPath: argumentos[3]), options: nil, delegate: nil, progressHandler: nil)
    print("USDZ escrito: \(ok)")
}

let (minimo, maximo) = escena.rootNode.flattenedClone().boundingBox
let centro = SCNVector3((minimo.x + maximo.x) / 2, (minimo.y + maximo.y) / 2, (minimo.z + maximo.z) / 2)
let tamano = max(maximo.x - minimo.x, maximo.y - minimo.y, maximo.z - minimo.z)
print("Caja: \(minimo) … \(maximo)")

guard let dispositivo = MTLCreateSystemDefaultDevice() else {
    print("Sin Metal: no se pueden hacer vistas")
    exit(0)
}
let renderizador = SCNRenderer(device: dispositivo, options: nil)
renderizador.scene = escena
let camara = SCNNode()
camara.camera = SCNCamera()
camara.camera?.zFar = Double(tamano) * 20
camara.camera?.zNear = Double(tamano) / 1000
escena.rootNode.addChildNode(camara)
renderizador.pointOfView = camara
escena.background.contents = NSColor(calibratedWhite: 0.3, alpha: 1)

// Desde fuera en seis direcciones y una desde el centro hacia cada lado.
let direcciones: [(String, SCNVector3)] = [
    ("x+", SCNVector3(1, 0.4, 0)), ("x-", SCNVector3(-1, 0.4, 0)), ("y+", SCNVector3(0.01, 1, 0.01)),
    ("y-", SCNVector3(0.01, -1, 0.01)), ("z+", SCNVector3(0, 0.4, 1)), ("z-", SCNVector3(0, 0.4, -1)),
]
for (nombre, d) in direcciones {
    let largo = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    let distancia = tamano * 1.3
    camara.position = SCNVector3(centro.x + d.x / largo * distancia, centro.y + d.y / largo * distancia, centro.z + d.z / largo * distancia)
    camara.look(at: centro)
    let imagen = renderizador.snapshot(atTime: 0, with: CGSize(width: 1200, height: 900), antialiasingMode: .multisampling4X)
    if let tiff = imagen.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: carpeta.appendingPathComponent("vista-\(nombre).png"))
    }
}
print("Vistas listas")
