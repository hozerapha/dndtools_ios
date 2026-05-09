import SwiftUI

/// Collapsible 18-skill list. Sort order is "by ability, then alphabetically"
/// (matches the layout most paper character sheets use), so all DEX skills sit
/// together, all WIS skills sit together, etc.
struct SkillListView: View {
    let character: Character
    @State private var expanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 4) {
                ForEach(sortedSkills, id: \.self) { skill in
                    SkillRow(character: character, skill: skill)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Skills", systemImage: "list.bullet.clipboard")
                .font(.headline)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var sortedSkills: [Skill] {
        // Ability.allCases is already in canonical STR/DEX/CON/INT/WIS/CHA order.
        let abilityOrder = Ability.allCases
        return Skill.allCases.sorted { a, b in
            let aIdx = abilityOrder.firstIndex(of: a.ability) ?? 0
            let bIdx = abilityOrder.firstIndex(of: b.ability) ?? 0
            if aIdx != bIdx { return aIdx < bIdx }
            return a.displayName < b.displayName
        }
    }
}

private struct SkillRow: View {
    let character: Character
    let skill: Skill

    var body: some View {
        let mod = CharacterCalculator.skillModifier(character: character, skill: skill)
        let level = character.proficiencies[.skill(skill)] ?? .none

        HStack(spacing: 8) {
            ProficiencyDot(level: level)
            Text(skill.displayName)
                .font(.subheadline)
            Text("(\(skill.ability.abbreviation))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(mod.formattedModifier)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct ProficiencyDot: View {
    let level: ProficiencyLevel

    var body: some View {
        Image(systemName: iconName)
            .font(.caption)
            .frame(width: 16)
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
