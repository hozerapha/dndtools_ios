import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct ResourceTests {

    // MARK: - LevelScaledValue

    @Test func levelScaledValueDecodesFlatInt() throws {
        let value = try JSONDecoder().decode(LevelScaledValue.self, from: Data("5".utf8))
        #expect(value == .flat(5))
        #expect(value.value(classLevel: 1, characterLevel: 1) == 5)
        #expect(value.value(classLevel: 20, characterLevel: 20) == 5)
    }

    @Test func levelScaledValueDecodesByClassLevel() throws {
        let json = """
        { "byClassLevel": { "1": 2, "4": 3, "10": 4 } }
        """.data(using: .utf8)!
        let value = try JSONDecoder().decode(LevelScaledValue.self, from: json)
        // Sparse table: take highest key ≤ class level.
        #expect(value.value(classLevel: 1,  characterLevel: 1) == 2)
        #expect(value.value(classLevel: 3,  characterLevel: 3) == 2)  // still in the L1-3 band
        #expect(value.value(classLevel: 4,  characterLevel: 4) == 3)
        #expect(value.value(classLevel: 9,  characterLevel: 9) == 3)
        #expect(value.value(classLevel: 10, characterLevel: 10) == 4)
        #expect(value.value(classLevel: 20, characterLevel: 20) == 4)
    }

    @Test func levelScaledValueRoundTrips() throws {
        let original = LevelScaledValue.byClassLevel([1: 2, 4: 3, 10: 4])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LevelScaledValue.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - RefreshAmount

    @Test func refreshAmountDecodesAll() throws {
        let value = try JSONDecoder().decode(RefreshAmount.self, from: Data("\"all\"".utf8))
        #expect(value == .all)
    }

    @Test func refreshAmountDecodesFixed() throws {
        let json = "{ \"fixed\": 1 }".data(using: .utf8)!
        let value = try JSONDecoder().decode(RefreshAmount.self, from: json)
        #expect(value == .fixed(1))
    }

    @Test func refreshAmountDecodesRoll() throws {
        let json = "{ \"roll\": \"1d6+1\" }".data(using: .utf8)!
        let value = try JSONDecoder().decode(RefreshAmount.self, from: json)
        #expect(value == .roll(formula: "1d6+1"))
    }

    @Test func refreshAmountRoundTrips() throws {
        for amount: RefreshAmount in [.all, .fixed(2), .roll(formula: "1d6"), .byClassLevel([1: 1, 5: 2])] {
            let data = try JSONEncoder().encode(amount)
            let decoded = try JSONDecoder().decode(RefreshAmount.self, from: data)
            #expect(decoded == amount)
        }
    }

    // MARK: - RefreshTrigger.fires(on:)

    @Test func shortRestFiresOnBothRests() {
        // Per 5e: a long rest counts as a short rest for refresh purposes.
        #expect(RefreshTrigger.shortRest.fires(on: .short))
        #expect(RefreshTrigger.shortRest.fires(on: .long))
    }

    @Test func longRestOnlyFiresOnLongRest() {
        #expect(!RefreshTrigger.longRest.fires(on: .short))
        #expect(RefreshTrigger.longRest.fires(on: .long))
    }

    @Test func dawnFoldsIntoLongRest() {
        // MVP simplification: dawn refreshes happen at long rest until we add
        // an explicit "advance time" flow.
        #expect(!RefreshTrigger.dawn.fires(on: .short))
        #expect(RefreshTrigger.dawn.fires(on: .long))
    }

    @Test func neverNeverFires() {
        #expect(!RefreshTrigger.never.fires(on: .short))
        #expect(!RefreshTrigger.never.fires(on: .long))
    }

    // MARK: - ResourceCalculator

    private func makeFighter(level: Int = 1) -> Character {
        Character(
            name: "Bruenor", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: level)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 12, currentHP: 12
        )
    }

    @Test func availableResourcesIncludesSecondWindForFighter() {
        let store = ContentStore()
        let character = makeFighter()
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let secondWind = resources.first { $0.definition.id == "fighter_second_wind" }
        #expect(secondWind != nil)
        #expect(secondWind?.max == 2) // L1 fighter
        #expect(secondWind?.current == 2) // unset state defaults to full
    }

    @Test func availableResourcesScalesSecondWindByLevel() {
        let store = ContentStore()
        let character = makeFighter(level: 4)
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let secondWind = resources.first { $0.definition.id == "fighter_second_wind" }
        #expect(secondWind?.max == 3) // L4 fighter bumps to 3
    }

    @Test func consumeReducesCurrent() {
        let store = ContentStore()
        var character = makeFighter()
        let ok = ResourceCalculator.consume(
            amount: 1, from: "fighter_second_wind",
            in: &character, content: store
        )
        #expect(ok == true)
        #expect(character.resources["fighter_second_wind"]?.current == 1)
    }

    @Test func consumeRefusesWhenExhausted() {
        let store = ContentStore()
        var character = makeFighter()
        // Drain to zero.
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        // Third attempt should fail and not mutate.
        let ok = ResourceCalculator.consume(
            amount: 1, from: "fighter_second_wind",
            in: &character, content: store
        )
        #expect(ok == false)
        #expect(character.resources["fighter_second_wind"]?.current == 0)
    }

    @Test func shortRestRefreshesSecondWindByOne() {
        let store = ContentStore()
        var character = makeFighter()
        // Drain both charges.
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        #expect(character.resources["fighter_second_wind"]?.current == 0)
        // Short rest restores 1.
        let pending = ResourceCalculator.applyRest(.short, to: &character, content: store)
        #expect(pending.isEmpty)
        #expect(character.resources["fighter_second_wind"]?.current == 1)
    }

    @Test func longRestRefreshesSecondWindToMax() {
        let store = ContentStore()
        var character = makeFighter()
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        _ = ResourceCalculator.consume(amount: 1, from: "fighter_second_wind", in: &character, content: store)
        let pending = ResourceCalculator.applyRest(.long, to: &character, content: store)
        // 5e RAW: a long rest fully restores anything refreshable, regardless
        // of the per-short-rest bump amount.
        #expect(pending.isEmpty)
        #expect(character.resources["fighter_second_wind"]?.current == 2)
    }

    @Test func longRestHealsHPToMax() {
        let store = ContentStore()
        var character = makeFighter()
        character.currentHP = 3
        character.tempHP = 4
        _ = ResourceCalculator.applyRest(.long, to: &character, content: store)
        #expect(character.currentHP == character.maxHP)
        #expect(character.tempHP == 0)
    }

    @Test func setCurrentClampsToBounds() {
        let store = ContentStore()
        var character = makeFighter()
        ResourceCalculator.setCurrent(99, for: "fighter_second_wind", in: &character, content: store)
        #expect(character.resources["fighter_second_wind"]?.current == 2) // clamped to max

        ResourceCalculator.setCurrent(-5, for: "fighter_second_wind", in: &character, content: store)
        #expect(character.resources["fighter_second_wind"]?.current == 0) // clamped to 0
    }

    // MARK: - Character backwards-compat

    @Test func characterDecodesWithoutResourcesField() throws {
        // Pre-Phase-I character JSON has no `resources` key. Should decode
        // with an empty resources map.
        let id = UUID().uuidString
        let json = """
        {
          "id": "\(id)",
          "name": "Old Save",
          "level": 1,
          "speciesID": "human",
          "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "strength": 16, "dexterity": 12, "constitution": 14, "intelligence": 10, "wisdom": 13, "charisma": 8 },
          "maxHP": 12,
          "currentHP": 12,
          "tempHP": 0,
          "proficiencies": {},
          "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        #expect(character.resources.isEmpty)
    }
}
