import Foundation
import Observation

/// Cross-tab handoff queue. The character sheet writes a `ResolvedAction` here
/// when the user taps an action button; the dice roller reads + clears it on
/// appear / change, prefilling the formula and roll mode.
///
/// `followUp` carries an optional second action (typically the damage roll for
/// a spell attack) that the dice tab parks until the primary roll lands, then
/// surfaces as a "Roll damage?" chip so the player can chain it without going
/// back to the sheet.
@Observable
@MainActor
final class PendingRollStore {
    var pending: ResolvedAction?
    var followUp: ResolvedAction?
}
