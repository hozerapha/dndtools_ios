import Foundation

/// A homebrew content pack: a single JSON object with one optional array per
/// content category. This is both the IMPORT contract (what a user's `.json`
/// must look like) and the natural EXPORT shape. Every section is optional, so
/// a pack can ship just spells, just a class, or a full supplement.
///
/// ```json
/// {
///   "name": "Tomes of the Deep",
///   "classes": [ ... ],
///   "spells": [ ... ]
/// }
/// ```
///
/// `.zip` archives of per-category files (the original Phase H sketch) are
/// deferred — they'd need a zip dependency we haven't proposed. A single JSON
/// envelope is friendlier to share anyway.
struct ContentPack: Codable, Equatable {
    /// Display name for the Settings list. Defaults to the filename on import
    /// when the JSON omits it.
    var name: String?
    var classes: [ClassDefinition]?
    var species: [SpeciesDefinition]?
    var backgrounds: [BackgroundDefinition]?
    var weapons: [WeaponDefinition]?
    var armor: [ArmorDefinition]?
    var gear: [ItemDefinition]?
    var spells: [SpellDefinition]?
    var conditions: [ConditionDefinition]?
    var feats: [FeatDefinition]?

    /// Total entries across every section — used by the importer's summary
    /// ("Imported 1 class, 6 spells") and to reject an empty pack.
    var entryCount: Int {
        (classes?.count ?? 0) + (species?.count ?? 0) + (backgrounds?.count ?? 0)
            + (weapons?.count ?? 0) + (armor?.count ?? 0) + (gear?.count ?? 0)
            + (spells?.count ?? 0) + (conditions?.count ?? 0)
            + (feats?.count ?? 0)
    }

    /// Short per-category breakdown for the import-success message.
    var summary: String {
        var parts: [String] = []
        func add(_ n: Int?, _ singular: String, _ plural: String) {
            guard let n, n > 0 else { return }
            parts.append("\(n) \(n == 1 ? singular : plural)")
        }
        add(classes?.count, "class", "classes")
        add(species?.count, "species", "species")
        add(backgrounds?.count, "background", "backgrounds")
        add(weapons?.count, "weapon", "weapons")
        add(armor?.count, "armor", "armor")
        add(gear?.count, "item", "items")
        add(spells?.count, "spell", "spells")
        add(conditions?.count, "condition", "conditions")
        add(feats?.count, "feat", "feats")
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }
}
