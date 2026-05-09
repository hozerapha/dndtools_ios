import SwiftUI

struct CharacterListView: View {
    @Environment(CharacterStore.self) private var characterStore
    @Environment(ContentStore.self) private var contentStore
    @State private var showCreation = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(characterStore.characters) { character in
                    NavigationLink(value: character) {
                        CharacterRow(character: character)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Characters")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreation) {
                CharacterCreationView { draft in
                    let character = finalizeDraft(draft)
                    characterStore.create(character)
                    showCreation = false
                }
            }
            .navigationDestination(for: Character.self) { character in
                CharacterSheetView(character: character)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let character = characterStore.characters[index]
            characterStore.delete(id: character.id)
        }
    }

    private func finalizeDraft(_ draft: CharacterDraft) -> Character {
        var character = draft.toCharacter()

        // Apply background ability score increases
        if let background = contentStore.backgroundDefinition(id: draft.backgroundID) {
            for (ability, increase) in background.abilityScoreIncreases {
                character.abilityScores[ability, default: 10] += increase
            }
            // Apply background skill proficiencies
            for skill in background.skillProficiencies {
                character.proficiencies[.skill(skill)] = .proficient
            }
        }

        // Apply class proficiencies
        if let classDef = contentStore.classDefinition(id: draft.classID) {
            for ability in classDef.savingThrows {
                character.proficiencies[.savingThrow(ability)] = .proficient
            }
            for armor in classDef.armorProficiencies {
                character.proficiencies[.armor(armor)] = .proficient
            }
            for weapon in classDef.weaponProficiencies {
                character.proficiencies[.weapon(weapon)] = .proficient
            }
        }

        return character
    }
}

// MARK: - Row

private struct CharacterRow: View {
    let character: Character
    @Environment(ContentStore.self) private var contentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(character.name)
                .font(.headline)

            HStack(spacing: 6) {
                Text(className)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Level \(character.level)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(speciesName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var className: String {
        character.classEntries.first.flatMap { contentStore.classDefinition(id: $0.classID)?.name } ?? "Unknown"
    }

    private var speciesName: String {
        contentStore.speciesDefinition(id: character.speciesID)?.name ?? "Unknown"
    }
}

// MARK: - Placeholder sheet view

struct CharacterSheetView: View {
    let character: Character

    var body: some View {
        Text(character.name)
            .navigationTitle(character.name)
    }
}
