import SwiftUI

/// Collapsible 18-skill list, sorted alphabetically by display name. Each row
/// carries an inline trio of roll buttons (normal / advantage / disadvantage)
/// so the dice handoff happens with one explicit tap.
struct SkillListView: View {
    let character: Character
    let onRoll: (Skill, RollMode) -> Void
    @State private var expanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 4) {
                ForEach(sortedSkills, id: \.self) { skill in
                    SkillRow(character: character, skill: skill, onRoll: onRoll)
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
        Skill.allCases.sorted { $0.displayName < $1.displayName }
    }
}

private struct SkillRow: View {
    let character: Character
    let skill: Skill
    let onRoll: (Skill, RollMode) -> Void

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
                .frame(minWidth: 32, alignment: .trailing)
            RollModeChips(accessibilityRoot: "Roll \(skill.displayName)") { mode in
                onRoll(skill, mode)
            }
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
