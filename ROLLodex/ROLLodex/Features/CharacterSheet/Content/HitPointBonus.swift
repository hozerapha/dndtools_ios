import Foundation

/// A Hit-Point bonus a feature confers: a one-time `flat` amount plus a
/// `perLevel` amount applied for every character level. Draconic Resilience is
/// `flat 3, perLevel 1`; Dwarven Toughness is `perLevel 1`. Both default to 0
/// so JSON can specify only the part it needs.
struct HitPointBonus: Codable, Equatable {
    let flat: Int
    let perLevel: Int

    init(flat: Int = 0, perLevel: Int = 0) {
        self.flat = flat
        self.perLevel = perLevel
    }

    private enum CodingKeys: String, CodingKey { case flat, perLevel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flat = try c.decodeIfPresent(Int.self, forKey: .flat) ?? 0
        perLevel = try c.decodeIfPresent(Int.self, forKey: .perLevel) ?? 0
    }

    /// Total bonus at a given character level.
    func total(atLevel level: Int) -> Int {
        flat + perLevel * level
    }
}
