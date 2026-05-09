import Foundation

struct ItemDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let cost: Int
    let weight: Double
    let category: ItemCategory
}
