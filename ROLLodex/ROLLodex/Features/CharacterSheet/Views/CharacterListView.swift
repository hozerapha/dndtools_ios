import SwiftUI

struct CharacterListView: View {
    @Binding var selectedTab: AppTab
    @Environment(CharacterStore.self) private var characterStore
    @Environment(ContentStore.self) private var contentStore
    @State private var showCreation = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(characterStore.characters) { character in
                    NavigationLink(value: character.id) {
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
            // Push the UUID, not the Character struct. Character's auto-Hashable
            // hashes every field, so editing HP would invalidate a pushed value.
            .navigationDestination(for: UUID.self) { id in
                if let binding = characterStore.binding(for: id) {
                    CharacterSheetView(character: binding, selectedTab: $selectedTab)
                } else {
                    ContentUnavailableView("Character not found", systemImage: "person.crop.circle.badge.exclamationmark")
                }
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
            for tool in classDef.toolProficiencies {
                character.proficiencies[.tool(tool)] = .proficient
            }

            // Apply any automatic proficiency grants from level 1 class features
            // (e.g. Rogue's starting expertise doesn't route here — it's a
            // selection — but passive grants like Slippery Mind do).
            for feature in classDef.levelFeatures[1] ?? [] {
                for key in feature.grantsProficiencies ?? [] {
                    character.proficiencies[key] = .proficient
                }
            }

            // Seed the starting spell list for caster classes. Phase J MVP
            // grants every level-appropriate spell we ship so a fresh wizard
            // can cast immediately — Phase M's level-up flow will replace
            // this with proper "choose your starting spells" prompts.
            if classDef.spellcasting != nil {
                seedStartingSpells(character: &character, classDef: classDef)
            }
        }

        return character
    }

    /// Bulk-load all bundled spells the class would reasonably know at L1:
    /// cantrips up to `cantripsKnown(L1)`, plus every L1 spell in the store.
    /// Sets `spellbookIDs` and `preparedIDs` for prepared casters; sets
    /// `knownIDs` for "known list" casters.
    private func seedStartingSpells(character: inout Character, classDef: ClassDefinition) {
        guard let block = classDef.spellcasting else { return }

        let classLevel = character.classEntries.first(where: { $0.classID == classDef.id })?.level ?? 1
        let cantripBudget = block.cantripsKnown.value(classLevel: classLevel, characterLevel: character.level)

        let allSpells = Array(contentStore.spells.values)
        let cantrips = allSpells
            .filter { $0.level == 0 }
            .sorted { $0.name < $1.name }
            .prefix(cantripBudget)
        let leveledSpells = allSpells
            .filter { $0.level == 1 }
            .sorted { $0.name < $1.name }

        let cantripIDs = cantrips.map(\.id)
        let leveledIDs = leveledSpells.map(\.id)

        switch block.preparedRule {
        case .knownList, .pactMagic:
            character.spells.knownIDs = cantripIDs + leveledIDs
        case .preparedFromBook:
            // Wizards: leveled spells live in the spellbook; cantrips are
            // always-known. Prepared list starts as everything until the
            // player curates it.
            character.spells.spellbookIDs = leveledIDs
            character.spells.preparedIDs = cantripIDs + leveledIDs
        case .preparedFromAll:
            // Clerics / druids / paladins: cantrips + prepared list (curated
            // from the full class list, which we don't model yet — so seed
            // everything we have).
            character.spells.preparedIDs = cantripIDs + leveledIDs
        }
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
