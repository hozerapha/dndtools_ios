import Foundation

/// A pool of charges / uses / slots that a feature, item, or class grants.
/// Lives inline on the entity that owns it — a Fighter feature carries its
/// own Second Wind resource, a magic item carries its own charges, a class
/// spellcasting block synthesizes one resource per slot level.
///
/// Per the locked-in decision in PLAN_CharacterSheet.md, the character JSON
/// only stores the `current` value keyed by `id` — the max and refresh rule
/// always come from content so that schema edits propagate automatically.
struct ResourceDefinition: Codable, Equatable {
    /// Globally unique within content (e.g., `fighter_second_wind`,
    /// `wand_of_mm_charges`). Used as the key on the character's resource
    /// state dictionary.
    let id: String
    /// Display name on the sheet (independent of the owning feature's name).
    let name: String
    let max: LevelScaledValue
    /// When set, the pool's max is this ability's modifier (minimum 1) rather
    /// than the level-scaled `max` — the 2024 "uses equal to your Charisma
    /// modifier" shape (Bardic Inspiration). `max` is still decoded and used as
    /// the fallback (e.g. minimum) when resolving.
    let maxAbilityModifier: Ability?
    let refreshOn: RefreshTrigger
    let refreshAmount: RefreshAmount
    let displayHint: ResourceDisplayHint?

    init(
        id: String,
        name: String,
        max: LevelScaledValue,
        maxAbilityModifier: Ability? = nil,
        refreshOn: RefreshTrigger,
        refreshAmount: RefreshAmount,
        displayHint: ResourceDisplayHint? = nil
    ) {
        self.id = id
        self.name = name
        self.max = max
        self.maxAbilityModifier = maxAbilityModifier
        self.refreshOn = refreshOn
        self.refreshAmount = refreshAmount
        self.displayHint = displayHint
    }
}

/// Optional UI grouping hint. Phase J spells will use `.spellSlot(level:)` so
/// the spells UI can collect synthesized slot resources together; other
/// surfaces just render them in the generic resources list.
enum ResourceDisplayHint: Codable, Equatable {
    case spellSlot(level: Int)

    private enum CodingKeys: String, CodingKey {
        case kind, level
    }

    private enum Kind: String, Codable {
        case spellSlot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .spellSlot:
            self = .spellSlot(level: try c.decode(Int.self, forKey: .level))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spellSlot(let level):
            try c.encode(Kind.spellSlot, forKey: .kind)
            try c.encode(level, forKey: .level)
        }
    }
}
