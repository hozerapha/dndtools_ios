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
    /// When the granted feat is Magic Initiate, the SRD locks the class list
    /// per background (Sage → Wizard, Acolyte → Cleric). Nil for other feats
    /// or for backgrounds that leave the list open. Consumed by the Magic
    /// Initiate spell picker to pre-lock the class-list step.
    let featClassList: String?
    let toolProficiency: String?
    let equipment: [String]

    init(
        id: String,
        name: String,
        abilityScoreOptions: [Ability],
        skillProficiencies: [Skill],
        feat: String? = nil,
        featClassList: String? = nil,
        toolProficiency: String? = nil,
        equipment: [String] = []
    ) {
        self.id = id
        self.name = name
        self.abilityScoreOptions = abilityScoreOptions
        self.skillProficiencies = skillProficiencies
        self.feat = feat
        self.featClassList = featClassList
        self.toolProficiency = toolProficiency
        self.equipment = equipment
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, abilityScoreOptions, skillProficiencies
        case feat, featClassList, toolProficiency, equipment
    }

    /// Custom decoder so hand-authored `backgrounds.json` can omit the new
    /// `featClassList` field without breaking existing entries.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(String.self, forKey: .id)
        name                  = try c.decode(String.self, forKey: .name)
        abilityScoreOptions   = try c.decode([Ability].self, forKey: .abilityScoreOptions)
        skillProficiencies    = try c.decode([Skill].self, forKey: .skillProficiencies)
        feat                  = try c.decodeIfPresent(String.self, forKey: .feat)
        featClassList         = try c.decodeIfPresent(String.self, forKey: .featClassList)
        toolProficiency       = try c.decodeIfPresent(String.self, forKey: .toolProficiency)
        equipment             = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
    }
}
