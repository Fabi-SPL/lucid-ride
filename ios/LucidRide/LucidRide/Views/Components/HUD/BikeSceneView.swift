import SwiftUI
import SceneKit
import GLTFKit2

/// 3D sport-bike rendered with SceneKit. Tries to load `bike.glb` (a real
/// sport-bike model, CC-BY 3.0 / Paul Spooner — see Resources/bike-license.txt)
/// via GLTFKit2. If bundle or import fails for any reason, falls back to a
/// procedural primitives bike so the HUD never goes empty.
///
/// Either model path → tap-to-data still works: after loading the GLB, every
/// mesh node is position-clustered into one of six BikePart regions
/// (headlight, frontFairing, tank, tailFairing, frontWheel, rearWheel) and
/// renamed so the hit-test walks up the graph and resolves a BikePart
/// regardless of the model author's naming.
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
        /// after a BikePart (USDZ/GLB models often have nested geometry — this
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

    /// Try `bike.glb` from the bundle first (via GLTFKit2); fall back to
    /// procedural primitives if the file isn't present or import fails.
    private func loadOrBuildBike() -> SCNNode {
        if let bike = loadGLBBike() {
            return bike
        }
        return primitiveBike()
    }

    /// Load `bike.glb` from the bundle via GLTFKit2, normalize scale, recolor
    /// to Lucid aesthetic, and position-cluster meshes into BikeParts so
    /// the named-node hit testing in the Coordinator works.
    private func loadGLBBike() -> SCNNode? {
        guard let url = Bundle.main.url(forResource: "bike", withExtension: "glb") else { return nil }
        guard let asset = try? GLTFAsset(url: url) else { return nil }
        let source = GLTFSCNSceneSource(asset: asset)
        guard let importedScene = source.defaultScene else { return nil }

        let bike = SCNNode()
        bike.name = "bike"

        // Move all top-level children of the imported scene into our bike node.
        let kids = Array(importedScene.rootNode.childNodes)
        for child in kids {
            child.removeFromParentNode()
            bike.addChildNode(child)
        }

        // Normalize size: scale longest dimension to ~4.0 units so the camera
        // setup (designed around the primitive bike at ~3.5 units long) frames
        // it correctly. Also center on origin.
        normalizeTransform(bike)

        // Assign BikePart names by position cluster so hit-testing resolves.
        clusterAndNamePartNodes(bike)

        // Recolor to Lucid aesthetic.
        applyLucidColors(bike)

        // Wrap children inside yWrapper so the idle spin doesn't fight the
        // lean rotation applied directly to `bike`.
        let yWrapper = SCNNode()
        yWrapper.name = "yWrapper"
        let bikeKids = Array(bike.childNodes)
        for k in bikeKids {
            k.removeFromParentNode()
            yWrapper.addChildNode(k)
        }
        bike.addChildNode(yWrapper)
        yWrapper.runAction(idleSpin())

        return bike
    }

    /// Compute the bike's bounding box, then translate + scale so it's
    /// centered on the origin and ~4 units in longest dimension.
    private func normalizeTransform(_ bike: SCNNode) {
        let (minP, maxP) = bike.boundingBox
        let size = SCNVector3(maxP.x - minP.x, maxP.y - minP.y, maxP.z - minP.z)
        let longest = max(max(abs(size.x), abs(size.y)), abs(size.z))
        guard longest > 0.001 else { return }
        let targetLongest: Float = 4.0
        let scale = targetLongest / longest
        bike.scale = SCNVector3(scale, scale, scale)
        // Recenter on origin (after scaling)
        let centerLocal = SCNVector3((minP.x + maxP.x) / 2, (minP.y + maxP.y) / 2, (minP.z + maxP.z) / 2)
        bike.position = SCNVector3(-centerLocal.x * scale, -centerLocal.y * scale, -centerLocal.z * scale)
    }

    /// Find all mesh-bearing nodes, compute their center in bike-local space,
    /// then map each onto one of six BikePart regions and assign that part's
    /// nodeName. Robust to model author's original naming.
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
            // Express the mesh's center in the bike-root coord system so
            // multi-level transforms are accounted for.
            let world = node.convertPosition(local, to: bike)
            let size = SCNVector3(abs(bb.max.x - bb.min.x), abs(bb.max.y - bb.min.y), abs(bb.max.z - bb.min.z))
            let volume = size.x * size.y * size.z
            meshes.append(MeshInfo(node: node, center: world, volume: volume))
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

        // Detect which horizontal axis is the front-rear (the longer one).
        // For SV650 import: Z is the long axis (front +Z, rear -Z).
        let frontAxisIsZ = zSpan > xSpan
        let frontSpan = max(frontAxisIsZ ? zSpan : xSpan, 0.001)
        let frontMin = frontAxisIsZ ? minZ : minX

        func frontPct(_ p: SCNVector3) -> Float {
            let v = frontAxisIsZ ? p.z : p.x
            return (v - frontMin) / frontSpan
        }
        func upPct(_ p: SCNVector3) -> Float {
            return (p.y - minY) / ySpan
        }

        // First pass: assign regions
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

        // Second pass: within the front-top region, the smallest mesh is the
        // headlight (best-effort heuristic — works for sport-bikes where the
        // headlight panel is a small detail on top of the fairing).
        if let smallest = frontTopMeshes.min(by: { $0.volume < $1.volume }) {
            smallest.node.name = BikePart.headlight.nodeName
        }
    }

    /// Override material colors to match the Lucid dark + cyan aesthetic.
    private func applyLucidColors(_ bike: SCNNode) {
        let bodyColor = UIColor(red: 0.07, green: 0.06, blue: 0.10, alpha: 1)
        let accentColor = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)

        bike.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            for mat in geom.materials {
                mat.lightingModel = .physicallyBased
                if node.name == BikePart.headlight.nodeName {
                    mat.diffuse.contents = accentColor
                    mat.emission.contents = accentColor.withAlphaComponent(0.85)
                    mat.metalness.contents = 0.4
                    mat.roughness.contents = 0.05
                } else {
                    mat.diffuse.contents = bodyColor
                    mat.metalness.contents = 0.85
                    mat.roughness.contents = 0.28
                    mat.emission.contents = UIColor.black
                }
            }
        }
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
            n.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            bike.addChildNode(n)
        }

        let headlight = SCNCylinder(radius: 0.20, height: 0.10)
        headlight.firstMaterial = accent
        let headN = SCNNode(geometry: headlight)
        headN.name = BikePart.headlight.nodeName
        headN.position = SCNVector3(-1.66, 0.62, 0)
        headN.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
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
        haloN.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        bike.addChildNode(haloN)

        // Idle Y rotation so the bike feels alive at rest
        let yWrapper = SCNNode()
        yWrapper.name = "yWrapper"
        let kids = Array(bike.childNodes)
        for k in kids {
            k.removeFromParentNode()
            yWrapper.addChildNode(k)
        }
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
