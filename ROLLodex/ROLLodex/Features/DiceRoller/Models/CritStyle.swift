import Foundation

/// How a critical hit (natural 20 on an attack) modifies the damage roll.
///
/// The model is deliberately *composable* — the same shape the dice formulas
/// take — so it can grow into a fully custom editor later. Every named style is
/// just a `CritRule`: a dice transformation plus a flat-modifier multiplier.
/// A future "Custom" style would persist a `CritRule` directly; today we ship
/// named presets that map to one.

/// What happens to the *dice* portion of the damage on a crit.
enum CritDiceMode: String, Codable, CaseIterable, Equatable {
    /// Dice unchanged (used by Off, or as the base for a mods-only rule).
    case normal
    /// Roll twice as many dice (official RAW): `2d6` → `4d6`.
    case doubleCount
    /// Roll the normal dice, then double the rolled value (same average as
    /// `doubleCount`, swingier). Needs a result-time multiplier, not a static
    /// formula, so it sets `DiceFormula.diceResultMultiplier`.
    case doubleRolledValue
    /// Add the dice's maximum, then roll the normal dice too (popular homebrew):
    /// `2d6` → `12 + 2d6`.
    case maxPlusRoll
    /// The dice deal their maximum, no roll: `2d6` → `12`.
    case maximize
}

/// The composable core: a dice transformation + how many times flat modifiers
/// count. `modifierMultiplier` is 1 almost always; 2 expresses "double the
/// whole total, modifiers included."
struct CritRule: Equatable {
    var dice: CritDiceMode
    var modifierMultiplier: Int

    init(dice: CritDiceMode, modifierMultiplier: Int = 1) {
        self.dice = dice
        self.modifierMultiplier = modifierMultiplier
    }

    /// A rule that leaves damage untouched.
    static let off = CritRule(dice: .normal, modifierMultiplier: 1)
}

/// Named presets the player picks in Settings. Each resolves to a `CritRule`.
enum CritStyle: String, Codable, CaseIterable, Identifiable {
    case off
    case doubleDice        // RAW
    case doubleValue       // "Critical Role" — double what you rolled
    case maxPlusRoll       // homebrew
    case maximize          // deterministic max
    case doubleTotal       // double dice and modifiers

    var id: String { rawValue }

    var rule: CritRule {
        switch self {
        case .off:         return .off
        case .doubleDice:  return CritRule(dice: .doubleCount)
        case .doubleValue: return CritRule(dice: .doubleRolledValue)
        case .maxPlusRoll: return CritRule(dice: .maxPlusRoll)
        case .maximize:    return CritRule(dice: .maximize)
        case .doubleTotal: return CritRule(dice: .doubleRolledValue, modifierMultiplier: 2)
        }
    }

    var label: String {
        switch self {
        case .off:         return "Off"
        case .doubleDice:  return "Double the dice (RAW)"
        case .doubleValue: return "Double the rolled value"
        case .maxPlusRoll: return "Max die + roll"
        case .maximize:    return "Maximize dice"
        case .doubleTotal: return "Double the total"
        }
    }

    /// One-line explanation for the Settings picker, using a 2d6+3 example.
    var detail: String {
        switch self {
        case .off:         return "Damage isn't changed on a crit — handle it yourself."
        case .doubleDice:  return "Roll twice the dice, add modifiers once. 2d6+3 → 4d6+3."
        case .doubleValue: return "Roll normally, then double the dice you rolled. 2d6+3 → (2d6)×2 + 3."
        case .maxPlusRoll: return "Add the dice's max, then roll them too. 2d6+3 → 12 + 2d6 + 3."
        case .maximize:    return "Dice deal their maximum, no roll. 2d6+3 → 12 + 3 = 15."
        case .doubleTotal: return "Double everything — dice and modifiers. 2d6+3 → (2d6)×2 + 6."
        }
    }

    /// `@AppStorage` key for the saved default; the raw value is persisted.
    static let storageKey = "crit.style"
    /// Official rules default.
    static let `default`: CritStyle = .doubleDice
}
