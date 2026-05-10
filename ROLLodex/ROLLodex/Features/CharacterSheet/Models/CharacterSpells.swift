import Foundation

/// The character's spell list. Stored as three string arrays of spell IDs;
/// each casting class reads whichever subset it cares about:
///
/// - `knownIDs` — bards, sorcerers, rangers, warlocks (fixed daily list).
/// - `spellbookIDs` — wizards (their spellbook; prepared list is a subset).
/// - `preparedIDs` — clerics, druids, paladins, and wizards (today's prep).
///
/// The same character might use multiple lists (multi-class), so we store
/// all three rather than collapsing into one. Empty arrays default in.
struct CharacterSpells: Codable, Equatable, Hashable {
    var preparedIDs: [String]
    var knownIDs: [String]
    var spellbookIDs: [String]

    init(
        preparedIDs: [String] = [],
        knownIDs: [String] = [],
        spellbookIDs: [String] = []
    ) {
        self.preparedIDs = preparedIDs
        self.knownIDs = knownIDs
        self.spellbookIDs = spellbookIDs
    }

    var isEmpty: Bool {
        preparedIDs.isEmpty && knownIDs.isEmpty && spellbookIDs.isEmpty
    }
}
