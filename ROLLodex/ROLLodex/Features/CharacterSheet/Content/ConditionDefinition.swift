import Foundation

/// One of the 14 SRD conditions (plus user-importable homebrew). Pure content:
/// the character carries `[CharacterCondition]` referencing definitions by id,
/// and the calculator consults `effects` when deciding whether to grant
/// advantage / disadvantage / auto-fail.
struct ConditionDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let effects: [ConditionEffect]
}

/// Discriminated effect list. Phase L wires the prompts (advantage on attacks
/// against, etc.) into the dice handoff; downstream UI just renders the badge.
enum ConditionEffect: Codable, Equatable {
    case attacksAgainstHaveAdvantage
    case attacksAgainstHaveDisadvantage
    case attacksByHaveAdvantage
    case attacksByHaveDisadvantage
    case savingThrowDisadvantage(abilities: [Ability])
    case abilityCheckDisadvantage(abilities: [Ability])
    case cantTakeActions
    case cantTakeReactions
    case cantMove
    case speedZero
    case speedHalved
    case autoFailStrengthAndDexSaves
    case autoCritOnHit
    case incapacitated

    private enum CodingKeys: String, CodingKey {
        case type, abilities
    }

    private enum Kind: String, Codable {
        case attacksAgainstHaveAdvantage
        case attacksAgainstHaveDisadvantage
        case attacksByHaveAdvantage
        case attacksByHaveDisadvantage
        case savingThrowDisadvantage
        case abilityCheckDisadvantage
        case cantTakeActions
        case cantTakeReactions
        case cantMove
        case speedZero
        case speedHalved
        case autoFailStrengthAndDexSaves
        case autoCritOnHit
        case incapacitated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .attacksAgainstHaveAdvantage:    self = .attacksAgainstHaveAdvantage
        case .attacksAgainstHaveDisadvantage: self = .attacksAgainstHaveDisadvantage
        case .attacksByHaveAdvantage:         self = .attacksByHaveAdvantage
        case .attacksByHaveDisadvantage:      self = .attacksByHaveDisadvantage
        case .savingThrowDisadvantage:
            let abilities = try c.decodeIfPresent([Ability].self, forKey: .abilities) ?? []
            self = .savingThrowDisadvantage(abilities: abilities)
        case .abilityCheckDisadvantage:
            let abilities = try c.decodeIfPresent([Ability].self, forKey: .abilities) ?? []
            self = .abilityCheckDisadvantage(abilities: abilities)
        case .cantTakeActions:               self = .cantTakeActions
        case .cantTakeReactions:             self = .cantTakeReactions
        case .cantMove:                      self = .cantMove
        case .speedZero:                     self = .speedZero
        case .speedHalved:                   self = .speedHalved
        case .autoFailStrengthAndDexSaves:   self = .autoFailStrengthAndDexSaves
        case .autoCritOnHit:                 self = .autoCritOnHit
        case .incapacitated:                 self = .incapacitated
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .attacksAgainstHaveAdvantage:    try c.encode(Kind.attacksAgainstHaveAdvantage, forKey: .type)
        case .attacksAgainstHaveDisadvantage: try c.encode(Kind.attacksAgainstHaveDisadvantage, forKey: .type)
        case .attacksByHaveAdvantage:         try c.encode(Kind.attacksByHaveAdvantage, forKey: .type)
        case .attacksByHaveDisadvantage:      try c.encode(Kind.attacksByHaveDisadvantage, forKey: .type)
        case .savingThrowDisadvantage(let abilities):
            try c.encode(Kind.savingThrowDisadvantage, forKey: .type)
            try c.encode(abilities, forKey: .abilities)
        case .abilityCheckDisadvantage(let abilities):
            try c.encode(Kind.abilityCheckDisadvantage, forKey: .type)
            try c.encode(abilities, forKey: .abilities)
        case .cantTakeActions:             try c.encode(Kind.cantTakeActions, forKey: .type)
        case .cantTakeReactions:           try c.encode(Kind.cantTakeReactions, forKey: .type)
        case .cantMove:                    try c.encode(Kind.cantMove, forKey: .type)
        case .speedZero:                   try c.encode(Kind.speedZero, forKey: .type)
        case .speedHalved:                 try c.encode(Kind.speedHalved, forKey: .type)
        case .autoFailStrengthAndDexSaves: try c.encode(Kind.autoFailStrengthAndDexSaves, forKey: .type)
        case .autoCritOnHit:               try c.encode(Kind.autoCritOnHit, forKey: .type)
        case .incapacitated:               try c.encode(Kind.incapacitated, forKey: .type)
        }
    }
}
