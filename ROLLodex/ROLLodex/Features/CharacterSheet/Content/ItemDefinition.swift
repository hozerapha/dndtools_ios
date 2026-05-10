import Foundation

struct ItemDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let cost: Int
    let weight: Double
    let category: ItemCategory
    /// JSON: presence of the `attunement` key means "requires attunement".
    /// Absence means freely usable. See `AttunementRule` for the schema.
    let attunement: AttunementRule?
    /// Charges / uses pool the item owns (Phase K). Nil for mundane gear.
    let resource: ResourceDefinition?
    /// Tappable actions the item exposes — e.g. "Cast Magic Missile" on a
    /// Wand of Magic Missiles. Empty for items that just sit in inventory.
    let uses: [ItemUse]

    init(
        id: String,
        name: String,
        description: String,
        cost: Int,
        weight: Double,
        category: ItemCategory,
        attunement: AttunementRule? = nil,
        resource: ResourceDefinition? = nil,
        uses: [ItemUse] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cost = cost
        self.weight = weight
        self.category = category
        self.attunement = attunement
        self.resource = resource
        self.uses = uses
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, cost, weight, category
        case attunement, resource, uses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        name        = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        cost        = try c.decode(Int.self,    forKey: .cost)
        weight      = try c.decode(Double.self, forKey: .weight)
        category    = try c.decode(ItemCategory.self, forKey: .category)
        attunement  = try c.decodeIfPresent(AttunementRule.self, forKey: .attunement)
        resource    = try c.decodeIfPresent(ResourceDefinition.self, forKey: .resource)
        uses        = try c.decodeIfPresent([ItemUse].self, forKey: .uses) ?? []
    }
}
