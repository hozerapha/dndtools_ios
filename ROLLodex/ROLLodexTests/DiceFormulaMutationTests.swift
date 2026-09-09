import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: `DiceFormula` mutation + display contracts — the die
/// picker's `add`/`remove`/`clear`, dice counting (`count(of:)`,
/// `totalDiceCount`, `isEmpty`), `merging`'s zero-bucket pruning and
/// multiplier retention, `displayString`'s negative/empty rendering with
/// parser round-trips, and the untested `applyingCrit` branches (untyped
/// max-plus-roll, typed-modifier doubling).
struct DiceFormulaMutationTests {

    // MARK: - add (die picker increment)

    @Test func addCreatesThenBumpsPlainGroup() {
        var f = DiceFormula()
        f.add(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 1)
        f.add(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 2)
        f.add(.d20)
        #expect(f.groups.count == 2)
        #expect(f.groups[1].kind == .d20)
        #expect(f.groups[1].count == 1)
    }

    @Test func addBumpsModifiedGroupWithoutTouchingModifier() {
        // Picker taps bump the first group of that kind *even when it carries
        // a keep/drop modifier* — the modifier rides along on the new count.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2, modifier: .keepHighest(1)))
        f.add(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 3)
        #expect(f.groups[0].modifier == .keepHighest(1))
    }

    // MARK: - remove (die picker decrement)

    @Test func removeDecrementsThenDeletesGroupAtZero() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.remove(.d6)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 1)
        f.remove(.d6)
        #expect(f.groups.isEmpty)
    }

    @Test func removeDeletesSingleModifiedGroup() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1, modifier: .dropLowest(1)))
        f.remove(.d6)
        #expect(f.groups.isEmpty)
    }

    @Test func removeMissingKindIsNoOp() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.modifier = 3
        f.remove(.d20)
        #expect(f.groups.count == 1)
        #expect(f.groups[0].count == 2)
        #expect(f.modifier == 3)
    }

    // MARK: - clear

    @Test func clearWipesGroupsAndBothModifierKinds() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .fire))
        f.modifier = 3
        f.typedModifiers[.fire] = 2
        f.clear()
        #expect(f.groups.isEmpty)
        #expect(f.modifier == 0)
        #expect(f.typedModifiers.isEmpty)
        #expect(f.isEmpty)
    }

    // MARK: - Dice counting

    @Test func countOfKindSumsAcrossPlainAndModifiedGroups() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d6, count: 3, modifier: .keepHighest(2)))
        f.groups.append(DiceGroup(kind: .d8, count: 1))
        #expect(f.count(of: .d6) == 5)
        #expect(f.count(of: .d8) == 1)
        #expect(f.count(of: .d20) == 0)
    }

    @Test func totalDiceCountSumsAllGroups() {
        var f = DiceFormula()
        #expect(f.totalDiceCount == 0)
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.groups.append(DiceGroup(kind: .d100, count: 1))
        #expect(f.totalDiceCount == 3)
    }

    @Test func isEmptyRequiresNoDiceAndNoModifiers() {
        var bare = DiceFormula()
        #expect(bare.isEmpty)
        bare.modifier = 3
        #expect(!bare.isEmpty)

        var typedOnly = DiceFormula()
        typedOnly.typedModifiers[.force] = 5
        #expect(!typedOnly.isEmpty)

        var diceOnly = DiceFormula()
        diceOnly.groups.append(DiceGroup(kind: .d4, count: 1))
        #expect(!diceOnly.isEmpty)
    }

    // MARK: - merging: zero pruning and multiplier retention

    @Test func mergingPrunesTypedBucketsThatCancelToZero() {
        // Doc contract: "Zero entries are pruned so a 'fire: 0' key never
        // lingers after edits."
        var base = DiceFormula()
        base.typedModifiers[.fire] = 2
        var rider = DiceFormula()
        rider.typedModifiers[.fire] = -2
        let merged = base.merging(rider)
        #expect(merged.typedModifiers.isEmpty)
        #expect(merged.typedModifiers[.fire] == nil)
    }

    @Test func mergingKeepsBaseDiceMultiplier() {
        // Doc contract: "The base's `diceResultMultiplier` is kept (riders
        // don't carry one)."
        var base = DiceFormula()
        base.groups.append(DiceGroup(kind: .d6, count: 2))
        base.diceResultMultiplier = 2
        var rider = DiceFormula()
        rider.groups.append(DiceGroup(kind: .d8, count: 1))
        let merged = base.merging(rider)
        #expect(merged.diceResultMultiplier == 2)
        #expect(merged.groups.count == 2)
    }

    // MARK: - displayString rendering + round-trips

    @Test func displayStringRendersEmptyFormulaAsPlaceholder() {
        #expect(DiceFormula().displayString == "—")
    }

    @Test func displayStringRendersNegativeUntypedModifier() throws {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d8, count: 1))
        f.modifier = -2
        #expect(f.displayString == "1d8 − 2")
        // Round-trip: the parser folds U+2212 back to "-".
        let reparsed = try DiceFormulaParser().parse(f.displayString)
        #expect(reparsed.modifier == -2)
        #expect(reparsed.groups.count == 1)
    }

    @Test func displayStringRendersNegativeTypedModifier() throws {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .fire))
        f.typedModifiers[.fire] = -2
        #expect(f.displayString == "[fire]1d6 − [fire]2")
        let reparsed = try DiceFormulaParser().parse(f.displayString)
        #expect(reparsed.typedModifiers == [.fire: -2])
        #expect(reparsed.modifier == 0)
    }

    @Test func displayStringOrdersGroupsThenTypedThenFlat() throws {
        // Positive typed flats ride with the groups; the untyped flat trails.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .fire))
        f.typedModifiers[.fire] = 2
        f.modifier = 3
        #expect(f.displayString == "[fire]1d6 + [fire]2 + 3")
        let reparsed = try DiceFormulaParser().parse(f.displayString)
        #expect(reparsed.typedModifiers == [.fire: 2])
        #expect(reparsed.modifier == 3)
    }

    // MARK: - applyingCrit untested branches

    @Test func critMaxPlusRollAddsMaxToUntypedModifierWhenGroupIsUntyped() {
        // Typed groups push their max into the typed bucket (covered in
        // DiceRollerTests); an untyped group pushes into the flat modifier.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2))
        f.modifier = 3
        let crit = f.applyingCrit(CritStyle.maxPlusRoll.rule)
        #expect(crit.modifier == 15) // 3 + 2×6
        #expect(crit.typedModifiers.isEmpty)
        #expect(crit.groups.first?.count == 2)
    }

    @Test func critDoubleTotalDoublesTypedModifiersToo() {
        // modifierMultiplier must hit typed flats as well as the untyped one,
        // or a double-total crit under-charges typed riders.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d6, count: 2, damageType: .fire))
        f.typedModifiers[.fire] = 2
        f.modifier = 3
        let crit = f.applyingCrit(CritStyle.doubleTotal.rule)
        #expect(crit.typedModifiers == [.fire: 4])
        #expect(crit.modifier == 6)
        #expect(crit.diceResultMultiplier == 2)
    }
}
