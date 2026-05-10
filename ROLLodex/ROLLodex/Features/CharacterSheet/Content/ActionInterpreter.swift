import Foundation

enum ActionInterpreter {
    static func resolve(
        recipe: ActionRecipe,
        character: Character,
        weapon: WeaponDefinition?
    ) -> ResolvedAction {
        switch recipe {
        case .weaponAttack(let abilityOverride, let finesse):
            return resolveWeaponAttack(
                character: character,
                weapon: weapon,
                abilityOverride: abilityOverride,
                finesse: finesse
            )

        case .weaponDamage(let dieOverride, let addAbility, let versatile):
            return resolveWeaponDamage(
                character: character,
                weapon: weapon,
                dieOverride: dieOverride,
                addAbility: addAbility,
                versatile: versatile
            )

        case .abilityCheck(let ability):
            return resolveAbilityCheck(character: character, ability: ability)

        case .skillCheck(let skill):
            return resolveSkillCheck(character: character, skill: skill)

        case .savingThrow(let ability):
            return resolveSavingThrow(character: character, ability: ability)

        case .saveDC(let ability):
            return resolveSaveDC(character: character, ability: ability)

        case .heal(let dice, let addLevel, let label):
            return resolveHeal(character: character, dice: dice, addLevel: addLevel, label: label)
        }
    }

    // MARK: - Private helpers

    private static func resolveWeaponAttack(
        character: Character,
        weapon: WeaponDefinition?,
        abilityOverride: Ability?,
        finesse: Bool
    ) -> ResolvedAction {
        let ability: Ability
        if let override = abilityOverride {
            ability = override
        } else if finesse {
            let strMod = CharacterCalculator.abilityModifier(score: character.abilityScores[.strength] ?? 10)
            let dexMod = CharacterCalculator.abilityModifier(score: character.abilityScores[.dexterity] ?? 10)
            ability = dexMod > strMod ? .dexterity : .strength
        } else {
            ability = .strength
        }

        let abilityMod = CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)

        let isProficient: Bool
        if let weapon = weapon {
            isProficient = character.proficiencies[.weapon(weapon.weaponCategory)] != nil
        } else {
            isProficient = false
        }

        let profBonus = CharacterCalculator.proficiencyBonus(level: character.level)
        let totalBonus = abilityMod + (isProficient ? profBonus : 0)

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = totalBonus

        let label = weapon?.name ?? "Attack"
        let desc = "1d20 + \(ability.abbreviation) (\(abilityMod >= 0 ? "+" : "")\(abilityMod))" +
                   (isProficient ? " + Prof (\(profBonus))" : "")

        return ResolvedAction(
            id: "weapon_\(weapon?.id ?? "attack")_attack",
            label: "\(label) Attack \(totalBonus >= 0 ? "+" : "")\(totalBonus)",
            formula: formula,
            description: desc
        )
    }

    private static func resolveWeaponDamage(
        character: Character,
        weapon: WeaponDefinition?,
        dieOverride: String?,
        addAbility: Bool,
        versatile: Bool
    ) -> ResolvedAction {
        let dieString: String
        if let override = dieOverride {
            dieString = override
        } else if let weapon = weapon {
            if versatile, let versatileDamage = weapon.versatileDamage {
                dieString = versatileDamage
            } else {
                dieString = weapon.damage
            }
        } else {
            dieString = "1d4"
        }

        let ability: Ability
        if weapon?.properties.contains(.finesse) == true {
            let strMod = CharacterCalculator.abilityModifier(score: character.abilityScores[.strength] ?? 10)
            let dexMod = CharacterCalculator.abilityModifier(score: character.abilityScores[.dexterity] ?? 10)
            ability = dexMod > strMod ? .dexterity : .strength
        } else {
            ability = weapon?.damageAbility ?? .strength
        }

        let abilityMod = CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)
        let totalMod = addAbility ? abilityMod : 0

        let formula = parseDieString(dieString, modifier: totalMod)
        let label = weapon?.name ?? "Damage"
        let desc = "\(dieString)" + (addAbility ? " + \(ability.abbreviation) (\(totalMod >= 0 ? "+" : "")\(totalMod))" : "")

        return ResolvedAction(
            id: "weapon_\(weapon?.id ?? "damage")_damage",
            label: "\(label) Damage",
            formula: formula,
            description: desc
        )
    }

    private static func resolveAbilityCheck(
        character: Character,
        ability: Ability
    ) -> ResolvedAction {
        let score = character.abilityScores[ability] ?? 10
        let mod = CharacterCalculator.abilityModifier(score: score)

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = mod

        return ResolvedAction(
            id: "ability_\(ability.rawValue)",
            label: "\(ability.rawValue.capitalized) Check \(mod >= 0 ? "+" : "")\(mod)",
            formula: formula,
            description: "1d20 + \(ability.abbreviation) (\(mod >= 0 ? "+" : "")\(mod))"
        )
    }

    private static func resolveSkillCheck(
        character: Character,
        skill: Skill
    ) -> ResolvedAction {
        let mod = CharacterCalculator.skillModifier(character: character, skill: skill)

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = mod

        return ResolvedAction(
            id: "skill_\(skill.rawValue)",
            label: "\(skill.displayName) \(mod >= 0 ? "+" : "")\(mod)",
            formula: formula,
            description: "1d20 + \(skill.ability.abbreviation) (skill)"
        )
    }

    private static func resolveSavingThrow(
        character: Character,
        ability: Ability
    ) -> ResolvedAction {
        let bonus = CharacterCalculator.saveBonus(character: character, ability: ability)

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = bonus

        return ResolvedAction(
            id: "save_\(ability.rawValue)",
            label: "\(ability.rawValue.capitalized) Save \(bonus >= 0 ? "+" : "")\(bonus)",
            formula: formula,
            description: "1d20 + \(ability.abbreviation) save"
        )
    }

    private static func resolveSaveDC(
        character: Character,
        ability: Ability
    ) -> ResolvedAction {
        let score = character.abilityScores[ability] ?? 10
        let abilityMod = CharacterCalculator.abilityModifier(score: score)
        let profBonus = CharacterCalculator.proficiencyBonus(level: character.level)
        let dc = 8 + abilityMod + profBonus

        return ResolvedAction(
            id: "dc_\(ability.rawValue)",
            label: "\(ability.rawValue.capitalized) Save DC \(dc)",
            formula: nil,
            description: "8 + \(ability.abbreviation) (\(abilityMod >= 0 ? "+" : "")\(abilityMod)) + Prof (\(profBonus))"
        )
    }

    private static func resolveHeal(
        character: Character,
        dice: String,
        addLevel: Bool,
        label: String
    ) -> ResolvedAction {
        let formula = parseDieString(dice, modifier: addLevel ? character.level : 0)

        return ResolvedAction(
            id: "heal_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))",
            label: label,
            formula: formula,
            description: addLevel ? "\(dice) + level (\(character.level))" : dice
        )
    }

    // MARK: - Die string parser

    private static func parseDieString(_ dieString: String, modifier: Int) -> DiceFormula {
        var formula = DiceFormula()

        // Expect format like "1d8", "2d6", or just a number
        let components = dieString.split(separator: "d")
        if components.count == 2,
           let count = Int(components[0]),
           let sides = Int(components[1]),
           let kind = DieKind(rawValue: sides) {
            formula.groups.append(DiceGroup(kind: kind, count: count))
        }

        formula.modifier = modifier
        return formula
    }
}
