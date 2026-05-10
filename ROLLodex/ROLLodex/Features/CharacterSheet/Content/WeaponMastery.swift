import Foundation

/// 5e (2024) Weapon Mastery properties. Each weapon may have one mastery that
/// becomes active when a character with the relevant class feature wields it.
enum WeaponMastery: String, Codable, Hashable, CaseIterable {
    case cleave
    case graze
    case nick
    case push
    case sap
    case slow
    case topple
    case vex

    /// Capitalized name for chips and popovers.
    var displayName: String { rawValue.capitalized }

    /// Short 5e SRD-style description. Surfaced in the mastery popover on
    /// weapon rows so the player can re-read the rule mid-combat without
    /// flipping to a separate reference.
    var summary: String {
        switch self {
        case .cleave:
            return "If you hit a creature with a melee attack using this weapon, you can make a second melee attack with it against another creature within 5 feet of the first that's also within your reach. On a hit, the second creature takes the weapon's damage but you don't add your ability modifier unless that modifier is negative. Once per turn."
        case .graze:
            return "If your attack roll with this weapon misses a creature, you can deal damage to that creature equal to the ability modifier you used to make the attack roll. The damage is the same type as the weapon's."
        case .nick:
            return "When you make the extra attack from the Light property, you can make it as part of the Attack action instead of as a Bonus Action. Once per turn."
        case .push:
            return "If you hit a creature with this weapon, you can push the creature up to 10 feet straight away from you if it is Large or smaller."
        case .sap:
            return "If you hit a creature with this weapon, that creature has Disadvantage on its next attack roll before the start of your next turn."
        case .slow:
            return "If you hit a creature with this weapon and deal damage, you can reduce its Speed by 10 feet until the start of your next turn. The reduction doesn't stack beyond 10 feet from multiple Slow hits."
        case .topple:
            return "If you hit a creature with this weapon, you can force it to make a Constitution save (DC 8 + your attack-roll ability mod + your Proficiency Bonus). On a failed save, the creature has the Prone condition."
        case .vex:
            return "If you hit a creature with this weapon and deal damage, you have Advantage on your next attack roll against that creature before the end of your next turn."
        }
    }
}
