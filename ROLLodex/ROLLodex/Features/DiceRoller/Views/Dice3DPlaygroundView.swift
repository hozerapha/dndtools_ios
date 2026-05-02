import SwiftUI
import SceneKit
import simd

// MARK: - SwiftUI

struct Dice3DPlaygroundView: View {
    @State private var controller = DiceSceneController()
    @State private var diceCount = 1
    @State private var results: [Int?] = [nil]
    @State private var isRolling = false

    private let maxDice = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    SceneKitView(controller: controller)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

                    if let total = totalResult {
                        Text("\(total)")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 20)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text("Dice")
                        .font(.headline)
                    Spacer()
                    Stepper("\(diceCount)", value: $diceCount, in: 1...maxDice)
                        .labelsHidden()
                    Text("\(diceCount)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 24)
                }
                .disabled(isRolling)

                Button {
                    rollAll()
                } label: {
                    Label(isRolling ? "Rolling…" : "Roll \(diceCount)d6", systemImage: "dice.fill")
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
            .animation(.snappy, value: results)
            .onAppear {
                controller.setDieCount(diceCount)
                controller.onDieSettled = { @MainActor index, face in
                    guard results.indices.contains(index) else { return }
                    results[index] = face
                }
            }
            .onChange(of: diceCount) { _, new in
                controller.setDieCount(new)
                results = Array(repeating: nil, count: new)
            }
        }
    }

    private func rollAll() {
        results = Array(repeating: nil, count: diceCount)
        isRolling = true
        controller.rollAll { @MainActor _ in
            isRolling = false
        }
    }

    private var totalResult: Int? {
        let settled = results.compactMap { $0 }
        return settled.isEmpty ? nil : settled.reduce(0, +)
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

    /// Fires once per die as it comes to rest. `(dieIndex, faceValue)`.
    var onDieSettled: (@MainActor (Int, Int) -> Void)?

    private weak var scnView: SCNView?
    private var scene: SCNScene!

    private struct ManagedDie {
        let node: SCNNode
        var hasSettled: Bool
        var stillFrameCount: Int
        var rolledFace: Int?
    }

    private var dice: [ManagedDie] = []

    private var allSettledCallback: (@MainActor ([Int]) -> Void)?
    private var isAwaitingRest = false
    private var rollStartTime: TimeInterval = 0

    private let restSpeedThreshold: Float = 0.10
    private let restAngularThreshold: Float = 0.25     // rad/sec — catches still-spinning cubes
    private let restFramesRequired = 12                // ~192ms of continuous stillness
    private let minRollDuration: TimeInterval = 0.30

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

        // Invisible containment walls. The visible wood walls stop at y=wallHeight (3);
        // a hard-thrown die can clip over them into the gap below the ceiling and
        // escape the tray laterally. These extend the walls upward so that can't happen.
        let invisibleWallHeight: Float = 20
        let invisibleWallY = wallHeight + invisibleWallHeight / 2

        let invisibleWalls: [(size: SCNVector3, position: SCNVector3)] = [
            (SCNVector3(wallThick, invisibleWallHeight, outerSpan),
             SCNVector3(-trayHalf - wallThick / 2, invisibleWallY, 0)),
            (SCNVector3(wallThick, invisibleWallHeight, outerSpan),
             SCNVector3( trayHalf + wallThick / 2, invisibleWallY, 0)),
            (SCNVector3(trayHalf * 2, invisibleWallHeight, wallThick),
             SCNVector3(0, invisibleWallY, -trayHalf - wallThick / 2)),
            (SCNVector3(trayHalf * 2, invisibleWallHeight, wallThick),
             SCNVector3(0, invisibleWallY,  trayHalf + wallThick / 2))
        ]
        for spec in invisibleWalls {
            scene.rootNode.addChildNode(makeBox(
                size: spec.size,
                position: spec.position,
                faceImages: [nil],
                fallback: .clear
            ))
        }

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

    // MARK: Dice — body cube + 6 plane children for textures

    private func createDieNode() -> SCNNode {
        let cubeSizeCG = CGFloat(cubeSize)
        let geometry = SCNBox(width: cubeSizeCG, height: cubeSizeCG, length: cubeSizeCG, chamferRadius: 0.11)

        // Body — single ivory material on all sides; chamfered edges visible behind plane skins.
        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        bodyMat.roughness.contents = 0.40
        geometry.materials = [bodyMat]

        let node = SCNNode(geometry: geometry)
        node.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)

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

    // MARK: Population

    /// Add or remove dice to match the requested count. Existing dice keep their state.
    func setDieCount(_ count: Int) {
        let target = max(0, count)

        while dice.count > target {
            let removed = dice.removeLast()
            removed.node.removeFromParentNode()
        }

        while dice.count < target {
            let node = createDieNode()
            node.position = findEmptyTrayPosition()
            // Random yaw so newly added dice don't all face the same way.
            node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
            scene.rootNode.addChildNode(node)
            dice.append(ManagedDie(node: node, hasSettled: true, stillFrameCount: 0, rolledFace: nil))
        }
    }

    /// Picks a spot inside the tray that doesn't overlap any existing die. If the tray
    /// is too crowded to find a clear spot, drops the new die in higher up so physics
    /// can resolve any soft contact naturally.
    private func findEmptyTrayPosition() -> SCNVector3 {
        let margin = cubeSize
        let bound = trayHalf - margin
        let minSpacing = cubeSize * 1.5

        for _ in 0..<30 {
            let x = Float.random(in: -bound...bound)
            let z = Float.random(in: -bound...bound)
            let tooClose = dice.contains { existing in
                let p = existing.node.position
                let dx = p.x - x, dz = p.z - z
                return sqrt(dx * dx + dz * dz) < minSpacing
            }
            if !tooClose {
                return SCNVector3(x, cubeHalfSize + 0.02, z)
            }
        }
        // Tray is crowded — spawn higher so the new die can settle on top of others
        // without intersecting them.
        return SCNVector3(
            Float.random(in: -bound...bound),
            cubeHalfSize + 4.0,
            Float.random(in: -bound...bound)
        )
    }

    // MARK: Roll

    /// Roll every die in the scene. `onAllSettled` fires once when all dice are at rest,
    /// with their face values in die-index order. `onDieSettled` fires per-die as each one rests.
    func rollAll(onAllSettled: @escaping @MainActor ([Int]) -> Void) {
        guard !dice.isEmpty else { onAllSettled([]); return }

        for i in dice.indices {
            dice[i].hasSettled = false
            dice[i].stillFrameCount = 0
            dice[i].rolledFace = nil

            let node = dice[i].node
            guard let body = node.physicsBody else { continue }
            body.velocity = SCNVector3Zero
            body.angularVelocity = SCNVector4Zero

            // Spawn slightly staggered so dice don't all start coincident.
            node.position = SCNVector3(
                Float.random(in: -1.5...1.5),
                5 + Float(i) * 0.25,
                Float.random(in: -1.5...1.5)
            )
            node.simdOrientation = randomOrientation()

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
        }

        allSettledCallback = onAllSettled
        isAwaitingRest = true
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
        guard isAwaitingRest, !dice.isEmpty else { return }
        let elapsed = CACurrentMediaTime() - rollStartTime
        guard elapsed > minRollDuration else { return }

        for i in dice.indices {
            if dice[i].hasSettled { continue }
            guard let body = dice[i].node.physicsBody else { continue }

            // Trust SceneKit's `isResting` when set; manual fallback for the cases where
            // it never sleeps. Both paths require a continuous-still streak so we don't
            // settle mid-bounce.
            if body.isResting {
                dice[i].stillFrameCount += 1
                if dice[i].stillFrameCount >= restFramesRequired {
                    settleDie(at: i)
                }
                continue
            }

            let v = body.velocity
            let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            let angularSpeed = abs(body.angularVelocity.w)
            let yPos = dice[i].node.presentation.position.y
            let nearFloor = yPos < cubeHalfSize + 0.6

            if speed < restSpeedThreshold
                && angularSpeed < restAngularThreshold
                && nearFloor {
                dice[i].stillFrameCount += 1
                if dice[i].stillFrameCount >= restFramesRequired * 2 {
                    settleDie(at: i)
                }
            } else {
                dice[i].stillFrameCount = 0
            }
        }

        if dice.allSatisfy(\.hasSettled) {
            isAwaitingRest = false
            let cb = allSettledCallback
            allSettledCallback = nil
            cb?(dice.map { $0.rolledFace ?? 1 })
        }
    }

    private func settleDie(at index: Int) {
        let face = detectTopFace(of: dice[index].node)
        dice[index].hasSettled = true
        dice[index].rolledFace = face
        onDieSettled?(index, face)
    }

    /// Returns the face whose outward normal, after the cube's current rotation, points
    /// most directly upward in world space. Equivalent to "which face's center is highest".
    private func detectTopFace(of node: SCNNode) -> Int {
        let q = node.presentation.simdOrientation
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
