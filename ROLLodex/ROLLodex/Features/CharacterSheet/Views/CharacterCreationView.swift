import SwiftUI

struct CharacterCreationView: View {
    @Environment(ContentStore.self) private var contentStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = CharacterDraft()
    @State private var path = NavigationPath()
    let onComplete: (CharacterDraft) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            NameStep(draft: $draft) {
                path.append(CreationStep.species)
            }
            .navigationDestination(for: CreationStep.self) { step in
                switch step {
                case .species:
                    SpeciesStep(draft: $draft, contentStore: contentStore) {
                        // Only stop for species choices when there are any
                        // (Dragonborn ancestry, Elf/Gnome lineage, Tiefling
                        // legacy, innate ability); plain species skip straight on.
                        path.append(speciesHasChoices(draft.speciesID) ? CreationStep.speciesChoices : CreationStep.background)
                    }
                case .speciesChoices:
                    SpeciesChoicesStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.background)
                    }
                case .background:
                    BackgroundStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.classSelection)
                    }
                case .classSelection:
                    ClassStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.classSkills)
                    }
                case .classSkills:
                    ClassSkillsStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.abilities)
                    }
                case .abilities:
                    AbilitiesStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.review)
                    }
                case .review:
                    ReviewStep(draft: $draft, contentStore: contentStore) {
                        onComplete(draft)
                    }
                }
            }
        }
    }

    /// Does this species have any player choice to make at creation (a
    /// fixed-options selection: ancestry / lineage / legacy / innate ability)?
    private func speciesHasChoices(_ id: String) -> Bool {
        guard let species = contentStore.speciesDefinition(id: id) else { return false }
        return species.traits.contains {
            if case .fixedOptions = $0.selection?.optionsSource { return true }
            return false
        }
    }
}

private enum CreationStep: Hashable {
    case species, speciesChoices, background, classSelection, classSkills, abilities, review
}

// MARK: - Name Step

private struct NameStep: View {
    @Binding var draft: CharacterDraft
    let onNext: () -> Void

    var body: some View {
        Form {
            Section("Character Name") {
                TextField("Name", text: $draft.name)
            }
        }
        .navigationTitle("Name")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next", action: onNext)
                    .disabled(draft.name.isEmpty)
            }
        }
    }
}

// MARK: - Species Step

private struct SpeciesStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    var body: some View {
        let speciesList: [SpeciesDefinition] = contentStore.species.values.sorted(by: { $0.name < $1.name })
        List {
            ForEach(0..<speciesList.count, id: \.self) { index in
                speciesRow(speciesList[index])
            }
        }
        .navigationTitle("Species")
    }

    private func speciesRow(_ species: SpeciesDefinition) -> some View {
        Button {
            // Switching species drops any stale ancestry/lineage/legacy picks.
            if draft.speciesID != species.id {
                draft.featureSelections = [:]
            }
            draft.speciesID = species.id
            onNext()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(species.name)
                        .font(.headline)
                    Text("Size: \(species.size.capitalized) • Speed: \(species.speed) ft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if draft.speciesID == species.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Species Choices Step

/// Shown only for species with choices. Renders a radio picker per fixed-
/// option selection (Draconic Ancestry, lineage, Fiendish Legacy, innate
/// ability), writing to `draft.featureSelections`. Picks are optional here —
/// the player can also set them later on the Features tab.
private struct SpeciesChoicesStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    private var species: SpeciesDefinition? {
        contentStore.speciesDefinition(id: draft.speciesID)
    }

    private var choiceTraits: [TraitDefinition] {
        (species?.traits ?? []).filter {
            if case .fixedOptions = $0.selection?.optionsSource { return true }
            return false
        }
    }

    var body: some View {
        Form {
            ForEach(choiceTraits) { trait in
                if let selection = trait.selection,
                   case .fixedOptions(let options) = selection.optionsSource {
                    Section(selection.prompt) {
                        ForEach(options) { option in
                            optionRow(selectionID: selection.id, option: option)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(species?.name ?? "Species") Traits")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Picks are optional — they're also editable on the Features tab.
                Button("Next", action: onNext)
            }
        }
    }

    @ViewBuilder
    private func optionRow(selectionID: String, option: SelectionOption) -> some View {
        let picked = draft.featureSelections[selectionID]?.contains(option.id) ?? false
        Button {
            // Count-1 radio behavior: tap to set, tap again to clear.
            draft.featureSelections[selectionID] = picked ? [] : [option.id]
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).font(.subheadline.weight(.semibold))
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: - Background Step

private struct BackgroundStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    var body: some View {
        let backgroundList: [BackgroundDefinition] = contentStore.backgrounds.values.sorted(by: { $0.name < $1.name })
        List {
            ForEach(0..<backgroundList.count, id: \.self) { index in
                backgroundRow(backgroundList[index])
            }
        }
        .navigationTitle("Background")
    }

    private func backgroundRow(_ background: BackgroundDefinition) -> some View {
        Button {
            // Switching backgrounds invalidates any prior bonus picks (they
            // may reference abilities the new background doesn't offer).
            if draft.backgroundID != background.id {
                draft.backgroundAbilityBonuses = [:]
            }
            draft.backgroundID = background.id
            onNext()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(background.name)
                        .font(.headline)
                    Text(background.skillProficiencies.map(\.displayName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if draft.backgroundID == background.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Class Step

private struct ClassStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    var body: some View {
        let classList: [ClassDefinition] = contentStore.classes.values.sorted(by: { $0.name < $1.name })
        List {
            ForEach(0..<classList.count, id: \.self) { index in
                classRow(classList[index])
            }
        }
        .navigationTitle("Class")
    }

    private func classRow(_ classDef: ClassDefinition) -> some View {
        Button {
            // Changing class invalidates prior skill picks (different list).
            if draft.classID != classDef.id {
                draft.classSkillChoices = []
            }
            draft.classID = classDef.id
            onNext()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(classDef.name)
                        .font(.headline)
                    Text("Hit Die: \(classDef.hitDie.label) • Primary: \(classDef.primaryAbility.abbreviation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if draft.classID == classDef.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Class Skills Step

/// Pick the class's level-1 skill proficiencies (Rogue: 4 of 10; most: 2).
/// Background skills are already granted, so those are shown as locked-in to
/// avoid wasting a class pick on a duplicate.
private struct ClassSkillsStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    /// (count, options) for the class's level-1 skill choice, if any.
    private var choice: (count: Int, options: [Skill])? {
        guard let sel = contentStore.classDefinition(id: draft.classID)?.skillProficiencySelection
        else { return nil }
        let count = sel.selection.count.value(classLevel: 1, characterLevel: 1)
        return (count, sel.options)
    }

    private var backgroundSkills: Set<Skill> {
        Set(contentStore.backgroundDefinition(id: draft.backgroundID)?.skillProficiencies ?? [])
    }

    var body: some View {
        Form {
            if let choice {
                let remaining = choice.count - draft.classSkillChoices.count
                Section {
                    ForEach(choice.options, id: \.self) { skill in
                        skillRow(skill, count: choice.count)
                    }
                } header: {
                    Text("Choose \(choice.count) skills")
                } footer: {
                    Text(remaining > 0
                         ? "Pick \(remaining) more."
                         : "All set. Skills already from your background are marked.")
                }
            } else {
                Text("This class grants no skill choice.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next", action: onNext)
                    .disabled(!draft.isValidClassSkillChoice(
                        count: choice?.count ?? 0, options: choice?.options ?? []))
            }
        }
    }

    @ViewBuilder
    private func skillRow(_ skill: Skill, count: Int) -> some View {
        let fromBackground = backgroundSkills.contains(skill)
        let picked = draft.classSkillChoices.contains(skill)
        let atLimit = draft.classSkillChoices.count >= count
        Button {
            toggle(skill, count: count)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.displayName)
                    Text(skill.ability.abbreviation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if fromBackground {
                    Text("Background")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if picked {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        // Can't pick a background skill (already have it), and can't exceed
        // the limit without first deselecting.
        .disabled(fromBackground || (atLimit && !picked))
        .opacity(fromBackground ? 0.5 : 1)
    }

    private func toggle(_ skill: Skill, count: Int) {
        if let i = draft.classSkillChoices.firstIndex(of: skill) {
            draft.classSkillChoices.remove(at: i)
        } else if draft.classSkillChoices.count < count {
            draft.classSkillChoices.append(skill)
        }
    }
}

// MARK: - Abilities Step

private struct AbilitiesStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onNext: () -> Void

    @State private var quickRoll: QuickRollRequest?
    /// Pool chip the player tapped — drives the reroll confirmation dialog.
    @State private var rerollCandidate: Int?
    /// Pool index the in-flight mini-tray roll replaces (nil = appending a
    /// fresh roll). Survives the dialog's dismissal until the result lands.
    @State private var replacingIndex: Int?

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: methodBinding) {
                    ForEach(AbilityScoreMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch draft.abilityMethod {
            case .pointBuy:
                pointBuySections
            case .standardArray:
                assignmentSection(header: "Assign 15 · 14 · 13 · 12 · 10 · 8 (each once)")
            case .rolled:
                rolledSections
            }

            backgroundBonusSection

            #if DEBUG
            Section {
                Button {
                    draft.debugAutofill(backgroundOptions: backgroundOptions)
                } label: {
                    Label("Autofill (debug)", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Fills ability scores and origin bonuses so you can blow through creation while testing.")
            }
            #endif
        }
        .navigationTitle("Ability Scores")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next", action: onNext)
                    .disabled(!draft.isAbilityAssignmentValid || !backgroundBonusValid)
            }
        }
        .overlay {
            if let request = quickRoll {
                QuickRollOverlay(
                    request: request,
                    onResult: { result in
                        // A vicious house formula could go nonpositive; an
                        // ability score below 1 isn't a thing.
                        let value = max(1, result.total)
                        if let index = replacingIndex {
                            draft.replaceRolledScore(at: index, with: value)
                            replacingIndex = nil
                        } else {
                            draft.rolledScores.append(value)
                        }
                    },
                    onDismiss: { quickRoll = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: quickRoll != nil)
        .confirmationDialog(
            "Reroll this score?",
            isPresented: Binding(
                get: { rerollCandidate != nil },
                set: { if !$0 { rerollCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: rerollCandidate
        ) { index in
            if draft.rolledScores.indices.contains(index) {
                Button("Reroll the \(draft.rolledScores[index])", role: .destructive) {
                    replacingIndex = index
                    rollReplacement()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { index in
            if draft.rolledScores.indices.contains(index) {
                Text("Replaces the \(draft.rolledScores[index]) with a fresh \(draft.rollFormula) roll. If it was assigned, that ability is cleared.")
            }
        }
    }

    private var methodBinding: Binding<AbilityScoreMethod> {
        Binding(
            get: { draft.abilityMethod },
            set: { draft.setAbilityMethod($0) }
        )
    }

    // MARK: Background ability bonus (2024: +2/+1, or +1 to all three)

    private enum BonusMode { case focused, balanced }

    private var backgroundOptions: [Ability] {
        contentStore.backgroundDefinition(id: draft.backgroundID)?.abilityScoreOptions ?? []
    }

    /// Empty options (no/unknown background) shouldn't trap the player.
    private var backgroundBonusValid: Bool {
        let opts = backgroundOptions
        return opts.isEmpty || draft.isValidBackgroundBonus(options: opts)
    }

    private var plusTwoAbility: Ability? {
        backgroundOptions.first { draft.backgroundAbilityBonuses[$0] == 2 }
    }
    private var plusOneAbility: Ability? {
        backgroundOptions.first { draft.backgroundAbilityBonuses[$0] == 1 }
    }

    /// Derived from the draft so the draft stays the single source of truth:
    /// "balanced" only when all three options sit at +1.
    private var bonusMode: BonusMode {
        let opts = backgroundOptions
        if opts.count == 3, opts.allSatisfy({ draft.backgroundAbilityBonuses[$0] == 1 }) {
            return .balanced
        }
        return .focused
    }

    private var bonusModeBinding: Binding<BonusMode> {
        Binding(
            get: { bonusMode },
            set: { newMode in
                switch newMode {
                case .balanced:
                    draft.backgroundAbilityBonuses = Dictionary(
                        uniqueKeysWithValues: backgroundOptions.map { ($0, 1) }
                    )
                case .focused:
                    draft.backgroundAbilityBonuses = [:] // clear so the player picks +2 then +1
                }
            }
        )
    }

    @ViewBuilder
    private var backgroundBonusSection: some View {
        let opts = backgroundOptions
        if !opts.isEmpty {
            Section {
                Picker("Spread", selection: bonusModeBinding) {
                    Text("+2 / +1").tag(BonusMode.focused)
                    Text("+1 to all three").tag(BonusMode.balanced)
                }
                .pickerStyle(.segmented)

                if bonusMode == .focused {
                    abilityMenu(label: "+2 to", current: plusTwoAbility, choices: opts) { setPlusTwo($0) }
                    abilityMenu(label: "+1 to", current: plusOneAbility,
                                choices: opts.filter { $0 != plusTwoAbility }) { setPlusOne($0) }
                }

                ForEach(opts, id: \.self) { ability in
                    bonusPreviewRow(ability)
                }
            } header: {
                Text("Background Bonus")
            } footer: {
                Text("Your \(backgroundName) background boosts these three abilities. Choose +2 and +1, or +1 to all three.")
            }
        }
    }

    private func abilityMenu(
        label: String, current: Ability?, choices: [Ability], set: @escaping (Ability) -> Void
    ) -> some View {
        Menu {
            ForEach(choices, id: \.self) { ability in
                Button(ability.rawValue.capitalized) { set(ability) }
            }
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(current?.abbreviation ?? "Choose")
                    .foregroundStyle(current == nil ? .secondary : .primary)
            }
        }
    }

    private func bonusPreviewRow(_ ability: Ability) -> some View {
        let bonus = draft.backgroundAbilityBonuses[ability] ?? 0
        return HStack {
            Text(ability.abbreviation)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, alignment: .leading)
            Spacer()
            if let base = draft.abilityScores[ability] {
                Text("\(base) + \(bonus) = \(min(Character.abilityScoreCeiling, base + bonus))")
                    .font(.subheadline.monospacedDigit())
            } else {
                Text(bonus > 0 ? "+\(bonus)" : "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backgroundName: String {
        contentStore.backgroundDefinition(id: draft.backgroundID)?.name ?? "selected"
    }

    /// Keep exactly one +2 and one +1 across the options as the player picks.
    private func setPlusTwo(_ ability: Ability) {
        var b = draft.backgroundAbilityBonuses
        for key in b.keys where b[key] == 2 { b[key] = nil }
        if b[ability] == 1 { b[ability] = nil } // can't be both
        b[ability] = 2
        draft.backgroundAbilityBonuses = b
    }

    private func setPlusOne(_ ability: Ability) {
        var b = draft.backgroundAbilityBonuses
        for key in b.keys where b[key] == 1 { b[key] = nil }
        if b[ability] == 2 { b[ability] = nil }
        b[ability] = 1
        draft.backgroundAbilityBonuses = b
    }

    // MARK: Point buy

    @ViewBuilder
    private var pointBuySections: some View {
        Section {
            HStack {
                Text("Points Remaining")
                    .font(.headline)
                Spacer()
                Text("\(draft.remainingPoints)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(draft.remainingPoints < 0 ? .red : .primary)
            }
        }

        Section("Ability Scores (8–15)") {
            ForEach(Ability.allCases, id: \.self) { ability in
                AbilityRow(
                    ability: ability,
                    score: binding(for: ability)
                )
            }
        }

        if !draft.isValidPointBuy {
            Section {
                Text("Assign exactly 27 points using scores 8–15.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for ability: Ability) -> Binding<Int> {
        Binding(
            get: { draft.abilityScores[ability, default: 8] },
            set: { draft.abilityScores[ability] = $0 }
        )
    }

    // MARK: Array / rolled assignment

    @ViewBuilder
    private func assignmentSection(header: String) -> some View {
        Section(header) {
            ForEach(Ability.allCases, id: \.self) { ability in
                AssignmentRow(ability: ability, draft: $draft)
            }
        }
    }

    // MARK: Rolled

    @ViewBuilder
    private var rolledSections: some View {
        Section("Roll Formula") {
            HStack {
                TextField("4d6kh3", text: $draft.rollFormula)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())
                    // Mid-pool formula edits would mix provenances; Reroll
                    // All clears the pool and unlocks the field again.
                    .disabled(!draft.rolledScores.isEmpty)
                Spacer()
                if draft.rolledScores.count < 6 {
                    // Explicit HStack — Label drops its icon inside Form
                    // button rows, which left the die invisible.
                    Button {
                        rollNextScore()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "dice.fill")
                            Text("Roll \(draft.rolledScores.count + 1) of 6")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedRollFormula == nil)
                } else {
                    Button("Reroll All", role: .destructive) {
                        draft.setRolledScores([])
                    }
                    .buttonStyle(.bordered)
                }
            }
            if parsedRollFormula == nil {
                Text("Enter a valid dice formula — 4d6kh3, 3d6, 2d6+6, …")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        if !draft.rolledScores.isEmpty {
            Section {
                HStack(spacing: 8) {
                    ForEach(Array(draft.rolledScores.enumerated()), id: \.offset) { index, value in
                        Button {
                            rerollCandidate = index
                        } label: {
                            Text("\(value)")
                                .font(.subheadline.bold().monospacedDigit())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if draft.rolledScores.count < 6 {
                        // Bail out mid-pool without grinding through all six.
                        Button {
                            draft.setRolledScores([])
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset rolls")
                    }
                }
            } header: {
                Text("Rolled Pool")
            } footer: {
                Text("Tap a score to reroll just that one (house rules welcome).")
            }
        }

        if draft.rolledScores.count == 6 {
            assignmentSection(header: "Assign your rolls")
        }
    }

    /// The formula must parse, contain at least one die, stay tray-sized,
    /// and use only kinds with 3D models — it's headed for the mini tray.
    private var parsedRollFormula: DiceFormula? {
        guard let formula = try? DiceFormulaParser().parse(draft.rollFormula),
              !formula.groups.isEmpty,
              formula.totalDiceCount <= 12,
              formula.allKinds3DSupported
        else { return nil }
        return formula
    }

    private func rollNextScore() {
        guard let formula = parsedRollFormula else { return }
        quickRoll = QuickRollRequest(
            formula: formula,
            label: "Ability roll \(draft.rolledScores.count + 1) of 6 (\(draft.rollFormula))"
        )
    }

    private func rollReplacement() {
        guard let formula = parsedRollFormula else { return }
        quickRoll = QuickRollRequest(
            formula: formula,
            label: "Ability score reroll (\(draft.rollFormula))"
        )
    }
}

/// One ability row in array/rolled mode: a menu offering the pool values
/// still unassigned (deduped for display — picking either of two rolled 12s
/// is the same act), plus Clear to take the assignment back.
private struct AssignmentRow: View {
    let ability: Ability
    @Binding var draft: CharacterDraft

    var body: some View {
        HStack {
            Text(ability.abbreviation)
                .font(.headline)
                .frame(width: 40, alignment: .leading)

            Spacer()

            if let assigned = draft.abilityScores[ability] {
                Text(modifierString(for: assigned))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach(choices, id: \.self) { value in
                    Button("\(value)") {
                        draft.abilityScores[ability] = value
                    }
                }
                if draft.abilityScores[ability] != nil {
                    Divider()
                    Button("Clear", role: .destructive) {
                        draft.abilityScores[ability] = nil
                    }
                }
            } label: {
                Text(draft.abilityScores[ability].map(String.init) ?? "Assign")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(minWidth: 64)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }

    private var choices: [Int] {
        Array(Set(draft.availableValues(excluding: ability))).sorted(by: >)
    }

    private func modifierString(for score: Int) -> String {
        let mod = CharacterCalculator.abilityModifier(score: score)
        return mod >= 0 ? "+\(mod)" : "\(mod)"
    }
}

private struct AbilityRow: View {
    let ability: Ability
    @Binding var score: Int

    var body: some View {
        HStack {
            Text(ability.abbreviation)
                .font(.headline)
                .frame(width: 40, alignment: .leading)

            Spacer()

            Text("\(score)")
                .font(.title3.monospacedDigit())
                .frame(width: 32)

            Text(modifierString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Stepper("", value: $score, in: 8...15)
                .labelsHidden()
        }
    }

    private var modifierString: String {
        let mod = CharacterCalculator.abilityModifier(score: score)
        return mod >= 0 ? "+\(mod)" : "\(mod)"
    }
}

// MARK: - Review Step

private struct ReviewStep: View {
    @Binding var draft: CharacterDraft
    let contentStore: ContentStore
    let onCreate: () -> Void

    var body: some View {
        Form {
            Section("Identity") {
                LabeledContent("Name", value: draft.name)
                LabeledContent("Species", value: speciesName)
                LabeledContent("Background", value: backgroundName)
                LabeledContent("Class", value: className)
            }

            Section("Ability Scores") {
                ForEach(Ability.allCases) { ability in
                    // Final = base + chosen background bonus (clamped to 20),
                    // matching what finalizeDraft will persist.
                    let base = draft.abilityScores[ability, default: 8]
                    let bonus = draft.backgroundAbilityBonuses[ability] ?? 0
                    let score = min(Character.abilityScoreCeiling, base + bonus)
                    let mod = CharacterCalculator.abilityModifier(score: score)
                    let suffix = bonus > 0 ? " (incl. +\(bonus) background)" : ""
                    LabeledContent(
                        ability.abbreviation,
                        value: "\(score) (\(mod >= 0 ? "+" : "")\(mod))\(suffix)"
                    )
                }
            }
        }
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create", action: onCreate)
            }
        }
    }

    private var speciesName: String {
        contentStore.speciesDefinition(id: draft.speciesID)?.name ?? "Unknown"
    }

    private var backgroundName: String {
        contentStore.backgroundDefinition(id: draft.backgroundID)?.name ?? "Unknown"
    }

    private var className: String {
        contentStore.classDefinition(id: draft.classID)?.name ?? "Unknown"
    }
}
