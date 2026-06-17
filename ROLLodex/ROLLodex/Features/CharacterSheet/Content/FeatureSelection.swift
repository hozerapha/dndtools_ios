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
    /// Pick from an inline list of named options. The picked option's ID is
    /// what downstream lookups key off (e.g., Fighting Style: archery /
    /// defense / dueling). Mechanical effects live in the calculator and
    /// interpreter — the choice itself just records "which option".
    case fixedOptions(options: [SelectionOption])
    /// Pick a subclass for the given parent class. Options come from
    /// `ContentStore.classDefinition(id: parentClassID)?.subclasses`. Stored
    /// under the convention key `<parentClassID>_subclass` (see
    /// `ClassDefinition.subclassSelectionID(forClassID:)`).
    case subclasses(parentClassID: String)
    /// Distribute N points across ability scores (the 5e ASI mechanic).
    /// `FeatureSelection.count` carries the total point budget (typically 2).
    /// `perAbilityMax` caps how many points can land on a single ability
    /// (typically 2 so the player can't dump 2 into one and still have an
    /// over-cap pick). Each pick is recorded as an `Ability.rawValue` in
    /// `featureSelections`; the picker mutates `character.abilityScores`
    /// directly on each tap.
    case abilityScoreIncrease(perAbilityMax: Int)
    /// Pick skill IDs from the full skill list. `proficientOnly: true`
    /// restricts to skills the character already has proficiency in (used by
    /// Expertise and similar features).
    case skills(proficientOnly: Bool)
    /// Pick from a SPECIFIC list of skills, GRANTING proficiency in the picks
    /// (a class's level-1 "choose N skills" grant). Distinct from `.skills`,
    /// which picks from skills already proficient (Expertise).
    case skillsFrom(options: [Skill])

    private enum CodingKeys: String, CodingKey {
        case type, proficientOnly, options, parentClassID, perAbilityMax, skills
    }

    private enum Kind: String, Codable {
        case weapons, fixedOptions, subclasses, abilityScoreIncrease, skills, skillsFrom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .weapons:
            let proficient = try c.decodeIfPresent(Bool.self, forKey: .proficientOnly) ?? false
            self = .weapons(proficientOnly: proficient)
        case .fixedOptions:
            let options = try c.decode([SelectionOption].self, forKey: .options)
            self = .fixedOptions(options: options)
        case .subclasses:
            let parent = try c.decode(String.self, forKey: .parentClassID)
            self = .subclasses(parentClassID: parent)
        case .abilityScoreIncrease:
            let max = try c.decodeIfPresent(Int.self, forKey: .perAbilityMax) ?? 2
            self = .abilityScoreIncrease(perAbilityMax: max)
        case .skills:
            let proficient = try c.decodeIfPresent(Bool.self, forKey: .proficientOnly) ?? false
            self = .skills(proficientOnly: proficient)
        case .skillsFrom:
            let options = try c.decode([Skill].self, forKey: .skills)
            self = .skillsFrom(options: options)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .weapons(let proficient):
            try c.encode(Kind.weapons, forKey: .type)
            try c.encode(proficient, forKey: .proficientOnly)
        case .fixedOptions(let options):
            try c.encode(Kind.fixedOptions, forKey: .type)
            try c.encode(options, forKey: .options)
        case .subclasses(let parent):
            try c.encode(Kind.subclasses, forKey: .type)
            try c.encode(parent, forKey: .parentClassID)
        case .abilityScoreIncrease(let max):
            try c.encode(Kind.abilityScoreIncrease, forKey: .type)
            try c.encode(max, forKey: .perAbilityMax)
        case .skills(let proficient):
            try c.encode(Kind.skills, forKey: .type)
            try c.encode(proficient, forKey: .proficientOnly)
        case .skillsFrom(let options):
            try c.encode(Kind.skillsFrom, forKey: .type)
            try c.encode(options, forKey: .skills)
        }
    }
}

/// One named pick inside a `.fixedOptions` selection. The option `id` is what
/// the calculator / interpreter check against — by convention a snake_case
/// token like `defense` or `great_weapon_fighting`.
struct SelectionOption: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
    /// Spells this option confers when chosen (Drow → Dancing Lights at L1,
    /// Faerie Fire at L3, …). Always-prepared; see `SpellGrant`. Empty for
    /// options with no spell payload (Fighting Styles, subraces, etc.).
    let grantsSpells: [SpellGrant]
    /// Damage type this option imparts to a sibling trait's roll (Draconic
    /// Ancestry → Breath Weapon / Damage Resistance type). Nil when the option
    /// carries no damage-type payload.
    let damageType: DamageType?

    init(
        id: String,
        name: String,
        description: String,
        grantsSpells: [SpellGrant] = [],
        damageType: DamageType? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.grantsSpells = grantsSpells
        self.damageType = damageType
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, grantsSpells, damageType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        grantsSpells = try c.decodeIfPresent([SpellGrant].self, forKey: .grantsSpells) ?? []
        damageType = try c.decodeIfPresent(DamageType.self, forKey: .damageType)
    }
}
