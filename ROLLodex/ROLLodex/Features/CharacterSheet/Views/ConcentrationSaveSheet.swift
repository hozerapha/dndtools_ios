import SwiftUI

/// Surfaced after the character takes damage while concentrating. Shows the
/// DC, lets the player roll the Constitution save right here in the Quick
/// Roll mini tray — the outcome auto-applies against the DC (fail drops
/// concentration) — or call it manually with the pass/fail buttons for
/// physical-dice tables.
struct ConcentrationSaveSheet: View {
    @Binding var character: Character
    let check: ConcentrationCheck

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var quickRoll: QuickRollRequest?

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
        .overlay {
            if let request = quickRoll {
                QuickRollOverlay(
                    request: request,
                    onResult: { result in
                        // The app rolled it, so it's trusted: failing the DC
                        // drops concentration immediately. The overlay stays
                        // up so the player sees the number vs the DC behind.
                        if result.total < check.dc {
                            character.stopConcentrating()
                        }
                    },
                    onDismiss: {
                        quickRoll = nil
                        dismiss()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: quickRoll != nil)
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
            let resolved = ActionInterpreter.resolve(
                recipe: .savingThrow(ability: .constitution),
                character: character,
                weapon: nil
            )
            var formula = resolved.formula
            if formula == nil {
                var d20 = DiceFormula()
                d20.groups.append(DiceGroup(kind: .d20, count: 1))
                formula = d20
            }
            quickRoll = QuickRollRequest(
                formula: formula ?? DiceFormula(),
                label: "Concentration save (DC \(check.dc))"
            )
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
                character.stopConcentrating()
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
}
