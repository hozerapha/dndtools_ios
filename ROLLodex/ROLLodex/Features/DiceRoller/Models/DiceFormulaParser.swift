import Foundation

struct DiceFormulaParser {
    enum ParseError: Error, LocalizedError {
        case empty
        case invalidToken(String)
        case invalidDieSize(Int)
        case nonPositiveCount(String)
        case negativeDice(String)
        case overflow
        case unknownModifier(String)
        case modifierOutOfRange(String)
        case rerollAlwaysTriggers(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                "Formula is empty."
            case .invalidToken(let token):
                "Can't parse '\(token)'."
            case .invalidDieSize(let n):
                "d\(n) isn't a standard die. Try d4, d6, d8, d10, d12, d20, or d100."
            case .nonPositiveCount(let term):
                "Dice count must be at least 1 in '\(term)'."
            case .negativeDice(let term):
                "Dice can't be subtracted ('\(term)')."
            case .overflow:
                "That's too many dice."
            case .unknownModifier(let s):
                "Unknown modifier '\(s)'. Try kh, kl, dh, dl, or r."
            case .modifierOutOfRange(let term):
                "Modifier in '\(term)' asks for more dice than were rolled."
            case .rerollAlwaysTriggers(let term):
                "Reroll threshold in '\(term)' must be less than the die's max."
            }
        }
    }

    func parse(_ input: String) throws -> DiceFormula {
        var s = input
            .lowercased()
            .replacingOccurrences(of: "−", with: "-")
        s.removeAll(where: { $0.isWhitespace })
        guard !s.isEmpty else { throw ParseError.empty }

        if !(s.first == "+" || s.first == "-") {
            s = "+" + s
        }

        var formula = DiceFormula()
        var index = s.startIndex
        while index < s.endIndex {
            let signChar = s[index]
            guard signChar == "+" || signChar == "-" else {
                throw ParseError.invalidToken(String(s[index...]))
            }
            let sign = signChar == "+" ? 1 : -1

            var end = s.index(after: index)
            while end < s.endIndex, s[end] != "+", s[end] != "-" {
                end = s.index(after: end)
            }
            let term = String(s[s.index(after: index)..<end])
            try apply(term, sign: sign, into: &formula)
            index = end
        }
        return formula
    }

    private func apply(_ term: String, sign: Int, into formula: inout DiceFormula) throws {
        guard !term.isEmpty else { throw ParseError.invalidToken("") }

        guard term.contains("d") else {
            // Pure number → modifier
            guard let n = Int(term) else { throw ParseError.invalidToken(term) }
            formula.modifier += sign * n
            return
        }

        // Dice term: <count>?d<sides>[<modifier>...]
        guard let dIndex = term.firstIndex(of: "d") else {
            throw ParseError.invalidToken(term)
        }
        let countStr = String(term[..<dIndex])
        let afterD = term[term.index(after: dIndex)...]

        let count: Int
        if countStr.isEmpty {
            count = 1
        } else if let parsed = Int(countStr) {
            count = parsed
        } else {
            throw ParseError.invalidToken(term)
        }
        if count <= 0 { throw ParseError.nonPositiveCount(term) }
        if count > 999 { throw ParseError.overflow }

        // Read sides as the leading run of digits, rest is the modifier suffix.
        var sidesEnd = afterD.startIndex
        while sidesEnd < afterD.endIndex, afterD[sidesEnd].isNumber {
            sidesEnd = afterD.index(after: sidesEnd)
        }
        let sidesStr = String(afterD[..<sidesEnd])
        let modifierStr = String(afterD[sidesEnd...])

        guard let sides = Int(sidesStr) else { throw ParseError.invalidToken(term) }
        guard let kind = DieKind(rawValue: sides) else { throw ParseError.invalidDieSize(sides) }
        if sign < 0 { throw ParseError.negativeDice(term) }

        let groupModifier = try parseGroupModifier(
            modifierStr,
            count: count,
            sides: sides,
            term: term
        )

        // Merge plain terms with an existing plain group of the same kind so that "1d6 + 2d6"
        // collapses to "3d6", but DON'T collapse plain terms into a *modified* group.
        if groupModifier == nil,
           let i = formula.groups.firstIndex(where: { $0.kind == kind && $0.isPlain }) {
            formula.groups[i].count += count
        } else {
            formula.groups.append(DiceGroup(kind: kind, count: count, modifier: groupModifier))
        }
    }

    private func parseGroupModifier(
        _ raw: String,
        count: Int,
        sides: Int,
        term: String
    ) throws -> GroupModifier? {
        guard !raw.isEmpty else { return nil }
        let chars = Array(raw)
        let first = chars[0]

        switch first {
        case "k", "d":
            // Keep / drop. Forms accepted: kh3, k3h, kl3, k3l, dh1, d1h, dl1, d1l.
            var direction: Character?
            var nString = ""
            for c in chars.dropFirst() {
                if c == "h" || c == "l" {
                    if direction != nil { throw ParseError.invalidToken(term) }
                    direction = c
                } else if c.isNumber {
                    nString.append(c)
                } else {
                    throw ParseError.invalidToken(term)
                }
            }
            guard let direction, let n = Int(nString), n > 0 else {
                throw ParseError.invalidToken(term)
            }

            let isKeep = (first == "k")
            if isKeep && n > count { throw ParseError.modifierOutOfRange(term) }
            if !isKeep && n >= count { throw ParseError.modifierOutOfRange(term) }

            switch (first, direction) {
            case ("k", "h"): return .keepHighest(n)
            case ("k", "l"): return .keepLowest(n)
            case ("d", "h"): return .dropHighest(n)
            case ("d", "l"): return .dropLowest(n)
            default: throw ParseError.invalidToken(term)
            }

        case "r":
            let nString = String(chars.dropFirst())
            guard let n = Int(nString), n >= 1 else {
                throw ParseError.invalidToken(term)
            }
            if n >= sides { throw ParseError.rerollAlwaysTriggers(term) }
            return .rerollOnceIfAtMost(n)

        default:
            throw ParseError.unknownModifier(raw)
        }
    }
}
