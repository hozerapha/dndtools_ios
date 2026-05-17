import Testing
import Foundation
@testable import ROLLodex

// MARK: - DiceRoller override logic

struct StrokeOfLuckRollerTests {

    /// Helper that mimics the override logic in DiceRollerView.applyStrokeOfLuck.
    private func overrideD20To20(formula: DiceFormula, values: [Int]) -> [Int] {
        var overridden = values
        var cursor = 0
        for group in formula.groups {
            let endIndex = min(cursor + group.count, overridden.count)
            if group.kind == .d20 {
                for i in cursor..<endIndex {
                    overridden[i] = 20
                }
                break
            }
            cursor += group.count
        }
        return overridden
    }

    @Test func plainD20Becomes20() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.modifier = 5

        let original = DiceRoller().resultFrom(formula: formula, values: [3])
        #expect(original.total == 8)

        let overridden = overrideD20To20(formula: formula, values: [3])
        let result = DiceRoller().resultFrom(formula: formula, values: overridden)
        #expect(result.dieRolls[0].value == 20)
        #expect(result.total == 25)
    }

    @Test func advantageBothDiceBecome20() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 2, modifier: .keepHighest(1)))
        formula.modifier = 3

        let overridden = overrideD20To20(formula: formula, values: [3, 15])
        let result = DiceRoller().resultFrom(
            formula: formula,
            values: overridden,
            mode: .advantage
        )
        #expect(result.dieRolls[0].value == 20)
        #expect(result.dieRolls[1].value == 20)
        // Both are 20; kh1 keeps one, drops the other.
        let kept = result.dieRolls.filter(\.isKept)
        #expect(kept.count == 1)
        #expect(kept[0].value == 20)
        #expect(result.total == 23)
    }

    @Test func disadvantageBothDiceBecome20() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 2, modifier: .keepLowest(1)))
        formula.modifier = 3

        let overridden = overrideD20To20(formula: formula, values: [3, 15])
        let result = DiceRoller().resultFrom(
            formula: formula,
            values: overridden,
            mode: .disadvantage
        )
        #expect(result.dieRolls[0].value == 20)
        #expect(result.dieRolls[1].value == 20)
        let kept = result.dieRolls.filter(\.isKept)
        #expect(kept.count == 1)
        #expect(kept[0].value == 20)
        #expect(result.total == 23)
    }

    @Test func mixedRollOnlyD20Overridden() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.groups.append(DiceGroup(kind: .d6, count: 2))
        formula.modifier = 2

        let overridden = overrideD20To20(formula: formula, values: [3, 4, 5])
        let result = DiceRoller().resultFrom(formula: formula, values: overridden)
        #expect(result.dieRolls[0].value == 20) // d20 forced
        #expect(result.dieRolls[1].value == 4)  // d6 unchanged
        #expect(result.dieRolls[2].value == 5)  // d6 unchanged
        #expect(result.total == 31)
    }

    @Test func onlyFirstD20GroupOverridden() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.modifier = 0

        let overridden = overrideD20To20(formula: formula, values: [3, 18])
        let result = DiceRoller().resultFrom(formula: formula, values: overridden)
        #expect(result.dieRolls[0].value == 20) // first d20 forced
        #expect(result.dieRolls[1].value == 18) // second d20 untouched
        #expect(result.total == 38)
    }
}

// MARK: - ActionDeriver filtering

@MainActor
struct StrokeOfLuckDeriverTests {

    private func makeRogue20() -> Character {
        Character(
            name: "Shadow",
            level: 20,
            speciesID: "human",
            backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 20)],
            abilityScores: [
                .dexterity: 20,
                .intelligence: 14
            ],
            maxHP: 120,
            proficiencies: [
                .savingThrow(.dexterity): .proficient,
                .savingThrow(.intelligence): .proficient,
                .skill(.stealth): .expertise,
                .skill(.sleightOfHand): .expertise,
                .skill(.acrobatics): .proficient,
                .skill(.perception): .proficient,
                .skill(.investigation): .proficient,
                .skill(.insight): .proficient,
                .skill(.deception): .proficient,
                .skill(.persuasion): .proficient,
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ],
            featureSelections: [
                "rogue_subclass": ["thief"]
            ]
        )
    }

    @Test func actionGridOmitsStrokeOfLuck() {
        let store = ContentStore()
        let character = makeRogue20()
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        let allRows = sections.flatMap(\.rows)
        let ids = allRows.map(\.id)
        #expect(!ids.contains(where: { $0.contains("stroke_of_luck") }))
    }

    @Test func rogue20HasStrokeOfLuckResource() {
        let store = ContentStore()
        let character = makeRogue20()
        let resources = ResourceCalculator.availableResources(
            character: character,
            content: store
        )
        let sol = resources.first { $0.definition.id == "rogue_stroke_of_luck" }
        #expect(sol != nil)
        #expect(sol?.max == 1)
        #expect(sol?.current == 1)
    }
}
