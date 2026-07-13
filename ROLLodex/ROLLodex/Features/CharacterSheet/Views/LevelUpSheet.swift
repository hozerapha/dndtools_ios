import SwiftUI

/// Guided level-up flow. Player picks how to gain HP (roll the class hit die
/// or take the average), the sheet stages the gain, and the Finish button
/// commits the level bump together with the HP delta. Selection prompts
/// granted at the new level are listed as a reminder; the Features tab
/// hosts the actual pickers (existing Slice A surface).
///
/// v1 single-class only: levels the first `ClassEntry`. Multi-class will
/// gain a class picker in a later slice.
struct LevelUpSheet: View {
    @Binding var character: Character
    /// Invoked on commit when this level grew any spell budget (cantrips
    /// known, prepared cap, spells known, new slot levels). The sheet's owner
    /// uses it to chain the spell picker after dismissal, so the player is
    /// prompted to learn/prepare their new spells.
    var onSpellBudgetsGrew: (() -> Void)? = nil
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    /// Set when the player picks "Roll" — the hit die lands in the Quick
    /// Roll mini tray and its total is staged here.
    @State private var stagedRoll: Int?
    /// Set when the player picks "Take Average" — locks the staged gain.
    @State private var usedAverage: Bool = false
    @State private var quickRoll: QuickRollRequest?
    /// Which class this level goes into: an existing entry's classID, or a
    /// class the character doesn't have yet (multiclassing into it). Nil
    /// defaults to the first entry. Switching resets the staged HP roll —
    /// the hit die may differ.
    @State private var selectedClassID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    levelHeader
                    classPickerCard
                    hpGainCard
                    if unlocksSubclass {
                        subclassUnlockBanner
                    }
                    if !spellBudgetChanges.isEmpty {
                        spellBudgetCard
                    }
                    if unresolvedPromptsCount > 0 {
                        pendingPicksBanner
                    }
                    if hasNewFeatures {
                        newFeaturesCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Level Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { commit() }
                        .bold()
                        .disabled(stagedHPGain == nil || resolvedClassID == nil)
                }
            }
        }
        .overlay {
            if let request = quickRoll {
                QuickRollOverlay(
                    request: request,
                    onResult: { result in
                        stagedRoll = result.total
                        usedAverage = false
                    },
                    onDismiss: { quickRoll = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: quickRoll != nil)
    }

    // MARK: - Sections

    private var levelHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Level \(character.level) → \(newCharacterLevel)")
                .font(.title2.bold().monospacedDigit())
            if let cls = classDef {
                Text(isAddingNewClass
                     ? "\(cls.name) · NEW class → Level 1"
                     : "\(cls.name) · Class Level \(classEntry?.level ?? 1) → \(newClassLevel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Which class receives this level: the character's existing classes, plus
    /// a "Multiclass into…" menu of every other authored class, hard-gated by
    /// the RAW 13+ primary-ability prerequisites.
    private var classPickerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Class", systemImage: "person.text.rectangle")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(character.classEntries, id: \.classID) { entry in
                    let name = content.classDefinition(id: entry.classID)?.name ?? entry.classID
                    Button {
                        select(classID: entry.classID)
                    } label: {
                        VStack(spacing: 2) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                            Text("L\(entry.level) → \(entry.level + 1)")
                                .font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            resolvedClassID == entry.classID
                                ? Color.accentColor.opacity(0.22)
                                : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(resolvedClassID == entry.classID ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Menu {
                ForEach(multiclassCandidates, id: \.cls.id) { candidate in
                    Button {
                        select(classID: candidate.cls.id)
                    } label: {
                        if let blocker = candidate.blocker {
                            Label("\(candidate.cls.name) — \(blocker)", systemImage: "lock")
                        } else {
                            Text(candidate.cls.name)
                        }
                    }
                    .disabled(candidate.blocker != nil)
                }
            } label: {
                Label(
                    isAddingNewClass
                        ? "Multiclass into: \(classDef?.name ?? "?") (L1)"
                        : "Multiclass into…",
                    systemImage: "plus.circle"
                )
                .font(.caption.weight(.semibold))
            }
            if isAddingNewClass, let cls = classDef {
                Text(multiclassGrantSummary(for: cls))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func select(classID: String) {
        selectedClassID = classID
        // Different class may mean a different hit die — restage the HP gain.
        stagedRoll = nil
        usedAverage = false
    }

    /// Classes the character could multiclass into, each with its RAW blocker
    /// (nil = eligible). Existing classes are excluded (they're the buttons).
    private var multiclassCandidates: [(cls: ClassDefinition, blocker: String?)] {
        let owned = Set(character.classEntries.map(\.classID))
        return content.allClasses
            .filter { !owned.contains($0.id) }
            .sorted { $0.name < $1.name }
            .map { cls in
                (cls, CharacterCalculator.multiclassBlocker(
                    addingClassID: cls.id, character: character, content: content
                ))
            }
    }

    /// What multiclassing into `cls` grants (the 5e limited proficiency list),
    /// so the pick isn't a mystery box.
    private func multiclassGrantSummary(for cls: ClassDefinition) -> String {
        guard !cls.multiclassProficiencies.isEmpty else {
            return "Multiclass grants: no new proficiencies."
        }
        let names = cls.multiclassProficiencies.map { key -> String in
            switch key {
            case .armor(let cat):  return "\(cat.rawValue.capitalized) armor"
            case .weapon(let cat): return "\(cat.rawValue.capitalized) weapons"
            case .skill(let s):    return s.displayName
            case .savingThrow(let a): return "\(a.abbreviation) saves"
            case .tool(let t):     return t
            }
        }
        return "Multiclass grants: " + names.joined(separator: ", ") + "."
    }

    private var hpGainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hit Points", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("Hit Die: 1d\(hitDie) + CON (\(conMod.formattedModifier))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                rollButton
                averageButton
            }
            if let gain = stagedHPGain {
                stagedSummary(gain: gain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rollButton: some View {
        Button {
            // Real dice, not hidden RNG: the hit die tumbles in the mini
            // tray and the settled total comes back via the overlay.
            var formula = DiceFormula()
            formula.groups.append(DiceGroup(kind: DieKind(rawValue: hitDie) ?? .d8, count: 1))
            quickRoll = QuickRollRequest(formula: formula, label: "Level-Up HP (1d\(hitDie))")
        } label: {
            VStack(spacing: 2) {
                Label("Roll", systemImage: "dice.fill")
                    .font(.subheadline.weight(.semibold))
                Text("1d\(hitDie)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(stagedHPGain != nil)
    }

    private var averageButton: some View {
        let dieAverage = hitDie / 2 + 1
        return Button {
            usedAverage = true
            stagedRoll = nil
        } label: {
            VStack(spacing: 2) {
                Label("Take Avg", systemImage: "equal")
                    .font(.subheadline.weight(.semibold))
                Text("\(dieAverage)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .disabled(stagedHPGain != nil)
    }

    private func stagedSummary(gain: Int) -> some View {
        let dieValue = stagedRoll ?? (hitDie / 2 + 1)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(usedAverage ? "Average \(dieValue)" : "Rolled \(dieValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("+\(gain) HP (max \(character.maxHP) → \(character.maxHP + gain))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                if featureHPDelta > 0 {
                    Text("incl. +\(featureHPDelta) from features (Toughness-style bonuses)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Reset") {
                stagedRoll = nil
                usedAverage = false
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    /// Named callout when the upcoming level is the subclass-unlock level and
    /// no subclass has been chosen — more actionable than the generic
    /// pending-picks count.
    private var subclassUnlockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.purple)
            Text("Level \(newClassLevel) unlocks your \(classDef?.name ?? "class") subclass — choose it in the Features tab after finishing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    /// What this level does to the character's spell budgets — cantrips known,
    /// prepared-spell cap, newly unlocked slot levels. Slots themselves appear
    /// automatically (derived live); this card tells the player to go re-pick.
    private var spellBudgetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Spellcasting", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.purple)
            ForEach(spellBudgetChanges, id: \.self) { line in
                Text("• \(line)")
                    .font(.subheadline)
            }
            Text("Update your list on the Spells tab (Prepare Spells / Add Spell).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var pendingPicksBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .foregroundStyle(.orange)
            Text("\(unresolvedPromptsCount) selection\(unresolvedPromptsCount == 1 ? "" : "s") still pending — fill them in the Features tab after finishing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var newFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("New at \(classDef?.name ?? "this class") L\(newClassLevel)", systemImage: "sparkles")
                .font(.headline)
            ForEach(newFeatures, id: \.feature.id) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.feature.name)
                            .font(.subheadline.weight(.semibold))
                        if let sub = entry.subclassName {
                            Text(sub)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.18), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    Text(entry.feature.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Commit

    private func commit() {
        guard let dieGain = stagedDieGain, let classID = resolvedClassID else { return }
        // Evaluate against the PRE-commit state — spellBudgetChanges diffs the
        // current level against the new one.
        let budgetsGrew = !spellBudgetChanges.isEmpty
        var copy = character
        // Feature HP bonus before the level bump (subclass already chosen in
        // this sheet, so a subclass gained now is counted in the "after").
        let oldFeatureHP = CharacterCalculator.featureHitPointBonus(character: copy, content: content)
        // Die-only value — applyLevelUp banks it into rolledHP and
        // recalculateHP() layers the CON share on retroactively. A classID
        // with no entry appends one at level 1 (multiclassing in).
        CharacterCalculator.applyLevelUp(to: &copy, hpGain: dieGain, classID: classID)
        // Fold the change in feature HP (per-level growth + any newly-granted
        // feature like Draconic Resilience at L3) into rolledHP, then recalc.
        let newFeatureHP = CharacterCalculator.featureHitPointBonus(character: copy, content: content)
        copy.rolledHP += (newFeatureHP - oldFeatureHP)
        copy.recalculateHP()
        // Multiclassing in grants the class's LIMITED proficiency list (never
        // its saves or skill choices) — the 5e multiclass table.
        if isAddingNewClass, let cls = classDef {
            for key in cls.multiclassProficiencies where copy.proficiencies[key] == nil {
                copy.proficiencies[key] = .proficient
            }
        }
        applyNewFeatureProficiencies(to: &copy)
        character = copy
        if budgetsGrew { onSpellBudgetsGrew?() }
        dismiss()
    }

    /// Scan features that are new at the upcoming class level and apply any
    /// automatic proficiency grants (e.g. Rogue's Slippery Mind → WIS/CHA saves).
    /// Skipped when ADDING a class — its L1 `grantsProficiencies` are the
    /// full-class grants; multiclassing in gets only the limited list above.
    private func applyNewFeatureProficiencies(to character: inout Character) {
        guard let cls = classDef, let entry = classEntry, !isAddingNewClass else { return }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: entry.classID)
        ]?.first
        // Base-class features new at this level
        for feature in cls.levelFeatures[newClassLevel] ?? [] {
            for key in feature.grantsProficiencies ?? [] {
                character.proficiencies[key] = .proficient
            }
        }
        // Subclass features new at this level
        if let subclassID, let subclass = cls.subclasses.first(where: { $0.id == subclassID }) {
            for feature in subclass.levelFeatures[newClassLevel] ?? [] {
                for key in feature.grantsProficiencies ?? [] {
                    character.proficiencies[key] = .proficient
                }
            }
        }
    }

    // MARK: - Derived state

    /// The class receiving this level — the picked one, or the first entry.
    private var resolvedClassID: String? {
        selectedClassID ?? character.classEntries.first?.classID
    }

    /// The existing entry for the resolved class; nil when multiclassing into
    /// a class the character doesn't have yet.
    private var classEntry: ClassEntry? {
        character.classEntries.first { $0.classID == resolvedClassID }
    }

    private var isAddingNewClass: Bool {
        resolvedClassID != nil && classEntry == nil
    }

    private var classDef: ClassDefinition? {
        resolvedClassID.flatMap { content.classDefinition(id: $0) }
    }

    private var newClassLevel: Int { (classEntry?.level ?? 0) + 1 }
    private var newCharacterLevel: Int { character.level + 1 }
    private var hitDie: Int { classDef?.hitDie.rawValue ?? 8 }
    private var conMod: Int {
        CharacterCalculator.abilityModifier(score: character.abilityScores[.constitution] ?? 10)
    }

    /// Die-only value to bank into `rolledHP` — the roll itself or the die
    /// average, WITHOUT the CON modifier (CON is applied retroactively by
    /// `recalculateHP()` during commit).
    private var stagedDieGain: Int? {
        if let r = stagedRoll { return r }
        if usedAverage { return hitDie / 2 + 1 }
        return nil
    }

    /// What the player sees as this level's HP change: die value + CON mod +
    /// any feature-HP growth (audit #9 — the preview now matches the commit,
    /// which folds the `featureHitPointBonus` diff into `rolledHP`).
    /// Display only — the commit path goes through `stagedDieGain`.
    private var stagedHPGain: Int? {
        stagedDieGain.map { $0 + conMod + featureHPDelta }
    }

    /// Feature-HP change this level-up produces (Dwarven Toughness +1/level,
    /// Draconic Resilience +1/sorcerer level). Simulated on a copy with the
    /// bumped levels — the same diff `commit()` applies for real. Handles a
    /// brand-new class (appends a level-1 entry to the simulation).
    private var featureHPDelta: Int {
        guard let classID = resolvedClassID else { return 0 }
        let old = CharacterCalculator.featureHitPointBonus(character: character, content: content)
        var bumped = character
        bumped.level += 1
        if let idx = bumped.classEntries.firstIndex(where: { $0.classID == classID }) {
            let e = bumped.classEntries[idx]
            bumped.classEntries[idx] = ClassEntry(classID: e.classID, level: e.level + 1)
        } else {
            bumped.classEntries.append(ClassEntry(classID: classID, level: 1))
        }
        let new = CharacterCalculator.featureHitPointBonus(character: bumped, content: content)
        return new - old
    }

    /// True when the upcoming class level is the subclass-unlock level and no
    /// subclass has been picked yet.
    private var unlocksSubclass: Bool {
        guard let cls = classDef, let classID = resolvedClassID, !cls.subclasses.isEmpty else { return false }
        guard cls.subclassLevel == newClassLevel else { return false }
        let picked = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: classID)
        ]?.first
        return picked == nil
    }

    /// Human-readable spell-budget changes this level brings: cantrips known,
    /// prepared-spell cap (ability mod + class level for prepared casters),
    /// and newly unlocked slot levels. Empty for non-casters / no changes.
    /// A brand-new casting class diffs from level 0 (everything is new).
    private var spellBudgetChanges: [String] {
        guard let cls = classDef, let block = cls.spellcasting else { return [] }
        let oldLevel = classEntry?.level ?? 0
        var out: [String] = []

        let oldCantrips = oldLevel == 0 ? 0
            : block.cantripsKnown.value(classLevel: oldLevel, characterLevel: character.level)
        let newCantrips = block.cantripsKnown.value(classLevel: newClassLevel, characterLevel: newCharacterLevel)
        if newCantrips > oldCantrips {
            out.append("Cantrips known: \(oldCantrips) → \(newCantrips)")
        }

        if block.preparedRule == .preparedFromAll || block.preparedRule == .preparedFromBook {
            let mod = CharacterCalculator.abilityModifier(score: character.abilityScores[block.ability] ?? 10)
            let oldMax = oldLevel == 0 ? 0 : max(1, mod + oldLevel)
            let newMax = max(1, mod + newClassLevel)
            if newMax > oldMax {
                out.append("Prepared spells: \(oldMax) → \(newMax)")
            }
        }

        let oldSlots = oldLevel == 0 ? [:] : block.slotTable.slots(atClassLevel: oldLevel)
        let newSlots = block.slotTable.slots(atClassLevel: newClassLevel)
        let unlocked = Set(newSlots.keys).subtracting(oldSlots.keys).sorted()
        if !unlocked.isEmpty {
            out.append("New spell slot level\(unlocked.count == 1 ? "" : "s"): " + unlocked.map { "L\($0)" }.joined(separator: ", "))
        }
        // Existing slot levels that grow (L1: 2 → 3) — summarize compactly.
        let grown = oldSlots.keys.filter { (newSlots[$0] ?? 0) > (oldSlots[$0] ?? 0) }.sorted()
        if !grown.isEmpty {
            out.append("More slots at: " + grown.map { "L\($0) (\(oldSlots[$0] ?? 0) → \(newSlots[$0] ?? 0))" }.joined(separator: ", "))
        }
        return out
    }

    /// Selection prompts the character SHOULD have filled by their **current**
    /// class level but hasn't, plus prior-level selections whose caps grew
    /// with the upcoming level (Eldritch Invocations 2 → 3, Weapon Mastery
    /// 2 → 3). Used for the "pending picks" banner.
    ///
    /// Selections that unlock **at** the level being gained (a Druid's L4 ASI
    /// during a L3 → L4 level-up) are intentionally NOT counted here: the
    /// character legitimately hasn't been offered them yet, and warning about
    /// them reads as "you're behind" when they're actually new. Those unlocks
    /// are surfaced by `newFeaturesCard` instead.
    ///
    /// Multiclass exception: adding a new class starts at class-level 1 with
    /// nothing yet resolved, so there's no "current level" to walk — count
    /// against `newClassLevel` (i.e. L1 features of the new class) so the
    /// player is nudged toward the Fighting Style / etc. pickers after
    /// finishing. L1 skill choices don't apply on multiclass (5e rule).
    private var unresolvedPromptsCount: Int {
        guard let cls = classDef, let classID = resolvedClassID else { return 0 }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: classID)
        ]?.first
        // Walk up to the CURRENT class level for same-class level-ups; up to
        // the NEW class level for a multiclass add (there is no "current" for
        // the class you're adding).
        let walkThroughLevel = isAddingNewClass ? newClassLevel : max(0, newClassLevel - 1)
        var count = 0
        for resolved in cls.resolvedFeatures(throughClassLevel: walkThroughLevel, subclassID: subclassID) {
            guard let selection = resolved.feature.selection else { continue }
            if isAddingNewClass, resolved.grantedAtLevel == 1,
               case .skillsFrom = selection.optionsSource { continue }
            // Evaluate max at the NEW level so a scaling cap (invocations
            // 2 → 3 on the level being gained) correctly surfaces as pending.
            let max = selection.count.value(
                classLevel: newClassLevel,
                characterLevel: newCharacterLevel
            )
            let picks = (character.featureSelections[selection.id] ?? []).count
            if picks < max { count += 1 }
        }
        return count
    }

    /// Features new at the upcoming class level — both base-class additions
    /// and (once a subclass is picked) new subclass level-features. For a
    /// brand-new class this is its whole L1 feature list.
    private var newFeatures: [(feature: FeatureDefinition, subclassName: String?)] {
        guard let cls = classDef, let classID = resolvedClassID else { return [] }
        var out: [(FeatureDefinition, String?)] = []
        for feature in cls.levelFeatures[newClassLevel] ?? [] {
            out.append((feature, nil))
        }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: classID)
        ]?.first
        if let subclassID, let subclass = cls.subclasses.first(where: { $0.id == subclassID }) {
            for feature in subclass.levelFeatures[newClassLevel] ?? [] {
                out.append((feature, subclass.name))
            }
        }
        return out
    }

    private var hasNewFeatures: Bool { !newFeatures.isEmpty }
}
