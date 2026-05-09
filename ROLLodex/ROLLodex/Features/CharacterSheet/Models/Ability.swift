import Foundation

enum Ability: String, Codable, CaseIterable, Identifiable, Hashable {
    case strength = "strength"
    case dexterity = "dexterity"
    case constitution = "constitution"
    case intelligence = "intelligence"
    case wisdom = "wisdom"
    case charisma = "charisma"

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .strength: return "STR"
        case .dexterity: return "DEX"
        case .constitution: return "CON"
        case .intelligence: return "INT"
        case .wisdom: return "WIS"
        case .charisma: return "CHA"
        }
    }
}
