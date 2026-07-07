import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct RangerTests {

    // MARK: - Fixtures

    private func makeRanger(level: Int, hunter: Bool = false, equipped: [String] = ["longsword"]) -> Character {
        var selections: [String: [String]] = [:]
        if hunter {
            selections["ranger_subclass"] = ["hunter"]
        }
        return Character(
            name: "Aragorn", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "ranger", level: level)],
            abilityScores: [
                .strength: 14, .dexterity: 16, .constitution: 14,
                .intelligence: 10, .wisdom: 16, .charisma: 10
            ],
            maxHP: 10,
            proficiencies: [
                .weapon(.simple): .proficient, .weapon(.martial): .proficient,
                .armor(.light): .proficient, .armor(.medium): .proficient
            ],
            inventory: equipped.map { InventoryItem(itemID: $0, quantity: 1, equipped: true) },
            featureSelections: selections
        )
    }

    private func slotPools(_ c: Character, _ s: ContentStore) -> [ResolvedResource] {
        ResourceCalculator.availableResources(character: c, content: s)
            .filter { if case .spellSlot = $0.definition.displayHint { return true }; return false }
    }

    // MARK: - Class load

    @Test func loadsRangerAsWisdomHalfCaster() {
        let store = ContentStore()
        let ranger = store.classDefinition(id: "ranger")
        #expect(ranger?.hitDie == .d10)
        #expect(ranger?.primaryAbility == .dexterity)
        let block = ranger?.spellcasting
        #expect(block?.ability == .wisdom)
        #expect(block?.preparedRule == .preparedFromAll)
        #expect(block?.casterLevelDivisor == 2)
        #expect(block?.spellsKnown != nil)
        #expect(block?.ritualCasting == false)
        #expect(ranger?.subclassLevel == 3)
        #expect(ranger?.subclasses.first?.id == "hunter")
    }

    // MARK: - Half-caster slots

    @Test func rangerHasNoSlotsAtLevelOne() {
        let store = ContentStore()
        let pools = slotPools(makeRanger(level: 1), store)
        #expect(pools.isEmpty)
    }

    @Test func rangerL2GetsTwoLevelOneSlots() {
        let store = ContentStore()
        let pools = slotPools(makeRanger(level: 2), store)
        #expect(pools.count == 1)
        #expect(pools.first?.definition.id == "ranger_slot_1")
        #expect(pools.first?.max == 2)
        #expect(pools.first?.definition.refreshOn == .longRest)
    }

    @Test func rangerL5MatchesPaladinSlotProgression() {
        let store = ContentStore()
        let pools = slotPools(makeRanger(level: 5), store)
        #expect(pools.first { $0.definition.id == "ranger_slot_1" }?.max == 4)
        #expect(pools.first { $0.definition.id == "ranger_slot_2" }?.max == 2)
    }

    @Test func rangerHalfCastingCountsHalfInMulticlass() {
        let store = ContentStore()
        // Druid 3 / Ranger 4 → combined caster level 3 + 4/2 = 5 → 4 L1, 3 L2, 2 L3 slots.
        let character = Character(
            name: "Poly", level: 7,
            speciesID: "human", backgroundID: "sage",
            classEntries: [
                ClassEntry(classID: "druid", level: 3),
                ClassEntry(classID: "ranger", level: 4)
            ],
            abilityScores: [.wisdom: 16, .dexterity: 14, .constitution: 14],
            maxHP: 42
        )
        #expect(ResourceCalculator.combinedCasterLevel(character: character, content: store) == 5)
        let pools = slotPools(character, store)
        #expect(pools.first { $0.definition.id == "multiclass_slot_1" }?.max == 4)
        #expect(pools.first { $0.definition.id == "multiclass_slot_2" }?.max == 3)
        #expect(pools.first { $0.definition.id == "multiclass_slot_3" }?.max == 2)
    }

    // MARK: - Prepared table + Hunter's Mark grant

    @Test func rangerUsesFixedSpellsTableForPrepCap() {
        let store = ContentStore()
        // Ranger L1 = 2 by the table regardless of WIS mod (the bug the
        // Bard fix closed — Ranger is the third fixed-table caster).
        var lowWisRanger = makeRanger(level: 1)
        lowWisRanger.abilityScores[.wisdom] = 8
        #expect(CharacterCalculator.maxPreparedSpells(
            character: lowWisRanger, content: store, forClassID: "ranger") == 2)
        #expect(CharacterCalculator.maxPreparedSpells(
            character: makeRanger(level: 5), content: store, forClassID: "ranger") == 6)
        #expect(CharacterCalculator.hasFixedSpellsTable(classID: "ranger", content: store))
    }

    @Test func rangerAlwaysHasHuntersMarkGranted() {
        let store = ContentStore()
        let ranger = makeRanger(level: 1)
        let granted = CharacterSpellGrants.resolve(character: ranger, content: store)
        #expect(granted.contains { $0.spell.id == "hunters_mark" })
    }

    @Test func huntersMarkFreeCastPoolScales() {
        let store = ContentStore()
        func poolMax(_ level: Int) -> Int? {
            ResourceCalculator.availableResources(character: makeRanger(level: level), content: store)
                .first { $0.definition.id == "ranger_hunters_mark_free" }?.max
        }
        #expect(poolMax(1) == 2)
        #expect(poolMax(5) == 3)
        #expect(poolMax(13) == 4)
        #expect(poolMax(17) == 5)
    }

    // MARK: - Roving (speed bonus)

    @Test func rovingBumpsSpeedByTen() {
        let store = ContentStore()
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeRanger(level: 4), content: store, unarmored: true) == 0)
        // At L5 Roving fires.
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeRanger(level: 5), content: store, unarmored: true) == 10)
    }

    // MARK: - Hunter: Colossus Slayer rider

    @Test func colossusSlayerRiderFiresForHunter() {
        let store = ContentStore()
        let hunter = makeRanger(level: 3, hunter: true)
        let weapon = store.weaponDefinition(id: "longsword")!
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: weapon, character: hunter, content: store
        )
        let cs = riders.first { $0.label == "Colossus Slayer" }
        #expect(cs != nil)
        #expect(cs?.formula.groups.first?.count == 1)
        #expect(cs?.formula.groups.first?.kind == .d8)
        #expect(cs?.formula.groups.first?.damageType == weapon.damageType)
    }

    @Test func colossusSlayerIsOncePerTurn() {
        let store = ContentStore()
        var hunter = makeRanger(level: 3, hunter: true)
        hunter.setTurnFlag("colossus_slayer")
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: store.weaponDefinition(id: "longsword"), character: hunter, content: store
        )
        #expect(!riders.contains { $0.label == "Colossus Slayer" })
    }

    @Test func nonHunterRangerHasNoColossusSlayerRider() {
        let store = ContentStore()
        let ranger = makeRanger(level: 3, hunter: false)
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: store.weaponDefinition(id: "longsword"), character: ranger, content: store
        )
        #expect(!riders.contains { $0.label == "Colossus Slayer" })
    }
}
