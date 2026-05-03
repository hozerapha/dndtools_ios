import SwiftUI
import SceneKit
import simd

// MARK: - Dice kinds

enum Dice3DKind: String, CaseIterable, Identifiable {
    case d4
    case d6
    case d8
    case d10

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var sides: Int {
        switch self {
        case .d4:  return 4
        case .d6:  return 6
        case .d8:  return 8
        case .d10: return 10
        }
    }

    /// Bridges from the project-wide `DieKind` (which spans d4–d100) to the subset
    /// the 3D scene currently knows how to model. Returns nil for unsupported kinds.
    init?(_ kind: DieKind) {
        switch kind {
        case .d4:  self = .d4
        case .d6:  self = .d6
        case .d8:  self = .d8
        case .d10: self = .d10
        default:   return nil
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
    /// die has been at rest for `requiredAllStillDuration` and face values have
    /// been read.
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
        var rolledFace: Int?
        /// Snapshot from the previous rest-detection tick. `nil` immediately after a
        /// (re)throw; populated on the first tick afterward. Compared frame-to-frame
        /// to detect ANY positional or rotational change — even sub-physics-threshold
        /// drift counts as motion and resets the all-still streak.
        var lastPosition: SCNVector3?
        var lastOrientation: simd_quatf?
    }

    private var dice: [ManagedDie] = []

    /// Number of dice currently in the scene. Lets callers do idempotent setup
    /// (e.g. only call `setDice(formula:)` on the first view appearance) without
    /// peeking at the private collection.
    var diceCount: Int { dice.count }

    private var allSettledCallback: (@MainActor ([Int]) -> Void)?
    private var isAwaitingRest = false
    private var rollStartTime: TimeInterval = 0
    /// Bumped on every `rollAll`/`rethrowDice` so any in-flight async work from a
    /// prior roll knows to bail out instead of writing stale face values.
    private var currentRollId: Int = 0

    // MARK: - Rest detection thresholds
    //
    // We require every die in the scene to register as still — both by physics
    // velocity AND by frame-to-frame coordinate change — continuously for
    // `requiredAllStillDuration` before snapshotting any face values. Per-die
    // settling was previously used, but it could lock in a die's orientation
    // moments before a still-rolling neighbour bumped it, leaving the displayed
    // value out of sync with the visible face. The all-still gate trades a small
    // extra wait for guaranteed agreement between read and visual state.
    private let requiredAllStillDuration: TimeInterval = 0.5
    private let restSpeedThreshold: Float = 0.05
    private let restAngularThreshold: Float = 0.10
    private let posStillEpsilon: Float = 0.0005
    /// |dot(q, q_prev)| above this means the orientation hasn't changed perceptibly
    /// (≈0.014 rad / 0.8°). Quaternions q and -q describe the same rotation, hence
    /// the abs.
    private let orientStillDotThreshold: Float = 0.99999
    private let minRollDuration: TimeInterval = 0.30

    /// Timestamp at which the current "all dice still" streak began. `nil` whenever
    /// at least one die failed the still check on the most recent tick.
    private var allStillSince: TimeInterval?

    private var restPollTask: Task<Void, Never>?

    // d6 geometry constants
    private let cubeSize: Float = 1.7
    private var cubeHalfSize: Float { cubeSize / 2 }

    // d4 geometry constants — vertices at scale·(±1,±1,±1) alternating-corners-of-cube,
    // giving a regular tetrahedron with circumscribed-sphere radius scale·√3.
    // Picked so the d4 has a similar bounding sphere to the d6.
    private let d4Scale: Float = 0.85

    // d8 geometry constant — vertices on the axes at ±d8Scale (regular octahedron).
    // Picked so the d8 has a face-to-face (inradius) distance similar to the d6
    // cube: 2·d8Scale/√3 ≈ d6's cubeSize when d8Scale ≈ cubeSize·√3/2.
    private let d8Scale: Float = 1.5

    // d10 geometry — pentagonal trapezohedron. 12 vertices: top apex at +d10H,
    // bottom apex at -d10H, plus two zig-zag rings of 5 equatorial vertices at
    // radius d10R and heights ±d10e (offset 36° between rings). The H/e ratio is
    // CONSTRAINED: for the 10 kite faces to be planar (which is what makes it a
    // proper pentagonal trapezohedron), H/e must equal (1+cos β)/(1−cos β) where
    // β = π/5 ≈ 36°. That works out to ≈9.47, so d10H ≈ 9.47 · d10e. Bounding box
    // ≈ 1.7 wide × 1.9 tall — close to the d6 cube width.
    private let d10R: Float = 0.85
    private let d10e: Float = 0.10
    private let d10H: Float = 0.95

    /// Each face stores its number and its outward normal in die-local frame.
    private struct FaceSpec {
        let number: Int
        let normal: SIMD3<Float>
    }

    /// Face layout for a kind. The visual texture/plane sits along the face's outward
    /// normal. Instance method (rather than static) so the d10 case can read this
    /// scene's d10R/d10e/d10H — the kite face normals' tilt depends on those.
    private func faceSpecs(for kind: Dice3DKind) -> [FaceSpec] {
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
        case .d8:
            // Outward normals for the 8 faces of a regular octahedron — each face
            // points into one of the 8 (±X, ±Y, ±Z) octants. Numbered so opposite
            // faces sum to 9 (standard d8 convention: 1↔8, 2↔7, 3↔6, 4↔5).
            let inv = 1.0 / sqrtf(3)
            return [
                FaceSpec(number: 1, normal: SIMD3( inv,  inv,  inv)),
                FaceSpec(number: 2, normal: SIMD3( inv, -inv,  inv)),
                FaceSpec(number: 3, normal: SIMD3( inv, -inv, -inv)),
                FaceSpec(number: 4, normal: SIMD3( inv,  inv, -inv)),
                FaceSpec(number: 5, normal: SIMD3(-inv, -inv,  inv)),
                FaceSpec(number: 6, normal: SIMD3(-inv,  inv,  inv)),
                FaceSpec(number: 7, normal: SIMD3(-inv,  inv, -inv)),
                FaceSpec(number: 8, normal: SIMD3(-inv, -inv, -inv))
            ]
        case .d10:
            // 10 kite faces in two zig-zag rings of 5. Each upper kite uses the top
            // apex T and points outward at angle (2k+1)·36° in XZ, tilted up by a Y
            // component determined by the (e+H):R aspect ratio. Lower kites mirror
            // across the equator with a 36° rotational offset.
            //
            // Numbering puts 1..5 on the upper ring; lower ring is arranged so
            // opposite faces sum to 11 (standard 1–10 d10 convention). Upper_k is
            // opposite Lower_{(k+2) mod 5}, so Lower numbers are
            // [Lower_0..Lower_4] = [11-(Upper_3), 11-(Upper_4), 11-(Upper_0),
            //                       11-(Upper_1), 11-(Upper_2)] = [7, 6, 10, 9, 8].
            let beta = Float.pi / 5
            let denom = sqrtf((d10e + d10H) * (d10e + d10H) + d10R * d10R)
            let horiz = (d10e + d10H) / denom
            let vert  = d10R / denom
            let upperNumbers = [1, 2, 3, 4, 5]
            let lowerNumbers = [7, 6, 10, 9, 8]
            var specs: [FaceSpec] = []
            for k in 0..<5 {
                let angle = Float(2 * k + 1) * beta
                specs.append(FaceSpec(
                    number: upperNumbers[k],
                    normal: SIMD3(horiz * cosf(angle), vert, horiz * sinf(angle))
                ))
            }
            for k in 0..<5 {
                let angle = Float(2 * k + 2) * beta
                specs.append(FaceSpec(
                    number: lowerNumbers[k],
                    normal: SIMD3(horiz * cosf(angle), -vert, horiz * sinf(angle))
                ))
            }
            return specs
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
        case .d4:  return createD4Node()
        case .d6:  return createD6Node()
        case .d8:  return createD8Node()
        case .d10: return createD10Node()
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

        // Plane child per face. Sized to match the cube face exactly so hand-designed
        // textures (512×512 in the asset catalog) cover the whole visible face without
        // an ivory border. The 0.005 outward offset hides z-fighting against the body.
        let planeSize = CGFloat(cubeSize) * 1.02
        for face in faceSpecs(for: .d6) {
            let plane = SCNPlane(width: planeSize, height: planeSize)
            let mat = SCNMaterial()
            // Prefer hand-designed face textures from the asset catalog; fall back
            // to the runtime pip generator for any face whose asset isn't present.
            mat.diffuse.contents = UIImage(named: "d6-face-\(face.number)")
                ?? Self.makePipImage(faceNumber: face.number)
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

    /// Builds a regular octahedron with 6 vertices on the axes at ±d8Scale. Same
    /// pattern as createD4Node — one ivory body geometry handles physics + base
    /// color, and 8 child triangle nodes overlay each face with its own UV-mapped
    /// texture. d8 result-detection is "top face up" (parallel face on top), so
    /// face textures show a single number that reads upright when that face is
    /// facing the camera.
    private func createD8Node() -> SCNNode {
        let s = d8Scale
        // 6 vertices, one on each end of the three axes.
        let v: [SIMD3<Float>] = [
            SIMD3( 1,  0,  0) * s,  // 0
            SIMD3(-1,  0,  0) * s,  // 1
            SIMD3( 0,  1,  0) * s,  // 2
            SIMD3( 0, -1,  0) * s,  // 3
            SIMD3( 0,  0,  1) * s,  // 4
            SIMD3( 0,  0, -1) * s   // 5
        ]
        // 8 faces, each picking one X-axis, one Y-axis, and one Z-axis vertex.
        // Numbering matches faceSpecs(for: .d8) so detection lines up with rendering.
        // Winding gives outward-facing normals (verified by cross product sign).
        let faces: [(verts: [Int], number: Int)] = [
            (verts: [0, 2, 4], number: 1),  // outward (+,+,+)
            (verts: [0, 4, 3], number: 2),  // outward (+,-,+)
            (verts: [0, 3, 5], number: 3),  // outward (+,-,-)
            (verts: [0, 5, 2], number: 4),  // outward (+,+,-)
            (verts: [1, 3, 4], number: 5),  // outward (-,-,+)
            (verts: [1, 4, 2], number: 6),  // outward (-,+,+)
            (verts: [1, 2, 5], number: 7),  // outward (-,+,-)
            (verts: [1, 5, 3], number: 8)   // outward (-,-,-)
        ]

        // Body geometry — single element, single ivory material. Convex-hull
        // physics inferred from the 6 unique vertex positions.
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

        // One textured triangle child per face, sitting just outside the body face
        // along its outward normal. Same UV layout as d4 (apex at image top-center,
        // base verts at image bottom corners) so designers can use a similar art
        // template for both kinds.
        let outwardOffset: Float = 0.005
        let inset: Float = 1.02

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
            let uvs: [CGPoint] = [
                CGPoint(x: 0.5, y: 0.0),
                CGPoint(x: 0.0, y: 1.0),
                CGPoint(x: 1.0, y: 1.0)
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
            // a simple centered-digit image until those textures are added.
            mat.diffuse.contents = UIImage(named: "d8-face-\(face.number)")
                ?? Self.makeD8FallbackImage(number: face.number)
            mat.roughness.contents = 0.45
            mat.isDoubleSided = false
            faceGeometry.materials = [mat]

            node.addChildNode(SCNNode(geometry: faceGeometry))
        }

        return node
    }

    /// Builds a pentagonal trapezohedron (10 kite faces in two zig-zag rings of 5).
    /// Same body+children pattern as createD4Node / createD8Node — one ivory body
    /// geometry handles the convex-hull physics and base color, then 10 textured
    /// child nodes overlay each kite face. Each kite is triangulated into 2 tris
    /// along its long pole-to-far diagonal; UVs map the 4 kite verts to the four
    /// edge-midpoints of the texture (rotated-square inscribed in a unit square),
    /// so a designer can use a 512×512 square asset with the digit centered.
    private func createD10Node() -> SCNNode {
        let R = d10R, e = d10e, H = d10H
        let beta = Float.pi / 5  // 36°

        // 12 vertices: 2 polar + 5 upper-ring + 5 lower-ring (offset 36° between rings).
        let T = SIMD3<Float>(0,  H, 0)
        let B = SIMD3<Float>(0, -H, 0)
        var U: [SIMD3<Float>] = []
        var L: [SIMD3<Float>] = []
        for k in 0..<5 {
            let aU = Float(2 * k) * beta       // 0°, 72°, 144°, 216°, 288°
            let aL = Float(2 * k + 1) * beta   // 36°, 108°, 180°, 252°, 324°
            U.append(SIMD3(R * cosf(aU),  e, R * sinf(aU)))
            L.append(SIMD3(R * cosf(aL), -e, R * sinf(aL)))
        }

        // 10 kite faces. Each kite has a "pole" (T or B), a "far" vertex on the
        // opposite ring, and two "wings" — adjacent equator vertices on the pole's
        // ring. Numbers chosen so opposite faces sum to 11; see faceSpecs(.d10).
        struct Kite {
            let pole: SIMD3<Float>
            let wing1: SIMD3<Float>
            let far: SIMD3<Float>
            let wing2: SIMD3<Float>
            let number: Int
            let isUpper: Bool
        }
        let upperNumbers = [1, 2, 3, 4, 5]
        let lowerNumbers = [7, 6, 10, 9, 8]
        var kites: [Kite] = []
        for k in 0..<5 {
            kites.append(Kite(
                pole:  T,           wing1: U[k],
                far:   L[k],        wing2: U[(k + 1) % 5],
                number: upperNumbers[k], isUpper: true
            ))
        }
        for k in 0..<5 {
            kites.append(Kite(
                pole:  B,           wing1: L[k],
                far:   U[(k + 1) % 5], wing2: L[(k + 1) % 5],
                number: lowerNumbers[k], isUpper: false
            ))
        }

        // Outward triangle winding differs between upper and lower kites because the
        // perimeter order (pole → wing1 → far → wing2) wraps opposite ways relative
        // to each kite's outward normal.
        func outwardNormal(of kite: Kite) -> SIMD3<Float> {
            kite.isUpper
                ? simd_normalize(simd_cross(kite.far - kite.pole, kite.wing1 - kite.pole))
                : simd_normalize(simd_cross(kite.wing1 - kite.pole, kite.far - kite.pole))
        }

        // Body geometry — single ivory mesh, two triangles per kite, all 60 vertex
        // entries laid out flat (each face shares one normal across its 6 entries
        // for flat shading). SceneKit infers convex-hull physics from these positions.
        var bodyPositions: [SCNVector3] = []
        var bodyNormals: [SCNVector3] = []
        for kite in kites {
            let n = outwardNormal(of: kite)
            let nv = SCNVector3(n)
            if kite.isUpper {
                bodyPositions += [SCNVector3(kite.pole), SCNVector3(kite.far),  SCNVector3(kite.wing1)]
                bodyPositions += [SCNVector3(kite.pole), SCNVector3(kite.wing2), SCNVector3(kite.far)]
            } else {
                bodyPositions += [SCNVector3(kite.pole), SCNVector3(kite.wing1), SCNVector3(kite.far)]
                bodyPositions += [SCNVector3(kite.pole), SCNVector3(kite.far),   SCNVector3(kite.wing2)]
            }
            bodyNormals += Array(repeating: nv, count: 6)
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

        // One textured child per kite, sitting just outside the body face along its
        // outward normal. UV layout is GEOMETRY-AWARE — for any planar pentagonal
        // trapezohedron the wings sit ≈81% down the long diagonal (cos 36° rooted),
        // not at its midpoint. Texture assets are expected to match the kite's
        // bounding-box aspect ratio (short:long ≈ 0.74:1, so a 378×512 PNG fills
        // the kite edge-to-edge with no padding). With that convention the long
        // diagonal spans the full image height (pole at v=0, far at v=1) AND the
        // short diagonal spans the full image width (wings at u=0 / u=1), so the
        // texture maps onto the face without horizontal or vertical stretch.
        let longDiagSq = d10R * d10R + (d10e + d10H) * (d10e + d10H)
        let wingV = (d10R * d10R * cosf(beta) + d10H * d10H - d10e * d10e) / longDiagSq
        let outwardOffset: Float = 0.005
        let inset: Float = 1.02

        let uvPole  = CGPoint(x: 0.5, y: 0.0)
        let uvWing1 = CGPoint(x: 1.0, y: CGFloat(wingV))
        let uvFar   = CGPoint(x: 0.5, y: 1.0)
        let uvWing2 = CGPoint(x: 0.0, y: CGFloat(wingV))

        for kite in kites {
            let outNormal = outwardNormal(of: kite)
            let centroid = (kite.pole + kite.wing1 + kite.far + kite.wing2) / 4.0
            func shift(_ v: SIMD3<Float>) -> SIMD3<Float> {
                centroid + (v - centroid) * inset + outNormal * outwardOffset
            }
            let qPole  = shift(kite.pole)
            let qWing1 = shift(kite.wing1)
            let qFar   = shift(kite.far)
            let qWing2 = shift(kite.wing2)

            let positions: [SCNVector3]
            let uvs: [CGPoint]
            if kite.isUpper {
                positions = [
                    SCNVector3(qPole), SCNVector3(qFar),   SCNVector3(qWing1),
                    SCNVector3(qPole), SCNVector3(qWing2), SCNVector3(qFar)
                ]
                uvs = [
                    uvPole, uvFar,   uvWing1,
                    uvPole, uvWing2, uvFar
                ]
            } else {
                positions = [
                    SCNVector3(qPole), SCNVector3(qWing1), SCNVector3(qFar),
                    SCNVector3(qPole), SCNVector3(qFar),   SCNVector3(qWing2)
                ]
                // Lower kites are mirrored across the equator relative to upper
                // kites, so their perimeter order winds the opposite way: wing1
                // (L_k) sits on the visual LEFT and wing2 (L_{k+1}) on the RIGHT
                // when viewing the face from outside, the reverse of upper kites.
                // Swap the wing UVs here so 6–10 don't render horizontally flipped.
                uvs = [
                    uvPole, uvWing2, uvFar,
                    uvPole, uvFar,   uvWing1
                ]
            }
            let normals: [SCNVector3] = Array(repeating: SCNVector3(outNormal), count: 6)

            let posSource = SCNGeometrySource(vertices: positions)
            let normSource = SCNGeometrySource(normals: normals)
            let uvSource = SCNGeometrySource(textureCoordinates: uvs)
            let element = SCNGeometryElement(
                indices: (0..<Int32(positions.count)).map { $0 },
                primitiveType: .triangles
            )
            let faceGeometry = SCNGeometry(
                sources: [posSource, normSource, uvSource],
                elements: [element]
            )

            let mat = SCNMaterial()
            mat.diffuse.contents = UIImage(named: String(format: "d10-face-%02d", kite.number))
                ?? Self.makeD10FallbackImage(number: kite.number)
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

    /// Placeholder d8 face texture used until the user adds `d8-face-N` assets.
    /// Single digit, centered in the visible triangle (~2/3 down the image to land
    /// near the inscribed-triangle centroid in image space).
    private static func makeD8FallbackImage(number: Int) -> UIImage {
        let pixelSize: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize)))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 110, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: "\(number)", attributes: attrs)
            let size = str.size()
            // Triangle's centroid in image space is roughly (0.5W, 2H/3) given the
            // UV mapping (apex at image top-center, base verts at image bottom corners).
            str.draw(at: CGPoint(
                x: (pixelSize - size.width) / 2,
                y: pixelSize * 2 / 3 - size.height / 2
            ))
        }
    }

    /// Placeholder d10 face texture used until the user adds `d10-face-N` assets.
    /// Canvas matches the kite's bounding-box aspect ratio (~189×256, the same
    /// 0.74:1 short-to-long-diagonal ratio as a 378×512 hand-drawn asset) so the
    /// digit isn't horizontally squashed or vertically stretched on the face.
    /// The digit sits at the kite's actual centroid (v ≈ 0.655), not the image
    /// center, since the kite is bottom-heavy — a dead-centre digit looks shifted
    /// upward on the face.
    private static func makeD10FallbackImage(number: Int) -> UIImage {
        let pixelHeight: CGFloat = 256
        let pixelWidth: CGFloat = 189   // ≈ pixelHeight × 0.74 (kite aspect ratio)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelWidth, height: pixelHeight))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 86, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: "\(number)", attributes: attrs)
            let size = str.size()
            let centroidV: CGFloat = 0.655
            str.draw(at: CGPoint(
                x: (pixelWidth - size.width) / 2,
                y: pixelHeight * centroidV - size.height / 2
            ))
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
            dice.append(ManagedDie(
                node: node, kind: kind, formulaIndex: -1,
                rolledFace: nil, lastPosition: nil, lastOrientation: nil
            ))
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
                    rolledFace: nil, lastPosition: nil, lastOrientation: nil
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

    /// Roll every die in the scene. `onAllSettled` fires once every die has been
    /// continuously at rest for `requiredAllStillDuration`, with face values in
    /// die-index order. `onDieSettled` fires for each die at that same moment.
    func rollAll(onAllSettled: @escaping @MainActor ([Int]) -> Void) {
        guard !dice.isEmpty else { onAllSettled([]); return }
        currentRollId += 1

        for i in dice.indices {
            dice[i].rolledFace = nil
            dice[i].lastPosition = nil
            dice[i].lastOrientation = nil
            // Reset opacity in case the die was dimmed by a previous roll's modifier.
            dice[i].node.opacity = 1.0
            throwDieImpulse(at: i)
        }

        allSettledCallback = onAllSettled
        isAwaitingRest = true
        allStillSince = nil
        rollStartTime = CACurrentMediaTime()
    }

    /// Re-throw a subset of dice (identified by their `formulaIndex`). All dice in
    /// the scene must subsequently be still for `requiredAllStillDuration` —
    /// including any neighbours nudged by the rethrown dice — before `onAllSettled`
    /// fires with the updated full result array in formula order. Used to implement
    /// the `r2` (reroll-once-if-at-most) modifier physically.
    func rethrowDice(at formulaIndices: Set<Int>, onAllSettled: @escaping @MainActor ([Int]) -> Void) {
        guard !formulaIndices.isEmpty else {
            onAllSettled(dice.map { $0.rolledFace ?? 0 })
            return
        }
        currentRollId += 1

        for i in dice.indices {
            // Snapshots get reset for ALL dice — even ones we're not re-throwing —
            // so the all-still streak restarts from a clean slate. A neighbour bumped
            // by a re-thrown die needs to fail its first stillness check, not pass it
            // because its old snapshot still happens to match.
            dice[i].lastPosition = nil
            dice[i].lastOrientation = nil
            guard formulaIndices.contains(dice[i].formulaIndex) else { continue }
            dice[i].rolledFace = nil
            dice[i].node.opacity = 1.0
            throwDieImpulse(at: i)
        }

        allSettledCallback = onAllSettled
        isAwaitingRest = true
        allStillSince = nil
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
            Float.random(in: 8...14),
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

    /// Per-tick check: each die's current position+orientation are compared to the
    /// previous tick's snapshot, AND its physics velocities are checked against the
    /// rest thresholds. A die is "still" only if BOTH agree it hasn't moved.
    /// Once EVERY die in the scene has been still continuously for
    /// `requiredAllStillDuration`, all face values are read in one pass.
    ///
    /// Per-die settling was tried first but kept locking in values for dice that a
    /// still-rolling neighbour later bumped, leaving the displayed total out of sync
    /// with the visible dice. Waiting for global stillness costs a small extra beat
    /// but guarantees what the player sees matches what the app records.
    private func tickRestDetection() {
        guard isAwaitingRest, !dice.isEmpty else { return }
        let now = CACurrentMediaTime()
        guard now - rollStartTime > minRollDuration else { return }

        var allStill = true
        for i in dice.indices {
            let pres = dice[i].node.presentation
            let pos = pres.position
            let orient = pres.simdOrientation

            var dieStill = true
            if let prevPos = dice[i].lastPosition, let prevOrient = dice[i].lastOrientation {
                let dx = pos.x - prevPos.x
                let dy = pos.y - prevPos.y
                let dz = pos.z - prevPos.z
                let posDelta = sqrtf(dx * dx + dy * dy + dz * dz)
                let orientDot = abs(simd_dot(orient.vector, prevOrient.vector))
                if posDelta > posStillEpsilon || orientDot < orientStillDotThreshold {
                    dieStill = false
                }
            } else {
                // No prior snapshot — first tick after a (re)throw, treat as moving
                // so the streak doesn't start on stale state.
                dieStill = false
            }

            if dieStill, let body = dice[i].node.physicsBody {
                let v = body.velocity
                let speed = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z)
                let angularSpeed = abs(body.angularVelocity.w)
                if speed > restSpeedThreshold || angularSpeed > restAngularThreshold {
                    dieStill = false
                }
            }

            // Update snapshot every tick regardless — next tick compares against this.
            dice[i].lastPosition = pos
            dice[i].lastOrientation = orient

            if !dieStill { allStill = false }
        }

        if allStill {
            if allStillSince == nil {
                allStillSince = now
            } else if now - allStillSince! >= requiredAllStillDuration {
                settleAllDice()
            }
        } else {
            allStillSince = nil
        }
    }

    /// All dice have been completely still for the required duration — snapshot
    /// each face value in one pass and fire the all-settled callback. Called only
    /// from `tickRestDetection`; do not call directly.
    private func settleAllDice() {
        isAwaitingRest = false
        allStillSince = nil

        var values: [Int] = []
        for i in dice.indices {
            let face = detectResult(of: dice[i])
            dice[i].rolledFace = face
            onDieSettled?(i, face)
            values.append(face)
        }

        let cb = allSettledCallback
        allSettledCallback = nil
        cb?(values)
    }

    /// Computes the rolled value from the die's rest orientation. For a d6 the result
    /// is the face whose normal points most upward in world space (the visible top
    /// face). For a d4 there is no top face — the cube rests on a face with a vertex
    /// pointing up — so the result is the face on the BOTTOM (whose normal points
    /// most downward in world space). d10 always rests on a kite with its parallel
    /// kite on top, so it follows the same top-face-up rule as d6/d8.
    private func detectResult(of die: ManagedDie) -> Int {
        let q = die.node.presentation.simdOrientation
        let target: SIMD3<Float>
        switch die.kind {
        case .d4:              target = [0, -1, 0]   // bottom face = result (no top face — vertex up)
        case .d6, .d8, .d10:   target = [0,  1, 0]   // top face = result (parallel face up)
        }

        var best = 1
        var bestDot: Float = -2
        for face in faceSpecs(for: die.kind) {
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
