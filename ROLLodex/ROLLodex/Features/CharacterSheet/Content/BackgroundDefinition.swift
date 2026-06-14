import Foundation

struct BackgroundDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// The three abilities this background lets the player boost. Per the
    /// 2024 rule, the player distributes either +2/+1 across two of them or
    /// +1 to all three — that distribution is the player's choice at creation
    /// (stored on the character), not baked into the background.
    let abilityScoreOptions: [Ability]
    let skillProficiencies: [Skill]
    let feat: String?
    let toolProficiency: String?
    let equipment: [String]
}
