import SwiftUI
import SceneKit
import simd

// MARK: - SwiftUI

struct Dice3DPlaygroundView: View {
    @State private var controller = DiceSceneController()
    @State private var resultFace: Int?
    @State private var isRolling = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    SceneKitView(controller: controller)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

                    if let face = resultFace {
                        Text("\(face)")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)

                Button {
                    rollD6()
                } label: {
                    Label(isRolling ? "Rolling…" : "Roll d6", systemImage: "dice.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRolling)
            }
            .padding()
            .navigationTitle("3D Dice (sandbox)")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: resultFace)
        }
    }

    private func rollD6() {
        resultFace = nil
        isRolling = true
        controller.rollDie { @MainActor face in
            resultFace = face
            isRolling = false
        }
    }
}

private struct SceneKitView: UIViewRepresentable {
    let controller: DiceSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = true
        view.backgroundColor = UIColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 1)
        view.isPlaying = true
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Scene controller

@MainActor
final class DiceSceneController: NSObject {

    private weak var scnView: SCNView?
    private var scene: SCNScene!
    private var dieNode: SCNNode!

    private var settledCallback: (@MainActor (Int) -> Void)?
    private var isAwaitingRest = false
    private var stillFrameCount = 0
    private var rollStartTime: TimeInterval = 0
    private let restSpeedThreshold: Float = 0.10
    private let restAngularThreshold: Float = 0.25     // rad/sec — catches still-spinning cubes
    private let restFramesRequired = 12                // ~192ms of continuous stillness
    private let minRollDuration: TimeInterval = 0.30
    private let maxRollDuration: TimeInterval = 5.0

    private var restPollTask: Task<Void, Never>?

    // Cube geometry constants
    private let cubeSize: Float = 1.7
    private var cubeHalfSize: Float { cubeSize / 2 }

    /// Each face stores its number and its outward normal in cube-local frame.
    /// The visual texture sits on a plane child positioned along that normal.
    private struct FaceSpec {
        let number: Int
        let normal: SIMD3<Float>
    }

    private static let faceSpecs: [FaceSpec] = [
        FaceSpec(number: 1, normal: [ 0,  1,  0]),
        FaceSpec(number: 6, normal: [ 0, -1,  0]),
        FaceSpec(number: 2, normal: [ 1,  0,  0]),
        FaceSpec(number: 5, normal: [-1,  0,  0]),
        FaceSpec(number: 3, normal: [ 0,  0,  1]),
        FaceSpec(number: 4, normal: [ 0,  0, -1])
    ]

    deinit {
        restPollTask?.cancel()
    }

    func attach(to view: SCNView) {
        guard scnView == nil else { return }
        scnView = view
        setupScene()
        view.scene = scene

        restPollTask?.cancel()
        restPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tickRestDetection()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: Scene

    private func setupScene() {
        scene = SCNScene()
        scene.background.contents = UIColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 1)
        scene.physicsWorld.speed = 3.0

        setupCamera()
        setupLighting()
        setupTray()
        setupDie()
    }

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 55
        cameraNode.position = SCNVector3(0, 26, 9)

        let target = SCNNode()
        target.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(target)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]

        scene.rootNode.addChildNode(cameraNode)
    }

    private func setupLighting() {
        let omni = SCNNode()
        omni.light = SCNLight()
        omni.light?.type = .omni
        omni.light?.intensity = 1200
        omni.position = SCNVector3(4, 12, 6)
        scene.rootNode.addChildNode(omni)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.35, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    private let trayHalf: Float = 7
    private let wallHeight: Float = 3
    private let wallThick: Float = 0.5
    private let floorThick: Float = 0.4

    private func setupTray() {
        let feltImage = UIImage(named: "tray-felt")
        let woodImage = UIImage(named: "tray-wood")
        let feltColor = UIColor(red: 0.10, green: 0.30, blue: 0.18, alpha: 1)
        let woodColor = UIColor(red: 0.36, green: 0.21, blue: 0.10, alpha: 1)

        let floor = makeBox(
            size: SCNVector3(trayHalf * 2, floorThick, trayHalf * 2),
            position: SCNVector3(0, -floorThick / 2, 0),
            faceImages: [woodImage, woodImage, woodImage, woodImage, feltImage, woodImage],
            fallback: feltColor
        )
        scene.rootNode.addChildNode(floor)

        let wallY = wallHeight / 2
        let outerSpan = trayHalf * 2 + wallThick * 2

        scene.rootNode.addChildNode(makeBox(
            size: SCNVector3(wallThick, wallHeight, outerSpan),
            position: SCNVector3(-trayHalf - wallThick / 2, wallY, 0),
            faceImages: [woodImage], fallback: woodColor
        ))
        scene.rootNode.addChildNode(makeBox(
            size: SCNVector3(wallThick, wallHeight, outerSpan),
            position: SCNVector3( trayHalf + wallThick / 2, wallY, 0),
            faceImages: [woodImage], fallback: woodColor
        ))
        scene.rootNode.addChildNode(makeBox(
            size: SCNVector3(trayHalf * 2, wallHeight, wallThick),
            position: SCNVector3(0, wallY, -trayHalf - wallThick / 2),
            faceImages: [woodImage], fallback: woodColor
        ))
        scene.rootNode.addChildNode(makeBox(
            size: SCNVector3(trayHalf * 2, wallHeight, wallThick),
            position: SCNVector3(0, wallY,  trayHalf + wallThick / 2),
            faceImages: [woodImage], fallback: woodColor
        ))

        let ceiling = SCNNode(geometry: SCNPlane(width: 60, height: 60))
        ceiling.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        ceiling.geometry?.firstMaterial?.isDoubleSided = true
        ceiling.position = SCNVector3(0, 9, 0)
        ceiling.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        ceiling.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(ceiling)
    }

    private func makeBox(
        size: SCNVector3,
        position: SCNVector3,
        faceImages: [UIImage?],
        fallback: UIColor
    ) -> SCNNode {
        let geometry = SCNBox(
            width:  CGFloat(size.x),
            height: CGFloat(size.y),
            length: CGFloat(size.z),
            chamferRadius: 0.05
        )
        let materials: [SCNMaterial] = (faceImages.count == 6 ? faceImages : Array(repeating: faceImages.first ?? nil, count: 6))
            .map { image in
                let m = SCNMaterial()
                m.diffuse.contents = image ?? fallback
                return m
            }
        geometry.materials = materials

        let node = SCNNode(geometry: geometry)
        node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        node.position = position
        return node
    }

    // MARK: Die — body cube + 6 plane children for textures

    private func setupDie() {
        dieNode = createDie()
        scene.rootNode.addChildNode(dieNode)
    }

    private func createDie() -> SCNNode {
        let cubeSizeCG = CGFloat(cubeSize)
        let geometry = SCNBox(width: cubeSizeCG, height: cubeSizeCG, length: cubeSizeCG, chamferRadius: 0.11)

        // Body — single ivory material on all sides; chamfered edges visible behind plane skins.
        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        bodyMat.roughness.contents = 0.40
        geometry.materials = [bodyMat]

        let node = SCNNode(geometry: geometry)
        node.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)
        node.position = SCNVector3(0, 4, 0)

        // Add a plane child for each face. The plane's diffuse content is the face's
        // texture (currently a generated pip pattern; later swap for skin images).
        let planeSize = CGFloat(cubeSize) * 0.85
        for face in Self.faceSpecs {
            let plane = SCNPlane(width: planeSize, height: planeSize)
            let mat = SCNMaterial()
            mat.diffuse.contents = Self.makePipImage(faceNumber: face.number)
            mat.roughness.contents = 0.45
            plane.materials = [mat]

            let planeNode = SCNNode(geometry: plane)
            planeNode.simdPosition = face.normal * (cubeHalfSize + 0.005)
            planeNode.simdOrientation = Self.rotationFromZ(to: face.normal)
            node.addChildNode(planeNode)
        }

        return node
    }

    /// Rotation that maps SCNPlane's default +Z normal to `target`.
    private static func rotationFromZ(to target: SIMD3<Float>) -> simd_quatf {
        let from: SIMD3<Float> = [0, 0, 1]
        let d = simd_dot(from, target)
        if d > 0.9999 { return simd_quatf(angle: 0, axis: [1, 0, 0]) }
        if d < -0.9999 { return simd_quatf(angle: .pi, axis: [0, 1, 0]) }
        let axis = simd_normalize(simd_cross(from, target))
        return simd_quatf(angle: acos(d), axis: axis)
    }

    private static func makePipImage(faceNumber: Int) -> UIImage {
        let pixelSize: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize)))
            UIColor(white: 0.08, alpha: 1).setFill()
            let pipRadius: CGFloat = 18
            for pos in pipPositions(count: faceNumber, side: pixelSize) {
                let r = CGRect(
                    x: pos.x - pipRadius, y: pos.y - pipRadius,
                    width: pipRadius * 2, height: pipRadius * 2
                )
                ctx.cgContext.fillEllipse(in: r)
            }
        }
    }

    private static func pipPositions(count: Int, side: CGFloat) -> [CGPoint] {
        let c = side / 2
        let o = side / 4
        switch count {
        case 1: return [CGPoint(x: c, y: c)]
        case 2: return [CGPoint(x: c - o, y: c - o), CGPoint(x: c + o, y: c + o)]
        case 3: return [CGPoint(x: c - o, y: c - o), CGPoint(x: c, y: c), CGPoint(x: c + o, y: c + o)]
        case 4: return [CGPoint(x: c - o, y: c - o), CGPoint(x: c + o, y: c - o),
                        CGPoint(x: c - o, y: c + o), CGPoint(x: c + o, y: c + o)]
        case 5: return [CGPoint(x: c - o, y: c - o), CGPoint(x: c + o, y: c - o), CGPoint(x: c, y: c),
                        CGPoint(x: c - o, y: c + o), CGPoint(x: c + o, y: c + o)]
        case 6: return [CGPoint(x: c - o, y: c - o), CGPoint(x: c + o, y: c - o),
                        CGPoint(x: c - o, y: c    ), CGPoint(x: c + o, y: c    ),
                        CGPoint(x: c - o, y: c + o), CGPoint(x: c + o, y: c + o)]
        default: return []
        }
    }

    // MARK: Roll

    func rollDie(onSettled: @escaping @MainActor (Int) -> Void) {
        guard let body = dieNode.physicsBody else { return }

        body.velocity = SCNVector3Zero
        body.angularVelocity = SCNVector4Zero

        dieNode.position = SCNVector3(
            Float.random(in: -1.0...1.0),
            5,
            Float.random(in: -1.0...1.0)
        )
        dieNode.simdOrientation = randomOrientation()

        let torque = SCNVector4(
            Float.random(in: -2...2),
            Float.random(in: -3...3),
            Float.random(in: -2...2),
            Float.random(in: 1.5...3.0)
        )
        body.applyTorque(torque, asImpulse: true)

        let force = SCNVector3(
            Float.random(in: -3...3),
            Float.random(in: 18...26),
            Float.random(in: -3...3)
        )
        body.applyForce(force, asImpulse: true)

        settledCallback = onSettled
        isAwaitingRest = true
        stillFrameCount = 0
        rollStartTime = CACurrentMediaTime()
    }

    private func randomOrientation() -> simd_quatf {
        let axis = simd_normalize(simd_float3(
            Float.random(in: -1...1),
            Float.random(in: -1...1),
            Float.random(in: -1...1)
        ))
        return simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: axis)
    }

    // MARK: Rest detection

    private func tickRestDetection() {
        guard isAwaitingRest, let dieNode, let body = dieNode.physicsBody else { return }
        let elapsed = CACurrentMediaTime() - rollStartTime

        if elapsed > maxRollDuration {
            finishRoll()
            return
        }
        guard elapsed > minRollDuration else { return }

        // Trust SceneKit's `isResting` as the authoritative signal — the solver only sets
        // it to true once the body has actually been still long enough to be put to sleep.
        // The manual velocity fallback only kicks in if the body genuinely never sleeps,
        // and even then we require all three motion signals to be quiet plus the cube to
        // be near the floor (not mid-bounce).
        if body.isResting {
            stillFrameCount += 1
            if stillFrameCount >= restFramesRequired {
                finishRoll()
            }
            return
        }

        let v = body.velocity
        let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        let angularSpeed = abs(body.angularVelocity.w)
        let yPos = dieNode.presentation.position.y
        let nearFloor = yPos < cubeHalfSize + 0.6

        if speed < restSpeedThreshold
            && angularSpeed < restAngularThreshold
            && nearFloor {
            stillFrameCount += 1
            // Manual fallback needs longer continuity to be safe.
            if stillFrameCount >= restFramesRequired * 2 {
                finishRoll()
            }
        } else {
            stillFrameCount = 0
        }
    }

    private func finishRoll() {
        isAwaitingRest = false
        let cb = settledCallback
        settledCallback = nil

        // No snap — read the actual rest orientation. Whichever face's normal is most
        // aligned with world-up after rotation is the face whose center has the
        // highest Y, i.e. the face the user sees on top.
        cb?(detectTopFace())
    }

    /// Returns the face whose outward normal, after the cube's current rotation, points
    /// most directly upward in world space. Equivalent to "which face's center is highest".
    private func detectTopFace() -> Int {
        guard let dieNode else { return 1 }
        let q = dieNode.presentation.simdOrientation     // what's actually rendered
        let upWorld = simd_float3(0, 1, 0)

        var best = 1
        var bestDot: Float = -2
        for face in Self.faceSpecs {
            let world = q.act(face.normal)
            let d = simd_dot(world, upWorld)
            if d > bestDot {
                bestDot = d
                best = face.number
            }
        }
        return best
    }
}
