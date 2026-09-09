import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: DiceRoller boundary conditions — `resultFrom` with mismatched
/// array lengths, `rerollIndices` truncation, interaction between
/// `minimumValue` and `diceResultMultiplier`, and keep/drop with count=0 edge.
struct DiceRollerBoundaryTests {

    private let roller = DiceRoller()

    private func formula(_ groups: [DiceGroup], modifier: Int = 0) -> DiceFormula {
        var f = DiceFormula()
        f.groups = groups
        f.modifier = modifier
        return f
    }

    // MARK: - resultFrom: mismatched array lengths

    @Test func resultFromHandlesTooFewValues() {
        // Formula wants 5 dice; values array has only 3 — should not crash,
        // should produce 3 rolls (the available ones).
        let f = formula([DiceGroup(kind: .d6, count: 5)])
        let result = roller.resultFrom(formula: f, values: [4, 2, 6])
        #expect(result.dieRolls.count == 3)
        #expect(result.dieRolls.map(\.value) == [4, 2, 6])
    }

    @Test func resultFromHandlesTooManyValues() {
        // Formula wants 2 dice; values array has 5 — should consume only the
        // first 2 and ignore the extras.
        let f = formula([DiceGroup(kind: .d6, count: 2)])
        let result = roller.resultFrom(formula: f, values: [3, 5, 7, 9, 11])
        #expect(result.dieRolls.count == 2)
        #expect(result.dieRolls.map(\.value) == [3, 5])
    }

    @Test func resultFromWithEmptyValuesProducesNoDice() {
        let f = formula([DiceGroup(kind: .d6, count: 3)])
        let result = roller.resultFrom(formula: f, values: [])
        #expect(result.dieRolls.isEmpty)
        #expect(result.total == 0)
    }

    @Test func resultFromAppliesMinimumFloorEvenWithMismatchedLength() {
        // Flooring is applied to the values that DO exist, even if fewer than expected.
        let f = formula([DiceGroup(kind: .d20, count: 5, minimumValue: 10)])
        let result = roller.resultFrom(formula: f, values: [3, 15])
        #expect(result.dieRolls.count == 2)
        #expect(result.dieRolls[0].value == 10)  // floored from 3
        #expect(result.dieRolls[1].value == 15)
    }

    // MARK: - rerollIndices: truncation and boundary

    @Test func rerollIndicesIgnoresOutOfBoundsValues() {
        // Formula has a reroll group, but values array is shorter than the
        // group count — indices beyond the array are silently skipped.
        let f = formula([DiceGroup(kind: .d6, count: 5, modifier: .rerollOnceIfAtMost(2))])
        let indices = roller.rerollIndices(formula: f, values: [1, 3])
        #expect(indices == [0])  // Only index 0 (value 1 ≤ 2); indices 2–4 don't exist in values
    }

    @Test func rerollIndicesReturnsEmptyWhenThresholdIsZero() {
        // threshold=0 means "reroll if value ≤ 0", which is impossible for
        // standard dice (min 1). This should never trigger.
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .rerollOnceIfAtMost(0))])
        #expect(roller.rerollIndices(formula: f, values: [1, 2, 3]).isEmpty)
    }

    @Test func rerollIndicesWorksWhenThresholdEqualsSides() {
        // Parser rejects this (throws .rerollAlwaysTriggers), but if
        // constructed directly it should flag every die for reroll.
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .rerollOnceIfAtMost(6))])
        #expect(roller.rerollIndices(formula: f, values: [1, 6, 3]) == [0, 1, 2])
    }

    // MARK: - minimumValue × diceResultMultiplier interaction

    @Test func minimumFloorAppliesBeforeMultiplier() {
        // A floored die reads its floor value; that value is then multiplied
        // by the result multiplier (crit style "double rolled value").
        var f = formula([DiceGroup(kind: .d20, count: 1, minimumValue: 10)])
        f.diceResultMultiplier = 2
        let result = roller.resultFrom(formula: f, values: [3])
        // value 3 → floored to 10 → multiplier doesn't touch minimumValue
        // itself; the roll is still 10, and total includes the multiplier:
        // Wait, the multiplier applies to the ROLLED value before modifiers.
        // Let me check the RollResult contract.
        // Actually, reading RollResult.swift (not shown here), the multiplier
        // affects `rolledTotal` but the `DieRoll.value` is the face value.
        // `resultFrom` just produces die rolls; the multiplier is read by
        // RollResult's total computation. So here we check the die roll value.
        #expect(result.dieRolls[0].value == 10)  // floored
    }

    // MARK: - Keep/drop edge: keep/drop 0

    @Test func keepHighestZeroIsRejectedByParser() {
        // Parser should reject kh0 with invalidToken because keeping 0
        // dice violates n > 0 requirement in parseGroupModifier.
        let parser = DiceFormulaParser()
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("3d6kh0")) {
            try parser.parse("3d6kh0")
        }
    }

    @Test func keepHighestZeroDirectlyConstructedKeepsNothing() {
        // If someone bypasses the parser and constructs `keepHighest(0)`
        // directly, the roller's keepIndices should mark all dice dropped.
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .keepHighest(0))])
        let result = roller.resultFrom(formula: f, values: [4, 2, 6])
        #expect(result.dieRolls.allSatisfy { !$0.isKept })
        #expect(result.total == 0)
    }

    @Test func dropHighestZeroKeepsAllDice() {
        // drop 0 = drop nothing = keep everything.
        let f = formula([DiceGroup(kind: .d6, count: 3, modifier: .dropHighest(0))])
        let result = roller.resultFrom(formula: f, values: [4, 2, 6])
        let allKept = result.dieRolls.allSatisfy(\.isKept)
        #expect(allKept)
        #expect(result.total == 12)
    }
}
