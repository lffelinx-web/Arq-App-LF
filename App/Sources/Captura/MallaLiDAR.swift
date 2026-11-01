import ARKit
import AVFoundation
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
    static let anchoTextura: Float = 2560
    static let anchoColor: Float = 320
    /// Photos are written here while scanning and moved into the project on saving.
    let carpetaFotos = FileManager.default.temporaryDirectory.appendingPathComponent("Fotos-\(UUID().uuidString)", isDirectory: true)
    private var fotoAnterior: (transform: simd_float4x4, tiempo: TimeInterval)?
    /// When the session (re)started, to lock the camera once auto-exposure settles.
    private var inicioSesion = Date()
    private var camaraBloqueada = false
    /// Ajustes → "Fijar exposición" (on by default).
    private var fijarExposicion: Bool { UserDefaults.standard.object(forKey: "fijarExposicion") as? Bool ?? true }
    private var altaResolucion = false
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
        // A 4:3 format that can also take full-resolution stills for the textures.
        if let formato = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuracion.videoFormat = formato
            altaResolucion = true
        } else {
            altaResolucion = false
        }
        return configuracion
    }

    /// Locks white balance and exposure so every photo has the same tone.
    private func bloquearCamara() {
        guard fijarExposicion, let camara = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return }
        do {
            try camara.lockForConfiguration()
            if camara.isWhiteBalanceModeSupported(.locked) { camara.whiteBalanceMode = .locked }
            if camara.isExposureModeSupported(.locked) { camara.exposureMode = .locked }
            camara.unlockForConfiguration()
        } catch {}
    }

    private func liberarCamara() {
        camaraBloqueada = false
        guard let camara = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return }
        do {
            try camara.lockForConfiguration()
            if camara.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camara.whiteBalanceMode = .continuousAutoWhiteBalance }
            if camara.isExposureModeSupported(.continuousAutoExposure) { camara.exposureMode = .continuousAutoExposure }
            camara.unlockForConfiguration()
        } catch {}
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
        liberarCamara()
        inicioSesion = Date()
        vista.session.run(configuracion(), options: [.resetTracking, .removeExistingAnchors])
        capturando = true
        escaneando = true
    }

    /// Continues after a pause keeping what was scanned.
    func reanudar() {
        vista.session.run(configuracion())
        // Pausing may reset the camera; lock it again once it settles.
        camaraBloqueada = false
        inicioSesion = Date()
        capturando = true
        escaneando = true
    }

    func pausar() {
        capturando = false
        vista.session.pause()
        escaneando = false
    }

    /// Leaves the camera on automatic for the rest of the app.
    func cerrar() {
        pausar()
        liberarCamara()
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
        // One welded, cleaned mesh instead of ARKit's loose pieces.
        var malla = LimpiezaMalla.limpiar(Texturizar.unir(piezas))
        var fotogramas = fotogramas
        if !fotogramas.isEmpty {
            Exposicion.igualar(&fotogramas, malla: malla)
            malla.colores = Colorear.colores(vertices: malla.vertices, normales: malla.normales, fotogramas: fotogramas)
        }
        let texturizada = try guardarTextura(malla, fotogramas: fotogramas, en: carpeta)
        let ply = carpeta.appendingPathComponent(ArchivoProyecto.mallaPLY.rawValue)
        let totales = try PLY.escribir([malla], en: ply)
        let obj = carpeta.appendingPathComponent(ArchivoProyecto.mallaOBJ.rawValue)
        try OBJ.escribir([malla], en: obj, nombre: Formato.nombreArchivo(nombre))
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
        let contexto = CIContext(options: [.cacheIntermediates: false])
        for foto in texturizada.fotosUsadas {
            let fotograma = conFoto[Int(foto)]
            guard let origen = fotograma.archivo else { continue }
            let destino = fotos.appendingPathComponent(Texturizar.nombreFoto(foto))
            try? FileManager.default.removeItem(at: destino)
            if !copiar(origen, a: destino, ganancia: fotograma.ganancia, contexto: contexto) {
                try FileManager.default.copyItem(at: origen, to: destino)
            }
        }
        try Texturizar.escribirOBJ(texturizada, en: fotos)
        try Texturizar.datos(texturizada).write(to: carpeta.appendingPathComponent(ArchivoProyecto.texturaBIN.rawValue), options: .atomic)
        return texturizada
    }


    /// Copies a photo applying its exposure gain. The gain was measured on sRGB
    /// values; Core Image works in linear light, hence the 2.2 power.
    private static func copiar(_ origen: URL, a destino: URL, ganancia: SIMD3<Float>, contexto: CIContext) -> Bool {
        guard simd_reduce_max(simd_abs(ganancia - 1)) > 0.01 else { return false }
        guard let imagen = CIImage(contentsOf: origen), let filtro = CIFilter(name: "CIColorMatrix") else { return false }
        let lineal = SIMD3<Float>(pow(ganancia.x, 2.2), pow(ganancia.y, 2.2), pow(ganancia.z, 2.2))
        filtro.setValue(imagen, forKey: kCIInputImageKey)
        filtro.setValue(CIVector(x: CGFloat(lineal.x), y: 0, z: 0, w: 0), forKey: "inputRVector")
        filtro.setValue(CIVector(x: 0, y: CGFloat(lineal.y), z: 0, w: 0), forKey: "inputGVector")
        filtro.setValue(CIVector(x: 0, y: 0, z: CGFloat(lineal.z), w: 0), forKey: "inputBVector")
        guard let salida = filtro.outputImage else { return false }
        return (try? contexto.writeJPEGRepresentation(
            of: salida, to: destino, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
        )) != nil
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
        if !camaraBloqueada, capturando, case .normal = frame.camera.trackingState, Date().timeIntervalSince(inicioSesion) > 1.5 {
            camaraBloqueada = true
            bloquearCamara()
        }
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
        guard altaResolucion else {
            procesar(imagen: imagen, profundidad: profundidad, camara: camara, archivo: archivo)
            return
        }
        // Full-resolution still (about 4032 × 3024) for sharper textures; the
        // depth from the current frame still applies because the iPhone is still.
        vista.session.captureHighResolutionFrame { [weak self] alta, _ in
            guard let self else { return }
            if let alta {
                self.procesar(imagen: alta.capturedImage, profundidad: profundidad, camara: alta.camera, archivo: archivo)
            } else {
                self.procesar(imagen: imagen, profundidad: profundidad, camara: camara, archivo: archivo)
            }
        }
    }

    private func procesar(imagen: CVPixelBuffer, profundidad: CVPixelBuffer?, camara: ARCamera, archivo: URL) {
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
        fotograma.nitidez = Fotograma.nitidez(rgba: rgba, ancho: ancho, alto: alto)

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
