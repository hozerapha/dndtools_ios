import Foundation

enum CharacterCalculator {
    static func abilityModifier(score: Int) -> Int {
        // `(score - 10) / 2` truncates toward zero in Swift, giving odd
        // scores below 10 a modifier one too high (9 → 0 instead of −1,
        // 1 → −4 instead of −5). `score / 2 - 5` is the exact 5e floor
        // for every non-negative score.
        score / 2 - 5
    }

    static func proficiencyBonus(level: Int) -> Int {
        (level - 1) / 4 + 2
    }

    /// `jackOfAllTrades` adds half the Proficiency Bonus (round down) to checks
    /// for skills the character is NOT proficient in (Bard's Jack of All
    /// Trades). It never stacks on a proficient/expertise skill. The caller
    /// resolves whether the character has the feature via
    /// `hasJackOfAllTrades(character:content:)` and passes the flag in, keeping
    /// this function content-free.
    static func skillModifier(
        character: Character,
        skill: Skill,
        jackOfAllTrades: Bool = false
    ) -> Int {
        let abilityMod = abilityModifier(score: character.abilityScores[skill.ability] ?? 10)
        let profBonus = proficiencyBonus(level: character.level)
        switch skillProficiencyLevel(character: character, skill: skill) {
        case .none:       return abilityMod + (jackOfAllTrades ? profBonus / 2 : 0)
        case .proficient: return abilityMod + profBonus
        case .expertise:  return abilityMod + (profBonus * 2)
        }
    }

    /// Whether `jackOfAllTrades` applies to this specific skill: the character
    /// has the feature AND lacks proficiency in the skill (so the half-PB
    /// actually contributes). Used by the skills table to show the ½ indicator
    /// only where it matters.
    static func appliesJackOfAllTrades(character: Character, skill: Skill, hasFeature: Bool) -> Bool {
        hasFeature && skillProficiencyLevel(character: character, skill: skill) == .none
    }

    /// True when the character has a Jack of All Trades feature (id matching
    /// the marker) at or below their level. Content-aware; walks resolved
    /// features so a subclass grant would also count.
    @MainActor
    static func hasJackOfAllTrades(character: Character, content: ContentStore) -> Bool {
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID)
            where resolved.feature.id.contains(FeatureIDs.jackOfAllTradesMarker) {
                return true
            }
        }
        return false
    }

    /// The character's effective proficiency in a skill, resolved from every
    /// source: stored proficiencies (background grants), class skill-choice
    /// selections (`.skillsFrom`, granting proficiency), and expertise
    /// selections (upgrading to expertise). Content-free — it reads
    /// `featureSelections` by marker, the same trick that makes these picks
    /// re-editable anywhere (creation, Features tab) with no extra wiring.
    static func skillProficiencyLevel(character: Character, skill: Skill) -> ProficiencyLevel {
        let stored = character.proficiencies[.skill(skill)] ?? .none
        let proficient = stored == .proficient || stored == .expertise
            || hasClassSkillProficiency(in: skill, character: character)
        guard proficient else { return .none }
        let expertise = stored == .expertise || hasExpertise(in: skill, character: character)
        return expertise ? .expertise : .proficient
    }

    /// True when an expertise selection (id containing `expertise`) lists this
    /// skill. The convention lets any class use the mechanism without
    /// hard-coding feature IDs.
    private static func hasExpertise(in skill: Skill, character: Character) -> Bool {
        character.featureSelections.contains { key, values in
            key.contains(FeatureIDs.expertiseMarker) && values.contains(skill.rawValue)
        }
    }

    /// True when a class skill-choice selection (id containing `class_skills`)
    /// lists this skill — granting base proficiency, resolved live so the pick
    /// is editable from creation or the Features tab interchangeably.
    private static func hasClassSkillProficiency(in skill: Skill, character: Character) -> Bool {
        character.featureSelections.contains { key, values in
            key.contains(FeatureIDs.classSkillsMarker) && values.contains(skill.rawValue)
        }
    }

    /// The highest skill-check floor any of the character's features impose
    /// (Reliable Talent → 10 from Rogue 7). Returns nil when none apply. The
    /// floor only takes effect on skills the character is proficient in — the
    /// interpreter applies that gate; this just reports the value. Walks
    /// resolved features so subclass-granted variants scale by the right
    /// class level.
    @MainActor
    static func skillCheckFloor(character: Character, content: ContentStore) -> Int? {
        var best: Int?
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                guard let scaled = resolved.feature.skillCheckMinimum else { continue }
                let value = scaled.value(classLevel: entry.level, characterLevel: character.level)
                if value > 0 { best = max(best ?? 0, value) }
            }
        }
        return best
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

    /// `unarmoredDefenseBonus` is the ability modifier an Unarmored Defense
    /// feature adds to the no-armor AC (Barbarian → CON, Draconic Sorcerer →
    /// CHA, Monk → WIS). It only applies when no armor is worn; with armor on,
    /// the armor's own formula wins. The caller resolves it via
    /// `unarmoredDefenseAbility(character:content:)` to keep this function
    /// content-free.
    static func armorClass(
        dexMod: Int,
        armor: ArmorDefinition?,
        hasShield: Bool,
        fightingStyleBonus: Int = 0,
        unarmoredDefenseBonus: Int = 0
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
            // No armor: 10 + Dex, plus any Unarmored Defense ability mod.
            base = 10 + dexMod + unarmoredDefenseBonus
        }

        let shieldBonus = hasShield ? 2 : 0
        return base + shieldBonus + fightingStyleBonus
    }

    /// The ability whose modifier feeds Unarmored Defense for this character,
    /// or nil if no feature grants it. First match across resolved class /
    /// subclass features. Content-aware (walks features); the AC formula stays
    /// content-free and just takes the resolved modifier.
    @MainActor
    static func unarmoredDefenseAbility(character: Character, content: ContentStore) -> Ability? {
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                if let ability = resolved.feature.unarmoredDefenseAbility { return ability }
            }
        }
        return nil
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
              character.featureSelections[FeatureIDs.fightingStyle]?.first == FeatureIDs.FightingStyle.defense
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
        let style = character.featureSelections[FeatureIDs.fightingStyle]?.first
        let equippedWeapons = character.inventory
            .filter { $0.equipped }
            .compactMap { content.weaponDefinition(id: $0.itemID) }
        return FightingStyleEffects(
            style: style,
            onlyOneWeaponEquipped: equippedWeapons.count == 1
        )
    }

    /// Total HP change the player will SEE at level-up when taking the
    /// average — die average + CON mod. 5e PHB rule: `floor(hitDie/2) + 1 +
    /// CON mod`. Display/preview helper only: the value banked into
    /// `rolledHP` by `applyLevelUp` is the die-only part; the CON share is
    /// derived retroactively by `Character.recalculateHP()`.
    static func averageLevelUpHPGain(hitDie: Int, conMod: Int) -> Int {
        (hitDie / 2 + 1) + conMod
    }

    /// 5e rule: a level-up never grants fewer than 1 HP even with a brutal
    /// CON penalty. Wrap any computed gain through this before applying.
    static func clampedLevelUpHPGain(_ raw: Int) -> Int {
        max(1, raw)
    }

    /// Bumps the character's overall level and the matching class entry's
    /// level, and banks the (clamped) **die-only** HP gain into `rolledHP` —
    /// `hpGain` is the hit-die roll or die average WITHOUT the CON modifier.
    /// `recalculateHP()` then derives the new max, so the per-level CON
    /// bonus stays retroactive (a later CON change reflows every level).
    /// Centralized so the level-up sheet and any future automation share
    /// the same math.
    static func applyLevelUp(
        to character: inout Character,
        hpGain: Int,
        classID: String
    ) {
        let clampedGain = clampedLevelUpHPGain(hpGain)
        character.rolledHP += clampedGain
        character.level += 1
        if let idx = character.classEntries.firstIndex(where: { $0.classID == classID }) {
            let entry = character.classEntries[idx]
            character.classEntries[idx] = ClassEntry(classID: entry.classID, level: entry.level + 1)
        }
        character.recalculateHP()
    }

    /// Total feature-granted Hit-Point bonus the character currently qualifies
    /// for. Class/subclass bonuses scale by the owning class level (Draconic
    /// Resilience → sorcerer level, correct for multiclass); species-trait
    /// bonuses scale by character level (Dwarven Toughness). The caller folds
    /// this into `rolledHP` at creation and level-up (diffed), so the
    /// content-free `recalculateHP()` stays correct through CON changes.
    @MainActor
    static func featureHitPointBonus(character: Character, content: ContentStore) -> Int {
        var total = 0
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                if let hp = resolved.feature.hitPointBonus { total += hp.total(atLevel: entry.level) }
            }
        }
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits {
                if let hp = trait.hitPointBonus { total += hp.total(atLevel: character.level) }
            }
        }
        return total
    }

    /// The spellcasting buff currently active on the character (Innate
    /// Sorcery): the spell-save-DC bonus and whether spell attacks have
    /// Advantage. Sums `.spellcastingBuff` effects sitting in `activeEffects`,
    /// resolving each effect's payload from its source feature. Returns zero /
    /// false when nothing applies.
    @MainActor
    static func spellcastingBuff(
        character: Character, content: ContentStore
    ) -> (saveDCBonus: Int, attackAdvantage: Bool) {
        var dc = 0
        var advantage = false
        for active in character.activeEffects {
            guard case .feature(let featureID) = active.source else { continue }
            for entry in character.classEntries {
                guard let cls = content.classDefinition(id: entry.classID) else { continue }
                let subclassID = character.featureSelections[
                    ClassDefinition.subclassSelectionID(forClassID: entry.classID)
                ]?.first
                for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                    guard resolved.feature.id == featureID,
                          let effect = resolved.feature.triggeredEffect,
                          effect.id == active.effectID,
                          case .spellcastingBuff(let dcBonus, let adv) = effect.effect else { continue }
                    dc += dcBonus
                    advantage = advantage || adv
                }
            }
        }
        return (dc, advantage)
    }

    static func initiativeBonus(character: Character) -> Int {
        let dexScore = character.abilityScores[.dexterity] ?? 10
        return abilityModifier(score: dexScore)
    }

    static func passivePerception(character: Character) -> Int {
        10 + skillModifier(character: character, skill: .perception)
    }

    /// Content-aware passive Perception: includes Jack of All Trades' half-PB
    /// when the character has the feature and lacks Perception proficiency.
    @MainActor
    static func passivePerception(character: Character, content: ContentStore) -> Int {
        let joat = hasJackOfAllTrades(character: character, content: content)
        return 10 + skillModifier(character: character, skill: .perception, jackOfAllTrades: joat)
    }

    static func spellSaveDC(
        character: Character,
        spellcastingAbility: Ability,
        bonus: Int = 0
    ) -> Int {
        let score = character.abilityScores[spellcastingAbility] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profBonus = proficiencyBonus(level: character.level)
        return 8 + abilityMod + profBonus + bonus
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
                      selection.id == FeatureIDs.weaponMastery else { continue }
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
        return (character.featureSelections[FeatureIDs.weaponMastery] ?? []).contains(weaponID)
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
