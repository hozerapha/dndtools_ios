import SwiftUI

/// Modal that opens when the user taps a spell. Shows the spell text, lets
/// the player pick an upcast slot level (if there are higher slots available),
/// then commits the cast on confirm: consumes the slot resource, applies
/// upcast scaling to the spell's recipes, and routes any rolls through the
/// existing dice-tab handoff.
///
/// Cantrips skip the slot picker entirely — `Cast` is the only action.
struct SpellCastSheet: View {
    @Binding var character: Character
    let spell: SpellDefinition
    /// Called after the slot is consumed with the (possibly scaled) recipes
    /// to push to the dice tab. The sheet dismisses itself afterward.
    let onResolved: ([ResolvedAction]) -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: Int

    init(
        character: Binding<Character>,
        spell: SpellDefinition,
        onResolved: @escaping ([ResolvedAction]) -> Void
    ) {
        self._character = character
        self.spell = spell
        self.onResolved = onResolved
        // Default cast level = spell's base level (or 0 for cantrips).
        self._selectedLevel = State(initialValue: spell.level)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGrid
                    if !spell.isCantrip {
                        slotPicker
                    }
                    descriptionCard
                    if let higher = spell.higherLevel, !higher.isEmpty {
                        higherLevelCard(higher)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(spell.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cast") { cast() }
                        .bold()
                        .disabled(!canCast)
                }
            }
        }
    }

    // MARK: - Subviews

    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                MetadataChip(label: "Level", value: spell.isCantrip ? "Cantrip" : "\(spell.level)")
                MetadataChip(label: "School", value: spell.school.displayName)
                MetadataChip(label: "Time", value: spell.castingTime.shortLabel)
            }
            HStack(spacing: 14) {
                MetadataChip(label: "Range", value: spell.range.shortLabel)
                MetadataChip(label: "Comp", value: spell.components.shortLabel)
                MetadataChip(label: "Dur", value: spell.duration.shortLabel)
            }
        }
        .padding(.top, 4)
    }

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast at slot level")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(availableLevels, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        VStack(spacing: 2) {
                            Text("L\(level)")
                                .font(.subheadline.weight(.semibold))
                            if let slot = slotResource(forLevel: level) {
                                Text("\(slot.current) / \(slot.max)")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            level == selectedLevel
                                ? Color.accentColor.opacity(0.22)
                                : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(level == selectedLevel ? Color.accentColor : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    level == selectedLevel ? Color.accentColor.opacity(0.5) : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasSlotAtLevel(level))
                    .opacity(hasSlotAtLevel(level) ? 1 : 0.45)
                }
            }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spell.description)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func higherLevelCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("At Higher Levels")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Slot context

    private var slotResources: [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: content)
            .filter {
                if case .spellSlot = $0.definition.displayHint { return true }
                return false
            }
    }

    /// Slot levels visible in the picker — from the spell's base level up to
    /// the highest level the caster has slots for.
    private var availableLevels: [Int] {
        guard !spell.isCantrip else { return [] }
        let maxLevel = slotResources.compactMap { resolved -> Int? in
            guard case .spellSlot(let level) = resolved.definition.displayHint else { return nil }
            return level
        }.max() ?? spell.level
        return Array(spell.level...max(spell.level, maxLevel))
    }

    private func slotResource(forLevel level: Int) -> ResolvedResource? {
        slotResources.first {
            if case .spellSlot(let l) = $0.definition.displayHint { return l == level }
            return false
        }
    }

    private func hasSlotAtLevel(_ level: Int) -> Bool {
        guard let resolved = slotResource(forLevel: level) else { return false }
        return resolved.current > 0
    }

    private var canCast: Bool {
        spell.isCantrip || hasSlotAtLevel(selectedLevel)
    }

    // MARK: - Cast

    private func cast() {
        // Cantrips: no slot consumption.
        if !spell.isCantrip {
            guard let resolved = slotResource(forLevel: selectedLevel) else { return }
            _ = ResourceCalculator.consume(
                amount: 1,
                from: resolved.definition.id,
                in: &character,
                content: content
            )
        }
        let resolvedActions = buildResolvedActions()
        onResolved(resolvedActions)
        dismiss()
    }

    /// Apply upcast scaling (if any) to the spell's recipes, then resolve them
    /// through `ActionInterpreter`. The hand-off layer takes care of pushing
    /// each rollable action into the dice tab.
    private func buildResolvedActions() -> [ResolvedAction] {
        let scaledRecipes = spell.recipes(castAtLevel: selectedLevel)
        return scaledRecipes.compactMap { recipe in
            let resolved = ActionInterpreter.resolve(
                recipe: recipe,
                character: character,
                weapon: nil
            )
            // Re-label so history reads "Magic Missile (L2)" instead of the
            // raw "Magic Missile" pulled from the recipe.
            let label: String
            if spell.isCantrip || selectedLevel == spell.level {
                label = spell.name
            } else {
                label = "\(spell.name) (L\(selectedLevel))"
            }
            return ResolvedAction(
                id: "spell_\(spell.id)_l\(selectedLevel)",
                label: label,
                formula: resolved.formula,
                description: resolved.description
            )
        }
    }
}

private struct MetadataChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
