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
        case unknownDamageType(String)
        case invalidMinimum(String)

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
                "Unknown modifier '\(s)'. Try kh, kl, dh, dl, r, or min."
            case .modifierOutOfRange(let term):
                "Modifier in '\(term)' asks for more dice than were rolled."
            case .rerollAlwaysTriggers(let term):
                "Reroll threshold in '\(term)' must be less than the die's max."
            case .unknownDamageType(let name):
                "Unknown damage type '\(name)'. Try fire, cold, slashing, force, …"
            case .invalidMinimum(let term):
                "Minimum in '\(term)' must be between 1 and the die's max."
            }
        }
    }

    func parse(_ input: String) throws -> DiceFormula {
        var s = input
            .lowercased()
            .replacingOccurrences(of: "−", with: "-")
        // Strip whitespace AND parens — the latter let users visually group
        // typed clusters like `([fire]2d6+2) + ([bludgeoning]3d8)` without
        // affecting the underlying sum-of-terms semantics.
        s.removeAll(where: { $0.isWhitespace || $0 == "(" || $0 == ")" })
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

        // Optional `[damageType]` prefix tags the resulting dice group.
        var damageType: DamageType? = nil
        var workingTerm = term
        if workingTerm.first == "[" {
            guard let closeIndex = workingTerm.firstIndex(of: "]") else {
                throw ParseError.invalidToken(term)
            }
            let nameStart = workingTerm.index(after: workingTerm.startIndex)
            let name = String(workingTerm[nameStart..<closeIndex])
            guard !name.isEmpty, let parsed = DamageType(rawValue: name) else {
                throw ParseError.unknownDamageType(name)
            }
            damageType = parsed
            workingTerm = String(workingTerm[workingTerm.index(after: closeIndex)...])
            guard !workingTerm.isEmpty else { throw ParseError.invalidToken(term) }
        }

        guard workingTerm.contains("d") else {
            // Pure number — either an untyped flat modifier ("+ 3") or a typed
            // flat modifier ("[force]5") that adds to that type's bucket
            // instead of the formula-wide modifier. Useful for spells like
            // Magic Missile's per-dart `+1 force` baked into the formula.
            guard let n = Int(workingTerm) else { throw ParseError.invalidToken(term) }
            let signed = sign * n
            if let damageType {
                let next = (formula.typedModifiers[damageType] ?? 0) + signed
                if next == 0 {
                    formula.typedModifiers.removeValue(forKey: damageType)
                } else {
                    formula.typedModifiers[damageType] = next
                }
            } else {
                formula.modifier += signed
            }
            return
        }

        // Dice term: <count>?d<sides>[<modifier>...]
        guard let dIndex = workingTerm.firstIndex(of: "d") else {
            throw ParseError.invalidToken(term)
        }
        let countStr = String(workingTerm[..<dIndex])
        let afterD = workingTerm[workingTerm.index(after: dIndex)...]

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

        let (groupModifier, minimumValue) = try parseModifiers(
            modifierStr,
            count: count,
            sides: sides,
            term: term
        )

        // Merge plain terms with an existing plain group of the same kind AND
        // matching damage type, so that `1d6 + 2d6` collapses to `3d6` and
        // `[fire]1d6 + [fire]1d6` collapses to `[fire]2d6`. Different damage
        // types stay as separate groups so the per-type breakdown reads right.
        if groupModifier == nil, minimumValue == nil,
           let i = formula.groups.firstIndex(where: {
               $0.kind == kind && $0.isPlain && $0.damageType == damageType
           }) {
            formula.groups[i].count += count
        } else {
            formula.groups.append(DiceGroup(
                kind: kind,
                count: count,
                modifier: groupModifier,
                damageType: damageType,
                minimumValue: minimumValue
            ))
        }
    }

    private func parseModifiers(
        _ raw: String,
        count: Int,
        sides: Int,
        term: String
    ) throws -> (modifier: GroupModifier?, minimumValue: Int?) {
        var remaining = raw
        var minimumValue: Int? = nil

        // Extract minN suffix/prefix if present.
        if let range = remaining.range(of: "min") {
            let before = String(remaining[..<range.lowerBound])
            let after = String(remaining[range.upperBound...])
            guard let n = Int(after), n >= 1, n <= sides else {
                throw ParseError.invalidMinimum(term)
            }
            minimumValue = n
            remaining = before
        }

        let modifier = try parseGroupModifier(remaining, count: count, sides: sides, term: term)
        return (modifier, minimumValue)
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
            var direction: Swift.Character?
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
