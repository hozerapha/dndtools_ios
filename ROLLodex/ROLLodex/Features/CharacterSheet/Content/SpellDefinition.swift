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

    var isCantrip: Bool { level == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, level, school, castingTime, range, components, duration
        case description, higherLevel, actionRecipes, upcastEffect
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
        upcastEffect: UpcastEffect? = nil
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
        case .rawDamage(let dice, let damageType, let label):
            return .rawDamage(dice: "\(dice)+\(extra)", damageType: damageType, label: label)
        case .heal(let dice, let addLevel, let label):
            return .heal(dice: "\(dice)+\(extra)", addLevel: addLevel, label: label)
        default:
            return recipe
        }
    }
}
