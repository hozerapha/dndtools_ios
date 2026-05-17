import Foundation

struct ClassDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let hitDie: DieKind
    let primaryAbility: Ability
    let savingThrows: [Ability]
    let armorProficiencies: [ArmorCategory]
    let weaponProficiencies: [WeaponCategory]
    let toolProficiencies: [String]
    let levelFeatures: [Int: [FeatureDefinition]]
    let masteryCount: Int?
    let masteryRestrictions: [String]
    /// Spell-slot table, casting ability, prep rules. Absent on non-casting
    /// classes (Fighter, Barbarian, Rogue without a subclass). When present,
    /// `ResourceCalculator` synthesizes one slot resource per slot level.
    let spellcasting: SpellcastingBlock?
    /// Subclasses available to this class (Champion, Battle Master, etc.).
    /// Empty when subclasses haven't been authored yet — selection prompts
    /// at the subclass level will just show no options until content lands.
    let subclasses: [SubclassDefinition]
    /// Class level at which the subclass is chosen (Fighter = 3, Wizard = 2,
    /// Cleric = 1). Nil for classes that don't have subclasses authored.
    let subclassLevel: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, hitDie, primaryAbility, savingThrows
        case armorProficiencies, weaponProficiencies, toolProficiencies, levelFeatures
        case masteryCount, masteryRestrictions, spellcasting
        case subclasses, subclassLevel
    }

    init(
        id: String,
        name: String,
        hitDie: DieKind,
        primaryAbility: Ability,
        savingThrows: [Ability],
        armorProficiencies: [ArmorCategory],
        weaponProficiencies: [WeaponCategory],
        toolProficiencies: [String] = [],
        levelFeatures: [Int: [FeatureDefinition]],
        masteryCount: Int? = nil,
        masteryRestrictions: [String] = [],
        spellcasting: SpellcastingBlock? = nil,
        subclasses: [SubclassDefinition] = [],
        subclassLevel: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.hitDie = hitDie
        self.primaryAbility = primaryAbility
        self.savingThrows = savingThrows
        self.armorProficiencies = armorProficiencies
        self.weaponProficiencies = weaponProficiencies
        self.toolProficiencies = toolProficiencies
        self.levelFeatures = levelFeatures
        self.masteryCount = masteryCount
        self.masteryRestrictions = masteryRestrictions
        self.spellcasting = spellcasting
        self.subclasses = subclasses
        self.subclassLevel = subclassLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(String.self, forKey: .id)
        name                = try c.decode(String.self, forKey: .name)
        hitDie              = try c.decode(DieKind.self, forKey: .hitDie)
        primaryAbility      = try c.decode(Ability.self, forKey: .primaryAbility)
        savingThrows        = try c.decode([Ability].self, forKey: .savingThrows)
        armorProficiencies  = try c.decode([ArmorCategory].self, forKey: .armorProficiencies)
        weaponProficiencies = try c.decode([WeaponCategory].self, forKey: .weaponProficiencies)
        toolProficiencies   = try c.decodeIfPresent([String].self, forKey: .toolProficiencies) ?? []
        // levelFeatures has Int keys; classes.json encodes them as strings, so
        // the synthesized JSONDecoder handles the conversion automatically for
        // [Int: T] dictionaries via `.useDefaultKeys`. The bundled loader
        // relies on that behavior — keep it intact.
        levelFeatures       = try c.decode([Int: [FeatureDefinition]].self, forKey: .levelFeatures)
        masteryCount        = try c.decodeIfPresent(Int.self, forKey: .masteryCount)
        masteryRestrictions = try c.decodeIfPresent([String].self, forKey: .masteryRestrictions) ?? []
        spellcasting        = try c.decodeIfPresent(SpellcastingBlock.self, forKey: .spellcasting)
        subclasses          = try c.decodeIfPresent([SubclassDefinition].self, forKey: .subclasses) ?? []
        subclassLevel       = try c.decodeIfPresent(Int.self, forKey: .subclassLevel)
    }

    /// Convention-key for storing a character's chosen subclass under
    /// `Character.featureSelections`. Centralized so the picker, the
    /// aggregator, and content authors agree on the spelling.
    static func subclassSelectionID(forClassID classID: String) -> String {
        "\(classID)_subclass"
    }

    /// All features a character has access to at the given class level:
    /// base-class features at or below the level, plus features from the
    /// chosen subclass (if any) at or below the level. Centralizes the walk
    /// so the action grid, Features tab, resource calculator, etc. all see
    /// the same picture.
    func resolvedFeatures(
        throughClassLevel level: Int,
        subclassID: String?
    ) -> [ResolvedFeature] {
        var result: [ResolvedFeature] = []
        let cap = max(level, 1)
        for lv in 1...cap {
            for feature in levelFeatures[lv] ?? [] {
                result.append(ResolvedFeature(
                    feature: feature,
                    grantedAtLevel: lv,
                    subclassName: nil
                ))
            }
        }
        if let subclassID,
           let subclass = subclasses.first(where: { $0.id == subclassID }) {
            for lv in 1...cap {
                for feature in subclass.levelFeatures[lv] ?? [] {
                    result.append(ResolvedFeature(
                        feature: feature,
                        grantedAtLevel: lv,
                        subclassName: subclass.name
                    ))
                }
            }
        }
        return result
    }
}
