import Foundation

/// How a randomly-determined value gets settled. The player picks a default in
/// Settings; any prompt can override per-roll. Used by Phase I's resource
/// refresh prompts and (eventually) every other random outcome in the sheet.
enum RollResolutionMode: String, Codable, CaseIterable, Identifiable {
    /// User types the result they rolled IRL. Number-pad input.
    case manual
    /// Push the formula into the dice tab and wait for the user to roll it.
    /// Default for action handoffs. For rest refreshes Phase I currently
    /// falls back to `.behindTheScenes` (deferred coordination work).
    case tray
    /// Generate `Int.random(in: 1...sides)` per die and apply the result
    /// without any UI step. Fastest path for groups that don't care about
    /// theatrics on every refresh roll.
    case behindTheScenes

    var id: Self { self }

    var label: String {
        switch self {
        case .manual:           return "Type result"
        case .tray:             return "Roll in dice tray"
        case .behindTheScenes:  return "Roll behind the scenes"
        }
    }

    var systemImage: String {
        switch self {
        case .manual:           return "keyboard"
        case .tray:             return "dice.fill"
        case .behindTheScenes:  return "wand.and.stars"
        }
    }
}

/// Settings key for the global default. The per-prompt override never persists.
enum RollResolutionDefaults {
    static let storageKey = "roll.resolution.default"
}
