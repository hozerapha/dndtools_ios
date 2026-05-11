import Foundation

/// What a tappable action costs on the character's turn. Informational in v1
/// (no per-turn enforcement); used to render an "Action / Bonus / Reaction"
/// chip on each row so the player can see their economy at a glance.
enum ActionCost: String, Codable, Equatable, CaseIterable {
    case action
    case bonusAction
    case reaction
    case free
    case movement

    /// Short label for the inline chip ("Action", "Bonus", etc.).
    var shortLabel: String {
        switch self {
        case .action:      return "Action"
        case .bonusAction: return "Bonus"
        case .reaction:    return "Reaction"
        case .free:        return "Free"
        case .movement:    return "Move"
        }
    }

    /// SF Symbol that hints at the cost type. Kept generic; the chip text
    /// carries the real semantics.
    var systemImage: String {
        switch self {
        case .action:      return "bolt.fill"
        case .bonusAction: return "bolt.badge.clock.fill"
        case .reaction:    return "arrow.uturn.backward.circle.fill"
        case .free:        return "infinity"
        case .movement:    return "figure.run"
        }
    }
}
