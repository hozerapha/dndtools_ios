import SwiftUI

/// Collapsible 18-skill list, sorted alphabetically by display name. Each row
/// carries an inline trio of roll buttons (normal / advantage / disadvantage)
/// so the dice handoff happens with one explicit tap.
struct SkillListView: View {
    let character: Character
    let onRoll: (Skill, RollMode) -> Void
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true

    var body: some View {
        // Resolve Jack of All Trades once for the whole table; rows read it to
        // add the half-PB to non-proficient skills and show a ½ indicator.
        let jackOfAllTrades = CharacterCalculator.hasJackOfAllTrades(character: character, content: content)
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 4) {
                ForEach(sortedSkills, id: \.self) { skill in
                    SkillRow(
                        character: character,
                        skill: skill,
                        jackOfAllTrades: jackOfAllTrades,
                        onRoll: onRoll
                    )
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
    let jackOfAllTrades: Bool
    let onRoll: (Skill, RollMode) -> Void

    var body: some View {
        let mod = CharacterCalculator.skillModifier(
            character: character, skill: skill, jackOfAllTrades: jackOfAllTrades
        )
        // Resolved level (background + class-skill grants + expertise), so the
        // dot reflects class skills picked at creation or in the Features tab.
        let level = CharacterCalculator.skillProficiencyLevel(character: character, skill: skill)

        HStack(spacing: 8) {
            // The dot shows a diagonal half-fill on non-proficient skills that
            // Jack of All Trades is boosting.
            ProficiencyDot(level: level, jackOfAllTrades: jackOfAllTrades)
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
    /// Whether the character has Jack of All Trades. Only changes the dot for
    /// non-proficient skills (where the half-PB actually applies).
    var jackOfAllTrades: Bool = false

    /// A non-proficient skill the half-PB is boosting gets the diagonal-split
    /// treatment instead of the empty circle.
    private var showsJoAT: Bool { level == .none && jackOfAllTrades }

    var body: some View {
        Group {
            if showsJoAT {
                // Half-filled circle rotated 45° → a diagonal split filled on
                // one side, marking Jack of All Trades' partial proficiency.
                Image(systemName: "circle.lefthalf.filled")
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Jack of All Trades (half proficiency)")
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(color)
            }
        }
        .font(.caption)
        .frame(width: 16)
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
