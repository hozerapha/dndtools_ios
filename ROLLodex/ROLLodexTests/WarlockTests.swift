import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct WarlockTests {

    // MARK: - Fixtures

    private func makeWarlock(level: Int, fiend: Bool = false) -> Character {
        Character(
            name: "Wyll", level: level,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "warlock", level: level)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 12, .wisdom: 13, .charisma: 16
            ],
            maxHP: 8,
            featureSelections: fiend ? ["warlock_subclass": ["fiend_patron"]] : [:]
        )
    }

    private func slotPools(_ c: Character, _ s: ContentStore) -> [ResolvedResource] {
        ResourceCalculator.availableResources(character: c, content: s)
            .filter { if case .spellSlot = $0.definition.displayHint { return true }; return false }
    }

    // MARK: - Class load

    @Test func loadsWarlockAsPactMagicCharismaCaster() {
        let store = ContentStore()
        let warlock = store.classDefinition(id: "warlock")
        #expect(warlock?.hitDie == .d8)
        #expect(warlock?.primaryAbility == .charisma)
        let block = warlock?.spellcasting
        #expect(block?.ability == .charisma)
        #expect(block?.preparedRule == .pactMagic)
        #expect(block?.slotTable.isPactMagic == true)
        #expect(block?.ritualCasting == false)
        #expect(warlock?.subclasses.contains { $0.id == "fiend_patron" } == true)
    }

    // MARK: - Pact magic slots

    @Test func pactSlotsAreOneLevelAndShortRestRefreshing() {
        let store = ContentStore()
        // L5 warlock: two slots, all at slot level 3, refreshing on Short Rest.
        let pools = slotPools(makeWarlock(level: 5), store)
        #expect(pools.count == 1)
        #expect(pools.first?.definition.id == "warlock_slot_3")
        #expect(pools.first?.max == 2)
        #expect(pools.first?.definition.refreshOn == .shortRest)
    }

    @Test func pactSlotsScaleWithWarlockLevel() {
        let store = ContentStore()
        #expect(slotPools(makeWarlock(level: 1), store).first?.max == 1)
        let l11 = slotPools(makeWarlock(level: 11), store).first
        #expect(l11?.definition.id == "warlock_slot_5")
        #expect(l11?.max == 3)
        #expect(slotPools(makeWarlock(level: 17), store).first?.max == 4)
    }

    @Test func pactMagicIsExcludedFromMulticlassCasterLevel() {
        let store = ContentStore()
        // Druid 3 / Warlock 3: combined caster level counts ONLY the druid;
        // no merged pools — druid keeps its own slots, warlock keeps pact.
        let character = Character(
            name: "Poly", level: 6,
            speciesID: "human", backgroundID: "sage",
            classEntries: [
                ClassEntry(classID: "druid", level: 3),
                ClassEntry(classID: "warlock", level: 3)
            ],
            abilityScores: [.wisdom: 16, .charisma: 16, .constitution: 14],
            maxHP: 30
        )
        #expect(ResourceCalculator.combinedCasterLevel(character: character, content: store) == 3)
        let pools = slotPools(character, store)
        #expect(pools.contains { $0.definition.id == "druid_slot_1" })
        #expect(pools.contains { $0.definition.id == "warlock_slot_2" })
        #expect(!pools.contains { $0.definition.id.hasPrefix("multiclass_slot_") })
    }

    // MARK: - Known-spell budget (Learn mode)

    @Test func warlockKnownBudgetFollowsTheTable() {
        let store = ContentStore()
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeWarlock(level: 1), content: store, forClassID: "warlock") == 2)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeWarlock(level: 5), content: store, forClassID: "warlock") == 6)
        #expect(CharacterCalculator.knownSpellBudget(
            character: makeWarlock(level: 19), content: store, forClassID: "warlock") == 15)
    }

    @Test func eldritchBlastIsWarlockOnly() {
        let store = ContentStore()
        let warlockList = CharacterCalculator.spellList(forClassID: "warlock", content: store)
        #expect(warlockList.contains { $0.id == "eldritch_blast" })
        let wizardList = CharacterCalculator.spellList(forClassID: "wizard", content: store)
        #expect(!wizardList.contains { $0.id == "eldritch_blast" })
    }

    // MARK: - Features & subclass

    @Test func invocationCountScalesByLevel() {
        let store = ContentStore()
        let warlock = store.classDefinition(id: "warlock")
        let feature = warlock?.levelFeatures[1]?.first { $0.id == "eldritch_invocations" }
        let count = feature?.selection?.count
        #expect(count?.value(classLevel: 1, characterLevel: 1) == 1)
        #expect(count?.value(classLevel: 5, characterLevel: 5) == 5)
        #expect(count?.value(classLevel: 18, characterLevel: 18) == 10)
    }

    @Test func fiendGrantsCommandAtLevelThree() {
        let store = ContentStore()
        let granted = CharacterSpellGrants.resolve(
            character: makeWarlock(level: 3, fiend: true), content: store
        )
        #expect(granted.contains { $0.spell.id == "command" })
        // No subclass chosen → no grant.
        let ungrantedWarlock = CharacterSpellGrants.resolve(
            character: makeWarlock(level: 3, fiend: false), content: store
        )
        #expect(!ungrantedWarlock.contains { $0.spell.id == "command" })
    }

    @Test func fiendResourcesResolve() {
        let store = ContentStore()
        let resources = ResourceCalculator.availableResources(
            character: makeWarlock(level: 14, fiend: true), content: store
        )
        // Dark One's Own Luck: CHA mod (+3) uses.
        #expect(resources.first { $0.definition.id == "warlock_dark_ones_own_luck" }?.max == 3)
        #expect(resources.first { $0.definition.id == "warlock_hurl_through_hell" }?.max == 1)
        #expect(resources.first { $0.definition.id == "warlock_magical_cunning" }?.max == 1)
    }
}
