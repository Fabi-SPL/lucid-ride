import SwiftUI
import SceneKit
import GLTFKit2

/// Logo-style monochrome sport bike scene.
///
/// Aesthetic: black background, black-to-white grayscale only, no chroma
/// accents. Matches the Lucid logo's pure monochrome read. The bike is the
/// low-poly Suzuki SV650 by Paul Spooner (CC-BY 3.0, see Resources/bike-license.txt)
/// chosen for the clean sport-bike silhouette — fairings, low handlebars,
/// swept tail. Recoloured at runtime to enforce the black-and-white look.
///
/// Pipeline:
/// - Load bike.glb via GLTFKit2.
/// - Position-cluster the 16 separate meshes into 6 BikePart regions so
///   tap-to-data still works (model author named meshes "test.001..." etc.,
///   not "headlight" / "tank", so we map by position instead).
/// - Override every material to pure grayscale based on its original colour
///   slot (dark for the body, light gray for chrome accents, near-white
///   emissive on the headlight cylinder).
/// - Three-point lighting in pure white only — key (sharp top-right), fill
///   (soft left), rim (rear). Shadow-catching floor underneath.
/// - HDR + subtle bloom on the camera. No colour grading toward warm or cool.
/// - Orbit-rig camera: the camera revolves slowly around the bike centre;
///   the bike itself remains static apart from the lean-angle tilt.
struct BikeSceneView: UIViewRepresentable {
    let leanDegrees: Double
    let pulseBPM: Double?
    let accentColor: Color   // Kept in the API but intentionally ignored —
    //                          monochrome aesthetic doesn't accept HR-zone tint.
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
        // Pure black background — matches Lucid logo's monochrome ground.
        scene.background.contents = UIColor.black

        // No IBL — keep lighting purely directional + ambient so there's no
        // colour cast from a procedural sky. PBR materials still render fine
        // without an environment, just slightly flatter reflections, which
        // suits the logo aesthetic.
        scene.lightingEnvironment.contents = UIColor(white: 0.08, alpha: 1)
        scene.lightingEnvironment.intensity = 0.6

        // Bike
        let bike = loadOrBuildBike()
        scene.rootNode.addChildNode(bike)

        // World bounds for camera framing (computed from local bounds + transform)
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
        cam.bloomIntensity = 0.9
        cam.bloomThreshold = 0.75
        cam.bloomBlurRadius = 5
        cam.exposureOffset = 0.3
        cam.colorFringeIntensity = 0.0   // No chromatic aberration in monochrome
        cam.contrast = 0.10
        cam.saturation = 0.85            // Slight desaturation pushes any
        //                                  residual chroma toward grayscale.

        let camNode = SCNNode()
        camNode.camera = cam
        let camDist = longestHorizontal * 1.85
        camNode.position = SCNVector3(0, 0, camDist)

        let orbitRig = SCNNode()
        orbitRig.name = "orbitRig"
        orbitRig.position = SCNVector3(0, bikeCenterY, 0)
        orbitRig.eulerAngles = SCNVector3(-0.18, 0.55, 0)  // 3/4 front-left
        orbitRig.addChildNode(camNode)
        scene.rootNode.addChildNode(orbitRig)
        orbitRig.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: 0.18, z: 0, duration: 6)
        ))

        // Lighting — pure white only, no chroma
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1500
        key.color = UIColor.white
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 32
        key.shadowRadius = 8
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0.0, alpha: 0.85)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.65, 0.45, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 350
        fill.color = UIColor(white: 0.78, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.30, -1.4, 0)
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 1400
        rim.color = UIColor.white
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.55, -2.75, 0)
        scene.rootNode.addChildNode(rimNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 80
        amb.color = UIColor(white: 0.5, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Shadow-catching floor — pure black, low reflectivity so it doesn't
        // visually compete with the bike.
        let floor = SCNFloor()
        floor.reflectivity = 0.06
        floor.reflectionFalloffEnd = 1.2
        floor.reflectionResolutionScaleFactor = 0.4
        let fmat = SCNMaterial()
        fmat.lightingModel = .physicallyBased
        fmat.diffuse.contents = UIColor.black
        fmat.metalness.contents = 0.0
        fmat.roughness.contents = 0.55
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

        // Map meshes into BikePart regions (named-node hit testing)
        clusterAndNamePartNodes(bike)

        // Override every material to pure grayscale — enforce the monochrome
        // look regardless of the model author's original colour slots.
        applyMonochromeMaterials(bike)

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

    /// Override every material to pure grayscale + PBR. Tries to honour the
    /// source material name as a tone hint (Black/Silver/Blue meshes get
    /// different gray values for visual interest) while keeping everything
    /// strictly monochrome. The headlight cluster is set to bright emissive
    /// white so it pops in the rim-light view.
    private func applyMonochromeMaterials(_ bike: SCNNode) {
        let darkBody = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)   // near-black
        let midBody  = UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)   // mid gray (was Blue)
        let chrome   = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)   // off-white (was Silver)
        let headOn   = UIColor.white

        bike.enumerateChildNodes { node, _ in
            guard let geom = node.geometry else { return }
            for mat in geom.materials {
                mat.lightingModel = .physicallyBased

                let isHeadlight = (node.name == BikePart.headlight.nodeName)
                let matName = (mat.name ?? "").lowercased()

                let baseColor: UIColor
                let metalness: CGFloat
                let roughness: CGFloat
                if isHeadlight {
                    baseColor = headOn
                    metalness = 0.0
                    roughness = 0.2
                    mat.emission.contents = UIColor(white: 0.95, alpha: 1)
                } else if matName.contains("silver") {
                    baseColor = chrome
                    metalness = 0.92
                    roughness = 0.18
                    mat.emission.contents = UIColor.black
                } else if matName.contains("blue") {
                    baseColor = midBody
                    metalness = 0.70
                    roughness = 0.30
                    mat.emission.contents = UIColor.black
                } else {
                    // Default — Black or any unrecognised slot
                    baseColor = darkBody
                    metalness = 0.55
                    roughness = 0.45
                    mat.emission.contents = UIColor.black
                }

                mat.diffuse.contents = baseColor
                mat.metalness.contents = metalness
                mat.roughness.contents = roughness
                mat.normal.contents = nil
                mat.specular.contents = UIColor.white
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
