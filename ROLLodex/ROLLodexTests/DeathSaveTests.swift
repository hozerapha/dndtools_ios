import Testing
import Foundation
@testable import ROLLodex

/// Death saves (Phase G follow-up): 3 successes → stable, 3 failures → dead.
/// Counters persist on the character, auto-reset on regaining any HP, and
/// damage taken while already at 0 HP auto-records a failure.
@MainActor
struct DeathSaveTests {

    // MARK: - Defaults & persistence

    @Test func newCharacterStartsWithCleanTally() {
        let character = makeFighter()
        #expect(character.deathSaves.successes == 0)
        #expect(character.deathSaves.failures == 0)
        #expect(character.deathSaves.isEmpty)
    }

    @Test func legacyJSONDecodesWithEmptyTally() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Old", "level": 1,
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "constitution": 14 },
          "maxHP": 12, "currentHP": 0, "tempHP": 0,
          "proficiencies": {}, "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        #expect(character.deathSaves.isEmpty)
        // Decoding must not trigger the heal-reset observer or coerce HP.
        #expect(character.currentHP == 0)
    }

    @Test func tallyRoundTripsAndOmitsKeyWhenEmpty() throws {
        var dying = makeFighter()
        dying.currentHP = 0
        dying.deathSaves.successes = 2
        dying.deathSaves.failures = 1

        let data = try JSONEncoder().encode(dying)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.deathSaves.successes == 2)
        #expect(decoded.deathSaves.failures == 1)

        // A clean tally shouldn't bloat every save file with the key.
        let healthy = makeFighter()
        let healthyJSON = String(data: try JSONEncoder().encode(healthy), encoding: .utf8) ?? ""
        #expect(!healthyJSON.contains("deathSaves"))
    }

    // MARK: - Damage interaction

    @Test func damageWhileDyingRecordsFailure() {
        var character = makeFighter()
        character.currentHP = 0
        _ = character.applyDamage(5)
        #expect(character.deathSaves.failures == 1)
        #expect(character.deathSaves.successes == 0)
    }

    @Test func damageDroppingToZeroDoesNotRecordFailure() {
        var character = makeFighter()
        _ = character.applyDamage(99)
        #expect(character.currentHP == 0)
        #expect(character.deathSaves.failures == 0)
    }

    @Test func tempHPAbsorbingEverythingDoesNotRecordFailure() {
        var character = makeFighter()
        character.currentHP = 0
        character.tempHP = 10
        _ = character.applyDamage(5)
        #expect(character.deathSaves.failures == 0)
        #expect(character.tempHP == 5)
    }

    @Test func failuresCapAtThree() {
        var character = makeFighter()
        character.currentHP = 0
        for _ in 0..<5 { _ = character.applyDamage(1) }
        #expect(character.deathSaves.failures == 3)
        #expect(character.deathSaves.isDead)
    }

    // MARK: - Healing resets

    @Test func regainingHPResetsTally() {
        var character = makeFighter()
        character.currentHP = 0
        character.deathSaves.successes = 2
        character.deathSaves.failures = 2
        // Nat 20 / healing word: any HP regained ends the dying state.
        character.currentHP = 1
        #expect(character.deathSaves.isEmpty)
    }

    @Test func damageAtPositiveHPDoesNotTouchTally() {
        var character = makeFighter()
        _ = character.applyDamage(3)
        #expect(character.currentHP == 9)
        #expect(character.deathSaves.isEmpty)
    }

    // MARK: - Rolled-save auto-tally (Quick Roll path)

    @Test func rolledSaveOutcomesFollowFiveE() {
        var character = makeFighter()
        character.currentHP = 0

        character.applyDeathSaveRoll(10) // success at exactly 10
        #expect(character.deathSaves.successes == 1)

        character.applyDeathSaveRoll(9)  // failure below 10
        #expect(character.deathSaves.failures == 1)

        character.applyDeathSaveRoll(1)  // nat 1 counts twice
        #expect(character.deathSaves.failures == 3)
        #expect(character.deathSaves.isDead)
    }

    @Test func rolledNatTwentyRegainsOneHPAndClearsTally() {
        var character = makeFighter()
        character.currentHP = 0
        character.deathSaves.successes = 2
        character.deathSaves.failures = 1

        character.applyDeathSaveRoll(20)
        #expect(character.currentHP == 1)
        #expect(character.deathSaves.isEmpty)
    }

    @Test func rolledSaveIsNoOpWhenNotDying() {
        var character = makeFighter()
        character.applyDeathSaveRoll(1)
        #expect(character.deathSaves.isEmpty)
        #expect(character.currentHP == 12)
    }

    // MARK: - Thresholds

    @Test func stableAndDeadThresholds() {
        var state = DeathSaveState()
        #expect(!state.isStable && !state.isDead)
        state.recordSuccess()
        state.recordSuccess()
        state.recordSuccess()
        #expect(state.isStable)
        state.recordSuccess()
        #expect(state.successes == 3) // clamped

        var failing = DeathSaveState()
        failing.recordFailure()
        failing.recordFailure()
        #expect(!failing.isDead)
        failing.recordFailure()
        #expect(failing.isDead)
    }

    // MARK: - Helpers

    private func makeFighter() -> Character {
        Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 12,
            currentHP: 12
        )
    }
}
