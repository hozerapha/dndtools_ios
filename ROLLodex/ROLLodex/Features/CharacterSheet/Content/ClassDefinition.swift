import Foundation

struct ClassDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let hitDie: DieKind
    let primaryAbility: Ability
    let savingThrows: [Ability]
    let armorProficiencies: [ArmorCategory]
    let weaponProficiencies: [WeaponCategory]
    let levelFeatures: [Int: [FeatureDefinition]]
    let masteryCount: Int?
    let masteryRestrictions: [String]
    /// Spell-slot table, casting ability, prep rules. Absent on non-casting
    /// classes (Fighter, Barbarian, Rogue without a subclass). When present,
    /// `ResourceCalculator` synthesizes one slot resource per slot level.
    let spellcasting: SpellcastingBlock?

    private enum CodingKeys: String, CodingKey {
        case id, name, hitDie, primaryAbility, savingThrows
        case armorProficiencies, weaponProficiencies, levelFeatures
        case masteryCount, masteryRestrictions, spellcasting
    }

    init(
        id: String,
        name: String,
        hitDie: DieKind,
        primaryAbility: Ability,
        savingThrows: [Ability],
        armorProficiencies: [ArmorCategory],
        weaponProficiencies: [WeaponCategory],
        levelFeatures: [Int: [FeatureDefinition]],
        masteryCount: Int? = nil,
        masteryRestrictions: [String] = [],
        spellcasting: SpellcastingBlock? = nil
    ) {
        self.id = id
        self.name = name
        self.hitDie = hitDie
        self.primaryAbility = primaryAbility
        self.savingThrows = savingThrows
        self.armorProficiencies = armorProficiencies
        self.weaponProficiencies = weaponProficiencies
        self.levelFeatures = levelFeatures
        self.masteryCount = masteryCount
        self.masteryRestrictions = masteryRestrictions
        self.spellcasting = spellcasting
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
        // levelFeatures has Int keys; classes.json encodes them as strings, so
        // the synthesized JSONDecoder handles the conversion automatically for
        // [Int: T] dictionaries via `.useDefaultKeys`. The bundled loader
        // relies on that behavior — keep it intact.
        levelFeatures       = try c.decode([Int: [FeatureDefinition]].self, forKey: .levelFeatures)
        masteryCount        = try c.decodeIfPresent(Int.self, forKey: .masteryCount)
        masteryRestrictions = try c.decodeIfPresent([String].self, forKey: .masteryRestrictions) ?? []
        spellcasting        = try c.decodeIfPresent(SpellcastingBlock.self, forKey: .spellcasting)
    }
}
