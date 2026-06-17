import Foundation

/// A species trait is mechanically identical to a class feature: a named,
/// described capability that may carry action recipes, a resource pool, a
/// player choice (lineage / ancestry), or granted action options. Rather than
/// maintain a parallel, weaker struct, a trait *is* a `FeatureDefinition`.
/// The alias keeps the domain vocabulary ("trait") at call sites. Existing
/// species JSON (`{id,name,description,actionRecipes}`) still decodes — every
/// other `FeatureDefinition` field is optional with a sensible default.
typealias TraitDefinition = FeatureDefinition

struct SpeciesDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let size: String
    let speed: Int
    let traits: [TraitDefinition]
}
