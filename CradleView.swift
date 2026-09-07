import Cocoa
import SceneKit
import simd

final class CradleView: SCNView {
    let sim = Simulation()
    private var builtFor: CGSize = .zero
    private var ballNodes: [SCNNode] = []
    private var stringNodes: [[SCNNode]] = []
    private var cradleRoot = SCNNode()

    override init(frame: NSRect) {
        super.init(frame: frame, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue
        ])
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        allowsCameraControl = false
        antialiasingMode = .multisampling4X
        backgroundColor = NSColor(calibratedRed: 0.045, green: 0.035, blue: 0.028, alpha: 1)
        autoenablesDefaultLighting = false
        isPlaying = true
        rendersContinuously = true
        isJitteringEnabled = true
        wantsLayer = true
        layer?.isOpaque = true
    }

    override func layout() {
        super.layout()
        sim.layout(in: bounds)
        if bounds.size != builtFor, bounds.width > 8 {
            rebuildScene()
        }
    }

    func tick(dt: Double) {
        if bounds.width > 8 { sim.layout(in: bounds) }
        if builtFor != bounds.size, bounds.width > 8 { rebuildScene() }
        if !MotionHub.shared.paused {
            sim.step(dt: dt, hub: MotionHub.shared)
        }
        syncNodes()
    }

    // MARK: - Scene

    private func rebuildScene() {
        guard sim.balls.count >= 2 else { return }
        builtFor = bounds.size

        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.045, green: 0.035, blue: 0.028, alpha: 1)
        if let hdr = Bundle.main.url(forResource: "env", withExtension: "hdr") {
            scene.lightingEnvironment.contents = hdr
        } else if let jpg = Bundle.main.url(forResource: "env", withExtension: "jpg") {
            scene.lightingEnvironment.contents = jpg
        }
        scene.lightingEnvironment.intensity = 1.15

        cradleRoot = SCNNode()
        scene.rootNode.addChildNode(cradleRoot)

        let first = sim.balls[0]
        let last = sim.balls[sim.balls.count - 1]
        let r = CGFloat(first.radius)
        let railZ = r * 0.95
        let attach = r * 0.16
        let deskY = CGFloat(first.pivotY - first.length) - r * 2.2
        let frontY = CGFloat(first.pivotY)
        let leftX = CGFloat(first.pivotX) - r * 2.2
        let rightX = CGFloat(last.pivotX) + r * 2.2
        let postBottom = deskY + r * 0.15
        let midX = (leftX + rightX) / 2
        let midY = (deskY + frontY) / 2

        addDesk(deskY: deskY, r: r)
        addPlinth(leftX: leftX, rightX: rightX, deskY: deskY, r: r)
        addPostsAndRails(leftX: leftX, rightX: rightX, frontY: frontY, postBottom: postBottom, railZ: railZ, r: r)

        ballNodes = []
        stringNodes = []
        for b in sim.balls {
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 48
            sphere.materials = [chromeMaterial()]
            let node = SCNNode(geometry: sphere)
            node.castsShadow = true
            cradleRoot.addChildNode(node)
            ballNodes.append(node)

            var wires: [SCNNode] = []
            for _ in 0..<2 {
                let cyl = SCNCylinder(radius: 1, height: 1)
                cyl.materials = [wireMaterial()]
                let wn = SCNNode(geometry: cyl)
                wn.castsShadow = false
                cradleRoot.addChildNode(wn)
                wires.append(wn)
            }
            stringNodes.append(wires)
            _ = (b, attach, railZ)
        }

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.78, alpha: 1)
        key.light?.intensity = 650
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowSampleCount = 16
        key.light?.shadowRadius = 6
        key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0.12)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.22, alpha: 1)
        fill.light?.intensity = 180
        scene.rootNode.addChildNode(fill)

        let camNode = SCNNode()
        let cam = SCNCamera()
        cam.zNear = 2
        cam.zFar = 8000
        cam.fieldOfView = 32
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.15
        cam.bloomIntensity = 0.22
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 6
        cam.vignettingIntensity = 0.45
        cam.vignettingPower = 0.8
        cam.colorFringeIntensity = 0.15
        camNode.camera = cam
        let dist = max(bounds.width, bounds.height) * 0.72
        camNode.position = SCNVector3(midX + r * 1.8, midY + r * 3.2, dist)
        camNode.look(at: SCNVector3(midX, midY - r * 0.6, 0))
        scene.rootNode.addChildNode(camNode)
        pointOfView = camNode

        self.scene = scene
        syncNodes()
    }

    private func addDesk(deskY: CGFloat, r: CGFloat) {
        let plane = SCNPlane(width: bounds.width * 1.6, height: bounds.width * 1.6)
        plane.materials = [woodMaterial(repeat: 6)]
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        node.position = SCNVector3(bounds.midX, deskY, 0)
        node.castsShadow = false
        cradleRoot.addChildNode(node)

        // Dark back wall so chrome doesn't reflect a void.
        let wall = SCNPlane(width: bounds.width * 1.6, height: bounds.height * 1.2)
        let wm = SCNMaterial()
        wm.lightingModel = .physicallyBased
        wm.diffuse.contents = NSColor(calibratedRed: 0.07, green: 0.055, blue: 0.04, alpha: 1)
        wm.roughness.contents = 0.9
        wm.metalness.contents = 0.0
        wall.materials = [wm]
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = SCNVector3(bounds.midX, deskY + bounds.height * 0.4, -r * 14)
        wallNode.castsShadow = false
        cradleRoot.addChildNode(wallNode)
    }

    private func addPlinth(leftX: CGFloat, rightX: CGFloat, deskY: CGFloat, r: CGFloat) {
        let w = (rightX - leftX) + r * 3.8
        let d = r * 3.4
        let h = r * 0.55
        let box = SCNBox(width: w, height: h, length: d, chamferRadius: r * 0.06)
        box.materials = [woodMaterial(repeat: 1.4)]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((leftX + rightX) / 2, deskY + h / 2, 0)
        node.castsShadow = true
        cradleRoot.addChildNode(node)

        let felt = SCNBox(width: w - r * 0.5, height: r * 0.06, length: d - r * 0.5, chamferRadius: r * 0.02)
        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        fm.diffuse.contents = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.07, alpha: 1)
        fm.roughness.contents = 1.0
        fm.metalness.contents = 0.0
        felt.materials = [fm]
        let fn = SCNNode(geometry: felt)
        fn.position = SCNVector3((leftX + rightX) / 2, deskY + h + r * 0.02, 0)
        fn.castsShadow = false
        cradleRoot.addChildNode(fn)
    }

    private func addPostsAndRails(leftX: CGFloat, rightX: CGFloat, frontY: CGFloat, postBottom: CGFloat, railZ: CGFloat, r: CGFloat) {
        let postR = r * 0.16
        let height = frontY - postBottom + r * 0.25
        for x in [leftX, rightX] {
            for z in [-railZ, railZ] {
                let post = SCNCylinder(radius: postR, height: height)
                post.materials = [steelMaterial()]
                let n = SCNNode(geometry: post)
                n.position = SCNVector3(x, postBottom + height / 2, z)
                n.castsShadow = true
                cradleRoot.addChildNode(n)
            }
        }
        let railLen = rightX - leftX + r * 0.5
        let railR = r * 0.11
        for z in [-railZ, railZ] {
            let rail = SCNCylinder(radius: railR, height: railLen)
            rail.materials = [brassMaterial()]
            let n = SCNNode(geometry: rail)
            n.position = SCNVector3((leftX + rightX) / 2, frontY, z)
            n.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            n.castsShadow = true
            cradleRoot.addChildNode(n)
        }
    }

    private func syncNodes() {
        guard ballNodes.count == sim.balls.count else { return }
        let first = sim.balls[0]
        let r = CGFloat(first.radius)
        let railZ = r * 0.95
        for (i, b) in sim.balls.enumerated() {
            let p = b.position
            ballNodes[i].position = SCNVector3(p.x, p.y, 0)
            ballNodes[i].scale = SCNVector3(r, r, r)
            let top = SCNVector3(p.x, p.y + r * 0.92, 0)
            let back = SCNVector3(b.pivotX, b.pivotY, -railZ)
            let front = SCNVector3(b.pivotX, b.pivotY, railZ)
            if stringNodes[i].count == 2 {
                placeWire(stringNodes[i][0], from: back, to: top, radius: r * 0.016)
                placeWire(stringNodes[i][1], from: front, to: top, radius: r * 0.016)
            }
        }
    }

    private func placeWire(_ node: SCNNode, from a: SCNVector3, to b: SCNVector3, radius: CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let h = CGFloat(sqrt(dx * dx + dy * dy + dz * dz))
        guard h > 0.5 else { return }
        node.position = SCNVector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
        node.scale = SCNVector3(radius, h, radius)
        let dir = simd_normalize(simd_float3(Float(dx), Float(dy), Float(dz)))
        let yAxis = simd_float3(0, 1, 0)
        let dot = simd_dot(yAxis, dir)
        if dot > 0.999 {
            node.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        } else if dot < -0.999 {
            node.simdOrientation = simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0))
        } else {
            node.simdOrientation = simd_quatf(from: yAxis, to: dir)
        }
    }

    // MARK: - Materials

    private func chromeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedWhite: 0.92, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = Bundle.main.url(forResource: "chrome_rough", withExtension: "png")
            ?? NSNumber(value: 0.12)
        m.roughness.intensity = 1.0
        return m
    }

    private func brassMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedRed: 0.78, green: 0.55, blue: 0.22, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = 0.32
        return m
    }

    private func steelMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedRed: 0.55, green: 0.54, blue: 0.52, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = 0.28
        return m
    }

    private func wireMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedRed: 0.42, green: 0.40, blue: 0.36, alpha: 1)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.38
        return m
    }

    private func woodMaterial(repeat n: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = Bundle.main.url(forResource: "wood", withExtension: "jpg")
            ?? NSColor(calibratedRed: 0.25, green: 0.14, blue: 0.07, alpha: 1)
        m.roughness.contents = Bundle.main.url(forResource: "wood_rough", withExtension: "jpg")
            ?? NSNumber(value: 0.72)
        m.metalness.contents = 0.0
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.roughness.wrapS = .repeat
        m.roughness.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(n, n, 1)
        m.roughness.contentsTransform = SCNMatrix4MakeScale(n, n, 1)
        return m
    }
}
