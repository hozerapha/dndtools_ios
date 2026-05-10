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
}
