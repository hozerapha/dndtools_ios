import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: roll-result *aggregation* — how `RollResult.total` and
/// `subtotalsByType` combine kept dice, typed flat modifiers, and the
/// `diceResultMultiplier` crit knob; plus the `DiceRoller.resultFrom`
/// physics-path contract (label/mode stamping, value-count mismatch
/// tolerance) and legacy `RollResult` decoding.
struct RollResultAggregationTests {

    private let roller = DiceRoller()

    // MARK: - total: typed modifiers and the dice multiplier

    @Test func totalIncludesTypedFlatModifiers() {
        // [force]1d12 + [force]5: the typed flat contributes to the grand
        // total, not just to the per-type bucket.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d12, count: 1, damageType: .force))
        formula.typedModifiers = [.force: 5]
        let result = RollResult(formula: formula, dieRolls: [DieRoll(kind: .d12, value: 8)])
        #expect(result.total == 13)
    }

    @Test func totalMultipliesDiceOnlyNeverModifiers() {
        // CritStyle.doubleValue: (4+4)×2 dice, + 5 typed flat, + 3 untyped
        // flat — the multiplier must NOT touch either modifier.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2, damageType: .fire))
        formula.typedModifiers = [.fire: 5]
        formula.modifier = 3
        formula.diceResultMultiplier = 2
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d6, value: 4), DieRoll(kind: .d6, value: 4)]
        )
        #expect(result.total == 24)
    }

    @Test func subtotalsByTypeScalesDiceBucketsByMultiplier() {
        // The bucket math must mirror total's multiplier handling so the HUD
        // breakdown always sums back to the headline number.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2, damageType: .fire))
        formula.diceResultMultiplier = 2
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d6, value: 4), DieRoll(kind: .d6, value: 4)]
        )
        #expect(result.subtotalsByType == [.fire: 16])
        #expect(result.total == 16)
    }

    // MARK: - resultFrom stamping contract (label, mode)

    @Test func resultFromStampsLabelOntoResult() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        let result = roller.resultFrom(formula: formula, values: [12], label: "Stealth Check")
        #expect(result.label == "Stealth Check")
    }

    @Test func resultFromTreatsModeAsMetadataOnly() {
        // REGRESSION GUARD for the MinimumValueTests.swift:130 crash.
        // `resultFrom` never inflates a d20 for adv/dis — it consumes exactly
        // one value per group.count and merely stamps `mode`. Advantage
        // doubling lives in `roll()` and in `applyingAdvantage`, which the
        // caller must apply FIRST. This pins that contract so a future
        // "resultFrom should handle adv/dis itself" change is deliberate.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        let result = roller.resultFrom(formula: formula, values: [12], mode: .disadvantage)
        #expect(result.dieRolls.count == 1)
        #expect(result.dieRolls[0].isKept)
        #expect(result.total == 12)
        #expect(result.mode == .disadvantage)
    }

    // MARK: - resultFrom value-count mismatch tolerance

    @Test func resultFromToleratesTrailingUnderflow() {
        // Physics snapshot short on the LAST group: the roll still resolves
        // with the dice that arrived instead of crashing.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1))
        formula.groups.append(DiceGroup(kind: .d6, count: 3))
        let result = roller.resultFrom(formula: formula, values: [5, 2, 4])
        #expect(result.dieRolls.count == 3)
        #expect(result.total == 11)
    }

    @Test func resultFromIgnoresSurplusValues() {
        // Extra snapshot values beyond the formula's dice are dropped, not
        // summed into the total.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2))
        let result = roller.resultFrom(formula: formula, values: [3, 4, 9, 9])
        #expect(result.dieRolls.count == 2)
        #expect(result.total == 7)
    }

    // MARK: - Critical flags only count kept d20s

    @Test func criticalFlagsRequireD20KeptAndExactFace() {
        let nat20Kept = DieRoll(kind: .d20, value: 20, isKept: true)
        #expect(nat20Kept.isCriticalSuccess)
        let nat20Dropped = DieRoll(kind: .d20, value: 20, isKept: false)
        #expect(!nat20Dropped.isCriticalSuccess)
        // A 20-sided face on another die kind is not a crit.
        let d6Max = DieRoll(kind: .d6, value: 6, isKept: true)
        #expect(!d6Max.isCriticalSuccess)
        #expect(!d6Max.isCriticalFail)
        let nat1Kept = DieRoll(kind: .d20, value: 1, isKept: true)
        #expect(nat1Kept.isCriticalFail)
        let nat1Dropped = DieRoll(kind: .d20, value: 1, isKept: false)
        #expect(!nat1Dropped.isCriticalFail)
    }

    // MARK: - Legacy RollResult decoding

    @Test func legacyRollResultWithoutModeOrLabelDecodes() throws {
        // History entries written before `mode`/`label` existed must still
        // load: mode defaults to .normal, label to nil.
        let json = """
        {
          "id": "00000000-0000-0000-0000-0000000000A1",
          "formula": {
            "groups": [
              { "id": "00000000-0000-0000-0000-0000000000B2", "kind": 20, "count": 1 }
            ],
            "modifier": 5
          },
          "dieRolls": [
            { "id": "00000000-0000-0000-0000-0000000000C3", "kind": 20, "value": 15, "isKept": true }
          ],
          "timestamp": 750000000.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RollResult.self, from: json)
        #expect(decoded.mode == .normal)
        #expect(decoded.label == nil)
        #expect(decoded.total == 20)
        #expect(decoded.dieRolls.count == 1)
    }
}
