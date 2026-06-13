import Foundation

enum ActionInterpreter {
    /// `spellcastingAbility` is consulted by `.spellAttack` and by
    /// `.heal` / `.rawDamage` recipes flagged `addSpellcastingMod` (2024 Cure
    /// Wounds = 2d8 + mod, Divine Spark = 1d8 + WIS) — every other recipe
    /// ignores it. `fightingStyle` modifies weapon attack / damage rolls
    /// (Archery +2 ranged attack, Dueling +2 damage when single-wielding melee).
    /// Both default to nil so callers that don't care can keep the bare API.
    /// `skillCheckFloor`, when non-nil, is the minimum d20 value a skill
    /// check is treated as (Reliable Talent → 10). The caller computes it
    /// from the character's features via `CharacterCalculator.skillCheckFloor`
    /// (the interpreter has no content access); it only takes effect on
    /// skills the character is proficient in.
    static func resolve(
        recipe: ActionRecipe,
        character: Character,
        weapon: WeaponDefinition?,
        spellcastingAbility: Ability? = nil,
        fightingStyle: FightingStyleEffects? = nil,
        skillCheckFloor: Int? = nil
    ) -> ResolvedAction {
        switch recipe {
        case .weaponAttack(let abilityOverride, let finesse):
            return resolveWeaponAttack(
                character: character,
                weapon: weapon,
                abilityOverride: abilityOverride,
                finesse: finesse,
                fightingStyle: fightingStyle
            )

        case .weaponDamage(let dieOverride, let addAbility, let versatile):
            return resolveWeaponDamage(
                character: character,
                weapon: weapon,
                dieOverride: dieOverride,
                addAbility: addAbility,
                versatile: versatile,
                fightingStyle: fightingStyle
            )

        case .abilityCheck(let ability):
            return resolveAbilityCheck(character: character, ability: ability)

        case .skillCheck(let skill):
            return resolveSkillCheck(character: character, skill: skill, skillCheckFloor: skillCheckFloor)

        case .savingThrow(let ability):
            return resolveSavingThrow(character: character, ability: ability)

        case .saveDC(let ability):
            return resolveSaveDC(character: character, ability: ability)

        case .heal(let dice, let addLevel, let addSpellcastingMod, let label):
            return resolveHeal(
                character: character,
                dice: dice,
                addLevel: addLevel,
                spellcastingMod: addSpellcastingMod ? spellcastingMod(character, spellcastingAbility) : nil,
                label: label
            )

        case .rawDamage(let dice, let damageType, let addSpellcastingMod, let label):
            return resolveRawDamage(
                dice: dice,
                damageType: damageType,
                spellcastingMod: addSpellcastingMod ? spellcastingMod(character, spellcastingAbility) : nil,
                label: label
            )

        case .spellAttack(let label):
            return resolveSpellAttack(
                character: character,
                ability: spellcastingAbility,
                label: label
            )
        }
    }

    private static func resolveSpellAttack(
        character: Character,
        ability: Ability?,
        label: String
    ) -> ResolvedAction {
        // Without a spellcasting ability we have nothing to roll. Return a
        // no-formula action so the caller can tell there's nothing to do.
        guard let ability else {
            return ResolvedAction(
                id: "spell_attack_unresolved",
                label: label,
                formula: nil,
                description: nil
            )
        }
        let abilityMod = CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)
        let profBonus = CharacterCalculator.proficiencyBonus(level: character.level)
        let total = abilityMod + profBonus

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = total

        return ResolvedAction(
            id: "spell_attack_\(ability.rawValue)",
            label: "\(label) \(total >= 0 ? "+" : "")\(total)",
            formula: formula,
            description: "1d20 + \(ability.abbreviation) (\(abilityMod >= 0 ? "+" : "")\(abilityMod)) + Prof (\(profBonus))"
        )
    }

    private static func resolveRawDamage(
        dice: String,
        damageType: DamageType,
        spellcastingMod: Int? = nil,
        label: String
    ) -> ResolvedAction {
        // Spell formulas can carry inline modifiers ("3d4+3"). The simple
        // `parseDieString` helper only handles the bare "NdM" shape, so we
        // route through the existing dice-formula parser instead and fall
        // back to an empty formula if anything goes wrong.
        var formula = (try? DiceFormulaParser().parse(dice)) ?? DiceFormula()
        formula.applyDamageType(damageType)
        // Untyped flat is fine: when every group shares one damage type the
        // result breakdown attributes the modifier to that type anyway.
        if let mod = spellcastingMod {
            formula.modifier += mod
        }
        return ResolvedAction(
            id: "raw_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))",
            label: label,
            formula: formula,
            description: spellcastingMod.map { "\(dice) + spell mod (\($0 >= 0 ? "+" : "")\($0))" } ?? dice
        )
    }

    /// Caster's spellcasting ability modifier, or nil when the caller didn't
    /// supply an ability (the flag then degrades to a bare-dice roll rather
    /// than guessing a stat).
    private static func spellcastingMod(_ character: Character, _ ability: Ability?) -> Int? {
        guard let ability else { return nil }
        return CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)
    }

    // MARK: - Private helpers

    private static func resolveWeaponAttack(
        character: Character,
        weapon: WeaponDefinition?,
        abilityOverride: Ability?,
        finesse: Bool,
        fightingStyle: FightingStyleEffects?
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

        // Archery: +2 to attack rolls with ranged weapons (the SRD restricts
        // this to weapons with the ammunition property — bows, crossbows,
        // etc. — not thrown melee weapons).
        let archeryBonus: Int = {
            guard fightingStyle?.style == FeatureIDs.FightingStyle.archery,
                  let weapon, weapon.properties.contains(.ammunition)
            else { return 0 }
            return 2
        }()

        let totalBonus = abilityMod + (isProficient ? profBonus : 0) + archeryBonus

        var formula = DiceFormula()
        formula.add(.d20)
        formula.modifier = totalBonus

        let label = weapon?.name ?? "Attack"
        var desc = "1d20 + \(ability.abbreviation) (\(abilityMod >= 0 ? "+" : "")\(abilityMod))"
        if isProficient { desc += " + Prof (\(profBonus))" }
        if archeryBonus > 0 { desc += " + Archery (+\(archeryBonus))" }

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
        versatile: Bool,
        fightingStyle: FightingStyleEffects?
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
        let abilityContribution = addAbility ? abilityMod : 0

        // Dueling: +2 damage when wielding a melee weapon in one hand and no
        // other weapons. The "no other weapons" gate comes pre-computed in
        // `fightingStyle.onlyOneWeaponEquipped`. Versatile-2H (`versatile:true`)
        // and intrinsic two-handed weapons are excluded — Dueling only applies
        // to one-handed melee swings.
        let duelingBonus: Int = {
            guard fightingStyle?.style == FeatureIDs.FightingStyle.dueling,
                  fightingStyle?.onlyOneWeaponEquipped == true,
                  let weapon,
                  !weapon.properties.contains(.ammunition),
                  !weapon.properties.contains(.twoHanded),
                  !versatile
            else { return 0 }
            return 2
        }()

        let totalMod = abilityContribution + duelingBonus

        var formula = parseDieString(dieString, modifier: totalMod)
        if let dmgType = weapon?.damageType {
            formula.applyDamageType(dmgType)
        }
        let label = weapon?.name ?? "Damage"
        var desc = dieString
        if addAbility {
            desc += " + \(ability.abbreviation) (\(abilityContribution >= 0 ? "+" : "")\(abilityContribution))"
        }
        if duelingBonus > 0 {
            desc += " + Dueling (+\(duelingBonus))"
        }

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
        skill: Skill,
        skillCheckFloor: Int?
    ) -> ResolvedAction {
        let mod = CharacterCalculator.skillModifier(character: character, skill: skill)

        // The floor (Reliable Talent) only applies to skills you're
        // proficient in — feature-driven now, no class-name check here.
        let isProficient = character.proficiencies[.skill(skill)] == .proficient
            || character.proficiencies[.skill(skill)] == .expertise
        let floor = isProficient ? skillCheckFloor : nil

        var formula = DiceFormula()
        formula.groups.append(DiceGroup(
            kind: .d20,
            count: 1,
            minimumValue: floor
        ))
        formula.modifier = mod

        var description = "1d20 + \(skill.ability.abbreviation) (skill)"
        if let floor {
            description += " — floor \(floor)"
        }

        return ResolvedAction(
            id: "skill_\(skill.rawValue)",
            label: "\(skill.displayName) \(mod >= 0 ? "+" : "")\(mod)",
            formula: formula,
            description: description
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
        spellcastingMod: Int? = nil,
        label: String
    ) -> ResolvedAction {
        let modifier = (addLevel ? character.level : 0) + (spellcastingMod ?? 0)
        let formula = parseDieString(dice, modifier: modifier)

        var parts = [dice]
        if addLevel { parts.append("level (\(character.level))") }
        if let mod = spellcastingMod { parts.append("spell mod (\(mod >= 0 ? "+" : "")\(mod))") }

        return ResolvedAction(
            id: "heal_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))",
            label: label,
            formula: formula,
            description: parts.joined(separator: " + ")
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
