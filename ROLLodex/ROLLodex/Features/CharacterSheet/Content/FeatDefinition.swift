import Foundation

/// A feat the character can select at a specific moment: Origin at L1
/// (background), General at ASI moments (L4/8/12/16), Fighting Style when a
/// class's Fighting Style feature fires, Epic Boon at L19. Bundled read-only
/// from `Resources/Content/feats.json`; picks land under
/// `Character.featureSelections["feats"]`.
///
/// The schema is deliberately data-first: every mechanical hook that varies
/// across the SRD's 17 feats is a stored field. Fields default to a zero-
/// value / empty state so a feat with no relevant hook decodes cleanly. The
/// prose in `description` is the SRD source of truth — any hook we haven't
/// wired mechanically yet still reads correctly from the description card,
/// on the honor system.
struct FeatDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: FeatCategory
    /// Human-readable prerequisite summary rendered next to the name.
    let prerequisiteText: String
    /// Structured prerequisites for eligibility gating in the picker.
    let prerequisites: FeatPrerequisites
    /// Full SRD 5.2.1 description text; players read this to understand the
    /// feat's on-the-honor-system parts.
    let description: String
    /// Whether the SRD "Repeatable" clause applies — the player can take it
    /// multiple times (Skilled, ASI, Magic Initiate).
    let repeatable: Bool

    // MARK: - Mechanical hooks (all optional / zero-valued when unused)

    /// Ability bump the feat grants. Nil = the feat carries no ability
    /// change (Skilled, Fighting Style feats).
    let abilityScoreBonus: FeatAbilityBonus?
    /// Add the character's Proficiency Bonus to Initiative rolls (Alert).
    let initiativeProficiencyBonus: Bool
    /// Extra "pick a skill OR tool" slots the feat grants (Skilled: 3). The
    /// picker offers skills and tools alike; the pick is recorded under
    /// `featureSelections["feat_<id>_skills"]` and folded into the character's
    /// proficiencies at resolve time.
    let skillOrToolProficiencyCount: Int
    /// Truesight range in feet (Boon of Truesight: 60). Nil = no truesight.
    let truesightRange: Int?
    /// +N to AC while wearing any armor (Defense: +1). Zero when the feat
    /// doesn't grant an AC bump.
    let armorClassBonusInArmor: Int
    /// Magic Initiate's spell payload: which class list, how many cantrips,
    /// how many leveled spells. Nil for feats that don't grant spells.
    let magicInitiate: MagicInitiateGrant?
    /// Override the max ability score cap for scores this feat bumped
    /// (Epic Boons raise the ceiling to 30). Nil = default 20 cap applies.
    let abilityScoreCapOverride: Int?
    /// Bonus to ranged weapon attack rolls (Archery: +2). Zero = no bonus.
    let rangedAttackBonus: Int
    /// Reroll damage dice showing 1 or 2 on a two-handed melee weapon roll
    /// (Great Weapon Fighting). The interpreter reads this the same way it
    /// reads the Fighter's inline GWF selection.
    let grantsGWFDamageReroll: Bool
    /// Restore the ability modifier to a Light-weapon extra attack's damage
    /// (Two-Weapon Fighting).
    let grantsTWFOffHandModifier: Bool

    init(
        id: String,
        name: String,
        category: FeatCategory,
        prerequisiteText: String = "",
        prerequisites: FeatPrerequisites = FeatPrerequisites(),
        description: String,
        repeatable: Bool = false,
        abilityScoreBonus: FeatAbilityBonus? = nil,
        initiativeProficiencyBonus: Bool = false,
        skillOrToolProficiencyCount: Int = 0,
        truesightRange: Int? = nil,
        armorClassBonusInArmor: Int = 0,
        magicInitiate: MagicInitiateGrant? = nil,
        abilityScoreCapOverride: Int? = nil,
        rangedAttackBonus: Int = 0,
        grantsGWFDamageReroll: Bool = false,
        grantsTWFOffHandModifier: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.prerequisiteText = prerequisiteText
        self.prerequisites = prerequisites
        self.description = description
        self.repeatable = repeatable
        self.abilityScoreBonus = abilityScoreBonus
        self.initiativeProficiencyBonus = initiativeProficiencyBonus
        self.skillOrToolProficiencyCount = skillOrToolProficiencyCount
        self.truesightRange = truesightRange
        self.armorClassBonusInArmor = armorClassBonusInArmor
        self.magicInitiate = magicInitiate
        self.abilityScoreCapOverride = abilityScoreCapOverride
        self.rangedAttackBonus = rangedAttackBonus
        self.grantsGWFDamageReroll = grantsGWFDamageReroll
        self.grantsTWFOffHandModifier = grantsTWFOffHandModifier
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, prerequisiteText, prerequisites, description, repeatable
        case abilityScoreBonus, initiativeProficiencyBonus, skillOrToolProficiencyCount
        case truesightRange, armorClassBonusInArmor, magicInitiate
        case abilityScoreCapOverride, rangedAttackBonus, grantsGWFDamageReroll
        case grantsTWFOffHandModifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                          = try c.decode(String.self, forKey: .id)
        name                        = try c.decode(String.self, forKey: .name)
        category                    = try c.decode(FeatCategory.self, forKey: .category)
        prerequisiteText            = try c.decodeIfPresent(String.self, forKey: .prerequisiteText) ?? ""
        prerequisites               = try c.decodeIfPresent(FeatPrerequisites.self, forKey: .prerequisites) ?? FeatPrerequisites()
        description                 = try c.decode(String.self, forKey: .description)
        repeatable                  = try c.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        abilityScoreBonus           = try c.decodeIfPresent(FeatAbilityBonus.self, forKey: .abilityScoreBonus)
        initiativeProficiencyBonus  = try c.decodeIfPresent(Bool.self, forKey: .initiativeProficiencyBonus) ?? false
        skillOrToolProficiencyCount = try c.decodeIfPresent(Int.self, forKey: .skillOrToolProficiencyCount) ?? 0
        truesightRange              = try c.decodeIfPresent(Int.self, forKey: .truesightRange)
        armorClassBonusInArmor      = try c.decodeIfPresent(Int.self, forKey: .armorClassBonusInArmor) ?? 0
        magicInitiate               = try c.decodeIfPresent(MagicInitiateGrant.self, forKey: .magicInitiate)
        abilityScoreCapOverride     = try c.decodeIfPresent(Int.self, forKey: .abilityScoreCapOverride)
        rangedAttackBonus           = try c.decodeIfPresent(Int.self, forKey: .rangedAttackBonus) ?? 0
        grantsGWFDamageReroll       = try c.decodeIfPresent(Bool.self, forKey: .grantsGWFDamageReroll) ?? false
        grantsTWFOffHandModifier    = try c.decodeIfPresent(Bool.self, forKey: .grantsTWFOffHandModifier) ?? false
    }
}

/// SRD 5.2.1 groups feats into four categories. Origin fires at Background
/// pick (L1). General is the "instead of ASI" branch at L4/8/12/16.
/// Fighting Style is consumed by class Fighting Style features (Archery et
/// al.). Epic Boon lands at L19.
enum FeatCategory: String, Codable, CaseIterable {
    case origin
    case general
    case fightingStyle = "fighting_style"
    case epicBoon = "epic_boon"

    var displayName: String {
        switch self {
        case .origin:        return "Origin"
        case .general:       return "General"
        case .fightingStyle: return "Fighting Style"
        case .epicBoon:      return "Epic Boon"
        }
    }
}

/// Structured prerequisites for feat eligibility. All fields default to a
/// no-op so a feat with no prereqs decodes cleanly. The picker greys out
/// feats whose prereqs fail; the reason text comes from `firstUnmetReason`.
struct FeatPrerequisites: Codable, Equatable {
    /// Minimum character level (General: 4, Epic Boon: 19). Nil / zero = any.
    let minLevel: Int?
    /// Any-of minimum ability score requirements (Grappler: STR OR DEX 13+).
    /// Keys are Ability rawValues; value is the required minimum. Empty =
    /// no ability prereq. When multiple entries are present the character
    /// must meet AT LEAST ONE.
    let minAbilityScoresAnyOf: [String: Int]
    /// The character must have any class-level Spellcasting feature (Boon
    /// of Spell Recall).
    let requiresSpellcastingFeature: Bool
    /// The character must have picked a class Fighting Style (Fighting
    /// Style feats).
    let requiresFightingStyleFeature: Bool

    init(
        minLevel: Int? = nil,
        minAbilityScoresAnyOf: [String: Int] = [:],
        requiresSpellcastingFeature: Bool = false,
        requiresFightingStyleFeature: Bool = false
    ) {
        self.minLevel = minLevel
        self.minAbilityScoresAnyOf = minAbilityScoresAnyOf
        self.requiresSpellcastingFeature = requiresSpellcastingFeature
        self.requiresFightingStyleFeature = requiresFightingStyleFeature
    }

    private enum CodingKeys: String, CodingKey {
        case minLevel, minAbilityScoresAnyOf
        case requiresSpellcastingFeature, requiresFightingStyleFeature
    }

    /// Custom decoder so hand-authored JSON can omit fields it isn't using.
    /// The synthesized decoder would reject `{"minLevel": 4}` — every
    /// non-optional field would be required in the payload, which is hostile
    /// to sparse per-feat prereq blocks.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minLevel                     = try c.decodeIfPresent(Int.self, forKey: .minLevel)
        minAbilityScoresAnyOf        = try c.decodeIfPresent([String: Int].self, forKey: .minAbilityScoresAnyOf) ?? [:]
        requiresSpellcastingFeature  = try c.decodeIfPresent(Bool.self, forKey: .requiresSpellcastingFeature) ?? false
        requiresFightingStyleFeature = try c.decodeIfPresent(Bool.self, forKey: .requiresFightingStyleFeature) ?? false
    }
}

/// Ability bump payload. `.oneAbility` = +N to one chosen ability (Grappler
/// +1 to STR or DEX; Epic Boons +1 to any). `.pointBuy` = distribute `amount`
/// points across ANY of the listed abilities, max 1 per ability (ASI's +2 to
/// one OR +1 to two shape).
struct FeatAbilityBonus: Codable, Equatable {
    let amount: Int
    let abilities: [Ability]
    let distribute: FeatAbilityDistribution
}

enum FeatAbilityDistribution: String, Codable {
    case oneAbility
    case pointBuy
}

/// Magic Initiate's spell payload — which class list to draw from, how many
/// cantrips, how many leveled spells (always exactly 1 for the SRD feat but
/// kept as a field for potential homebrew). The player picks the specific
/// spells at feat-pick time; picks land under
/// `featureSelections["feat_<id>_spells"]`.
struct MagicInitiateGrant: Codable, Equatable {
    /// Which class lists the player may pick from (SRD: Cleric / Druid /
    /// Wizard). One list per feat instance.
    let classListOptions: [String]
    let cantripCount: Int
    let leveledSpellCount: Int
    let leveledSpellLevel: Int
    /// Which ability mods the SRD lets the character use as the spellcasting
    /// ability for this feat's spells. SRD: INT / WIS / CHA. Player chooses.
    let spellcastingAbilityOptions: [Ability]
    /// Whether the leveled spell gets a once-per-Long-Rest free cast (the
    /// pool is synthesized at feat-pick time, mirroring species free casts).
    let leveledSpellHasFreeCast: Bool
}
