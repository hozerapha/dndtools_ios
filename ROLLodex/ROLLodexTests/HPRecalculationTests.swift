import Testing
@testable import ROLLodex

struct HPRecalculationTests {

    // MARK: - Migration

    @Test func oldCharacterWithoutRolledHPMigratesCorrectly() throws {
        let id = UUID().uuidString
        let json = """
        {
          "id": "\(id)",
          "name": "OldFighter", "level": 3,
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 3 }],
          "abilityScores": { "constitution": 14 },
          "maxHP": 36, "currentHP": 36, "tempHP": 0,
          "proficiencies": {}, "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        // CON 14 = +2.  Level 3.  maxHP 36 → rolledHP = 36 - (3 * 2) = 30
        #expect(character.rolledHP == 30)
        #expect(character.maxHP == 36)
    }

    @Test func newCharacterWithRolledHPLoadsCorrectly() throws {
        let id = UUID().uuidString
        let json = """
        {
          "id": "\(id)",
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

    // MARK: - recalculateHP()

    @Test func conIncreaseRetroactivelyHeals() {
        var character = Character(
            name: "Test",
            level: 3,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.constitution: 14],  // +2
            maxHP: 36,                          // 30 rolled + 3*2
            currentHP: 30                        // took 6 damage
        )
        #expect(character.rolledHP == 30)
        #expect(character.maxHP == 36)
        #expect(character.currentHP == 30)

        // ASI bumps CON 14 → 16 (+2 → +3)
        character.abilityScores[.constitution] = 16
        character.recalculateHP()

        // New max = 30 + (3 * 3) = 39.  Delta = +3.
        #expect(character.maxHP == 39)
        #expect(character.currentHP == 33)  // healed by the delta
    }

    @Test func conDecreaseCapsCurrentHP() {
        var character = Character(
            name: "Test",
            level: 3,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.constitution: 16],  // +3
            maxHP: 39,
            currentHP: 39
        )
        #expect(character.rolledHP == 30)

        // CON drain 16 → 14 (+3 → +2)
        character.abilityScores[.constitution] = 14
        character.recalculateHP()

        // New max = 30 + (3 * 2) = 36.  Delta = -3.
        #expect(character.maxHP == 36)
        #expect(character.currentHP == 36)  // clamped to new max
    }

    @Test func conDecreaseNeverKills() {
        var character = Character(
            name: "Test",
            level: 3,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.constitution: 20],  // +5
            maxHP: 45,
            currentHP: 1  // barely alive
        )

        // Brutal CON drain 20 → 8 (-5 → -1)
        character.abilityScores[.constitution] = 8
        character.recalculateHP()

        // New max = 30 + (3 * -1) = 27.  Delta = -18.
        #expect(character.maxHP == 27)
        #expect(character.currentHP == 1)  // never drops below 1
    }

    // MARK: - applyLevelUp with rolledHP

    @Test func levelUpAddsToRolledHPAndRecalculates() {
        var character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.constitution: 14],  // +2
            maxHP: 12,                          // 10 + 2
            currentHP: 12
        )
        #expect(character.rolledHP == 10)

        // Level up: rolled a 6 on d10
        CharacterCalculator.applyLevelUp(to: &character, hpGain: 6, classID: "fighter")

        #expect(character.level == 2)
        #expect(character.rolledHP == 16)          // 10 + 6
        #expect(character.maxHP == 20)             // 16 + (2 * 2)
        #expect(character.currentHP == 20)       // healed to full on level up
    }

    @Test func levelUpWithAverageRecalculatesCorrectly() {
        var character = Character(
            name: "Test",
            level: 2,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 2)],
            abilityScores: [.constitution: 12],  // +1
            maxHP: 13,                          // rolledHP 11 + 2*1
            currentHP: 10
        )
        #expect(character.rolledHP == 11)

        // Average for d10 = 6 (10/2 + 1)
        let avg = CharacterCalculator.averageLevelUpHPGain(hitDie: 10)
        #expect(avg == 6)

        CharacterCalculator.applyLevelUp(to: &character, hpGain: avg, classID: "fighter")

        #expect(character.level == 3)
        #expect(character.rolledHP == 17)          // 11 + 6
        #expect(character.maxHP == 20)             // 17 + (3 * 1)
        #expect(character.currentHP == 16)         // 10 + 6 (die) + 1 (new CON level) = 17, but min(17,20)=17... wait
        // Actually: old max = 13, new max = 20, delta = 7
        // currentHP = 10 + 7 = 17? Wait, let me recalculate:
        // rolledHP was 11, add 6 = 17
        // new max = 17 + 3*1 = 20
        // old max = 11 + 2*1 = 13
        // delta = 7
        // currentHP = 10 + 7 = 17
        #expect(character.currentHP == 17)
    }
}
