import SwiftUI
import SceneKit

/// Minimalist 3D sport-bike rendered with SceneKit. Single dark body, single
/// cyan accent on the headlight (matches the Lucid Ride logo aesthetic).
///
/// Tries to load `bike.usdz` from the app bundle for higher-quality geometry.
/// If the model isn't bundled, falls back to a procedural primitives bike.
/// Either way, key parts are exposed under stable node names so Phase 2
/// hit-testing works regardless of the model source.
///
/// Phase 2: tap any named part → onPartTap fires with the BikePart, the
/// hit node pulses, and the parent view shows a BikePartSheet.
struct BikeSceneView: UIViewRepresentable {
    let leanDegrees: Double
    let pulseBPM: Double?
    let accentColor: Color
    var onPartTap: ((BikePart) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPartTap: onPartTap)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true

        context.coordinator.scnView = view
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onPartTap = onPartTap
        guard let bike = view.scene?.rootNode.childNode(withName: "bike", recursively: false) else { return }

        let radians = -leanDegrees * .pi / 180
        let lean = SCNAction.rotateTo(
            x: 0, y: 0, z: CGFloat(radians), duration: 0.18, usesShortestUnitArc: true
        )
        lean.timingMode = .easeOut
        bike.runAction(lean, forKey: "lean")

        let uiAccent = UIColor(accentColor)
        if let head = view.scene?.rootNode.childNode(withName: BikePart.headlight.nodeName, recursively: true),
           let mat = head.geometry?.firstMaterial {
            mat.diffuse.contents = uiAccent
            mat.emission.contents = uiAccent.withAlphaComponent(0.85)
        }
    }

    // MARK: - Coordinator (gesture)

    final class Coordinator: NSObject {
        var onPartTap: ((BikePart) -> Void)?
        weak var scnView: SCNView?

        init(onPartTap: ((BikePart) -> Void)?) {
            self.onPartTap = onPartTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)
            let hits = view.hitTest(location, options: [
                SCNHitTestOption.boundingBoxOnly: false,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            for hit in hits {
                if let part = matchPart(node: hit.node) {
                    pulse(node: hit.node)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onPartTap?(part)
                    return
                }
            }
        }

        /// Walks up the scene graph from the hit node looking for a node named
        /// after a BikePart (USDZ models often have nested geometry — this
        /// handles both flat-named nodes and nested hierarchies).
        private func matchPart(node: SCNNode) -> BikePart? {
            var current: SCNNode? = node
            while let n = current {
                if let name = n.name,
                   let part = BikePart.allCases.first(where: { $0.nodeName == name }) {
                    return part
                }
                current = n.parent
            }
            return nil
        }

        private func pulse(node: SCNNode) {
            let up   = SCNAction.scale(by: 1.15, duration: 0.12)
            let down = SCNAction.scale(by: 1.0/1.15, duration: 0.18)
            up.timingMode = .easeOut
            down.timingMode = .easeOut
            node.runAction(SCNAction.sequence([up, down]))
        }
    }

    // MARK: - Scene

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let cam = SCNCamera()
        cam.fieldOfView = 32
        cam.zNear = 0.1
        cam.zFar = 100
        cam.wantsHDR = true
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(-4.6, 1.8, 4.6)
        camNode.eulerAngles = SCNVector3(-0.18, -0.78, 0)
        scene.rootNode.addChildNode(camNode)

        // Three-point lighting for cinematic depth
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.color = UIColor.white
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.7, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 220
        amb.color = UIColor(red: 0.50, green: 0.46, blue: 0.78, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 800
        rim.color = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.4, -2.7, 0)
        scene.rootNode.addChildNode(rimNode)

        scene.rootNode.addChildNode(loadOrBuildBike())
        return scene
    }

    /// Try `bike.usdz` from the bundle first; fall back to procedural primitives
    /// if the file isn't present. This lets us swap in a downloaded high-quality
    /// model later without changing any other code.
    private func loadOrBuildBike() -> SCNNode {
        if let url = Bundle.main.url(forResource: "bike", withExtension: "usdz"),
           let scene = try? SCNScene(url: url, options: nil) {
            let bike = SCNNode()
            bike.name = "bike"
            scene.rootNode.childNodes.forEach { bike.addChildNode($0) }
            // Wrap inside yWrapper for idle rotation without fighting lean
            let yWrapper = SCNNode()
            yWrapper.name = "yWrapper"
            bike.childNodes.forEach { yWrapper.addChildNode($0) }
            bike.childNodes.forEach { $0.removeFromParentNode() }
            bike.addChildNode(yWrapper)
            yWrapper.runAction(idleSpin())
            return bike
        }
        return primitiveBike()
    }

    /// Fallback procedural sport-bike from primitives. Each body part has a
    /// stable name matching BikePart.nodeName so hit-testing works.
    private func primitiveBike() -> SCNNode {
        let bike = SCNNode()
        bike.name = "bike"

        let body = uiMaterial(
            color: UIColor(red: 0.07, green: 0.06, blue: 0.10, alpha: 1),
            metal: 0.85, rough: 0.28
        )
        let accent = uiMaterial(
            color: UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1),
            metal: 0.4, rough: 0.05, emission: 0.85
        )

        let fairing = SCNBox(width: 1.10, height: 1.20, length: 0.95, chamferRadius: 0.45)
        fairing.firstMaterial = body
        let fairingN = SCNNode(geometry: fairing)
        fairingN.name = BikePart.frontFairing.nodeName
        fairingN.position = SCNVector3(-1.20, 0.45, 0)
        fairingN.eulerAngles = SCNVector3(0, 0, -0.16)
        bike.addChildNode(fairingN)

        let tank = SCNBox(width: 1.05, height: 0.55, length: 0.85, chamferRadius: 0.28)
        tank.firstMaterial = body
        let tankN = SCNNode(geometry: tank)
        tankN.name = BikePart.tank.nodeName
        tankN.position = SCNVector3(-0.10, 0.62, 0)
        bike.addChildNode(tankN)

        let tail = SCNBox(width: 0.95, height: 0.22, length: 0.55, chamferRadius: 0.14)
        tail.firstMaterial = body
        let tailN = SCNNode(geometry: tail)
        tailN.name = BikePart.tailFairing.nodeName
        tailN.position = SCNVector3(0.95, 0.55, 0)
        bike.addChildNode(tailN)

        for (part, x) in [(BikePart.frontWheel, -1.65), (BikePart.rearWheel, 1.65)] {
            let tire = SCNTorus(ringRadius: 0.62, pipeRadius: 0.18)
            tire.firstMaterial = body
            tire.ringSegmentCount = 48
            tire.pipeSegmentCount = 24
            let n = SCNNode(geometry: tire)
            n.name = part.nodeName
            n.position = SCNVector3(x, -0.20, 0)
            n.eulerAngles = SCNVector3(0, 0, .pi / 2)
            bike.addChildNode(n)
        }

        let headlight = SCNCylinder(radius: 0.20, height: 0.10)
        headlight.firstMaterial = accent
        let headN = SCNNode(geometry: headlight)
        headN.name = BikePart.headlight.nodeName
        headN.position = SCNVector3(-1.66, 0.62, 0)
        headN.eulerAngles = SCNVector3(0, 0, .pi / 2)
        bike.addChildNode(headN)

        // Halo behind headlight — additive blend for the lit-eye look
        let halo = SCNPlane(width: 0.55, height: 0.55)
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 0.25)
        haloMat.emission.contents = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 0.45)
        haloMat.lightingModel = .constant
        haloMat.isDoubleSided = true
        haloMat.transparent.contents = UIColor(white: 1, alpha: 0.45)
        haloMat.blendMode = .add
        halo.firstMaterial = haloMat
        let haloN = SCNNode(geometry: halo)
        haloN.position = SCNVector3(-1.55, 0.62, 0)
        haloN.eulerAngles = SCNVector3(0, .pi / 2, 0)
        bike.addChildNode(haloN)

        // Idle Y rotation so the bike feels alive at rest
        let yWrapper = SCNNode()
        yWrapper.name = "yWrapper"
        bike.childNodes.forEach { yWrapper.addChildNode($0) }
        bike.childNodes.forEach { $0.removeFromParentNode() }
        bike.addChildNode(yWrapper)
        yWrapper.runAction(idleSpin())

        return bike
    }

    private func idleSpin() -> SCNAction {
        SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.10, z: 0, duration: 6),
                SCNAction.rotateBy(x: 0, y: -0.20, z: 0, duration: 12),
                SCNAction.rotateBy(x: 0, y: 0.10, z: 0, duration: 6)
            ])
        )
    }

    private func uiMaterial(color: UIColor, metal: CGFloat, rough: CGFloat, emission: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if emission > 0 {
            m.emission.contents = color.withAlphaComponent(emission)
        }
        return m
    }
}
