import SwiftUI

/// Surfaced after the character takes damage while concentrating. Shows the
/// DC, lets the player either roll the Constitution save (handed off to the
/// dice tab like any other save) or call it manually with the pass/fail
/// buttons. Failing drops concentration.
struct ConcentrationSaveSheet: View {
    @Binding var character: Character
    let check: ConcentrationCheck
    /// Called when the player taps the roll button. The host pushes the save
    /// onto the dice tab and dismisses this sheet. The host then decides
    /// whether to clear concentration based on the player's reported outcome.
    let onRollSave: (ResolvedAction) -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                damageLine
                dcBlock
                rollButton
                manualButtons
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Concentration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
    }

    private var damageLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Took \(check.damageTaken) damage")
                .font(.subheadline.weight(.semibold))
            if let spellName {
                Text("Holding \(spellName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dcBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DC \(check.dc) Constitution save")
                .font(.title3.bold().monospacedDigit())
            Text("DC = max(10, damage ÷ 2)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rollButton: some View {
        Button {
            let action = saveAction()
            onRollSave(action)
            dismiss()
        } label: {
            Label("Roll Con Save", systemImage: "dice.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    private var manualButtons: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Label("Passed", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                character.concentratingSpellID = nil
                dismiss()
            } label: {
                Label("Failed (drop)", systemImage: "xmark.octagon.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var spellName: String? {
        content.spellDefinition(id: check.spellID)?.name
    }

    /// Resolve a Con save with the character's bonus baked in, so the dice tab
    /// fires the same as any other save.
    private func saveAction() -> ResolvedAction {
        let resolved = ActionInterpreter.resolve(
            recipe: .savingThrow(ability: .constitution),
            character: character,
            weapon: nil
        )
        // Cleaner history label than the on-sheet button form.
        return ResolvedAction(
            id: "concentration_save_\(check.spellID)",
            label: "Concentration save (DC \(check.dc))",
            formula: resolved.formula,
            description: resolved.description
        )
    }
}
