import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct MulticlassTests {

    // MARK: - Fixtures

    private func makeCharacter(
        classes: [(String, Int)],
        scores: [Ability: Int] = [
            .strength: 14, .dexterity: 14, .constitution: 14,
            .intelligence: 14, .wisdom: 16, .charisma: 14
        ]
    ) -> Character {
        Character(
            name: "Poly", level: classes.reduce(0) { $0 + $1.1 },
            speciesID: "human", backgroundID: "sage",
            classEntries: classes.map { ClassEntry(classID: $0.0, level: $0.1) },
            abilityScores: scores,
            maxHP: 20
        )
    }

    private func slotPools(_ character: Character, _ store: ContentStore) -> [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: store)
            .filter { if case .spellSlot = $0.definition.displayHint { return true }; return false }
    }

    // MARK: - Combined caster level & slot merging

    @Test func singleClassCasterKeepsPerClassSlotPools() {
        let store = ContentStore()
        let druid = makeCharacter(classes: [("druid", 3)])
        let pools = slotPools(druid, store)
        #expect(pools.allSatisfy { $0.definition.id.hasPrefix("druid_slot_") })
        #expect(pools.first { $0.definition.id == "druid_slot_1" }?.max == 4)
        #expect(pools.first { $0.definition.id == "druid_slot_2" }?.max == 2)
    }

    @Test func twoFullCastersMergeIntoTheSharedTable() {
        let store = ContentStore()
        // Druid 2 / Cleric 2 → combined caster level 4 → 4× L1, 3× L2.
        // Per-class it would (wrongly) be 3+3 L1 and no L2.
        let character = makeCharacter(classes: [("druid", 2), ("cleric", 2)])
        #expect(ResourceCalculator.combinedCasterLevel(character: character, content: store) == 4)
        let pools = slotPools(character, store)
        #expect(pools.allSatisfy { $0.definition.id.hasPrefix("multiclass_slot_") })
        #expect(pools.first { $0.definition.id == "multiclass_slot_1" }?.max == 4)
        #expect(pools.first { $0.definition.id == "multiclass_slot_2" }?.max == 3)
    }

    @Test func halfCasterCountsHalfRoundedDown() {
        let store = ContentStore()
        // Druid 3 / Paladin 3 → 3 + 3/2 = 4 (paladin has casterLevelDivisor 2).
        let character = makeCharacter(classes: [("druid", 3), ("paladin", 3)])
        #expect(ResourceCalculator.combinedCasterLevel(character: character, content: store) == 4)
    }

    @Test func nonCasterClassDoesNotTriggerMerging() {
        let store = ContentStore()
        // Druid 3 / Fighter 2 → still one casting class → per-class pools.
        let character = makeCharacter(classes: [("druid", 3), ("fighter", 2)])
        let pools = slotPools(character, store)
        #expect(pools.allSatisfy { $0.definition.id.hasPrefix("druid_slot_") })
    }

    @Test func multiclassResourceIDsHaveNoDuplicates() {
        let store = ContentStore()
        let character = makeCharacter(classes: [("cleric", 3), ("paladin", 3)])
        let all = ResourceCalculator.availableResources(character: character, content: store)
        let ids = all.map(\.definition.id)
        #expect(Set(ids).count == ids.count)
        // Both Channel Divinities exist under their namespaced ids.
        #expect(ids.contains("cleric_channel_divinity"))
        #expect(ids.contains("paladin_channel_divinity"))
    }

    // MARK: - Prerequisites (RAW hard block)

    @Test func multiclassBlockedWhenNewClassPrimaryBelow13() {
        let store = ContentStore()
        let fighter = makeCharacter(
            classes: [("fighter", 3)],
            scores: [.strength: 16, .dexterity: 12, .constitution: 14,
                     .intelligence: 10, .wisdom: 10, .charisma: 8]
        )
        // Druid needs WIS 13 — this fighter has WIS 10.
        let blocker = CharacterCalculator.multiclassBlocker(
            addingClassID: "druid", character: fighter, content: store
        )
        #expect(blocker != nil)
        #expect(blocker?.contains("WIS") == true)
    }

    @Test func multiclassBlockedWhenCurrentClassPrimaryBelow13() {
        let store = ContentStore()
        // Fighter primary STR 10 blocks multiclassing OUT even with WIS 16.
        let fighter = makeCharacter(
            classes: [("fighter", 3)],
            scores: [.strength: 10, .dexterity: 14, .constitution: 14,
                     .intelligence: 10, .wisdom: 16, .charisma: 8]
        )
        let blocker = CharacterCalculator.multiclassBlocker(
            addingClassID: "druid", character: fighter, content: store
        )
        #expect(blocker?.contains("STR") == true)
    }

    @Test func multiclassAllowedWhenBothPrimariesAre13Plus() {
        let store = ContentStore()
        let fighter = makeCharacter(
            classes: [("fighter", 3)],
            scores: [.strength: 16, .dexterity: 12, .constitution: 14,
                     .intelligence: 10, .wisdom: 14, .charisma: 8]
        )
        let blocker = CharacterCalculator.multiclassBlocker(
            addingClassID: "druid", character: fighter, content: store
        )
        #expect(blocker == nil)
    }

    // MARK: - Multiclass proficiency lists (content)

    @Test func bundledClassesCarryTheir5eMulticlassProficiencies() {
        let store = ContentStore()
        #expect(store.classDefinition(id: "druid")?.multiclassProficiencies
            .contains(.armor(.light)) == true)
        #expect(store.classDefinition(id: "fighter")?.multiclassProficiencies
            .contains(.weapon(.martial)) == true)
        // Wizard/sorcerer grant nothing on multiclass.
        #expect(store.classDefinition(id: "wizard")?.multiclassProficiencies.isEmpty == true)
        #expect(store.classDefinition(id: "sorcerer")?.multiclassProficiencies.isEmpty == true)
        // Never saving throws, never skills (choice-based ones stay manual).
        for cls in store.allClasses {
            #expect(cls.multiclassProficiencies.allSatisfy { key in
                if case .savingThrow = key { return false }
                if case .skill = key { return false }
                return true
            })
        }
    }

    // MARK: - Per-class preparation

    @Test func eachPreparedCasterClassHasItsOwnCap() {
        let store = ContentStore()
        // WIS 16 (+3): Druid 3 → 6; Cleric 2 → 5. Separate caps.
        let character = makeCharacter(classes: [("druid", 3), ("cleric", 2)])
        #expect(CharacterCalculator.maxPreparedSpells(
            character: character, content: store, forClassID: "druid") == 6)
        #expect(CharacterCalculator.maxPreparedSpells(
            character: character, content: store, forClassID: "cleric") == 5)
    }

    @Test func preparedCountsAreScopedToTheClassBucket() {
        let store = ContentStore()
        var character = makeCharacter(classes: [("druid", 3), ("cleric", 2)])
        character.spells.preparedByClass["druid"] = ["cure_wounds", "faerie_fire", "druidcraft"]
        character.spells.preparedByClass["cleric"] = ["bless"]
        #expect(CharacterCalculator.preparedLeveledCount(
            character: character, content: store, forClassID: "druid") == 2)
        #expect(CharacterCalculator.preparedLeveledCount(
            character: character, content: store, forClassID: "cleric") == 1)
        // Whole-character union counts all three leveled spells.
        #expect(CharacterCalculator.preparedLeveledCount(character: character, content: store) == 3)
    }

    // MARK: - Per-spell casting ability

    @Test func spellAbilityFollowsThePreparingClass() {
        let store = ContentStore()
        // Cleric(WIS) first, Sorcerer(CHA) second. A spell in the sorcerer's
        // known flow but prepared under neither → tagged/list fallback.
        var character = makeCharacter(classes: [("druid", 3), ("sorcerer", 2)])
        character.spells.preparedByClass["druid"] = ["cure_wounds"]
        // cure_wounds sits in the druid bucket → WIS.
        #expect(CharacterCalculator.spellcastingAbility(
            forSpellID: "cure_wounds", character: character, content: store) == .wisdom)
        // fire_bolt isn't prepared and isn't druid-tagged → falls back to the
        // first casting class (druid → WIS is wrong RAW, but it's the declared
        // fallback; the important part is the prepared-bucket override above).
        #expect(CharacterCalculator.spellcastingAbility(
            forSpellID: "fire_bolt", character: character, content: store) != nil)
    }

    // MARK: - Legacy migration

    @Test func legacyFlatPreparedListMigratesToFirstClassBucket() throws {
        let store = ContentStore()
        var original = makeCharacter(classes: [("druid", 3)])
        original.spells.preparedIDs = ["druidcraft", "cure_wounds"]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.spells.preparedIDs.isEmpty)
        #expect(decoded.spells.preparedByClass["druid"] == ["druidcraft", "cure_wounds"])
        // And the whole-character view still sees both.
        #expect(Set(decoded.spells.allPreparedIDs) == ["druidcraft", "cure_wounds"])
        _ = store  // silences unused warning if assertions change
    }

    // MARK: - Display

    @Test func classSummaryShowsLevelsOnlyWhenMulticlassed() {
        let store = ContentStore()
        let single = makeCharacter(classes: [("druid", 3)])
        #expect(CharacterCalculator.classSummary(character: single, content: store) == "Druid")
        let multi = makeCharacter(classes: [("druid", 3), ("cleric", 2)])
        #expect(CharacterCalculator.classSummary(character: multi, content: store) == "Druid 3 / Cleric 2")
    }
}
