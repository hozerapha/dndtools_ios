import Foundation

struct FeatureDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let actionRecipes: [ActionRecipe]
    /// If non-nil, this feature sets the character's attunement slot count
    /// while it is active. The calculator picks the highest value across all
    /// active features (Artificer's "Magic Item Adept" → 4, "Master" → 5,
    /// "Savant" → 6). Absent means the feature doesn't touch attunement.
    let attunementSlots: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, actionRecipes, attunementSlots
    }

    init(
        id: String,
        name: String,
        description: String,
        actionRecipes: [ActionRecipe] = [],
        attunementSlots: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.actionRecipes = actionRecipes
        self.attunementSlots = attunementSlots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        actionRecipes = try c.decodeIfPresent([ActionRecipe].self, forKey: .actionRecipes) ?? []
        attunementSlots = try c.decodeIfPresent(Int.self, forKey: .attunementSlots)
    }
}
