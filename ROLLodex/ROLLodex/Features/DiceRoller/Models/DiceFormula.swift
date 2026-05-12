import Foundation

enum GroupModifier: Codable, Hashable {
    case keepHighest(Int)
    case keepLowest(Int)
    case dropHighest(Int)
    case dropLowest(Int)
    case rerollOnceIfAtMost(Int)

    var suffix: String {
        switch self {
        case .keepHighest(let n):       "kh\(n)"
        case .keepLowest(let n):        "kl\(n)"
        case .dropHighest(let n):       "dh\(n)"
        case .dropLowest(let n):        "dl\(n)"
        case .rerollOnceIfAtMost(let n): "r\(n)"
        }
    }
}

struct DiceGroup: Identifiable, Codable {
    var id: UUID
    var kind: DieKind
    var count: Int
    var modifier: GroupModifier?
    /// Optional 5e damage type for this group's dice (slashing, fire, necrotic, …).
    /// Nil for non-damage rolls (ability checks, saves, manual tray rolls). When
    /// multiple groups in a formula carry different types, the result HUD surfaces
    /// a per-type breakdown so e.g. Eldritch Smite reads "8 slashing · 6 radiant"
    /// instead of one anonymous total.
    var damageType: DamageType?

    init(
        id: UUID = UUID(),
        kind: DieKind,
        count: Int,
        modifier: GroupModifier? = nil,
        damageType: DamageType? = nil
    ) {
        self.id = id
        self.kind = kind
        self.count = count
        self.modifier = modifier
        self.damageType = damageType
    }

    var isPlain: Bool { modifier == nil }

    /// Dice notation with optional `[damageType]` prefix — `1d8`, `[fire]2d6`,
    /// `2d20kh1`, `[slashing]1d8`. Round-trips through `DiceFormulaParser`, so
    /// the formula bar can show typed groups and have the parser read them
    /// back identically.
    var displayString: String {
        let prefix = damageType.map { "[\($0.rawValue)]" } ?? ""
        let base = "\(count)\(kind.label)"
        return prefix + base + (modifier?.suffix ?? "")
    }
}

// Equality / Hashable ignore `id` — two groups are "the same" if their dice/modifier/type match,
// regardless of UUID. UUIDs are for SwiftUI identity only.
extension DiceGroup: Hashable {
    static func == (lhs: DiceGroup, rhs: DiceGroup) -> Bool {
        lhs.kind == rhs.kind
            && lhs.count == rhs.count
            && lhs.modifier == rhs.modifier
            && lhs.damageType == rhs.damageType
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(count)
        hasher.combine(modifier)
        hasher.combine(damageType)
    }
}

struct DiceFormula: Codable, Hashable {
    var groups: [DiceGroup] = []
    /// Untyped flat modifier — the trailing `+ 3` in `1d8 + 3`.
    var modifier: Int = 0
    /// Flat modifiers carrying a damage type, e.g. the `+5 force` half of
    /// `[force]1d12 + [force]5 + [necrotic]1d6`. Keyed by type; values can be
    /// negative if the user typed a `-`. Empty for untyped formulas. Zero
    /// entries are pruned so a "fire: 0" key never lingers after edits.
    var typedModifiers: [DamageType: Int] = [:]

    init(
        groups: [DiceGroup] = [],
        modifier: Int = 0,
        typedModifiers: [DamageType: Int] = [:]
    ) {
        self.groups = groups
        self.modifier = modifier
        self.typedModifiers = typedModifiers
    }

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case groups, modifier, typedModifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.groups = try c.decodeIfPresent([DiceGroup].self, forKey: .groups) ?? []
        self.modifier = try c.decodeIfPresent(Int.self, forKey: .modifier) ?? 0
        // Pre-typed-modifiers formulas (any preset / history entry saved before
        // this field existed) decode with an empty dict instead of crashing.
        self.typedModifiers = try c.decodeIfPresent([DamageType: Int].self, forKey: .typedModifiers) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groups, forKey: .groups)
        try c.encode(modifier, forKey: .modifier)
        if !typedModifiers.isEmpty {
            try c.encode(typedModifiers, forKey: .typedModifiers)
        }
    }

    var totalDiceCount: Int {
        groups.map(\.count).reduce(0, +)
    }

    var isEmpty: Bool {
        groups.isEmpty && modifier == 0 && typedModifiers.isEmpty
    }

    /// Adv/dis only makes sense for exactly one plain d20.
    var supportsAdvantage: Bool {
        groups.count == 1
            && groups[0].kind == .d20
            && groups[0].count == 1
            && groups[0].isPlain
    }

    /// If the formula encodes a 5e advantage / disadvantage roll
    /// (`2d20kh1` / `2d20kl1`) returns the matching mode; otherwise `nil`.
    /// Used by the history sheet to decorate labels with "(adv)" / "(dis)".
    var encodedAdvantageMode: RollMode? {
        for group in groups where group.kind == .d20 && group.count == 2 {
            switch group.modifier {
            case .keepHighest(1): return .advantage
            case .keepLowest(1):  return .disadvantage
            default: continue
            }
        }
        return nil
    }

    /// Total count of dice of the given kind, summed across all groups (any modifier).
    func count(of kind: DieKind) -> Int {
        groups.filter { $0.kind == kind }.map(\.count).reduce(0, +)
    }

    /// Picker increment: bumps the first group of `kind` (any modifier), or creates a plain group.
    mutating func add(_ kind: DieKind) {
        if let i = groups.firstIndex(where: { $0.kind == kind }) {
            groups[i].count += 1
        } else {
            groups.append(DiceGroup(kind: kind, count: 1))
        }
    }

    /// Picker decrement: drops one from the first group of `kind` (any modifier).
    mutating func remove(_ kind: DieKind) {
        guard let i = groups.firstIndex(where: { $0.kind == kind }) else { return }
        if groups[i].count <= 1 {
            groups.remove(at: i)
        } else {
            groups[i].count -= 1
        }
    }

    mutating func clear() {
        groups.removeAll()
        modifier = 0
        typedModifiers.removeAll()
    }

    var displayString: String {
        var parts = groups.map(\.displayString)
        let sortedTypes = typedModifiers.keys.sorted(by: { $0.rawValue < $1.rawValue })
        // Positive typed modifiers join into the "+"-separated leading run so
        // they read naturally next to their dice groups.
        for type in sortedTypes {
            guard let value = typedModifiers[type], value > 0 else { continue }
            parts.append("[\(type.rawValue)]\(value)")
        }
        var result = parts.joined(separator: " + ")
        if result.isEmpty { result = "—" }
        // Negative typed modifiers tack on as " − [type]N" so the parser can
        // tell them apart from a "+"-sign separator (avoids a "+ −" pair).
        for type in sortedTypes {
            guard let value = typedModifiers[type], value < 0 else { continue }
            result += " − [\(type.rawValue)]\(abs(value))"
        }
        if modifier > 0 {
            result += " + \(modifier)"
        } else if modifier < 0 {
            result += " − \(abs(modifier))"
        }
        return result
    }

    /// Stamp `type` onto every group in the formula. Used by the action
    /// interpreter to apply a recipe's damage type (the weapon's or the spell
    /// recipe's) onto the parsed dice groups in one step.
    mutating func applyDamageType(_ type: DamageType) {
        for i in groups.indices {
            groups[i].damageType = type
        }
    }
}
