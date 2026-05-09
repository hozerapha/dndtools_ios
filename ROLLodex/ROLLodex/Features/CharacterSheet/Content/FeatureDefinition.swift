import Foundation

struct FeatureDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let actionRecipes: [ActionRecipe]
}
