import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SpellSelectionTests {

    // MARK: - Class tagging (SRD 5.2.1 lists)

    @Test func everyBundledSpellCarriesAClassList() {
        let store = ContentStore()
        for spell in store.allSpells {
            #expect(!spell.classes.isEmpty, "untagged spell: \(spell.id)")
        }
    }

    @Test func spellTagsReferenceOnlyKnownClassIDs() {
        let store = ContentStore()
        // Bundled classes plus SRD casters not yet authored (their tags light
        // up when the class ships).
        let allowed = Set(store.allClasses.map(\.id)).union(["ranger", "warlock"])
        for spell in store.allSpells {
            for tag in spell.classes {
                #expect(allowed.contains(tag), "\(spell.id) tags unknown class \(tag)")
            }
        }
    }

    @Test func blessIsClericAndPaladinOnly() {
        let store = ContentStore()
        #expect(store.spellDefinition(id: "bless")?.classes.sorted() == ["cleric", "paladin"])
        let wizardList = CharacterCalculator.spellList(forClassID: "wizard", content: store)
        #expect(!wizardList.contains { $0.id == "bless" })
        let clericList = CharacterCalculator.spellList(forClassID: "cleric", content: store)
        #expect(clericList.contains { $0.id == "bless" })
    }

    @Test func wizardListNoLongerFallsBackToFullCatalog() {
        let store = ContentStore()
        let wizardList = CharacterCalculator.spellList(forClassID: "wizard", content: store)
        #expect(wizardList.count < store.allSpells.count)
        #expect(wizardList.contains { $0.id == "fire_bolt" })
        #expect(!wizardList.contains { $0.id == "sacred_flame" })
    }

    // MARK: - Known-spell budgets

    private func makeCaster(classID: String, level: Int) -> Character {
        Character(
            name: "Caster", level: level,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: classID, level: level)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 14, .wisdom: 14, .charisma: 16
            ],
            maxHP: 8
        )
    }

    @Test func knownSpellBudgetsFollowTheSRDTables() {
        let store = ContentStore()
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "bard", level: 1), content: store, forClassID: "bard") == 4)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "sorcerer", level: 1), content: store, forClassID: "sorcerer") == 2)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "sorcerer", level: 3), content: store, forClassID: "sorcerer") == 6)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "bard", level: 20), content: store, forClassID: "bard") == 22)
    }

    @Test func preparedCastersHaveNoKnownBudget() {
        let store = ContentStore()
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "druid", level: 3), content: store, forClassID: "druid") == nil)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeCaster(classID: "wizard", level: 3), content: store, forClassID: "wizard") == nil)
    }

    @Test func knownLeveledCountExcludesCantrips() {
        let store = ContentStore()
        var bard = makeCaster(classID: "bard", level: 1)
        bard.spells.knownIDs = ["dancing_lights", "healing_word", "faerie_fire"] // 1 cantrip + 2 leveled
        #expect(CharacterCalculator.knownLeveledCount(character: bard, content: store) == 2)
    }

    // MARK: - Creation draft picks

    @Test func draftCarriesChosenSpells() {
        var draft = CharacterDraft()
        draft.classID = "druid"
        #expect(draft.chosenSpellIDs.isEmpty)
        draft.chosenSpellIDs = ["druidcraft", "cure_wounds"]
        #expect(draft.chosenSpellIDs.count == 2)
    }
}
