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
        unarmoredDefenseBonus: Int = 0,
        spellACBonus: Int = 0,
        unarmoredACBase: Int? = nil
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
        } else if let mageBase = unarmoredACBase {
            // Mage Armor (13 + Dex) overrides Unarmored Defense — they don't
            // stack; the better one wins, and a 13 base beats most low-mod
            // unarmored builds. Use the higher of the two so we never downgrade.
            base = max(mageBase, 10 + unarmoredDefenseBonus) + dexMod
        } else {
            // No armor: 10 + Dex, plus any Unarmored Defense ability mod.
            base = 10 + dexMod + unarmoredDefenseBonus
        }

        let shieldBonus = hasShield ? 2 : 0
        return base + shieldBonus + fightingStyleBonus + spellACBonus
    }

    /// Every `SpellBuffEffect` currently riding on the character via an active
    /// spell effect (Bless, Shield of Faith, Mage Armor, Longstrider, Shield).
    @MainActor
    static func activeSpellBuffs(character: Character, content: ContentStore) -> [SpellBuffEffect] {
        var out: [SpellBuffEffect] = []
        for active in character.activeEffects {
            guard case .spell(let id) = active.source,
                  let spell = content.spellDefinition(id: id) else { continue }
            for effect in spell.effects {
                if case .selfBuff(let buff) = effect { out.append(buff) }
            }
        }
        return out
    }

    /// Flat AC bonus from active spell buffs (Shield + Shield of Faith stack).
    @MainActor
    static func spellACBonus(character: Character, content: ContentStore) -> Int {
        activeSpellBuffs(character: character, content: content).reduce(0) { $0 + $1.acBonus }
    }

    /// The highest unarmored AC base granted by an active buff (Mage Armor →
    /// 13), or nil when none is active. Only meaningful while no armor is worn.
    @MainActor
    static func spellUnarmoredACBase(character: Character, content: ContentStore) -> Int? {
        activeSpellBuffs(character: character, content: content)
            .compactMap(\.unarmoredACBase)
            .max()
    }

    /// Walking-speed bonus in feet from active spell buffs (Longstrider +10).
    @MainActor
    static func spellSpeedBonus(character: Character, content: ContentStore) -> Int {
        activeSpellBuffs(character: character, content: content).reduce(0) { $0 + $1.speedBonus }
    }

    /// Walking-speed bonus from class features (Monk Unarmored Movement,
    /// Barbarian Fast Movement), scaled by the owning class level. Applies
    /// only while UNARMORED (no body armor, no shield) — the shared 5e
    /// condition for both features; the caller passes that state.
    @MainActor
    static func featureSpeedBonus(
        character: Character, content: ContentStore, unarmored: Bool
    ) -> Int {
        guard unarmored else { return 0 }
        var total = 0
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                if let bonus = resolved.feature.speedBonus {
                    total += bonus.value(classLevel: entry.level, characterLevel: character.level)
                }
            }
        }
        return total
    }

    /// Dice groups every active buff adds to attack rolls and saving throws
    /// (Bless → 1d4). Callers append these to the resolved d20 formula.
    @MainActor
    static func attackSaveBuffDiceGroups(character: Character, content: ContentStore) -> [DiceGroup] {
        var groups: [DiceGroup] = []
        for buff in activeSpellBuffs(character: character, content: content) {
            guard let dice = buff.attackAndSaveBonusDice,
                  let parsed = try? DiceFormulaParser().parse(dice) else { continue }
            groups.append(contentsOf: parsed.groups)
        }
        return groups
    }

    // MARK: - Spell preparation

    /// The character's primary spellcasting class — the first class entry that
    /// carries a `SpellcastingBlock`. Multiclass casters with diverging
    /// abilities/rules need a per-class resolver later.
    @MainActor
    static func primarySpellcasting(
        character: Character, content: ContentStore
    ) -> (classID: String, level: Int, block: SpellcastingBlock)? {
        for entry in character.classEntries {
            if let block = content.classDefinition(id: entry.classID)?.spellcasting {
                return (entry.classID, entry.level, block)
            }
        }
        return nil
    }

    /// Every class entry that prepares spells daily (`preparedFromAll` or
    /// `preparedFromBook`), in classEntries order. Each prepares SEPARATELY
    /// with its own cap and list (5e multiclass rule).
    @MainActor
    static func preparedCasterClasses(
        character: Character, content: ContentStore
    ) -> [(classID: String, level: Int, block: SpellcastingBlock)] {
        character.classEntries.compactMap { entry in
            guard let block = content.classDefinition(id: entry.classID)?.spellcasting,
                  block.preparedRule == .preparedFromAll || block.preparedRule == .preparedFromBook
            else { return nil }
            return (entry.classID, entry.level, block)
        }
    }

    /// True when any of the character's classes prepares spells daily.
    @MainActor
    static func isPreparedCaster(character: Character, content: ContentStore) -> Bool {
        !preparedCasterClasses(character: character, content: content).isEmpty
    }

    /// Max LEVELED spells `classID` can have prepared. Two shapes:
    /// - If the class declares a fixed `spellsKnown` table (2024 Bard,
    ///   Sorcerer — "Prepared Spells" column of their level table), the table
    ///   value at the class level wins. Prep is capped by the table; players
    ///   swap on level-up (RAW), not each long rest.
    /// - Otherwise `ability mod + class level` (min 1) — the SRD "prepare from
    ///   the whole list" formula (cleric, druid, paladin, wizard-from-book).
    /// Cantrips don't count. Nil when `classID` isn't a prepared-caster class.
    @MainActor
    static func maxPreparedSpells(
        character: Character, content: ContentStore, forClassID classID: String
    ) -> Int? {
        guard let sc = preparedCasterClasses(character: character, content: content)
            .first(where: { $0.classID == classID }) else { return nil }
        if let table = sc.block.spellsKnown {
            return table.value(classLevel: sc.level, characterLevel: character.level)
        }
        let mod = abilityModifier(score: character.abilityScores[sc.block.ability] ?? 10)
        return max(1, mod + sc.level)
    }

    /// True when the class uses the 2024 "Prepared Spells" fixed-table shape
    /// (Bard, Sorcerer) — swap on level-up, not on long rest. Drives the
    /// picker footer copy and separates the two prep regimes for UI.
    @MainActor
    static func hasFixedSpellsTable(classID: String, content: ContentStore) -> Bool {
        content.classDefinition(id: classID)?.spellcasting?.spellsKnown != nil
    }

    /// Whole-character convenience: the FIRST prepared-caster class's cap.
    /// Single-class callers (the common case) keep working; multiclass UIs
    /// should use the per-class variant.
    @MainActor
    static func maxPreparedSpells(character: Character, content: ContentStore) -> Int? {
        guard let first = preparedCasterClasses(character: character, content: content).first
        else { return nil }
        return maxPreparedSpells(character: character, content: content, forClassID: first.classID)
    }

    /// Cantrips-known budget for `classID` at its class level, or nil when the
    /// class isn't one of the character's casting classes.
    @MainActor
    static func cantripsKnownBudget(
        character: Character, content: ContentStore, forClassID classID: String
    ) -> Int? {
        guard let entry = character.classEntries.first(where: { $0.classID == classID }),
              let block = content.classDefinition(id: classID)?.spellcasting else { return nil }
        return block.cantripsKnown.value(classLevel: entry.level, characterLevel: character.level)
    }

    /// Whole-character convenience: the primary caster's cantrip budget.
    @MainActor
    static func cantripsKnownBudget(character: Character, content: ContentStore) -> Int? {
        guard let sc = primarySpellcasting(character: character, content: content) else { return nil }
        return sc.block.cantripsKnown.value(classLevel: sc.level, characterLevel: character.level)
    }

    /// Count of LEVELED spells prepared in `classID`'s bucket (cantrips
    /// excluded — they don't count against the prep cap).
    @MainActor
    static func preparedLeveledCount(
        character: Character, content: ContentStore, forClassID classID: String
    ) -> Int {
        (character.spells.preparedByClass[classID] ?? [])
            .compactMap { content.spellDefinition(id: $0) }
            .filter { !$0.isCantrip }
            .count
    }

    /// Whole-character count of prepared leveled spells across every class
    /// bucket plus the legacy flat list.
    @MainActor
    static func preparedLeveledCount(character: Character, content: ContentStore) -> Int {
        character.spells.allPreparedIDs
            .compactMap { content.spellDefinition(id: $0) }
            .filter { !$0.isCantrip }
            .count
    }

    /// The spell list a class chooses from: spells tagged with `classID`. If the
    /// class has NO tagged spells in the catalog, falls back to the full catalog
    /// so untagged classes behave exactly as before (incremental tagging).
    @MainActor
    static func spellList(forClassID classID: String, content: ContentStore) -> [SpellDefinition] {
        let tagged = content.allSpells.filter { $0.classes.contains(classID) }
        return tagged.isEmpty ? content.allSpells : tagged
    }

    /// LEVELED spells a known-list caster can know at its class level, from the
    /// class's `spellsKnown` table (SRD "prepared spells" column for Bard /
    /// Sorcerer / Warlock). Nil for prepared casters, non-casters, and classes
    /// whose table isn't authored (→ no cap, old behavior).
    @MainActor
    static func knownSpellBudget(
        character: Character, content: ContentStore, forClassID classID: String
    ) -> Int? {
        guard let entry = character.classEntries.first(where: { $0.classID == classID }),
              let block = content.classDefinition(id: classID)?.spellcasting,
              block.preparedRule == .knownList || block.preparedRule == .pactMagic,
              let table = block.spellsKnown else { return nil }
        return table.value(classLevel: entry.level, characterLevel: character.level)
    }

    /// Count of LEVELED spells in the known list (cantrips excluded — they
    /// have their own budget).
    @MainActor
    static func knownLeveledCount(character: Character, content: ContentStore) -> Int {
        character.spells.knownIDs
            .compactMap { content.spellDefinition(id: $0) }
            .filter { !$0.isCantrip }
            .count
    }

    /// The ability a multiclass caster uses for a specific spell: the class
    /// whose prepared bucket holds it wins; else the single caster class whose
    /// tagged spell list contains it; else the first casting class (matching
    /// the old single-class behavior). Nil for non-casters.
    @MainActor
    static func spellcastingAbility(
        forSpellID spellID: String, character: Character, content: ContentStore
    ) -> Ability? {
        let casters = character.classEntries.compactMap { entry -> (classID: String, block: SpellcastingBlock)? in
            guard let block = content.classDefinition(id: entry.classID)?.spellcasting else { return nil }
            return (entry.classID, block)
        }
        guard !casters.isEmpty else { return nil }
        for caster in casters
        where (character.spells.preparedByClass[caster.classID] ?? []).contains(spellID) {
            return caster.block.ability
        }
        let listed = casters.filter { caster in
            content.spellDefinition(id: spellID)?.classes.contains(caster.classID) == true
        }
        if listed.count == 1 { return listed[0].block.ability }
        return casters.first?.block.ability
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
        // Collect every fighting-style selection: the base `fighting_style`
        // slot plus extras like the Fighter's `fighter_fighting_style_2`. All
        // such selection ids contain "fighting_style".
        var styles: Set<String> = []
        for (key, values) in character.featureSelections where key.contains("fighting_style") {
            styles.formUnion(values)
        }
        let equippedWeapons = character.inventory
            .filter { $0.equipped }
            .compactMap { content.weaponDefinition(id: $0.itemID) }
        return FightingStyleEffects(
            styles: styles,
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
    /// A `classID` with no existing entry is a MULTICLASS pick — a new entry
    /// is appended at level 1. Centralized so the level-up sheet and any
    /// future automation share the same math.
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
        } else {
            character.classEntries.append(ClassEntry(classID: classID, level: 1))
        }
        character.recalculateHP()
    }

    /// "Druid 3 / Cleric 2" — one segment per class entry, in order. Single-
    /// class characters read as just the class name ("Druid") since the
    /// character level is shown separately everywhere this appears.
    @MainActor
    static func classSummary(character: Character, content: ContentStore) -> String? {
        let parts = character.classEntries.map { entry -> String in
            let name = content.classDefinition(id: entry.classID)?.name ?? entry.classID
            return character.classEntries.count > 1 ? "\(name) \(entry.level)" : name
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// RAW multiclass prerequisite: 13+ in the primary ability of EVERY class
    /// the character already has AND of the class being added. Returns nil
    /// when eligible, else the failing requirement as display text.
    @MainActor
    static func multiclassBlocker(
        addingClassID newClassID: String, character: Character, content: ContentStore
    ) -> String? {
        var required: [(name: String, ability: Ability)] = []
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            required.append((cls.name, cls.primaryAbility))
        }
        if let newCls = content.classDefinition(id: newClassID) {
            required.append((newCls.name, newCls.primaryAbility))
        }
        for req in required {
            let score = character.abilityScores[req.ability] ?? 10
            if score < 13 {
                return "\(req.name) needs \(req.ability.abbreviation) 13 (you have \(score))"
            }
        }
        return nil
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

    /// The ability whose modifier a weapon's attack roll uses — finesse picks
    /// the better of STR/DEX, otherwise the weapon's declared damage ability
    /// (default STR). Mirrors `ActionInterpreter.resolveWeaponAttack`'s choice.
    static func weaponAttackAbilityMod(character: Character, weapon: WeaponDefinition) -> Int {
        let str = abilityModifier(score: character.abilityScores[.strength] ?? 10)
        let dex = abilityModifier(score: character.abilityScores[.dexterity] ?? 10)
        if weapon.properties.contains(.finesse) { return max(str, dex) }
        let ability = weapon.damageAbility ?? .strength
        return abilityModifier(score: character.abilityScores[ability] ?? 10)
    }

    /// Character-specific, resolved mechanic text for a weapon's Mastery
    /// property — the numbers filled in (Topple save DC, Graze damage) so the
    /// player can act on it without flipping to a reference. Self-affecting
    /// masteries (Vex's "advantage on your next attack") read as guidance;
    /// enemy-only ones (Sap, Slow) stay narrative — there's no enemy sheet.
    static func masteryMechanic(
        weapon: WeaponDefinition,
        mastery: WeaponMastery,
        character: Character
    ) -> String {
        let abilityMod = weaponAttackAbilityMod(character: character, weapon: weapon)
        let pb = proficiencyBonus(level: character.level)
        let type = weapon.damageType.rawValue
        switch mastery {
        case .vex:
            return "On a hit that deals damage: Advantage on your next attack against that target."
        case .graze:
            return "On a miss: deal \(max(0, abilityMod)) \(type) damage anyway."
        case .topple:
            return "On a hit: target makes a DC \(8 + abilityMod + pb) Constitution save or falls Prone."
        case .sap:
            return "On a hit: target has Disadvantage on its next attack."
        case .slow:
            return "On a hit that deals damage: target's Speed −10 ft until your next turn."
        case .push:
            return "On a hit: push a Large-or-smaller target up to 10 ft away."
        case .nick:
            return "Make the Light extra attack as part of your Attack action (no Bonus Action)."
        case .cleave:
            return "On a hit: a second creature within 5 ft takes the weapon's damage (no ability mod). Once per turn."
        }
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

    // MARK: - Condition effects on rolls

    /// Which kind of d20 roll a condition gate is being asked about. Only these
    /// three carry condition advantage/disadvantage for the *rolling* character;
    /// `attacksAgainst*` effects act on whoever attacks them and aren't applied
    /// to the character's own dice.
    enum ConditionRollContext: Equatable {
        case attack
        case abilityCheck(Ability)   // skills map to their governing ability
        case savingThrow(Ability)
    }

    /// Net advantage/disadvantage the character's active conditions impose on a
    /// roll of `context` (Blinded/Poisoned/Frightened/Prone/Restrained →
    /// attack disadvantage; Invisible → attack advantage; Poisoned → check
    /// disadvantage; Restrained → DEX-save disadvantage; …).
    @MainActor
    static func conditionRollMode(
        character: Character, content: ContentStore, context: ConditionRollContext
    ) -> (advantage: Bool, disadvantage: Bool) {
        var advantage = false
        var disadvantage = false
        for cond in character.conditions {
            guard let def = content.conditionDefinition(id: cond.id) else { continue }
            for effect in def.effects {
                switch (context, effect) {
                case (.attack, .attacksByHaveAdvantage):
                    advantage = true
                case (.attack, .attacksByHaveDisadvantage):
                    disadvantage = true
                case (.abilityCheck(let a), .abilityCheckDisadvantage(let abilities)) where abilities.contains(a):
                    disadvantage = true
                case (.savingThrow(let a), .savingThrowDisadvantage(let abilities)) where abilities.contains(a):
                    disadvantage = true
                default:
                    break
                }
            }
        }
        return (advantage, disadvantage)
    }

    /// Combine a user-chosen roll mode with condition-imposed advantage/
    /// disadvantage per 5e: any advantage + any disadvantage cancels to normal.
    static func combineRollMode(_ user: RollMode, advantage: Bool, disadvantage: Bool) -> RollMode {
        let adv = advantage || user == .advantage
        let dis = disadvantage || user == .disadvantage
        if adv && dis { return .normal }
        if adv { return .advantage }
        if dis { return .disadvantage }
        return .normal
    }

    /// The condition roll context a recipe maps to, or nil for rolls conditions
    /// don't touch (damage, save DCs, …).
    static func conditionContext(for recipe: ActionRecipe) -> ConditionRollContext? {
        switch recipe {
        case .weaponAttack, .spellAttack:  return .attack
        case .abilityCheck(let a):         return .abilityCheck(a)
        case .skillCheck(let s):           return .abilityCheck(s.ability)
        case .savingThrow(let a):          return .savingThrow(a)
        default:                           return nil
        }
    }

    /// One-call: a recipe's effective roll mode after folding in the character's
    /// conditions AND worn-armor effects on top of the user's choice. Returns
    /// `userMode` unchanged for recipes neither touches.
    @MainActor
    static func conditionAdjustedMode(
        for recipe: ActionRecipe, userMode: RollMode, character: Character, content: ContentStore
    ) -> RollMode {
        guard let context = conditionContext(for: recipe) else { return userMode }
        var (adv, dis) = conditionRollMode(character: character, content: content, context: context)
        // Heavy/medium armor's Stealth penalty isn't a condition — fold it in
        // here so a single call yields the true Stealth roll mode.
        if case .skillCheck(.stealth) = recipe,
           stealthDisadvantageFromArmor(character: character, content: content) {
            dis = true
        }
        return combineRollMode(userMode, advantage: adv, disadvantage: dis)
    }

    /// True when the character wears (non-shield) armor that imposes
    /// disadvantage on Dexterity (Stealth) checks. Drives the Stealth roll mode
    /// and a sheet note. Honors the first equipped body armor (only one counts).
    @MainActor
    static func stealthDisadvantageFromArmor(character: Character, content: ContentStore) -> Bool {
        for item in character.inventory where item.equipped {
            if let armor = content.armorDefinition(id: item.itemID),
               armor.armorCategory != .shield {
                return armor.stealthDisadvantage
            }
        }
        return false
    }

    /// The name of an active condition that makes a saving throw of `ability`
    /// auto-fail (Paralyzed / Stunned / Unconscious → STR & DEX saves), or nil
    /// when nothing forces a failure. Surfaced as an alert so the player doesn't
    /// waste a roll on a save that can't succeed.
    @MainActor
    static func autoFailedSaveCondition(
        character: Character, content: ContentStore, ability: Ability
    ) -> String? {
        guard ability == .strength || ability == .dexterity else { return nil }
        for cond in character.conditions {
            guard let def = content.conditionDefinition(id: cond.id) else { continue }
            if def.effects.contains(.autoFailStrengthAndDexSaves) { return def.name }
        }
        return nil
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
    /// Every chosen Fighting Style option id (`archery`, `dueling`,
    /// `great_weapon_fighting`, …). A set because Fighters get a second style
    /// (Champion) and a character could carry one from each of two classes.
    let styles: Set<String>
    /// True when exactly one weapon is equipped — the Dueling pre-condition.
    let onlyOneWeaponEquipped: Bool

    /// Whether the character has the given Fighting Style active.
    func has(_ id: String) -> Bool { styles.contains(id) }

    static let none = FightingStyleEffects(styles: [], onlyOneWeaponEquipped: false)
}
