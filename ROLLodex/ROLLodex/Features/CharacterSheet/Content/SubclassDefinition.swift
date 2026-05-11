import Foundation

/// A subclass within a class — Champion / Battle Master / Eldritch Knight
/// for Fighter, School of Evocation for Wizard, etc. Stored inside the
/// owning `ClassDefinition` so the picker can list them by parent.
///
/// Subclasses contribute their own `levelFeatures` keyed by *class level*
/// (not subclass level). The character-sheet aggregator pulls the chosen
/// subclass's features at or below the character's class level, alongside
/// the base class features.
struct SubclassDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let levelFeatures: [Int: [FeatureDefinition]]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, levelFeatures
    }

    init(
        id: String,
        name: String,
        description: String,
        levelFeatures: [Int: [FeatureDefinition]]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.levelFeatures = levelFeatures
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        name          = try c.decode(String.self, forKey: .name)
        description   = try c.decode(String.self, forKey: .description)
        levelFeatures = try c.decode([Int: [FeatureDefinition]].self, forKey: .levelFeatures)
    }
}

/// One aggregated feature with its source metadata. Returned by
/// `ClassDefinition.resolvedFeatures(throughClassLevel:subclassID:)`; lets
/// callers render the right source label ("Fighter · L3" vs.
/// "Champion · L3") without duplicating the walk logic.
struct ResolvedFeature: Equatable {
    let feature: FeatureDefinition
    /// Class level at which the feature was granted (used for sparse-table
    /// resolution of resource caps, selection counts, etc.).
    let grantedAtLevel: Int
    /// Subclass name when this is a subclass feature; nil for plain class
    /// features.
    let subclassName: String?
}
