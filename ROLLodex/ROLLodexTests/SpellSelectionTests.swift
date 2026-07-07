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

    // MARK: - Picker level filter (a L4 bard shouldn't see L3+ spells)

    @Test func maxSpellSlotLevelReflectsClassSlotTable() {
        let store = ContentStore()
        // L4 bard: full caster, slot table maxes at level 2 → no L3+ picker
        // rows. This is the exact bug the user hit — the picker was showing
        // Fear (3rd), Charm Monster (4th), Legend Lore (5th) to a L4 bard.
        let l4bard = makeCaster(classID: "bard", level: 4)
        #expect(CharacterCalculator.maxSpellSlotLevel(character: l4bard, content: store) == 2)
        // L9 bard: full-caster table reaches L5 slots.
        let l9bard = makeCaster(classID: "bard", level: 9)
        #expect(CharacterCalculator.maxSpellSlotLevel(character: l9bard, content: store) == 5)
    }

    @Test func rangerHasNoSlotLevelAtLevelOne() {
        // Half-caster edge: L1 ranger has NO slots yet, so max slot level is
        // nil (picker falls back to cantrips + L1 with a defensive default).
        let store = ContentStore()
        let ranger = makeCaster(classID: "ranger", level: 1)
        #expect(CharacterCalculator.maxSpellSlotLevel(character: ranger, content: store) == nil)
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

    // MARK: - Picker presentation (title label unification)

    @Test func learnCastersShareOneRegimeRegardlessOfPreparedRule() {
        // What matters for the picker's day-to-day title is whether the class
        // has a fixed spellsKnown table. Bard/Sorcerer/Ranger use
        // preparedFromAll + table, Warlock uses pactMagic + table — they all
        // fall into the same customization regime (Manage), so the sheet's
        // button label ends up the same string for all four.
        let store = ContentStore()
        for classID in ["bard", "sorcerer", "ranger", "warlock"] {
            #expect(
                store.classDefinition(id: classID)?.spellcasting?.spellsKnown != nil,
                "\(classID) should have a fixed spellsKnown table"
            )
        }
        // Unlimited-prep classes have NO fixed table.
        for classID in ["cleric", "druid", "paladin"] {
            #expect(
                store.classDefinition(id: classID)?.spellcasting?.spellsKnown == nil,
                "\(classID) should NOT have a spellsKnown table (unlimited prep)"
            )
        }
    }

    @Test func draftCarriesChosenSpells() {
        var draft = CharacterDraft()
        draft.classID = "druid"
        #expect(draft.chosenSpellIDs.isEmpty)
        draft.chosenSpellIDs = ["druidcraft", "cure_wounds"]
        #expect(draft.chosenSpellIDs.count == 2)
    }
}
