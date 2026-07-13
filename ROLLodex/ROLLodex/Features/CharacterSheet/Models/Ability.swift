import Foundation

// `nonisolated`: pure leaf enum used inside other nonisolated model
// types (ProficiencyKey) despite the target's MainActor default isolation.
nonisolated enum Ability: String, Codable, CaseIterable, Identifiable, Hashable {
    case strength = "strength"
    case dexterity = "dexterity"
    case constitution = "constitution"
    case intelligence = "intelligence"
    case wisdom = "wisdom"
    case charisma = "charisma"

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .strength: return "STR"
        case .dexterity: return "DEX"
        case .constitution: return "CON"
        case .intelligence: return "INT"
        case .wisdom: return "WIS"
        case .charisma: return "CHA"
        }
    }
}

/// Lets `[Ability: Int]` encode/decode as a JSON object (`{"strength": 10, …}`)
/// instead of Swift's default alternating-array shape. Without this,
/// `Character.abilityScores` round-trips as a flat array of interleaved keys
/// and values — technically valid JSON but hostile to hand-authored fixtures,
/// tests, and any homebrew content pack a user might write.
extension Ability: CodingKeyRepresentable {
    var codingKey: some CodingKey { RawCodingKey(rawValue) }

    init?<T: CodingKey>(codingKey: T) {
        guard let ability = Ability(rawValue: codingKey.stringValue) else { return nil }
        self = ability
    }
}

/// Minimal `CodingKey` used only to bridge `Ability` into
/// `CodingKeyRepresentable`. Int keys are never used for abilities.
private struct RawCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
