import Foundation

struct BackgroundDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let abilityScoreIncreases: [Ability: Int]
    let skillProficiencies: [Skill]
    let feat: String?
    let toolProficiency: String?
    let equipment: [String]
}

// MARK: - Custom Codable for [Ability: Int] dictionary

extension BackgroundDefinition {
    private enum CodingKeys: String, CodingKey {
        case id, name, abilityScoreIncreases, skillProficiencies, feat, toolProficiency, equipment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        skillProficiencies = try container.decode([Skill].self, forKey: .skillProficiencies)
        feat = try container.decodeIfPresent(String.self, forKey: .feat)
        toolProficiency = try container.decodeIfPresent(String.self, forKey: .toolProficiency)
        equipment = try container.decode([String].self, forKey: .equipment)

        let rawDict = try container.decode([String: Int].self, forKey: .abilityScoreIncreases)
        abilityScoreIncreases = Dictionary(uniqueKeysWithValues: rawDict.compactMap { key, value in
            guard let ability = Ability(rawValue: key) else { return nil }
            return (ability, value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(skillProficiencies, forKey: .skillProficiencies)
        try container.encodeIfPresent(feat, forKey: .feat)
        try container.encodeIfPresent(toolProficiency, forKey: .toolProficiency)
        try container.encode(equipment, forKey: .equipment)

        let rawDict = Dictionary(uniqueKeysWithValues: abilityScoreIncreases.map { ($0.rawValue, $1) })
        try container.encode(rawDict, forKey: .abilityScoreIncreases)
    }
}
