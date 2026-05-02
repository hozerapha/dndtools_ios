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

    init(id: UUID = UUID(), kind: DieKind, count: Int, modifier: GroupModifier? = nil) {
        self.id = id
        self.kind = kind
        self.count = count
        self.modifier = modifier
    }

    var isPlain: Bool { modifier == nil }

    var displayString: String {
        let base = "\(count)\(kind.label)"
        return base + (modifier?.suffix ?? "")
    }
}

// Equality / Hashable ignore `id` — two groups are "the same" if their dice/modifier match,
// regardless of UUID. UUIDs are for SwiftUI identity only.
extension DiceGroup: Hashable {
    static func == (lhs: DiceGroup, rhs: DiceGroup) -> Bool {
        lhs.kind == rhs.kind && lhs.count == rhs.count && lhs.modifier == rhs.modifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(count)
        hasher.combine(modifier)
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
}
