import SwiftUI
import SceneKit
import GLTFKit2

/// Premium product-showcase scene for the bike.
///
/// Renders the bundled GLB through GLTFKit2 with the model's original PBR
/// textures intact (do NOT strip them — Fabi's directive 2026-05-11). Quality
/// comes from three production techniques:
///
/// 1. HDR image-based lighting (`scene.lightingEnvironment` = Polyhaven Studio
///    Small 04, CC0). PBR materials NEED a real environment image for indirect
///    specular — flat UIColor environments make metallic surfaces look like
///    dead plastic.
/// 2. Original normal maps are preserved (do NOT set `mat.normal.contents = nil`).
///    Stripping normals on a low-poly model creates visible faceting on every
///    curved fairing and wheel arch.
/// 3. HDR camera with measured bloom + vignette + DOF that won't fight the IBL.
///
/// Background stays pure black so the bike pops against the HUD chrome. The
/// HDR is used only as `lightingEnvironment`, not as `background.contents`.
///
/// Pipeline:
/// - Load bike.glb via GLTFKit2 (PBR materials come through automatically).
/// - Position-cluster the 16 anonymous meshes into 6 BikePart regions for
///   tap-to-data hit testing.
/// - Light: HDR IBL + a soft key fill + dim ambient. The HDR carries most of
///   the work — directional lights only add edge definition.
/// - Camera: orbit rig revolves slowly around the bike's vertical centre.
struct BikeSceneView: UIViewRepresentable {
    let leanDegrees: Double
    let pulseBPM: Double?
    let accentColor: Color   // Kept in the API; not currently used by the scene.
    var onPartTap: ((BikePart) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onPartTap: onPartTap) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene(coordinator: context.coordinator)
        view.backgroundColor = .black
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.autoenablesDefaultLighting = false

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
    }

    // MARK: - Coordinator

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
    }

    // MARK: - Scene assembly

    private func makeScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        // Real HDR IBL — the biggest single quality lever. Without an actual
        // environment image, PBR metallics show no indirect specular and look
        // like dead plastic. Polyhaven Studio Small 04 is CC0 (see
        // Resources/studio_hdr-license.txt). Bundle-loaded as a raw URL because
        // UIImage(named:) can't open .hdr — SceneKit accepts URL contents.
        if let hdrURL = Bundle.main.url(forResource: "studio_small_04_1k", withExtension: "hdr") {
            scene.lightingEnvironment.contents = hdrURL
        }
        scene.lightingEnvironment.intensity = 1.6

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
        let bikeBottomY = worldMin.y
        let longestHorizontal = max(worldMax.x - worldMin.x, worldMax.z - worldMin.z)

        // Camera + orbit rig
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.05
        cam.zFar = 100
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.4
        cam.bloomIntensity = 0.85
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 6.0
        cam.colorFringeIntensity = 0.0
        cam.contrast = 0.20
        cam.saturation = 1.0                   // Keep original colours intact.
        cam.vignettingPower = 0.55
        cam.vignettingIntensity = 0.45
        // DOF focused on the bike centre so the floor reflection softens
        // without smearing the bike itself.
        let camDist = longestHorizontal * 1.85
        cam.focalDistance = CGFloat(camDist)
        cam.focalBlurRadius = 2.5
        cam.focalLength = 50
        cam.fStop = 6.0

        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, camDist)

        let orbitRig = SCNNode()
        orbitRig.name = "orbitRig"
        orbitRig.position = SCNVector3(0, bikeCenterY, 0)
        orbitRig.eulerAngles = SCNVector3(-0.24, 0.55, 0)   // slightly more elevated pitch
        orbitRig.addChildNode(camNode)
        scene.rootNode.addChildNode(orbitRig)
        orbitRig.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: 0.18, z: 0, duration: 6)
        ))

        // Lighting — IBL does most of the work, directional lights only sharpen
        // edges and cast a shadow. Lower intensities than pre-IBL setup.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor.white
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 32
        key.shadowRadius = 8
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0.0, alpha: 0.8)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.65, 0.45, 0)
        scene.rootNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 700
        rim.color = UIColor.white
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.55, -2.75, 0)
        scene.rootNode.addChildNode(rimNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 40
        amb.color = UIColor(white: 0.6, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Shadow-catching floor. Slight reflectivity gives the bike a sense of
        // being on a surface without competing for visual attention.
        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.reflectionFalloffEnd = 1.6
        floor.reflectionResolutionScaleFactor = 0.5
        let fmat = SCNMaterial()
        fmat.lightingModel = .physicallyBased
        fmat.diffuse.contents = UIColor.black
        fmat.metalness.contents = 0.0
        fmat.roughness.contents = 0.6
        floor.firstMaterial = fmat
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, bikeBottomY - 0.001, 0)
        scene.rootNode.addChildNode(floorNode)

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

        // Auto-fit: longest dim → 4 units, X/Z centred, bottom on Y=0
        let (minP, maxP) = bike.boundingBox
        let size = SCNVector3(maxP.x - minP.x, maxP.y - minP.y, maxP.z - minP.z)
        let longest = max(max(abs(size.x), abs(size.y)), abs(size.z))
        guard longest > 0.001 else { return bike }
        let scale: Float = 4.0 / longest
        bike.scale = SCNVector3(scale, scale, scale)
        let centerX = (minP.x + maxP.x) / 2
        let centerZ = (minP.z + maxP.z) / 2
        bike.position = SCNVector3(-centerX * scale, -minP.y * scale, -centerZ * scale)

        // Map meshes into BikePart regions for tap-to-data hit testing.
        clusterAndNamePartNodes(bike)

        // Promote materials to PBR (some GLB importers default to Phong) and
        // boost headlight emission so it reads as the "powered on" element.
        // CRITICAL: do NOT touch diffuse / normal / metalness / roughness —
        // those come from the GLB and stripping them is what made the bike
        // look like a CAD render. Fabi 2026-05-11: "stop stripping it."
        promoteMaterialsToPBR(bike)

        return bike
    }

    /// Cluster the GLB's anonymous mesh nodes into BikePart regions by
    /// position. Works for any model where the source author didn't name
    /// nodes "headlight" / "tank" / etc.
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

        // Smallest mesh in the front-top region is best-effort headlight.
        if let smallest = frontTopMeshes.min(by: { $0.volume < $1.volume }) {
            smallest.node.name = BikePart.headlight.nodeName
        }
    }

    /// Promote each material to PBR (some GLTF importers default to Phong)
    /// and boost the headlight cluster's emission so it reads as "lit".
    ///
    /// Does NOT modify diffuse, normal, metalness, roughness, or AO —
    /// those come from the GLB textures and stripping them removes the
    /// surface detail that distinguishes a textured render from a CAD model.
    private func promoteMaterialsToPBR(_ bike: SCNNode) {
        bike.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            let isHeadlight = (node.name == BikePart.headlight.nodeName)
            for mat in geom.materials {
                mat.lightingModel = .physicallyBased
                if isHeadlight {
                    // Let the headlight glow — overrides whatever emission the
                    // GLB shipped with (which is typically none for a lamp lens).
                    mat.emission.contents = UIColor(white: 0.92, alpha: 1)
                }
            }
        }
    }

    // MARK: - Procedural fallback (kept simple — used only if GLB missing)

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
