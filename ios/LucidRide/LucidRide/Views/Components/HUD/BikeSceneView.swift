import SwiftUI
import SceneKit
import ModelIO
import GLTFKit2

/// High-quality 3D bike scene.
///
/// Pipeline:
/// - Loads `bike.glb` from the bundle via GLTFKit2 (67k tris PBR model, see
///   Resources/bike-license.txt for origin).
/// - Auto-frames it: scales the longest dimension to 4 units, centers X/Z on
///   origin, places the bottom on Y=0 so a shadow-catching floor works.
/// - Lighting environment from MDLSkyCubeTexture for IBL — gives the PBR
///   materials proper reflections without bundling an HDR file.
/// - Three-point directional lighting (warm key, violet fill, cyan rim).
/// - HDR + bloom + subtle colour fringe on the camera so emissions pop.
/// - Camera orbit rig rotates slowly around the bike centre (the bike itself
///   stays static — only the view moves, which reads more cinematic than a
///   spinning model).
/// - Tap → world-coordinate to BikePart-region mapping (front-30%-top of
///   bounding box = headlight, etc.) so the existing BikePartSheet flow works
///   even though the high-poly model is one fused mesh.
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
        view.scene = makeScene(coordinator: context.coordinator)
        view.backgroundColor = .clear
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

        // Lean (Z roll) animates from the IMU placeholder sine wave
        let radians = -leanDegrees * .pi / 180
        let lean = SCNAction.rotateTo(
            x: 0, y: 0, z: CGFloat(radians), duration: 0.18, usesShortestUnitArc: true
        )
        lean.timingMode = .easeOut
        bike.runAction(lean, forKey: "lean")
    }

    // MARK: - Coordinator (gesture + hit-test)

    final class Coordinator: NSObject {
        var onPartTap: ((BikePart) -> Void)?
        weak var scnView: SCNView?

        // World-space bounds of the bike, computed once after load. Used to
        // map a tap's world position to a BikePart region.
        var worldMin: SCNVector3 = SCNVector3Zero
        var worldMax: SCNVector3 = SCNVector3Zero
        var boundsReady = false

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
            guard let hit = hits.first else { return }
            let world = hit.worldCoordinates
            let part = partForWorldPosition(world)

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            if let bike = view.scene?.rootNode.childNode(withName: "bike", recursively: false) {
                let up   = SCNAction.scale(by: 1.035, duration: 0.10)
                let down = SCNAction.scale(by: 1.0/1.035, duration: 0.16)
                up.timingMode = .easeOut
                down.timingMode = .easeOut
                bike.runAction(SCNAction.sequence([up, down]))
            }

            onPartTap?(part)
        }

        /// Map a world-space hit position onto a BikePart region. Works without
        /// per-part nodes — the bike is a single fused mesh in the high-quality
        /// GLB, so node-name matching doesn't apply. Instead we slice the
        /// bounding box into six regions and pick the closest one.
        private func partForWorldPosition(_ p: SCNVector3) -> BikePart {
            guard boundsReady else { return .headlight }
            let xSpan = worldMax.x - worldMin.x
            let ySpan = max(worldMax.y - worldMin.y, 0.001)
            let zSpan = worldMax.z - worldMin.z

            // Front-rear axis = the longer horizontal axis. For this GLB, Z.
            let frontAxisZ = zSpan > xSpan
            let frontMin = frontAxisZ ? worldMin.z : worldMin.x
            let frontSpan = max(frontAxisZ ? zSpan : xSpan, 0.001)
            let frontVal = frontAxisZ ? p.z : p.x
            let fPct = (frontVal - frontMin) / frontSpan
            let uPct = (p.y - worldMin.y) / ySpan

            // Bottom 35% of bounds → wheels
            if uPct < 0.35 {
                return fPct > 0.5 ? .frontWheel : .rearWheel
            }
            // Front 28% (upper half) → headlight (very top) or front fairing
            if fPct > 0.72 {
                return uPct > 0.72 ? .headlight : .frontFairing
            }
            // Rear 30% → tail fairing
            if fPct < 0.30 {
                return .tailFairing
            }
            // Middle → tank
            return .tank
        }
    }

    // MARK: - Scene assembly

    private func makeScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // ---- Image-based lighting (IBL) via procedural sky -------------------
        // MDLSkyCubeTexture produces a HDR cube map without bundling any image.
        // Tuned warm/violet to match the Lucid aesthetic.
        let sky = MDLSkyCubeTexture(
            name: "lucidSky",
            channelEncoding: .float16,
            textureDimensions: vector_int2(256, 256),
            turbidity: 0.45,
            sunElevation: 0.65,
            upperAtmosphereScattering: 0.32,
            groundAlbedo: 0.4
        )
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = 1.15

        // ---- Bike --------------------------------------------------------------
        let bike = loadOrBuildBike()
        scene.rootNode.addChildNode(bike)

        // Compute the bike's world-space bounding box for the camera framer
        // and the tap-region mapper. After loadGLB the bike has a uniform scale
        // and a position offset that centres X/Z and floors Y at 0.
        let (lMin, lMax) = bike.boundingBox
        let s = bike.scale.x  // uniform
        let bp = bike.position
        coordinator.worldMin = SCNVector3(lMin.x * s + bp.x, lMin.y * s + bp.y, lMin.z * s + bp.z)
        coordinator.worldMax = SCNVector3(lMax.x * s + bp.x, lMax.y * s + bp.y, lMax.z * s + bp.z)
        coordinator.boundsReady = true

        let bikeCenterY = (coordinator.worldMin.y + coordinator.worldMax.y) / 2
        let bikeBottomY = coordinator.worldMin.y
        let xExtent = coordinator.worldMax.x - coordinator.worldMin.x
        let zExtent = coordinator.worldMax.z - coordinator.worldMin.z
        let longestHorizontal = max(xExtent, zExtent)

        // ---- Camera + orbit rig ------------------------------------------------
        let cam = SCNCamera()
        cam.fieldOfView = 28
        cam.zNear = 0.05
        cam.zFar = 100
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 1.6
        cam.bloomThreshold = 0.55
        cam.bloomBlurRadius = 6
        cam.exposureOffset = 0.45
        cam.colorFringeIntensity = 0.15
        cam.contrast = 0.08
        cam.saturation = 1.05

        let camNode = SCNNode()
        camNode.camera = cam
        // Camera sits behind the bike, looking down its local -Z. The orbitRig
        // rotates the camera around the bike's centre.
        let camDist = longestHorizontal * 1.75
        camNode.position = SCNVector3(0, 0, camDist)

        let orbitRig = SCNNode()
        orbitRig.name = "orbitRig"
        orbitRig.position = SCNVector3(0, bikeCenterY, 0)
        // Initial 3/4 angle: slight tilt down, rotated to show the front-left.
        orbitRig.eulerAngles = SCNVector3(-0.18, 0.55, 0)
        orbitRig.addChildNode(camNode)
        scene.rootNode.addChildNode(orbitRig)

        // Slow idle orbit (full rev every ~3.5 minutes)
        orbitRig.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: 0.18, z: 0, duration: 6)
        ))

        // ---- Three-point lighting ---------------------------------------------
        // Key — warm white from front-top-right, shadow caster
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1400
        key.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 32
        key.shadowRadius = 10
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.68, 0.50, 0)
        scene.rootNode.addChildNode(keyNode)

        // Fill — cool violet from left, softens shadows
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 500
        fill.color = UIColor(red: 0.55, green: 0.48, blue: 0.85, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.32, -1.4, 0)
        scene.rootNode.addChildNode(fillNode)

        // Rim — cyan from behind, gives the Lucid edge glow
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 1300
        rim.color = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.55, -2.75, 0)
        scene.rootNode.addChildNode(rimNode)

        // Subtle ambient bounce
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 100
        amb.color = UIColor(red: 0.45, green: 0.42, blue: 0.78, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // ---- Shadow-catching floor --------------------------------------------
        // Dark, low-reflectivity floor under the bike. Catches the key light's
        // shadow so the bike feels grounded rather than floating.
        let floor = SCNFloor()
        floor.reflectivity = 0.08
        floor.reflectionFalloffEnd = 1.4
        floor.reflectionResolutionScaleFactor = 0.4
        let fmat = SCNMaterial()
        fmat.lightingModel = .physicallyBased
        fmat.diffuse.contents = UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        fmat.metalness.contents = 0.0
        fmat.roughness.contents = 0.45
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

    /// Load `bike.glb` via GLTFKit2. Preserves the model's own PBR textures —
    /// the only post-load step is forcing the lighting model to physicallyBased
    /// in case any material defaults to lambert.
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

        // Auto-fit: longest dimension scaled to 4 units. Centre X/Z on origin.
        // Put the bike's bottom at Y=0 so the shadow-catching floor lines up.
        let (minP, maxP) = bike.boundingBox
        let size = SCNVector3(maxP.x - minP.x, maxP.y - minP.y, maxP.z - minP.z)
        let longest = max(max(abs(size.x), abs(size.y)), abs(size.z))
        guard longest > 0.001 else { return bike }
        let scale: Float = 4.0 / longest
        bike.scale = SCNVector3(scale, scale, scale)

        let centerX = (minP.x + maxP.x) / 2
        let centerZ = (minP.z + maxP.z) / 2
        bike.position = SCNVector3(-centerX * scale, -minP.y * scale, -centerZ * scale)

        // Ensure PBR shading on every material — preserve textures, just guarantee
        // the lighting model. Don't recolour: the model's own textures look great.
        bike.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            for mat in geom.materials {
                mat.lightingModel = .physicallyBased
            }
        }

        return bike
    }

    // MARK: - Procedural fallback

    /// Procedural sport-bike from primitives. Used only if `bike.glb` is
    /// missing or fails to load — primary path is the GLB above.
    private func primitiveBike() -> SCNNode {
        let bike = SCNNode()
        bike.name = "bike"

        let body = uiMaterial(
            color: UIColor(red: 0.10, green: 0.09, blue: 0.13, alpha: 1),
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
        headlight.firstMaterial = accent
        let headN = SCNNode(geometry: headlight)
        headN.name = BikePart.headlight.nodeName
        headN.position = SCNVector3(-1.66, 1.22, 0)
        headN.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        bike.addChildNode(headN)

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
