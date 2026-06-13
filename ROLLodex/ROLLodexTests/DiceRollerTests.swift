import Testing
import Foundation
@testable import ROLLodex

/// Direct coverage of `DiceRoller` (roadmap item 10) — the one big production
/// type that had only incidental testing. `roll` is random, so it's tested
/// for invariants (ranges, counts, kept-die rules) over many iterations;
/// `resultFrom` / `rerollIndices` are deterministic and tested exactly.
struct DiceRollerTests {

    private let roller = DiceRoller()

    private func formula(_ groups: [DiceGroup], modifier: Int = 0) -> DiceFormula {
        var f = DiceFormula()
        f.groups = groups
        f.modifier = modifier
        return f
    }

    // MARK: - roll(): ranges & counts (random → invariants)

    @Test func everyDieKindRollsInRange() {
        for kind in DieKind.allCases {
            let f = formula([DiceGroup(kind: kind, count: 3)])
            for _ in 0..<200 {
                let result = roller.roll(f)
                #expect(result.dieRolls.count == 3)
                for die in result.dieRolls {
                    #expect((1...kind.sides).contains(die.value))
                }
            }
        }
    }

    @Test func totalSumsKeptDicePlusModifier() {
        let f = formula([DiceGroup(kind: .d6, count: 2)], modifier: 3)
        for _ in 0..<200 {
            let result = roller.roll(f)
            let keptSum = result.dieRolls.filter(\.isKept).map(\.value).reduce(0, +)
            #expect(result.total == keptSum + 3)
        }
    }

    @Test func d100RollsOneToHundred() {
        let f = formula([DiceGroup(kind: .d100, count: 1)])
        for _ in 0..<300 {
            let value = roller.roll(f).dieRolls.first?.value ?? 0
            #expect((1...100).contains(value))
        }
    }

    // MARK: - Advantage / disadvantage (single plain d20)

    @Test func advantageRollsTwiceAndKeepsHigher() {
        var f = DiceFormula()
        f.add(.d20)
        #expect(f.supportsAdvantage)
        for _ in 0..<300 {
            let result = roller.roll(f, mode: .advantage)
            #expect(result.dieRolls.count == 2)
            #expect(result.dieRolls.filter(\.isKept).count == 1)
            let values = result.dieRolls.map(\.value)
            let kept = result.dieRolls.first(where: \.isKept)!.value
            #expect(kept == values.max())
        }
    }

    @Test func disadvantageKeepsLower() {
        var f = DiceFormula()
        f.add(.d20)
        for _ in 0..<300 {
            let result = roller.roll(f, mode: .disadvantage)
            #expect(result.dieRolls.count == 2)
            let kept = result.dieRolls.first(where: \.isKept)!.value
            #expect(kept == result.dieRolls.map(\.value).min())
        }
    }

    @Test func normalModeRollsSingleD20() {
        var f = DiceFormula()
        f.add(.d20)
        let result = roller.roll(f, mode: .normal)
        #expect(result.dieRolls.count == 1)
        #expect(result.dieRolls.first?.isKept == true)
    }

    @Test func advantageIgnoredWhenFormulaDoesNotSupportIt() {
        // Two groups → not a lone d20, so adv/dis must not double anything.
        let f = formula([DiceGroup(kind: .d20, count: 1), DiceGroup(kind: .d6, count: 1)])
        #expect(!f.supportsAdvantage)
        let result = roller.roll(f, mode: .advantage)
        #expect(result.dieRolls.count == 2) // 1 d20 + 1 d6, no doubling
    }

    // MARK: - keep / drop (deterministic via resultFrom)

    @Test func keepHighestKeepsTopN() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .keepHighest(3))])
        let result = roller.resultFrom(formula: f, values: [5, 2, 8, 1])
        let kept = result.dieRolls.filter(\.isKept).map(\.value).sorted()
        #expect(kept == [2, 5, 8])
        #expect(result.total == 15)
    }

    @Test func keepLowestKeepsBottomN() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .keepLowest(1))])
        let result = roller.resultFrom(formula: f, values: [5, 2, 8, 1])
        #expect(result.dieRolls.filter(\.isKept).map(\.value) == [1])
        #expect(result.total == 1)
    }

    @Test func dropHighestRemovesTopN() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .dropHighest(1))])
        let result = roller.resultFrom(formula: f, values: [5, 2, 8, 1])
        #expect(result.total == 8) // 5 + 2 + 1, the 8 dropped
        #expect(result.dieRolls.filter { !$0.isKept }.map(\.value) == [8])
    }

    @Test func dropLowestRemovesBottomN() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .dropLowest(1))])
        let result = roller.resultFrom(formula: f, values: [5, 2, 8, 1])
        #expect(result.total == 15) // 5 + 2 + 8, the 1 dropped
    }

    // MARK: - rerollIndices (deterministic physics-path helper)

    @Test func rerollIndicesFlagsValuesAtOrBelowThreshold() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .rerollOnceIfAtMost(1))])
        #expect(roller.rerollIndices(formula: f, values: [1, 3, 1, 6]) == [0, 2])
    }

    @Test func rerollIndicesRespectGroupOffset() {
        // A leading group shifts the flat indices of the reroll group.
        let f = formula([
            DiceGroup(kind: .d20, count: 1),
            DiceGroup(kind: .d6, count: 4, modifier: .rerollOnceIfAtMost(2))
        ])
        #expect(roller.rerollIndices(formula: f, values: [15, 2, 5, 1, 6]) == [1, 3])
    }

    @Test func rerollIndicesEmptyWithoutRerollModifier() {
        let f = formula([DiceGroup(kind: .d6, count: 4)])
        #expect(roller.rerollIndices(formula: f, values: [1, 1, 1, 1]).isEmpty)
    }

    // MARK: - minimumValue floor

    @Test func resultFromFloorsValuesBelowMinimum() {
        let f = formula([DiceGroup(kind: .d20, count: 1, minimumValue: 10)])
        #expect(roller.resultFrom(formula: f, values: [3]).total == 10)
        #expect(roller.resultFrom(formula: f, values: [14]).total == 14)
    }

    @Test func rollAlwaysHonorsMinimumFloor() {
        // Statistical: a floored d20 never reads below the floor, ever.
        let f = formula([DiceGroup(kind: .d20, count: 1, minimumValue: 10)])
        for _ in 0..<500 {
            #expect(roller.roll(f).dieRolls[0].value >= 10)
        }
    }

    @Test func floorAppliesAfterKeepDrop() {
        // keepHighest picks by raw value, then each kept die is floored.
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .keepHighest(2), minimumValue: 4)])
        let result = roller.resultFrom(formula: f, values: [1, 2, 6])
        // Keeps the 6 and the 2 (top two raw); the 2 floors to 4 → 6 + 4 = 10.
        #expect(result.total == 10)
    }

    // MARK: - resultFrom: multi-group, modifier, mode, crits

    @Test func resultFromMapsValuesAcrossGroupsInOrder() {
        let f = formula([
            DiceGroup(kind: .d8, count: 1),
            DiceGroup(kind: .d6, count: 2)
        ], modifier: 2)
        let result = roller.resultFrom(formula: f, values: [7, 3, 5])
        #expect(result.dieRolls.map(\.value) == [7, 3, 5])
        #expect(result.total == 17) // 7 + 3 + 5 + 2
    }

    @Test func resultFromPreservesMode() {
        let f = formula([DiceGroup(kind: .d20, count: 1)])
        #expect(roller.resultFrom(formula: f, values: [12], mode: .advantage).mode == .advantage)
    }

    @Test func critDetectionRespectsKeptDiceOnly() {
        let nat20 = formula([DiceGroup(kind: .d20, count: 1)])
        #expect(roller.resultFrom(formula: nat20, values: [20]).hasCriticalSuccess)
        #expect(roller.resultFrom(formula: nat20, values: [1]).hasCriticalFail)

        // A nat 20 that gets DROPPED (disadvantage keeps the lower) isn't a crit.
        let dropped = formula([DiceGroup(kind: .d20, count: 2, modifier: .keepLowest(1))])
        let result = roller.resultFrom(formula: dropped, values: [20, 5])
        #expect(!result.hasCriticalSuccess)
        #expect(result.total == 5)
    }
}
