import Foundation

struct DieRoll: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: DieKind
    let value: Int
    let isKept: Bool

    init(id: UUID = UUID(), kind: DieKind, value: Int, isKept: Bool = true) {
        self.id = id
        self.kind = kind
        self.value = value
        self.isKept = isKept
    }

    var isCriticalSuccess: Bool { kind == .d20 && value == 20 && isKept }
    var isCriticalFail:    Bool { kind == .d20 && value == 1  && isKept }
}

struct RollResult: Identifiable, Codable, Hashable {
    let id: UUID
    let formula: DiceFormula
    let dieRolls: [DieRoll]
    let mode: RollMode
    let timestamp: Date

    init(
        id: UUID = UUID(),
        formula: DiceFormula,
        dieRolls: [DieRoll],
        mode: RollMode = .normal,
        timestamp: Date = .now
    ) {
        self.id = id
        self.formula = formula
        self.dieRolls = dieRolls
        self.mode = mode
        self.timestamp = timestamp
    }

    var modifier: Int { formula.modifier }

    var total: Int {
        dieRolls.filter(\.isKept).map(\.value).reduce(0, +) + modifier
    }

    var hasCriticalSuccess: Bool { dieRolls.contains(where: \.isCriticalSuccess) }
    var hasCriticalFail:    Bool { dieRolls.contains(where: \.isCriticalFail) }
}
