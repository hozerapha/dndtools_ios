import Testing
import Foundation
@testable import ROLLodex

/// Tests the draft-to-character pipeline as exercised by `CharacterDraft.toCharacter()`
/// and the real `ContentStore` lookups that `CharacterListView.finalizeDraft` applies
/// on top of it. The helper below mirrors that view logic so the model conversion is
/// covered without reaching into private UI code.
@MainActor
struct CharacterCreationFinalizationTests {

    private let content = ContentStore(importedContentDirectory: Self.makeTempDir())

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDraft(
        classID: String = "fighter",
        backgroundID: String = "soldier",
        speciesID: String = "human"
    ) -> CharacterDraft {
        var draft = CharacterDraft()
        draft.name = "Test Hero"
        draft.classID = classID
        draft.backgroundID = backgroundID
        draft.speciesID = speciesID
        draft.abilityScores = [
            .strength: 15,
            .dexterity: 14,
            .constitution: 14,
            .intelligence: 12,
            .wisdom: 10,
            .charisma: 8
        ]
        return draft
    }

    private func finalize(_ draft: CharacterDraft) -> Character {
        var character = draft.toCharacter()

        // Background ASIs (mirrors CharacterListView).
        for (ability, increase) in draft.backgroundAbilityBonuses {
            character.abilityScores[ability, default: 10] = min(
                Character.abilityScoreCeiling,
                (character.abilityScores[ability] ?? 10) + increase
            )
        }

        // Background skill proficiencies.
        if let background = content.backgroundDefinition(id: draft.backgroundID) {
            for skill in background.skillProficiencies {
                character.proficiencies[.skill(skill)] = .proficient
            }
        }

        // Species selections carried over.
        for (selectionID, picks) in draft.featureSelections {
            character.featureSelections[selectionID] = picks
        }

        // Class skill choices.
        if let sel = content.classDefinition(id: draft.classID)?.skillProficiencySelection {
            character.featureSelections[sel.selection.id] = draft.classSkillChoices.map(\.rawValue)
        }

        // Class-derived HP, saves, armor/weapon/tool proficiencies.
        if let classDef = content.classDefinition(id: draft.classID) {
            character.rolledHP = classDef.hitDie.rawValue
            character.rolledHP += CharacterCalculator.featureHitPointBonus(character: character, content: content)
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
            for feature in classDef.levelFeatures[1] ?? [] {
                for key in feature.grantsProficiencies ?? [] {
                    character.proficiencies[key] = .proficient
                }
            }

            if classDef.spellcasting != nil {
                seedStartingSpells(character: &character, classDef: classDef)
            }
        }

        return character
    }

    private func seedStartingSpells(character: inout Character, classDef: ClassDefinition) {
        guard let block = classDef.spellcasting else { return }
        let classLevel = character.classEntries.first { $0.classID == classDef.id }?.level ?? 1
        let cantripBudget = block.cantripsKnown.value(classLevel: classLevel, characterLevel: character.level)

        let allSpells = Array(content.spells.values)
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
            character.spells.spellbookIDs = leveledIDs
            character.spells.preparedByClass[classDef.id] = cantripIDs + leveledIDs
        case .preparedFromAll:
            character.spells.preparedByClass[classDef.id] = cantripIDs + leveledIDs
        }
    }

    // MARK: - Core conversion

    @Test func toCharacterProducesLevelOneCharacter() {
        let draft = makeDraft()
        let character = draft.toCharacter()

        #expect(character.name == "Test Hero")
        #expect(character.level == 1)
        #expect(character.classEntries == [ClassEntry(classID: "fighter", level: 1)])
        #expect(character.speciesID == "human")
        #expect(character.backgroundID == "soldier")
    }

    @Test func backgroundASIsAreAppliedAndCapped() {
        var draft = makeDraft(backgroundID: "soldier")
        draft.backgroundAbilityBonuses = [.strength: 2, .dexterity: 1]
        let character = finalize(draft)

        #expect(character.abilityScores[.strength] == 17)
        #expect(character.abilityScores[.dexterity] == 15)
    }

    @Test func backgroundASICeilingIsRespected() {
        var draft = makeDraft(backgroundID: "soldier")
        draft.abilityScores[.strength] = 19
        draft.backgroundAbilityBonuses = [.strength: 2]
        let character = finalize(draft)

        #expect(character.abilityScores[.strength] == Character.abilityScoreCeiling)
    }

    @Test func backgroundSkillProficienciesAreWired() {
        var draft = makeDraft(backgroundID: "soldier")
        draft.backgroundAbilityBonuses = [.strength: 2, .dexterity: 1]
        let character = finalize(draft)

        #expect(character.proficiencies[.skill(.athletics)] == .proficient)
        #expect(character.proficiencies[.skill(.intimidation)] == .proficient)
    }

    @Test func classSkillChoicesAreSeededAsFeatureSelections() {
        var draft = makeDraft(classID: "fighter")
        draft.backgroundAbilityBonuses = [.strength: 2, .dexterity: 1]
        draft.classSkillChoices = [.acrobatics, .animalHandling]
        let character = finalize(draft)

        let selections = character.featureSelections["fighter_class_skills"] ?? []
        #expect(selections.count == 2)
        #expect(selections.contains("acrobatics"))
        #expect(selections.contains("animal_handling"))
    }

    @Test func classProficienciesAreApplied() {
        let draft = makeDraft(classID: "fighter")
        let character = finalize(draft)

        #expect(character.proficiencies[.savingThrow(.strength)] == .proficient)
        #expect(character.proficiencies[.savingThrow(.constitution)] == .proficient)
        #expect(character.proficiencies[.armor(.heavy)] == .proficient)
        #expect(character.proficiencies[.armor(.shield)] == .proficient)
        #expect(character.proficiencies[.weapon(.simple)] == .proficient)
        #expect(character.proficiencies[.weapon(.martial)] == .proficient)
    }

    @Test func hitPointsUseRealClassHitDieAndConstitution() {
        let draft = makeDraft(classID: "fighter")
        let character = finalize(draft)
        // Fighter d10 + CON(+2) = 12.
        #expect(character.maxHP == 12)
        #expect(character.currentHP == character.maxHP)
    }

    @Test func speciesSelectionsAreCarriedOver() {
        var draft = makeDraft(speciesID: "dragonborn")
        draft.featureSelections = ["dragonborn_ancestry": ["red"]]
        let character = finalize(draft)

        #expect(character.featureSelections["dragonborn_ancestry"] == ["red"])
    }

    // MARK: - Spellcasting classes

    @Test func wizardSeedsSpellbookAndPreparedLists() {
        var draft = makeDraft(classID: "wizard")
        draft.abilityScores[.intelligence] = 16
        draft.classSkillChoices = [.arcana, .investigation]
        let character = finalize(draft)

        let prepared = character.spells.preparedByClass["wizard"] ?? []
        #expect(!character.spells.spellbookIDs.isEmpty)
        #expect(!prepared.isEmpty)
        #expect(prepared.contains(where: { character.spells.spellbookIDs.contains($0) }))
    }
}
