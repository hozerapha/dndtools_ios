import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct LevelUpTests {

    // MARK: - HP gain math

    @Test func averageHPGainFollowsPHB() {
        // Fighter d10, CON +2 → 6 + 2 = 8.
        #expect(CharacterCalculator.averageLevelUpHPGain(hitDie: 10, conMod: 2) == 8)
        // Wizard d6, CON 0 → 4.
        #expect(CharacterCalculator.averageLevelUpHPGain(hitDie: 6, conMod: 0) == 4)
        // Cleric d8, CON +3 → 5 + 3 = 8.
        #expect(CharacterCalculator.averageLevelUpHPGain(hitDie: 8, conMod: 3) == 8)
        // d12 (Barbarian), CON +5 → 7 + 5 = 12.
        #expect(CharacterCalculator.averageLevelUpHPGain(hitDie: 12, conMod: 5) == 12)
    }

    @Test func averageHPGainCanGoNegativeBeforeClamp() {
        // d6, CON -5 → 4 - 5 = -1. The raw math is allowed to dip; the
        // commit path clamps it.
        #expect(CharacterCalculator.averageLevelUpHPGain(hitDie: 6, conMod: -5) == -1)
    }

    @Test func clampedHPGainFloorsAtOne() {
        #expect(CharacterCalculator.clampedLevelUpHPGain(0) == 1)
        #expect(CharacterCalculator.clampedLevelUpHPGain(-3) == 1)
        #expect(CharacterCalculator.clampedLevelUpHPGain(1) == 1)
        #expect(CharacterCalculator.clampedLevelUpHPGain(7) == 7)
    }

    // MARK: - applyLevelUp
    //
    // `hpGain` is the DIE-ONLY value (roll or die average) — the CON share
    // is layered on retroactively by `recalculateHP()`. The fighter fixture
    // has CON 14 (+2), so each level contributes die + 2 to max HP.

    @Test func applyLevelUpBumpsLevelMaxAndCurrentHP() {
        // maxHP 12 at L1/CON +2 → rolledHP 10. Roll a 6: rolledHP 16,
        // new max = 16 + 2×2 = 20.
        var character = makeFighter(level: 1, maxHP: 12, currentHP: 12)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        #expect(character.level == 2)
        #expect(character.classEntries.first?.level == 2)
        #expect(character.maxHP == 20)
        #expect(character.currentHP == 20)
    }

    @Test func applyLevelUpRespectsHPFloor() {
        // A negative staged value still banks at least 1 die HP.
        // maxHP 6 at L1/CON +2 → rolledHP 4. Clamped gain 1 → rolledHP 5,
        // new max = 5 + 2×2 = 9.
        var character = makeFighter(level: 1, maxHP: 6, currentHP: 6)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: -3, classID: "fighter")
        #expect(character.maxHP == 9)
        #expect(character.currentHP == 9)
    }

    @Test func applyLevelUpDoesNotOvershootCurrentHP() {
        // Player was at half HP; the level's delta (die 6 + CON 2 = 8) heals
        // by the same amount, but currentHP shouldn't exceed the new max.
        var character = makeFighter(level: 1, maxHP: 12, currentHP: 6)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        #expect(character.maxHP == 20)
        // 6 + 8 = 14, which is ≤ 20 → currentHP = 14.
        #expect(character.currentHP == 14)
    }

    @Test func applyLevelUpOnlyTouchesMatchingClassEntry() {
        // Multi-class fighter/wizard: leveling fighter shouldn't bump wizard.
        var character = Character(
            name: "Mage Warrior", level: 2,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [
                ClassEntry(classID: "fighter", level: 1),
                ClassEntry(classID: "wizard", level: 1)
            ],
            abilityScores: [.constitution: 14],
            maxHP: 16,
            currentHP: 16
        )
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 7, classID: "fighter")
        #expect(character.classEntries[0].level == 2)
        #expect(character.classEntries[1].level == 1)
        // Character level still bumps by 1.
        #expect(character.level == 3)
    }

    @Test func applyLevelUpWithNewClassIDAppendsAMulticlassEntry() {
        // A classID with no existing entry is the multiclass path: a new
        // ClassEntry is appended at level 1 and the character level bumps.
        var character = makeFighter(level: 1, maxHP: 10, currentHP: 10)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 5, classID: "ranger")
        #expect(character.level == 2)
        #expect(character.classEntries.first?.level == 1)
        #expect(character.classEntries.count == 2)
        #expect(character.classEntries.last?.classID == "ranger")
        #expect(character.classEntries.last?.level == 1)
        // maxHP 10 at L1/CON +2 → rolledHP 8; +5 die → 13; +2×2 CON = 17.
        #expect(character.maxHP == 17)
    }

    // MARK: - Level-up sheet inputs (audit #9/#10)
    //
    // The sheet's HP preview and spell-budget card are simulations over these
    // primitives — pin the level transitions the UI reports.

    @Test func druidSlotTableUnlocksAndGrowsAcrossLevels() {
        let store = ContentStore()
        let block = store.classDefinition(id: "druid")?.spellcasting
        let l1 = block?.slotTable.slots(atClassLevel: 1) ?? [:]
        let l2 = block?.slotTable.slots(atClassLevel: 2) ?? [:]
        let l3 = block?.slotTable.slots(atClassLevel: 3) ?? [:]
        // L1→L2: same slot levels, L1 count grows 2 → 3.
        #expect(Set(l2.keys) == Set(l1.keys))
        #expect(l1[1] == 2 && l2[1] == 3)
        // L2→L3: L2 slots unlock.
        #expect(Set(l3.keys).subtracting(l2.keys) == [2])
    }

    @Test func druidCantripBudgetGrowsAtLevelFour() {
        let store = ContentStore()
        let block = store.classDefinition(id: "druid")?.spellcasting
        #expect(block?.cantripsKnown.value(classLevel: 3, characterLevel: 3) == 2)
        #expect(block?.cantripsKnown.value(classLevel: 4, characterLevel: 4) == 3)
    }

    @Test func featureHPBonusDiffMatchesLevelBumpSimulation() {
        // The sheet previews the feature-HP delta by re-computing
        // featureHitPointBonus on a level-bumped copy — a Dwarf (Dwarven
        // Toughness, +1/character level) must show +1 per level.
        let store = ContentStore()
        var dwarf = Character(
            name: "Bruenor", level: 3,
            speciesID: "dwarf", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 28
        )
        let before = CharacterCalculator.featureHitPointBonus(character: dwarf, content: store)
        dwarf.level += 1
        dwarf.classEntries[0] = ClassEntry(classID: "fighter", level: 4)
        let after = CharacterCalculator.featureHitPointBonus(character: dwarf, content: store)
        #expect(after - before == 1)
    }

    // MARK: - Helpers

    private func makeFighter(level: Int, maxHP: Int, currentHP: Int) -> Character {
        Character(
            name: "Bruenor", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: level)],
            abilityScores: [
                .strength: 16, .dexterity: 12, .constitution: 14
            ],
            maxHP: maxHP,
            currentHP: currentHP
        )
    }
}
