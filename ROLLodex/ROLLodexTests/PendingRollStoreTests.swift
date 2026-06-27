import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct PendingRollStoreTests {

    private func makeAction(id: String = "action") -> ResolvedAction {
        ResolvedAction(
            id: id,
            label: "Test Action",
            formula: DiceFormula(),
            description: nil,
            resourceCost: nil,
            actionCost: .action
        )
    }

    private func makeCost() -> TriggerCost {
        .oncePerTurn(flagID: "sneak_attack")
    }

    // MARK: - Pending action

    @Test func enqueueAndClearPending() {
        let store = PendingRollStore()
        let action = makeAction()
        store.pending = action

        #expect(store.pending != nil)
        let equal = store.pending == action
        #expect(equal)

        store.pending = nil
        #expect(store.pending == nil)
    }

    @Test func pendingCharacterIDTracksHandoff() {
        let store = PendingRollStore()
        let id = UUID()
        store.pendingCharacterID = id

        #expect(store.pendingCharacterID == id)

        store.pendingCharacterID = nil
        #expect(store.pendingCharacterID == nil)
    }

    // MARK: - Follow-ups

    @Test func setFollowUpsAndClearIndependently() {
        let store = PendingRollStore()
        let action = makeAction(id: "damage")
        let followUp = PendingFollowUp.chainedDamage(action)
        store.followUps = [followUp]

        #expect(store.followUps.count == 1)
        #expect(store.followUps.first?.id == "chained_\(action.id)")

        store.followUps.removeAll()
        #expect(store.followUps.isEmpty)
    }

    // MARK: - Costs to apply

    @Test func pendingCostsToApplyAccumulate() {
        let store = PendingRollStore()
        let cost = makeCost()
        store.pendingCostsToApply = [cost]

        #expect(store.pendingCostsToApply.count == 1)
        let equal = store.pendingCostsToApply.first == cost
        #expect(equal)
    }

    @Test func consumptionOrderClearsPendingButLeavesFollowUpsAndCosts() {
        let store = PendingRollStore()
        store.pending = makeAction()
        store.followUps = [PendingFollowUp.chainedDamage(makeAction(id: "dmg"))]
        store.pendingCostsToApply = [makeCost()]

        // Simulate dice-tab consumption of the primary action.
        store.pending = nil

        #expect(store.pending == nil)
        #expect(store.followUps.count == 1)
        #expect(store.pendingCostsToApply.count == 1)
    }

    // MARK: - Idempotency

    @Test func reEnqueuingSamePendingIsIdempotent() {
        let store = PendingRollStore()
        let action = makeAction()
        store.pending = action
        store.pending = action

        #expect(store.pending != nil)
        let equal = store.pending == action
        #expect(equal)
    }

    @Test func chainedDamageReusesActionID() {
        let action = makeAction(id: "base_damage")
        let followUp = PendingFollowUp.chainedDamage(action)

        #expect(followUp.id == "chained_\(action.id)")
        #expect(followUp.cost == nil)
    }
}
