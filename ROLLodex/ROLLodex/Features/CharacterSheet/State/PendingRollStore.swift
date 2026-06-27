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
    /// Opt-in damage riders (Sneak Attack, Divine Smite, Fire's Burn …) the
    /// player can stack onto the damage roll after an attack lands. Unlike
    /// `followUps`, these are independent toggles: each carries only its OWN
    /// dice, and the dice tab combines the base damage with whichever are
    /// active, then rolls once (crit-aware, costs paid at roll time).
    var pendingRiders: [DamageRider] = []
    /// The character that dispatched `pending`. Used by the dice tab to
    /// apply reactive features (e.g. Stroke of Luck) that trigger after a
    /// roll settles. Cleared alongside `pending` when consumed.
    var pendingCharacterID: UUID?
    /// Costs the player has paid by tapping a chip in the dice tab. The
    /// character sheet observes this list and applies each cost (set turn
    /// flag, consume spell slot, etc.) to the bound character, then clears
    /// the list. Lets the dice tab fire chip side-effects without holding a
    /// reference to the character.
    var pendingCostsToApply: [TriggerCost] = []
    /// Feature resource costs (Second Wind's use, Channel Divinity, …) for a
    /// *rollable* action, parked when the dice tab actually rolls — so bailing
    /// before rolling doesn't burn the charge (audit #2). No-formula actions
    /// (Action Surge) still spend on tap, in the sheet.
    var pendingResourceCostsToApply: [ResourceCost] = []
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

/// An opt-in damage rider the player can toggle onto a damage roll (Sneak
/// Attack, Divine Smite at a chosen slot, Fire's Burn …). Carries ONLY the
/// rider's own dice — the dice tab merges it into the base damage when active,
/// so multiple riders stack into one roll and crit doubling applies to the
/// whole combined formula.
struct DamageRider: Identifiable, Equatable {
    let id: String
    /// Player-facing label, e.g. "Sneak Attack" or "Divine Smite (L1 slot)".
    let label: String
    /// The rider's own dice (typed), without the base weapon damage.
    let formula: DiceFormula
    /// What firing the rider costs — a once-per-turn flag or a spell slot.
    let cost: TriggerCost?
}
