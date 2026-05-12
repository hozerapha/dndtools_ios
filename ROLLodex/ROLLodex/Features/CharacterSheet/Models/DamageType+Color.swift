import UIKit

extension DamageType {
    /// Color the dice-tray glow light uses for this damage type. Tuned for
    /// `SCNLight` colors — saturated and bright (channels mostly 0.6–1.0) so
    /// the colored pool the omni light pours onto the felt actually reads. The
    /// SceneKit lighting model handles falloff, so we don't need to dim these
    /// for "subtlety" — falloff distance does that work.
    var glowColor: UIColor {
        switch self {
        case .bludgeoning: return UIColor(red: 0.85, green: 0.62, blue: 0.40, alpha: 1) // warm tan
        case .piercing:    return UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1) // steel blue
        case .slashing:    return UIColor(red: 1.00, green: 0.35, blue: 0.30, alpha: 1) // crimson
        case .acid:        return UIColor(red: 0.55, green: 1.00, blue: 0.20, alpha: 1) // bright green
        case .cold:        return UIColor(red: 0.45, green: 0.85, blue: 1.00, alpha: 1) // ice cyan
        case .fire:        return UIColor(red: 1.00, green: 0.50, blue: 0.10, alpha: 1) // orange-red
        case .force:       return UIColor(red: 0.75, green: 0.55, blue: 1.00, alpha: 1) // violet
        case .lightning:   return UIColor(red: 1.00, green: 0.95, blue: 0.30, alpha: 1) // electric yellow
        case .necrotic:    return UIColor(red: 0.45, green: 0.85, blue: 0.40, alpha: 1) // sickly green
        case .poison:      return UIColor(red: 0.75, green: 1.00, blue: 0.20, alpha: 1) // toxic chartreuse
        case .psychic:     return UIColor(red: 1.00, green: 0.40, blue: 0.85, alpha: 1) // hot magenta
        case .radiant:     return UIColor(red: 1.00, green: 0.90, blue: 0.55, alpha: 1) // warm gold
        case .thunder:     return UIColor(red: 0.65, green: 0.70, blue: 1.00, alpha: 1) // bright periwinkle
        }
    }
}
