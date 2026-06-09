import SwiftUI
import SceneKit
import simd

// MARK: - Dice kinds

enum Dice3DKind: String, CaseIterable, Identifiable {
    case d4
    case d6
    case d8
    case d10
    case d12
    case d20
    case d100

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var sides: Int {
        switch self {
        case .d4:   return 4
        case .d6:   return 6
        case .d8:   return 8
        case .d10:  return 10
        case .d12:  return 12
        case .d20:  return 20
        case .d100: return 100
        }
    }

    /// Compound kinds expand to multiple physical dice in the 3D scene rather
    /// than rendering as a single die. d100 is a real-world pair of d10s (a "ones"
    /// die labeled 0–9 and a "tens" die labeled 00–90), so each d100 in the
    /// formula spawns two d10 nodes that share a formula slot. Standalone kinds
    /// render as one physical die per formula entry.
    var isStandalone: Bool { self != .d100 }

    /// Bridges from the project-wide `DieKind` (which spans d4–d100) to the subset
    /// the 3D scene currently knows how to model. Returns nil for unsupported kinds.
    init?(_ kind: DieKind) {
        switch kind {
        case .d4:   self = .d4
        case .d6:   self = .d6
        case .d8:   self = .d8
        case .d10:  self = .d10
        case .d12:  self = .d12
        case .d20:  self = .d20
        case .d100: self = .d100
        default:    return nil
        }
    }
}

/// What role a physical die plays in the formula. `.standard` for everything
/// except d100 components; d100s spawn one `.d100Ones` (a normal d10 read 0–9)
/// and one `.d100Tens` (read 00–90) that share a formula slot. The role decides
/// which texture set to load and how the face value contributes to the combined
/// d100 result.
enum DieRole {
    case standard
    case d100Ones
    case d100Tens
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
                    // Compound kinds (d100) need formula context to spawn pairs and
                    // wire connectors, so the legacy playground picker only offers
                    // standalone kinds. The main DiceRollerView still surfaces d100.
                    ForEach(Dice3DKind.allCases.filter(\.isStandalone)) { kind in
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
    /// Pinch to zoom / drag to orbit / two-finger pan. Useful in the playground
    /// for inspecting geometry, but the main DiceRollerView turns it off so the
    /// press-and-hold magnifier gesture isn't fighting SCNView's own pan
    /// recognizer for the same touches.
    var allowsCameraControl: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = true
        // Transparent so the SwiftUI/system background shows through behind the
        // tray — meshes with both light and dark mode without hard-coding a color.
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isPlaying = true
        view.allowsCameraControl = allowsCameraControl
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

/// Renders the same `SCNScene` as `SceneKitView` but viewed through one of the
/// controller's magnifier cameras — a pointOfView positioned above the tapped
/// die looking straight down. Designed to be hosted inside a circular SwiftUI
/// clip shape for the "shopping-site magnifier" effect.
///
/// `slot` selects which magnifier camera to use; with a d100 pair we host TWO
/// of these side-by-side (slot 0 = tens, slot 1 = ones) so the user sees both
/// halves of the result at once. For standalone dice only slot 0 is used. The
/// caller is responsible for calling `controller.positionMagnifier(slot:
/// forDieIndex:)` for each slot before rendering — `MagnifierView` itself just
/// reads whatever camera state the controller currently holds.
struct MagnifierView: UIViewRepresentable {
    let controller: DiceSceneController
    var slot: Int = 0

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isPlaying = true
        view.allowsCameraControl = false
        controller.attachMagnifier(to: view, slot: slot)
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
    /// Parent node holding all d100 pair connector lines. Lives directly under
    /// the scene root so we can clear all connectors with one
    /// `childNodes.forEach { $0.removeFromParentNode() }`. Connectors are drawn
    /// inside `settleAllDice` once every die is at rest and cleared whenever the
    /// dice are about to move (rollAll, rethrowDice) or the formula changes.
    private var connectorContainer: SCNNode!
    /// Cameras used by the press-and-hold magnifier. Each lives in the same scene
    /// as the tray camera; a separate `SCNView` rendering the same scene with one
    /// of these as its `pointOfView` shows the inspected die from straight above.
    /// Sized for the largest formula slot we ever magnify — 2 cameras covers the
    /// d100 pair case, where a single tap on either die opens TWO overlays so the
    /// user can read the full ones+tens result. Standalone slots use only the
    /// first camera; the second sits unused. Repositioned per-press by
    /// `positionMagnifier(slot:forDieIndex:)` — no per-frame follow needed since
    /// the dice are settled when the magnifier is open.
    private var magnifierCameras: [SCNNode] = []
    private let defaultCameraPosition = SCNVector3(0, 22, 7.5)
    private let defaultCameraTarget   = SCNVector3(0, 0, 0)

    private struct ManagedDie {
        let node: SCNNode
        /// The physical 3D kind that's actually rendered. For d100 components this
        /// is `.d10` — d100s render as a pair of d10s, not as a single d100 node.
        let kind: Dice3DKind
        /// Most dice are `.standard`. d100 components are `.d100Ones` (read 0–9)
        /// or `.d100Tens` (read 00–90); a d100 pair shares one `formulaIndex`.
        let role: DieRole
        /// Position of this die in the formula's flat dice list (groups expanded
        /// in order). For d100 the two physical dice in a pair share the same
        /// `formulaIndex` — the result-combining loop pairs them up by it.
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

    // Real-world polyhedral dice have very different edge lengths per kind
    // (d4 ~22mm, d6 16mm, d8 ~16mm, d10 ~12mm). We anchor on the d6 (cubeSize)
    // and scale every other kind so its edge length is in the right physical
    // proportion to the d6 — otherwise mixed-die scenes look "wonky" (e.g. an
    // octahedron the same edge length as the cube would otherwise dwarf it).

    // d6 geometry constants — the size anchor for the proportions below.
    // Real d6 ≈ 16mm edge, so cubeSize ↔ 16mm.
    private let cubeSize: Float = 1.615
    private var cubeHalfSize: Float { cubeSize / 2 }

    // d4 — vertices at d4Scale·(±1,±1,±1) on alternating cube corners, giving a
    // regular tetrahedron with edge length 2·d4Scale·√2. Real d4 ≈ 22mm edge,
    // so we want edge ≈ 1.375·cubeSize ≈ 2.22. d4Scale = cubeSize·1.375/(2√2).
    private let d4Scale: Float = 0.79

    // d8 — vertices on the axes at ±d8Scale (regular octahedron) with edge
    // length d8Scale·√2. Real d8 ≈ 16mm edge (same as d6), so we want edge
    // ≈ cubeSize. d8Scale = cubeSize/√2.
    private let d8Scale: Float = 1.14

    // d10 — pentagonal trapezohedron. 12 vertices: top apex at +d10H, bottom
    // apex at -d10H, plus two zig-zag rings of 5 equatorial vertices at radius
    // d10R and heights ±d10e (offset 36° between rings). The H/e ratio is
    // CONSTRAINED: for the 10 kite faces to be planar (a proper pentagonal
    // trapezohedron), H/e must equal (1+cos β)/(1−cos β) where β = π/5 ≈ 36°.
    // That works out to ≈9.47, so d10H ≈ 9.47 · d10e.
    //
    // Real d10 long-kite-edge ≈ 13–14mm (vs d6 16mm), so we want the long edge
    // (apex→equator) ≈ 0.85·cubeSize ≈ 1.37. Long edge = √(d10R² + (d10H−d10e)²);
    // with d10H − d10e = d10R the long edge collapses to d10R·√2, so d10R ≈ 0.974.
    private let d10R: Float = 0.974
    private let d10e: Float = 0.114
    private let d10H: Float = 1.089

    // d12 — regular dodecahedron. 20 vertices in three groups: 8 cube corners
    // (±1, ±1, ±1) and 12 "edge" vertices on three rings — (0, ±φ, ±1/φ),
    // (±1/φ, 0, ±φ), (±φ, ±1/φ, 0) — all scaled by d12Scale. φ is the golden
    // ratio. Picked so the inscribed sphere radius (face-to-face / 2) ≈
    // cubeSize/2: at unit scale the inradius is ≈1.378, so d12Scale ≈ 0.85/1.378.
    private let d12Scale: Float = 0.62

    // d20 — regular icosahedron. 12 vertices: (0, ±1, ±φ), (±1, ±φ, 0),
    // (±φ, 0, ±1), all scaled by d20Scale. Faces are 20 equilateral triangles
    // whose outward normals point through the 20 dodecahedron vertex directions
    // (icosahedron and dodecahedron are duals). Inradius at unit scale ≈ 1.512,
    // so d20Scale ≈ 0.85/1.512 keeps the face-to-face distance close to d6's.
    private let d20Scale: Float = 0.56

    /// Each face stores its number, outward normal, and the direction the digit's
    /// "top" points — all in die-local frame. `digitUp` lies in the face plane
    /// (perpendicular to `normal`); the magnifier camera uses it to orient the
    /// rolled face right-side-up by aligning its world projection with screen-up.
    private struct FaceSpec {
        let number: Int
        let normal: SIMD3<Float>
        let digitUp: SIMD3<Float>
    }

    /// Face layout for a kind. The visual texture/plane sits along the face's outward
    /// normal. `digitUp` is the body-local direction the digit's "top" points on each
    /// face — derived from each kind's UV layout (the texture vertex that maps to
    /// image-top): for d4/d8/d20 it's the triangle apex (`verts[0]`), for d10 the
    /// kite pole, for d12 the pentagon's first cyclic-sorted vertex, for d6 the
    /// SCNPlane's local +Y rotated through `rotationFromZ`. Instance method (rather
    /// than static) so the d10 case can read this scene's d10R/d10e/d10H — the kite
    /// face normals' tilt depends on those.
    private func faceSpecs(for kind: Dice3DKind) -> [FaceSpec] {
        switch kind {
        case .d4:
            // Outward normals for the 4 faces of a tetrahedron with vertices at the
            // alternating corners of a cube ((±1,±1,±1) with even sign-parity). Each
            // normal is the negation of the opposite vertex direction, normalized.
            // digitUp is computed from the actual face triangle — the texture maps
            // verts[0] (the face's first vertex) to image top-center, so digit-up
            // points from the face centroid toward verts[0].
            let v: [SIMD3<Float>] = [
                SIMD3( 1,  1,  1) * d4Scale,
                SIMD3( 1, -1, -1) * d4Scale,
                SIMD3(-1,  1, -1) * d4Scale,
                SIMD3(-1, -1,  1) * d4Scale
            ]
            let faces: [(verts: [Int], number: Int)] = [
                ([1, 3, 2], 1),
                ([0, 2, 3], 2),
                ([0, 3, 1], 3),
                ([0, 1, 2], 4)
            ]
            return faces.map { face in
                let p0 = v[face.verts[0]]
                let p1 = v[face.verts[1]]
                let p2 = v[face.verts[2]]
                let normal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
                let centroid = (p0 + p1 + p2) / 3
                let digitUp = simd_normalize(p0 - centroid)
                return FaceSpec(number: face.number, normal: normal, digitUp: digitUp)
            }
        case .d6:
            // SCNPlane lies in its local XY plane with +Z out and +Y "up" of the
            // texture — and createD6Node orients each plane via rotationFromZ(to:
            // face.normal). Applying the same rotation to (0, 1, 0) gives the
            // texture's image-up direction in body coords.
            let normals: [(Int, SIMD3<Float>)] = [
                (1, [ 0,  1,  0]),
                (6, [ 0, -1,  0]),
                (2, [ 1,  0,  0]),
                (5, [-1,  0,  0]),
                (3, [ 0,  0,  1]),
                (4, [ 0,  0, -1])
            ]
            return normals.map { number, normal in
                let q = Self.rotationFromZ(to: normal)
                let digitUp = q.act(SIMD3<Float>(0, 1, 0))
                return FaceSpec(number: number, normal: normal, digitUp: digitUp)
            }
        case .d8:
            // Same body+children pattern as d4: each face's verts[0] (apex of the
            // triangle, mapped to the texture's image-top) drives digit-up.
            let s = d8Scale
            let v: [SIMD3<Float>] = [
                SIMD3( 1,  0,  0) * s,
                SIMD3(-1,  0,  0) * s,
                SIMD3( 0,  1,  0) * s,
                SIMD3( 0, -1,  0) * s,
                SIMD3( 0,  0,  1) * s,
                SIMD3( 0,  0, -1) * s
            ]
            let faces: [(verts: [Int], number: Int)] = [
                ([0, 2, 4], 1), ([0, 4, 3], 2),
                ([0, 3, 5], 3), ([0, 5, 2], 4),
                ([1, 3, 4], 5), ([1, 4, 2], 6),
                ([1, 2, 5], 7), ([1, 5, 3], 8)
            ]
            return faces.map { face in
                let p0 = v[face.verts[0]]
                let p1 = v[face.verts[1]]
                let p2 = v[face.verts[2]]
                let normal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
                let centroid = (p0 + p1 + p2) / 3
                let digitUp = simd_normalize(p0 - centroid)
                return FaceSpec(number: face.number, normal: normal, digitUp: digitUp)
            }
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
            //
            // digitUp points from the kite centroid toward its pole (T or B) — the
            // texture maps the pole to image top-center, so the digit's "up" lies
            // along the kite's long diagonal away from the equator.
            let R = d10R, e = d10e, H = d10H
            let beta = Float.pi / 5
            let T = SIMD3<Float>(0,  H, 0)
            let B = SIMD3<Float>(0, -H, 0)
            var U: [SIMD3<Float>] = []
            var L: [SIMD3<Float>] = []
            for k in 0..<5 {
                let aU = Float(2 * k) * beta
                let aL = Float(2 * k + 1) * beta
                U.append(SIMD3(R * cosf(aU),  e, R * sinf(aU)))
                L.append(SIMD3(R * cosf(aL), -e, R * sinf(aL)))
            }
            let upperNumbers = [1, 2, 3, 4, 5]
            let lowerNumbers = [7, 6, 10, 9, 8]
            var specs: [FaceSpec] = []
            for k in 0..<5 {
                let pole = T, wing1 = U[k], far = L[k], wing2 = U[(k + 1) % 5]
                let centroid = (pole + wing1 + far + wing2) / 4
                let normal = simd_normalize(simd_cross(far - pole, wing1 - pole))
                let digitUp = simd_normalize(pole - centroid)
                specs.append(FaceSpec(number: upperNumbers[k], normal: normal, digitUp: digitUp))
            }
            for k in 0..<5 {
                let pole = B, wing1 = L[k], far = U[(k + 1) % 5], wing2 = L[(k + 1) % 5]
                let centroid = (pole + wing1 + far + wing2) / 4
                let normal = simd_normalize(simd_cross(wing1 - pole, far - pole))
                let digitUp = simd_normalize(pole - centroid)
                specs.append(FaceSpec(number: lowerNumbers[k], normal: normal, digitUp: digitUp))
            }
            return specs
        case .d12:
            // 12 face normals point through the 12 vertices of an icosahedron — the
            // dodecahedron's dual — so they're (0, ±1, ±φ), (±1, ±φ, 0), (±φ, 0, ±1)
            // up to normalization. Numbering puts opposite faces summing to 13.
            //
            // digitUp requires resolving each face's 5 vertices and the cyclic-sort
            // order createD12Node uses (so we agree with the texture's image-top
            // mapping at pentagonUVs[0]). The math here mirrors createD12Node — if
            // the resolution algorithm changes there, mirror it here too.
            let phi: Float = (1 + sqrtf(5)) / 2
            let invPhi: Float = 1 / phi
            let s = d12Scale
            var verts: [SIMD3<Float>] = []
            for sx: Float in [-1, 1] {
                for sy: Float in [-1, 1] {
                    for sz: Float in [-1, 1] {
                        verts.append(SIMD3(sx, sy, sz) * s)
                    }
                }
            }
            for sa: Float in [-1, 1] {
                for sb: Float in [-1, 1] {
                    verts.append(SIMD3(0, sa * phi, sb * invPhi) * s)
                    verts.append(SIMD3(sa * invPhi, 0, sb * phi) * s)
                    verts.append(SIMD3(sa * phi, sb * invPhi, 0) * s)
                }
            }
            let faceDefs: [(normal: SIMD3<Float>, number: Int)] = [
                (SIMD3( 0,  1,  phi), 1),  (SIMD3( 0, -1,  phi), 2),
                (SIMD3( 0,  1, -phi), 11), (SIMD3( 0, -1, -phi), 12),
                (SIMD3( 1,  phi,  0), 3),  (SIMD3(-1,  phi,  0), 4),
                (SIMD3( 1, -phi,  0), 9),  (SIMD3(-1, -phi,  0), 10),
                (SIMD3( phi,  0,  1), 5),  (SIMD3(-phi,  0,  1), 6),
                (SIMD3( phi,  0, -1), 7),  (SIMD3(-phi,  0, -1), 8)
            ]
            return faceDefs.map { def in
                let n = simd_normalize(def.normal)
                let projected = verts.enumerated()
                    .map { ($0.offset, simd_dot($0.element, def.normal)) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(5)
                    .map { verts[$0.0] }
                var u = SIMD3<Float>(1, 0, 0)
                if abs(simd_dot(u, n)) > 0.9 { u = SIMD3<Float>(0, 1, 0) }
                u = simd_normalize(u - simd_dot(u, n) * n)
                let vAxis = simd_cross(n, u)
                let center = projected.reduce(SIMD3<Float>(0, 0, 0), +) / 5
                let sorted = projected
                    .map { v -> (vert: SIMD3<Float>, angle: Float) in
                        let d = v - center
                        return (v, atan2f(simd_dot(d, vAxis), simd_dot(d, u)))
                    }
                    .sorted { $0.angle < $1.angle }
                    .map { $0.vert }
                let digitUp = simd_normalize(sorted[0] - center)
                return FaceSpec(number: def.number, normal: n, digitUp: digitUp)
            }
        case .d20:
            // 20 face normals point through the 20 dodecahedron vertex directions
            // (icosahedron's dual): 8 "cube corner" directions (±1, ±1, ±1) and 12
            // "edge" directions. Numbering puts opposite faces summing to 21.
            //
            // digitUp requires the same procedural face resolution as createD20Node:
            // for each face normal, the 3 vertices with the highest projection are
            // the face triangle, sorted cyclically so sorted[0] maps to the texture's
            // apex (UV (0.5, 0)). digit-up points from face center toward sorted[0].
            let phi: Float = (1 + sqrtf(5)) / 2
            let invPhi: Float = 1 / phi
            let s = d20Scale
            var verts: [SIMD3<Float>] = []
            for sa: Float in [-1, 1] {
                for sb: Float in [-1, 1] {
                    verts.append(SIMD3(0, sa, sb * phi) * s)
                    verts.append(SIMD3(sa, sb * phi, 0) * s)
                    verts.append(SIMD3(sa * phi, 0, sb) * s)
                }
            }
            let faceDefs: [(normal: SIMD3<Float>, number: Int)] = [
                (SIMD3( 1,  1,  1),  1), (SIMD3(-1, -1, -1), 20),
                (SIMD3( 1,  1, -1), 14), (SIMD3(-1, -1,  1),  7),
                (SIMD3( 1, -1,  1), 17), (SIMD3(-1,  1, -1),  4),
                (SIMD3( 1, -1, -1),  2), (SIMD3(-1,  1,  1), 19),
                (SIMD3(0,  phi,  invPhi), 13), (SIMD3(0, -phi, -invPhi),  8),
                (SIMD3(0,  phi, -invPhi),  6), (SIMD3(0, -phi,  invPhi), 15),
                (SIMD3( phi,  invPhi, 0),  9), (SIMD3(-phi, -invPhi, 0), 12),
                (SIMD3( phi, -invPhi, 0), 16), (SIMD3(-phi,  invPhi, 0),  5),
                (SIMD3( invPhi, 0,  phi), 11), (SIMD3(-invPhi, 0, -phi), 10),
                (SIMD3( invPhi, 0, -phi), 18), (SIMD3(-invPhi, 0,  phi),  3)
            ]
            return faceDefs.map { def in
                let n = simd_normalize(def.normal)
                let projected = verts.enumerated()
                    .map { ($0.offset, simd_dot($0.element, def.normal)) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(3)
                    .map { verts[$0.0] }
                var u = SIMD3<Float>(1, 0, 0)
                if abs(simd_dot(u, n)) > 0.9 { u = SIMD3<Float>(0, 1, 0) }
                u = simd_normalize(u - simd_dot(u, n) * n)
                let vAxis = simd_cross(n, u)
                let center = projected.reduce(SIMD3<Float>(0, 0, 0), +) / 3
                let sorted = projected
                    .map { v -> (vert: SIMD3<Float>, angle: Float) in
                        let d = v - center
                        return (v, atan2f(simd_dot(d, vAxis), simd_dot(d, u)))
                    }
                    .sorted { $0.angle < $1.angle }
                    .map { $0.vert }
                let digitUp = simd_normalize(sorted[0] - center)
                return FaceSpec(number: def.number, normal: n, digitUp: digitUp)
            }
        case .d100:
            // Unreachable — d100 is compound and rendered as a pair of d10 nodes,
            // each tagged kind=.d10. faceSpecs is only ever queried via the
            // physical kind, so this branch is here just to keep the switch
            // exhaustive. Returning the d10 layout keeps downstream callers safe
            // if it does get invoked.
            return faceSpecs(for: .d10)
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
        setupMagnifierCameras()
        setupLighting()
        setupTray()

        connectorContainer = SCNNode()
        scene.rootNode.addChildNode(connectorContainer)
    }

    /// Builds the magnifier camera nodes and parks them in the scene root. Two
    /// cameras to cover the d100 pair case (ones + tens shown side-by-side);
    /// standalone dice use only the first. Position and orientation get set
    /// per-press by `positionMagnifier(slot:forDieIndex:)` — initial values here
    /// just need to be valid (any orientation works since the cameras aren't
    /// rendered until the magnifier overlay is shown).
    private func setupMagnifierCameras() {
        for _ in 0..<2 {
            let camera = SCNCamera()
            // Narrow FOV keeps perspective foreshortening minimal on the rolled face,
            // so a slightly tilted face (e.g. d10) still reads close to flat.
            camera.fieldOfView = 25
            camera.zNear = 0.1
            camera.zFar = 50
            let node = SCNNode()
            node.camera = camera
            node.position = SCNVector3(0, 5, 0)
            scene.rootNode.addChildNode(node)
            magnifierCameras.append(node)
        }
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

    private func createDieNode(kind: Dice3DKind, role: DieRole = .standard) -> SCNNode {
        switch kind {
        case .d4:   return createD4Node()
        case .d6:   return createD6Node()
        case .d8:   return createD8Node()
        case .d10:  return createD10Node(role: role)
        case .d12:  return createD12Node()
        case .d20:  return createD20Node()
        case .d100:
            // d100 is a compound kind — `setDice(formula:)` expands each d100 in
            // the formula to two d10 nodes (one .d100Ones, one .d100Tens) before
            // calling here, so this branch shouldn't be reached. Fall back to a
            // standard d10 if it ever is, just so we don't crash.
            return createD10Node(role: role)
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
    private func createD10Node(role: DieRole = .standard) -> SCNNode {
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
            // Texture lookup branches on role: a `.d100Tens` die loads the
            // `d100-face-NN` set (NN = multiples of 10, where kite.number K maps to
            // (K * 10) % 100, so K=1→10, K=9→90, K=10→00); ones and standard d10s
            // both use the regular `d10-face-NN` set. Same kite geometry / detection
            // either way — only the rendered art differs.
            switch role {
            case .d100Tens:
                let tensValue = (kite.number * 10) % 100
                mat.diffuse.contents = UIImage(named: String(format: "d100-face-%02d", tensValue))
                    ?? Self.makeD100TensFallbackImage(value: tensValue)
            case .standard, .d100Ones:
                mat.diffuse.contents = UIImage(named: String(format: "d10-face-%02d", kite.number))
                    ?? Self.makeD10FallbackImage(number: kite.number)
            }
            mat.roughness.contents = 0.45
            mat.isDoubleSided = false
            faceGeometry.materials = [mat]

            node.addChildNode(SCNNode(geometry: faceGeometry))
        }

        return node
    }

    /// Builds a regular dodecahedron — 20 vertices (8 cube corners + 12 edge
    /// vertices on three rings) and 12 pentagonal faces. Same body+children pattern
    /// as the other kinds: one ivory body geometry handles the convex-hull physics
    /// and base color, then 12 textured triangle-fan child nodes overlay each face
    /// with its own UV-mapped pentagon.
    ///
    /// The 5 vertices of each face are discovered procedurally: for each of the 12
    /// face-normal directions (which equal the 12 icosahedron vertex directions —
    /// dodecahedron and icosahedron are duals), the 5 vertices with the highest
    /// projection onto that normal lie on that face. Those 5 are then sorted by
    /// angle in the face's plane to produce a counter-clockwise (outward-facing)
    /// winding for triangulation.
    private func createD12Node() -> SCNNode {
        let s = d12Scale
        let phi: Float = (1 + sqrtf(5)) / 2
        let invPhi: Float = 1 / phi

        // 20 vertices.
        var verts: [SIMD3<Float>] = []
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                for sz: Float in [-1, 1] {
                    verts.append(SIMD3(sx, sy, sz) * s)
                }
            }
        }
        for sa: Float in [-1, 1] {
            for sb: Float in [-1, 1] {
                verts.append(SIMD3(0, sa * phi, sb * invPhi) * s)
                verts.append(SIMD3(sa * invPhi, 0, sb * phi) * s)
                verts.append(SIMD3(sa * phi, sb * invPhi, 0) * s)
            }
        }

        // 12 face-normal directions (un-normalized — only direction matters here)
        // and the corresponding face number, in the SAME order as faceSpecs(.d12)
        // so detection and rendering agree.
        let faceDefs: [(normal: SIMD3<Float>, number: Int)] = [
            (SIMD3( 0,  1,  phi), 1),  (SIMD3( 0, -1,  phi), 2),
            (SIMD3( 0,  1, -phi), 11), (SIMD3( 0, -1, -phi), 12),
            (SIMD3( 1,  phi,  0), 3),  (SIMD3(-1,  phi,  0), 4),
            (SIMD3( 1, -phi,  0), 9),  (SIMD3(-1, -phi,  0), 10),
            (SIMD3( phi,  0,  1), 5),  (SIMD3(-phi,  0,  1), 6),
            (SIMD3( phi,  0, -1), 7),  (SIMD3(-phi,  0, -1), 8)
        ]

        // UV layout for one pentagonal face: vertex-up regular pentagon, vertices
        // listed in counter-clockwise order from the top to match the cyclic 3D sort.
        //
        // The hand-drawn PNG assets have a transparent margin between the image edge
        // and the pentagon — the top vertex sits ~16 px below the top of a 512² PNG
        // rather than at y=0 — so a UV of (0.5, 0) at the body's top vertex pulls
        // a transparent pixel and the body ivory leaks through. Shifting every v
        // down by `topMarginV` re-aligns the sampling to the actual artwork.
        // Adjust this constant if asset margins change.
        let topMarginV: CGFloat = 28.0 / 512.0
        let pentagonUVs: [CGPoint] = [
            CGPoint(x: 0.5,   y: 0.0   + topMarginV),  // 0: top
            CGPoint(x: 0.024, y: 0.346 + topMarginV),  // 1: upper-left
            CGPoint(x: 0.206, y: 0.905 + topMarginV),  // 2: lower-left
            CGPoint(x: 0.794, y: 0.905 + topMarginV),  // 3: lower-right
            CGPoint(x: 0.976, y: 0.346 + topMarginV)   // 4: upper-right
        ]

        // Resolve the 5 vertices of each face and put them in CCW (outward) order.
        // We compute once and reuse for both the body geometry and the textured
        // child nodes so winding stays consistent.
        struct ResolvedFace {
            let verts: [SIMD3<Float>]   // 5 vertices in CCW-from-outside order
            let normal: SIMD3<Float>    // unit outward normal
            let number: Int
        }
        let resolved: [ResolvedFace] = faceDefs.map { def in
            let n = simd_normalize(def.normal)
            let projected = verts.enumerated()
                .map { ($0.offset, simd_dot($0.element, def.normal)) }
                .sorted { $0.1 > $1.1 }
                .prefix(5)
                .map { verts[$0.0] }
            // Build an orthonormal (u, v) basis in the face plane to sort by angle.
            var u = SIMD3<Float>(1, 0, 0)
            if abs(simd_dot(u, n)) > 0.9 { u = SIMD3<Float>(0, 1, 0) }
            u = simd_normalize(u - simd_dot(u, n) * n)
            let vAxis = simd_cross(n, u)
            let center = projected.reduce(SIMD3<Float>(0, 0, 0), +) / 5
            let sorted = projected
                .map { v -> (vert: SIMD3<Float>, angle: Float) in
                    let d = v - center
                    return (v, atan2f(simd_dot(d, vAxis), simd_dot(d, u)))
                }
                .sorted { $0.angle < $1.angle }
                .map { $0.vert }
            return ResolvedFace(verts: sorted, normal: n, number: def.number)
        }

        // Body geometry — fan-triangulate each pentagon (3 tris per face).
        var bodyPositions: [SCNVector3] = []
        var bodyNormals: [SCNVector3] = []
        for face in resolved {
            let nv = SCNVector3(face.normal)
            for i in 1..<4 {
                bodyPositions += [
                    SCNVector3(face.verts[0]),
                    SCNVector3(face.verts[i]),
                    SCNVector3(face.verts[i + 1])
                ]
                bodyNormals += [nv, nv, nv]
            }
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

        // One textured pentagon child per face. Inset = 1.0 (texture child the same
        // size as the body face, NOT 1.02 like the other dice) — with fan-triangulation
        // through vertex 0 a 1.02 inset makes body vertices land *inside* the texture
        // child's triangles, so each body vertex samples a UV ~1% biased toward the
        // texture's centroid instead of at the pentagon corner you set. For the d12
        // specifically that meant a thin border drawn at the image edge wasn't
        // visible at the body's perimeter (border lived in the overhang ring outside
        // the visible face) and the body's edge ivory leaked through. With inset=1.0
        // body vertex N samples exactly pentagonUVs[N], so a border drawn at the
        // image edge in the PNG renders at the face's edge.
        // outwardOffset bumped to compensate for the lost overhang — the texture sits
        // further forward so the dodecahedron's ridge ivory hides behind it from
        // typical viewing angles.
        let outwardOffset: Float = 0.005
        let inset: Float = 1.02

        for face in resolved {
            let center = face.verts.reduce(SIMD3<Float>(0, 0, 0), +) / 5
            let shifted = face.verts.map { v -> SIMD3<Float> in
                center + (v - center) * inset + face.normal * outwardOffset
            }
            var positions: [SCNVector3] = []
            var uvs: [CGPoint] = []
            for i in 1..<4 {
                positions += [
                    SCNVector3(shifted[0]),
                    SCNVector3(shifted[i]),
                    SCNVector3(shifted[i + 1])
                ]
                uvs += [pentagonUVs[0], pentagonUVs[i], pentagonUVs[i + 1]]
            }
            let normals: [SCNVector3] = Array(repeating: SCNVector3(face.normal),
                                              count: positions.count)

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
            mat.diffuse.contents = UIImage(named: String(format: "d12-face-%02d", face.number))
                ?? Self.makeD12FallbackImage(number: face.number)
            mat.roughness.contents = 0.45
            mat.isDoubleSided = false
            faceGeometry.materials = [mat]

            node.addChildNode(SCNNode(geometry: faceGeometry))
        }

        return node
    }

    /// Builds a regular icosahedron — 12 vertices at the golden-ratio coords
    /// (0, ±1, ±φ), (±1, ±φ, 0), (±φ, 0, ±1), all scaled by d20Scale, and 20
    /// equilateral triangular faces. Same body+children pattern as d12: one
    /// ivory body geometry handles convex-hull physics and base color, then 20
    /// textured triangle child nodes overlay each face.
    ///
    /// Faces are discovered procedurally — for each of the 20 face-normal
    /// directions (which equal the 20 dodecahedron vertex directions, since
    /// icosahedron and dodecahedron are duals), the 3 icosahedron vertices with
    /// the highest projection onto that normal lie on that face. Those 3 are
    /// then sorted by angle in the face plane to give a CCW outward winding.
    private func createD20Node() -> SCNNode {
        let s = d20Scale
        let phi: Float = (1 + sqrtf(5)) / 2
        let invPhi: Float = 1 / phi

        // 12 vertices.
        var verts: [SIMD3<Float>] = []
        for sa: Float in [-1, 1] {
            for sb: Float in [-1, 1] {
                verts.append(SIMD3(0, sa, sb * phi) * s)
                verts.append(SIMD3(sa, sb * phi, 0) * s)
                verts.append(SIMD3(sa * phi, 0, sb) * s)
            }
        }

        // 20 face-normal directions and numbers, in the SAME order as
        // faceSpecs(.d20). Numbers chosen so opposite faces sum to 21.
        // Numbers must match faceSpecs(.d20) exactly so detection and rendering agree.
        let faceDefs: [(normal: SIMD3<Float>, number: Int)] = [
            // 8 cube-corner directions
            (SIMD3( 1,  1,  1),  1), (SIMD3(-1, -1, -1), 20),
            (SIMD3( 1,  1, -1), 14), (SIMD3(-1, -1,  1),  7),
            (SIMD3( 1, -1,  1), 17), (SIMD3(-1,  1, -1),  4),
            (SIMD3( 1, -1, -1),  2), (SIMD3(-1,  1,  1), 19),
            // 12 edge directions
            // Plane x=0: (0, ±φ, ±1/φ)
            (SIMD3(0,  phi,  invPhi), 13), (SIMD3(0, -phi, -invPhi),  8),
            (SIMD3(0,  phi, -invPhi),  6), (SIMD3(0, -phi,  invPhi), 15),
            // Plane z=0: (±φ, ±1/φ, 0)
            (SIMD3( phi,  invPhi, 0),  9), (SIMD3(-phi, -invPhi, 0), 12),
            (SIMD3( phi, -invPhi, 0), 16), (SIMD3(-phi,  invPhi, 0),  5),
            // Plane y=0: (±1/φ, 0, ±φ)
            (SIMD3( invPhi, 0,  phi), 11), (SIMD3(-invPhi, 0, -phi), 10),
            (SIMD3( invPhi, 0, -phi), 18), (SIMD3(-invPhi, 0,  phi),  3)
        ]

        // UV layout: triangle inscribed in unit square with apex at top-center
        // and base at bottom corners — same convention as d4 and d8 fallbacks.
        let triangleUVs: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.0),  // 0: apex (top-center)
            CGPoint(x: 0.0, y: 1.0),  // 1: bottom-left
            CGPoint(x: 1.0, y: 1.0)   // 2: bottom-right
        ]

        struct ResolvedFace {
            let verts: [SIMD3<Float>]   // 3 vertices in CCW-from-outside order
            let normal: SIMD3<Float>    // unit outward normal
            let number: Int
        }
        let resolved: [ResolvedFace] = faceDefs.map { def in
            let n = simd_normalize(def.normal)
            let projected = verts.enumerated()
                .map { ($0.offset, simd_dot($0.element, def.normal)) }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map { verts[$0.0] }
            // Build an orthonormal (u, v) basis in the face plane to sort by angle.
            var u = SIMD3<Float>(1, 0, 0)
            if abs(simd_dot(u, n)) > 0.9 { u = SIMD3<Float>(0, 1, 0) }
            u = simd_normalize(u - simd_dot(u, n) * n)
            let vAxis = simd_cross(n, u)
            let center = projected.reduce(SIMD3<Float>(0, 0, 0), +) / 3
            let sorted = projected
                .map { v -> (vert: SIMD3<Float>, angle: Float) in
                    let d = v - center
                    return (v, atan2f(simd_dot(d, vAxis), simd_dot(d, u)))
                }
                .sorted { $0.angle < $1.angle }
                .map { $0.vert }
            return ResolvedFace(verts: sorted, normal: n, number: def.number)
        }

        // Body geometry — single ivory mesh, 1 triangle per face. SceneKit infers
        // convex-hull physics from the unique vertex positions.
        var bodyPositions: [SCNVector3] = []
        var bodyNormals: [SCNVector3] = []
        for face in resolved {
            let nv = SCNVector3(face.normal)
            bodyPositions += [
                SCNVector3(face.verts[0]),
                SCNVector3(face.verts[1]),
                SCNVector3(face.verts[2])
            ]
            bodyNormals += [nv, nv, nv]
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

        // One textured triangle child per face. Slight outward offset prevents
        // z-fighting with the body underneath; inset 1.02 gives a small overshoot
        // so trimming imperfections in hand-drawn assets don't show as ivory.
        let outwardOffset: Float = 0.005
        let inset: Float = 1.02

        for face in resolved {
            let center = face.verts.reduce(SIMD3<Float>(0, 0, 0), +) / 3
            let shifted = face.verts.map { v -> SIMD3<Float> in
                center + (v - center) * inset + face.normal * outwardOffset
            }
            let positions = shifted.map { SCNVector3($0) }
            let normals: [SCNVector3] = Array(repeating: SCNVector3(face.normal), count: 3)

            let posSource = SCNGeometrySource(vertices: positions)
            let normSource = SCNGeometrySource(normals: normals)
            let uvSource = SCNGeometrySource(textureCoordinates: triangleUVs)
            let element = SCNGeometryElement(
                indices: [Int32(0), Int32(1), Int32(2)],
                primitiveType: .triangles
            )
            let faceGeometry = SCNGeometry(
                sources: [posSource, normSource, uvSource],
                elements: [element]
            )

            let mat = SCNMaterial()
            mat.diffuse.contents = UIImage(named: String(format: "d20-face-%02d", face.number))
                ?? Self.makeD20FallbackImage(number: face.number)
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

    /// Placeholder d100 "tens" face texture used until the user adds the
    /// `d100-face-NN` assets (NN = multiples of 10 from 00 to 90). Renders the
    /// printed value (e.g. "30", "00") at the kite centroid the same way the d10
    /// fallback does — `value` is the on-face label the user would draw, not the
    /// kite-number.
    private static func makeD100TensFallbackImage(value: Int) -> UIImage {
        let pixelHeight: CGFloat = 256
        let pixelWidth: CGFloat = 189
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelWidth, height: pixelHeight))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: String(format: "%02d", value), attributes: attrs)
            let size = str.size()
            let centroidV: CGFloat = 0.655
            str.draw(at: CGPoint(
                x: (pixelWidth - size.width) / 2,
                y: pixelHeight * centroidV - size.height / 2
            ))
        }
    }

    /// Placeholder d12 face texture used until the user adds `d12-face-NN` assets.
    /// Square canvas with the pentagon UV layout (top vertex at v=0, bottom edge at
    /// v=0.905). The digit sits at the pentagon's BBOX MIDPOINT (v ≈ 0.453), NOT
    /// its geometric centroid (v=0.5) — for a vertex-up pentagon the centroid is
    /// biased downward (the top half of the face, apex→centroid, is taller than
    /// the bottom half, centroid→bottom-edge), so a digit drawn at the centroid
    /// reads as sitting low. Splitting the difference between top vertex and
    /// bottom edge looks visually centered.
    private static func makeD12FallbackImage(number: Int) -> UIImage {
        let pixelSize: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize)))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 86, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: "\(number)", attributes: attrs)
            let size = str.size()
            let digitV: CGFloat = 0.453   // (0 + 0.905) / 2 — pentagon bbox midpoint
            str.draw(at: CGPoint(
                x: (pixelSize - size.width) / 2,
                y: pixelSize * digitV - size.height / 2
            ))
        }
    }

    /// Placeholder d20 face texture used until the user adds `d20-face-NN` assets.
    /// Square canvas with the triangle UV layout (apex at top-center, base at the
    /// bottom corners). The digit sits at the triangle's geometric centroid
    /// (v ≈ 0.667 — apex y=0, base y=1, so centroid is 2/3 of the way down) so it
    /// reads visually centered on the equilateral face rather than image-centred.
    private static func makeD20FallbackImage(number: Int) -> UIImage {
        let pixelSize: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        return renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize)))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 90, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ]
            let str = NSAttributedString(string: "\(number)", attributes: attrs)
            let size = str.size()
            str.draw(at: CGPoint(
                x: (pixelSize - size.width) / 2,
                y: pixelSize * 2 / 3 - size.height / 2
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
    /// add/remove only the delta. The legacy playground entry — doesn't support
    /// compound kinds (d100), so callers should filter those out before calling.
    func setDice(count: Int, kind: Dice3DKind) {
        if dice.contains(where: { $0.kind != kind }) {
            for die in dice { die.node.removeFromParentNode() }
            dice.removeAll()
        }
        clearConnectors()

        let target = max(0, count)

        while dice.count > target {
            let removed = dice.removeLast()
            removed.node.removeFromParentNode()
        }

        while dice.count < target {
            let node = createDieNode(kind: kind, role: .standard)
            node.position = findEmptyTrayPosition()
            node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
            scene.rootNode.addChildNode(node)
            // Sequential formulaIndex so each playground die is its own slot —
            // makes the per-formula-slot result-grouping in `settleAllDice` work
            // even though there's no actual formula here.
            dice.append(ManagedDie(
                node: node, kind: kind, role: .standard, formulaIndex: dice.count,
                rolledFace: nil, lastPosition: nil, lastOrientation: nil
            ))
        }
    }

    /// Formula-driven population. Clears the existing dice and rebuilds one node per
    /// die in the formula, tagging each with its position in the flat dice list
    /// (groups expanded in order). Groups whose kind isn't supported in 3D are
    /// silently skipped — callers should pre-validate via `Dice3DKind(_:)`.
    ///
    /// d100 is COMPOUND — each d100 in the formula spawns TWO physical d10 nodes
    /// (one `.d100Ones` and one `.d100Tens`) that share the same `formulaIndex`.
    /// `settleAllDice` later pairs them up by index and combines their face values
    /// into the 1–100 result that the formula layer sees.
    func setDice(formula: DiceFormula) {
        for die in dice { die.node.removeFromParentNode() }
        dice.removeAll()
        clearConnectors()

        var formulaIndex = 0
        for group in formula.groups {
            guard let kind = Dice3DKind(group.kind) else {
                // Skip unsupported kinds. Caller is expected to have filtered these out
                // already, but we tolerate them here so a stale formula can't crash.
                formulaIndex += group.count
                continue
            }
            for _ in 0..<group.count {
                if kind == .d100 {
                    spawnD100Pair(formulaIndex: formulaIndex)
                } else {
                    spawnStandardDie(kind: kind, formulaIndex: formulaIndex)
                }
                formulaIndex += 1
            }
        }
    }

    /// Adds one standard die (any kind except d100) to the scene at a random
    /// empty tray position with a random Y-axis rotation.
    private func spawnStandardDie(kind: Dice3DKind, formulaIndex: Int) {
        let node = createDieNode(kind: kind, role: .standard)
        node.position = findEmptyTrayPosition()
        node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
        scene.rootNode.addChildNode(node)
        dice.append(ManagedDie(
            node: node, kind: kind, role: .standard, formulaIndex: formulaIndex,
            rolledFace: nil, lastPosition: nil, lastOrientation: nil
        ))
    }

    /// Adds one d100 pair to the scene — a `.d100Ones` and a `.d100Tens` d10,
    /// each at its own random empty tray position. Both share `formulaIndex` so
    /// the result-combining loop pairs them up. Spawn positions are independent
    /// (no proximity bias) — the connector line drawn after settling is what
    /// communicates the pairing visually.
    private func spawnD100Pair(formulaIndex: Int) {
        for role in [DieRole.d100Ones, DieRole.d100Tens] {
            let node = createDieNode(kind: .d10, role: role)
            node.position = findEmptyTrayPosition()
            node.simdOrientation = simd_quatf(angle: Float.random(in: 0..<2 * .pi), axis: [0, 1, 0])
            scene.rootNode.addChildNode(node)
            dice.append(ManagedDie(
                node: node, kind: .d10, role: role, formulaIndex: formulaIndex,
                rolledFace: nil, lastPosition: nil, lastOrientation: nil
            ))
        }
    }

    // MARK: - Damage-type glow (post-settle)

    /// Name tag for the per-die glow shell, so `clearGlow` can find and remove
    /// only the nodes we added — die nodes share their tree with face-decal
    /// child nodes, connector cylinders, and magnifier cameras.
    private static let glowShellName = "damage-glow-shell"

    /// Attach an inverted-hull outline shell to each die whose `formulaIndex`
    /// is in the map. The shell is a clone of the die's body geometry scaled
    /// up slightly and rendered with `cullMode = .front` — so only the back
    /// faces draw, and the die's front faces occlude all but a thin rim
    /// around the screen-space silhouette. Tracks the die's exact outline at
    /// any camera angle. Call this only AFTER dice settle (otherwise the
    /// shell tumbles with the body, which still works but flickers).
    func setGlow(_ colorsByFormulaIndex: [Int: UIColor]) {
        clearGlow()
        for die in dice {
            guard let color = colorsByFormulaIndex[die.formulaIndex] else { continue }
            // The body geometry lives on the die's root node; face decals are
            // children. Cloning the root geometry gives us the polyhedron
            // (cube / tetra / octa / etc.) without the textured face planes.
            guard let cloned = die.node.geometry?.copy() as? SCNGeometry else { continue }

            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = color
            mat.emission.contents = color
            // Only the back-facing polygons of the shell render. Combined with
            // a slightly enlarged scale, this leaves just a thin rim around
            // the die's silhouette visible.
            mat.cullMode = .front
            mat.isDoubleSided = false
            // Full opacity so similar damage colors stay distinguishable.
            // The shell trick already keeps the rim thin — softening with
            // transparency mostly hurt contrast on look-alike pairs (slashing
            // vs. fire, necrotic vs. poison).
            mat.transparency = 1.0
            cloned.materials = [mat]

            let shell = SCNNode(geometry: cloned)
            shell.name = Self.glowShellName
            // Tune for rim width — 1.08 yields a few pixels of glow at the
            // standard camera distance. Bump to 1.12 for a fatter outline.
            shell.scale = SCNVector3(1.08, 1.08, 1.08)
            shell.castsShadow = false
            // Render before the die so the die's depth pass overdraws the
            // shell's interior cleanly; only the rim survives.
            shell.renderingOrder = -1
            die.node.addChildNode(shell)
        }
    }

    /// Strip all damage-type glow shells from every die. Called at the start
    /// of every roll (so shells don't tumble with the dice) and implicitly by
    /// `setGlow` before re-stamping.
    func clearGlow() {
        for die in dice {
            for child in die.node.childNodes where child.name == Self.glowShellName {
                child.removeFromParentNode()
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
        clearConnectors()

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
            onAllSettled(formulaSlotValuesFromCurrentFaces())
            return
        }
        currentRollId += 1
        clearConnectors()

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
            let since = allStillSince ?? now
            allStillSince = since
            if now - since >= requiredAllStillDuration {
                settleAllDice()
            }
        } else {
            allStillSince = nil
        }
    }

    /// All dice have been completely still for the required duration — snapshot
    /// each face value in one pass and fire the all-settled callback. Called only
    /// from `tickRestDetection`; do not call directly.
    ///
    /// The values returned are PER FORMULA SLOT, not per physical die — for d100
    /// pairs the two physical face values get combined into a single 1–100 result
    /// before being placed in the values array, and only the d100 slot's
    /// formulaIndex appears in the output. This matches what
    /// `DiceRoller.resultFrom(formula:values:mode:)` expects.
    private func settleAllDice() {
        isAwaitingRest = false
        allStillSince = nil

        for i in dice.indices {
            let face = detectResult(of: dice[i])
            dice[i].rolledFace = face
            onDieSettled?(i, face)
        }

        drawD100Connectors()

        let cb = allSettledCallback
        allSettledCallback = nil
        cb?(formulaSlotValuesFromCurrentFaces())
    }

    /// Builds the values-array the formula layer expects from the dice array's
    /// current `rolledFace` snapshot. One entry per formula slot, in slot order;
    /// d100 pairs are combined into their 1–100 value here. Used both by
    /// `settleAllDice` (after a fresh roll) and by `rethrowDice` (when a no-op
    /// rethrow needs to return the previous values without re-throwing anything).
    private func formulaSlotValuesFromCurrentFaces() -> [Int] {
        let grouped = Dictionary(grouping: dice.indices, by: { dice[$0].formulaIndex })
        return grouped
            .sorted { $0.key < $1.key }
            .map { _, indices -> Int in
                if indices.count == 2,
                   let oI = indices.first(where: { dice[$0].role == .d100Ones }),
                   let tI = indices.first(where: { dice[$0].role == .d100Tens }) {
                    return combineD100(
                        onesFace: dice[oI].rolledFace ?? 0,
                        tensFace: dice[tI].rolledFace ?? 0
                    )
                }
                // Standalone die — single physical face value IS the formula value.
                return dice[indices[0]].rolledFace ?? 0
            }
    }

    /// Combines two d10 face values (each 1–10 from the kite geometry) into a
    /// single d100 result (1–100). The d10 textures are labeled 0–9 with the
    /// face that the geometry numbers as 10 carrying the "0" art, so we mod-10
    /// each input to recover the printed digit, then add `tens * 10 + ones`.
    /// `0 + 00` is the conventional read for 100, so we promote that case.
    private func combineD100(onesFace: Int, tensFace: Int) -> Int {
        let onesDigit = onesFace % 10                    // 1..9 stay; 10 → 0
        let tensDigit = tensFace % 10                    // same mapping for the tens die
        let result = tensDigit * 10 + onesDigit
        return result == 0 ? 100 : result
    }

    // MARK: - d100 pair connector lines

    /// Removes every connector line currently in the scene. Called whenever the
    /// dice are about to move (rollAll, rethrowDice) or the formula changes —
    /// connectors are stale at any moment that isn't "all dice resting at their
    /// post-settle positions", and we'd rather show none than show wrong ones.
    private func clearConnectors() {
        for child in connectorContainer.childNodes {
            child.removeFromParentNode()
        }
    }

    /// Adds one connector node per d100 pair currently in the scene, drawn from
    /// each die's upper polar apex (the kite-trapezohedron tip facing UP after
    /// settling — the one not touching the felt). Called from `settleAllDice`
    /// after the all-still gate has fired, so positions won't shift again until
    /// the next roll and we can read the orientations safely.
    private func drawD100Connectors() {
        let grouped = Dictionary(grouping: dice.indices, by: { dice[$0].formulaIndex })
        for (_, indices) in grouped {
            guard indices.count == 2,
                  let oI = indices.first(where: { dice[$0].role == .d100Ones }),
                  let tI = indices.first(where: { dice[$0].role == .d100Tens })
            else { continue }
            let onesApex = upperApexWorldPosition(of: dice[oI])
            let tensApex = upperApexWorldPosition(of: dice[tI])
            connectorContainer.addChildNode(makeConnectorNode(from: onesApex, to: tensApex))
        }
    }

    /// World-space position of a d10's UPPER polar apex (the vertex that's pointing
    /// up after settling). The kite trapezohedron has two polar vertices at
    /// die-local `(0, ±d10H, 0)`; we apply the die's current orientation to both
    /// and pick the one with the higher world-Y. Used to anchor the connector
    /// line at the visible tip rather than at the die's geometric center.
    private func upperApexWorldPosition(of die: ManagedDie) -> SCNVector3 {
        let pres = die.node.presentation
        let center = SIMD3<Float>(pres.position)
        let q = pres.simdOrientation
        let topWorld    = center + q.act(SIMD3<Float>(0,  d10H, 0))
        let bottomWorld = center + q.act(SIMD3<Float>(0, -d10H, 0))
        return SCNVector3(topWorld.y > bottomWorld.y ? topWorld : bottomWorld)
    }

    /// Builds an arched, semi-translucent connector between two world-space
    /// points. The curve is a quadratic Bézier with a control point lifted above
    /// the chord midpoint — height scales with chord length (with a small floor
    /// so very-close pairs still arch visibly). Sampled into ~24 short cylinder
    /// segments, each parented to a single returned node so the whole connector
    /// can be removed in one `removeFromParentNode()` call.
    private func makeConnectorNode(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let parent = SCNNode()

        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let chord = sqrtf(dx * dx + dy * dy + dz * dz)
        let archHeight = max(chord * 0.30, 1.2)

        // Control point sits directly above the chord midpoint — keeps the arch
        // in a vertical plane so it reads as "lifted off the tray" from any
        // camera angle, not skewed sideways.
        let control = SCNVector3(
            (a.x + b.x) / 2,
            (a.y + b.y) / 2 + archHeight,
            (a.z + b.z) / 2
        )

        let segments = 24
        var prev = a
        for i in 1...segments {
            let t = Float(i) / Float(segments)
            let next = quadraticBezier(a: a, c: control, b: b, t: t)
            parent.addChildNode(makeConnectorSegment(from: prev, to: next))
            prev = next
        }
        return parent
    }

    /// One straight cylinder segment of a connector, semi-translucent ivory-gold.
    /// Lighting is `.constant` so the segment color stays even from the side
    /// (we want a flat glow, not a shaded tube), and `blendMode = .alpha` plus
    /// `transparency` < 1 give the see-through look.
    private func makeConnectorSegment(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrtf(dx * dx + dy * dy + dz * dz)

        let cylinder = SCNCylinder(radius: 0.06, height: CGFloat(length))
        let mat = SCNMaterial()
        mat.diffuse.contents  = UIColor(red: 1.00, green: 0.84, blue: 0.20, alpha: 0.45)
        mat.emission.contents = UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 0.45)
        mat.transparency = 0.55
        mat.blendMode = .alpha
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false   // adjacent segments shouldn't punch holes through each other
        cylinder.materials = [mat]

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)

        let dir = simd_normalize(SIMD3<Float>(dx, dy, dz))
        let from: SIMD3<Float> = [0, 1, 0]
        let dot = simd_dot(from, dir)
        if dot < 0.9999 {
            if dot < -0.9999 {
                node.simdOrientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            } else {
                let axis = simd_normalize(simd_cross(from, dir))
                node.simdOrientation = simd_quatf(angle: acos(dot), axis: axis)
            }
        }
        return node
    }

    /// Quadratic Bézier sample at `t ∈ [0, 1]`. `a` and `b` are endpoints, `c` is
    /// the lifted control point.
    private func quadraticBezier(a: SCNVector3, c: SCNVector3, b: SCNVector3, t: Float) -> SCNVector3 {
        let u = 1 - t
        return SCNVector3(
            u * u * a.x + 2 * u * t * c.x + t * t * b.x,
            u * u * a.y + 2 * u * t * c.y + t * t * b.y,
            u * u * a.z + 2 * u * t * c.z + t * t * b.z
        )
    }

    // MARK: - Press-and-hold magnifier

    /// Hit-test a press location (in `scnView` coordinates) and return the dice
    /// array indices of EVERY die in the formula slot under the finger, ordered
    /// for left-to-right display. Walks up the parent chain so taps on textured
    /// face children resolve back to their owning die node, then expands to the
    /// full formula slot — for a d100 the tens die comes first (left, reads
    /// naturally as the "tens" digit of a 2-digit number) and the ones die
    /// second; for any standalone kind the result is just `[index]`. Returns
    /// `[]` for taps on empty space or on dice that haven't settled (no rolled
    /// face yet to magnify).
    func diceInSlot(at point: CGPoint) -> [Int] {
        guard let scnView else { return [] }
        let hits = scnView.hitTest(point, options: nil)
        for hit in hits {
            var current: SCNNode? = hit.node
            while let node = current {
                if let tappedIdx = dice.firstIndex(where: { $0.node === node }) {
                    guard dice[tappedIdx].rolledFace != nil else { return [] }
                    let slot = dice[tappedIdx].formulaIndex
                    let group = dice.indices.filter { dice[$0].formulaIndex == slot }
                    // Tens-then-ones puts the tens digit on the left so the pair
                    // reads as a 2-digit number (e.g. "30" + "7" → thirty-seven).
                    // For standalone slots there's only one die, so the sort is a
                    // no-op.
                    return group.sorted { lhs, rhs in
                        let lTens = dice[lhs].role == .d100Tens
                        let rTens = dice[rhs].role == .d100Tens
                        if lTens != rTens { return lTens }
                        return lhs < rhs
                    }
                }
                current = node.parent
            }
        }
        return []
    }

    /// Snaps the magnifier camera at `slot` directly above the die at `index`,
    /// looking straight down, with screen-up aligned to the rolled face's
    /// digit-up direction (transformed through the die's rest orientation and
    /// flattened onto the horizontal plane).
    ///
    /// The face the camera orients to is the one whose outward normal is most
    /// aligned with world +Y — for d6/d8/d10/d12/d20 this is the rolled face on
    /// top; for d4 the rolled face is the bottom (hidden), so this picks one
    /// of the three visible side faces, which all carry the result digit at
    /// their image-apex anyway. The pick is deterministic but somewhat
    /// arbitrary for d4 — only one of the three side digits ends up upright,
    /// the other two are rotated 120°/240° in screen space.
    func positionMagnifier(slot: Int, forDieIndex index: Int) {
        guard magnifierCameras.indices.contains(slot),
              dice.indices.contains(index) else { return }
        let die = dice[index]
        let pres = die.node.presentation
        let dieOrient = pres.simdOrientation
        let dieCenter = SIMD3<Float>(pres.position)

        var bestFace: FaceSpec?
        var bestY: Float = -2
        for face in faceSpecs(for: die.kind) {
            let world = dieOrient.act(face.normal)
            if world.y > bestY {
                bestY = world.y
                bestFace = face
            }
        }

        // Default fallback: world -Z. Rarely used — only triggers if the chosen
        // face's digit-up happens to be perfectly vertical in world space.
        var cameraUp = SIMD3<Float>(0, 0, -1)
        if let face = bestFace {
            let worldDigitUp = dieOrient.act(face.digitUp)
            let horizontal = SIMD3<Float>(worldDigitUp.x, 0, worldDigitUp.z)
            let len = simd_length(horizontal)
            if len > 0.001 {
                cameraUp = horizontal / len
            }
        }

        let cameraHeight: Float = 5.0
        let camera = magnifierCameras[slot]
        camera.simdPosition = dieCenter + SIMD3<Float>(0, cameraHeight, 0)
        // SCNCamera's local "forward" is -Z, so localFront = (0, 0, -1).
        camera.simdLook(
            at: dieCenter,
            up: cameraUp,
            localFront: SIMD3<Float>(0, 0, -1)
        )
    }

    /// Wires an external `SCNView` (the magnifier overlay) to render this same
    /// scene through the camera at `slot`. Called from `MagnifierView.makeUIView`.
    func attachMagnifier(to view: SCNView, slot: Int) {
        guard magnifierCameras.indices.contains(slot) else { return }
        view.scene = scene
        view.pointOfView = magnifierCameras[slot]
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
        case .d6, .d8, .d10, .d12, .d20:   target = [0,  1, 0]   // top face = result (parallel face up)
        case .d100:            target = [0,  1, 0]   // unreachable — d100 dice carry kind=.d10
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
