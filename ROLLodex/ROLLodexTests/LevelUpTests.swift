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

    @Test func applyLevelUpWithUnknownClassIDStillBumpsCharacterLevel() {
        // Edge case: classID doesn't match any entry. Character level still
        // ticks up + HP applies; the class entry just doesn't move. (UI
        // shouldn't ever call this path, but the helper shouldn't crash.)
        var character = makeFighter(level: 1, maxHP: 10, currentHP: 10)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 5, classID: "ranger")
        #expect(character.level == 2)
        #expect(character.classEntries.first?.level == 1)
        // maxHP 10 at L1/CON +2 → rolledHP 8; +5 die → 13; +2×2 CON = 17.
        #expect(character.maxHP == 17)
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
