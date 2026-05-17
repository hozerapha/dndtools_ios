import Testing
import Foundation
@testable import ROLLodex

struct MinimumValueTests {

    // MARK: - DiceGroup schema

    @Test func diceGroupRoundTripsWithMinimumValue() throws {
        let group = DiceGroup(kind: .d20, count: 1, minimumValue: 10)
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(DiceGroup.self, from: data)
        #expect(decoded.minimumValue == 10)
        #expect(decoded.kind == .d20)
    }

    @Test func diceGroupDecodesLegacyJSONWithoutMinimumValue() throws {
        // Pre-minimumValue JSON must keep decoding cleanly.
        let json = """
        { "id": "00000000-0000-0000-0000-000000000001", "kind": 20, "count": 1 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DiceGroup.self, from: json)
        #expect(decoded.minimumValue == nil)
        #expect(decoded.kind == .d20)
    }

    @Test func diceGroupDisplayStringIncludesMinSuffix() {
        let group = DiceGroup(kind: .d20, count: 1, minimumValue: 10)
        #expect(group.displayString == "1d20min10")
    }

    @Test func diceGroupDisplayStringOmitsMinWhenNil() {
        let group = DiceGroup(kind: .d20, count: 1)
        #expect(group.displayString == "1d20")
    }

    @Test func diceGroupEqualityIncludesMinimumValue() {
        let a = DiceGroup(kind: .d20, count: 1, minimumValue: 10)
        let b = DiceGroup(kind: .d20, count: 1, minimumValue: 10)
        let c = DiceGroup(kind: .d20, count: 1, minimumValue: 5)
        let d = DiceGroup(kind: .d20, count: 1)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    // MARK: - Parser

    @Test func parserReadsMinSuffix() throws {
        let formula = try DiceFormulaParser().parse("1d20min10")
        #expect(formula.groups.count == 1)
        #expect(formula.groups[0].kind == .d20)
        #expect(formula.groups[0].minimumValue == 10)
    }

    @Test func parserRoundTripsMinSuffix() throws {
        let original = try DiceFormulaParser().parse("1d20min10+3")
        #expect(original.displayString == "1d20min10 + 3")
        let reparsed = try DiceFormulaParser().parse(original.displayString)
        #expect(reparsed.groups[0].minimumValue == 10)
        #expect(reparsed.modifier == 3)
    }

    @Test func parserRejectsMinGreaterThanDieSize() {
        #expect(throws: DiceFormulaParser.ParseError.invalidMinimum("1d6min8")) {
            try DiceFormulaParser().parse("1d6min8")
        }
    }

    @Test func parserRejectsMinZero() {
        #expect(throws: DiceFormulaParser.ParseError.invalidMinimum("1d20min0")) {
            try DiceFormulaParser().parse("1d20min0")
        }
    }

    // MARK: - Roller

    @Test func rollerFloorsSingleDieBelowMinimum() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        // Simulate a roll by building a result with a predetermined low value.
        let result = DiceRoller().resultFrom(formula: formula, values: [3])
        #expect(result.dieRolls[0].value == 10)
        #expect(result.total == 10)
    }

    @Test func rollerLeavesHighDieUnchanged() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        let result = DiceRoller().resultFrom(formula: formula, values: [15])
        #expect(result.dieRolls[0].value == 15)
        #expect(result.total == 15)
    }

    @Test func rollerFloorsAdvantageDiceBeforeKeep() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        // adv: roll 3 and 15 → floor 3 to 10, keep 15.
        let result = DiceRoller().resultFrom(
            formula: formula,
            values: [3, 15],
            mode: .advantage
        )
        #expect(result.dieRolls[0].value == 10) // floored
        #expect(result.dieRolls[0].isKept == false) // 10 < 15
        #expect(result.dieRolls[1].value == 15)
        #expect(result.dieRolls[1].isKept == true)
        #expect(result.total == 15)
    }

    @Test func rollerFloorsDisadvantageDiceBeforeKeep() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        // dis: roll 3 and 15 → floor 3 to 10, keep 10 (lower of 10 and 15).
        let result = DiceRoller().resultFrom(
            formula: formula,
            values: [3, 15],
            mode: .disadvantage
        )
        #expect(result.dieRolls[0].value == 10) // floored
        #expect(result.dieRolls[0].isKept == true) // 10 < 15
        #expect(result.dieRolls[1].value == 15)
        #expect(result.dieRolls[1].isKept == false)
        #expect(result.total == 10)
    }

    @Test func rollerFloorsMultipleDiceInGroup() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 3, minimumValue: 4))
        let result = DiceRoller().resultFrom(formula: formula, values: [2, 4, 6])
        #expect(result.dieRolls[0].value == 4)
        #expect(result.dieRolls[1].value == 4)
        #expect(result.dieRolls[2].value == 6)
        #expect(result.total == 14)
    }

    @Test func rollerAppliesMinimumAfterReroll() {
        // A d6 with reroll-on-1 and min 4: if it rolls 1, reroll → say 2 → floor to 4.
        // We can't easily test the random path, but resultFrom tests the deterministic path.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 1, modifier: .rerollOnceIfAtMost(1), minimumValue: 4))
        let result = DiceRoller().resultFrom(formula: formula, values: [2])
        #expect(result.dieRolls[0].value == 4)
    }

    // MARK: - ActionInterpreter / Reliable Talent

    @Test func reliableTalentSetsMinimumValueOnSkillCheck() {
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character,
            weapon: nil
        )
        #expect(resolved.formula?.groups.first?.minimumValue == 10)
    }

    @Test func noReliableTalentWithoutProficiency() {
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.strength: 10],
            maxHP: 10,
            proficiencies: [:]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .athletics),
            character: character,
            weapon: nil
        )
        #expect(resolved.formula?.groups.first?.minimumValue == nil)
    }

    @Test func noReliableTalentBelowRogue7() {
        let character = Character(
            name: "Lazlo", level: 6,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 6)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character,
            weapon: nil
        )
        #expect(resolved.formula?.groups.first?.minimumValue == nil)
    }
}
