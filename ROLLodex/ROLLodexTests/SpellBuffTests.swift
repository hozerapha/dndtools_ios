import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SpellBuffTests {

    // MARK: - Helpers

    private func makeWizard(equippedArmor: String? = nil) -> Character {
        var inventory: [InventoryItem] = []
        if let armor = equippedArmor {
            inventory.append(InventoryItem(itemID: armor, quantity: 1, equipped: true))
        }
        return Character(
            name: "Gale", level: 3,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 3)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 16, .wisdom: 12, .charisma: 10
            ],
            maxHP: 18,
            inventory: inventory
        )
    }

    // MARK: - Model round-trip

    @Test func selfBuffRoundTrips() throws {
        let effect = SpellEffect.selfBuff(SpellBuffEffect(
            acBonus: 5, unarmoredACBase: 13, attackAndSaveBonusDice: "1d4", speedBonus: 10, rounds: 1
        ))
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(SpellEffect.self, from: data)
        #expect(decoded == effect)
    }

    @Test func bundledBuffSpellsCarryTheirEffects() {
        let store = ContentStore()
        func buff(_ id: String) -> SpellBuffEffect? {
            store.spellDefinition(id: id)?.effects.compactMap {
                if case .selfBuff(let b) = $0 { return b } else { return nil }
            }.first
        }
        #expect(buff("bless")?.attackAndSaveBonusDice == "1d4")
        #expect(buff("shield")?.acBonus == 5)
        #expect(buff("shield_of_faith")?.acBonus == 2)
        #expect(buff("mage_armor")?.unarmoredACBase == 13)
        #expect(buff("longstrider")?.speedBonus == 10)
    }

    // MARK: - AC buffs

    @Test func shieldOfFaithAddsTwoAC() {
        let store = ContentStore()
        var character = makeWizard()
        let before = CharacterCalculator.spellACBonus(character: character, content: store)
        character.applySpellBuff(spellID: "shield_of_faith", rounds: nil)
        let after = CharacterCalculator.spellACBonus(character: character, content: store)
        #expect(before == 0)
        #expect(after == 2)
    }

    @Test func mageArmorSetsUnarmoredBaseTo13() {
        let store = ContentStore()
        var character = makeWizard()
        character.applySpellBuff(spellID: "mage_armor", rounds: nil)
        let base = CharacterCalculator.spellUnarmoredACBase(character: character, content: store)
        #expect(base == 13)
        // 13 + DEX(+2) = 15 unarmored.
        let ac = CharacterCalculator.armorClass(
            dexMod: 2, armor: nil, hasShield: false, unarmoredACBase: base
        )
        #expect(ac == 15)
    }

    @Test func shieldAndShieldOfFaithACStack() {
        let store = ContentStore()
        var character = makeWizard()
        character.applySpellBuff(spellID: "shield", rounds: 1)
        character.applySpellBuff(spellID: "shield_of_faith", rounds: nil)
        #expect(CharacterCalculator.spellACBonus(character: character, content: store) == 7)
    }

    // MARK: - Speed buff

    @Test func longstriderAddsTenSpeed() {
        let store = ContentStore()
        var character = makeWizard()
        character.applySpellBuff(spellID: "longstrider", rounds: nil)
        #expect(CharacterCalculator.spellSpeedBonus(character: character, content: store) == 10)
    }

    // MARK: - Bless attack/save dice

    @Test func blessProducesAOneD4Group() {
        let store = ContentStore()
        var character = makeWizard()
        character.applySpellBuff(spellID: "bless", rounds: nil)
        let groups = CharacterCalculator.attackSaveBuffDiceGroups(character: character, content: store)
        #expect(groups.count == 1)
        #expect(groups.first?.kind == .d4)
        #expect(groups.first?.count == 1)
    }

    // MARK: - Lifecycle

    @Test func roundLimitedBuffDropsAtZero() {
        var character = makeWizard()
        character.applySpellBuff(spellID: "shield", rounds: 1)
        #expect(character.activeEffects.contains { $0.effectID == "spellbuff_shield" })
        character.startNewTurn()  // 1 → 0, removed
        #expect(!character.activeEffects.contains { $0.effectID == "spellbuff_shield" })
    }

    @Test func concentrationBuffDropsWhenConcentrationEnds() {
        var character = makeWizard()
        character.startConcentrating(on: "shield_of_faith")
        character.applySpellBuff(spellID: "shield_of_faith", rounds: nil)
        #expect(character.activeEffects.contains { $0.effectID == "spellbuff_shield_of_faith" })
        character.stopConcentrating()
        #expect(!character.activeEffects.contains { $0.effectID == "spellbuff_shield_of_faith" })
    }

    @Test func recastingBuffDoesNotStackDuplicates() {
        var character = makeWizard()
        character.applySpellBuff(spellID: "shield_of_faith", rounds: nil)
        character.applySpellBuff(spellID: "shield_of_faith", rounds: nil)
        let count = character.activeEffects.filter { $0.effectID == "spellbuff_shield_of_faith" }.count
        #expect(count == 1)
    }
}
