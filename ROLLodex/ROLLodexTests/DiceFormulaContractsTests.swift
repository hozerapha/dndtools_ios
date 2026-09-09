import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: DiceFormula mutation methods (`add`, `remove`, `clear`) and
/// computed properties (`count(of:)`, `totalDiceCount`, `isEmpty`). These
/// power the picker UI and formula validation but had only incidental coverage.
struct DiceFormulaContractsTests {

    // MARK: - Picker mutation methods

    @Test func addIncrementsDieCountWhenGroupExists() {
        var f = DiceFormula()
        f.add(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d6)
        #expect(f.groups[0].count == 1)

        // Adding again increments the existing group
        f.add(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 2)
    }

    @Test func addCreatesNewGroupForDifferentKind() {
        var f = DiceFormula()
        f.add(.d6)
        f.add(.d20)
        #expect(f.groups.count == 2)
        #expect(f.groups[0].kind == .d6)
        #expect(f.groups[0].count == 1)
        #expect(f.groups[1].kind == .d20)
        #expect(f.groups[1].count == 1)
    }

    @Test func addMergesIntoModifiedGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2, modifier: .keepHighest(1)))
        f.add(.d6)
        // add() merges into ANY matching kind, even if it has a modifier
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 3)
        #expect(f.groups[0].modifier == .keepHighest(1))
    }

    @Test func removeDecrementsDieCountToZeroThenRemovesGroup() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 3))
        f.groups.append(DiceGroup(kind: .d20, count: 1))

        f.remove(.d6)
        #expect(f.groups.count == 2)
        #expect(f.groups.first(where: { $0.kind == .d6 })?.count == 2)

        f.remove(.d6)
        f.remove(.d6)
        // Group removed when count reaches zero
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d20)
    }

    @Test func removeIsNoOpWhenKindAbsent() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1))
        f.remove(.d20)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d6)
    }

    @Test func removeTargetsFirstMatchingGroupOnly() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d6, count: 1, modifier: .rerollOnceIfAtMost(1)))
        f.remove(.d6)
        // First group decremented, second untouched
        #expect(f.groups.count == 2)
        #expect(f.groups[0].count == 1)
        #expect(f.groups[1].count == 1)
    }

    @Test func clearRemovesEverything() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        f.modifier = 5
        f.typedModifiers[.fire] = 3
        f.diceResultMultiplier = 2

        f.clear()
        #expect(f.groups.isEmpty)
        #expect(f.modifier == 0)
        #expect(f.typedModifiers.isEmpty)
        // Multiplier is NOT cleared — it persists across formula edits
        // (crit styles set it; clearing dice shouldn't reset crit mode).
    }

    // MARK: - Counting methods

    @Test func countOfKindSumsAcrossGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d6, count: 3, modifier: .keepHighest(2)))
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        #expect(f.count(of: .d6) == 5)
        #expect(f.count(of: .d20) == 1)
        #expect(f.count(of: .d8) == 0)
    }

    @Test func totalDiceCountSumsAllGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d8, count: 1))
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        #expect(f.totalDiceCount == 4)
    }

    @Test func totalDiceCountIsZeroWhenEmpty() {
        #expect(DiceFormula().totalDiceCount == 0)
    }

    @Test func isEmptyTrueWhenNoGroupsAndNoModifiers() {
        #expect(DiceFormula().isEmpty)
        #expect(DiceFormula(modifier: 0).isEmpty)
    }

    @Test func isEmptyFalseWhenGroupsPresent() {
        var f = DiceFormula()
        f.add(.d6)
        #expect(!f.isEmpty)
    }

    @Test func isEmptyFalseWhenModifierNonZero() {
        var f = DiceFormula(modifier: 3)
        #expect(!f.isEmpty)
    }

    @Test func isEmptyFalseWhenTypedModifiersPresent() {
        var f = DiceFormula(typedModifiers: [.fire: 2])
        #expect(!f.isEmpty)
    }

    // MARK: - supportsAdvantage boundary cases

    @Test func supportsAdvantageTrueOnlyForExactlyOnePlainD20() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        #expect(f.supportsAdvantage)
    }

    @Test func supportsAdvantageFalseWhenD20CountIsTwo() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 2))
        #expect(!f.supportsAdvantage)
    }

    @Test func supportsAdvantageFalseWhenD20HasModifier() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1, modifier: .rerollOnceIfAtMost(1)))
        #expect(!f.supportsAdvantage)
    }

    @Test func supportsAdvantageFalseWhenMultipleGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        f.groups.append(DiceGroup(kind: .d6, count: 1))
        #expect(!f.supportsAdvantage)
    }

    @Test func supportsAdvantageFalseForSingleD6() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1))
        #expect(!f.supportsAdvantage)
    }
}
