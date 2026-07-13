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

    /// Button label matches the picker's presentation for the primary casting
    /// class. Unlimited-prep casters ("Prepare Spells" — daily rebuild);
    /// learn-style casters, i.e. anyone with a fixed spellsKnown table
    /// ("Manage Spells" — cap-relaxed customization escape hatch); wizard
    /// ("Add Spell", until spellbook UI ships); mixed multiclass ("Manage").
    private var spellButtonLabel: String {
        let casters = character.classEntries.compactMap {
            content.classDefinition(id: $0.classID)?.spellcasting
        }
        if casters.count > 1 { return "Manage Spells" }
        guard let block = casters.first else { return "Add Spell" }
        if block.spellsKnown != nil { return "Manage Spells" }
        switch block.preparedRule {
        case .preparedFromAll:  return "Prepare Spells"
        case .preparedFromBook: return "Add Spell"
        case .knownList, .pactMagic: return "Manage Spells"
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
                    GrantedSpellRow(
                        spell: item.spell,
                        sourceLabel: item.sourceLabel,
                        canCast: canCast(item.spell),
                        levelLabel: levelLabel(item.spell),
                        onTap: { onTap(item.spell) }
                    )
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

/// Row inside `GrantedSpellsSection`. Split into its own view so it can own the
/// `showDetail` sheet state per-row, mirroring `SpellRow`.
private struct GrantedSpellRow: View {
    let spell: SpellDefinition
    let sourceLabel: String
    let canCast: Bool
    let levelLabel: String
    let onTap: () -> Void
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 8) {
            SpellInfoButton(spell: spell, showDetail: $showDetail)
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: spell.school.systemImage)
                        .font(.caption)
                        .frame(width: 18)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(spell.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(levelLabel) · \(sourceLabel)")
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
        .sheet(isPresented: $showDetail) {
            SpellDetailSheet(spell: spell)
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
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 8) {
            // Info affordance. Separate button so it stays live even when the
            // main row is disabled (no slot available) — the player still needs
            // to look up what the spell does.
            SpellInfoButton(spell: spell, showDetail: $showDetail)
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
        .sheet(isPresented: $showDetail) {
            SpellDetailSheet(spell: spell)
        }
    }
}

/// Small "info" affordance that opens `SpellDetailSheet`. Extracted so the
/// same button works from the row, the picker, and any future spell surface
/// (SpellCastSheet header, follow-up chips, …) without duplication.
struct SpellInfoButton: View {
    let spell: SpellDefinition
    @Binding var showDetail: Bool

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(spell.name)")
    }
}

/// Spell picker, grouped by level. TWO axes independently drive behavior:
///
/// 1. **`PickerPresentation`** (title + cap enforcement + copy). Overridden
///    only from the level-up flow, which forces `.learnOnLevelUp`; otherwise
///    derived from the class regime:
///    - Learn casters (any class with a `spellsKnown` fixed table:
///      bard/sorcerer/ranger/warlock): `.manage` — "Manage Spells", **cap
///      relaxed** (DM-approved boons / negotiations / homebrew — customization
///      isn't gatekept).
///    - Unlimited-prep casters (cleric/druid/paladin): `.dailyPrepare` —
///      "Prepare Spells", cap enforced (rebuild each Long Rest).
///    - Wizard (preparedFromBook): `.dailyPrepare` too (their prep still has
///      a cap; the spellbook is a separate list).
///    - Level-up context: **all casters** see `.learnOnLevelUp` — "Learn
///      Spells", cap enforced, universal terminology when acquiring.
///
/// 2. **`PickMode`** (which bucket the row writes to). Fixed per class:
///    - `.prepare`: writes to `character.spells.preparedByClass[classID]`
///      (bard/sorcerer/ranger, cleric/druid/paladin).
///    - `.learn`: writes to `character.spells.knownIDs` (warlock).
///    - `.add`: reconciles into every list (wizard, until spellbook UI ships).
///
/// The pool is always the selected class's spell list, capped by the highest
/// slot level the character has — a L4 bard doesn't see L3+ spells they
/// literally can't cast. Multiclass casters get a segment picker.
enum PickerPresentation: Identifiable {
    case dailyPrepare      // "Prepare Spells" — daily rebuild context (long rest / sheet button)
    case learnOnLevelUp    // "Learn Spells"  — level-up moment, any caster
    case manage            // "Manage Spells" — learn casters' day-to-day (swap/tweak, cap enforced)
    var id: Self { self }
}

struct AddSpellSheet: View {
    @Binding var character: Character
    /// Overrides the derived presentation. Level-up flow passes
    /// `.learnOnLevelUp` so every caster reads "Learn Spells" at level-up
    /// regardless of their day-to-day regime. Omit elsewhere.
    let presentationOverride: PickerPresentation?
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    /// The casting class being edited. Defaults to the first; a segment picker
    /// appears for multiclass casters (each class picks separately, per 5e).
    @State private var selectedClassID: String?

    init(character: Binding<Character>, presentation: PickerPresentation? = nil) {
        self._character = character
        self.presentationOverride = presentation
    }

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

    /// UI regime for this open. Explicit override wins (level-up); else
    /// derived from whether the active class has a fixed spellsKnown table.
    /// Every presentation currently enforces the class cap — Manage is a
    /// terminology fix (learn-caster button label + footer), not a bypass.
    /// A future "DM-approved override" toggle could opt into a cap-relaxed
    /// variant; the mechanism is deliberately still one branch.
    private var presentation: PickerPresentation {
        if let override = presentationOverride { return override }
        guard let ac = activeClass else { return .dailyPrepare }
        return ac.block.spellsKnown != nil ? .manage : .dailyPrepare
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
        // Wizard (add mode) is unique — keep its own label until spellbook UI ships.
        if mode == .add { return "Add Spell" }
        switch presentation {
        case .dailyPrepare:   return "Prepare Spells"
        case .learnOnLevelUp: return "Learn Spells"
        case .manage:         return "Manage Spells"
        }
    }

    private var footerText: String {
        if mode == .add {
            return "Wizard spellbook management is coming — added spells land in the book and prepared list."
        }
        switch presentation {
        case .dailyPrepare:
            return "Tap to prepare or unprepare. You can re-pick after a long rest."
        case .learnOnLevelUp:
            return "Your budget grew. Pick a new spell (or swap one) to fill it — this is the RAW learn-on-level-up moment."
        case .manage:
            return "Rearrange your prepared list within your class cap. RAW you swap on level-up — the app trusts you if you tweak between."
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
        PickerRowWithInfo(spell: spell) {
            switch mode {
            case .prepare: prepareRow(for: spell)
            case .learn:   learnRow(for: spell)
            case .add:     addRow(for: spell)
            }
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
        // Filter to spells the caster can actually cast: cantrips are always
        // in; leveled spells cap at the highest slot level the character has
        // any pool for (a L4 bard has only L1/L2 slots → no L3+ spells shown).
        // A caster with no leveled slots (a slotless first-level half-caster)
        // sees cantrips only.
        let maxLevel = CharacterCalculator.maxSpellSlotLevel(character: character, content: content) ?? 0
        let castable = spellPool.filter { $0.isCantrip || $0.level <= maxLevel }
        return Dictionary(grouping: castable, by: \.level)
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

/// Wraps any picker row with an info affordance on the leading edge and a
/// SpellDetailSheet presenter. Keeps the picker's toggle/add logic in one
/// place while every spell surface gets consistent "look up what this does"
/// behavior.
private struct PickerRowWithInfo<Content: View>: View {
    let spell: SpellDefinition
    @ViewBuilder let content: () -> Content
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 8) {
            SpellInfoButton(spell: spell, showDetail: $showDetail)
            content()
        }
        .sheet(isPresented: $showDetail) {
            SpellDetailSheet(spell: spell)
        }
    }
}

/// Full-text detail for a bundled spell — school, level, casting time, range,
/// components (with material cost), duration, description, higher-level scaling,
/// and the class list the SRD associates the spell with. Read-only; the only
/// affordance is Dismiss. Presented from any of the picker / cast / granted-spell
/// rows via the `ⓘ` button.
struct SpellDetailSheet: View {
    let spell: SpellDefinition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    metaBlock
                    descriptionBlock
                    if let higher = spell.higherLevel, !higher.isEmpty {
                        higherLevelBlock(higher)
                    }
                    if !spell.classes.isEmpty {
                        classesBlock
                    }
                }
                .padding()
            }
            .navigationTitle(spell.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: spell.school.systemImage)
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(spell.isCantrip ? "\(spell.school.displayName) Cantrip"
                                     : "Level \(spell.level) \(spell.school.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if spell.duration.requiresConcentration {
                    Label("Concentration", systemImage: "bolt.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow(icon: "clock",       label: "Casting Time", value: spell.castingTime.shortLabel)
            metaRow(icon: "arrow.up.right", label: "Range",     value: spell.range.shortLabel)
            metaRow(icon: "hourglass",   label: "Duration",     value: spell.duration.shortLabel)
            metaRow(icon: "sparkles",    label: "Components",   value: componentsSummary)
            if let material = spell.components.material, !material.isEmpty {
                metaRow(icon: "cube",    label: "Material",     value: material)
            }
        }
        .font(.subheadline)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            Text(spell.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func higherLevelBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("At Higher Levels")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var classesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Classes")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            Text(spell.classes.map { $0.capitalized }.sorted().joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var componentsSummary: String {
        var parts: [String] = []
        if spell.components.verbal   { parts.append("V") }
        if spell.components.somatic  { parts.append("S") }
        if spell.components.material != nil { parts.append("M") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}
