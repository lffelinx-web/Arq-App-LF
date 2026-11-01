import ARKit
import Combine
import CoreImage
import ModelIO
import SceneKit
import UIKit

/// Free-form LiDAR scan: ARKit rebuilds the surfaces around you as a triangle
/// mesh while sharp photos are taken along the way. On saving, the photos are
/// projected onto the mesh as textures (textured OBJ/MTL and USDZ), and also
/// paint its vertices for the PLY and plain OBJ copies.
final class MallaLiDAR: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    let vista = ARSCNView(frame: .zero)
    @Published private(set) var triangulos = 0
    @Published private(set) var aviso = "Mueve el iPhone despacio para cubrir todo el espacio."
    @Published private(set) var escaneando = false
    /// Photos kept to texture the mesh.
    @Published private(set) var fotos = 0

    static let maximoFotos = 80
    /// Width of the texture photos and of the small copy used for vertex colours.
    static let anchoTextura: Float = 1440
    static let anchoColor: Float = 320
    /// Photos are written here while scanning and moved into the project on saving.
    let carpetaFotos = FileManager.default.temporaryDirectory.appendingPathComponent("Fotos-\(UUID().uuidString)", isDirectory: true)
    private var fotoAnterior: (transform: simd_float4x4, tiempo: TimeInterval)?
    private let colaFotos = DispatchQueue(label: "com.lfaz.arq.fotos", qos: .utility)
    private let candado = NSLock()
    private var fotogramas: [Fotograma] = []
    private var procesandoFoto = false
    private var capturando = false
    private var ultimaFoto: simd_float4x4?
    private var ultimaFotoFecha = Date.distantPast
    private let contextoCI = CIContext(options: [.cacheIntermediates: false])

    private let material: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.96, green: 0.65, blue: 0.24, alpha: 1)
        m.lightingModel = .constant
        m.fillMode = .lines
        m.isDoubleSided = true
        return m
    }()
    private var ultimoConteo = Date.distantPast

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: carpetaFotos, withIntermediateDirectories: true)
        vista.delegate = self
        vista.session.delegate = self
        vista.automaticallyUpdatesLighting = true
        vista.rendersContinuously = true
    }

    deinit {
        try? FileManager.default.removeItem(at: carpetaFotos)
    }

    private func configuracion() -> ARWorldTrackingConfiguration {
        let configuracion = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuracion.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuracion.frameSemantics.insert(.sceneDepth)
        }
        configuracion.planeDetection = [.horizontal, .vertical]
        return configuracion
    }

    /// Starts from scratch, dropping the mesh and photos.
    func iniciar() {
        candado.lock()
        fotogramas.removeAll()
        candado.unlock()
        try? FileManager.default.removeItem(at: carpetaFotos)
        try? FileManager.default.createDirectory(at: carpetaFotos, withIntermediateDirectories: true)
        ultimaFoto = nil
        fotos = 0
        vista.session.run(configuracion(), options: [.resetTracking, .removeExistingAnchors])
        capturando = true
        escaneando = true
    }

    /// Continues after a pause keeping what was scanned.
    func reanudar() {
        vista.session.run(configuracion())
        capturando = true
        escaneando = true
    }

    func pausar() {
        capturando = false
        vista.session.pause()
        escaneando = false
    }

    /// Photos taken so far.
    func fotosTomadas() -> [Fotograma] {
        candado.lock()
        defer { candado.unlock() }
        return fotogramas
    }

    /// Mesh anchors converted to world coordinates.
    func piezas() -> [PiezaMalla] {
        let anclas = vista.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        return anclas.map(Self.pieza)
    }

    /// Saves the scan into `carpeta`, returning the vertex and triangle count.
    static func guardar(_ piezas: [PiezaMalla], fotogramas: [Fotograma], captura: UIImage?, en carpeta: URL, nombre: String) throws -> (vertices: Int, triangulos: Int) {
        var piezas = piezas
        if !fotogramas.isEmpty {
            for i in piezas.indices {
                piezas[i].colores = Colorear.colores(vertices: piezas[i].vertices, normales: piezas[i].normales, fotogramas: fotogramas)
            }
        }
        let texturizada = try guardarTextura(Texturizar.unir(piezas), fotogramas: fotogramas, en: carpeta)
        let ply = carpeta.appendingPathComponent(ArchivoProyecto.mallaPLY.rawValue)
        let totales = try PLY.escribir(piezas, en: ply)
        let obj = carpeta.appendingPathComponent(ArchivoProyecto.mallaOBJ.rawValue)
        try OBJ.escribir(piezas, en: obj, nombre: Formato.nombreArchivo(nombre))
        if let captura {
            try? captura.reducida(a: 1600).jpegData(compressionQuality: 0.85)?.write(to: carpeta.appendingPathComponent(ArchivoProyecto.foto.rawValue))
            try? captura.reducida(a: 400).jpegData(compressionQuality: 0.8)?.write(to: carpeta.appendingPathComponent(ArchivoProyecto.miniatura.rawValue))
        }
        // USDZ opens in Quick Look and AR: textured when possible, otherwise with
        // vertex colours, and ModelIO from the OBJ as the last resort.
        let usdz = carpeta.appendingPathComponent(ArchivoProyecto.modeloUSDZ.rawValue)
        var escrito = false
        if let texturizada {
            let fotos = carpeta.appendingPathComponent(ArchivoProyecto.carpetaTextura.rawValue)
            let escena = EscenaMalla.escena(texturizada) { foto in fotos.appendingPathComponent(Texturizar.nombreFoto(foto)) }
            escrito = escena.write(to: usdz, options: nil, delegate: nil, progressHandler: nil)
        }
        if !escrito {
            escrito = (try? PLY.leer(ply)).map { EscenaMalla.escena($0).write(to: usdz, options: nil, delegate: nil, progressHandler: nil) } ?? false
        }
        if !escrito, MDLAsset.canExportFileExtension("usdz") {
            try? MDLAsset(url: obj).export(to: usdz)
        }
        return totales
    }

    /// Projects the photos onto the mesh and writes `textura.bin` plus the
    /// `textura/` folder (OBJ, MTL and the photos it uses).
    private static func guardarTextura(_ malla: PiezaMalla, fotogramas: [Fotograma], en carpeta: URL) throws -> MallaTexturizada? {
        let conFoto = fotogramas.filter { $0.archivo != nil }
        guard !conFoto.isEmpty, malla.triangulos > 0 else { return nil }
        let texturizada = Texturizar.construir(malla, fotogramas: conFoto)
        guard !texturizada.fotosUsadas.isEmpty else { return nil }

        let fotos = carpeta.appendingPathComponent(ArchivoProyecto.carpetaTextura.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: fotos, withIntermediateDirectories: true)
        for foto in texturizada.fotosUsadas {
            guard let origen = conFoto[Int(foto)].archivo else { continue }
            let destino = fotos.appendingPathComponent(Texturizar.nombreFoto(foto))
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.copyItem(at: origen, to: destino)
        }
        try Texturizar.escribirOBJ(texturizada, en: fotos)
        try Texturizar.datos(texturizada).write(to: carpeta.appendingPathComponent(ArchivoProyecto.texturaBIN.rawValue), options: .atomic)
        return texturizada
    }


    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let malla = anchor as? ARMeshAnchor else { return nil }
        return SCNNode(geometry: geometria(malla.geometry))
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let malla = anchor as? ARMeshAnchor else { return }
        node.geometry = geometria(malla.geometry)
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        tomarFotoSiConviene(frame)
        guard Date().timeIntervalSince(ultimoConteo) > 0.5 else { return }
        ultimoConteo = Date()
        let total = frame.anchors.reduce(0) { $0 + (($1 as? ARMeshAnchor)?.geometry.faces.count ?? 0) }
        let mensaje = Self.mensaje(frame.camera.trackingState)
        DispatchQueue.main.async {
            self.triangulos = total
            self.aviso = mensaje
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        let texto = MensajeError.texto(error)
        DispatchQueue.main.async {
            self.aviso = texto
            self.escaneando = false
        }
    }

    // MARK: - Photos

    /// Keeps a photo each time the camera has moved or turned enough, so the
    /// whole space ends up covered without filling the memory.
    private func tomarFotoSiConviene(_ frame: ARFrame) {
        let camara = frame.camera
        let t = camara.transform
        // Skip blurry photos: only shoot while the iPhone is almost still.
        let anterior = fotoAnterior
        fotoAnterior = (t, frame.timestamp)
        guard capturando, !procesandoFoto, case .normal = camara.trackingState else { return }
        guard Date().timeIntervalSince(ultimaFotoFecha) > 0.4 else { return }
        if let anterior, frame.timestamp > anterior.tiempo {
            let dt = Float(frame.timestamp - anterior.tiempo)
            let velocidad = simd_distance(t.posicion, anterior.transform.posicion) / dt
            let giro = acos(min(1, max(-1, simd_dot(-t.columns.2.xyz, -anterior.transform.columns.2.xyz)))) / dt
            guard velocidad < 0.35, giro < 0.5 else { return }
        }
        if let anterior = ultimaFoto {
            let movimiento = simd_distance(t.posicion, anterior.posicion)
            let giro = acos(min(1, max(-1, simd_dot(-t.columns.2.xyz, -anterior.columns.2.xyz))))
            guard movimiento > 0.25 || giro > 0.35 else { return }
        }
        candado.lock()
        let lleno = fotogramas.count >= Self.maximoFotos
        candado.unlock()
        guard !lleno else { return }

        procesandoFoto = true
        ultimaFoto = t
        ultimaFotoFecha = Date()
        let imagen = frame.capturedImage
        let profundidad = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap
        let archivo = carpetaFotos.appendingPathComponent("captura-\(Int(frame.timestamp * 1000)).jpg")
        colaFotos.async { [weak self] in
            guard let self else { return }
            let fotograma = Self.fotograma(imagen: imagen, profundidad: profundidad, camara: camara, contexto: self.contextoCI, archivo: archivo)
            self.candado.lock()
            if let fotograma { self.fotogramas.append(fotograma) }
            let total = self.fotogramas.count
            self.candado.unlock()
            DispatchQueue.main.async {
                self.fotos = total
                self.procesandoFoto = false
            }
        }
    }

    /// Saves the photo as a 1440 px JPEG for the texture, keeps a small copy for
    /// the vertex colours and copies the LiDAR depth.
    private static func fotograma(imagen: CVPixelBuffer, profundidad: CVPixelBuffer?, camara: ARCamera, contexto: CIContext, archivo: URL) -> Fotograma? {
        let anchoOriginal = CVPixelBufferGetWidth(imagen)
        let altoOriginal = CVPixelBufferGetHeight(imagen)
        guard anchoOriginal > 0 else { return nil }
        let original = CIImage(cvPixelBuffer: imagen)
        let escalaTextura = CGFloat(min(1, anchoTextura / Float(anchoOriginal)))
        let grande = original.transformed(by: CGAffineTransform(scaleX: escalaTextura, y: escalaTextura))
        let guardada = (try? contexto.writeJPEGRepresentation(
            of: grande, to: archivo, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.82]
        )) != nil

        let escala = anchoColor / Float(anchoOriginal)
        let ancho = Int(Float(anchoOriginal) * escala)
        let alto = Int(Float(altoOriginal) * escala)
        let reducida = original.transformed(by: CGAffineTransform(scaleX: CGFloat(escala), y: CGFloat(escala)))
        guard let cg = contexto.createCGImage(reducida, from: CGRect(x: 0, y: 0, width: ancho, height: alto)) else { return nil }

        var rgba = [UInt8](repeating: 0, count: ancho * alto * 4)
        let dibujado = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let contexto = CGContext(
                data: buffer.baseAddress, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: ancho * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            contexto.draw(cg, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
            return true
        }
        guard dibujado else { return nil }

        let k = camara.intrinsics
        var fotograma = Fotograma(
            camaraAMundo: camara.transform,
            fx: k.columns.0.x * escala, fy: k.columns.1.y * escala,
            cx: k.columns.2.x * escala, cy: k.columns.2.y * escala,
            ancho: ancho, alto: alto, rgba: rgba
        )
        fotograma.archivo = guardada ? archivo : nil

        if let profundidad, CVPixelBufferGetPixelFormatType(profundidad) == kCVPixelFormatType_DepthFloat32 {
            CVPixelBufferLockBaseAddress(profundidad, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(profundidad, .readOnly) }
            let w = CVPixelBufferGetWidth(profundidad)
            let h = CVPixelBufferGetHeight(profundidad)
            let bytesFila = CVPixelBufferGetBytesPerRow(profundidad)
            if let base = CVPixelBufferGetBaseAddress(profundidad) {
                var valores = [Float](repeating: 0, count: w * h)
                for y in 0..<h {
                    let fila = base.advanced(by: y * bytesFila).assumingMemoryBound(to: Float32.self)
                    for x in 0..<w { valores[y * w + x] = fila[x] }
                }
                fotograma.profundidad = valores
                fotograma.anchoProfundidad = w
                fotograma.altoProfundidad = h
            }
        }
        return fotograma
    }

    private static func mensaje(_ estado: ARCamera.TrackingState) -> String {
        switch estado {
        case .normal: return "Escaneando… cubre paredes, piso, techo y muebles."
        case .notAvailable: return "El seguimiento no está disponible."
        case .limited(.excessiveMotion): return "Más despacio."
        case .limited(.insufficientFeatures): return "Apunta a una zona con más detalle o luz."
        case .limited(.initializing): return "Iniciando… mueve el iPhone un poco."
        case .limited(.relocalizing): return "Recuperando la posición…"
        case .limited: return "Seguimiento limitado."
        }
    }

    // MARK: - Geometry

    private func geometria(_ g: ARMeshGeometry) -> SCNGeometry {
        let v = g.vertices
        let vertices = SCNGeometrySource(buffer: v.buffer, vertexFormat: v.format, semantic: .vertex, vertexCount: v.count, dataOffset: v.offset, dataStride: v.stride)
        let n = g.normals
        let normales = SCNGeometrySource(buffer: n.buffer, vertexFormat: n.format, semantic: .normal, vertexCount: n.count, dataOffset: n.offset, dataStride: n.stride)
        let f = g.faces
        let datos = Data(bytes: f.buffer.contents(), count: f.count * f.indexCountPerPrimitive * f.bytesPerIndex)
        let elemento = SCNGeometryElement(data: datos, primitiveType: .triangles, primitiveCount: f.count, bytesPerIndex: f.bytesPerIndex)
        let geometria = SCNGeometry(sources: [vertices, normales], elements: [elemento])
        geometria.materials = [material]
        return geometria
    }

    static func pieza(_ ancla: ARMeshAnchor) -> PiezaMalla {
        let g = ancla.geometry
        let t = ancla.transform
        let rotacion = simd_float3x3(t.columns.0.xyz, t.columns.1.xyz, t.columns.2.xyz)

        func leer(_ fuente: ARGeometrySource, _ i: Int) -> SIMD3<Float> {
            let p = fuente.buffer.contents().advanced(by: fuente.offset + fuente.stride * i).assumingMemoryBound(to: Float.self)
            return SIMD3(p[0], p[1], p[2])
        }

        var vertices: [(Float, Float, Float)] = []
        vertices.reserveCapacity(g.vertices.count)
        for i in 0..<g.vertices.count {
            let w = (t * SIMD4<Float>(leer(g.vertices, i), 1)).xyz
            vertices.append((w.x, w.y, w.z))
        }

        var normales: [(Float, Float, Float)] = []
        if g.normals.count == g.vertices.count {
            normales.reserveCapacity(g.normals.count)
            for i in 0..<g.normals.count {
                let n = simd_normalize(rotacion * leer(g.normals, i))
                normales.append((n.x, n.y, n.z))
            }
        }

        let f = g.faces
        let total = f.count * f.indexCountPerPrimitive
        var indices: [UInt32] = []
        indices.reserveCapacity(total)
        let base = f.buffer.contents()
        for i in 0..<total {
            let p = base.advanced(by: i * f.bytesPerIndex)
            indices.append(f.bytesPerIndex == 2 ? UInt32(p.assumingMemoryBound(to: UInt16.self).pointee) : p.assumingMemoryBound(to: UInt32.self).pointee)
        }
        return PiezaMalla(vertices: vertices, normales: normales, indices: indices)
    }
}
