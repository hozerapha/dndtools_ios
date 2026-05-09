import Foundation

struct TraitDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let actionRecipes: [ActionRecipe]
}

struct SpeciesDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let size: String
    let speed: Int
    let traits: [TraitDefinition]
}
