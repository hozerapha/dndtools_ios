import Foundation

/// A value that may be a flat constant or scale by class / character level via
/// a sparse table. Used for resource maxes (Second Wind uses), spell-slot
/// counts, cantrip damage dice — anywhere D&D scales a number with level.
///
/// Sparse-table semantics: `value(at: L)` returns the entry at the highest key
/// `≤ L`, falling back to 0 if no key qualifies. Same shape as the existing
/// `attunementSlotsByLevel` field on classes / features.
///
/// JSON shapes (the decoder accepts any of):
/// ```
/// 5                                                  // → flat(5)
/// { "byClassLevel":     { "1": 2, "4": 3, "10": 4 } }
/// { "byCharacterLevel": { "1": 1, "5": 2 } }
/// ```
enum LevelScaledValue: Codable, Equatable {
    case flat(Int)
    case byClassLevel([Int: Int])
    case byCharacterLevel([Int: Int])

    /// Resolve the value given the class level (the level of the class entry
    /// that owns this resource) and the overall character level.
    func value(classLevel: Int, characterLevel: Int) -> Int {
        switch self {
        case .flat(let n):
            return n
        case .byClassLevel(let table):
            return Self.lookup(table, level: classLevel)
        case .byCharacterLevel(let table):
            return Self.lookup(table, level: characterLevel)
        }
    }

    private static func lookup(_ table: [Int: Int], level: Int) -> Int {
        guard let bestKey = table.keys.filter({ $0 <= level }).max() else { return 0 }
        return table[bestKey] ?? 0
    }

    // MARK: - Codable

    private enum ObjectKey: String, CodingKey {
        case byClassLevel, byCharacterLevel
    }

    init(from decoder: Decoder) throws {
        // Bare integer literal → .flat
        if let single = try? decoder.singleValueContainer(), let n = try? single.decode(Int.self) {
            self = .flat(n)
            return
        }
        let c = try decoder.container(keyedBy: ObjectKey.self)
        if let table = try c.decodeIfPresent([String: Int].self, forKey: .byClassLevel) {
            self = .byClassLevel(Self.parseLevelTable(table))
            return
        }
        if let table = try c.decodeIfPresent([String: Int].self, forKey: .byCharacterLevel) {
            self = .byCharacterLevel(Self.parseLevelTable(table))
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "LevelScaledValue requires a flat int or a single key of byClassLevel / byCharacterLevel"
        ))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .flat(let n):
            var single = encoder.singleValueContainer()
            try single.encode(n)
        case .byClassLevel(let table):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode(Self.encodeLevelTable(table), forKey: .byClassLevel)
        case .byCharacterLevel(let table):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode(Self.encodeLevelTable(table), forKey: .byCharacterLevel)
        }
    }

    /// JSON object keys must be strings; convert "1" → 1 etc.
    private static func parseLevelTable(_ raw: [String: Int]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    private static func encodeLevelTable(_ table: [Int: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) })
    }
}
