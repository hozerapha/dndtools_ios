import Foundation

/// When a resource refreshes back toward its max. A resource refreshed by
/// `.shortRest` *also* refreshes on long rest (per 5e: a long rest counts as
/// a short rest for refresh purposes). `.dawn` is folded into `.longRest` for
/// MVP — see Phase K.5 in PLAN_CharacterSheet.md.
enum RefreshTrigger: String, Codable, Equatable {
    case shortRest
    case longRest
    case dawn
    case encounter
    case never

    /// Whether this trigger fires for a given rest kind.
    func fires(on rest: RestKind) -> Bool {
        switch (self, rest) {
        case (.never, _):                       return false
        case (.encounter, _):                   return false
        case (.shortRest, .short),
             (.shortRest, .long):               return true
        case (.longRest, .long):                return true
        case (.dawn, .long):                    return true   // dawn folds into long rest for now
        case (.longRest, .short),
             (.dawn, .short):                   return false
        }
    }
}

enum RestKind: String, Codable, CaseIterable, Identifiable {
    case short, long
    var id: Self { self }

    var displayName: String {
        switch self {
        case .short: return "Short Rest"
        case .long:  return "Long Rest"
        }
    }
}
