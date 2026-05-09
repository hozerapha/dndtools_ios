import Foundation

enum ActionRecipe: Codable, Equatable {
    case weaponAttack(abilityOverride: Ability?, finesse: Bool)
    case weaponDamage(dieOverride: String?, addAbility: Bool, versatile: Bool)
    case abilityCheck(ability: Ability)
    case skillCheck(skill: Skill)
    case savingThrow(ability: Ability)
    case saveDC(ability: Ability)
    case heal(dice: String, addLevel: Bool, label: String)
}

extension ActionRecipe {
    private enum CodingKeys: String, CodingKey {
        case type, abilityOverride, finesse, dieOverride, addAbility, versatile
        case ability, skill, dice, addLevel, label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "weaponAttack":
            let abilityOverride = try container.decodeIfPresent(Ability.self, forKey: .abilityOverride)
            let finesse = try container.decodeIfPresent(Bool.self, forKey: .finesse) ?? false
            self = .weaponAttack(abilityOverride: abilityOverride, finesse: finesse)

        case "weaponDamage":
            let dieOverride = try container.decodeIfPresent(String.self, forKey: .dieOverride)
            let addAbility = try container.decodeIfPresent(Bool.self, forKey: .addAbility) ?? true
            let versatile = try container.decodeIfPresent(Bool.self, forKey: .versatile) ?? false
            self = .weaponDamage(dieOverride: dieOverride, addAbility: addAbility, versatile: versatile)

        case "abilityCheck":
            let ability = try container.decode(Ability.self, forKey: .ability)
            self = .abilityCheck(ability: ability)

        case "skillCheck":
            let skill = try container.decode(Skill.self, forKey: .skill)
            self = .skillCheck(skill: skill)

        case "savingThrow":
            let ability = try container.decode(Ability.self, forKey: .ability)
            self = .savingThrow(ability: ability)

        case "saveDC":
            let ability = try container.decode(Ability.self, forKey: .ability)
            self = .saveDC(ability: ability)

        case "heal":
            let dice = try container.decode(String.self, forKey: .dice)
            let addLevel = try container.decodeIfPresent(Bool.self, forKey: .addLevel) ?? false
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Heal"
            self = .heal(dice: dice, addLevel: addLevel, label: label)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ActionRecipe type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .weaponAttack(let abilityOverride, let finesse):
            try container.encode("weaponAttack", forKey: .type)
            try container.encodeIfPresent(abilityOverride, forKey: .abilityOverride)
            try container.encode(finesse, forKey: .finesse)

        case .weaponDamage(let dieOverride, let addAbility, let versatile):
            try container.encode("weaponDamage", forKey: .type)
            try container.encodeIfPresent(dieOverride, forKey: .dieOverride)
            try container.encode(addAbility, forKey: .addAbility)
            try container.encode(versatile, forKey: .versatile)

        case .abilityCheck(let ability):
            try container.encode("abilityCheck", forKey: .type)
            try container.encode(ability, forKey: .ability)

        case .skillCheck(let skill):
            try container.encode("skillCheck", forKey: .type)
            try container.encode(skill, forKey: .skill)

        case .savingThrow(let ability):
            try container.encode("savingThrow", forKey: .type)
            try container.encode(ability, forKey: .ability)

        case .saveDC(let ability):
            try container.encode("saveDC", forKey: .type)
            try container.encode(ability, forKey: .ability)

        case .heal(let dice, let addLevel, let label):
            try container.encode("heal", forKey: .type)
            try container.encode(dice, forKey: .dice)
            try container.encode(addLevel, forKey: .addLevel)
            try container.encode(label, forKey: .label)
        }
    }
}
