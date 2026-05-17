import Foundation
import Observation

@Observable
@MainActor
final class ContentStore {
    private(set) var classes: [String: ClassDefinition] = [:]
    private(set) var species: [String: SpeciesDefinition] = [:]
    private(set) var backgrounds: [String: BackgroundDefinition] = [:]
    private(set) var weapons: [String: WeaponDefinition] = [:]
    private(set) var armor: [String: ArmorDefinition] = [:]
    private(set) var gear: [String: ItemDefinition] = [:]
    private(set) var spells: [String: SpellDefinition] = [:]
    private(set) var conditions: [String: ConditionDefinition] = [:]

    init() {
        loadBundledContent()
    }

    // MARK: - Lookups

    func classDefinition(id: String) -> ClassDefinition? { classes[id] }
    func speciesDefinition(id: String) -> SpeciesDefinition? { species[id] }
    func backgroundDefinition(id: String) -> BackgroundDefinition? { backgrounds[id] }
    func weaponDefinition(id: String) -> WeaponDefinition? { weapons[id] }
    func armorDefinition(id: String) -> ArmorDefinition? { armor[id] }
    func gearDefinition(id: String) -> ItemDefinition? { gear[id] }
    func spellDefinition(id: String) -> SpellDefinition? { spells[id] }
    func conditionDefinition(id: String) -> ConditionDefinition? { conditions[id] }
    var allConditions: [ConditionDefinition] {
        conditions.values.sorted { $0.name < $1.name }
    }
    /// All bundled + loaded spells, sorted by level then name. Used by the
    /// "Add Spell" picker so the player can grant their character any spell
    /// regardless of class restrictions (v1 has no class spell lists).
    var allSpells: [SpellDefinition] {
        spells.values.sorted { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level < rhs.level }
            return lhs.name < rhs.name
        }
    }

    func itemName(forItemID id: String) -> String? {
        gear[id]?.name ?? weapons[id]?.name ?? armor[id]?.name
    }

    func itemWeight(forItemID id: String) -> Double? {
        gear[id]?.weight ?? weapons[id]?.weight ?? armor[id]?.weight
    }

    /// Flavor / mechanical description for the item ("This wand has 7 charges
    /// …"). Empty string if the item exists but has no description (rare).
    func itemDescription(forItemID id: String) -> String? {
        gear[id]?.description ?? weapons[id]?.description ?? armor[id]?.description
    }

    /// Returns the attunement rule for an item across all kinds (weapon /
    /// armor / gear). Nil result means either the item doesn't exist OR it
    /// doesn't require attunement — both are equivalent for the eligibility
    /// check (no toggle is shown).
    func attunementRule(forItemID id: String) -> AttunementRule? {
        if let w = weapons[id] { return w.attunement }
        if let a = armor[id]   { return a.attunement }
        if let g = gear[id]    { return g.attunement }
        return nil
    }

    /// Resource pool an item owns (Wand of Magic Missiles' charges, etc.).
    /// Nil for mundane items.
    func itemResource(forItemID id: String) -> ResourceDefinition? {
        if let w = weapons[id] { return w.resource }
        if let a = armor[id]   { return a.resource }
        if let g = gear[id]    { return g.resource }
        return nil
    }

    /// Tappable actions an item exposes ("Cast Magic Missile", "Drink", etc.).
    /// Empty for items that just sit in inventory.
    func itemUses(forItemID id: String) -> [ItemUse] {
        if let w = weapons[id] { return w.uses }
        if let a = armor[id]   { return a.uses }
        if let g = gear[id]    { return g.uses }
        return []
    }

    // MARK: - Loading

    private func loadBundledContent() {
        classes = loadDictionary(from: "classes", decode: [ClassDefinition].self)
        species = loadDictionary(from: "species", decode: [SpeciesDefinition].self)
        backgrounds = loadDictionary(from: "backgrounds", decode: [BackgroundDefinition].self)
        weapons = loadDictionary(from: "weapons", decode: [WeaponDefinition].self)
        armor = loadDictionary(from: "armor", decode: [ArmorDefinition].self)
        gear = loadDictionary(from: "gear", decode: [ItemDefinition].self)
        spells = loadDictionary(from: "spells", decode: [SpellDefinition].self)
        conditions = loadDictionary(from: "conditions", decode: [ConditionDefinition].self)
    }

    private func loadDictionary<T: Codable & Identifiable>(
        from filename: String,
        decode type: [T].Type
    ) -> [String: T] where T.ID == String {
        let possibleURLs = [
            Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Content"),
            Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Resources/Content"),
            Bundle.main.url(forResource: filename, withExtension: "json")
        ]

        guard let url = possibleURLs.compactMap({ $0 }).first else {
            let allURLs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
            print("Available JSON files in bundle:")
            for u in allURLs {
                print("  - \(u.lastPathComponent) at \(u.path)")
            }
            fatalError("Missing bundled content: \(filename).json")
        }

        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode(type, from: data)
            return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        } catch {
            fatalError("Failed to decode \(filename).json: \(error)")
        }
    }
}
