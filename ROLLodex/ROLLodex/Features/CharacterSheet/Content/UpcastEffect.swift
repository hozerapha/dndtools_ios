import Foundation

/// How a spell's effect scales when cast using a slot above its base level.
/// Applied by `SpellCastSheet` before it runs the spell's recipes.
///
/// Phase J MVP ships `extraDicePerLevel` because that's the shape Magic
/// Missile and Cure Wounds use. The other cases are stubs for the larger
/// spell library — leave them out of v1 if you don't have content using them.
enum UpcastEffect: Codable, Equatable {
    /// Add `dice` to the damage / heal recipe at `recipeIndex`, once per
    /// slot level above the spell's base level.
    /// Magic Missile: `extraDicePerLevel(0, "1d4+1")` — at L2 the 3d4+3 recipe
    /// becomes 4d4+4, at L3 it becomes 5d5+5, etc.
    case extraDicePerLevel(recipeIndex: Int, dice: String)
    /// Informational scaling (used by spells whose mechanical effect doesn't
    /// change but text mentions "one extra target" per level).
    case extraTargetsPerLevel(Int)

    private enum CodingKeys: String, CodingKey {
        case type, recipeIndex, dice, value
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
            self = .extraDicePerLevel(recipeIndex: index, dice: dice)
        case .extraTargetsPerLevel:
            self = .extraTargetsPerLevel(try c.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .extraDicePerLevel(let index, let dice):
            try c.encode(Kind.extraDicePerLevel, forKey: .type)
            try c.encode(index, forKey: .recipeIndex)
            try c.encode(dice, forKey: .dice)
        case .extraTargetsPerLevel(let n):
            try c.encode(Kind.extraTargetsPerLevel, forKey: .type)
            try c.encode(n, forKey: .value)
        }
    }
}
