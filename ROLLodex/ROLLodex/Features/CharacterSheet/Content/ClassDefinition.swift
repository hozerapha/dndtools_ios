import Foundation

struct ClassDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let hitDie: DieKind
    let primaryAbility: Ability
    let savingThrows: [Ability]
    let armorProficiencies: [ArmorCategory]
    let weaponProficiencies: [WeaponCategory]
    let levelFeatures: [Int: [FeatureDefinition]]
    let masteryCount: Int?
    let masteryRestrictions: [String]
}
