import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: the advantage/disadvantage *encoding* contract —
/// `DiceFormula.supportsAdvantage`, `DiceFormula.applyingAdvantage(_:)`,
/// and `DiceFormula.encodedAdvantageMode` (the inverse mapping the history
/// sheet uses to decorate "2d20kh1" with "(adv)"). The roller side
/// (roll-twice-keep-one) is covered in `DiceRollerTests`; these tests pin
/// the formula-level encoding that drives it.
///
/// SRD_CC_v5.2.1, p.7 ("Advantage/Disadvantage — Roll Two D20s"):
/// "When a roll has either Advantage or Disadvantage, roll a second d20
/// when you make the roll. Use the higher of the two rolls if you have
/// Advantage, and use the lower roll if you have Disadvantage."
struct AdvantageEncodingTests {

    // MARK: - supportsAdvantage (the roller's gate for doubling the d20)

    @Test func supportsAdvantageForPlainSingleD20() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        #expect(f.supportsAdvantage)
    }

    @Test func supportsAdvantageIgnoresFormulaLevelModifier() {
        // "1d20+5" — a flat ability/attack bonus must not disqualify adv/dis.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        f.modifier = 5
        #expect(f.supportsAdvantage)
    }

    @Test func supportsAdvantageWithMinimumValueFloor() {
        // Reliable Talent's "1d20min10" is still a single plain d20 — the floor
        // is a per-die clamp, not a keep/drop modifier. (SRD p.64: Reliable
        // Talent treats a d20 roll of 9 or lower as a 10.)
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1, minimumValue: 10))
        #expect(f.supportsAdvantage)
    }

    @Test func supportsAdvantageRejectsNonSingleOrModifiedD20() {
        var twoDice = DiceFormula()
        twoDice.groups.append(DiceGroup(kind: .d20, count: 2))
        #expect(!twoDice.supportsAdvantage)

        var keepModified = DiceFormula()
        keepModified.groups.append(DiceGroup(kind: .d20, count: 1, modifier: .keepHighest(1)))
        #expect(!keepModified.supportsAdvantage)

        var withOtherDice = DiceFormula()
        withOtherDice.groups.append(DiceGroup(kind: .d20, count: 1))
        withOtherDice.groups.append(DiceGroup(kind: .d6, count: 1))
        #expect(!withOtherDice.supportsAdvantage)

        var wrongKind = DiceFormula()
        wrongKind.groups.append(DiceGroup(kind: .d12, count: 1))
        #expect(!wrongKind.supportsAdvantage)
    }

    // MARK: - applyingAdvantage (formula → 2d20kh1 / 2d20kl1)

    @Test func applyingAdvantageExpandsTheD20Group() {
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        let adv = f.applyingAdvantage(.advantage)
        #expect(adv.groups.first?.count == 2)
        #expect(adv.groups.first?.modifier == .keepHighest(1))
        let dis = f.applyingAdvantage(.disadvantage)
        #expect(dis.groups.first?.count == 2)
        #expect(dis.groups.first?.modifier == .keepLowest(1))
    }

    @Test func applyingAdvantageLeavesNonEligibleFormulasUntouched() {
        var alreadyTwo = DiceFormula()
        alreadyTwo.groups.append(DiceGroup(kind: .d20, count: 2))
        let expandedTwo = alreadyTwo.applyingAdvantage(.advantage)
        #expect(expandedTwo.groups.first?.count == 2)
        #expect(expandedTwo.groups.first?.modifier == nil)

        var alreadyModified = DiceFormula()
        alreadyModified.groups.append(DiceGroup(kind: .d20, count: 1, modifier: .rerollOnceIfAtMost(1)))
        let expandedModified = alreadyModified.applyingAdvantage(.advantage)
        #expect(expandedModified.groups.first?.count == 1)
        #expect(expandedModified.groups.first?.modifier == .rerollOnceIfAtMost(1))
    }

    @Test func applyingAdvantageTargetsD20GroupEvenAlongsideOtherDice() {
        // Per its doc comment, the expansion keys on "the first plain
        // single-d20 group" — not on the whole formula being a lone d20.
        // (e.g. a d20 check with a bonus d4 rider still expands the d20.)
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d4, count: 1))
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        let adv = f.applyingAdvantage(.advantage)
        #expect(adv.groups[0].count == 1)
        #expect(adv.groups[0].modifier == nil)
        #expect(adv.groups[1].count == 2)
        #expect(adv.groups[1].modifier == .keepHighest(1))
    }

    // MARK: - encodedAdvantageMode (history label decoration)

    @Test func encodedAdvantageModeReadsKeepEncodings() throws {
        let parser = DiceFormulaParser()
        let adv = try parser.parse("2d20kh1")
        #expect(adv.encodedAdvantageMode == .advantage)
        let dis = try parser.parse("2d20kl1")
        #expect(dis.encodedAdvantageMode == .disadvantage)
    }

    @Test func encodedAdvantageModeIsNilForNonEncodings() throws {
        let parser = DiceFormulaParser()
        // Plain rolls, wrong count, wrong modifier shape, wrong die — none of
        // these are advantage encodings.
        #expect(try parser.parse("1d20").encodedAdvantageMode == nil)
        #expect(try parser.parse("2d20").encodedAdvantageMode == nil)
        #expect(try parser.parse("3d20kh1").encodedAdvantageMode == nil)
        #expect(try parser.parse("2d20kh2").encodedAdvantageMode == nil)
        #expect(try parser.parse("2d20dh1").encodedAdvantageMode == nil)
        #expect(try parser.parse("2d6kh1").encodedAdvantageMode == nil)
    }

    @Test func encodedAdvantageModeScansAllGroupsAndToleratesFloor() throws {
        let parser = DiceFormulaParser()
        // A d20 pair hiding behind another group is still detected.
        #expect(try parser.parse("1d6+2d20kh1").encodedAdvantageMode == .advantage)
        // A Reliable-Talent floor on the pair must not hide the encoding.
        #expect(try parser.parse("2d20kl1min10").encodedAdvantageMode == .disadvantage)
    }

    @Test func applyingAdvantageRoundTripsThroughEncodedMode() {
        // The encoder and decoder must agree: whatever applyingAdvantage
        // produces, encodedAdvantageMode reads back.
        var f = DiceFormula()
        f.groups.append(DiceGroup(kind: .d20, count: 1))
        #expect(f.applyingAdvantage(.advantage).encodedAdvantageMode == .advantage)
        #expect(f.applyingAdvantage(.disadvantage).encodedAdvantageMode == .disadvantage)
        #expect(f.applyingAdvantage(.normal).encodedAdvantageMode == nil)
    }

    // MARK: - RollMode persistence raw values

    @Test func rollModeRawValuesAreStable() {
        // History entries persist RollMode by raw value in UserDefaults —
        // renaming a case silently corrupts saved modes on upgrade.
        #expect(RollMode.normal.rawValue == "normal")
        #expect(RollMode.advantage.rawValue == "advantage")
        #expect(RollMode.disadvantage.rawValue == "disadvantage")
        #expect(RollMode.allCases.count == 3)
    }
}
