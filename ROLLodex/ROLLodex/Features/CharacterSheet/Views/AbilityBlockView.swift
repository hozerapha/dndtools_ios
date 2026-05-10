import SwiftUI

/// 3-column × 2-row grid of ability cards (STR/DEX/CON on top, INT/WIS/CHA on
/// bottom). Each card surfaces the score, modifier, and saving-throw bonus,
/// plus an inline trio of roll buttons for the check and another for the save.
struct AbilityBlockView: View {
    let character: Character
    let onRollCheck: (Ability, RollMode) -> Void
    let onRollSave: (Ability, RollMode) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Ability.allCases) { ability in
                AbilityCard(
                    character: character,
                    ability: ability,
                    onRollCheck: onRollCheck,
                    onRollSave: onRollSave
                )
            }
        }
    }
}

private struct AbilityCard: View {
    let character: Character
    let ability: Ability
    let onRollCheck: (Ability, RollMode) -> Void
    let onRollSave: (Ability, RollMode) -> Void

    var body: some View {
        let score = character.abilityScores[ability] ?? 10
        let mod = CharacterCalculator.abilityModifier(score: score)
        let saveBonus = CharacterCalculator.saveBonus(character: character, ability: ability)
        let saveLevel = character.proficiencies[.savingThrow(ability)] ?? .none

        VStack(spacing: 4) {
            Text(ability.abbreviation)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(mod.formattedModifier)
                .font(.title.bold().monospacedDigit())

            Text("\(score)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Text("Check")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            RollModeChips(
                accessibilityRoot: "Roll \(ability.abbreviation) check",
                onRoll: { mode in onRollCheck(ability, mode) },
                size: .compact
            )

            HStack(spacing: 3) {
                SaveProficiencyDot(level: saveLevel)
                Text("Save \(saveBonus.formattedModifier)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            RollModeChips(
                accessibilityRoot: "Roll \(ability.abbreviation) save",
                onRoll: { mode in onRollSave(ability, mode) },
                size: .compact
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SaveProficiencyDot: View {
    let level: ProficiencyLevel

    var body: some View {
        Image(systemName: iconName)
            .font(.caption2)
            .foregroundStyle(color)
    }

    private var iconName: String {
        switch level {
        case .none: return "circle"
        case .proficient: return "checkmark.circle.fill"
        case .expertise: return "star.circle.fill"
        }
    }

    private var color: Color {
        switch level {
        case .none: return .secondary.opacity(0.5)
        case .proficient: return .green
        case .expertise: return .yellow
        }
    }
}
