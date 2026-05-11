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

    /// Per-damage-type subtotals, derived by mapping each kept die back to its
    /// source `DiceGroup`. Untyped groups bucket under `nil`. The flat formula
    /// modifier (the trailing `+3`) attaches to the formula's single damage
    /// type when every group shares one — that keeps a longsword swing
    /// `1d8+3 slashing` reading as one slashing total instead of splitting the
    /// STR bonus out. Mixed-type or partly-untyped formulas push the flat
    /// modifier under `nil`.
    var subtotalsByType: [DamageType?: Int] {
        var totals: [DamageType?: Int] = [:]

        // dieRolls is laid out in formula-group order: each group contributes
        // `count` dice, except the single d20 adv/dis case which doubles up.
        let advDoubled = mode != .normal && formula.supportsAdvantage
        var cursor = 0
        for group in formula.groups {
            let isAdvGroup =
                advDoubled && group.kind == .d20 && group.count == 1 && group.isPlain
            let consumed = isAdvGroup ? 2 : group.count
            let endIndex = min(cursor + consumed, dieRolls.count)
            let groupTotal = dieRolls[cursor..<endIndex]
                .filter(\.isKept)
                .map(\.value)
                .reduce(0, +)
            totals[group.damageType, default: 0] += groupTotal
            cursor = endIndex
        }

        // Attribute the flat modifier to the formula's lone damage type when
        // every group shares one; otherwise it's untyped.
        if modifier != 0 {
            let types = formula.groups.map(\.damageType)
            if let first = types.first, types.allSatisfy({ $0 == first }), let onlyType = first {
                totals[onlyType, default: 0] += modifier
            } else {
                totals[nil, default: 0] += modifier
            }
        }

        return totals.filter { $0.value != 0 }
    }

    /// True when the result has at least one typed damage bucket. The HUD/
    /// history surfaces only check this before rendering a breakdown chip.
    var hasTypedDamage: Bool {
        subtotalsByType.keys.contains { $0 != nil }
    }
}
