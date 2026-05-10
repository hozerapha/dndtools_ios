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
}
