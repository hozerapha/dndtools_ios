import Foundation

struct ClassEntry: Codable, Equatable, Hashable {
    let classID: String
    let level: Int
}

struct Character: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var level: Int
    var speciesID: String
    var backgroundID: String
    var classEntries: [ClassEntry]
    var abilityScores: [Ability: Int]
    var maxHP: Int
    var currentHP: Int
    var tempHP: Int
    var proficiencies: [ProficiencyKey: ProficiencyLevel]
    var inventory: [InventoryItem]
    var currency: Currency
    var notes: String
    /// Optional per-character override for the attunement slot count. When
    /// nil the limit comes from the class table (or the standard 5e cap of 3).
    /// Lets a homebrew/magic-item context bump the cap without touching class data.
    var attunementSlotsOverride: Int?
    /// Per-resource current values keyed by `ResourceDefinition.id`. Maxes
    /// and refresh rules live in content; this map only tracks how much the
    /// character has spent. Missing keys default to "full" via the calculator.
    var resources: [String: ResourceState]
    /// Spell list state — prepared / known / spellbook IDs. See `CharacterSpells`.
    var spells: CharacterSpells
    /// Player picks for each feature that has a `FeatureSelection`. The key
    /// is `FeatureSelection.id` (often the feature's id); the value is the
    /// list of chosen option IDs. One mechanism backs Weapon Mastery,
    /// Eldritch Invocations, Metamagic, etc. — the picker UI keys off the
    /// owning feature's selection block.
    var featureSelections: [String: [String]]
    /// Currently active conditions (poisoned, restrained, etc.). Order is
    /// preserved so the UI can render them in the order the player added them.
    var conditions: [CharacterCondition]
    /// Spell ID of the active concentration spell, if any. Only one at a time
    /// (5e rule); setters should clear any prior value before assigning. Nil
    /// when the character isn't concentrating.
    var concentratingSpellID: String?
    var manifestVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        level: Int,
        speciesID: String,
        backgroundID: String,
        classEntries: [ClassEntry],
        abilityScores: [Ability: Int],
        maxHP: Int,
        currentHP: Int = 0,
        tempHP: Int = 0,
        proficiencies: [ProficiencyKey: ProficiencyLevel] = [:],
        inventory: [InventoryItem] = [],
        currency: Currency = Currency(),
        notes: String = "",
        attunementSlotsOverride: Int? = nil,
        resources: [String: ResourceState] = [:],
        spells: CharacterSpells = CharacterSpells(),
        featureSelections: [String: [String]] = [:],
        conditions: [CharacterCondition] = [],
        concentratingSpellID: String? = nil,
        manifestVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.speciesID = speciesID
        self.backgroundID = backgroundID
        self.classEntries = classEntries
        self.abilityScores = abilityScores
        self.maxHP = maxHP
        self.currentHP = currentHP == 0 ? maxHP : currentHP
        self.tempHP = tempHP
        self.proficiencies = proficiencies
        self.inventory = inventory
        self.currency = currency
        self.notes = notes
        self.attunementSlotsOverride = attunementSlotsOverride
        self.resources = resources
        self.spells = spells
        self.featureSelections = featureSelections
        self.conditions = conditions
        self.concentratingSpellID = concentratingSpellID
        self.manifestVersion = manifestVersion
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, level, speciesID, backgroundID, classEntries
        case abilityScores, maxHP, currentHP, tempHP
        case proficiencies, inventory, currency, notes
        case attunementSlotsOverride, resources, spells
        case featureSelections, conditions, concentratingSpellID, manifestVersion
        /// Legacy key from when masteries lived on the character directly.
        /// Migrated into `featureSelections["weapon_mastery"]` on decode.
        case chosenWeaponMasteries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        level = try container.decode(Int.self, forKey: .level)
        speciesID = try container.decode(String.self, forKey: .speciesID)
        backgroundID = try container.decode(String.self, forKey: .backgroundID)
        classEntries = try container.decode([ClassEntry].self, forKey: .classEntries)
        abilityScores = try container.decode([Ability: Int].self, forKey: .abilityScores)
        maxHP = try container.decode(Int.self, forKey: .maxHP)
        currentHP = try container.decodeIfPresent(Int.self, forKey: .currentHP) ?? maxHP
        tempHP = try container.decodeIfPresent(Int.self, forKey: .tempHP) ?? 0
        inventory = try container.decode([InventoryItem].self, forKey: .inventory)
        currency = try container.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        attunementSlotsOverride = try container.decodeIfPresent(Int.self, forKey: .attunementSlotsOverride)
        resources = try container.decodeIfPresent([String: ResourceState].self, forKey: .resources) ?? [:]
        spells = try container.decodeIfPresent(CharacterSpells.self, forKey: .spells) ?? CharacterSpells()
        // Migrate the legacy chosenWeaponMasteries field if present.
        var selections = try container.decodeIfPresent([String: [String]].self, forKey: .featureSelections) ?? [:]
        if let legacyMasteries = try container.decodeIfPresent([String].self, forKey: .chosenWeaponMasteries),
           !legacyMasteries.isEmpty,
           selections["weapon_mastery"] == nil {
            selections["weapon_mastery"] = legacyMasteries
        }
        featureSelections = selections
        conditions = try container.decodeIfPresent([CharacterCondition].self, forKey: .conditions) ?? []
        concentratingSpellID = try container.decodeIfPresent(String.self, forKey: .concentratingSpellID)
        manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1

        let profDict = try container.decodeIfPresent([String: ProficiencyLevel].self, forKey: .proficiencies) ?? [:]
        proficiencies = Dictionary(uniqueKeysWithValues: profDict.compactMap { key, value in
            guard let profKey = ProficiencyKey.decode(from: key) else { return nil }
            return (profKey, value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(level, forKey: .level)
        try container.encode(speciesID, forKey: .speciesID)
        try container.encode(backgroundID, forKey: .backgroundID)
        try container.encode(classEntries, forKey: .classEntries)
        try container.encode(abilityScores, forKey: .abilityScores)
        try container.encode(maxHP, forKey: .maxHP)
        try container.encode(currentHP, forKey: .currentHP)
        try container.encode(tempHP, forKey: .tempHP)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(currency, forKey: .currency)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(attunementSlotsOverride, forKey: .attunementSlotsOverride)
        try container.encode(resources, forKey: .resources)
        try container.encode(spells, forKey: .spells)
        try container.encode(featureSelections, forKey: .featureSelections)
        try container.encode(conditions, forKey: .conditions)
        try container.encodeIfPresent(concentratingSpellID, forKey: .concentratingSpellID)
        try container.encode(manifestVersion, forKey: .manifestVersion)

        let profDict = Dictionary(uniqueKeysWithValues: proficiencies.map { key, value in
            (key.encodeToString(), value)
        })
        try container.encode(profDict, forKey: .proficiencies)
    }

    // MARK: - Condition mutators

    /// Apply a condition. Re-adding the same condition replaces its source
    /// rather than stacking — duplicates would just clutter the row.
    mutating func applyCondition(id: String, source: String? = nil) {
        if let index = conditions.firstIndex(where: { $0.id == id }) {
            conditions[index].source = source
        } else {
            conditions.append(CharacterCondition(id: id, source: source))
        }
    }

    mutating func removeCondition(id: String) {
        conditions.removeAll { $0.id == id }
    }

    /// Set the active concentration spell. Replacing a prior one is the
    /// caller's responsibility to confirm with the user; this just commits.
    mutating func startConcentrating(on spellID: String) {
        concentratingSpellID = spellID
    }

    mutating func stopConcentrating() {
        concentratingSpellID = nil
    }

    // MARK: - ASI mutators

    /// SRD 2024 ceiling for ability scores. ASI cannot push a score past this
    /// (magic items can, but they don't route through this path).
    static let abilityScoreCeiling = 20

    /// Apply +1 to `ability` via an ASI selection, recording the pick under
    /// `selectionID`. Refuses to act when:
    /// - the total budget (`totalPoints`) is exhausted,
    /// - the per-ability sub-cap (`perAbilityMax`) is reached, or
    /// - the score is already at the SRD ceiling.
    /// No-ops are silent so the picker UI can call this unguarded.
    mutating func applyASIIncrement(
        ability: Ability,
        selectionID: String,
        totalPoints: Int,
        perAbilityMax: Int
    ) {
        let picks = featureSelections[selectionID] ?? []
        let picksForAbility = picks.filter { $0 == ability.rawValue }.count
        guard picks.count < totalPoints,
              picksForAbility < perAbilityMax,
              (abilityScores[ability] ?? 10) < Self.abilityScoreCeiling
        else { return }
        var updated = picks
        updated.append(ability.rawValue)
        featureSelections[selectionID] = updated
        abilityScores[ability] = (abilityScores[ability] ?? 10) + 1
    }

    /// Reverse one ASI pick for `ability`. No-op when the ability has no
    /// picks recorded under `selectionID`.
    mutating func applyASIDecrement(
        ability: Ability,
        selectionID: String
    ) {
        let picks = featureSelections[selectionID] ?? []
        guard picks.contains(ability.rawValue) else { return }
        var updated = picks
        if let i = updated.lastIndex(of: ability.rawValue) {
            updated.remove(at: i)
        }
        featureSelections[selectionID] = updated
        abilityScores[ability] = max(1, (abilityScores[ability] ?? 10) - 1)
    }

    /// Apply `amount` damage. Drains temp HP first (per 5e), then chips
    /// current HP. Returns a pending `ConcentrationCheck` when the character
    /// was concentrating and actually took damage to current HP (temp-only
    /// absorbs don't trigger the save). Caller is responsible for prompting
    /// the player to roll.
    mutating func applyDamage(_ amount: Int) -> ConcentrationCheck? {
        guard amount > 0 else { return nil }
        var remaining = amount
        if tempHP > 0 {
            let absorbed = min(tempHP, remaining)
            tempHP -= absorbed
            remaining -= absorbed
        }
        guard remaining > 0 else { return nil }
        currentHP = max(0, currentHP - remaining)
        guard let spellID = concentratingSpellID else { return nil }
        // DC is the larger of 10 or half the damage taken (after temp HP).
        let dc = max(10, remaining / 2)
        return ConcentrationCheck(spellID: spellID, dc: dc, damageTaken: remaining)
    }
}

/// Returned by `Character.applyDamage` when the hit interrupts concentration.
/// The view layer reads this to surface the save sheet — the model itself
/// doesn't know whether the player passes or fails.
struct ConcentrationCheck: Equatable, Identifiable {
    /// Spell currently held; if the player fails, this is what drops.
    let spellID: String
    let dc: Int
    let damageTaken: Int

    /// Combine spell + damage so a re-tap on the same hit doesn't dedupe with
    /// the prior one (player might take multiple hits before saving).
    var id: String { "\(spellID)_\(dc)_\(damageTaken)" }
}
