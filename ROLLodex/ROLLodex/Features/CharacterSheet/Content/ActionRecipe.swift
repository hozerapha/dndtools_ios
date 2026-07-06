import Foundation

enum ActionRecipe: Codable, Equatable {
    case weaponAttack(abilityOverride: Ability?, finesse: Bool)
    case weaponDamage(dieOverride: String?, addAbility: Bool, versatile: Bool)
    case abilityCheck(ability: Ability)
    case skillCheck(skill: Skill)
    case savingThrow(ability: Ability)
    case saveDC(ability: Ability)
    /// `addSpellcastingMod` adds the caster's spellcasting ability modifier
    /// to the total (2024 Cure Wounds = 2d8 + mod, Divine Spark = 1d8 + WIS).
    /// Resolved at interpret time from the `spellcastingAbility` parameter.
    case heal(dice: String, addLevel: Bool, addSpellcastingMod: Bool, label: String)
    /// Self-contained damage formula — used by spells (Magic Missile 3d4+3,
    /// Sacred Flame 1d8, etc.) where the dice are part of the spell text
    /// rather than derived from a weapon. `damageType` is informational; the
    /// dice tab just rolls the formula. `addSpellcastingMod` mirrors `heal`'s.
    case rawDamage(dice: String, damageType: DamageType, addSpellcastingMod: Bool, label: String)
    /// Spell attack roll: d20 + spellcasting ability mod + proficiency. The
    /// caster's spellcasting ability is resolved at interpret time, not stored
    /// here, so this same recipe works for any caster.
    case spellAttack(label: String)
    /// Damage whose die COUNT and/or die SIZE scale with level. Count scaling:
    /// Dragonborn Breath Weapon (1d10 → 4d10). Die-size scaling: Monk Martial
    /// Arts (1d6 → 1d8 → 1d10 → 1d12) — `dieKind` is a `LevelScaledValue`
    /// whose values are die SIDES; bare-int JSON (`"dieKind": 10`) still
    /// decodes as a flat size. `damageType` optional (Breath Weapon takes its
    /// type from the Draconic Ancestry choice). `addAbility` adds that
    /// ability's modifier to the roll (Monk unarmed strike = die + DEX).
    case scaledDamage(dieKind: LevelScaledValue, count: LevelScaledValue, damageType: DamageType?, addAbility: Ability?, label: String)
    /// A flat dice roll plus a specific ability's modifier — Goliath Stone's
    /// Endurance (1d12 + Constitution). Distinct from `abilityCheck` (which is
    /// always a d20) and from `heal` (which adds level / spellcasting mod): the
    /// modifier is a fixed ability the recipe names. `addLevel` also adds the
    /// character level (Monk Deflect Attacks = 1d10 + DEX + monk level).
    /// Untyped (it's often a reduction or utility roll, not damage).
    case abilityRoll(dice: String, ability: Ability, addLevel: Bool, label: String)

    /// Pre-Monk shape without the level term.
    static func abilityRoll(dice: String, ability: Ability, label: String) -> ActionRecipe {
        .abilityRoll(dice: dice, ability: ability, addLevel: false, label: label)
    }

    /// Factory overloads preserving the pre-`addSpellcastingMod` call shape —
    /// existing Swift construction sites (tests, fixtures) keep compiling and
    /// default to no modifier, matching the old behavior.
    static func heal(dice: String, addLevel: Bool, label: String) -> ActionRecipe {
        .heal(dice: dice, addLevel: addLevel, addSpellcastingMod: false, label: label)
    }

    static func rawDamage(dice: String, damageType: DamageType, label: String) -> ActionRecipe {
        .rawDamage(dice: dice, damageType: damageType, addSpellcastingMod: false, label: label)
    }

    /// Pre-Monk shape: flat die size, no ability modifier.
    static func scaledDamage(dieKind: Int, count: LevelScaledValue, damageType: DamageType?, label: String) -> ActionRecipe {
        .scaledDamage(dieKind: .flat(dieKind), count: count, damageType: damageType, addAbility: nil, label: label)
    }
}

extension ActionRecipe {
    private enum CodingKeys: String, CodingKey {
        case type, abilityOverride, finesse, dieOverride, addAbility, versatile
        case ability, skill, dice, addLevel, label, damageType, addSpellcastingMod
        case dieKind, count
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
            let addMod = try container.decodeIfPresent(Bool.self, forKey: .addSpellcastingMod) ?? false
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Heal"
            self = .heal(dice: dice, addLevel: addLevel, addSpellcastingMod: addMod, label: label)

        case "rawDamage":
            let dice = try container.decode(String.self, forKey: .dice)
            let damageType = try container.decode(DamageType.self, forKey: .damageType)
            let addMod = try container.decodeIfPresent(Bool.self, forKey: .addSpellcastingMod) ?? false
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Damage"
            self = .rawDamage(dice: dice, damageType: damageType, addSpellcastingMod: addMod, label: label)

        case "spellAttack":
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Spell Attack"
            self = .spellAttack(label: label)

        case "scaledDamage":
            // LevelScaledValue decodes a bare int as `.flat`, so existing
            // `"dieKind": 10` content keeps working while Monk's Martial Arts
            // can write a byClassLevel table of die sizes.
            let dieKind = try container.decode(LevelScaledValue.self, forKey: .dieKind)
            let count = try container.decode(LevelScaledValue.self, forKey: .count)
            let damageType = try container.decodeIfPresent(DamageType.self, forKey: .damageType)
            let addAbility = try container.decodeIfPresent(Ability.self, forKey: .addAbility)
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Damage"
            self = .scaledDamage(dieKind: dieKind, count: count, damageType: damageType, addAbility: addAbility, label: label)

        case "abilityRoll":
            let dice = try container.decode(String.self, forKey: .dice)
            let ability = try container.decode(Ability.self, forKey: .ability)
            let addLevel = try container.decodeIfPresent(Bool.self, forKey: .addLevel) ?? false
            let label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Roll"
            self = .abilityRoll(dice: dice, ability: ability, addLevel: addLevel, label: label)

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

        case .heal(let dice, let addLevel, let addMod, let label):
            try container.encode("heal", forKey: .type)
            try container.encode(dice, forKey: .dice)
            try container.encode(addLevel, forKey: .addLevel)
            // Encode only when set so pre-existing content round-trips
            // byte-for-byte.
            if addMod { try container.encode(addMod, forKey: .addSpellcastingMod) }
            try container.encode(label, forKey: .label)

        case .rawDamage(let dice, let damageType, let addMod, let label):
            try container.encode("rawDamage", forKey: .type)
            try container.encode(dice, forKey: .dice)
            try container.encode(damageType, forKey: .damageType)
            if addMod { try container.encode(addMod, forKey: .addSpellcastingMod) }
            try container.encode(label, forKey: .label)

        case .spellAttack(let label):
            try container.encode("spellAttack", forKey: .type)
            try container.encode(label, forKey: .label)

        case .scaledDamage(let dieKind, let count, let damageType, let addAbility, let label):
            try container.encode("scaledDamage", forKey: .type)
            try container.encode(dieKind, forKey: .dieKind)
            try container.encode(count, forKey: .count)
            try container.encodeIfPresent(damageType, forKey: .damageType)
            try container.encodeIfPresent(addAbility, forKey: .addAbility)
            try container.encode(label, forKey: .label)

        case .abilityRoll(let dice, let ability, let addLevel, let label):
            try container.encode("abilityRoll", forKey: .type)
            try container.encode(dice, forKey: .dice)
            try container.encode(ability, forKey: .ability)
            if addLevel { try container.encode(addLevel, forKey: .addLevel) }
            try container.encode(label, forKey: .label)
        }
    }
}
