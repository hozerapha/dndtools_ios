import Foundation

/// How much a resource regains when its `RefreshTrigger` fires.
///
/// JSON shapes:
/// ```
/// "all"
/// { "fixed": 1 }
/// { "byClassLevel": { "1": 1, "5": 2 } }
/// { "roll": "1d6+1" }
/// ```
///
/// `.all` fills to max — the most common case for long rest.
/// `.roll` defers to a `RollPrompt` so the player picks how to roll
/// (manual / tray / hidden) per the global resolution mode.
enum RefreshAmount: Codable, Equatable {
    case all
    case fixed(Int)
    case byClassLevel([Int: Int])
    case roll(formula: String)

    private enum ObjectKey: String, CodingKey {
        case fixed, byClassLevel, roll
    }

    init(from decoder: Decoder) throws {
        // Bare string "all"
        if let single = try? decoder.singleValueContainer(),
           let s = try? single.decode(String.self), s == "all" {
            self = .all
            return
        }
        let c = try decoder.container(keyedBy: ObjectKey.self)
        if let n = try c.decodeIfPresent(Int.self, forKey: .fixed) {
            self = .fixed(n)
            return
        }
        if let table = try c.decodeIfPresent([String: Int].self, forKey: .byClassLevel) {
            let parsed = Dictionary(uniqueKeysWithValues: table.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
            self = .byClassLevel(parsed)
            return
        }
        if let formula = try c.decodeIfPresent(String.self, forKey: .roll) {
            self = .roll(formula: formula)
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "RefreshAmount expects \"all\", or a single key of fixed / byClassLevel / roll"
        ))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .all:
            var single = encoder.singleValueContainer()
            try single.encode("all")
        case .fixed(let n):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode(n, forKey: .fixed)
        case .byClassLevel(let table):
            var c = encoder.container(keyedBy: ObjectKey.self)
            let stringKeyed = Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) })
            try c.encode(stringKeyed, forKey: .byClassLevel)
        case .roll(let formula):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode(formula, forKey: .roll)
        }
    }
}
