import SwiftUI

/// Modal sheet that walks the user through every refresh that needs a dice
/// roll resolved (Wand of Magic Missiles' `1d6+1` at long rest, etc.).
///
/// Each refresh row waits for the player to resolve it: tap the dice button
/// to tumble the formula in the Quick Roll mini tray (the settled total
/// lands in the row), or type a number rolled at the table. Nothing is
/// pre-rolled — the dice are the point. Apply stays disabled until every
/// row has a value.
struct RefreshResolutionSheet: View {
    @Binding var character: Character
    let pendingRefreshes: [PendingRefresh]
    let onDismiss: () -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var rolls: [String: String] = [:]
    @State private var quickRoll: QuickRollRequest?
    /// Which refresh row the open mini tray is rolling for.
    @State private var quickRollTargetID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(pendingRefreshes) { refresh in
                        RefreshRow(
                            refresh: refresh,
                            value: Binding(
                                get: { rolls[refresh.id] ?? "" },
                                set: { rolls[refresh.id] = $0 }
                            ),
                            onReroll: { reroll(refresh) }
                        )
                    }
                } header: {
                    Text("Refresh rolls")
                } footer: {
                    Text("Tap the dice button to roll each refresh, or type a value you rolled at the table.")
                }
            }
            .navigationTitle("Apply Rest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { apply() }
                        .bold()
                        .disabled(!allRowsResolved)
                }
            }
        }
        .overlay {
            if let request = quickRoll {
                QuickRollOverlay(
                    request: request,
                    onResult: { result in
                        if let id = quickRollTargetID {
                            rolls[id] = String(result.total)
                        }
                    },
                    onDismiss: {
                        quickRoll = nil
                        quickRollTargetID = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: quickRoll != nil)
    }

    /// Every row needs a parseable number before Apply unlocks — applying a
    /// blank row would silently refresh by 0.
    private var allRowsResolved: Bool {
        pendingRefreshes.allSatisfy { Int(rolls[$0.id] ?? "") != nil }
    }

    private func reroll(_ refresh: PendingRefresh) {
        // Real dice in the mini tray; the settled total lands in the row.
        // Parse failure (content-authored formulas, shouldn't happen) falls
        // back to a hidden roll so the row stays usable.
        guard let parsed = try? DiceFormulaParser().parse(refresh.formula) else {
            rolls[refresh.id] = String(rollHidden(refresh.formula))
            return
        }
        quickRollTargetID = refresh.id
        quickRoll = QuickRollRequest(formula: parsed, label: "\(refresh.resourceName) refresh")
    }

    private func apply() {
        for refresh in pendingRefreshes {
            let amount = Int(rolls[refresh.id] ?? "") ?? 0
            ResourceCalculator.applyResolvedRefresh(
                resourceID: refresh.resourceID,
                amount: amount,
                in: &character,
                content: content
            )
        }
        onDismiss()
        dismiss()
    }

    /// Parse the formula and roll it without any UI. Returns the total.
    /// On parse failure (shouldn't happen for content-authored formulas)
    /// returns 0 so the row stays editable.
    private func rollHidden(_ formula: String) -> Int {
        guard let parsed = try? DiceFormulaParser().parse(formula) else { return 0 }
        return DiceRoller().roll(parsed).total
    }
}

private struct RefreshRow: View {
    let refresh: PendingRefresh
    @Binding var value: String
    let onReroll: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(refresh.resourceName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(refresh.currentBeforeRefresh) / \(refresh.max)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Text(refresh.formula)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
                    .focused($focused)
                    .textFieldStyle(.roundedBorder)
                Button(action: onReroll) {
                    Image(systemName: "dice.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Roll \(refresh.resourceName)")
            }
        }
        .padding(.vertical, 2)
    }
}
