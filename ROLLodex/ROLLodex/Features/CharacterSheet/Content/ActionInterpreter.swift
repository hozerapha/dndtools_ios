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
        skillCheckFloor: Int? = nil,
        jackOfAllTrades: Bool = false
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
            return resolveSkillCheck(character: character, skill: skill, skillCheckFloor: skillCheckFloor, jackOfAllTrades: jackOfAllTrades)

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

        case .scaledDamage(let dieKind, let count, let damageType, let addAbility, let label):
            return resolveScaledDamage(
                character: character,
                dieKind: dieKind,
                count: count,
                damageType: damageType,
                addAbility: addAbility,
                label: label
            )

        case .abilityRoll(let dice, let ability, let addLevel, let label):
            return resolveAbilityRoll(character: character, dice: dice, ability: ability, addLevel: addLevel, label: label)
        }
    }

    private static func resolveAbilityRoll(
        character: Character,
        dice: String,
        ability: Ability,
        addLevel: Bool,
        label: String
    ) -> ResolvedAction {
        let mod = CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)
        let total = mod + (addLevel ? character.level : 0)
        var formula = (try? DiceFormulaParser().parse(dice)) ?? DiceFormula()
        formula.modifier += total
        let sign = total >= 0 ? "+" : ""
        var desc = "\(dice) + \(ability.abbreviation) (\(mod >= 0 ? "+" : "")\(mod))"
        if addLevel { desc += " + level (\(character.level))" }
        return ResolvedAction(
            id: "abilityroll_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))",
            label: "\(label) (\(dice) \(sign)\(total))",
            formula: formula,
            description: desc
        )
    }

    private static func resolveScaledDamage(
        character: Character,
        dieKind: LevelScaledValue,
        count: LevelScaledValue,
        damageType: DamageType?,
        addAbility: Ability?,
        label: String
    ) -> ResolvedAction {
        // Single-class assumption: character level stands in for class level
        // (matches the existing count scaling; a multiclass monk's Martial
        // Arts die runs slightly hot — flagged in the plan).
        let sides = dieKind.value(classLevel: character.level, characterLevel: character.level)
        let n = count.value(classLevel: character.level, characterLevel: character.level)
        var formula = DiceFormula()
        if let kind = DieKind(rawValue: sides), n > 0 {
            formula.groups.append(DiceGroup(kind: kind, count: n))
            if let damageType { formula.applyDamageType(damageType) }
        }
        var desc = "\(n)d\(sides)"
        if let addAbility {
            let mod = CharacterCalculator.abilityModifier(score: character.abilityScores[addAbility] ?? 10)
            formula.modifier += mod
            desc += " + \(addAbility.abbreviation) (\(mod >= 0 ? "+" : "")\(mod))"
        }
        return ResolvedAction(
            id: "scaled_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))",
            label: "\(label) (\(desc))",
            formula: formula,
            description: desc
        )
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
        // Fill (don't overwrite): an inline `[type]` prefix in the recipe dice
        // wins over the recipe's default damage type.
        formula.fillDamageType(damageType)
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
            // No weapon = an unarmed strike; 5e (2024) makes everyone
            // proficient with those, so the attack always adds PB.
            isProficient = true
        }

        let profBonus = CharacterCalculator.proficiencyBonus(level: character.level)

        // Archery: +2 to attack rolls with ranged weapons (the SRD restricts
        // this to weapons with the ammunition property — bows, crossbows,
        // etc. — not thrown melee weapons).
        let archeryBonus: Int = {
            guard fightingStyle?.has(FeatureIDs.FightingStyle.archery) == true,
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

        let isMelee = !(weapon?.properties.contains(.ammunition) ?? false)
        let isTwoHandedSwing = (weapon?.properties.contains(.twoHanded) ?? false) || versatile

        // Two-Weapon Fighting: the off-hand (Light-weapon) attack normally omits
        // your ability modifier — TWF adds it back. We model an off-hand recipe
        // as `addAbility: false`; with TWF active on a Light melee weapon, the
        // mod is restored. (Until off-hand attacks are generated separately this
        // only fires for recipes that explicitly drop the mod.)
        let twfRestoresMod = !addAbility
            && fightingStyle?.has(FeatureIDs.FightingStyle.twoWeaponFighting) == true
            && isMelee
            && (weapon?.properties.contains(.light) ?? false)
        let abilityContribution = (addAbility || twfRestoresMod) ? abilityMod : 0

        // Dueling: +2 damage when wielding a melee weapon in one hand and no
        // other weapons. The "no other weapons" gate comes pre-computed in
        // `fightingStyle.onlyOneWeaponEquipped`. Versatile-2H (`versatile:true`)
        // and intrinsic two-handed weapons are excluded — Dueling only applies
        // to one-handed melee swings.
        let duelingBonus: Int = {
            guard fightingStyle?.has(FeatureIDs.FightingStyle.dueling) == true,
                  fightingStyle?.onlyOneWeaponEquipped == true,
                  let weapon,
                  !weapon.properties.contains(.ammunition),
                  !weapon.properties.contains(.twoHanded),
                  !versatile
            else { return 0 }
            return 2
        }()

        // Great Weapon Fighting: reroll 1s and 2s on the damage dice of a melee
        // weapon wielded with two hands (two-handed or versatile-used-2H).
        // Implemented as a per-die `rerollOnceIfAtMost(2)` on the weapon dice.
        let greatWeaponFighting = fightingStyle?.has(FeatureIDs.FightingStyle.greatWeaponFighting) == true
            && isMelee && isTwoHandedSwing

        let totalMod = abilityContribution + duelingBonus

        // Route through the full parser so weapon dice with inline modifiers or
        // typed prefixes ("1d8+2", "[fire]1d6") work, not just bare "NdM".
        // Fall back to an empty formula if a homebrew string is unparseable.
        var formula = (try? DiceFormulaParser().parse(dieString)) ?? DiceFormula()
        formula.modifier += totalMod
        if greatWeaponFighting {
            // Only stamp the reroll onto plain weapon dice — don't clobber a
            // homebrew group that already carries a keep/drop modifier.
            for i in formula.groups.indices where formula.groups[i].isPlain {
                formula.groups[i].modifier = .rerollOnceIfAtMost(2)
            }
        }
        if let dmgType = weapon?.damageType {
            formula.fillDamageType(dmgType)
        }
        let label = weapon?.name ?? "Damage"
        var desc = dieString
        if addAbility || twfRestoresMod {
            desc += " + \(ability.abbreviation) (\(abilityContribution >= 0 ? "+" : "")\(abilityContribution))"
        }
        if twfRestoresMod {
            desc += " [Two-Weapon Fighting]"
        }
        if duelingBonus > 0 {
            desc += " + Dueling (+\(duelingBonus))"
        }
        if greatWeaponFighting {
            desc += " (reroll 1-2)"
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
        skillCheckFloor: Int?,
        jackOfAllTrades: Bool
    ) -> ResolvedAction {
        let mod = CharacterCalculator.skillModifier(
            character: character, skill: skill, jackOfAllTrades: jackOfAllTrades
        )

        // The floor (Reliable Talent) only applies to skills you're proficient
        // in. Resolve via the calculator so proficiency from a class-skill
        // selection (stored in featureSelections, not the proficiencies dict)
        // counts too — same content-free source of truth the skills table uses.
        let isProficient = CharacterCalculator.skillProficiencyLevel(
            character: character, skill: skill
        ) != .none
        let floor = isProficient ? skillCheckFloor : nil

        var formula = DiceFormula()
        formula.groups.append(DiceGroup(
            kind: .d20,
            count: 1,
            minimumValue: floor
        ))
        formula.modifier = mod

        // Jack of All Trades only contributes when not proficient (its half-PB
        // never stacks on a proficient skill), so note it where it applies.
        let joatApplies = jackOfAllTrades && !isProficient
        var description = "1d20 + \(skill.ability.abbreviation) (skill)"
        if joatApplies {
            description += " — incl. Jack of All Trades"
        }
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
