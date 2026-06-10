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
                        path.append(CreationStep.background)
                    }
                case .background:
                    BackgroundStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.classSelection)
                    }
                case .classSelection:
                    ClassStep(draft: $draft, contentStore: contentStore) {
                        path.append(CreationStep.abilities)
                    }
                case .abilities:
                    AbilitiesStep(draft: $draft) {
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
}

private enum CreationStep: Hashable {
    case species, background, classSelection, abilities, review
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

// MARK: - Abilities Step

private struct AbilitiesStep: View {
    @Binding var draft: CharacterDraft
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
        }
        .navigationTitle("Ability Scores")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next", action: onNext)
                    .disabled(!draft.isAbilityAssignmentValid)
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
                    let score = draft.abilityScores[ability, default: 8]
                    let mod = CharacterCalculator.abilityModifier(score: score)
                    LabeledContent(ability.abbreviation, value: "\(score) (\(mod >= 0 ? "+" : "")\(mod))")
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
