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
        self.manifestVersion = manifestVersion
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, level, speciesID, backgroundID, classEntries
        case abilityScores, maxHP, currentHP, tempHP
        case proficiencies, inventory, currency, notes, manifestVersion
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
        try container.encode(manifestVersion, forKey: .manifestVersion)

        let profDict = Dictionary(uniqueKeysWithValues: proficiencies.map { key, value in
            (key.encodeToString(), value)
        })
        try container.encode(profDict, forKey: .proficiencies)
    }
}
