import SwiftUI

struct CharacterListView: View {
    @Binding var selectedTab: AppTab
    @Environment(CharacterStore.self) private var characterStore
    @Environment(ContentStore.self) private var contentStore
    @State private var showCreation = false
    /// Character staged for deletion — set by swipe or context menu, executed
    /// only after the confirmation dialog. Deleting removes the JSON file,
    /// so a lone swipe shouldn't be enough.
    @State private var pendingDelete: Character?

    var body: some View {
        NavigationStack {
            List {
                ForEach(characterStore.characters) { character in
                    NavigationLink(value: character.id) {
                        CharacterRow(character: character)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = character
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    pendingDelete = offsets.first.map { characterStore.characters[$0] }
                }
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
            .confirmationDialog(
                "Delete Character",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { character in
                Button("Delete \(character.name)", role: .destructive) {
                    characterStore.delete(id: character.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { character in
                Text("This permanently removes \(character.name) and cannot be undone.")
            }
        }
    }

    private func finalizeDraft(_ draft: CharacterDraft) -> Character {
        var character = draft.toCharacter()

        // Apply the player's chosen background ability bonuses (clamped to
        // the 5e ceiling of 20).
        for (ability, increase) in draft.backgroundAbilityBonuses {
            character.abilityScores[ability, default: 10] = min(
                Character.abilityScoreCeiling,
                (character.abilityScores[ability] ?? 10) + increase
            )
        }
        // Apply background skill proficiencies
        if let background = contentStore.backgroundDefinition(id: draft.backgroundID) {
            for skill in background.skillProficiencies {
                character.proficiencies[.skill(skill)] = .proficient
            }
        }
        // Carry the species picks made during creation (Draconic Ancestry,
        // lineage, Fiendish Legacy, innate-spellcasting ability). Distinct keys
        // from the class-skill seeding below, so order doesn't matter.
        for (selectionID, picks) in draft.featureSelections {
            character.featureSelections[selectionID] = picks
        }

        // Seed the class skill-choice selection from the player's creation
        // picks. Stored in featureSelections (not proficiencies) so the
        // Features tab can re-edit it; the calculator resolves these as
        // proficiency live.
        if let sel = contentStore.classDefinition(id: draft.classID)?.skillProficiencySelection {
            character.featureSelections[sel.selection.id] = draft.classSkillChoices.map(\.rawValue)
        }

        // Apply class proficiencies
        if let classDef = contentStore.classDefinition(id: draft.classID) {
            // Starting HP from the real class hit die + post-ASI CON. The
            // draft's placeholder math runs before background ASIs land and
            // assumes a d10 for every class, so both halves can be wrong here
            // (a Soldier's +1 CON never reached HP; a Wizard started at d10).
            character.rolledHP = classDef.hitDie.rawValue
            character.recalculateHP()
            character.currentHP = character.maxHP

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
