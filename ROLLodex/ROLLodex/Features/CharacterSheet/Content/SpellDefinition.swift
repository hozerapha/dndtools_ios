import Foundation

/// A spell definition loaded from `spells.json`. References by ID (`magic_missile`,
/// `cure_wounds`) — characters store known/prepared/spellbook lists as
/// `[String]` arrays of these IDs. `actionRecipes` is the on-cast effect
/// chain handed to the same `ActionInterpreter` / dice flow that powers
/// every other tappable action on the sheet.
struct SpellDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// 0 = cantrip, 1-9 = leveled spell.
    let level: Int
    let school: SpellSchool
    let castingTime: CastingTime
    let range: SpellRange
    let components: SpellComponents
    let duration: SpellDuration
    let description: String
    /// Text describing the upcast effect ("When you cast this spell using a
    /// spell slot of 2nd level or higher, …"). Informational; the mechanical
    /// scaling comes from `upcastEffect`.
    let higherLevel: String?
    let actionRecipes: [ActionRecipe]
    let upcastEffect: UpcastEffect?
    /// Persistent rider applied to the caster on cast — currently used by
    /// Hex, Hunter's Mark, and similar concentration spells that modify the
    /// caster's outgoing rolls until concentration drops. Nil for spells that
    /// don't grant a rider.
    let grantsTriggeredEffect: TriggeredEffect?
    /// Sheet state a cast produces. Caster-targeted effects (`tempHP`,
    /// `selfCondition`) auto-apply on cast; `targetCondition` is offered as an
    /// "apply to this character" button (the player is often the target a DM
    /// calls out, and there's no enemy sheet in a one-PC app). Empty for spells
    /// with no sheet effect.
    let effects: [SpellEffect]
    /// When non-empty, the caster picks one of these damage types at cast time
    /// (Chromatic Orb, Dragon's Breath). The chosen type is stamped onto the
    /// spell's damage dice, overriding the recipe's placeholder `damageType`.
    /// Empty for spells with a fixed damage type.
    let damageTypeChoices: [DamageType]
    /// Class IDs whose spell list this spell belongs to (`["druid", "cleric"]`).
    /// Used to filter the prepare/known picker to a caster's list. Tagging is
    /// incremental per class: a class with NO tagged spells falls back to the
    /// full catalog, so untagged classes behave exactly as before.
    let classes: [String]

    var isCantrip: Bool { level == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, level, school, castingTime, range, components, duration
        case description, higherLevel, actionRecipes, upcastEffect, grantsTriggeredEffect
        case effects, damageTypeChoices, classes
    }

    init(
        id: String,
        name: String,
        level: Int,
        school: SpellSchool,
        castingTime: CastingTime,
        range: SpellRange,
        components: SpellComponents,
        duration: SpellDuration,
        description: String,
        higherLevel: String? = nil,
        actionRecipes: [ActionRecipe] = [],
        upcastEffect: UpcastEffect? = nil,
        grantsTriggeredEffect: TriggeredEffect? = nil,
        effects: [SpellEffect] = [],
        damageTypeChoices: [DamageType] = [],
        classes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.school = school
        self.castingTime = castingTime
        self.range = range
        self.components = components
        self.duration = duration
        self.description = description
        self.higherLevel = higherLevel
        self.actionRecipes = actionRecipes
        self.upcastEffect = upcastEffect
        self.grantsTriggeredEffect = grantsTriggeredEffect
        self.effects = effects
        self.damageTypeChoices = damageTypeChoices
        self.classes = classes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        name         = try c.decode(String.self, forKey: .name)
        level        = try c.decode(Int.self, forKey: .level)
        school       = try c.decode(SpellSchool.self, forKey: .school)
        castingTime  = try c.decode(CastingTime.self, forKey: .castingTime)
        range        = try c.decode(SpellRange.self, forKey: .range)
        components   = try c.decode(SpellComponents.self, forKey: .components)
        duration     = try c.decode(SpellDuration.self, forKey: .duration)
        description  = try c.decode(String.self, forKey: .description)
        higherLevel  = try c.decodeIfPresent(String.self, forKey: .higherLevel)
        actionRecipes = try c.decodeIfPresent([ActionRecipe].self, forKey: .actionRecipes) ?? []
        upcastEffect  = try c.decodeIfPresent(UpcastEffect.self, forKey: .upcastEffect)
        grantsTriggeredEffect = try c.decodeIfPresent(TriggeredEffect.self, forKey: .grantsTriggeredEffect)
        effects = try c.decodeIfPresent([SpellEffect].self, forKey: .effects) ?? []
        damageTypeChoices = try c.decodeIfPresent([DamageType].self, forKey: .damageTypeChoices) ?? []
        classes = try c.decodeIfPresent([String].self, forKey: .classes) ?? []
    }

    /// Returns the spell's recipes with upcast scaling applied for the given
    /// cast level. Cantrips and casts at base level return unchanged. Pure
    /// function — extracted so the cast view's scaling math is testable.
    func recipes(castAtLevel castLevel: Int) -> [ActionRecipe] {
        let extraLevels = max(0, castLevel - level)
        guard let effect = upcastEffect, extraLevels > 0 else { return actionRecipes }
        switch effect {
        case .extraDicePerLevel(let index, let dice):
            guard actionRecipes.indices.contains(index) else { return actionRecipes }
            var copy = actionRecipes
            copy[index] = Self.scaledRecipe(copy[index], extraDice: dice, times: extraLevels)
            return copy
        case .extraTargetsPerLevel:
            return actionRecipes
        }
    }

    private static func scaledRecipe(_ recipe: ActionRecipe, extraDice: String, times: Int) -> ActionRecipe {
        let extra = Array(repeating: extraDice, count: times).joined(separator: "+")
        switch recipe {
        case .rawDamage(let dice, let damageType, let addMod, let label):
            return .rawDamage(dice: "\(dice)+\(extra)", damageType: damageType, addSpellcastingMod: addMod, label: label)
        case .heal(let dice, let addLevel, let addMod, let label):
            return .heal(dice: "\(dice)+\(extra)", addLevel: addLevel, addSpellcastingMod: addMod, label: label)
        default:
            return recipe
        }
    }
}

/// A sheet state change a spell produces. Caster-targeted effects apply to the
/// caster automatically on cast; `targetCondition` is surfaced as a manual
/// "apply to this character" button (the one-PC app has no enemy sheet, but the
/// player is often the *target* a DM calls out).
enum SpellEffect: Codable, Equatable {
    /// Caster gains temporary HP from a dice formula (False Life → "2d4+4").
    /// Temp HP doesn't stack — the higher value wins.
    case tempHP(dice: String)
    /// Caster gains a condition on cast (a self-buff like Invisibility on self).
    case selfCondition(id: String)
    /// The spell imposes a condition on its target (Hold Person → paralyzed).
    /// Offered as an apply button rather than auto-applied.
    case targetCondition(id: String)
    /// A timed buff the cast lands on the caster's own sheet — AC, attack/save
    /// dice (Bless), speed, or an unarmored AC base (Mage Armor). Parked as an
    /// `ActiveEffect` so it ticks down with rounds and drops with concentration.
    case selfBuff(SpellBuffEffect)

    private enum CodingKeys: String, CodingKey { case type, dice, condition, buff }
    private enum Kind: String, Codable { case tempHP, selfCondition, targetCondition, selfBuff }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .tempHP:
            self = .tempHP(dice: try c.decode(String.self, forKey: .dice))
        case .selfCondition:
            self = .selfCondition(id: try c.decode(String.self, forKey: .condition))
        case .targetCondition:
            self = .targetCondition(id: try c.decode(String.self, forKey: .condition))
        case .selfBuff:
            self = .selfBuff(try c.decode(SpellBuffEffect.self, forKey: .buff))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tempHP(let dice):
            try c.encode(Kind.tempHP, forKey: .type)
            try c.encode(dice, forKey: .dice)
        case .selfCondition(let id):
            try c.encode(Kind.selfCondition, forKey: .type)
            try c.encode(id, forKey: .condition)
        case .targetCondition(let id):
            try c.encode(Kind.targetCondition, forKey: .type)
            try c.encode(id, forKey: .condition)
        case .selfBuff(let buff):
            try c.encode(Kind.selfBuff, forKey: .type)
            try c.encode(buff, forKey: .buff)
        }
    }
}

/// The mechanical payload of a `SpellEffect.selfBuff`. All fields optional/zero
/// so a spell declares only what it changes. Read back by `CharacterCalculator`
/// while the buff sits in `Character.activeEffects`.
struct SpellBuffEffect: Codable, Equatable {
    /// Flat AC bonus while active — Shield (+5), Shield of Faith (+2).
    var acBonus: Int
    /// Sets the unarmored AC base (10 → this) — Mage Armor → 13 (+ DEX). Only
    /// applies while no armor is worn; doesn't stack with Unarmored Defense
    /// (the better of the two wins). Nil for buffs that don't touch the base.
    var unarmoredACBase: Int?
    /// Dice added to every attack roll AND saving throw while active — Bless
    /// ("1d4"). Nil for buffs that don't touch d20 rolls.
    var attackAndSaveBonusDice: String?
    /// Walking-speed bonus in feet — Longstrider (+10).
    var speedBonus: Int
    /// Lifetime in combat rounds; nil for buffs measured in minutes/hours that
    /// persist until dismissed or concentration drops (Mage Armor, Longstrider).
    var rounds: Int?

    init(
        acBonus: Int = 0,
        unarmoredACBase: Int? = nil,
        attackAndSaveBonusDice: String? = nil,
        speedBonus: Int = 0,
        rounds: Int? = nil
    ) {
        self.acBonus = acBonus
        self.unarmoredACBase = unarmoredACBase
        self.attackAndSaveBonusDice = attackAndSaveBonusDice
        self.speedBonus = speedBonus
        self.rounds = rounds
    }

    private enum CodingKeys: String, CodingKey {
        case acBonus, unarmoredACBase, attackAndSaveBonusDice, speedBonus, rounds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acBonus = try c.decodeIfPresent(Int.self, forKey: .acBonus) ?? 0
        unarmoredACBase = try c.decodeIfPresent(Int.self, forKey: .unarmoredACBase)
        attackAndSaveBonusDice = try c.decodeIfPresent(String.self, forKey: .attackAndSaveBonusDice)
        speedBonus = try c.decodeIfPresent(Int.self, forKey: .speedBonus) ?? 0
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds)
    }
}
