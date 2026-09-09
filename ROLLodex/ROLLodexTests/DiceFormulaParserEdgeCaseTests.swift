import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: parser *happy paths* and error edges not exercised by
/// `DiceFormulaParserErrorTests` (all-error-paths) or `DamageTypingTests`
/// (typed groups). These pin the grammar the formula bar accepts:
/// implicit counts, case folding, Unicode minus, alternate keep/drop
/// spellings, same-kind plain-group merging, reroll/min/d100 suffixes,
/// and the modifier-syntax rejects between the already-tested error cases.
struct DiceFormulaParserEdgeCaseTests {

    private let parser = DiceFormulaParser()

    // MARK: - Happy paths

    @Test func implicitCountDefaultsToOneDie() throws {
        let f = try parser.parse("d20")
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d20)
        #expect(f.groups[0].count == 1)
    }

    @Test func parsingIsCaseInsensitive() throws {
        let f = try parser.parse("2D6+1D20+3")
        #expect(f.groups.count == 2)
        #expect(f.groups[0].kind == .d6)
        #expect(f.groups[0].count == 2)
        #expect(f.groups[1].kind == .d20)
        #expect(f.modifier == 3)
        // Modifier suffixes fold too: "KH1" parses like "kh1".
        let adv = try parser.parse("2D20KH1")
        #expect(adv.groups[0].modifier == .keepHighest(1))
    }

    @Test func unicodeMinusParsesAsNegative() throws {
        // displayString emits U+2212 for negatives; pasted formulas must parse back.
        let f = try parser.parse("1d20−2")
        #expect(f.groups.count == 1)
        #expect(f.modifier == -2)
    }

    @Test func multiTermFormulaKeepsGroupOrderAndModifier() throws {
        let f = try parser.parse("2d6+1d20+3")
        #expect(f.groups.map(\.kind) == [.d6, .d20])
        #expect(f.groups.map(\.count) == [2, 1])
        #expect(f.modifier == 3)
    }

    @Test func alternateKeepDropSpellingsMatchCanonicalForms() throws {
        // Grammar accepts both "kh3" and "k3h" (and the drop twins).
        let kh = try parser.parse("4d6kh3")
        let kAlt = try parser.parse("4d6k3h")
        #expect(kh.groups[0].modifier == .keepHighest(3))
        #expect(kAlt.groups[0].modifier == .keepHighest(3))

        let kl = try parser.parse("2d20k1l")
        #expect(kl.groups[0].modifier == .keepLowest(1))
        let dh = try parser.parse("4d6d1h")
        #expect(dh.groups[0].modifier == .dropHighest(1))
        let dl = try parser.parse("4d6dl1")
        #expect(dl.groups[0].modifier == .dropLowest(1))
    }

    @Test func sameKindPlainGroupsMergeIntoOne() throws {
        // "1d6 + 2d6" is one 3d6 pool — keep/drop must see all three dice.
        let f = try parser.parse("1d6+2d6")
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d6)
        #expect(f.groups[0].count == 3)
        #expect(f.groups[0].modifier == nil)
    }

    @Test func mergeNeverCrossesKindsOrModifiers() throws {
        // Different kinds never merge.
        let kinds = try parser.parse("1d6+1d8")
        #expect(kinds.groups.count == 2)
        // A modified group stays its own term, even next to a plain twin.
        let modified = try parser.parse("1d6+2d6kh1")
        #expect(modified.groups.count == 2)
        #expect(modified.groups[0].modifier == nil)
        #expect(modified.groups[1].modifier == .keepHighest(1))
        // …and in the reverse order too.
        let reversed = try parser.parse("2d6kh1+1d6")
        #expect(reversed.groups.count == 2)
    }

    @Test func rerollSuffixParsesAndRoundTrips() throws {
        let f = try parser.parse("2d6r1")
        #expect(f.groups[0].modifier == .rerollOnceIfAtMost(1))
        #expect(f.displayString == "2d6r1")
        let reparsed = try parser.parse(f.displayString)
        #expect(reparsed.groups[0].modifier == .rerollOnceIfAtMost(1))
    }

    @Test func minimumEqualToSidesIsValid() throws {
        // min == sides means "always the top face" (crit-maximize relies on it).
        let f = try parser.parse("1d20min20")
        #expect(f.groups[0].minimumValue == 20)
    }

    @Test func d100ParsesAsADieKind() throws {
        let f = try parser.parse("2d100")
        #expect(f.groups.count == 1)
        #expect(f.groups[0].kind == .d100)
        #expect(f.groups[0].count == 2)
        // Keep/drop grammar applies to percentile dice as well.
        let kept = try parser.parse("2d100kh1")
        #expect(kept.groups[0].modifier == .keepHighest(1))
    }

    @Test func countBoundaryAccepts999() throws {
        let f = try parser.parse("999d6")
        #expect(f.groups[0].count == 999)
    }

    @Test func displayStringRoundTripsNegativeUntypedModifier() throws {
        let f = try parser.parse("1d8−2")
        let reparsed = try parser.parse(f.displayString)
        #expect(reparsed.modifier == -2)
        #expect(reparsed.groups[0].kind == .d8)
    }

    // MARK: - Error edges between the already-tested cases

    @Test func keepWithoutDirectionThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("1d6k2")) {
            try parser.parse("1d6k2")
        }
    }

    @Test func keepOfZeroThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("1d6kh0")) {
            try parser.parse("1d6kh0")
        }
    }

    @Test func doubledDirectionThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("1d6khh1")) {
            try parser.parse("1d6khh1")
        }
    }

    @Test func rerollOfZeroThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("1d6r0")) {
            try parser.parse("1d6r0")
        }
    }
}
