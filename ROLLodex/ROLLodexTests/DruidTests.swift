import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct DruidTests {

    // MARK: - Helpers

    private func makeDruid(level: Int, wisdom: Int = 16) -> Character {
        Character(
            name: "Elora", level: level,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "druid", level: level)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 12, .wisdom: wisdom, .charisma: 10
            ],
            maxHP: 8
        )
    }

    // MARK: - Class load

    @Test func loadsDruidAsPreparedWisdomFullCaster() {
        let store = ContentStore()
        let druid = store.classDefinition(id: "druid")
        #expect(druid?.hitDie == 8)
        #expect(druid?.primaryAbility == .wisdom)
        #expect(druid?.savingThrows.contains(.wisdom) == true)
        #expect(druid?.savingThrows.contains(.intelligence) == true)
        let block = druid?.spellcasting
        #expect(block?.ability == .wisdom)
        #expect(block?.preparedRule == .preparedFromAll)
        #expect(block?.ritualCasting == true)
        // Full caster: 4 first-level slots by level 4.
        #expect(block?.slotTable.slots(atClassLevel: 4)[1] == 4)
        // Cantrips: 2 at L1, 3 at L4.
        #expect(block?.cantripsKnown.value(classLevel: 1, characterLevel: 1) == 2)
        #expect(block?.cantripsKnown.value(classLevel: 4, characterLevel: 4) == 3)
    }

    @Test func druidHasCircleOfTheLandSubclass() {
        let store = ContentStore()
        let druid = store.classDefinition(id: "druid")
        #expect(druid?.subclassLevel == 3)
        #expect(druid?.subclasses.contains { $0.id == "circle_of_the_land" } == true)
    }

    @Test func wildShapeIsAResourceWithTwoUsesAtLevelTwo() {
        let store = ContentStore()
        let character = makeDruid(level: 2)
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let wildShape = resources.first { $0.definition.id == "druid_wild_shape" }
        #expect(wildShape?.max == 2)
    }

    // MARK: - Spell class tagging / filtering

    @Test func druidSpellListIsTaggedAndFiltered() {
        let store = ContentStore()
        let list = CharacterCalculator.spellList(forClassID: "druid", content: store)
        // Every returned spell is actually tagged for druid (not a fallback to all).
        #expect(list.allSatisfy { $0.classes.contains("druid") })
        let ids = Set(list.map(\.id))
        #expect(ids.contains("druidcraft"))
        #expect(ids.contains("cure_wounds"))
        #expect(ids.contains("faerie_fire"))
        // Not a druid spell — must be excluded.
        #expect(!ids.contains("fire_bolt"))
        #expect(!ids.contains("magic_missile"))
    }

    @Test func untaggedClassFallsBackToFullCatalog() {
        // Wizard has no tagged spells yet → picker still shows everything.
        let store = ContentStore()
        let list = CharacterCalculator.spellList(forClassID: "wizard", content: store)
        #expect(list.count == store.allSpells.count)
    }

    // MARK: - Preparation limits

    @Test func maxPreparedIsAbilityModPlusLevel() {
        let store = ContentStore()
        // WIS 16 (+3), druid level 3 → 6 prepared.
        #expect(CharacterCalculator.maxPreparedSpells(character: makeDruid(level: 3, wisdom: 16), content: store) == 6)
        // WIS 20 (+5), druid level 5 → 10.
        #expect(CharacterCalculator.maxPreparedSpells(character: makeDruid(level: 5, wisdom: 20), content: store) == 10)
    }

    @Test func maxPreparedNeverBelowOne() {
        let store = ContentStore()
        // WIS 8 (−1) at level 1 → −1 + 1 = 0, clamped to 1.
        #expect(CharacterCalculator.maxPreparedSpells(character: makeDruid(level: 1, wisdom: 8), content: store) == 1)
    }

    @Test func nonCasterHasNoPrepLimitAndIsNotPreparedCaster() {
        let store = ContentStore()
        let fighter = Character(
            name: "Bruenor", level: 3,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.strength: 16, .dexterity: 12, .constitution: 14,
                            .intelligence: 10, .wisdom: 10, .charisma: 8],
            maxHP: 28
        )
        #expect(CharacterCalculator.maxPreparedSpells(character: fighter, content: store) == nil)
        #expect(CharacterCalculator.isPreparedCaster(character: fighter, content: store) == false)
    }

    @Test func druidIsAPreparedCaster() {
        let store = ContentStore()
        #expect(CharacterCalculator.isPreparedCaster(character: makeDruid(level: 3), content: store) == true)
    }

    @Test func preparedLeveledCountExcludesCantrips() {
        let store = ContentStore()
        var character = makeDruid(level: 3)
        character.spells.preparedIDs = ["druidcraft", "cure_wounds", "faerie_fire"] // 1 cantrip + 2 leveled
        #expect(CharacterCalculator.preparedLeveledCount(character: character, content: store) == 2)
    }
}
