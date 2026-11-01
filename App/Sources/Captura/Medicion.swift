import ARKit
import Combine
import SceneKit
import UIKit

/// Point-to-point measuring tape. Aims with the centre of the screen and uses
/// the LiDAR depth (through ARKit's estimated planes) to land on real surfaces.
final class Medicion: NSObject, ObservableObject, ARSCNViewDelegate {
    let vista = ARSCNView(frame: .zero)
    @Published private(set) var medidas: [Medida] = []
    /// Distance from the pending first point to where the user is aiming.
    @Published private(set) var distanciaActual: Double?
    @Published private(set) var apuntando = false
    @Published private(set) var midiendo = false

    private static let acento = UIColor(red: 0.96, green: 0.65, blue: 0.24, alpha: 1)
    private var inicio: SIMD3<Float>?
    private var objetivo: SIMD3<Float>?
    private var nodosPorMedida: [[SCNNode]] = []
    private var nodoInicio: SCNNode?
    private let mira = Medicion.esfera(radio: 0.004, color: .white)
    private let lineaPrevia = SCNNode()

    override init() {
        super.init()
        vista.delegate = self
        vista.automaticallyUpdatesLighting = true
        vista.scene.rootNode.addChildNode(mira)
        vista.scene.rootNode.addChildNode(lineaPrevia)
        mira.isHidden = true
    }

    func iniciar() {
        let configuracion = ARWorldTrackingConfiguration()
        configuracion.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuracion.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuracion.frameSemantics.insert(.sceneDepth)
        }
        vista.session.run(configuracion)
    }

    func pausar() { vista.session.pause() }

    /// First tap fixes the start; the second closes the measurement.
    func agregarPunto() {
        guard let objetivo else { return }
        if let inicio {
            let metros = Double(simd_distance(inicio, objetivo))
            guard metros > 0.005 else { return }
            let linea = Self.linea(de: inicio, a: objetivo, color: Self.acento)
            let fin = Self.esfera(radio: 0.006, color: Self.acento)
            fin.simdPosition = objetivo
            let etiqueta = Self.etiqueta(Formato.longitud(metros, unidad), en: (inicio + objetivo) / 2)
            let nodos = [nodoInicio, linea, fin, etiqueta].compactMap { $0 }
            nodos.forEach { if $0.parent == nil { vista.scene.rootNode.addChildNode($0) } }
            nodosPorMedida.append(nodos)
            medidas.append(Medida(nombre: "Medida \(medidas.count + 1)", metros: metros))
            self.inicio = nil
            nodoInicio = nil
            lineaPrevia.isHidden = true
            distanciaActual = nil
            midiendo = false
        } else {
            inicio = objetivo
            let punto = Self.esfera(radio: 0.006, color: Self.acento)
            punto.simdPosition = objetivo
            vista.scene.rootNode.addChildNode(punto)
            nodoInicio = punto
            midiendo = true
        }
    }

    /// Cancels a measurement in progress or removes the last one.
    func deshacer() {
        if inicio != nil {
            nodoInicio?.removeFromParentNode()
            nodoInicio = nil
            inicio = nil
            lineaPrevia.isHidden = true
            distanciaActual = nil
            midiendo = false
        } else if let ultimos = nodosPorMedida.popLast() {
            ultimos.forEach { $0.removeFromParentNode() }
            medidas.removeLast()
        }
    }

    var unidad: Unidad = .metros

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { self.actualizarObjetivo() }
    }

    private func actualizarObjetivo() {
        let centro = CGPoint(x: vista.bounds.midX, y: vista.bounds.midY)
        guard vista.bounds.width > 0,
              let consulta = vista.raycastQuery(from: centro, allowing: .estimatedPlane, alignment: .any),
              let impacto = vista.session.raycast(consulta).first
        else {
            if apuntando { apuntando = false }
            mira.isHidden = true
            objetivo = nil
            return
        }
        let punto = impacto.worldTransform.posicion
        objetivo = punto
        mira.simdPosition = punto
        mira.isHidden = false
        if !apuntando { apuntando = true }

        if let inicio {
            Self.colocar(lineaPrevia, de: inicio, a: punto, color: .white)
            lineaPrevia.isHidden = false
            let nueva = Double(simd_distance(inicio, punto))
            if abs(nueva - (distanciaActual ?? -1)) > 0.0005 { distanciaActual = nueva }
        }
    }

    // MARK: - Nodes

    private static func esfera(radio: CGFloat, color: UIColor) -> SCNNode {
        let esfera = SCNSphere(radius: radio)
        esfera.firstMaterial?.diffuse.contents = color
        esfera.firstMaterial?.lightingModel = .constant
        let nodo = SCNNode(geometry: esfera)
        nodo.renderingOrder = 10
        return nodo
    }

    private static func linea(de a: SIMD3<Float>, a b: SIMD3<Float>, color: UIColor) -> SCNNode {
        let nodo = SCNNode()
        colocar(nodo, de: a, a: b, color: color)
        return nodo
    }

    /// Turns `nodo` into a thin cylinder going from `a` to `b`.
    private static func colocar(_ nodo: SCNNode, de a: SIMD3<Float>, a b: SIMD3<Float>, color: UIColor) {
        let largo = CGFloat(simd_distance(a, b))
        let cilindro = (nodo.geometry as? SCNCylinder) ?? {
            let c = SCNCylinder(radius: 0.002, height: largo)
            c.firstMaterial?.diffuse.contents = color
            c.firstMaterial?.lightingModel = .constant
            nodo.geometry = c
            return c
        }()
        cilindro.height = largo
        nodo.simdPosition = (a + b) / 2
        guard largo > 0 else { return }
        let direccion = simd_normalize(b - a)
        let arriba: SIMD3<Float> = abs(direccion.y) > 0.99 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        nodo.simdLook(at: b, up: arriba, localFront: SIMD3(0, 1, 0))
    }

    private static func etiqueta(_ texto: String, en posicion: SIMD3<Float>) -> SCNNode {
        let geometria = SCNText(string: texto, extrusionDepth: 0)
        geometria.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        geometria.flatness = 0.1
        geometria.firstMaterial?.diffuse.contents = UIColor.white
        geometria.firstMaterial?.lightingModel = .constant
        geometria.firstMaterial?.readsFromDepthBuffer = false
        let texto = SCNNode(geometry: geometria)
        let (minimo, maximo) = texto.boundingBox
        texto.pivot = SCNMatrix4MakeTranslation((maximo.x + minimo.x) / 2, (maximo.y + minimo.y) / 2, 0)

        let fondo = SCNPlane(width: CGFloat(maximo.x - minimo.x) + 8, height: CGFloat(maximo.y - minimo.y) + 6)
        fondo.cornerRadius = 4
        fondo.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
        fondo.firstMaterial?.lightingModel = .constant
        fondo.firstMaterial?.readsFromDepthBuffer = false
        let placa = SCNNode(geometry: fondo)
        placa.position.z = -0.1

        let contenedor = SCNNode()
        contenedor.addChildNode(placa)
        contenedor.addChildNode(texto)
        contenedor.scale = SCNVector3(0.003, 0.003, 0.003)
        contenedor.simdPosition = posicion + SIMD3(0, 0.02, 0)
        contenedor.constraints = [SCNBillboardConstraint()]
        contenedor.renderingOrder = 20
        texto.renderingOrder = 21
        placa.renderingOrder = 20
        return contenedor
    }
}
