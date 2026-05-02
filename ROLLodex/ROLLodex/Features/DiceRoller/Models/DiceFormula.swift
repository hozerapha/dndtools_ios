import Foundation

struct DiceFormula: Codable, Hashable {
    var counts: [DieKind: Int] = [:]
    var modifier: Int = 0

    var totalDiceCount: Int {
        counts.values.reduce(0, +)
    }

    var isEmpty: Bool {
        totalDiceCount == 0 && modifier == 0
    }

    var supportsAdvantage: Bool {
        totalDiceCount == 1 && counts[.d20, default: 0] == 1
    }

    mutating func add(_ kind: DieKind) {
        counts[kind, default: 0] += 1
    }

    mutating func remove(_ kind: DieKind) {
        let current = counts[kind, default: 0]
        if current <= 1 {
            counts.removeValue(forKey: kind)
        } else {
            counts[kind] = current - 1
        }
    }

    mutating func clear() {
        counts.removeAll()
        modifier = 0
    }

    var displayString: String {
        let diceParts: [String] = DieKind.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(count)\(kind.label)"
        }

        var result = diceParts.joined(separator: " + ")
        if result.isEmpty { result = "—" }

        if modifier > 0 {
            result += " + \(modifier)"
        } else if modifier < 0 {
            result += " − \(abs(modifier))"
        }
        return result
    }
}
