import Foundation

struct ArmorDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let cost: Int
    let weight: Double
    let category: ItemCategory = .armor
    let armorCategory: ArmorCategory
    let acBase: Int
    let dexCap: Int?
    let stealthDisadvantage: Bool
    let strengthRequirement: Int?
    let attunement: AttunementRule?
    let resource: ResourceDefinition?
    let uses: [ItemUse]

    init(
        id: String,
        name: String,
        description: String,
        cost: Int,
        weight: Double,
        armorCategory: ArmorCategory,
        acBase: Int,
        dexCap: Int? = nil,
        stealthDisadvantage: Bool = false,
        strengthRequirement: Int? = nil,
        attunement: AttunementRule? = nil,
        resource: ResourceDefinition? = nil,
        uses: [ItemUse] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cost = cost
        self.weight = weight
        self.armorCategory = armorCategory
        self.acBase = acBase
        self.dexCap = dexCap
        self.stealthDisadvantage = stealthDisadvantage
        self.strengthRequirement = strengthRequirement
        self.attunement = attunement
        self.resource = resource
        self.uses = uses
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, cost, weight
        case armorCategory, acBase, dexCap, stealthDisadvantage, strengthRequirement
        case attunement, resource, uses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(String.self, forKey: .id)
        name                 = try c.decode(String.self, forKey: .name)
        description          = try c.decode(String.self, forKey: .description)
        cost                 = try c.decode(Int.self,    forKey: .cost)
        weight               = try c.decode(Double.self, forKey: .weight)
        armorCategory        = try c.decode(ArmorCategory.self, forKey: .armorCategory)
        acBase               = try c.decode(Int.self, forKey: .acBase)
        dexCap               = try c.decodeIfPresent(Int.self,  forKey: .dexCap)
        stealthDisadvantage  = try c.decodeIfPresent(Bool.self, forKey: .stealthDisadvantage) ?? false
        strengthRequirement  = try c.decodeIfPresent(Int.self,  forKey: .strengthRequirement)
        attunement           = try c.decodeIfPresent(AttunementRule.self, forKey: .attunement)
        resource             = try c.decodeIfPresent(ResourceDefinition.self, forKey: .resource)
        uses                 = try c.decodeIfPresent([ItemUse].self, forKey: .uses) ?? []
    }
}
