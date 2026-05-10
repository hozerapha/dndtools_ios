import Foundation

/// Informational categorization for the Features tab UI. Drives icon /
/// header styling and lets the view branch on "is this a toggleable thing,
/// a charge pool, just text…" without inspecting every field. Defaults to
/// `.passive` when the JSON omits a `kind`.
enum FeatureKind: String, Codable, Equatable {
    /// Pure text — no resource, no selection, no action recipe. Goblin
    /// Nimble Escape, racial Darkvision, Fighting Style flavor.
    case passive
    /// Has a resource pool (charges) and/or an action recipe. Second Wind,
    /// Wild Shape, Bardic Inspiration.
    case active
    /// Player makes a binding choice (kept in `Character.featureSelections`).
    /// Weapon Mastery, Eldritch Invocations, Metamagic.
    case selection
    /// Toggleable state that modifies other rolls when on. Rage, Innate
    /// Sorcery. The mechanical hooks land in Phase O — for now the kind is
    /// purely a UI tag so the Features tab can render an on/off switch.
    case toggle
}

/// Description of a "pick N from a list" choice attached to a feature. The
/// player's picks are persisted under `Character.featureSelections[id]`.
///
/// JSON:
/// ```
/// "selection": {
///   "id": "weapon_mastery",
///   "prompt": "Choose 3 weapons to master",
///   "count": 3,
///   "optionsSource": { "type": "weapons", "proficientOnly": true }
/// }
/// ```
struct FeatureSelection: Codable, Equatable {
    /// Key into `Character.featureSelections`. Conventionally equal to the
    /// owning feature's `id`, but explicit so two features can share a slot
    /// (e.g., a multiclass that grants the same Mastery feature twice).
    let id: String
    /// Prompt rendered above the picker.
    let prompt: String
    /// How many options the player chooses. `LevelScaledValue` so growth
    /// tables (Eldritch Invocations 2 → 3 → …) work without code changes.
    let count: LevelScaledValue
    /// Where the options come from.
    let optionsSource: SelectionSource
}

/// What the player picks from. Each case carries its own list-building rules;
/// the Features tab branches on the case to pick the right picker UI.
enum SelectionSource: Codable, Equatable {
    /// Pick weapon IDs from the content store. `proficientOnly: true`
    /// restricts to weapons whose category the character is proficient in
    /// (most class Weapon Mastery features).
    case weapons(proficientOnly: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, proficientOnly
    }

    private enum Kind: String, Codable {
        case weapons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .weapons:
            let proficient = try c.decodeIfPresent(Bool.self, forKey: .proficientOnly) ?? false
            self = .weapons(proficientOnly: proficient)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .weapons(let proficient):
            try c.encode(Kind.weapons, forKey: .type)
            try c.encode(proficient, forKey: .proficientOnly)
        }
    }
}
