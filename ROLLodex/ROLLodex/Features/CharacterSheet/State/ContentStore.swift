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

    func itemName(forItemID id: String) -> String? {
        gear[id]?.name ?? weapons[id]?.name ?? armor[id]?.name
    }

    func itemWeight(forItemID id: String) -> Double? {
        gear[id]?.weight ?? weapons[id]?.weight ?? armor[id]?.weight
    }

    // MARK: - Loading

    private func loadBundledContent() {
        classes = loadDictionary(from: "classes", decode: [ClassDefinition].self)
        species = loadDictionary(from: "species", decode: [SpeciesDefinition].self)
        backgrounds = loadDictionary(from: "backgrounds", decode: [BackgroundDefinition].self)
        weapons = loadDictionary(from: "weapons", decode: [WeaponDefinition].self)
        armor = loadDictionary(from: "armor", decode: [ArmorDefinition].self)
        gear = loadDictionary(from: "gear", decode: [ItemDefinition].self)
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
