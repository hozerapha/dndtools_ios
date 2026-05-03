import SwiftUI
import SceneKit
import simd

// MARK: - Dice kinds

enum Dice3DKind: String, CaseIterable, Identifiable {
    case d4
    case d6

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var sides: Int {
        switch self {
        case .d4: return 4
        case .d6: return 6
        }
    }

    /// Bridges from the project-wide `DieKind` (which spans d4–d100) to the subset
    /// the 3D scene currently knows how to model. Returns nil for unsupported kinds.
    init?(_ kind: DieKind) {
        switch kind {
        case .d4: self = .d4
        case .d6: self = .d6
        default:  return nil
        }
    }
}

extension DieKind {
    /// True if this die kind has a 3D model + textures wired up.
    var has3DModel: Bool { Dice3DKind(self) != nil }
}

extension DiceFormula {
    /// True if every die kind in the formula has a 3D model. The Dice tab uses
    /// this to gate the roll button while only a subset of kinds is in 3D.
    var allKinds3DSupported: Bool {
        groups.allSatisfy(\.kind.has3DModel)
    }
}

// MARK: - SwiftUI

struct Dice3DPlaygroundView: View {
    @State private var controller = DiceSceneController()
    @State private var diceCount = 1
    @State private var diceKind: Dice3DKind = .d6
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

                Picker("Kind", selection: $diceKind) {
                    ForEach(Dice3DKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRolling)

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
                    Label(isRolling ? "Rolling…" : "Roll \(diceCount)\(diceKind.rawValue)", systemImage: "dice.fill")
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
                controller.setDice(count: diceCount, kind: diceKind)
                controller.onDieSettled = { @MainActor index, face in
                    guard results.indices.contains(index) else { return }
                    results[index] = face
                }
            }
            .onChange(of: diceCount) { _, new in
                controller.setDice(count: new, kind: diceKind)
                results = Array(repeating: nil, count: new)
            }
            .onChange(of: diceKind) { _, new in
                controller.setDice(count: diceCount, kind: new)
                results = Array(repeating: nil, count: diceCount)
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

struct SceneKitView: UIViewRepresentable {
    let controller: DiceSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = true
        // Transparent so the SwiftUI/system background shows through behind the
        // tray — meshes with both light and dark mode without hard-coding a color.
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isPlaying = true
        // Pinch to zoom, one-finger drag to orbit, two-finger drag to pan. Useful for
        // troubleshooting; harmless because no app logic depends on camera state.
        view.allowsCameraControl = true
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Async wrappers for callback APIs

extension DiceSceneController {
    /// Async version of `rollAll` for use from a SwiftUI Task. Resumes once every
    /// die has settled and its face value has been read (after `settleDelay`).
    @MainActor
    func rollAllAsync() async -> [Int] {
        await withCheckedContinuation { continuation in
            self.rollAll { values in continuation.resume(returning: values) }
        }
    }

    /// Async version of `rethrowDice`. Resumes when the rethrown dice have settled.
    @MainActor
    func rethrowDiceAsync(at formulaIndices: Set<Int>) async -> [Int] {
        await withCheckedContinuation { continuation in
            self.rethrowDice(at: formulaIndices) { values in continuation.resume(returning: values) }
        }
    }
}

// MARK: - Scene controller

@MainActor
final class DiceSceneController: NSObject {

    /// Fires once per die as it comes to rest. `(dieIndex, faceValue)`.
    var onDieSettled: (@MainActor (Int, Int) -> Void)?

    private weak var scnView: SCNView?
    private var scene: SCNScene!
    private var cameraNode: SCNNode!
    private let defaultCameraPosition = SCNVector3(0, 22, 7.5)
    private let defaultCameraTarget   = SCNVector3(0, 0, 0)

    private struct ManagedDie {
        let node: SCNNode
        let kind: Dice3DKind
        /// Position of this die in the formula's flat dice list (groups expanded
        /// in order). Used by callers to map roll results back to formula slots
        /// when applying modifiers. -1 for dice created via the legacy
        /// `setDice(count:kind:)` API where the concept doesn't apply.
        var formulaIndex: Int
        var hasSettled: Bool
        var stillFrameCount: Int
        var rolledFace: Int?
    }

    private var dice: [ManagedDie] = []

    /// Number of dice currently in the scene. Lets callers do idempotent setup
    /// (e.g. only call `setDice(formula:)` on the first view appearance) without
    /// peeking at the private collection.
    var diceCount: Int { dice.count }

    private var allSettledCallback: (@MainActor ([Int]) -> Void)?
    private var isAwaitingRest = false
    private var rollStartTime: TimeInterval = 0
    /// Bumped on every `rollAll` so any in-flight settle-delay tasks from a prior
    /// roll know to bail out instead of writing stale face values.
    private var currentRollId: Int = 0
    /// Grace period after physics rest before snapshotting each die's face. d4s
    /// can balance precariously on an edge for a moment before tipping; reading
    /// the orientation too early picks the wrong face.
    private let settleDelay: TimeInterval = 0.3

    private let restSpeedThreshold: Float = 0.10
    private let restAngularThreshold: Float = 0.25     // rad/sec — catches still-spinning dice
    private let restFramesRequired = 12                // ~192ms of continuous stillness
    private let minRollDuration: TimeInterval = 0.30

    private var restPollTask: Task<Void, Never>?

    // d6 geometry constants
    private let cubeSize: Float = 1.7
    private var cubeHalfSize: Float { cubeSize / 2 }

    // d4 geometry constants — vertices at scale·(±1,±1,±1) alternating-corners-of-cube,
    // giving a regular tetrahedron with circumscribed-sphere radius scale·√3.
    // Picked so the d4 has a similar bounding sphere to the d6.
    private let d4Scale: Float = 0.85

    /// Each face stores its number and its outward normal in die-local frame.
    private struct FaceSpec {
        let number: Int
        let normal: SIMD3<Float>
    }

    /// Face layout for a kind. The visual texture/plane sits along the face's outward normal.
    private static func faceSpecs(for kind: Dice3DKind) -> [FaceSpec] {
        switch kind {
        case .d4:
            // Outward normals for the 4 faces of a tetrahedron with vertices at the
            // alternating corners of a cube ((±1,±1,±1) with even sign-parity). Each
            // normal is the negation of the opposite vertex direction, normalized.
            let inv = 1.0 / sqrtf(3)
            return [
                FaceSpec(number: 1, normal: SIMD3(-inv, -inv, -inv)),
                FaceSpec(number: 2, normal: SIMD3(-inv,  inv,  inv)),
                FaceSpec(number: 3, normal: SIMD3( inv, -inv,  inv)),
                FaceSpec(number: 4, normal: SIMD3( inv,  inv, -inv))
            ]
        case .d6:
            return [
                FaceSpec(number: 1, normal: [ 0,  1,  0]),
                FaceSpec(number: 6, normal: [ 0, -1,  0]),
                FaceSpec(number: 2, normal: [ 1,  0,  0]),
                FaceSpec(number: 5, normal: [-1,  0,  0]),
                FaceSpec(number: 3, normal: [ 0,  0,  1]),
                FaceSpec(number: 4, normal: [ 0,  0, -1])
            ]
        }
    }

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
        // Leave the scene background unset — combined with `view.isOpaque = false`
        // and `view.backgroundColor = .clear` in SceneKitView, the void around the
        // tray is fully transparent and the SwiftUI layer behind shows through.
        scene.physicsWorld.speed = 3.0

        setupCamera()
        setupLighting()
        setupTray()
    }

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 55
        cameraNode.position = defaultCameraPosition
        // One-shot orientation toward the tray instead of a SCNLookAtConstraint —
        // the constraint would keep snapping the camera back every frame and
        // prevent the user from orbiting via SCNView.allowsCameraControl.
        cameraNode.look(at: defaultCameraTarget)
        scene.rootNode.addChildNode(cameraNode)
        self.cameraNode = cameraNode
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

    private let trayHalf: Float = 7.5
    private let wallHeight: Float = 1.5
    private let wallThick: Float = 0.5
    private let floorThick: Float = 0.4

    private func setupTray() {
        let feltImage = UIImage(named: "tray-felt")
        let woodImage = UIImage(named: "tray-wood")
        let feltColor = UIColor(red: 0.10, green: 0.30, blue: 0.18, alpha: 1)
        let woodColor = UIColor(red: 0.36, green: 0.21, blue: 0.10, alpha: 1)

        // Slightly oversize the floor so it tucks under the wall's inner face. Without
        // this, both boxes' chamfered edges curve away from the seam at y=0 and leave
        // a hairline gap that the (now transparent) background bleeds through.
        let floorOverhang: Float = 0.15
        let floorSpan = (trayHalf + floorOverhang) * 2
        let floor = makeBox(
            size: SCNVector3(floorSpan, floorThick, floorSpan),
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

        // Solid invisible ceiling sitting flush on top of the invisible walls.
        // Using a thick SCNBox (rather than the previous SCNPlane) so collisions
        // are reliable when many dice slam into it during a chaotic roll —
        // SCNPlane's single-thickness physics shape was occasionally letting fast
        // dice slip through and escape into the void.
        let ceilingThick: Float = 0.5
        let ceilingY = wallHeight + invisibleWallHeight + ceilingThick / 2
        scene.rootNode.addChildNode(makeBox(
            size: SCNVector3(outerSpan, ceilingThick, outerSpan),
            position: SCNVector3(0, ceilingY, 0),
            faceImages: [nil],
            fallback: .clear
        ))
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

    // MARK: Die geometry

    private func createDieNode(kind: Dice3DKind) -> SCNNode {
        switch kind {
        case .d4: return createD4Node()
        case .d6: return createD6Node()
        }
    }

    private func createD6Node() -> SCNNode {
        let cubeSizeCG = CGFloat(cubeSize)
        let geometry = SCNBox(width: cubeSizeCG, height: cubeSizeCG, length: cubeSizeCG, chamferRadius: 0.11)

        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = ivoryColor
        bodyMat.roughness.contents = 0.40
        geometry.materials = [bodyMat]

        let node = SCNNode(geometry: geometry)
        node.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)

        // Plane child per face — same approach as before, ivory background + pip pattern.
        let planeSize = CGFloat(cubeSize) * 0.85
        for face in Self.faceSpecs(for: .d6) {
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

    /// Builds a regular tetrahedron with vertex coords at d4Scale·(alternating-corners
    /// of a cube). The body is one ivory geometry handling shape + physics; on top of
    /// each face sits a child triangle node with its own UV-mapped texture showing the
    /// three corner digits (matching the standard d4 convention where each face omits
    /// its OWN number, and each visible face shows the result at its apex).
    ///
    /// Splitting the textured faces into separate child geometries (rather than a single
    /// multi-element geometry) sidesteps SceneKit's multi-element/multi-material rendering,
    /// which wasn't applying per-face textures correctly here.
    private func createD4Node() -> SCNNode {
        let s = d4Scale
        let v: [SIMD3<Float>] = [
            SIMD3( 1,  1,  1) * s,  // 0 — number 1
            SIMD3( 1, -1, -1) * s,  // 1 — number 2
            SIMD3(-1,  1, -1) * s,  // 2 — number 3
            SIMD3(-1, -1,  1) * s   // 3 — number 4
        ]
        // Vertex i carries number (i+1). The face opposite vertex i has RESULT (i+1) —
        // when the die rests on it, vertex i is the apex.
        let faces: [(verts: [Int], number: Int)] = [
            (verts: [1, 3, 2], number: 1),  // opposite v0; outward = (-,-,-)
            (verts: [0, 2, 3], number: 2),  // opposite v1; outward = (-,+,+)
            (verts: [0, 3, 1], number: 3),  // opposite v2; outward = (+,-,+)
            (verts: [0, 1, 2], number: 4)   // opposite v3; outward = (+,+,-)
        ]

        // Body geometry — single element, single ivory material. Used for the convex-hull
        // physics shape and as the opaque base color behind the textured face overlays.
        var bodyPositions: [SCNVector3] = []
        var bodyNormals: [SCNVector3] = []
        for face in faces {
            let p0 = v[face.verts[0]]
            let p1 = v[face.verts[1]]
            let p2 = v[face.verts[2]]
            let n = simd_normalize(simd_cross(p1 - p0, p2 - p0))
            bodyPositions += [SCNVector3(p0), SCNVector3(p1), SCNVector3(p2)]
            bodyNormals   += [SCNVector3(n), SCNVector3(n), SCNVector3(n)]
        }
        let bodyPosSource = SCNGeometrySource(vertices: bodyPositions)
        let bodyNormSource = SCNGeometrySource(normals: bodyNormals)
        let bodyIndices: [Int32] = (0..<Int32(bodyPositions.count)).map { $0 }
        let bodyElement = SCNGeometryElement(indices: bodyIndices, primitiveType: .triangles)
        let bodyGeometry = SCNGeometry(sources: [bodyPosSource, bodyNormSource], elements: [bodyElement])

        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = ivoryColor
        bodyMat.roughness.contents = 0.40
        bodyGeometry.materials = [bodyMat]

        let node = SCNNode(geometry: bodyGeometry)
        node.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)

        // One textured triangle child per face. Each is a 3-vertex single-element
        // geometry sitting just outside the body face along its outward normal.
        let outwardOffset: Float = 0.005
        let inset: Float = 1.02  // slight overshoot past the body face so trimming imperfections in the asset don't show as an ivory sliver

        for face in faces {
            let p0 = v[face.verts[0]]
            let p1 = v[face.verts[1]]
            let p2 = v[face.verts[2]]
            let outNormal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
            let centroid = (p0 + p1 + p2) / 3.0
            let q0 = centroid + (p0 - centroid) * inset + outNormal * outwardOffset
            let q1 = centroid + (p1 - centroid) * inset + outNormal * outwardOffset
            let q2 = centroid + (p2 - centroid) * inset + outNormal * outwardOffset

            let positions: [SCNVector3] = [SCNVector3(q0), SCNVector3(q1), SCNVector3(q2)]
            let normals:   [SCNVector3] = Array(repeating: SCNVector3(outNormal), count: 3)
            // The asset images are sized so the triangle vertices sit on the image
            // edges (apex at top-center, base verts at the bottom corners). Y is
            // flipped from the "obvious" Y-up mapping because SceneKit samples the
            // UIImage texture with the image's Y axis pointing down here.
            let uvs: [CGPoint] = [
                CGPoint(x: 0.5, y: 0.0),  // verts[0] → 3D apex (image top-center)
                CGPoint(x: 0.0, y: 1.0),  // verts[1] → 3D bottom-left (image bottom-left)
                CGPoint(x: 1.0, y: 1.0)   // verts[2] → 3D bottom-right (image bottom-right)
            ]
            let posSource = SCNGeometrySource(vertices: positions)
            let normSource = SCNGeometrySource(normals: normals)
            let uvSource = SCNGeometrySource(textureCoordinates: uvs)
            let element = SCNGeometryElement(
                indices: [Int32(0), Int32(1), Int32(2)],
                primitiveType: .triangles
            )
            let faceGeometry = SCNGeometry(
                sources: [posSource, normSource, uvSource],
                elements: [element]
            )

            let mat = SCNMaterial()
            // Prefer hand-designed face textures from the asset catalog; fall back to
            // the runtime generator for any face whose asset isn't in place yet.
            if let assetImage = UIImage(named: "d4-face-\(face.number)") {
                mat.diffuse.contents = assetImage
            } else {
                mat.diffuse.contents = Self.makeD4FaceImage(
                    top:         face.verts[0] + 1,
                    bottomLeft:  face.verts[1] + 1,
                    bottomRight: face.verts[2] + 1
                )
            }
            mat.roughness.contents = 0.45
            mat.isDoubleSided = false
            faceGeometry.materials = [mat]

            node.addChildNode(SCNNode(geometry: faceGeometry))
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

    private var ivoryColor: UIColor {
        UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
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

    /// Paints the three numbers that belong on a d4 face — one per corner, each
    /// rotated so its "top" points outward toward its corner. UV layout in
    /// `createD4Node` maps verts[0]→top, verts[1]→bottom-left, verts[2]→bottom-right.
    ///
    /// Rotated text is drawn by first rendering the digit to a small bitmap (upright),
    /// then re-drawing that bitmap with a CGAffineTransform. This avoids the brittle
    /// interaction between NSAttributedString.draw and a transformed CGContext.
    private static func makeD4FaceImage(top: Int, bottomLeft: Int, bottomRight: Int) -> UIImage {
        let pixelSize: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        return renderer.image { ctx in
            // Ivory background. Only the inscribed equilateral triangle is sampled
            // onto the face; pixels outside the triangle never render.
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize)))

            // 70% of the way from triangle centroid to each corner, in image pixels.
            // Rotations make each digit's "top" point outward toward its corner so it
            // reads upright when that vertex is the apex of the die at rest.
            let entries: [(digit: Int, position: CGPoint, rotation: CGFloat)] = [
                (top,         CGPoint(x: pixelSize * 0.50, y: pixelSize * 0.30),  0),
                (bottomLeft,  CGPoint(x: pixelSize * 0.15, y: pixelSize * 0.91),  2 * .pi / 3),
                (bottomRight, CGPoint(x: pixelSize * 0.85, y: pixelSize * 0.91), -2 * .pi / 3)
            ]

            for entry in entries {
                let glyph = makeDigitGlyphImage(digit: entry.digit)
                drawImage(glyph, centeredAt: entry.position, rotation: entry.rotation, in: ctx.cgContext)
            }
        }
    }

    /// Renders a single digit as an upright bitmap on a transparent background. Sized
    /// to a square so the bitmap can be rotated about its center cleanly.
    private static func makeDigitGlyphImage(digit: Int) -> UIImage {
        let glyphSize: CGFloat = 96
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: glyphSize, height: glyphSize))
        return renderer.image { _ in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 70, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: "\(digit)", attributes: attrs)
            let size = str.size()
            str.draw(at: CGPoint(x: (glyphSize - size.width) / 2,
                                 y: (glyphSize - size.height) / 2))
        }
    }

    /// Draws a UIImage centered at `position`, rotated about that center by `rotation`
    /// radians (CGContext convention: positive = visual clockwise in Y-down image space).
    private static func drawImage(_ image: UIImage, centeredAt position: CGPoint, rotation: CGFloat, in cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: position.x, y: position.y)
        cg.rotate(by: rotation)
        let size = image.size
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        if let cgImage = image.cgImage {
            // CGContext.draw flips Y, which is corrected here so the bitmap appears upright.
            cg.saveGState()
            cg.translateBy(x: 0, y: rect.midY * 2)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(cgImage, in: rect)
            cg.restoreGState()
        }
        cg.restoreGState()
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

    /// Add or remove dice to match the requested count and kind. Switching kinds clears
    /// all existing dice and recreates them in the new shape; same-kind changes
    /// add/remove only the delta.
    func setDice(count: Int, kind: Dice3DKind) {
        if dice.contains(where: { $0.kind != kind }) {
            for die in dice { die.node.removeFromParentNode() }
            dice.removeAll()
        }

        let target = max(0, count)

        while dice.count > target {
            let removed = dice.removeLast()
            removed.node.removeFromParentNode()
        }

        while dice.count < target {
            let node = createDieNode(kind: kind)
            node.position = findEmptyTrayPosition()
            node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
            scene.rootNode.addChildNode(node)
            dice.append(ManagedDie(node: node, kind: kind, formulaIndex: -1, hasSettled: true, stillFrameCount: 0, rolledFace: nil))
        }
    }

    /// Formula-driven population. Clears the existing dice and rebuilds one node per
    /// die in the formula, tagging each with its position in the flat dice list
    /// (groups expanded in order). Groups whose kind isn't supported in 3D are
    /// silently skipped — callers should pre-validate via `Dice3DKind(_:)`.
    func setDice(formula: DiceFormula) {
        for die in dice { die.node.removeFromParentNode() }
        dice.removeAll()

        var formulaIndex = 0
        for group in formula.groups {
            guard let kind = Dice3DKind(group.kind) else {
                // Skip unsupported kinds. Caller is expected to have filtered these out
                // already, but we tolerate them here so a stale formula can't crash.
                formulaIndex += group.count
                continue
            }
            for _ in 0..<group.count {
                let node = createDieNode(kind: kind)
                node.position = findEmptyTrayPosition()
                node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
                scene.rootNode.addChildNode(node)
                dice.append(ManagedDie(
                    node: node, kind: kind, formulaIndex: formulaIndex,
                    hasSettled: true, stillFrameCount: 0, rolledFace: nil
                ))
                formulaIndex += 1
            }
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
        // Invalidate any pending settle-delay tasks from a prior roll so they
        // don't write stale face values into the new roll's state.
        currentRollId += 1

        for i in dice.indices {
            dice[i].hasSettled = false
            dice[i].stillFrameCount = 0
            dice[i].rolledFace = nil
            // Reset opacity in case the die was dimmed by a previous roll's modifier.
            dice[i].node.opacity = 1.0
            throwDieImpulse(at: i)
        }

        allSettledCallback = onAllSettled
        isAwaitingRest = true
        rollStartTime = CACurrentMediaTime()
    }

    /// Re-throw a subset of dice (identified by their `formulaIndex`). Dice not in the
    /// set keep their existing rolled-face values; once the re-thrown dice settle,
    /// `onAllSettled` fires with the updated full result array in formula order.
    /// Used to implement the `r2` (reroll-once-if-at-most) modifier physically.
    func rethrowDice(at formulaIndices: Set<Int>, onAllSettled: @escaping @MainActor ([Int]) -> Void) {
        guard !formulaIndices.isEmpty else {
            onAllSettled(dice.map { $0.rolledFace ?? 0 })
            return
        }
        currentRollId += 1

        for i in dice.indices {
            guard formulaIndices.contains(dice[i].formulaIndex) else { continue }
            dice[i].hasSettled = false
            dice[i].stillFrameCount = 0
            dice[i].rolledFace = nil
            dice[i].node.opacity = 1.0
            throwDieImpulse(at: i)
        }

        allSettledCallback = onAllSettled
        isAwaitingRest = true
        rollStartTime = CACurrentMediaTime()
    }

    /// Animate dice opacity to mark a kept/dropped state for keep/drop modifiers.
    /// Pass the set of formula indices that should be dimmed; everything else snaps
    /// back to fully opaque. Animated over 0.2s for a soft fade.
    func setDimmed(formulaIndices: Set<Int>, dimOpacity: CGFloat = 0.25) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        for die in dice {
            die.node.opacity = formulaIndices.contains(die.formulaIndex) ? dimOpacity : 1.0
        }
        SCNTransaction.commit()
    }

    /// Per-die throw impulse — extracted so it can be reused by both `rollAll` (for the
    /// whole tray) and `rethrowDice` (for the subset that triggered a reroll modifier).
    private func throwDieImpulse(at index: Int) {
        let node = dice[index].node
        guard let body = node.physicsBody else { return }
        body.velocity = SCNVector3Zero
        body.angularVelocity = SCNVector4Zero

        node.position = SCNVector3(
            Float.random(in: -1.5...1.5),
            5 + Float(index) * 0.25,
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
            Float.random(in: -10...10),
            Float.random(in: 18...26),
            Float.random(in: -10...10)
        )
        body.applyForce(force, asImpulse: true)
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
            // Threshold accommodates both d6 (rests at y≈0.85) and d4 (rests at y≈0.49).
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

    }

    /// Mark the die as settled immediately so the tick loop stops processing it,
    /// then wait `settleDelay` before snapshotting its face — both because d4s can
    /// balance on an edge briefly before tipping, and because the user wants the
    /// total to update only after a beat of stillness. The all-settled callback
    /// fires from inside the delayed task once every die has a face value.
    private func settleDie(at index: Int) {
        dice[index].hasSettled = true
        let nodeRef = dice[index].node
        let rollId = currentRollId
        let delay = settleDelay

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.currentRollId == rollId else { return }
            guard let i = self.dice.firstIndex(where: { $0.node === nodeRef }) else { return }

            let face = self.detectResult(of: self.dice[i])
            self.dice[i].rolledFace = face
            self.onDieSettled?(i, face)

            if self.dice.allSatisfy({ $0.rolledFace != nil }) {
                self.isAwaitingRest = false
                let cb = self.allSettledCallback
                self.allSettledCallback = nil
                cb?(self.dice.compactMap { $0.rolledFace })
            }
        }
    }

    /// Computes the rolled value from the die's rest orientation. For a d6 the result
    /// is the face whose normal points most upward in world space (the visible top
    /// face). For a d4 there is no top face — the cube rests on a face with a vertex
    /// pointing up — so the result is the face on the BOTTOM (whose normal points
    /// most downward in world space).
    private func detectResult(of die: ManagedDie) -> Int {
        let q = die.node.presentation.simdOrientation
        let target: SIMD3<Float>
        switch die.kind {
        case .d4: target = [0, -1, 0]   // bottom face = result
        case .d6: target = [0,  1, 0]   // top face = result
        }

        var best = 1
        var bestDot: Float = -2
        for face in Self.faceSpecs(for: die.kind) {
            let world = q.act(face.normal)
            let d = simd_dot(world, target)
            if d > bestDot {
                bestDot = d
                best = face.number
            }
        }
        return best
    }
}
