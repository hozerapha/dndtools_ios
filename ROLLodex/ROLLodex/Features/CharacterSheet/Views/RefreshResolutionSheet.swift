import SwiftUI

/// Modal sheet that walks the user through every refresh that needs a dice
/// roll resolved (Wand of Magic Missiles' `1d6+1` at long rest, etc.).
///
/// Phase I MVP: each row shows a TextField pre-populated with a behind-the-
/// scenes roll result, plus a reroll button if the user wants a fresh hidden
/// value. The user can also type their own number (matching the `manual`
/// resolution mode) — useful for tables that roll physical dice. `tray` mode
/// for refresh rolls is deferred (the user would have to leave this sheet,
/// roll on the dice tab, and come back — that coordination lands in a later
/// pass).
struct RefreshResolutionSheet: View {
    @Binding var character: Character
    let pendingRefreshes: [PendingRefresh]
    let onDismiss: () -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var rolls: [String: String] = [:]

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
                    Text("Each row is pre-rolled behind the scenes. Tap the field to type your own value, or use the dice button to re-roll.")
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
                }
            }
            .onAppear {
                if rolls.isEmpty {
                    for refresh in pendingRefreshes {
                        rolls[refresh.id] = String(rollHidden(refresh.formula))
                    }
                }
            }
        }
    }

    private func reroll(_ refresh: PendingRefresh) {
        rolls[refresh.id] = String(rollHidden(refresh.formula))
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
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reroll \(refresh.resourceName)")
            }
        }
        .padding(.vertical, 2)
    }
}
