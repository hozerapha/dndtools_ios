import Foundation

struct DiceRoller {
    func roll(_ formula: DiceFormula, mode: RollMode = .normal) -> RollResult {
        var dieRolls: [DieRoll] = []

        for group in formula.groups {
            // Single plain d20 with adv/dis: roll twice, mark the kept one.
            if mode != .normal,
               group.kind == .d20, group.count == 1, group.isPlain,
               formula.supportsAdvantage {
                let a = Int.random(in: 1...20)
                let b = Int.random(in: 1...20)
                let aWins = (mode == .advantage) ? (a >= b) : (a <= b)
                dieRolls.append(DieRoll(kind: .d20, value: a, isKept:  aWins))
                dieRolls.append(DieRoll(kind: .d20, value: b, isKept: !aWins))
                continue
            }

            dieRolls.append(contentsOf: rollGroup(group))
        }

        return RollResult(formula: formula, dieRolls: dieRolls, mode: mode)
    }

    private func rollGroup(_ group: DiceGroup) -> [DieRoll] {
        var values: [Int] = []
        for _ in 0..<group.count {
            var v = Int.random(in: 1...group.kind.sides)
            if case .rerollOnceIfAtMost(let threshold) = group.modifier, v <= threshold {
                v = Int.random(in: 1...group.kind.sides)
            }
            values.append(v)
        }

        let keptFlags = keptFlags(for: values, modifier: group.modifier)
        return zip(values, keptFlags).map { value, kept in
            DieRoll(kind: group.kind, value: value, isKept: kept)
        }
    }

    /// Returns one Bool per value, true if that value is kept toward the total.
    private func keptFlags(for values: [Int], modifier: GroupModifier?) -> [Bool] {
        switch modifier {
        case .none, .rerollOnceIfAtMost:
            return Array(repeating: true, count: values.count)

        case .keepHighest(let n):
            return keepIndices(in: values, count: n, descending: true)
        case .keepLowest(let n):
            return keepIndices(in: values, count: n, descending: false)
        case .dropHighest(let n):
            return dropIndices(in: values, count: n, descending: true)
        case .dropLowest(let n):
            return dropIndices(in: values, count: n, descending: false)
        }
    }

    private func keepIndices(in values: [Int], count keep: Int, descending: Bool) -> [Bool] {
        let sorted = values.indices.sorted {
            descending ? values[$0] > values[$1] : values[$0] < values[$1]
        }
        let kept = Set(sorted.prefix(keep))
        return values.indices.map { kept.contains($0) }
    }

    private func dropIndices(in values: [Int], count drop: Int, descending: Bool) -> [Bool] {
        let sorted = values.indices.sorted {
            descending ? values[$0] > values[$1] : values[$0] < values[$1]
        }
        let dropped = Set(sorted.prefix(drop))
        return values.indices.map { !dropped.contains($0) }
    }

    // MARK: - Physics-driven helpers (used by the 3D dice tray)

    /// Build a `RollResult` from PRE-DETERMINED per-die values (e.g. produced by the
    /// 3D physics engine). Applies each group's keep/drop modifier, but does NOT
    /// generate any random values — the caller must already have resolved rerolls
    /// and pass in the FINAL face values, in formula order.
    func resultFrom(
        formula: DiceFormula,
        values: [Int],
        mode: RollMode = .normal,
        label: String? = nil
    ) -> RollResult {
        var dieRolls: [DieRoll] = []
        var cursor = 0
        for group in formula.groups {
            let endIndex = min(cursor + group.count, values.count)
            let groupValues = Array(values[cursor..<endIndex])
            let kept = keptFlags(for: groupValues, modifier: group.modifier)
            for (v, k) in zip(groupValues, kept) {
                dieRolls.append(DieRoll(kind: group.kind, value: v, isKept: k))
            }
            cursor += group.count
        }
        return RollResult(formula: formula, dieRolls: dieRolls, mode: mode, label: label)
    }

    /// Returns the formula-flat indices of dice that should re-roll under their
    /// group's `rerollOnceIfAtMost` modifier given the current values. The 3D roller
    /// uses this to decide which dice to physically rethrow after the initial settle.
    func rerollIndices(formula: DiceFormula, values: [Int]) -> [Int] {
        var result: [Int] = []
        var cursor = 0
        for group in formula.groups {
            if case .rerollOnceIfAtMost(let threshold) = group.modifier {
                for offset in 0..<group.count {
                    let i = cursor + offset
                    if i < values.count, values[i] <= threshold {
                        result.append(i)
                    }
                }
            }
            cursor += group.count
        }
        return result
    }
}
