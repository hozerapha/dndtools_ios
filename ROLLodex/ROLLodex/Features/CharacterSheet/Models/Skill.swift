import Foundation

enum Skill: String, Codable, CaseIterable, Identifiable, Hashable {
    case acrobatics = "acrobatics"
    case animalHandling = "animal_handling"
    case arcana = "arcana"
    case athletics = "athletics"
    case deception = "deception"
    case history = "history"
    case insight = "insight"
    case intimidation = "intimidation"
    case investigation = "investigation"
    case medicine = "medicine"
    case nature = "nature"
    case perception = "perception"
    case performance = "performance"
    case persuasion = "persuasion"
    case religion = "religion"
    case sleightOfHand = "sleight_of_hand"
    case stealth = "stealth"
    case survival = "survival"

    var id: String { rawValue }

    var ability: Ability {
        switch self {
        case .acrobatics: return .dexterity
        case .animalHandling: return .wisdom
        case .arcana: return .intelligence
        case .athletics: return .strength
        case .deception: return .charisma
        case .history: return .intelligence
        case .insight: return .wisdom
        case .intimidation: return .charisma
        case .investigation: return .intelligence
        case .medicine: return .wisdom
        case .nature: return .intelligence
        case .perception: return .wisdom
        case .performance: return .charisma
        case .persuasion: return .charisma
        case .religion: return .intelligence
        case .sleightOfHand: return .dexterity
        case .stealth: return .dexterity
        case .survival: return .wisdom
        }
    }

    var displayName: String {
        switch self {
        case .acrobatics: return "Acrobatics"
        case .animalHandling: return "Animal Handling"
        case .arcana: return "Arcana"
        case .athletics: return "Athletics"
        case .deception: return "Deception"
        case .history: return "History"
        case .insight: return "Insight"
        case .intimidation: return "Intimidation"
        case .investigation: return "Investigation"
        case .medicine: return "Medicine"
        case .nature: return "Nature"
        case .perception: return "Perception"
        case .performance: return "Performance"
        case .persuasion: return "Persuasion"
        case .religion: return "Religion"
        case .sleightOfHand: return "Sleight of Hand"
        case .stealth: return "Stealth"
        case .survival: return "Survival"
        }
    }
}
