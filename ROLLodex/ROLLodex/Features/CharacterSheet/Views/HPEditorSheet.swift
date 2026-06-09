import SwiftUI

/// Modal sheet for batch HP edits — typing an exact damage/healing amount,
/// adjusting max HP, and managing temp HP. The header bar's inline -/+ buttons
/// cover quick deltas; this sheet covers the cases where you need a number
/// pad or want to bump max HP after a level up.
struct HPEditorSheet: View {
    @Binding var character: Character
    /// Called when applying damage actually drains current HP while
    /// concentrating — host raises the concentration-save sheet from it. Nil
    /// when concentration isn't relevant.
    var onConcentrationCheck: ((ConcentrationCheck) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var deltaText: String = ""
    @FocusState private var deltaFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick adjust") {
                    HStack(spacing: 10) {
                        TextField("Amount", text: $deltaText)
                            .keyboardType(.numberPad)
                            .focused($deltaFocused)
                            .submitLabel(.done)
                        Button {
                            applyDelta(sign: -1)
                        } label: {
                            Label("Damage", systemImage: "burst.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        Button {
                            applyDelta(sign: +1)
                        } label: {
                            Label("Heal", systemImage: "cross.case.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                    LabeledContent("Current") {
                        Text("\(character.currentHP) / \(character.maxHP)")
                            .monospacedDigit()
                    }
                }

                Section("Max HP") {
                    // Route through setMaxHP so the manual edit writes into
                    // rolledHP — otherwise the next CON-driven recalculation
                    // would stomp it. setMaxHP also clamps current HP to the
                    // new ceiling so we never display "12 / 10".
                    Stepper(
                        value: Binding(
                            get: { character.maxHP },
                            set: { character.setMaxHP($0) }
                        ),
                        in: 1...999
                    ) {
                        LabeledContent("Maximum") {
                            Text("\(character.maxHP)").monospacedDigit()
                        }
                    }
                }

                Section("Temporary HP") {
                    Stepper(value: $character.tempHP, in: 0...200) {
                        LabeledContent("Temp") {
                            Text("\(character.tempHP)").monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Hit Points")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.async { deltaFocused = true }
            }
        }
    }

    /// Damage drains temp HP first (5e rule), then dips into current HP.
    /// Healing fills current HP toward max. Sign is +1 for heal, -1 for damage.
    private func applyDelta(sign: Int) {
        guard let amount = Int(deltaText), amount > 0 else { return }
        if sign > 0 {
            character.currentHP = min(character.maxHP, character.currentHP + amount)
        } else {
            var copy = character
            let pendingCheck = copy.applyDamage(amount)
            character = copy
            if let pendingCheck {
                // Dismiss first so the concentration sheet can rise on the
                // parent. SwiftUI won't stack two sheets from the same anchor.
                dismiss()
                onConcentrationCheck?(pendingCheck)
            }
        }
        deltaText = ""
    }
}
