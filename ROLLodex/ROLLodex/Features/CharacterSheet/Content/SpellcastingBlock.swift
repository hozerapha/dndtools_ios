import Foundation

/// Spellcasting metadata attached to a class. Drives slot synthesis, the
/// per-class spell list filter on the picker, and how the prepared / known
/// list is computed.
struct SpellcastingBlock: Codable, Equatable {
    /// The ability whose modifier feeds spell save DC and spell attacks.
    let ability: Ability
    /// Which list-management rule this class uses (wizard prep, sorcerer
    /// known list, warlock pact magic, etc.).
    let preparedRule: PreparedRule
    /// Cantrips known at the character's class level (sparse table).
    let cantripsKnown: LevelScaledValue
    /// For "known list" classes (sorcerer, bard, ranger). Nil for prepared
    /// classes (wizard, cleric, druid, paladin).
    let spellsKnown: LevelScaledValue?
    /// Slot table — full-caster or pact-magic shape.
    let slotTable: SlotTable
    let ritualCasting: Bool
    let spellcastingFocus: Bool
}

/// Different classes manage their daily spell list differently.
enum PreparedRule: String, Codable {
    /// Bard, sorcerer, ranger — fixed list of "known" spells; no daily prep.
    case knownList
    /// Wizard — prepare each long rest from spells in your spellbook.
    case preparedFromBook
    /// Cleric, druid, paladin — prepare each long rest from the entire class spell list.
    case preparedFromAll
    /// Warlock — known list with pact-magic slot table.
    case pactMagic
}

/// Slot count by class level. Two shapes:
/// - Full caster: nested `[classLevel: [slotLevel: count]]` (the standard 5e table)
/// - Pact magic (warlock): a single slot level per class level + a count
enum SlotTable: Codable, Equatable {
    case fullCaster([Int: [Int: Int]])
    case pactMagic([Int: PactSlots])

    private enum CodingKeys: String, CodingKey { case kind, table }
    private enum Kind: String, Codable { case fullCaster, pactMagic }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .fullCaster:
            let raw = try c.decode([String: [String: Int]].self, forKey: .table)
            self = .fullCaster(Self.parseNestedTable(raw))
        case .pactMagic:
            let raw = try c.decode([String: PactSlots].self, forKey: .table)
            self = .pactMagic(Self.parseLevelKeys(raw))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fullCaster(let table):
            try c.encode(Kind.fullCaster, forKey: .kind)
            try c.encode(Self.encodeNestedTable(table), forKey: .table)
        case .pactMagic(let table):
            try c.encode(Kind.pactMagic, forKey: .kind)
            try c.encode(Self.encodeLevelKeys(table), forKey: .table)
        }
    }

    /// Slot counts for a character at the given class level. Returns a
    /// `[slotLevel: count]` dictionary. Pact magic flattens its single-level
    /// representation into the same shape.
    func slots(atClassLevel level: Int) -> [Int: Int] {
        switch self {
        case .fullCaster(let table):
            // Take the entry at the highest class level ≤ `level`.
            guard let key = table.keys.filter({ $0 <= level }).max() else { return [:] }
            return table[key] ?? [:]
        case .pactMagic(let table):
            guard let key = table.keys.filter({ $0 <= level }).max(),
                  let entry = table[key] else { return [:] }
            return [entry.slotLevel: entry.count]
        }
    }

    var isPactMagic: Bool {
        if case .pactMagic = self { return true }
        return false
    }

    // MARK: - JSON key helpers (object keys must be strings)

    private static func parseNestedTable(_ raw: [String: [String: Int]]) -> [Int: [Int: Int]] {
        Dictionary(uniqueKeysWithValues: raw.compactMap { outerKey, inner in
            guard let outer = Int(outerKey) else { return nil }
            let parsedInner = Dictionary(uniqueKeysWithValues: inner.compactMap { k, v in
                Int(k).map { ($0, v) }
            })
            return (outer, parsedInner)
        })
    }

    private static func encodeNestedTable(_ table: [Int: [Int: Int]]) -> [String: [String: Int]] {
        Dictionary(uniqueKeysWithValues: table.map { outer, inner in
            (String(outer), Dictionary(uniqueKeysWithValues: inner.map { (String($0.key), $0.value) }))
        })
    }

    private static func parseLevelKeys(_ raw: [String: PactSlots]) -> [Int: PactSlots] {
        Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    private static func encodeLevelKeys(_ table: [Int: PactSlots]) -> [String: PactSlots] {
        Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) })
    }
}

struct PactSlots: Codable, Equatable {
    let slotLevel: Int
    let count: Int
}
