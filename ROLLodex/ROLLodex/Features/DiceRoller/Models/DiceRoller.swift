import Foundation

struct DiceRoller {
    func roll(_ formula: DiceFormula, mode: RollMode = .normal) -> RollResult {
        var dieRolls: [DieRoll] = []

        for kind in DieKind.allCases {
            let count = formula.counts[kind, default: 0]
            for _ in 0..<count {
                if kind == .d20 && mode != .normal {
                    let a = Int.random(in: 1...20)
                    let b = Int.random(in: 1...20)
                    let aWins = (mode == .advantage) ? (a >= b) : (a <= b)
                    dieRolls.append(DieRoll(kind: .d20, value: a, isKept:  aWins))
                    dieRolls.append(DieRoll(kind: .d20, value: b, isKept: !aWins))
                } else {
                    let value = Int.random(in: 1...kind.sides)
                    dieRolls.append(DieRoll(kind: kind, value: value))
                }
            }
        }

        return RollResult(formula: formula, dieRolls: dieRolls, mode: mode)
    }
}
