import SwiftUI

/// Sheet card listing a caster's spell slots and their castable spells. Two
/// sections:
/// - **Slots**: a row per spell level the character has slots in (synthesized
///   from the class's `slotTable` and routed through the same resources
///   plumbing). Shows current/max dots; the user can manually adjust via the
///   resources card if needed.
/// - **Spells**: prepared / known list, grouped by level. Tapping a row opens
///   `SpellCastSheet` to pick a slot level and cast.
///
/// Returns an empty view if the character has no spellcasting class — the
/// fighter / barbarian sheet just doesn't see it.
struct SpellListView: View {
    @Binding var character: Character
    let onCast: (SpellDefinition, Int) -> Void
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true

    var body: some View {
        if !hasAnySpellcasting {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if !slotResources.isEmpty {
                        SlotsRow(slots: slotResources)
                    }
                    if castableSpells.isEmpty {
                        Text("No spells prepared")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(spellsByLevel, id: \.level) { group in
                            SpellLevelSection(
                                level: group.level,
                                spells: group.spells,
                                slotResources: slotResources,
                                onTap: { spell in onCast(spell, max(group.level, spell.level)) }
                            )
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Spells", systemImage: "sparkles")
                    .font(.headline)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var hasAnySpellcasting: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting != nil
        }
    }

    private var slotResources: [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: content)
            .filter { resolved in
                if case .spellSlot = resolved.definition.displayHint { return true }
                return false
            }
    }

    /// The list of spells the character can actually cast right now. Reads
    /// from `preparedIDs` if non-empty (wizards / clerics) else `knownIDs`
    /// (sorcerers / warlocks). Cantrips are always castable; we union them
    /// in so a wizard's cantrip choice survives prep curation.
    private var castableSpells: [SpellDefinition] {
        let primaryIDs = character.spells.preparedIDs.isEmpty
            ? character.spells.knownIDs
            : character.spells.preparedIDs
        let ids = Set(primaryIDs)
        return ids.compactMap { content.spellDefinition(id: $0) }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level < rhs.level }
                return lhs.name < rhs.name
            }
    }

    private var spellsByLevel: [(level: Int, spells: [SpellDefinition])] {
        Dictionary(grouping: castableSpells, by: \.level)
            .map { (level: $0.key, spells: $0.value) }
            .sorted { $0.level < $1.level }
    }
}

/// Compact dots-per-slot-level row at the top of the card.
private struct SlotsRow: View {
    let slots: [ResolvedResource]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slots")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(slots) { slot in
                    HStack(spacing: 6) {
                        Text(levelLabel(for: slot))
                            .font(.caption.weight(.semibold))
                            .frame(width: 36, alignment: .leading)
                        ForEach(0..<slot.max, id: \.self) { i in
                            Image(systemName: i < slot.current ? "circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(i < slot.current ? Color.accentColor : Color.secondary.opacity(0.4))
                        }
                        Spacer()
                        Text("\(slot.current) / \(slot.max)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func levelLabel(for resource: ResolvedResource) -> String {
        if case .spellSlot(let level) = resource.definition.displayHint {
            switch level {
            case 1: return "L1"
            case 2: return "L2"
            case 3: return "L3"
            case 4: return "L4"
            case 5: return "L5"
            case 6: return "L6"
            case 7: return "L7"
            case 8: return "L8"
            case 9: return "L9"
            default: return "L?"
            }
        }
        return ""
    }
}

private struct SpellLevelSection: View {
    let level: Int
    let spells: [SpellDefinition]
    let slotResources: [ResolvedResource]
    let onTap: (SpellDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(spells) { spell in
                    SpellRow(
                        spell: spell,
                        canCast: canCast(spell),
                        onTap: { onTap(spell) }
                    )
                }
            }
        }
    }

    private var headerText: String {
        switch level {
        case 0: return "Cantrips"
        case 1: return "1st Level"
        case 2: return "2nd Level"
        case 3: return "3rd Level"
        default: return "\(level)th Level"
        }
    }

    /// Cantrips are always castable; leveled spells need an available slot at
    /// or above their base level.
    private func canCast(_ spell: SpellDefinition) -> Bool {
        if spell.isCantrip { return true }
        return slotResources.contains { resolved in
            guard case .spellSlot(let slotLevel) = resolved.definition.displayHint else { return false }
            return slotLevel >= spell.level && resolved.current > 0
        }
    }
}

private struct SpellRow: View {
    let spell: SpellDefinition
    let canCast: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: spell.school.systemImage)
                    .font(.caption)
                    .frame(width: 18)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spell.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(spell.castingTime.shortLabel)
                        Text("·")
                        Text(spell.range.shortLabel)
                        if spell.duration.requiresConcentration {
                            Text("· Conc")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "wand.and.rays")
                    .font(.subheadline)
                    .foregroundStyle(canCast ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canCast)
        .opacity(canCast ? 1 : 0.55)
    }
}
