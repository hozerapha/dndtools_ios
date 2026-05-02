import Foundation

struct DiceFormulaParser {
    enum ParseError: Error, LocalizedError {
        case empty
        case invalidToken(String)
        case invalidDieSize(Int)
        case nonPositiveCount(String)
        case negativeDice(String)
        case overflow

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

        if term.contains("d") {
            let parts = term.split(separator: "d", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ParseError.invalidToken(term) }

            let countStr = String(parts[0])
            let sidesStr = String(parts[1])

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

            guard let sides = Int(sidesStr) else {
                throw ParseError.invalidToken(term)
            }
            guard let kind = DieKind(rawValue: sides) else {
                throw ParseError.invalidDieSize(sides)
            }
            if sign < 0 {
                throw ParseError.negativeDice(term)
            }

            for _ in 0..<count {
                formula.add(kind)
            }
        } else {
            guard let n = Int(term) else { throw ParseError.invalidToken(term) }
            formula.modifier += sign * n
        }
    }
}
