import SwiftUI

/// 3-column × 2-row grid of ability cards (STR/DEX/CON on top, INT/WIS/CHA on
/// bottom). Each card surfaces score, modifier, and saving-throw bonus with a
/// proficiency indicator.
struct AbilityBlockView: View {
    let character: Character

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Ability.allCases) { ability in
                AbilityCard(character: character, ability: ability)
            }
        }
    }
}

private struct AbilityCard: View {
    let character: Character
    let ability: Ability

    var body: some View {
        let score = character.abilityScores[ability] ?? 10
        let mod = CharacterCalculator.abilityModifier(score: score)
        let saveBonus = CharacterCalculator.saveBonus(character: character, ability: ability)
        let saveProficient = (character.proficiencies[.savingThrow(ability)] ?? .none) != .none

        VStack(spacing: 4) {
            Text(ability.abbreviation)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(mod.formattedModifier)
                .font(.title.bold().monospacedDigit())
            Text("\(score)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            HStack(spacing: 3) {
                Image(systemName: saveProficient ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(saveProficient ? Color.green : Color.secondary.opacity(0.5))
                Text("save \(saveBonus.formattedModifier)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
