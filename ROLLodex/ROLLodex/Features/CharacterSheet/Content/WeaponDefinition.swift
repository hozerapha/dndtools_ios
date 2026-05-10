import Foundation

struct WeaponDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let cost: Int
    let weight: Double
    let category: ItemCategory = .weapon
    let weaponCategory: WeaponCategory
    let damage: String
    let damageType: DamageType
    let damageAbility: Ability?
    let properties: [WeaponProperty]
    let versatileDamage: String?
    let range: String?
    let masteryProperty: WeaponMastery?
    let actionRecipes: [ActionRecipe]
    let attunement: AttunementRule?
    let resource: ResourceDefinition?
    let uses: [ItemUse]

    init(
        id: String,
        name: String,
        description: String,
        cost: Int,
        weight: Double,
        weaponCategory: WeaponCategory,
        damage: String,
        damageType: DamageType,
        damageAbility: Ability?,
        properties: [WeaponProperty],
        versatileDamage: String? = nil,
        range: String? = nil,
        masteryProperty: WeaponMastery? = nil,
        actionRecipes: [ActionRecipe] = [],
        attunement: AttunementRule? = nil,
        resource: ResourceDefinition? = nil,
        uses: [ItemUse] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cost = cost
        self.weight = weight
        self.weaponCategory = weaponCategory
        self.damage = damage
        self.damageType = damageType
        self.damageAbility = damageAbility
        self.properties = properties
        self.versatileDamage = versatileDamage
        self.range = range
        self.masteryProperty = masteryProperty
        self.actionRecipes = actionRecipes
        self.attunement = attunement
        self.resource = resource
        self.uses = uses
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, cost, weight
        case weaponCategory, damage, damageType, damageAbility
        case properties, versatileDamage, range, masteryProperty
        case actionRecipes, attunement, resource, uses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        description     = try c.decode(String.self, forKey: .description)
        cost            = try c.decode(Int.self, forKey: .cost)
        weight          = try c.decode(Double.self, forKey: .weight)
        weaponCategory  = try c.decode(WeaponCategory.self, forKey: .weaponCategory)
        damage          = try c.decode(String.self, forKey: .damage)
        damageType      = try c.decode(DamageType.self, forKey: .damageType)
        damageAbility   = try c.decodeIfPresent(Ability.self, forKey: .damageAbility)
        properties      = try c.decodeIfPresent([WeaponProperty].self, forKey: .properties) ?? []
        versatileDamage = try c.decodeIfPresent(String.self, forKey: .versatileDamage)
        range           = try c.decodeIfPresent(String.self, forKey: .range)
        masteryProperty = try c.decodeIfPresent(WeaponMastery.self, forKey: .masteryProperty)
        actionRecipes   = try c.decodeIfPresent([ActionRecipe].self, forKey: .actionRecipes) ?? []
        attunement      = try c.decodeIfPresent(AttunementRule.self, forKey: .attunement)
        resource        = try c.decodeIfPresent(ResourceDefinition.self, forKey: .resource)
        uses            = try c.decodeIfPresent([ItemUse].self, forKey: .uses) ?? []
    }
}
