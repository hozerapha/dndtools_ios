import Testing
import Foundation
@testable import ROLLodex

struct DiceFormulaParserErrorTests {

    private let parser = DiceFormulaParser()

    @Test func emptyInputThrowsEmpty() {
        #expect(throws: DiceFormulaParser.ParseError.empty) {
            try parser.parse("")
        }
    }

    @Test func invalidTokenThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("")) {
            try parser.parse("1d6+")
        }
    }

    @Test func nonStandardDieSizeThrowsInvalidDieSize() {
        #expect(throws: DiceFormulaParser.ParseError.invalidDieSize(7)) {
            try parser.parse("1d7")
        }
    }

    @Test func zeroDiceCountThrowsNonPositiveCount() {
        #expect(throws: DiceFormulaParser.ParseError.nonPositiveCount("0d6")) {
            try parser.parse("0d6")
        }
    }

    @Test func negativeDiceTermThrowsNegativeDice() {
        // The parser strips the leading sign before reporting the term.
        #expect(throws: DiceFormulaParser.ParseError.negativeDice("1d6")) {
            try parser.parse("-1d6")
        }
    }

    @Test func overflowThrowsOverflow() {
        #expect(throws: DiceFormulaParser.ParseError.overflow) {
            try parser.parse("1000d6")
        }
    }

    @Test func unknownModifierThrowsUnknownModifier() {
        #expect(throws: DiceFormulaParser.ParseError.unknownModifier("x")) {
            try parser.parse("1d6x")
        }
    }

    @Test func keepHigherThanCountThrowsModifierOutOfRange() {
        #expect(throws: DiceFormulaParser.ParseError.modifierOutOfRange("2d6kh3")) {
            try parser.parse("2d6kh3")
        }
    }

    @Test func dropEqualToCountThrowsModifierOutOfRange() {
        #expect(throws: DiceFormulaParser.ParseError.modifierOutOfRange("2d6dh2")) {
            try parser.parse("2d6dh2")
        }
    }

    @Test func rerollThresholdEqualToSidesThrowsAlwaysTriggers() {
        #expect(throws: DiceFormulaParser.ParseError.rerollAlwaysTriggers("1d6r6")) {
            try parser.parse("1d6r6")
        }
    }

    @Test func unknownDamageTypeThrowsUnknownDamageType() {
        #expect(throws: DiceFormulaParser.ParseError.unknownDamageType("nope")) {
            try parser.parse("[nope]1d6")
        }
    }

    @Test func minimumBelowOneThrowsInvalidMinimum() {
        #expect(throws: DiceFormulaParser.ParseError.invalidMinimum("1d6min0")) {
            try parser.parse("1d6min0")
        }
    }

    @Test func minimumAboveSidesThrowsInvalidMinimum() {
        #expect(throws: DiceFormulaParser.ParseError.invalidMinimum("1d6min7")) {
            try parser.parse("1d6min7")
        }
    }

    @Test func malformedTypedGroupThrowsInvalidToken() {
        #expect(throws: DiceFormulaParser.ParseError.invalidToken("[fire1d6")) {
            try parser.parse("[fire1d6")
        }
    }

    @Test func emptyTypedGroupThrowsUnknownDamageType() {
        #expect(throws: DiceFormulaParser.ParseError.unknownDamageType("")) {
            try parser.parse("[]1d6")
        }
    }
}
