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
    @State private var showAddSpell = false

    var body: some View {
        // Show the card for any caster, OR any character with granted spells
        // (a Tiefling Fighter still has a Fiendish Legacy cantrip).
        if !hasAnySpellcasting && grantedSpells.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if !slotResources.isEmpty {
                        SlotsRow(slots: slotResources)
                    }
                    if !grantedSpells.isEmpty {
                        GrantedSpellsSection(
                            granted: grantedSpells,
                            slotResources: slotResources,
                            onTap: { spell in onCast(spell, spell.level) }
                        )
                    }
                    if hasAnySpellcasting {
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
                                    onTap: { spell in onCast(spell, max(group.level, spell.level)) },
                                    onForget: { spell in forget(spell) }
                                )
                            }
                        }
                        Button {
                            showAddSpell = true
                        } label: {
                            Label("Add Spell", systemImage: "plus.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Spells", systemImage: "sparkles")
                    .font(.headline)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .sheet(isPresented: $showAddSpell) {
                AddSpellSheet(character: $character)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Drop the spell from every list that carries it. Long-press on a spell
    /// row exposes this — useful for cleaning up test characters and for the
    /// eventual "Forget Spell" gesture on prepared casters.
    private func forget(_ spell: SpellDefinition) {
        character.spells.knownIDs.removeAll { $0 == spell.id }
        character.spells.preparedIDs.removeAll { $0 == spell.id }
        character.spells.spellbookIDs.removeAll { $0 == spell.id }
    }

    private var hasAnySpellcasting: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting != nil
        }
    }

    /// Species-granted, always-prepared spells (lineage / legacy picks). Live-
    /// resolved; not stored on the character's own lists.
    private var grantedSpells: [CharacterSpellGrants.GrantedSpell] {
        CharacterSpellGrants.resolve(character: character, content: content)
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

/// Always-prepared spells conferred by a species trait (Fiendish Legacy,
/// Elven Lineage, …). Each row shows the source trait; cantrips are always
/// castable, leveled grants need a slot like any other spell.
private struct GrantedSpellsSection: View {
    let granted: [CharacterSpellGrants.GrantedSpell]
    let slotResources: [ResolvedResource]
    let onTap: (SpellDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Granted")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(granted) { item in
                    Button { onTap(item.spell) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.spell.school.systemImage)
                                .font(.caption)
                                .frame(width: 18)
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.spell.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(levelLabel(item.spell)) · \(item.sourceLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "wand.and.rays")
                                .font(.subheadline)
                                .foregroundStyle(canCast(item.spell) ? Color.accentColor : Color.secondary.opacity(0.4))
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCast(item.spell))
                    .opacity(canCast(item.spell) ? 1 : 0.55)
                }
            }
        }
    }

    private func levelLabel(_ spell: SpellDefinition) -> String {
        spell.isCantrip ? "Cantrip" : "Level \(spell.level)"
    }

    private func canCast(_ spell: SpellDefinition) -> Bool {
        if spell.isCantrip { return true }
        return slotResources.contains { resolved in
            guard case .spellSlot(let slotLevel) = resolved.definition.displayHint else { return false }
            return slotLevel >= spell.level && resolved.current > 0
        }
    }
}

private struct SpellLevelSection: View {
    let level: Int
    let spells: [SpellDefinition]
    let slotResources: [ResolvedResource]
    let onTap: (SpellDefinition) -> Void
    let onForget: (SpellDefinition) -> Void

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
                        onTap: { onTap(spell) },
                        onForget: { onForget(spell) }
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
    let onForget: () -> Void

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
        .contextMenu {
            Button(role: .destructive) {
                onForget()
            } label: {
                Label("Forget", systemImage: "minus.circle")
            }
        }
    }
}

/// Picker that lists every spell in the content store, grouped by level, with
/// a chip showing whether the character already knows it. Tapping a "new"
/// row appends to `knownIDs`. No class-list filtering in v1 — the player can
/// grant any spell. Sheet-style presentation matches `AddConditionSheet`.
struct AddSpellSheet: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(spellsByLevel, id: \.level) { group in
                    Section(header: Text(headerText(for: group.level))) {
                        ForEach(group.spells) { spell in
                            row(for: spell)
                        }
                    }
                }
            }
            .navigationTitle("Add Spell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for spell: SpellDefinition) -> some View {
        let inAllLists = character.spells.knownIDs.contains(spell.id)
            && character.spells.preparedIDs.contains(spell.id)
            && character.spells.spellbookIDs.contains(spell.id)
        return Button {
            // Idempotent reconcile: ensure the spell is in every list. Fixes
            // orphans from older flows that only wrote to one list (a spell
            // in `knownIDs` alone is invisible if `preparedIDs` is non-empty,
            // so the user can't long-press to forget it from the main list).
            if !character.spells.knownIDs.contains(spell.id) {
                character.spells.knownIDs.append(spell.id)
            }
            if !character.spells.preparedIDs.contains(spell.id) {
                character.spells.preparedIDs.append(spell.id)
            }
            if !character.spells.spellbookIDs.contains(spell.id) {
                character.spells.spellbookIDs.append(spell.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: spell.school.systemImage)
                    .foregroundStyle(.purple)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spell.name)
                        .font(.subheadline.weight(.semibold))
                    Text(spell.school.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if inAllLists {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(inAllLists)
    }

    private var spellsByLevel: [(level: Int, spells: [SpellDefinition])] {
        Dictionary(grouping: content.allSpells, by: \.level)
            .map { (level: $0.key, spells: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.level < $1.level }
    }

    private func headerText(for level: Int) -> String {
        switch level {
        case 0: return "Cantrips"
        case 1: return "1st Level"
        case 2: return "2nd Level"
        case 3: return "3rd Level"
        default: return "\(level)th Level"
        }
    }
}
