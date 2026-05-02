import SwiftUI

struct SavePresetSheet: View {
    let formula: DiceFormula
    @Environment(PresetStore.self) private var presets
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Greatsword Attack", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Formula") {
                    Text(formula.displayString)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let finalName = name.trimmingCharacters(in: .whitespaces)
                        presets.add(
                            name: finalName.isEmpty ? formula.displayString : finalName,
                            formula: formula
                        )
                        dismiss()
                    }
                    .disabled(formula.totalDiceCount == 0)
                }
            }
        }
    }
}
