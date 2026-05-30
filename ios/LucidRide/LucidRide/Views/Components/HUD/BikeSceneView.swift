import SwiftUI
import SceneKit
import GLTFKit2

/// Quiet studio bike scene — static framing, HDR-driven lighting, no floor.
///
/// Rebuilt 2026-05-30 after Fabi: "as soon as I open it it just looks shit ...
/// the lighting is completely off ... stop moving it from left to right ...
/// the reflection at the bottom is just too detailed." The previous version
/// had auto-rotate + cinematic 3-point + bloom/vignette + a reflective floor
/// all fighting each other. New approach is minimal:
///
/// 1. Static 3/4 hero angle. No auto-rotate, ever. User can still pan/pinch
///    to inspect parts; gestures never trigger any return-to-spin motion.
/// 2. HDR does almost all the shading (Polyhaven Studio Small 04 CC0 at 1.3).
///    One soft key directional gives the bike a definite shadow direction;
///    low ambient lifts the blacks. No fill, no rim, no bloom, no vignette.
/// 3. No SCNFloor. The SwiftUI gradient behind the scene sweeps through
///    cleanly — the bike no longer sits on a second copy of itself.
///
/// Pipeline:
/// - Load bike.glb via GLTFKit2 (PBR materials come through automatically).
/// - Position-cluster the anonymous meshes into 6 BikePart regions for
///   tap-to-data hit testing.
/// - Camera: static orbit rig. Pan rotates it; pinch scales camNode.z to zoom.
/// - Every render frame: project each named bike-part node's world position
///   to 2-D screen space and surface it via `onPartScreenPositions` so the
///   ContentView overlay can draw tappable icons / arrows that follow the
///   bike when the user manually orbits it.
struct BikeSceneView: UIViewRepresentable {
    let leanDegrees: Double
    let pulseBPM: Double?
    let accentColor: Color   // Kept in the API; not currently used by the scene.
    var onPartTap: ((BikePart) -> Void)?
    var onPartScreenPositions: (([BikePart: CGPoint]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPartTap: onPartTap, onPositions: onPartScreenPositions)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene(coordinator: context.coordinator)
        view.backgroundColor = .clear           // let SwiftUI bg show through
        view.isOpaque = false
        view.allowsCameraControl = false        // we drive the orbit ourselves
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.autoenablesDefaultLighting = false

        context.coordinator.scnView = view
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onPartTap = onPartTap
        context.coordinator.onPositions = onPartScreenPositions
        guard let bike = view.scene?.rootNode.childNode(withName: "bike", recursively: false) else { return }
        let radians = -leanDegrees * .pi / 180
        let lean = SCNAction.rotateTo(
            x: 0, y: 0, z: CGFloat(radians), duration: 0.18, usesShortestUnitArc: true
        )
        lean.timingMode = .easeOut
        bike.runAction(lean, forKey: "lean")
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var onPartTap: ((BikePart) -> Void)?
        var onPositions: (([BikePart: CGPoint]) -> Void)?
        weak var scnView: SCNView?
        weak var orbitRig: SCNNode?
        weak var camNode: SCNNode?

        // Initial framing distance — captured once at scene build so zoom is
        // a multiplier on it, not a raw absolute world distance.
        var baseCamDist: Float = 4.0

        // Throttle projection callback to ~30 Hz to keep SwiftUI re-renders cheap.
        private var lastProjectionTime: TimeInterval = 0
        private let projectionInterval: TimeInterval = 1.0 / 30.0

        init(onPartTap: ((BikePart) -> Void)?,
             onPositions: (([BikePart: CGPoint]) -> Void)?) {
            self.onPartTap = onPartTap
            self.onPositions = onPositions
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)
            let hits = view.hitTest(location, options: [
                SCNHitTestOption.boundingBoxOnly: false,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                SCNHitTestOption.ignoreHiddenNodes: true
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

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = scnView, let rig = orbitRig else { return }
            switch gesture.state {
            case .changed:
                let t = gesture.translation(in: view)
                // Horizontal drag → Y rotation; vertical drag → X tilt (clamped).
                let rotY = Float(t.x) * 0.005
                let rotX = Float(t.y) * 0.003
                var e = rig.eulerAngles
                e.y += rotY
                e.x = clamp(e.x + rotX, min: -0.6, max: 0.05)
                rig.eulerAngles = e
                gesture.setTranslation(.zero, in: view)
            default: break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let cam = camNode else { return }
            switch gesture.state {
            case .changed:
                let factor = Float(1.0 / gesture.scale)
                let newZ = clamp(cam.position.z * factor,
                                 min: baseCamDist * 0.45,
                                 max: baseCamDist * 2.4)
                cam.position.z = newZ
                gesture.scale = 1.0
            default: break
            }
        }

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
            let up   = SCNAction.scale(by: 1.10, duration: 0.10)
            let down = SCNAction.scale(by: 1.0/1.10, duration: 0.16)
            up.timingMode = .easeOut
            down.timingMode = .easeOut
            node.runAction(SCNAction.sequence([up, down]))
        }

        private func clamp<T: Comparable>(_ v: T, min lo: T, max hi: T) -> T {
            return Swift.max(lo, Swift.min(hi, v))
        }

        // MARK: SCNSceneRendererDelegate

        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard let view = scnView, let cb = onPositions else { return }
            if time - lastProjectionTime < projectionInterval { return }
            lastProjectionTime = time

            var positions: [BikePart: CGPoint] = [:]
            guard let bike = scene.rootNode.childNode(withName: "bike", recursively: false) else { return }

            for part in BikePart.allCases {
                guard let node = bike.childNode(withName: part.nodeName, recursively: true) else { continue }
                let bb = node.boundingBox
                let localCenter = SCNVector3((bb.min.x + bb.max.x) / 2,
                                             (bb.min.y + bb.max.y) / 2,
                                             (bb.min.z + bb.max.z) / 2)
                let world = node.convertPosition(localCenter, to: nil)
                let projected = view.projectPoint(world)
                if projected.z < 0 || projected.z > 1 { continue }
                let pt = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                positions[part] = pt
            }

            DispatchQueue.main.async {
                cb(positions)
            }
        }
    }

    // MARK: - Scene assembly

    private func makeScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nil    // SwiftUI gradient shows through

        // HDR carries almost all the lighting — Polyhaven Studio Small 04 CC0.
        // Bright, neutral, evenly lit; chrome and paint get clean reflections
        // without help from extra directionals.
        if let hdrURL = Bundle.main.url(forResource: "studio_small_04_1k", withExtension: "hdr") {
            scene.lightingEnvironment.contents = hdrURL
        }
        scene.lightingEnvironment.intensity = 1.3

        // Bike
        let bike = loadOrBuildBike()
        scene.rootNode.addChildNode(bike)

        // World bounds for camera framing
        let (lMin, lMax) = bike.boundingBox
        let s = bike.scale.x
        let bp = bike.position
        let worldMin = SCNVector3(lMin.x * s + bp.x, lMin.y * s + bp.y, lMin.z * s + bp.z)
        let worldMax = SCNVector3(lMax.x * s + bp.x, lMax.y * s + bp.y, lMax.z * s + bp.z)
        let bikeCenterY = (worldMin.y + worldMax.y) / 2
        let longestHorizontal = max(worldMax.x - worldMin.x, worldMax.z - worldMin.z)

        // Camera — clean exposure, no bloom, no vignette. Lets the PBR
        // materials look like themselves instead of behind a filter.
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.05
        cam.zFar = 100
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.18
        cam.bloomIntensity = 0.0
        cam.bloomThreshold = 1.0
        cam.bloomBlurRadius = 0.0
        cam.colorFringeIntensity = 0.0
        cam.contrast = 0.08
        cam.saturation = 1.02
        cam.vignettingPower = 0.0
        cam.vignettingIntensity = 0.0
        let camDist = longestHorizontal * 1.5
        cam.focalDistance = CGFloat(camDist)
        cam.focalBlurRadius = 0.0
        cam.focalLength = 50
        cam.fStop = 6.0
        coordinator.baseCamDist = camDist

        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, camDist)
        coordinator.camNode = camNode

        let orbitRig = SCNNode()
        orbitRig.name = "orbitRig"
        orbitRig.position = SCNVector3(0, bikeCenterY, 0)
        orbitRig.eulerAngles = SCNVector3(-0.16, 0.55, 0)  // static 3/4 hero, no motion
        orbitRig.addChildNode(camNode)
        scene.rootNode.addChildNode(orbitRig)
        coordinator.orbitRig = orbitRig

        // No auto-rotate. Bike sits still until the user grabs it.

        // === Soft single key + low ambient ===
        // HDR does the bulk of the shading; this just gives the bike a
        // definite shadow direction so it sits on the page properly. Killed
        // the 3-point + rim + bloom that made the old version look weird.

        let key = SCNLight()
        key.type = .directional
        key.intensity = 450
        key.color = UIColor(white: 1.0, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 24
        key.shadowRadius = 14
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0.0, alpha: 0.38)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.65, 0.45, 0)
        scene.rootNode.addChildNode(keyNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 90
        amb.color = UIColor(white: 0.62, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // No SCNFloor. The previous reflective floor was too detailed and
        // made the entire bottom of the screen feel busy / wrong. The
        // SwiftUI background gradient now shows through cleanly behind the
        // bike instead.

        return scene
    }

    // MARK: - Bike loader

    private func loadOrBuildBike() -> SCNNode {
        if let bike = loadGLB() { return bike }
        return primitiveBike()
    }

    private func loadGLB() -> SCNNode? {
        guard let url = Bundle.main.url(forResource: "bike", withExtension: "glb") else { return nil }
        guard let asset = try? GLTFAsset(url: url) else { return nil }
        let source = GLTFSCNSceneSource(asset: asset)
        guard let imported = source.defaultScene else { return nil }

        let bike = SCNNode()
        bike.name = "bike"

        for child in Array(imported.rootNode.childNodes) {
            child.removeFromParentNode()
            bike.addChildNode(child)
        }

        let (minP, maxP) = bike.boundingBox
        let size = SCNVector3(maxP.x - minP.x, maxP.y - minP.y, maxP.z - minP.z)
        let longest = max(max(abs(size.x), abs(size.y)), abs(size.z))
        guard longest > 0.001 else { return bike }
        let scale: Float = 4.0 / longest
        bike.scale = SCNVector3(scale, scale, scale)
        let centerX = (minP.x + maxP.x) / 2
        let centerZ = (minP.z + maxP.z) / 2
        bike.position = SCNVector3(-centerX * scale, -minP.y * scale, -centerZ * scale)

        clusterAndNamePartNodes(bike)
        promoteMaterialsToPBR(bike)

        return bike
    }

    private func clusterAndNamePartNodes(_ bike: SCNNode) {
        struct MeshInfo {
            let node: SCNNode
            let center: SCNVector3
            let volume: Float
        }

        var meshes: [MeshInfo] = []
        bike.enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }
            let bb = node.boundingBox
            let local = SCNVector3((bb.min.x + bb.max.x) / 2,
                                   (bb.min.y + bb.max.y) / 2,
                                   (bb.min.z + bb.max.z) / 2)
            let world = node.convertPosition(local, to: bike)
            let sz = SCNVector3(abs(bb.max.x - bb.min.x), abs(bb.max.y - bb.min.y), abs(bb.max.z - bb.min.z))
            meshes.append(MeshInfo(node: node, center: world, volume: sz.x * sz.y * sz.z))
        }
        guard meshes.count >= 4 else { return }

        let xs = meshes.map { $0.center.x }
        let ys = meshes.map { $0.center.y }
        let zs = meshes.map { $0.center.z }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let xSpan = maxX - minX
        let ySpan = maxY - minY
        let zSpan = maxZ - minZ
        guard ySpan > 0.001 else { return }

        let frontAxisIsZ = zSpan > xSpan
        let frontSpan = max(frontAxisIsZ ? zSpan : xSpan, 0.001)
        let frontMin = frontAxisIsZ ? minZ : minX
        func frontPct(_ p: SCNVector3) -> Float {
            let v = frontAxisIsZ ? p.z : p.x
            return (v - frontMin) / frontSpan
        }
        func upPct(_ p: SCNVector3) -> Float { (p.y - minY) / ySpan }

        var frontTopMeshes: [MeshInfo] = []
        for m in meshes {
            let f = frontPct(m.center)
            let u = upPct(m.center)
            let part: BikePart
            if u < 0.35 {
                part = f > 0.5 ? .frontWheel : .rearWheel
            } else if f > 0.70 {
                frontTopMeshes.append(m)
                part = .frontFairing
            } else if f < 0.30 {
                part = .tailFairing
            } else {
                part = .tank
            }
            m.node.name = part.nodeName
        }

        if let smallest = frontTopMeshes.min(by: { $0.volume < $1.volume }) {
            smallest.node.name = BikePart.headlight.nodeName
        }
    }

    private func promoteMaterialsToPBR(_ bike: SCNNode) {
        bike.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            let isHeadlight = (node.name == BikePart.headlight.nodeName)
            for mat in geom.materials {
                mat.lightingModel = .physicallyBased
                if isHeadlight {
                    mat.emission.contents = UIColor(white: 0.92, alpha: 1)
                }
            }
        }
    }

    // MARK: - Procedural fallback

    private func primitiveBike() -> SCNNode {
        let bike = SCNNode()
        bike.name = "bike"

        let body = pbr(UIColor(white: 0.05, alpha: 1), metal: 0.6, rough: 0.4)
        let head = pbr(UIColor.white, metal: 0.0, rough: 0.15, emission: 0.95)

        let fairing = SCNBox(width: 1.10, height: 1.20, length: 0.95, chamferRadius: 0.45)
        fairing.firstMaterial = body
        let fairingN = SCNNode(geometry: fairing)
        fairingN.name = BikePart.frontFairing.nodeName
        fairingN.position = SCNVector3(-1.20, 1.05, 0)
        fairingN.eulerAngles = SCNVector3(0, 0, -0.16)
        bike.addChildNode(fairingN)

        let tank = SCNBox(width: 1.05, height: 0.55, length: 0.85, chamferRadius: 0.28)
        tank.firstMaterial = body
        let tankN = SCNNode(geometry: tank)
        tankN.name = BikePart.tank.nodeName
        tankN.position = SCNVector3(-0.10, 1.22, 0)
        bike.addChildNode(tankN)

        let tail = SCNBox(width: 0.95, height: 0.22, length: 0.55, chamferRadius: 0.14)
        tail.firstMaterial = body
        let tailN = SCNNode(geometry: tail)
        tailN.name = BikePart.tailFairing.nodeName
        tailN.position = SCNVector3(0.95, 1.15, 0)
        bike.addChildNode(tailN)

        for (part, x) in [(BikePart.frontWheel, -1.65), (BikePart.rearWheel, 1.65)] {
            let tire = SCNTorus(ringRadius: 0.62, pipeRadius: 0.18)
            tire.firstMaterial = body
            tire.ringSegmentCount = 48
            tire.pipeSegmentCount = 24
            let n = SCNNode(geometry: tire)
            n.name = part.nodeName
            n.position = SCNVector3(x, 0.60, 0)
            n.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            bike.addChildNode(n)
        }

        let headlight = SCNCylinder(radius: 0.20, height: 0.10)
        headlight.firstMaterial = head
        let headN = SCNNode(geometry: headlight)
        headN.name = BikePart.headlight.nodeName
        headN.position = SCNVector3(-1.66, 1.22, 0)
        headN.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        bike.addChildNode(headN)

        return bike
    }

    private func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat, emission: CGFloat = 0) -> SCNMaterial {
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
