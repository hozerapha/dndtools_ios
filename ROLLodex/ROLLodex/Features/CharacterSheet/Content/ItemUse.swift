import Foundation

/// A tappable action exposed by an item — typically "expend a charge to cast
/// the spell baked into this item". Sits alongside `resource` on an item
/// definition. Carries its own cost so the cost is whatever the item author
/// declared (Wand of Magic Missiles costs 1 charge per slot level above 1st).
struct ItemUse: Codable, Equatable {
    /// Stable id used to compose the action grid row's id (`itemUse_wand_of_mm_cast`).
    let id: String
    /// Display label on the action grid ("Cast Magic Missile").
    let name: String
    /// Pool to debit when the use fires. The amount stored here is the *base*
    /// cost; upcasts add `upcastChoice.extraCostPerLevel` on top.
    let cost: ItemUseCost
    let effect: ItemUseEffect
    /// When set, the cast sheet shows a level picker (Wand of MM: 1st–3rd).
    /// Nil means the item only ever fires at one level.
    let upcastChoice: UpcastChoice?

    init(
        id: String,
        name: String,
        cost: ItemUseCost,
        effect: ItemUseEffect,
        upcastChoice: UpcastChoice? = nil
    ) {
        self.id = id
        self.name = name
        self.cost = cost
        self.effect = effect
        self.upcastChoice = upcastChoice
    }
}

/// What an item's tappable action does when invoked.
enum ItemUseEffect: Codable, Equatable {
    /// Open the spell-cast flow with the item supplying the slot (and the
    /// upcast cost coming from the use's `upcastChoice` rather than the
    /// character's spell slots).
    case castSpell(spellID: String, atLevel: Int)
    /// Resolve a plain recipe list (e.g., a Potion of Healing's `heal` recipe
    /// chain). Routes through `ActionInterpreter` like any feature recipe.
    case actionRecipes([ActionRecipe])

    private enum CodingKeys: String, CodingKey {
        case type, spellID, atLevel, recipes
    }

    private enum Kind: String, Codable {
        case castSpell, actionRecipes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .castSpell:
            let spellID = try c.decode(String.self, forKey: .spellID)
            let level = try c.decode(Int.self, forKey: .atLevel)
            self = .castSpell(spellID: spellID, atLevel: level)
        case .actionRecipes:
            let recipes = try c.decode([ActionRecipe].self, forKey: .recipes)
            self = .actionRecipes(recipes)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .castSpell(let id, let level):
            try c.encode(Kind.castSpell, forKey: .type)
            try c.encode(id, forKey: .spellID)
            try c.encode(level, forKey: .atLevel)
        case .actionRecipes(let recipes):
            try c.encode(Kind.actionRecipes, forKey: .type)
            try c.encode(recipes, forKey: .recipes)
        }
    }
}

/// Cost to invoke an `ItemUse`. The resourceID names a pool the owning item
/// (or another item the user controls) declares — typically the item's own
/// charges block (`<itemID>_charges`).
struct ItemUseCost: Codable, Equatable {
    let resourceID: String
    /// Base charges per invocation. For upcastable uses, the cast sheet adds
    /// `upcastChoice.extraCostPerLevel` per slot level above the base.
    let amount: Int
}

/// Upcast pricing for an `ItemUse`. The cast sheet renders one button per
/// slot level in the range; the total cost is `cost.amount + (level - base) * extraCostPerLevel`.
struct UpcastChoice: Codable, Equatable {
    /// Highest slot level the item can cast at (inclusive). Base level comes
    /// from the `castSpell` effect.
    let maxLevel: Int
    /// Additional charges consumed per slot level above the base.
    let extraCostPerLevel: Int
}
