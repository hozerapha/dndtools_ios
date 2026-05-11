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
        hasShield: Bool,
        fightingStyleBonus: Int = 0
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
        return base + shieldBonus + fightingStyleBonus
    }

    /// Resolves Fighting Style "Defense" to its AC delta. +1 when the chosen
    /// style is `defense` *and* the character is wearing armor (the SRD
    /// condition). Zero otherwise. Other styles modify attacks / damage and
    /// are surfaced through `ActionInterpreter` instead.
    static func defenseACBonus(
        character: Character,
        wearingArmor: Bool
    ) -> Int {
        guard wearingArmor,
              character.featureSelections["fighting_style"]?.first == "defense"
        else { return 0 }
        return 1
    }

    /// Snapshot of fighting-style state that affects weapon rolls. Computed
    /// from inventory + content because Dueling needs to know whether the
    /// character has any *other* weapon equipped. Pure data so the
    /// interpreter can stay independent of ContentStore.
    static func fightingStyleEffects(
        character: Character,
        content: ContentStore
    ) -> FightingStyleEffects {
        let style = character.featureSelections["fighting_style"]?.first
        let equippedWeapons = character.inventory
            .filter { $0.equipped }
            .compactMap { content.weaponDefinition(id: $0.itemID) }
        return FightingStyleEffects(
            style: style,
            onlyOneWeaponEquipped: equippedWeapons.count == 1
        )
    }

    /// HP gain at level-up if the player takes the average. 5e PHB rule:
    /// `floor(hitDie/2) + 1 + CON mod`. Always ≥ 1 (CON penalty can't push
    /// the gain below 1 — handled in `clampedLevelUpHPGain`).
    static func averageLevelUpHPGain(hitDie: Int, conMod: Int) -> Int {
        (hitDie / 2 + 1) + conMod
    }

    /// 5e rule: a level-up never grants fewer than 1 HP even with a brutal
    /// CON penalty. Wrap any computed gain through this before applying.
    static func clampedLevelUpHPGain(_ raw: Int) -> Int {
        max(1, raw)
    }

    /// Bumps the character's overall level, the matching class entry's level,
    /// and adds the (clamped) HP gain to both max and current HP. Centralized
    /// so the level-up sheet and any future automation share the same math.
    static func applyLevelUp(
        to character: inout Character,
        hpGain: Int,
        classID: String
    ) {
        let clampedGain = clampedLevelUpHPGain(hpGain)
        character.maxHP += clampedGain
        character.currentHP = min(character.currentHP + clampedGain, character.maxHP)
        character.level += 1
        if let idx = character.classEntries.firstIndex(where: { $0.classID == classID }) {
            let entry = character.classEntries[idx]
            character.classEntries[idx] = ClassEntry(classID: entry.classID, level: entry.level + 1)
        }
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
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                if let slots = resolved.feature.attunementSlots {
                    limit = max(limit, slots)
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
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                guard let selection = resolved.feature.selection,
                      selection.id == "weapon_mastery" else { continue }
                total += selection.count.value(
                    classLevel: entry.level,
                    characterLevel: character.level
                )
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

        let fs = fightingStyleEffects(character: character, content: content)
        let attackRecipe = ActionRecipe.weaponAttack(
            abilityOverride: nil,
            finesse: weapon.properties.contains(.finesse)
        )
        let damageRecipe = ActionRecipe.weaponDamage(
            dieOverride: nil,
            addAbility: true,
            versatile: false
        )
        let attack = ActionInterpreter.resolve(recipe: attackRecipe, character: character, weapon: weapon, fightingStyle: fs)
        let damage = ActionInterpreter.resolve(recipe: damageRecipe, character: character, weapon: weapon, fightingStyle: fs)

        let versatile: WeaponRollLine?
        if weapon.versatileDamage != nil {
            let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: true)
            let resolved = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon, fightingStyle: fs)
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

/// Pre-computed Fighting Style context for the `ActionInterpreter`. Tells the
/// weapon-resolution path which style is active and whether the Dueling
/// condition ("no other weapons equipped") is currently satisfied. Spell
/// resolution ignores this entirely. Built via
/// `CharacterCalculator.fightingStyleEffects(character:content:)`.
struct FightingStyleEffects: Equatable {
    /// Picked option ID, e.g. `archery` / `defense` / `dueling`. Nil when the
    /// character hasn't chosen a style yet.
    let style: String?
    /// True when exactly one weapon is equipped — the Dueling pre-condition.
    let onlyOneWeaponEquipped: Bool

    static let none = FightingStyleEffects(style: nil, onlyOneWeaponEquipped: false)
}
