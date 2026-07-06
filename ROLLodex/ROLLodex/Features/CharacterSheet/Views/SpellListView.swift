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
                        // Prepared casters (druid, cleric, paladin, wizard):
                        // one "Prepared: X / N" line per prepared-caster class
                        // (each class preps separately in 5e multiclass).
                        ForEach(preparedCounts, id: \.classID) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "checklist")
                                    .font(.caption2)
                                Text(preparedCounts.count > 1
                                     ? "\(item.className) prepared: \(item.count) / \(item.max)"
                                     : "Prepared: \(item.count) / \(item.max)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.count > item.max ? .red : .secondary)
                            }
                            .padding(.top, 2)
                        }
                        Button {
                            showAddSpell = true
                        } label: {
                            Label(spellButtonLabel, systemImage: "plus.circle")
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

    /// Drop the spell from every list that carries it — including every
    /// class's prepared bucket. Long-press on a spell row exposes this.
    private func forget(_ spell: SpellDefinition) {
        character.spells.knownIDs.removeAll { $0 == spell.id }
        character.spells.preparedIDs.removeAll { $0 == spell.id }
        character.spells.spellbookIDs.removeAll { $0 == spell.id }
        for classID in character.spells.preparedByClass.keys {
            character.spells.preparedByClass[classID]?.removeAll { $0 == spell.id }
        }
    }

    private var hasAnySpellcasting: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting != nil
        }
    }

    private var isPreparedCaster: Bool {
        CharacterCalculator.isPreparedCaster(character: character, content: content)
    }

    /// Button label matches the picker's mode for the primary casting class:
    /// prepared casters manage a daily list, known casters learn spells, the
    /// wizard (and multi-mode multiclassers) get the generic label.
    private var spellButtonLabel: String {
        let rules = character.classEntries.compactMap {
            content.classDefinition(id: $0.classID)?.spellcasting?.preparedRule
        }
        if rules.count > 1 { return "Manage Spells" }
        switch rules.first {
        case .preparedFromAll:        return "Prepare Spells"
        case .knownList, .pactMagic:  return "Learn Spells"
        case .preparedFromBook, .none: return "Add Spell"
        }
    }

    /// One (class, prepared, cap) triple per prepared-caster class — drives
    /// the "Prepared: X / N" line(s) above the Prepare Spells button.
    private var preparedCounts: [(classID: String, className: String, count: Int, max: Int)] {
        CharacterCalculator.preparedCasterClasses(character: character, content: content)
            .compactMap { sc in
                guard let max = CharacterCalculator.maxPreparedSpells(
                    character: character, content: content, forClassID: sc.classID
                ) else { return nil }
                let count = CharacterCalculator.preparedLeveledCount(
                    character: character, content: content, forClassID: sc.classID
                )
                let name = content.classDefinition(id: sc.classID)?.name ?? sc.classID
                return (sc.classID, name, count, max)
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

    /// The list of spells the character can actually cast right now: the
    /// union of every class's prepared bucket (+ the legacy flat list) and
    /// the known list — a Druid/Sorcerer multiclass casts from both.
    private var castableSpells: [SpellDefinition] {
        let ids = Set(character.spells.allPreparedIDs).union(character.spells.knownIDs)
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

/// Spell picker, grouped by level. Three modes, per the SELECTED class's rule:
/// - **Prepare mode** (`preparedFromAll` — cleric / druid / paladin): toggle
///   spells in/out of today's per-class prepared bucket, cap-enforced. Models
///   "change your prepared spells after a long rest".
/// - **Learn mode** (`knownList` / `pactMagic` — bard / sorcerer / warlock):
///   toggle spells in/out of the known list, gated by the class's
///   `spellsKnown` table. RAW you swap on level-up; edits aren't time-gated.
/// - **Add mode** (`preparedFromBook` — wizard): reconciles into every list
///   until spellbook management lands.
///
/// The pool is always the selected class's spell list
/// (`CharacterCalculator.spellList(forClassID:)`; full catalog only for
/// classes with no tagged spells). Multiclass casters get a segment picker.
struct AddSpellSheet: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    /// The casting class being edited. Defaults to the first; a segment picker
    /// appears for multiclass casters (each class picks separately, per 5e).
    @State private var selectedClassID: String?

    private enum PickMode { case prepare, learn, add }

    /// Every casting class the character has, in classEntries order.
    private var castingClasses: [(classID: String, level: Int, block: SpellcastingBlock)] {
        character.classEntries.compactMap { entry in
            guard let block = content.classDefinition(id: entry.classID)?.spellcasting else { return nil }
            return (entry.classID, entry.level, block)
        }
    }

    /// The class whose lists the toggles edit — the picked one, or the first.
    private var activeClass: (classID: String, level: Int, block: SpellcastingBlock)? {
        castingClasses.first { $0.classID == selectedClassID } ?? castingClasses.first
    }

    private var mode: PickMode {
        switch activeClass?.block.preparedRule {
        case .preparedFromAll:          return .prepare
        case .knownList, .pactMagic:    return .learn
        case .preparedFromBook, .none:  return .add
        }
    }

    /// Leveled-spell budget for the active class: prep cap (prepare mode) or
    /// the spellsKnown table (learn mode). Nil = uncapped (wizard add mode, or
    /// a known caster with no authored table).
    private var leveledBudget: Int? {
        guard let ac = activeClass else { return nil }
        switch mode {
        case .prepare:
            return CharacterCalculator.maxPreparedSpells(character: character, content: content, forClassID: ac.classID)
        case .learn:
            return CharacterCalculator.knownSpellBudget(character: character, content: content, forClassID: ac.classID)
        case .add:
            return nil
        }
    }

    private var cantripBudget: Int {
        guard let ac = activeClass else { return 0 }
        return CharacterCalculator.cantripsKnownBudget(character: character, content: content, forClassID: ac.classID) ?? 0
    }

    /// The active class's leveled/cantrip counts in whichever list this mode
    /// edits (prepared bucket or known list).
    private var editedIDs: [String] {
        guard let ac = activeClass else { return [] }
        switch mode {
        case .prepare: return character.spells.preparedByClass[ac.classID] ?? []
        case .learn:   return character.spells.knownIDs
        case .add:     return []
        }
    }

    private var leveledCount: Int {
        editedIDs.compactMap { content.spellDefinition(id: $0) }.filter { !$0.isCantrip }.count
    }

    private var cantripCount: Int {
        editedIDs.compactMap { content.spellDefinition(id: $0) }.filter { $0.isCantrip }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if mode != .add || castingClasses.count > 1 {
                    budgetSection
                }
                ForEach(spellsByLevel, id: \.level) { group in
                    Section(header: Text(headerText(for: group.level))) {
                        ForEach(group.spells) { spell in
                            row(for: spell)
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .prepare: return "Prepare Spells"
        case .learn:   return "Learn Spells"
        case .add:     return "Add Spell"
        }
    }

    /// Rule-accurate copy for the footer. Prepare mode splits based on
    /// whether the class has a fixed `spellsKnown` table: those (2024
    /// Bard/Sorcerer) swap on level-up, others re-pick each long rest.
    private var footerText: String {
        switch mode {
        case .prepare:
            if let ac = activeClass,
               CharacterCalculator.hasFixedSpellsTable(classID: ac.classID, content: content) {
                return "Your prepared list is fixed by the class table. RAW you swap one spell when you gain a level (edits aren't time-gated here — the app trusts you)."
            }
            return "Tap to prepare or unprepare. You can re-pick after a long rest."
        case .learn:
            return "Tap to learn or forget. RAW you learn new spells on level-up and may swap one."
        case .add:
            return "Wizard spellbook management is coming — added spells land in the book and prepared list."
        }
    }

    private var budgetSection: some View {
        Section {
            if castingClasses.count > 1 {
                Picker("Class", selection: Binding(
                    get: { activeClass?.classID ?? "" },
                    set: { selectedClassID = $0 }
                )) {
                    ForEach(castingClasses, id: \.classID) { sc in
                        Text(content.classDefinition(id: sc.classID)?.name ?? sc.classID)
                            .tag(sc.classID)
                    }
                }
                .pickerStyle(.segmented)
            }
            if mode != .add {
                VStack(alignment: .leading, spacing: 2) {
                    if let budget = leveledBudget {
                        Text("\(mode == .prepare ? "Leveled prepared" : "Spells known"): \(leveledCount) / \(budget)")
                            .foregroundStyle(leveledCount > budget ? .red : .primary)
                    }
                    Text("Cantrips: \(cantripCount) / \(cantripBudget)")
                        .foregroundStyle(cantripCount > cantripBudget ? .red : .secondary)
                }
                .font(.caption.weight(.semibold))
            }
        } footer: {
            Text(footerText)
        }
    }

    @ViewBuilder
    private func row(for spell: SpellDefinition) -> some View {
        switch mode {
        case .prepare: prepareRow(for: spell)
        case .learn:   learnRow(for: spell)
        case .add:     addRow(for: spell)
        }
    }

    // MARK: - Learn-mode row (toggle in/out of knownIDs, budget-gated)

    private func learnRow(for spell: SpellDefinition) -> some View {
        let isKnown = character.spells.knownIDs.contains(spell.id)
        let atCap = spell.isCantrip
            ? cantripCount >= cantripBudget
            : leveledBudget.map { leveledCount >= $0 } ?? false
        let blocked = !isKnown && atCap
        return Button {
            if isKnown {
                character.spells.knownIDs.removeAll { $0 == spell.id }
            } else if !blocked {
                character.spells.knownIDs.append(spell.id)
            }
        } label: {
            toggleLabel(for: spell, isOn: isKnown, blocked: blocked)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    // MARK: - Prepare-mode row (toggle in/out of the selected class's bucket)

    private func prepareRow(for spell: SpellDefinition) -> some View {
        let classID = activeClass?.classID ?? ""
        let isPrepared = (character.spells.preparedByClass[classID] ?? []).contains(spell.id)
        // Block preparing a NEW spell once the relevant cap is hit. Already-
        // prepared spells stay tappable so you can unprepare to make room.
        let atCap = spell.isCantrip
            ? cantripCount >= cantripBudget
            : leveledBudget.map { leveledCount >= $0 } ?? false
        let blocked = !isPrepared && atCap
        return Button {
            if isPrepared {
                character.spells.preparedByClass[classID]?.removeAll { $0 == spell.id }
            } else if !blocked {
                character.spells.preparedByClass[classID, default: []].append(spell.id)
            }
        } label: {
            toggleLabel(for: spell, isOn: isPrepared, blocked: blocked)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    /// Shared row label for the prepare/learn toggle modes: spell name, school
    /// (+ concentration tag), and a check/slash/empty state circle.
    private func toggleLabel(for spell: SpellDefinition, isOn: Bool, blocked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: spell.school.systemImage)
                .foregroundStyle(.purple)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(spell.name)
                    .font(.subheadline.weight(.semibold))
                Text(spell.duration.requiresConcentration
                     ? "\(spell.school.displayName) · Conc"
                     : spell.school.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isOn ? "checkmark.circle.fill" : (blocked ? "circle.slash" : "circle"))
                .foregroundStyle(isOn ? .green : (blocked ? Color.secondary.opacity(0.4) : Color.accentColor))
        }
    }

    // MARK: - Add-mode row (reconcile into all lists)

    private func addRow(for spell: SpellDefinition) -> some View {
        // The prepared bucket Add mode reconciles into: the first casting
        // class (wizard for `preparedFromBook`; nothing for pure known-list
        // casters, who read `knownIDs` anyway).
        let prepBucketID = CharacterCalculator.primarySpellcasting(
            character: character, content: content
        )?.classID
        let inPrepared = prepBucketID.map {
            (character.spells.preparedByClass[$0] ?? []).contains(spell.id)
        } ?? true
        let inAllLists = character.spells.knownIDs.contains(spell.id)
            && character.spells.spellbookIDs.contains(spell.id)
            && inPrepared
        return Button {
            // Idempotent reconcile: ensure the spell is in every list. Fixes
            // orphans from older flows that only wrote to one list.
            if !character.spells.knownIDs.contains(spell.id) {
                character.spells.knownIDs.append(spell.id)
            }
            if let prepBucketID,
               !(character.spells.preparedByClass[prepBucketID] ?? []).contains(spell.id) {
                character.spells.preparedByClass[prepBucketID, default: []].append(spell.id)
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

    /// The pool to choose from: the SELECTED class's spell list in every mode
    /// (tagged; full-catalog fallback only for classes with no tagged spells).
    /// Non-casters — who can't normally reach this sheet — see everything.
    private var spellPool: [SpellDefinition] {
        guard let classID = activeClass?.classID else { return content.allSpells }
        return CharacterCalculator.spellList(forClassID: classID, content: content)
    }

    private var spellsByLevel: [(level: Int, spells: [SpellDefinition])] {
        Dictionary(grouping: spellPool, by: \.level)
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
