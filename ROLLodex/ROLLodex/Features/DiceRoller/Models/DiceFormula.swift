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

    /// Untyped dice notation — `1d8`, `2d20kh1`. Round-trips through
    /// `DiceFormulaParser` so it's safe to surface in the editable formula bar.
    var displayString: String {
        let base = "\(count)\(kind.label)"
        return base + (modifier?.suffix ?? "")
    }

    /// Dice notation with the damage type appended (`1d10 fire`) when present.
    /// Used by display-only surfaces (tray HUD, history) — never feed this back
    /// into `DiceFormulaParser`, which doesn't recognize the type token.
    var displayStringWithType: String {
        guard let damageType else { return displayString }
        return "\(displayString) \(damageType.rawValue)"
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
    var modifier: Int = 0

    var totalDiceCount: Int {
        groups.map(\.count).reduce(0, +)
    }

    var isEmpty: Bool {
        groups.isEmpty && modifier == 0
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
    }

    var displayString: String {
        var result = groups.map(\.displayString).joined(separator: " + ")
        if result.isEmpty { result = "—" }
        if modifier > 0 {
            result += " + \(modifier)"
        } else if modifier < 0 {
            result += " − \(abs(modifier))"
        }
        return result
    }

    /// Like `displayString`, but each group prints with its damage type when set.
    /// Display-only — see `DiceGroup.displayStringWithType`.
    var displayStringWithTypes: String {
        var result = groups.map(\.displayStringWithType).joined(separator: " + ")
        if result.isEmpty { result = "—" }
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
