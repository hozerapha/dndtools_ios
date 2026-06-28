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

    var isCantrip: Bool { level == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, level, school, castingTime, range, components, duration
        case description, higherLevel, actionRecipes, upcastEffect, grantsTriggeredEffect
        case effects
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
        effects: [SpellEffect] = []
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

    private enum CodingKeys: String, CodingKey { case type, dice, condition }
    private enum Kind: String, Codable { case tempHP, selfCondition, targetCondition }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .tempHP:
            self = .tempHP(dice: try c.decode(String.self, forKey: .dice))
        case .selfCondition:
            self = .selfCondition(id: try c.decode(String.self, forKey: .condition))
        case .targetCondition:
            self = .targetCondition(id: try c.decode(String.self, forKey: .condition))
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
        }
    }
}
