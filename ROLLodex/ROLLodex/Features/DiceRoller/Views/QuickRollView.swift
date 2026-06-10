import SwiftUI

/// One in-sheet roll: "roll this small formula right here, right now."
/// Identity is per-request so re-presenting the overlay always re-rolls.
struct QuickRollRequest: Identifiable, Equatable {
    let id = UUID()
    let formula: DiceFormula
    let label: String
}

/// Floating mini dice tray (roadmap item 14b). Hosts its OWN
/// `DiceSceneController` with `.compact` framing in a small card over the
/// current screen, throws the dice immediately, shows the total, records the
/// roll to history, and hands the result back exactly once. For "one die,
/// answer now" moments (death saves, level-up HP, concentration saves) —
/// bigger rolls keep the full dice-tab handoff with its chips and modes.
///
/// Dismissal is blocked while dice are in motion: tearing the scene down
/// mid-physics would strand the roll's continuation.
struct QuickRollOverlay: View {
    let request: QuickRollRequest
    /// Called once, when the dice settle. The host applies the outcome
    /// (tally a death save, bank HP, …) — the overlay stays up so the player
    /// sees what happened, until they tap Done / the backdrop.
    let onResult: (RollResult) -> Void
    let onDismiss: () -> Void

    @Environment(HistoryStore.self) private var history
    @State private var controller = DiceSceneController(framing: .compact)
    @State private var result: RollResult?
    @State private var isRolling = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isRolling { onDismiss() }
                }

            card
                .padding(.horizontal, 24)
        }
        .task(id: request.id) { await roll() }
    }

    private var card: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(request.label)
                    .font(.headline)
                Spacer()
                if let result {
                    Text("\(result.total)")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .foregroundStyle(totalColor(for: result))
                        .contentTransition(.numericText())
                }
            }

            SceneKitView(controller: controller, allowsCameraControl: false)
                .frame(height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                onDismiss()
            } label: {
                Text(result == nil ? "Rolling…" : "Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(result == nil)
        }
        .padding(14)
        // Constrained card: the post-settle camera zoom makes the die fill
        // the small viewport, so the tray doesn't need to be big.
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func totalColor(for result: RollResult) -> Color {
        if result.hasCriticalSuccess { return .yellow }
        if result.hasCriticalFail { return .red }
        return .primary
    }

    private func roll() async {
        guard !isRolling, result == nil else { return }
        isRolling = true
        controller.setDice(formula: request.formula)
        // One beat for SceneKit to place the dice (and for the card's
        // entrance to land) before the throw.
        try? await Task.sleep(for: .milliseconds(120))

        let roller = DiceRoller()
        var values = await controller.rollAllAsync()
        let rerolls = roller.rerollIndices(formula: request.formula, values: values)
        if !rerolls.isEmpty {
            values = await controller.rethrowDiceAsync(at: Set(rerolls))
        }
        let rolled = roller.resultFrom(
            formula: request.formula,
            values: values,
            label: request.label
        )
        // Zoom in on wherever the dice stopped, magnifier-style, so the face
        // is readable in the small card; the total fades in alongside.
        controller.focusCameraOnSettledDice()
        result = rolled
        isRolling = false
        // The dice tab's history stays the single ledger for every roll the
        // app makes, wherever it was rolled from.
        history.record(rolled)
        onResult(rolled)
    }
}
