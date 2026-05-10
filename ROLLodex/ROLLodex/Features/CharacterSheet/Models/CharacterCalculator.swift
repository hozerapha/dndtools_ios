import Foundation

enum CharacterCalculator {
    static func abilityModifier(score: Int) -> Int {
        (score - 10) / 2
    }

    static func proficiencyBonus(level: Int) -> Int {
        (level - 1) / 4 + 2
    }

    static func skillModifier(
        character: Character,
        skill: Skill
    ) -> Int {
        let ability = skill.ability
        let score = character.abilityScores[ability] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profLevel = character.proficiencies[.skill(skill)] ?? .none
        let profBonus = proficiencyBonus(level: character.level)

        switch profLevel {
        case .none:
            return abilityMod
        case .proficient:
            return abilityMod + profBonus
        case .expertise:
            return abilityMod + (profBonus * 2)
        }
    }

    static func saveBonus(
        character: Character,
        ability: Ability
    ) -> Int {
        let score = character.abilityScores[ability] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profLevel = character.proficiencies[.savingThrow(ability)] ?? .none
        let profBonus = proficiencyBonus(level: character.level)

        switch profLevel {
        case .none:       return abilityMod
        case .proficient: return abilityMod + profBonus
        case .expertise:  return abilityMod + (profBonus * 2)
        }
    }

    static func armorClass(
        dexMod: Int,
        armor: ArmorDefinition?,
        hasShield: Bool
    ) -> Int {
        let base: Int
        if let armor = armor {
            let dexContribution: Int
            if let cap = armor.dexCap {
                dexContribution = min(dexMod, cap)
            } else {
                dexContribution = dexMod // No cap = full Dex mod (light armor)
            }
            base = armor.acBase + dexContribution
        } else {
            base = 10 + dexMod
        }

        let shieldBonus = hasShield ? 2 : 0
        return base + shieldBonus
    }

    static func initiativeBonus(character: Character) -> Int {
        let dexScore = character.abilityScores[.dexterity] ?? 10
        return abilityModifier(score: dexScore)
    }

    static func passivePerception(character: Character) -> Int {
        10 + skillModifier(character: character, skill: .perception)
    }

    static func spellSaveDC(
        character: Character,
        spellcastingAbility: Ability
    ) -> Int {
        let score = character.abilityScores[spellcastingAbility] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profBonus = proficiencyBonus(level: character.level)
        return 8 + abilityMod + profBonus
    }

    static func spellAttackBonus(
        character: Character,
        spellcastingAbility: Ability
    ) -> Int {
        let score = character.abilityScores[spellcastingAbility] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profBonus = proficiencyBonus(level: character.level)
        return abilityMod + profBonus
    }

    /// Whether a character can attune to a given item right now, ignoring
    /// the slot cap (which the inventory view enforces separately).
    enum AttunementEligibility: Equatable {
        /// The item simply doesn't require attunement — the toggle is hidden.
        case notRequired
        /// All restrictions pass. The toggle is enabled (subject to slot cap).
        case eligible
        /// At least one restriction fails. The toggle is shown disabled with
        /// the human-readable reason underneath.
        case blocked(reason: String)
    }

    @MainActor
    static func attunementEligibility(
        itemID: String,
        character: Character,
        content: ContentStore
    ) -> AttunementEligibility {
        guard let rule = content.attunementRule(forItemID: itemID) else { return .notRequired }
        if let reason = rule.restrictions?.firstUnmetReason(for: character, content: content) {
            return .blocked(reason: reason)
        }
        return .eligible
    }

    /// Effective attunement slot count for a character. Resolution order:
    /// 1. Per-character override (`attunementSlotsOverride`) wins outright.
    /// 2. Otherwise, take the max `attunementSlots` across all class features
    ///    granted at or below the character's class level. The Artificer's
    ///    Magic Item Adept (L10 → 4), Master (L14 → 5), and Savant (L18 → 6)
    ///    are modeled as plain features with `"attunementSlots": N`.
    /// 3. Fall back to the standard 5e cap of 3.
    @MainActor
    static func attunementLimit(character: Character, content: ContentStore) -> Int {
        if let override = character.attunementSlotsOverride { return override }
        var limit = 3
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            for level in 1...max(entry.level, 1) {
                for feature in cls.levelFeatures[level] ?? [] {
                    if let slots = feature.attunementSlots {
                        limit = max(limit, slots)
                    }
                }
            }
        }
        return limit
    }

    // MARK: - Weapon Mastery (5e 2024)

    /// Total Weapon Mastery slots the character gets. Computed by walking
    /// every class feature granted at or below the character's class level
    /// for a `FeatureSelection` with id "weapon_mastery", summing each
    /// feature's selection count (sparse-table-resolved at the owning class
    /// level). Returns 0 when no class feature exposes a mastery selection.
    @MainActor
    static func weaponMasterySlotCount(character: Character, content: ContentStore) -> Int {
        var total = 0
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            for level in 1...max(entry.level, 1) {
                for feature in cls.levelFeatures[level] ?? [] {
                    guard let selection = feature.selection,
                          selection.id == "weapon_mastery" else { continue }
                    total += selection.count.value(
                        classLevel: entry.level,
                        characterLevel: character.level
                    )
                }
            }
        }
        return total
    }

    /// True when this character actively has the given weapon's mastery
    /// property online: they have the Weapon Mastery feature AND have selected
    /// this weapon as one of their masteries via `featureSelections`.
    @MainActor
    static func hasActiveMastery(
        weaponID: String,
        character: Character,
        content: ContentStore
    ) -> Bool {
        guard weaponMasterySlotCount(character: character, content: content) > 0 else { return false }
        return (character.featureSelections["weapon_mastery"] ?? []).contains(weaponID)
    }

    /// Per-weapon attack + damage breakdown shown in the inventory description.
    /// Lets the player audit why their Shortbow attack is "+3" instead of "+5":
    /// they see the DEX mod and proficiency contributions inline.
    ///
    /// Returns nil when the item id isn't a weapon (caller should fall back to
    /// the bare description).
    @MainActor
    static func weaponRollBreakdown(
        weaponID: String,
        character: Character,
        content: ContentStore
    ) -> WeaponRollBreakdown? {
        guard let weapon = content.weaponDefinition(id: weaponID) else { return nil }

        let attackRecipe = ActionRecipe.weaponAttack(
            abilityOverride: nil,
            finesse: weapon.properties.contains(.finesse)
        )
        let damageRecipe = ActionRecipe.weaponDamage(
            dieOverride: nil,
            addAbility: true,
            versatile: false
        )
        let attack = ActionInterpreter.resolve(recipe: attackRecipe, character: character, weapon: weapon)
        let damage = ActionInterpreter.resolve(recipe: damageRecipe, character: character, weapon: weapon)

        let versatile: WeaponRollLine?
        if weapon.versatileDamage != nil {
            let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: true)
            let resolved = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)
            versatile = WeaponRollLine(formula: formulaString(resolved.formula), breakdown: resolved.description ?? "")
        } else {
            versatile = nil
        }

        return WeaponRollBreakdown(
            attack: WeaponRollLine(
                formula: signedModifierString(attack.formula?.modifier ?? 0),
                breakdown: attack.description ?? ""
            ),
            damage: WeaponRollLine(
                formula: formulaString(damage.formula),
                breakdown: damage.description ?? ""
            ),
            versatile: versatile,
            damageType: weapon.damageType.rawValue.capitalized
        )
    }

    /// "+5" / "−2" / "+0" formatting for an attack bonus.
    private static func signedModifierString(_ mod: Int) -> String {
        if mod > 0 { return "+\(mod)" }
        if mod < 0 { return "−\(abs(mod))" }
        return "+0"
    }

    /// "1d8+3", "1d10−1", "1d4" — the formula a damage roll resolves to.
    private static func formulaString(_ formula: DiceFormula?) -> String {
        guard let formula else { return "—" }
        let dice = formula.groups.map { "\($0.count)d\($0.kind.rawValue)" }.joined(separator: "+")
        let mod = formula.modifier
        if mod == 0 { return dice }
        return mod > 0 ? "\(dice)+\(mod)" : "\(dice)−\(abs(mod))"
    }
}

struct WeaponRollLine: Equatable {
    /// Top-line formula ("1d8+3" or "+5").
    let formula: String
    /// How the formula was assembled ("1d8 + STR (+3)").
    let breakdown: String
}

struct WeaponRollBreakdown: Equatable {
    let attack: WeaponRollLine
    let damage: WeaponRollLine
    /// Two-handed damage line for versatile weapons; nil otherwise.
    let versatile: WeaponRollLine?
    /// Damage type label ("Slashing", "Piercing", …).
    let damageType: String
}
