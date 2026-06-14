import Foundation

/// A named action option a feature confers — what the feature *lets you do*,
/// surfaced on the Actions tab grouped by economy so the player can see their
/// full turn at a glance (roadmap item 17). Cunning Action grants three:
/// Dash and Disengage (informational) and Hide (which rolls Stealth).
///
/// `recipe` nil = informational only (a reminder row with a description).
/// When present, the row is tappable and hands the roll to the dice tab.
struct GrantedAction: Codable, Equatable {
    let name: String
    let description: String?
    let cost: ActionCost
    let recipe: ActionRecipe?

    init(name: String, description: String? = nil, cost: ActionCost, recipe: ActionRecipe? = nil) {
        self.name = name
        self.description = description
        self.cost = cost
        self.recipe = recipe
    }
}
