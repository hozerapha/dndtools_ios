import Foundation

/// The character's spell list. Stored as string arrays of spell IDs; each
/// casting class reads whichever subset it cares about:
///
/// - `preparedByClass` — per-class daily prepared lists, keyed by class ID
///   (clerics, druids, paladins, wizards). Each prepared caster prepares
///   separately with its own cap (5e multiclass rule).
/// - `knownIDs` — bards, sorcerers, rangers, warlocks (fixed daily list).
/// - `spellbookIDs` — wizards (their spellbook; prepared list is a subset).
/// - `preparedIDs` — LEGACY flat prepared list. Migrated into
///   `preparedByClass[firstClassID]` by `Character`'s decoder; kept in the
///   schema so old character files load, but new writes go per-class.
///
/// The same character might use multiple lists (multi-class), so we store
/// all of them rather than collapsing into one. Empty defaults in.
struct CharacterSpells: Codable, Equatable, Hashable {
    var preparedIDs: [String]
    var knownIDs: [String]
    var spellbookIDs: [String]
    var preparedByClass: [String: [String]]

    init(
        preparedIDs: [String] = [],
        knownIDs: [String] = [],
        spellbookIDs: [String] = [],
        preparedByClass: [String: [String]] = [:]
    ) {
        self.preparedIDs = preparedIDs
        self.knownIDs = knownIDs
        self.spellbookIDs = spellbookIDs
        self.preparedByClass = preparedByClass
    }

    private enum CodingKeys: String, CodingKey {
        case preparedIDs, knownIDs, spellbookIDs, preparedByClass
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preparedIDs = try c.decodeIfPresent([String].self, forKey: .preparedIDs) ?? []
        knownIDs = try c.decodeIfPresent([String].self, forKey: .knownIDs) ?? []
        spellbookIDs = try c.decodeIfPresent([String].self, forKey: .spellbookIDs) ?? []
        preparedByClass = try c.decodeIfPresent([String: [String]].self, forKey: .preparedByClass) ?? [:]
    }

    var isEmpty: Bool {
        preparedIDs.isEmpty && knownIDs.isEmpty && spellbookIDs.isEmpty
            && preparedByClass.values.allSatisfy(\.isEmpty)
    }

    /// Every prepared spell id across all classes plus the legacy flat list
    /// (pre-migration files, defensive). Order-stable: legacy first, then
    /// classes alphabetically.
    var allPreparedIDs: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in preparedIDs where seen.insert(id).inserted { out.append(id) }
        for classID in preparedByClass.keys.sorted() {
            for id in preparedByClass[classID] ?? [] where seen.insert(id).inserted {
                out.append(id)
            }
        }
        return out
    }

    /// Move the legacy flat prepared list into the given class's bucket.
    /// Called by `Character`'s decoder (which knows the class list) so
    /// single-class saves from before per-class prep keep working. No-op when
    /// there's nothing to migrate or the bucket is already populated.
    mutating func migrateLegacyPrepared(toClassID classID: String) {
        guard !preparedIDs.isEmpty, preparedByClass[classID, default: []].isEmpty else { return }
        preparedByClass[classID] = preparedIDs
        preparedIDs = []
    }
}
