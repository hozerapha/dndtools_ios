import Foundation

// `nonisolated`: pure data key — its Hashable/Codable conformances are used
// in nonisolated contexts (default arguments, background encodes) despite the
// target's MainActor default isolation.
nonisolated enum ProficiencyKey: Hashable {
    case savingThrow(Ability)
    case skill(Skill)
    case armor(ArmorCategory)
    case weapon(WeaponCategory)
    case tool(String)
}

extension ProficiencyKey: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = Self.decode(from: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ProficiencyKey: \(raw)"
            )
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodeToString())
    }
}

extension ProficiencyKey {
    static func decode(from string: String) -> ProficiencyKey? {
        let parts = string.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let type = String(parts[0])
        let value = String(parts[1])

        switch type {
        case "savingThrow":
            guard let ability = Ability(rawValue: value) else { return nil }
            return .savingThrow(ability)
        case "skill":
            guard let skill = Skill(rawValue: value) else { return nil }
            return .skill(skill)
        case "armor":
            guard let armor = ArmorCategory(rawValue: value) else { return nil }
            return .armor(armor)
        case "weapon":
            guard let weapon = WeaponCategory(rawValue: value) else { return nil }
            return .weapon(weapon)
        case "tool":
            return .tool(value)
        default:
            return nil
        }
    }

    func encodeToString() -> String {
        switch self {
        case .savingThrow(let ability):
            return "savingThrow_\(ability.rawValue)"
        case .skill(let skill):
            return "skill_\(skill.rawValue)"
        case .armor(let category):
            return "armor_\(category.rawValue)"
        case .weapon(let category):
            return "weapon_\(category.rawValue)"
        case .tool(let name):
            return "tool_\(name)"
        }
    }
}
