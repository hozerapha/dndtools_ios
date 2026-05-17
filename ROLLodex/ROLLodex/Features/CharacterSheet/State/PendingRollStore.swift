import Foundation
import Observation

/// Cross-tab handoff queue. The character sheet writes a `ResolvedAction` here
/// when the user taps an action button; the dice roller reads + clears it on
/// appear / change, prefilling the formula and roll mode.
///
/// `followUps` carries any number of secondary actions the dice tab should
/// surface as chips after the primary roll lands — the canonical pair is a
/// spell attack's damage roll plus any opt-in riders (Sneak Attack, Divine
/// Smite) the character can also choose to apply.
@Observable
@MainActor
final class PendingRollStore {
    var pending: ResolvedAction?
    var followUps: [PendingFollowUp] = []
    /// Costs the player has paid by tapping a chip in the dice tab. The
    /// character sheet observes this list and applies each cost (set turn
    /// flag, consume spell slot, etc.) to the bound character, then clears
    /// the list. Lets the dice tab fire chip side-effects without holding a
    /// reference to the character.
    var pendingCostsToApply: [TriggerCost] = []
}

/// One chip in the post-primary follow-up rail. Bundles the action with the
/// cost the player pays when they fire it — once-per-turn flags for now,
/// spell-slot cost when Paladin lands.
struct PendingFollowUp: Identifiable, Equatable {
    let id: String
    let action: ResolvedAction
    /// Optional cost paid when the chip is tapped. Nil for "automatic"
    /// chained rolls (the existing weapon-attack → damage handoff).
    let cost: TriggerCost?
    /// Cosmetic short label rendered on the chip ("Roll damage?",
    /// "Sneak Attack +1d6"). Defaults to the action's own label.
    let chipPrompt: String?

    init(
        id: String,
        action: ResolvedAction,
        cost: TriggerCost? = nil,
        chipPrompt: String? = nil
    ) {
        self.id = id
        self.action = action
        self.cost = cost
        self.chipPrompt = chipPrompt
    }

    /// Convenience for the legacy "attack → damage" pairing where there's no
    /// special cost. Reuses the action's id so duplicate enqueues collapse.
    static func chainedDamage(_ action: ResolvedAction) -> PendingFollowUp {
        PendingFollowUp(id: "chained_\(action.id)", action: action)
    }
}
