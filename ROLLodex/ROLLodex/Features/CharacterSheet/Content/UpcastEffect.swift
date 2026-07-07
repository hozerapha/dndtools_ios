import Foundation

/// How a spell's effect scales when cast using a slot above its base level.
/// Applied by `SpellCastSheet` before it runs the spell's recipes.
///
/// Phase J MVP ships `extraDicePerLevel` because that's the shape Magic
/// Missile and Cure Wounds use. The other cases are stubs for the larger
/// spell library — leave them out of v1 if you don't have content using them.
enum UpcastEffect: Codable, Equatable {
    /// Add `dice` to the damage / heal recipe at `recipeIndex`, once per
    /// `levelsPerBonus` slot levels above the spell's base level (default 1 —
    /// the SRD "damage increases by 1dX for each spell slot level above N"
    /// shape). Setting `levelsPerBonus: 2` covers the "every two slot levels"
    /// pattern used by Flame Blade, Spiritual Weapon, and Melf's Minute
    /// Meteors. Application count is integer-divided, so extras only kick in
    /// on exact multiples of the interval.
    /// Magic Missile: `extraDicePerLevel(0, "1d4+1")` — at L2 the 3d4+3 recipe
    /// becomes 4d4+4, at L3 it becomes 5d5+5, etc.
    /// Flame Blade: `extraDicePerLevel(0, "1d6", levelsPerBonus: 2)` — L2 base
    /// = 3d6, L4 = 4d6, L6 = 5d6, L8 = 6d6.
    case extraDicePerLevel(recipeIndex: Int, dice: String, levelsPerBonus: Int)
    /// Informational scaling (used by spells whose mechanical effect doesn't
    /// change but text mentions "one extra target" per level).
    case extraTargetsPerLevel(Int)

    private enum CodingKeys: String, CodingKey {
        case type, recipeIndex, dice, value, levelsPerBonus
    }

    private enum Kind: String, Codable {
        case extraDicePerLevel, extraTargetsPerLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .extraDicePerLevel:
            let index = try c.decodeIfPresent(Int.self, forKey: .recipeIndex) ?? 0
            let dice  = try c.decode(String.self, forKey: .dice)
            // Default to 1 so pre-`levelsPerBonus` content decodes with the
            // original "one bonus per slot level" behavior untouched.
            let interval = try c.decodeIfPresent(Int.self, forKey: .levelsPerBonus) ?? 1
            self = .extraDicePerLevel(recipeIndex: index, dice: dice, levelsPerBonus: max(1, interval))
        case .extraTargetsPerLevel:
            self = .extraTargetsPerLevel(try c.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .extraDicePerLevel(let index, let dice, let interval):
            try c.encode(Kind.extraDicePerLevel, forKey: .type)
            try c.encode(index, forKey: .recipeIndex)
            try c.encode(dice, forKey: .dice)
            // Encode only when non-default so backward-compatible content
            // round-trips byte-for-byte.
            if interval != 1 { try c.encode(interval, forKey: .levelsPerBonus) }
        case .extraTargetsPerLevel(let n):
            try c.encode(Kind.extraTargetsPerLevel, forKey: .type)
            try c.encode(n, forKey: .value)
        }
    }

    /// Pre-`levelsPerBonus` construction shape — existing Swift test fixtures
    /// keep compiling and default to the original per-level behavior.
    static func extraDicePerLevel(recipeIndex: Int, dice: String) -> UpcastEffect {
        .extraDicePerLevel(recipeIndex: recipeIndex, dice: dice, levelsPerBonus: 1)
    }
}
