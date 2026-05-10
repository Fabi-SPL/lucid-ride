import SwiftUI
import SceneKit

/// Procedural 3D motorcycle built from SceneKit primitives.
/// Leans on the Z axis based on `leanDegrees`. Pulses scale subtly on every
/// heartbeat (when `pulseBPM` is provided). Brand-colored: violet body,
/// teal accents, dark frame.
///
/// Phase A version uses primitives only — zero asset bundling. Future
/// upgrade path: swap `bikeNode()` to load a USDZ from the bundle.
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
        // Lean: rotate around the Z axis (forward axis from camera POV)
        let radians = -leanDegrees * .pi / 180
        let leanAction = SCNAction.rotateTo(
            x: 0, y: 0, z: CGFloat(radians), duration: 0.18, usesShortestUnitArc: true
        )
        leanAction.timingMode = .easeOut
        bike.runAction(leanAction, forKey: "lean")

        // Update accent material color in real time
        let uiAccent = UIColor(accentColor)
        if let tank = view.scene?.rootNode.childNode(withName: "tank", recursively: true),
           let mat = tank.geometry?.firstMaterial {
            mat.diffuse.contents = uiAccent
            mat.emission.contents = uiAccent.withAlphaComponent(0.20)
        }
    }

    // MARK: - Scene assembly

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // Camera — slight 3/4 view from above and forward
        let cam = SCNCamera()
        cam.fieldOfView = 28
        cam.zNear = 0.1
        cam.zFar = 100
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 1.4, 7.5)
        camNode.eulerAngles = SCNVector3(-0.18, 0, 0)
        scene.rootNode.addChildNode(camNode)

        // Lights — key + ambient + back rim for depth
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor(white: 1.0, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 5
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(3, 5, 3)
        keyNode.eulerAngles = SCNVector3(-0.8, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 250
        ambient.color = UIColor(red: 0.55, green: 0.50, blue: 0.85, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = ambient
        scene.rootNode.addChildNode(ambNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 600
        rim.color = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-2, 3, -3)
        rimNode.eulerAngles = SCNVector3(-0.5, -2.4, 0)
        scene.rootNode.addChildNode(rimNode)

        // The bike itself, parented under one node so we can lean the whole rig
        scene.rootNode.addChildNode(bikeNode())
        return scene
    }

    private func bikeNode() -> SCNNode {
        let bike = SCNNode()
        bike.name = "bike"

        let darkFrame = uiMaterial(color: UIColor(white: 0.10, alpha: 1), metal: 0.7, rough: 0.35)
        let chrome    = uiMaterial(color: UIColor(white: 0.55, alpha: 1), metal: 0.95, rough: 0.18)
        let tankMat   = uiMaterial(color: UIColor(red: 0.55, green: 0.49, blue: 0.97, alpha: 1), metal: 0.4, rough: 0.30, emission: 0.20)
        let tireMat   = uiMaterial(color: UIColor(white: 0.06, alpha: 1), metal: 0.0, rough: 0.95)
        let lightMat  = uiMaterial(color: UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1), metal: 0.3, rough: 0.10, emission: 0.65)

        // --- Wheels (front + rear) ---
        for (i, x) in [-1.55, 1.55].enumerated() {
            let tire = SCNTorus(ringRadius: 0.55, pipeRadius: 0.18)
            tire.firstMaterial = tireMat
            tire.ringSegmentCount = 36
            let tireN = SCNNode(geometry: tire)
            tireN.name = i == 0 ? "wheelFront" : "wheelRear"
            tireN.position = SCNVector3(x, -0.25, 0)
            tireN.eulerAngles = SCNVector3(0, 0, .pi / 2)
            bike.addChildNode(tireN)

            let rim = SCNCylinder(radius: 0.32, height: 0.08)
            rim.firstMaterial = chrome
            let rimN = SCNNode(geometry: rim)
            rimN.position = SCNVector3(x, -0.25, 0)
            rimN.eulerAngles = SCNVector3(0, 0, .pi / 2)
            bike.addChildNode(rimN)
        }

        // --- Frame: triangulated boxes connecting head tube to swingarm ---
        let mainTube = SCNBox(width: 1.6, height: 0.12, length: 0.12, chamferRadius: 0.04)
        mainTube.firstMaterial = darkFrame
        let mainN = SCNNode(geometry: mainTube)
        mainN.position = SCNVector3(0, 0.30, 0)
        mainN.eulerAngles = SCNVector3(0, 0, -0.18)
        bike.addChildNode(mainN)

        let downTube = SCNBox(width: 1.0, height: 0.09, length: 0.09, chamferRadius: 0.03)
        downTube.firstMaterial = darkFrame
        let dtN = SCNNode(geometry: downTube)
        dtN.position = SCNVector3(0.35, -0.05, 0)
        dtN.eulerAngles = SCNVector3(0, 0, 0.6)
        bike.addChildNode(dtN)

        // --- Tank (the brand-colored hero piece) ---
        let tank = SCNBox(width: 0.95, height: 0.42, length: 0.55, chamferRadius: 0.18)
        tank.firstMaterial = tankMat
        let tankN = SCNNode(geometry: tank)
        tankN.name = "tank"
        tankN.position = SCNVector3(0.05, 0.55, 0)
        tankN.eulerAngles = SCNVector3(0, 0, -0.05)
        bike.addChildNode(tankN)

        // --- Seat ---
        let seat = SCNBox(width: 0.75, height: 0.10, length: 0.40, chamferRadius: 0.06)
        seat.firstMaterial = uiMaterial(color: UIColor(white: 0.04, alpha: 1), metal: 0.0, rough: 0.7)
        let seatN = SCNNode(geometry: seat)
        seatN.position = SCNVector3(0.85, 0.55, 0)
        bike.addChildNode(seatN)

        // --- Forks (front + rear) ---
        for (xPos, angle) in [(-1.55, -0.10), (1.55, 0.10)] {
            let fork = SCNCylinder(radius: 0.05, height: 0.95)
            fork.firstMaterial = chrome
            let f1 = SCNNode(geometry: fork)
            f1.position = SCNVector3(xPos - 0.10, 0.10, 0.10)
            f1.eulerAngles = SCNVector3(0, 0, angle)
            bike.addChildNode(f1)
            let f2 = SCNNode(geometry: fork)
            f2.position = SCNVector3(xPos + 0.10, 0.10, -0.10)
            f2.eulerAngles = SCNVector3(0, 0, angle)
            bike.addChildNode(f2)
        }

        // --- Handlebars ---
        let bar = SCNCylinder(radius: 0.04, height: 0.85)
        bar.firstMaterial = chrome
        let barN = SCNNode(geometry: bar)
        barN.position = SCNVector3(-1.55, 0.65, 0)
        barN.eulerAngles = SCNVector3(.pi / 2, 0, 0)
        bike.addChildNode(barN)

        // --- Headlight ---
        let head = SCNSphere(radius: 0.18)
        head.firstMaterial = lightMat
        let headN = SCNNode(geometry: head)
        headN.position = SCNVector3(-1.45, 0.55, 0)
        bike.addChildNode(headN)

        // --- Exhaust ---
        let exhaust = SCNCylinder(radius: 0.08, height: 1.1)
        exhaust.firstMaterial = chrome
        let exN = SCNNode(geometry: exhaust)
        exN.position = SCNVector3(1.15, -0.10, -0.30)
        exN.eulerAngles = SCNVector3(0, 0, .pi / 2)
        bike.addChildNode(exN)

        // Slight idle rotation around Y so it feels alive when stationary
        let idle = SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.08, z: 0, duration: 6),
                SCNAction.rotateBy(x: 0, y: -0.16, z: 0, duration: 12),
                SCNAction.rotateBy(x: 0, y: 0.08, z: 0, duration: 6)
            ])
        )
        // Apply to a child wrapper so lean (Z rotation) and idle (Y rotation) don't fight
        let yWrapper = SCNNode()
        yWrapper.name = "yWrapper"
        bike.childNodes.forEach { yWrapper.addChildNode($0) }
        // Replace bike's children with the wrapper
        bike.childNodes.forEach { $0.removeFromParentNode() }
        bike.addChildNode(yWrapper)
        yWrapper.runAction(idle)

        // Initial bike position — slightly raised so it sits centered in the camera
        bike.position = SCNVector3(0, 0, 0)
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
