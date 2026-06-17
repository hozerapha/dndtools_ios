import Foundation

/// A spell conferred by a species trait, feature, or selection option
/// (Tiefling Fiendish Legacy → Fire Bolt; Drow Elven Lineage → Faerie Fire at
/// level 3). A granted spell is *always prepared*: it shows on the sheet
/// without spending the character's known / prepared budget. Cantrips are
/// usable at will; leveled grants unlock at `minCharacterLevel` (the SRD
/// lineages learn their higher-level spells at character levels 3 and 5).
struct SpellGrant: Codable, Equatable {
    let spellID: String
    /// Character level at which the grant becomes available. Defaults to 1
    /// (cantrips and level-1 always-prepared grants).
    let minCharacterLevel: Int

    init(spellID: String, minCharacterLevel: Int = 1) {
        self.spellID = spellID
        self.minCharacterLevel = minCharacterLevel
    }

    private enum CodingKeys: String, CodingKey {
        case spellID, minCharacterLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spellID = try c.decode(String.self, forKey: .spellID)
        minCharacterLevel = try c.decodeIfPresent(Int.self, forKey: .minCharacterLevel) ?? 1
    }
}
