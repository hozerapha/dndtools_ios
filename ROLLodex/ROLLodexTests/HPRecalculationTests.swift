import Testing
import Foundation
@testable import ROLLodex

/// Retroactive CON-modifier HP model: `rolledHP` stores die-only HP,
/// `maxHP = max(level, rolledHP + level × CON mod)` via `recalculateHP()`.
/// Re-land of the reverted 131da6d with its math bugs fixed (the original
/// derived rolledHP without the level multiplier and broke on level > 1).
@MainActor
struct HPRecalculationTests {

    // MARK: - Migration

    @Test func oldCharacterWithoutRolledHPMigratesCorrectly() throws {
        let character = try JSONDecoder().decode(Character.self, from: legacyJSON(
            level: 3, con: 14, maxHP: 36, currentHP: 36
        ))
        // CON 14 = +2, level 3 → rolledHP = 36 - (3 × 2) = 30.
        #expect(character.rolledHP == 30)
        #expect(character.maxHP == 36)
    }

    @Test func newCharacterWithRolledHPLoadsCorrectly() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "NewFighter", "level": 1,
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "constitution": 14 },
          "maxHP": 12, "rolledHP": 10, "currentHP": 12, "tempHP": 0,
          "proficiencies": {}, "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        #expect(character.rolledHP == 10)
        #expect(character.maxHP == 12)
    }

    @Test func legacySaveRoundTripPreservesRolledHP() throws {
        let migrated = try JSONDecoder().decode(Character.self, from: legacyJSON(
            level: 5, con: 16, maxHP: 49, currentHP: 30
        ))
        // CON +3, level 5 → rolledHP = 49 - 15 = 34.
        #expect(migrated.rolledHP == 34)
        let reencoded = try JSONEncoder().encode(migrated)
        let decoded = try JSONDecoder().decode(Character.self, from: reencoded)
        #expect(decoded.rolledHP == 34)
        #expect(decoded == migrated)
    }

    @Test func memberwiseInitDerivesRolledHPWithLevelMultiplier() {
        // The reverted attempt subtracted ONE con mod here regardless of
        // level, inflating HP on the next recalc for any level > 1.
        let character = makeCharacter(level: 3, con: 14, maxHP: 36, currentHP: 36)
        #expect(character.rolledHP == 30)
        var copy = character
        copy.recalculateHP()
        // Recalc of an untouched character must be a no-op.
        #expect(copy.maxHP == 36)
        #expect(copy.currentHP == 36)
    }

    // MARK: - recalculateHP()

    @Test func conIncreaseRetroactivelyHeals() {
        var character = makeCharacter(level: 3, con: 14, maxHP: 36, currentHP: 30)
        // ASI bumps CON 14 → 16 (+2 → +3).
        character.abilityScores[.constitution] = 16
        character.recalculateHP()
        // New max = 30 + (3 × 3) = 39, delta +3 heals the same amount.
        #expect(character.maxHP == 39)
        #expect(character.currentHP == 33)
    }

    @Test func conDecreaseCapsCurrentHP() {
        var character = makeCharacter(level: 3, con: 16, maxHP: 39, currentHP: 39)
        #expect(character.rolledHP == 30)
        // CON drain 16 → 14 (+3 → +2).
        character.abilityScores[.constitution] = 14
        character.recalculateHP()
        // New max = 30 + (3 × 2) = 36; current clamps to the new max.
        #expect(character.maxHP == 36)
        #expect(character.currentHP == 36)
    }

    @Test func conDecreaseNeverKills() {
        var character = makeCharacter(level: 3, con: 20, maxHP: 45, currentHP: 1)
        // Brutal drain 20 → 8 (+5 → -1). New max = 30 - 3 = 27, delta -18.
        character.abilityScores[.constitution] = 8
        character.recalculateHP()
        #expect(character.maxHP == 27)
        #expect(character.currentHP == 1) // floors at 1, never kills
    }

    @Test func recalcLeavesDyingCharacterAtZero() {
        var character = makeCharacter(level: 3, con: 14, maxHP: 36, currentHP: 36)
        character.currentHP = 0 // dying
        character.abilityScores[.constitution] = 16
        character.recalculateHP()
        #expect(character.maxHP == 39)
        // Recalculation never wakes the dying.
        #expect(character.currentHP == 0)
    }

    @Test func recalcFloorsMaxHPAtCharacterLevel() {
        var character = makeCharacter(
            level: 3, con: 3, maxHP: 4, currentHP: 4, rolledHP: 4
        )
        // CON 3 = -4 → raw 4 - 12 = -8; floored at level (3).
        character.recalculateHP()
        #expect(character.maxHP == 3)
        #expect(character.currentHP == 3)
    }

    // MARK: - ASI mutators recalc automatically

    @Test func asiConIncrementRecalculatesHP() {
        // L4, CON 14, maxHP 30 → rolledHP 22.
        var character = makeCharacter(level: 4, con: 14, maxHP: 30, currentHP: 30)
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        // CON 15 — modifier still +2, no HP change.
        #expect(character.maxHP == 30)
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        // CON 16 (+3): new max = 22 + 4 × 3 = 34.
        #expect(character.maxHP == 34)
        #expect(character.currentHP == 34)
    }

    @Test func asiConDecrementRecalculatesHP() {
        var character = makeCharacter(level: 4, con: 14, maxHP: 30, currentHP: 30)
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        #expect(character.maxHP == 34)
        // Un-picking one point: CON 15 (+2) → back to 30.
        character.applyASIDecrement(ability: .constitution, selectionID: "fighter_asi_4")
        #expect(character.maxHP == 30)
        #expect(character.currentHP == 30)
    }

    // MARK: - Manual max-HP edits

    @Test func setMaxHPWritesThroughRolledHPAndSurvivesRecalc() {
        var character = makeCharacter(level: 1, con: 14, maxHP: 12, currentHP: 12)
        #expect(character.rolledHP == 10)
        character.setMaxHP(15) // DM grants a +3 boon
        #expect(character.maxHP == 15)
        #expect(character.rolledHP == 13)
        // A later recalc must preserve the manual edit, not stomp it.
        character.recalculateHP()
        #expect(character.maxHP == 15)
    }

    @Test func setMaxHPClampsCurrentHP() {
        var character = makeCharacter(level: 1, con: 14, maxHP: 12, currentHP: 12)
        character.setMaxHP(8)
        #expect(character.maxHP == 8)
        #expect(character.currentHP == 8)
    }

    // MARK: - applyLevelUp banks die-only HP

    @Test func levelUpAddsToRolledHPAndRecalculates() {
        var character = makeCharacter(level: 1, con: 14, maxHP: 12, currentHP: 12)
        #expect(character.rolledHP == 10)
        // Rolled a 6 on the d10.
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        #expect(character.level == 2)
        #expect(character.rolledHP == 16)
        #expect(character.maxHP == 20)      // 16 + 2 × 2
        #expect(character.currentHP == 20)
    }

    @Test func levelUpWithAverageRecalculatesCorrectly() {
        // L2, CON 12 (+1), maxHP 13 → rolledHP 11. Took 3 damage.
        var character = makeCharacter(level: 2, con: 12, maxHP: 13, currentHP: 10)
        #expect(character.rolledHP == 11)
        // d10 average = 6 (die only — CON is layered on by the recalc).
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        #expect(character.level == 3)
        #expect(character.rolledHP == 17)
        #expect(character.maxHP == 20)      // 17 + 3 × 1
        #expect(character.currentHP == 17)  // 10 + delta 7
    }

    @Test func conChangeAfterLevelUpsAppliesToEveryLevel() {
        // The user-reported scenario end to end: level a few times, then a
        // CON bump lands, and HP rises by level × 1 per modifier step.
        var character = makeCharacter(level: 1, con: 14, maxHP: 12, currentHP: 12)
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")
        #expect(character.maxHP == 28)      // rolled 22 + 3 × 2
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        character.applyASIIncrement(
            ability: .constitution, selectionID: "fighter_asi_4",
            totalPoints: 2, perAbilityMax: 2
        )
        // CON 16 (+3): 22 + 3 × 3 = 31 — all three levels got the new mod.
        #expect(character.maxHP == 31)
    }

    // MARK: - Helpers

    private func makeCharacter(
        level: Int, con: Int, maxHP: Int, currentHP: Int, rolledHP: Int? = nil
    ) -> Character {
        Character(
            name: "Test", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: level)],
            abilityScores: [.strength: 16, .constitution: con],
            maxHP: maxHP,
            rolledHP: rolledHP,
            currentHP: currentHP
        )
    }

    private func legacyJSON(level: Int, con: Int, maxHP: Int, currentHP: Int) -> Data {
        """
        {
          "id": "\(UUID().uuidString)",
          "name": "OldFighter", "level": \(level),
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": \(level) }],
          "abilityScores": { "constitution": \(con) },
          "maxHP": \(maxHP), "currentHP": \(currentHP), "tempHP": 0,
          "proficiencies": {}, "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
    }
}
