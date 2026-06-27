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

    // MARK: - rerollOnceIfAtMost

    @Test func rerollGroupKeepsAllDiceInResultFrom() {
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .rerollOnceIfAtMost(2))])
        let result = roller.resultFrom(formula: f, values: [1, 3, 2])

        #expect(result.dieRolls.allSatisfy(\.isKept))
        #expect(result.total == 6)
    }

    @Test func rerollRollsRespectMinimumFloor() {
        // A reroll modifier plus a floor should never surface a value below the floor.
        let f = formula([DiceGroup(kind: .d6, count: 5, modifier: .rerollOnceIfAtMost(1), minimumValue: 3)])
        for _ in 0..<200 {
            let result = roller.roll(f)
            #expect(result.dieRolls.allSatisfy { (3...6).contains($0.value) })
            #expect(result.dieRolls.allSatisfy(\.isKept))
        }
    }

    // MARK: - d100 compound behavior

    @Test func d100RollsOneToHundredAsSingleDie() {
        let f = formula([DiceGroup(kind: .d100, count: 1)])
        for _ in 0..<200 {
            let value = roller.roll(f).dieRolls.first?.value ?? 0
            #expect((1...100).contains(value))
        }
    }

    @Test func d100RespectsKeepDrop() {
        let f = formula([DiceGroup(kind: .d100, count: 3, modifier: .keepHighest(1))])
        let result = roller.resultFrom(formula: f, values: [15, 82, 41])

        #expect(result.total == 82)
        #expect(result.dieRolls.filter(\.isKept).map(\.value) == [82])
    }

    // MARK: - Multi-group keep/drop tie-breaking

    @Test func keepDropAppliedPerGroup() {
        let f = formula([
            DiceGroup(kind: .d6, count: 3, modifier: .keepHighest(2)),
            DiceGroup(kind: .d8, count: 2, modifier: .dropLowest(1))
        ])
        let result = roller.resultFrom(formula: f, values: [1, 6, 3, 4, 2])
        let kept = result.dieRolls.filter(\.isKept).map(\.value)

        #expect(kept == [6, 3, 4])
        #expect(result.total == 13)
    }

    @Test func tiedValuesKeepStableLowestIndices() {
        let f = formula([DiceGroup(kind: .d6, count: 4, modifier: .keepHighest(2))])
        let result = roller.resultFrom(formula: f, values: [4, 4, 4, 4])

        #expect(result.dieRolls.filter(\.isKept).count == 2)
        #expect(result.total == 8)
    }

    // MARK: - QA P0: parser min + keep/drop combination (audit #5)

    @Test func parserAcceptsMinWithKeepDropInEitherOrder() throws {
        let parser = DiceFormulaParser()
        // mod-then-min (canonical displayString order)
        let a = try parser.parse("1d20kh1min10")
        #expect(a.groups.first?.modifier == .keepHighest(1))
        #expect(a.groups.first?.minimumValue == 10)
        // min-then-mod (manual entry) — previously threw invalidMinimum
        let b = try parser.parse("2d6min3kh2")
        #expect(b.groups.first?.count == 2)
        #expect(b.groups.first?.modifier == .keepHighest(2))
        #expect(b.groups.first?.minimumValue == 3)
        // disadvantage + floor
        let c = try parser.parse("2d20kl1min10")
        #expect(c.groups.first?.modifier == .keepLowest(1))
        #expect(c.groups.first?.minimumValue == 10)
        // bare floor still works; a floor with no digits still throws
        #expect((try? parser.parse("1d20min10")) != nil)
        #expect((try? parser.parse("1d20kh1min")) == nil)
    }

    // MARK: - QA P0: advantage preserves a Reliable Talent floor (audit #6)

    @Test func applyingAdvantagePreservesMinimumValue() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        f.modifier = 5
        let adv = f.applyingAdvantage(.advantage)
        #expect(adv.groups.first?.count == 2)
        #expect(adv.groups.first?.modifier == .keepHighest(1))
        #expect(adv.groups.first?.minimumValue == 10)   // floor survives
        #expect(adv.modifier == 5)
        #expect(f.applyingAdvantage(.disadvantage).groups.first?.modifier == .keepLowest(1))
        #expect(f.applyingAdvantage(.normal).groups.first?.count == 1) // no-op
    }

    // MARK: - QA P0: fillDamageType doesn't clobber inline types (audit #16)

    @Test func fillDamageTypeOnlyFillsUntypedGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .fire)) // explicit
        f.groups.append(DiceGroup(kind: .d6, count: 1))                     // untyped
        f.fillDamageType(.cold)
        #expect(f.groups[0].damageType == .fire)   // preserved
        #expect(f.groups[1].damageType == .cold)   // filled
    }

    // MARK: - Critical-hit styles (applyingCrit)

    /// Base damage: 2d6 + 3, slashing. resultFrom with both dice = 4 → dice sum 8.
    private func critBase() -> DiceFormula {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2, damageType: .slashing))
        f.modifier = 3
        return f
    }

    @Test func critDoubleDiceRollsTwiceTheDice() {
        let f = critBase().applyingCrit(CritStyle.doubleDice.rule)
        #expect(f.groups.first?.count == 4)         // 2d6 → 4d6
        #expect(f.diceResultMultiplier == 1)
        // Four 4s = 16, + 3 = 19.
        #expect(roller.resultFrom(formula: f, values: [4, 4, 4, 4]).total == 19)
    }

    @Test func critDoubleRolledValueDoublesDiceNotModifier() {
        let f = critBase().applyingCrit(CritStyle.doubleValue.rule)
        #expect(f.groups.first?.count == 2)         // same dice
        #expect(f.diceResultMultiplier == 2)
        // (4+4)×2 = 16, + 3 = 19 — same EV as RAW but doubles the actual roll.
        #expect(roller.resultFrom(formula: f, values: [4, 4]).total == 19)
        // A low roll stays low (variance differs from RAW): (1+1)×2 + 3 = 7.
        #expect(roller.resultFrom(formula: f, values: [1, 1]).total == 7)
    }

    @Test func critMaxPlusRollAddsMaxFlatAndKeepsDice() {
        let f = critBase().applyingCrit(CritStyle.maxPlusRoll.rule)
        #expect(f.groups.first?.count == 2)         // dice still rolled
        // 2d6 max = 12 → added as a slashing typed flat.
        #expect(f.typedModifiers[.slashing] == 12)
        // Rolled 4+4 = 8, + 12 max + 3 = 23.
        #expect(roller.resultFrom(formula: f, values: [4, 4]).total == 23)
    }

    @Test func critMaximizeFloorsEveryDieToMax() {
        let f = critBase().applyingCrit(CritStyle.maximize.rule)
        #expect(f.groups.first?.minimumValue == 6)  // floored to the die's max
        #expect(f.groups.first?.count == 2)         // still rollable (no 0-dice)
        // Even rolling 1s, each floors to 6: 6+6 + 3 = 15.
        #expect(roller.resultFrom(formula: f, values: [1, 1]).total == 15)
    }

    @Test func critDoubleTotalDoublesDiceAndModifier() {
        let f = critBase().applyingCrit(CritStyle.doubleTotal.rule)
        #expect(f.diceResultMultiplier == 2)
        #expect(f.modifier == 6)                    // 3 × 2
        // (4+4)×2 = 16, + 6 = 22.
        #expect(roller.resultFrom(formula: f, values: [4, 4]).total == 22)
    }

    @Test func critOffLeavesFormulaUnchanged() {
        let f = critBase().applyingCrit(CritStyle.off.rule)
        #expect(f.groups.first?.count == 2)
        #expect(f.modifier == 3)
        #expect(f.diceResultMultiplier == 1)
        #expect(roller.resultFrom(formula: f, values: [4, 4]).total == 11)
    }

    @Test func critStylePresetsMapToExpectedRules() {
        #expect(CritStyle.doubleDice.rule == CritRule(dice: .doubleCount))
        #expect(CritStyle.doubleValue.rule == CritRule(dice: .doubleRolledValue))
        #expect(CritStyle.doubleTotal.rule == CritRule(dice: .doubleRolledValue, modifierMultiplier: 2))
        #expect(CritStyle.default == .doubleDice)
    }
}
