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

    // MARK: - Fixed-table prep budgets (2024 Bard/Sorcerer regression)

    @Test func fixedTableClassesUseTheirSpellsKnownTableAsPrepCap() {
        // Bard L1 = 4 prepared regardless of CHA — the SRD 2024 "Prepared
        // Spells" column, not ability mod + level. This is the bug the user
        // hit: a CHA-8 bard was getting max(1, -1 + 1) = 1 instead of 4.
        let store = ContentStore()
        var lowChaBard = makeCaster(classID: "bard", level: 1)
        lowChaBard.abilityScores[.charisma] = 8
        #expect(CharacterCalculator.maxPreparedSpells(
            character: lowChaBard, content: store, forClassID: "bard") == 4)
        // Sorcerer L1 = 2 by the table.
        #expect(CharacterCalculator.maxPreparedSpells(
            character: makeCaster(classID: "sorcerer", level: 1), content: store, forClassID: "sorcerer") == 2)
        // Growth follows the table, not the ability score.
        #expect(CharacterCalculator.maxPreparedSpells(
            character: makeCaster(classID: "bard", level: 20), content: store, forClassID: "bard") == 22)
        // Druid still uses ability mod + level (no fixed table).
        let wisDruid = makeCaster(classID: "druid", level: 3)  // WIS 14 → +2
        #expect(CharacterCalculator.maxPreparedSpells(
            character: wisDruid, content: store, forClassID: "druid") == 5)
    }

    @Test func fixedTableFlagIdentifiesTheRightClasses() {
        let store = ContentStore()
        #expect(CharacterCalculator.hasFixedSpellsTable(classID: "bard", content: store))
        #expect(CharacterCalculator.hasFixedSpellsTable(classID: "sorcerer", content: store))
        // Druid/wizard/cleric are unlimited-prep (no table).
        #expect(!CharacterCalculator.hasFixedSpellsTable(classID: "druid", content: store))
        #expect(!CharacterCalculator.hasFixedSpellsTable(classID: "wizard", content: store))
        #expect(!CharacterCalculator.hasFixedSpellsTable(classID: "cleric", content: store))
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
