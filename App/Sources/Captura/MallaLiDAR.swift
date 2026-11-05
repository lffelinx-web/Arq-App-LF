import ARKit
import AVFoundation
import Combine
import CoreImage
import ModelIO
import SceneKit
import UIKit
import Vision

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
    /// False while a new section is still finding its place in the earlier ones.
    @Published private(set) var ubicado = true

    /// Enough for a large section; each photo keeps about 0.6 MB in memory.
    static let maximoFotos = 160
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

    /// Live mesh: translucent, tinted per vertex by the coverage guide
    /// (green = some photo already covers it, amber = still needs a photo).
    private let material: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.white
        m.lightingModel = .constant
        m.transparency = 0.55
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }()
    private var ultimoConteo = Date.distantPast

    /// World map of the earlier sections, when this scan continues a project.
    private var mapaInicial: ARWorldMap?
    private var vioReubicando = false
    /// Earlier sections drawn faintly once the position is found.
    private let nodoSecciones = SCNNode()

    /// Coverage guide: 10 cm cells the photos have already seen.
    static let tamanoCelda: Float = 0.1
    private let candadoCobertura = NSLock()
    private var celdasCubiertas = Set<SIMD3<Int32>>()
    /// Mesh nodes, touched only on SceneKit's render thread.
    private var nodos: [UUID: (nodo: SCNNode, ancla: ARMeshAnchor)] = [:]
    private var recolorear = false
    private var ultimoRecoloreo = Date.distantPast

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: carpetaFotos, withIntermediateDirectories: true)
        vista.delegate = self
        vista.session.delegate = self
        vista.automaticallyUpdatesLighting = true
        vista.rendersContinuously = true
        nodoSecciones.isHidden = true
        vista.scene.rootNode.addChildNode(nodoSecciones)
    }

    deinit {
        try? FileManager.default.removeItem(at: carpetaFotos)
    }

    private func configuracion() -> ARWorldTrackingConfiguration {
        let configuracion = ARWorldTrackingConfiguration()
        // With classification ARKit's on-device model labels each face as wall,
        // floor, ceiling, table, seat, window or door (used to straighten surfaces).
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuracion.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuracion.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuracion.frameSemantics.insert(.sceneDepth)
        }
        configuracion.planeDetection = [.horizontal, .vertical]
        configuracion.initialWorldMap = mapaInicial
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

    /// Starts from scratch, dropping the mesh and photos. With `mapa` (the world
    /// map of earlier sections) it first finds its place in them, so the new
    /// section comes out in the same coordinates.
    func iniciar(mapa: ARWorldMap?) {
        mapaInicial = mapa
        iniciar()
    }

    func iniciar() {
        candado.lock()
        fotogramas.removeAll()
        candadoCobertura.lock()
        celdasCubiertas.removeAll()
        candadoCobertura.unlock()
        candado.unlock()
        try? FileManager.default.removeItem(at: carpetaFotos)
        try? FileManager.default.createDirectory(at: carpetaFotos, withIntermediateDirectories: true)
        ultimaFoto = nil
        fotos = 0
        liberarCamara()
        inicioSesion = Date()
        vioReubicando = false
        ubicado = mapaInicial == nil
        nodoSecciones.isHidden = !ubicado
        vista.session.run(configuracion(), options: [.resetTracking, .removeExistingAnchors])
        capturando = true
        escaneando = true
    }

    /// Shows the earlier sections (their PLY) faintly as a guide.
    func mostrarSecciones(_ carpetas: [URL]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nodos = carpetas.compactMap { carpeta -> SCNNode? in
                guard let ply = try? PLY.leer(carpeta.appendingPathComponent(ArchivoProyecto.mallaPLY.rawValue)) else { return nil }
                let nodo = EscenaMalla.nodo(ply)
                for material in nodo.geometry?.materials ?? [] {
                    material.transparency = 0.35
                    material.writesToDepthBuffer = false
                    material.lightingModel = .constant
                }
                return nodo
            }
            DispatchQueue.main.async { nodos.forEach { self?.nodoSecciones.addChildNode($0) } }
        }
    }

    /// Current world map (without the mesh, which each section saves itself),
    /// for scanning more sections later. Call it before pausing.
    func obtenerMapa(_ listo: @escaping (ARWorldMap?) -> Void) {
        vista.session.getCurrentWorldMap { mapa, _ in
            if let mapa { mapa.anchors = mapa.anchors.filter { !($0 is ARMeshAnchor) } }
            DispatchQueue.main.async { listo(mapa) }
        }
    }

    static func guardarMapa(_ mapa: ARWorldMap, en url: URL) throws {
        try NSKeyedArchiver.archivedData(withRootObject: mapa, requiringSecureCoding: true).write(to: url, options: .atomic)
    }

    static func leerMapa(_ url: URL) -> ARWorldMap? {
        guard let datos = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: datos)
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
    /// - Parameter ocupado: cells earlier sections already cover (`Secciones.celdas`).
    static func guardar(
        _ piezas: [PiezaMalla], fotogramas: [Fotograma], captura: UIImage?, en carpeta: URL, nombre: String,
        ocupado: Set<SIMD3<Int32>> = []
    ) throws -> (vertices: Int, triangulos: Int) {
        // One welded, cleaned mesh instead of ARKit's loose pieces.
        // Clean, straighten walls, floor and ceiling (ARKit's classification), then
        // zip up the cracks between ARKit's pieces, now that both sides are coplanar.
        var malla = LimpiezaMalla.cerrarRendijas(Planos.regularizar(LimpiezaMalla.limpiar(Texturizar.unir(piezas))))
        // A new section drops what the earlier ones already have.
        malla = LimpiezaMalla.quitarTraslape(malla, ocupado: ocupado)
        var fotogramas = fotogramas
        var etiquetas: [Int32] = []
        if !fotogramas.isEmpty {
            Exposicion.igualar(&fotogramas, malla: malla)
            // Photo for each triangle; what no photo saw at the edge of the scan goes.
            let conFoto = fotogramas.filter { $0.archivo != nil }
            if !conFoto.isEmpty, malla.triangulos > 0 {
                (malla, etiquetas) = LimpiezaMalla.recortarSinFoto(malla, etiquetas: Texturizar.etiquetas(malla, fotogramas: conFoto))
            }
            let (colores, vistos) = Colorear.coloresYVistos(vertices: malla.vertices, normales: malla.normales, fotogramas: fotogramas)
            malla.colores = Colorear.rellenar(colores, vistos: vistos, malla: malla)
        }
        let texturizada = try guardarTextura(malla, etiquetas: etiquetas, fotogramas: fotogramas, en: carpeta)
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

    /// All sections as one USDZ (with their textures) and one PLY, for AR and
    /// for other programs.
    static func unirSecciones(_ carpetas: [URL], en proyecto: URL) throws {
        let escena = SCNScene()
        var piezas: [PiezaMalla] = []
        for carpeta in carpetas {
            let bin = carpeta.appendingPathComponent(ArchivoProyecto.texturaBIN.rawValue)
            let fotos = carpeta.appendingPathComponent(ArchivoProyecto.carpetaTextura.rawValue)
            let ply = try? PLY.leer(carpeta.appendingPathComponent(ArchivoProyecto.mallaPLY.rawValue))
            if let datos = try? Data(contentsOf: bin), let malla = try? Texturizar.leer(datos) {
                let parte = EscenaMalla.escena(malla) { foto in fotos.appendingPathComponent(Texturizar.nombreFoto(foto)) }
                parte.rootNode.childNodes.forEach { escena.rootNode.addChildNode($0) }
            } else if let ply {
                escena.rootNode.addChildNode(EscenaMalla.nodo(ply))
            }
            if let ply { piezas.append(PiezaMalla(ply)) }
        }
        let usdz = proyecto.appendingPathComponent(ArchivoProyecto.completoUSDZ.rawValue)
        try? FileManager.default.removeItem(at: usdz)
        _ = escena.write(to: usdz, options: nil, delegate: nil, progressHandler: nil)
        if !piezas.isEmpty {
            try PLY.escribir(piezas, en: proyecto.appendingPathComponent(ArchivoProyecto.completoPLY.rawValue))
        }
    }

    /// Projects the photos onto the mesh, packs the pieces it uses into up to
    /// eight 4096 px texture images with blended seams, and writes `textura.bin`
    /// plus the `textura/` folder (OBJ, MTL and those images).
    private static func guardarTextura(_ malla: PiezaMalla, etiquetas: [Int32], fotogramas: [Fotograma], en carpeta: URL) throws -> MallaTexturizada? {
        let conFoto = fotogramas.filter { $0.archivo != nil }
        guard !conFoto.isEmpty, malla.triangulos > 0, etiquetas.count == malla.triangulos else { return nil }
        let tamanos = conFoto.map { f in f.archivo.flatMap(ImagenesIO.tamano) ?? SIMD2(f.ancho, f.alto) }
        guard etiquetas.contains(where: { $0 >= 0 }) else { return nil }
        let uvs = Texturizar.uvs(malla, etiquetas: etiquetas, fotogramas: conFoto)
        let plan = Atlas.planificar(
            malla, etiquetas: etiquetas, uvFoto: uvs, fotogramas: conFoto, tamanos: tamanos,
            maximoAtlas: Atlas.maximoAtlas(area: Atlas.area(malla))
        )

        let fotos = carpeta.appendingPathComponent(ArchivoProyecto.carpetaTextura.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: fotos, withIntermediateDirectories: true)
        for indice in 0..<plan.numeroAtlas {
            let imagen = autoreleasepool {
                Atlas.hornear(plan, atlas: indice) { foto in conFoto[Int(foto)].archivo.flatMap(ImagenesIO.leer) }
            }
            ImagenesIO.escribirJPEG(imagen, en: fotos.appendingPathComponent(Texturizar.nombreFoto(Int32(indice))))
        }
        try Texturizar.escribirOBJ(plan.malla, en: fotos)
        try Texturizar.datos(plan.malla).write(to: carpeta.appendingPathComponent(ArchivoProyecto.texturaBIN.rawValue), options: .atomic)
        return plan.malla
    }

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let malla = anchor as? ARMeshAnchor else { return nil }
        let nodo = SCNNode(geometry: geometria(malla))
        nodos[malla.identifier] = (nodo, malla)
        return nodo
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let malla = anchor as? ARMeshAnchor else { return }
        node.geometry = geometria(malla)
        nodos[malla.identifier] = (node, malla)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        nodos[anchor.identifier] = nil
    }

    /// After a new photo, repaints the coverage of the pieces that didn't change.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard recolorear, Date().timeIntervalSince(ultimoRecoloreo) > 1 else { return }
        recolorear = false
        ultimoRecoloreo = Date()
        for (_, par) in nodos { par.nodo.geometry = geometria(par.ancla) }
    }

    // MARK: - Coverage guide

    private func marcarCubierto(_ fotograma: Fotograma) {
        let celdas = fotograma.puntosVistos().map(Self.celda)
        candadoCobertura.lock()
        celdasCubiertas.formUnion(celdas)
        candadoCobertura.unlock()
        recolorear = true
    }

    static func celda(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / tamanoCelda).rounded(.down)), Int32((p.y / tamanoCelda).rounded(.down)), Int32((p.z / tamanoCelda).rounded(.down)))
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if !camaraBloqueada, capturando, case .normal = frame.camera.trackingState, Date().timeIntervalSince(inicioSesion) > 1.5 {
            camaraBloqueada = true
            bloquearCamara()
        }
        if !ubicado {
            switch frame.camera.trackingState {
            case .limited(.relocalizing): vioReubicando = true
            case .normal where vioReubicando:
                DispatchQueue.main.async {
                    self.ubicado = true
                    self.nodoSecciones.isHidden = false
                }
            default: break
            }
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
        guard capturando, ubicado, !procesandoFoto, case .normal = camara.trackingState else { return }
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
            if let fotograma {
                self.fotogramas.append(fotograma)
                self.marcarCubierto(fotograma)
            }
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
        fotograma.personas = mascaraPersonas(original, camara: camara, ancho: ancho, alto: alto, contexto: contexto)

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

    /// Where the people are in the photo (1 = person), at `ancho` × `alto`, using
    /// Apple's person segmentation. The camera image is landscape whatever way the
    /// iPhone is held, so it is turned upright first (people are found much more
    /// reliably standing up) and the mask is turned back afterwards.
    private static func mascaraPersonas(_ imagen: CIImage, camara: ARCamera, ancho: Int, alto: Int, contexto: CIContext) -> [UInt8] {
        // World "up" seen from the camera: image X is camera +X, image rows grow along camera -Y.
        let arriba = camara.transform.inverse * SIMD4<Float>(0, 1, 0, 0)
        let orientacion: CGImagePropertyOrientation
        if abs(arriba.x) > abs(arriba.y) {
            orientacion = arriba.x < 0 ? .right : .left
        } else {
            orientacion = arriba.y > 0 ? .up : .down
        }
        let inversa: CGImagePropertyOrientation = orientacion == .right ? .left : orientacion == .left ? .right : orientacion

        let derecha = imagen.oriented(orientacion)
        let escala = 512 / max(derecha.extent.width, derecha.extent.height)
        let pequena = derecha.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
        guard let cg = contexto.createCGImage(pequena, from: pequena.extent) else { return [] }

        let solicitud = VNGeneratePersonSegmentationRequest()
        solicitud.qualityLevel = .balanced
        solicitud.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([solicitud])
        } catch {
            return []
        }
        guard let mascara = solicitud.results?.first?.pixelBuffer else { return [] }

        // Back to the camera's orientation and the photo's small size.
        var vuelta = CIImage(cvPixelBuffer: mascara).oriented(inversa)
        vuelta = vuelta.transformed(by: CGAffineTransform(translationX: -vuelta.extent.minX, y: -vuelta.extent.minY))
        vuelta = vuelta.transformed(by: CGAffineTransform(scaleX: CGFloat(ancho) / vuelta.extent.width, y: CGFloat(alto) / vuelta.extent.height))
        guard let cgMascara = contexto.createCGImage(vuelta, from: CGRect(x: 0, y: 0, width: ancho, height: alto)) else { return [] }
        var gris = [UInt8](repeating: 0, count: ancho * alto)
        let dibujado = gris.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: ancho,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            c.draw(cgMascara, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
            return true
        }
        guard dibujado else { return [] }
        let personas = gris.map { $0 > 127 ? UInt8(1) : 0 }
        return personas.contains(1) ? personas : []
    }

    private static func mensaje(_ estado: ARCamera.TrackingState) -> String {
        switch estado {
        case .normal: return "Escaneando… cubre paredes, piso, techo y muebles."
        case .notAvailable: return "El seguimiento no está disponible."
        case .limited(.excessiveMotion): return "Más despacio."
        case .limited(.insufficientFeatures): return "Apunta a una zona con más detalle o luz."
        case .limited(.initializing): return "Iniciando… mueve el iPhone un poco."
        case .limited(.relocalizing): return "Ubicándose… apunta a una zona que ya escaneaste."
        case .limited: return "Seguimiento limitado."
        }
    }

    // MARK: - Geometry

    private func geometria(_ ancla: ARMeshAnchor) -> SCNGeometry {
        let g = ancla.geometry
        let v = g.vertices
        let vertices = SCNGeometrySource(buffer: v.buffer, vertexFormat: v.format, semantic: .vertex, vertexCount: v.count, dataOffset: v.offset, dataStride: v.stride)
        let n = g.normals
        let normales = SCNGeometrySource(buffer: n.buffer, vertexFormat: n.format, semantic: .normal, vertexCount: n.count, dataOffset: n.offset, dataStride: n.stride)
        let f = g.faces
        let datos = Data(bytes: f.buffer.contents(), count: f.count * f.indexCountPerPrimitive * f.bytesPerIndex)
        let elemento = SCNGeometryElement(data: datos, primitiveType: .triangles, primitiveCount: f.count, bytesPerIndex: f.bytesPerIndex)
        let geometria = SCNGeometry(sources: [vertices, normales, colores(ancla)], elements: [elemento])
        geometria.materials = [material]
        return geometria
    }

    /// Green where a photo already covers the mesh, amber where one is missing.
    private func colores(_ ancla: ARMeshAnchor) -> SCNGeometrySource {
        let g = ancla.geometry
        let t = ancla.transform
        candadoCobertura.lock()
        let cubiertas = celdasCubiertas
        candadoCobertura.unlock()
        var valores = [Float]()
        valores.reserveCapacity(g.vertices.count * 3)
        for i in 0..<g.vertices.count {
            let p = g.vertices.buffer.contents().advanced(by: g.vertices.offset + g.vertices.stride * i).assumingMemoryBound(to: Float.self)
            let mundo = (t * SIMD4<Float>(p[0], p[1], p[2], 1)).xyz
            if cubiertas.contains(Self.celda(mundo)) {
                valores += [0.30, 0.85, 0.55]
            } else {
                valores += [0.96, 0.65, 0.24]
            }
        }
        let datos = valores.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: datos, semantic: .color, vectorCount: g.vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3
        )
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
        // Per-vertex class: the most common class among the faces around it.
        var clases: [UInt8] = []
        if let clasificacion = g.classification, clasificacion.count == f.count {
            var votos = [[UInt16]](repeating: [UInt16](repeating: 0, count: 8), count: g.vertices.count)
            for cara in 0..<f.count {
                let valor = clasificacion.buffer.contents().advanced(by: clasificacion.offset + clasificacion.stride * cara).assumingMemoryBound(to: UInt8.self).pointee
                let c = Int(min(valor, 7))
                for k in 0..<3 { votos[Int(indices[cara * 3 + k])][c] &+= 1 }
            }
            clases = votos.map { v in UInt8(v.indices.max { v[$0] < v[$1] } ?? 0) }
        }
        return PiezaMalla(vertices: vertices, normales: normales, indices: indices, clases: clases)
    }
}
