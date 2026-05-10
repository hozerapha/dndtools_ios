import Foundation
import Observation

/// Cross-tab handoff queue. The character sheet writes a `ResolvedAction` here
/// when the user taps an action button; the dice roller reads + clears it on
/// appear / change, prefilling the formula and roll mode.
@Observable
@MainActor
final class PendingRollStore {
    var pending: ResolvedAction?
}
