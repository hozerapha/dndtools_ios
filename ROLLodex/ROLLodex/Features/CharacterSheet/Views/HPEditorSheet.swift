import SwiftUI

/// Modal sheet for batch HP edits — typing an exact damage/healing amount,
/// adjusting max HP, and managing temp HP. The header bar's inline -/+ buttons
/// cover quick deltas; this sheet covers the cases where you need a number
/// pad or want to bump max HP after a level up.
struct HPEditorSheet: View {
    @Binding var character: Character
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
                    Stepper(value: $character.maxHP, in: 1...999) {
                        LabeledContent("Maximum") {
                            Text("\(character.maxHP)").monospacedDigit()
                        }
                    }
                    .onChange(of: character.maxHP) { _, new in
                        // Clamp current HP to the new ceiling so we never
                        // display "12 / 10".
                        if character.currentHP > new {
                            character.currentHP = new
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
            var remaining = amount
            if character.tempHP > 0 {
                let absorbed = min(character.tempHP, remaining)
                character.tempHP -= absorbed
                remaining -= absorbed
            }
            character.currentHP = max(0, character.currentHP - remaining)
        }
        deltaText = ""
    }
}
