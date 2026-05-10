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
    /// Friendly name carried over from the source of the roll: a sheet check
    /// ("Sleight of Hand Check"), a saved preset, or nil for an ad-hoc roll
    /// from the dice tab. Display layers fall back to "Custom roll" when nil.
    let label: String?

    init(
        id: UUID = UUID(),
        formula: DiceFormula,
        dieRolls: [DieRoll],
        mode: RollMode = .normal,
        timestamp: Date = .now,
        label: String? = nil
    ) {
        self.id = id
        self.formula = formula
        self.dieRolls = dieRolls
        self.mode = mode
        self.timestamp = timestamp
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id, formula, dieRolls, mode, timestamp, label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        formula = try c.decode(DiceFormula.self, forKey: .formula)
        dieRolls = try c.decode([DieRoll].self, forKey: .dieRolls)
        mode = try c.decodeIfPresent(RollMode.self, forKey: .mode) ?? .normal
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        // Backwards-compat: pre-label history entries decode with no label.
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }

    var modifier: Int { formula.modifier }

    var total: Int {
        dieRolls.filter(\.isKept).map(\.value).reduce(0, +) + modifier
    }

    var hasCriticalSuccess: Bool { dieRolls.contains(where: \.isCriticalSuccess) }
    var hasCriticalFail:    Bool { dieRolls.contains(where: \.isCriticalFail) }
}
