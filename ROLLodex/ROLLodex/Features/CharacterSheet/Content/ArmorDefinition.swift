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
}
