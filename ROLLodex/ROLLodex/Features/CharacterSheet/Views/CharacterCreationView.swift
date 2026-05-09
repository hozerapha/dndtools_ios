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

    var body: some View {
        Form {
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
        .navigationTitle("Ability Scores")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next", action: onNext)
                    .disabled(!draft.isValidPointBuy)
            }
        }
    }

    private func binding(for ability: Ability) -> Binding<Int> {
        Binding(
            get: { draft.abilityScores[ability, default: 8] },
            set: { draft.abilityScores[ability] = $0 }
        )
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
