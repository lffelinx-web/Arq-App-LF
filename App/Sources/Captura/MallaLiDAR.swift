import ARKit
import Combine
import ModelIO
import SceneKit
import UIKit

/// Free-form LiDAR scan: ARKit rebuilds the surfaces around you as a triangle
/// mesh, which is saved as OBJ (and USDZ when possible).
final class MallaLiDAR: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    let vista = ARSCNView(frame: .zero)
    @Published private(set) var triangulos = 0
    @Published private(set) var aviso = "Mueve el iPhone despacio para cubrir todo el espacio."
    @Published private(set) var escaneando = false

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
        vista.delegate = self
        vista.session.delegate = self
        vista.automaticallyUpdatesLighting = true
        vista.rendersContinuously = true
    }

    func iniciar() {
        let configuracion = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuracion.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuracion.frameSemantics.insert(.sceneDepth)
        }
        configuracion.planeDetection = [.horizontal, .vertical]
        vista.session.run(configuracion, options: [.resetTracking, .removeExistingAnchors])
        escaneando = true
    }

    func pausar() {
        vista.session.pause()
        escaneando = false
    }

    /// Mesh anchors converted to world coordinates.
    func piezas() -> [PiezaMalla] {
        let anclas = vista.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        return anclas.map(Self.pieza)
    }

    /// Saves the scan into `carpeta`, returning the vertex and triangle count.
    static func guardar(_ piezas: [PiezaMalla], captura: UIImage?, en carpeta: URL, nombre: String) throws -> (vertices: Int, triangulos: Int) {
        let obj = carpeta.appendingPathComponent(ArchivoProyecto.mallaOBJ.rawValue)
        let totales = try OBJ.escribir(piezas, en: obj, nombre: Formato.nombreArchivo(nombre))
        if let captura {
            try? captura.reducida(a: 1600).jpegData(compressionQuality: 0.85)?.write(to: carpeta.appendingPathComponent(ArchivoProyecto.foto.rawValue))
            try? captura.reducida(a: 400).jpegData(compressionQuality: 0.8)?.write(to: carpeta.appendingPathComponent(ArchivoProyecto.miniatura.rawValue))
        }
        // USDZ opens in Quick Look and AR; OBJ stays as the universal copy.
        let asset = MDLAsset(url: obj)
        if MDLAsset.canExportFileExtension("usdz") {
            try? asset.export(to: carpeta.appendingPathComponent(ArchivoProyecto.modeloUSDZ.rawValue))
        }
        return totales
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
        guard Date().timeIntervalSince(ultimoConteo) > 0.5 else { return }
        ultimoConteo = Date()
        let total = frame.anchors.reduce(0) { $0 + (($1 as? ARMeshAnchor)?.geometry.faces.count ?? 0) }
        let mensaje = Self.mensaje(frame.camera.trackingState)
        DispatchQueue.main.async {
            self.triangulos = total
            self.aviso = mensaje
        }
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
