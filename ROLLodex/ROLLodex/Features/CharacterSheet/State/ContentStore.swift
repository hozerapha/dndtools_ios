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

    /// User-imported packs live here (one `.json` per pack), separate from the
    /// read-only bundled SRD. Overlaid on top of bundled content at load,
    /// shadowing by id.
    private let importedContentDirectory: URL

    convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.init(importedContentDirectory: documents.appendingPathComponent("Content"))
    }

    init(importedContentDirectory: URL) {
        self.importedContentDirectory = importedContentDirectory
        try? FileManager.default.createDirectory(at: importedContentDirectory, withIntermediateDirectories: true)
        reload()
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

    /// (Re)build every content dictionary: bundled SRD as the base, then each
    /// imported pack overlaid on top so imported entries shadow bundled ones
    /// by id. Packs are applied in filename order (last wins on a collision
    /// between two imported packs). Called on init and after any import/remove.
    func reload() {
        let packs = loadImportedPacks().map(\.pack)
        classes     = merged(loadDictionary(from: "classes", decode: [ClassDefinition].self), packs.compactMap(\.classes))
        species     = merged(loadDictionary(from: "species", decode: [SpeciesDefinition].self), packs.compactMap(\.species))
        backgrounds = merged(loadDictionary(from: "backgrounds", decode: [BackgroundDefinition].self), packs.compactMap(\.backgrounds))
        weapons     = merged(loadDictionary(from: "weapons", decode: [WeaponDefinition].self), packs.compactMap(\.weapons))
        armor       = merged(loadDictionary(from: "armor", decode: [ArmorDefinition].self), packs.compactMap(\.armor))
        gear        = merged(loadDictionary(from: "gear", decode: [ItemDefinition].self), packs.compactMap(\.gear))
        spells      = merged(loadDictionary(from: "spells", decode: [SpellDefinition].self), packs.compactMap(\.spells))
        conditions  = merged(loadDictionary(from: "conditions", decode: [ConditionDefinition].self), packs.compactMap(\.conditions))
    }

    private func merged<T: Identifiable>(
        _ base: [String: T],
        _ imported: [[T]]
    ) -> [String: T] where T.ID == String {
        var dict = base
        for array in imported {
            for item in array { dict[item.id] = item }
        }
        return dict
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

    // MARK: - Imported packs (Phase H)

    /// What can go wrong importing a user-supplied pack. Unlike bundled
    /// content (a `fatalError` build bug), imported packs fail gracefully
    /// into an error sheet.
    enum ImportError: LocalizedError {
        case unreadable
        case malformed(String)
        case invalid([String])

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Couldn't read the selected file."
            case .malformed(let detail):
                return "That isn't a valid content pack.\n\(detail)"
            case .invalid(let issues):
                return issues.joined(separator: "\n")
            }
        }
    }

    /// One imported pack as shown in Settings.
    struct ImportedPackInfo: Identifiable {
        let fileName: String
        let name: String
        let summary: String
        var id: String { fileName }
    }

    private struct LoadedPack {
        let fileName: String
        let pack: ContentPack
    }

    /// Validate a user-selected `.json` content pack, persist it into
    /// `Documents/Content/`, and reload. Throws `ImportError` (with a
    /// human-readable message) on any failure so the caller can surface a
    /// sheet. Returns the decoded pack for the success summary.
    @discardableResult
    func importPack(from url: URL) throws -> ContentPack {
        // Files from the document picker are security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try importPack(data: data, suggestedName: url.deletingPathExtension().lastPathComponent)
    }

    /// Core import: validate `data` as a `ContentPack`, persist, reload.
    /// Shared by the file picker and the dev paste box. `suggestedName` is the
    /// fallback display name when the pack JSON omits its own `name`.
    @discardableResult
    func importPack(data: Data, suggestedName: String?) throws -> ContentPack {
        let pack: ContentPack
        do {
            pack = try JSONDecoder().decode(ContentPack.self, from: data)
        } catch {
            throw ImportError.malformed(error.localizedDescription)
        }

        let issues = ContentValidator.validate(pack)
        guard issues.isEmpty else { throw ImportError.invalid(issues) }

        // Filename derives from the pack's display name; re-importing a
        // same-named pack replaces it (the common "fix a bug and re-import"
        // case). Persist the ORIGINAL bytes so what's stored is exactly what
        // validated.
        let displayName = pack.name ?? suggestedName ?? "Imported Pack"
        let dest = importedContentDirectory.appendingPathComponent("\(sanitize(displayName)).json")
        try data.write(to: dest, options: .atomic)

        reload()
        return pack
    }

    /// Imported packs currently on disk, for the Settings list.
    var importedPacks: [ImportedPackInfo] {
        loadImportedPacks().map { loaded in
            ImportedPackInfo(
                fileName: loaded.fileName,
                name: loaded.pack.name ?? (loaded.fileName as NSString).deletingPathExtension,
                summary: loaded.pack.summary
            )
        }
    }

    /// Remove an imported pack file and reload (bundled content for any ids it
    /// shadowed re-surfaces automatically).
    func removeImportedPack(fileName: String) {
        let url = importedContentDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func loadImportedPacks() -> [LoadedPack] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: importedContentDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let pack = try? JSONDecoder().decode(ContentPack.self, from: data)
                else { return nil }
                return LoadedPack(fileName: url.lastPathComponent, pack: pack)
            }
    }

    /// Collapse a display name to a filesystem-safe slug for the pack file.
    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        // `Swift.Character` is explicit because this module's `Character` is
        // the D&D model type, which would otherwise shadow the grapheme.
        var slug = ""
        for scalar in name.unicodeScalars {
            slug.append(allowed.contains(scalar) ? Swift.Character(scalar) : "-")
        }
        let trimmed = slug.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "imported-pack" : trimmed
    }
}
