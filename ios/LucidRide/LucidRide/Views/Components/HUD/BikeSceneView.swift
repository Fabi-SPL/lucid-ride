import SwiftUI
import SceneKit

/// Minimalist 3D sport-bike rendered with SceneKit primitives.
/// Aesthetic target: matches the Lucid Ride logo — gloss-black silhouette
/// with a single cyan accent on the headlight. Front-3/4 camera angle for
/// premium product-render vibe.
///
/// Geometry deliberately simple: one dark material across the entire body,
/// no chrome detailing, no exhaust/seat clutter. Lean rotation on Z axis.
/// Idle Y-rotation makes it feel alive when stationary.
///
/// Each part is named (tank, tailFairing, frontWheel, rearWheel, frontFairing,
/// headlight) so a future iteration can wire SceneKit hit-testing to make the
/// bike itself a tappable spec-menu (Fabi's idea — phase 2).
struct BikeSceneView: UIViewRepresentable {
    let leanDegrees: Double
    let pulseBPM: Double?
    let accentColor: Color

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let bike = view.scene?.rootNode.childNode(withName: "bike", recursively: false) else { return }
        let radians = -leanDegrees * .pi / 180
        let lean = SCNAction.rotateTo(
            x: 0, y: 0, z: CGFloat(radians), duration: 0.18, usesShortestUnitArc: true
        )
        lean.timingMode = .easeOut
        bike.runAction(lean, forKey: "lean")

        // Live accent color — drives the headlight emission so HR zone tints the bike
        let uiAccent = UIColor(accentColor)
        if let head = view.scene?.rootNode.childNode(withName: "headlight", recursively: true),
           let mat = head.geometry?.firstMaterial {
            mat.diffuse.contents = uiAccent
            mat.emission.contents = uiAccent.withAlphaComponent(0.85)
        }
    }

    // MARK: - Scene

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // Camera — front-3/4 view, slightly elevated, looking back at origin.
        // Positioned so the fairing is visible head-on with depth on the right
        // side (where the rear of the bike fades into shadow).
        let cam = SCNCamera()
        cam.fieldOfView = 32
        cam.zNear = 0.1
        cam.zFar = 100
        cam.wantsHDR = true
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(-4.6, 1.8, 4.6)
        camNode.eulerAngles = SCNVector3(-0.18, -0.78, 0)   // ~-45° yaw, slight downward pitch
        scene.rootNode.addChildNode(camNode)

        // Lighting — three-point, dramatic.
        // Key from upper-front-right: defines the silhouette
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.color = UIColor(white: 1, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.7, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        // Ambient — low, slightly violet so dark surfaces aren't black holes
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 220
        amb.color = UIColor(red: 0.50, green: 0.46, blue: 0.78, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Rim from behind-left: cyan accent that wraps the silhouette,
        // matching the headlight color so the brand reads through
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 800
        rim.color = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.4, -2.7, 0)
        scene.rootNode.addChildNode(rimNode)

        scene.rootNode.addChildNode(bikeNode())
        return scene
    }

    private func bikeNode() -> SCNNode {
        let bike = SCNNode()
        bike.name = "bike"

        // Single body material — gloss near-black with subtle violet tint.
        // Slight metalness lets the rim light wrap the silhouette.
        let body = uiMaterial(
            color: UIColor(red: 0.07, green: 0.06, blue: 0.10, alpha: 1),
            metal: 0.85, rough: 0.28
        )
        // Cyan accent for the headlight — strong emission for the singular focal point
        let accent = uiMaterial(
            color: UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1),
            metal: 0.4, rough: 0.05, emission: 0.85
        )

        // --- Front fairing (the headlamp shroud) ---
        // Tall stretched box with high chamfer = aggressive sport-bike fairing
        let fairing = SCNBox(width: 1.10, height: 1.20, length: 0.95, chamferRadius: 0.45)
        fairing.firstMaterial = body
        let fairingN = SCNNode(geometry: fairing)
        fairingN.name = "frontFairing"
        fairingN.position = SCNVector3(-1.20, 0.45, 0)
        fairingN.eulerAngles = SCNVector3(0, 0, -0.16)
        bike.addChildNode(fairingN)

        // --- Tank ---
        // Wide chamfered box — the 'shoulders' of the bike
        let tank = SCNBox(width: 1.05, height: 0.55, length: 0.85, chamferRadius: 0.28)
        tank.firstMaterial = body
        let tankN = SCNNode(geometry: tank)
        tankN.name = "tank"
        tankN.position = SCNVector3(-0.10, 0.62, 0)
        bike.addChildNode(tankN)

        // --- Tail / seat fairing ---
        // Tapered slim rear — completes the silhouette
        let tail = SCNBox(width: 0.95, height: 0.22, length: 0.55, chamferRadius: 0.14)
        tail.firstMaterial = body
        let tailN = SCNNode(geometry: tail)
        tailN.name = "tailFairing"
        tailN.position = SCNVector3(0.95, 0.55, 0)
        bike.addChildNode(tailN)

        // --- Wheels ---
        // Smooth tori, single body material — minimal but readable
        for (name, x) in [("frontWheel", -1.65), ("rearWheel", 1.65)] {
            let tire = SCNTorus(ringRadius: 0.62, pipeRadius: 0.18)
            tire.firstMaterial = body
            tire.ringSegmentCount = 48
            tire.pipeSegmentCount = 24
            let n = SCNNode(geometry: tire)
            n.name = name
            n.position = SCNVector3(x, -0.20, 0)
            n.eulerAngles = SCNVector3(0, 0, .pi / 2)
            bike.addChildNode(n)
        }

        // --- Headlight (the cyan accent — match the logo's lit eye) ---
        let headlight = SCNCylinder(radius: 0.20, height: 0.10)
        headlight.firstMaterial = accent
        let headN = SCNNode(geometry: headlight)
        headN.name = "headlight"
        headN.position = SCNVector3(-1.66, 0.62, 0)
        headN.eulerAngles = SCNVector3(0, 0, .pi / 2)
        bike.addChildNode(headN)

        // Subtle halo / glow disk behind the headlight for premium "lit" feel
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

        // Idle Y rotation so the bike feels alive at rest. Wrapper child node
        // so lean (Z) and idle (Y) don't fight on the same transform.
        let yWrapper = SCNNode()
        yWrapper.name = "yWrapper"
        bike.childNodes.forEach { yWrapper.addChildNode($0) }
        bike.childNodes.forEach { $0.removeFromParentNode() }
        bike.addChildNode(yWrapper)
        let idle = SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.10, z: 0, duration: 6),
                SCNAction.rotateBy(x: 0, y: -0.20, z: 0, duration: 12),
                SCNAction.rotateBy(x: 0, y: 0.10, z: 0, duration: 6)
            ])
        )
        yWrapper.runAction(idle)

        return bike
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
