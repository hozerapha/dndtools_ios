import Foundation

enum SpellSchool: String, Codable, CaseIterable {
    case abjuration
    case conjuration
    case divination
    case enchantment
    case evocation
    case illusion
    case necromancy
    case transmutation

    var displayName: String { rawValue.capitalized }

    /// SF Symbol used by the spell list row icon. Lightweight visual cue so
    /// the player can scan their list without reading every name.
    var systemImage: String {
        switch self {
        case .abjuration:    return "shield.lefthalf.filled"
        case .conjuration:   return "sparkles"
        case .divination:    return "eye.fill"
        case .enchantment:   return "heart.text.square"
        case .evocation:     return "burst.fill"
        case .illusion:      return "theatermasks.fill"
        case .necromancy:    return "moon.stars.fill"
        case .transmutation: return "arrow.triangle.2.circlepath"
        }
    }
}
