import SwiftUI

/// Interactive exchange sheet for the Druid L5 Wild Resurgence feature.
/// Presents both SRD-documented trades with live gating:
///
/// 1. **Spell slot → Wild Shape use** — legal only when Wild Shape is at 0
///    and any leveled slot is available. Once per turn (turn flag).
/// 2. **Wild Shape use → level-1 slot** — legal only when a WS use is
///    available and L1 isn't already at max. Once per Long Rest (tracked
///    via the `druid_wild_resurgence_trade` resource pool).
///
/// Actions mutate the underlying resource pools directly; no dice roll is
/// involved. The sheet stays open after a trade so the player can see the
/// updated state, and dismisses on Done.
struct WildResurgenceSheet: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    static let slotToWSTurnFlag = "wild_resurgence_slot_to_ws"
    static let tradeResourceID = "druid_wild_resurgence_trade"
    static let wildShapeResourceID = "druid_wild_shape"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    slotToWildShapeCard
                    wildShapeToSlotCard
                    statusFooter
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wild Resurgence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trade a resource — no action required.")
                .font(.subheadline.weight(.semibold))
            Text("SRD 5.2.1 · Once on each of your turns you can spend a spell slot to regain a Wild Shape use (only when Wild Shape is empty). Once per Long Rest you can spend a Wild Shape use to regain a level-1 slot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var slotToWildShapeCard: some View {
        let usableSlot = lowestAvailableSlot()
        let alreadyUsedThisTurn = character.hasTurnFlag(Self.slotToWSTurnFlag)
        let wsCurrent = currentPool(id: Self.wildShapeResourceID)?.current ?? 0
        let wsAtZero = wsCurrent == 0
        let canTrade = wsAtZero && usableSlot != nil && !alreadyUsedThisTurn

        return exchangeCard(
            title: "Spend a spell slot → +1 Wild Shape use",
            subtitle: usableSlot.map { "Spends your lowest available slot: L\($0.level)." }
                ?? "No spell slots available.",
            statusLine: statusLine(
                wsAtZero: wsAtZero,
                usableSlot: usableSlot,
                alreadyUsedThisTurn: alreadyUsedThisTurn
            ),
            actionLabel: "Trade slot → Wild Shape",
            actionEnabled: canTrade,
            tint: .green,
            action: {
                guard let slot = usableSlot else { return }
                var copy = character
                _ = ResourceCalculator.consume(amount: 1, from: slot.id, in: &copy, content: content)
                let wsMax = currentPool(id: Self.wildShapeResourceID)?.max ?? 0
                let newWS = min(wsCurrent + 1, wsMax)
                ResourceCalculator.setCurrent(
                    newWS, for: Self.wildShapeResourceID,
                    in: &copy, content: content
                )
                copy.setTurnFlag(Self.slotToWSTurnFlag)
                character = copy
            }
        )
    }

    private var wildShapeToSlotCard: some View {
        let wsCurrent = currentPool(id: Self.wildShapeResourceID)?.current ?? 0
        let slotL1 = currentPool(matchingSlotLevel: 1)
        let tradeLeft = currentPool(id: Self.tradeResourceID)?.current ?? 0
        let l1Room = (slotL1?.max ?? 0) - (slotL1?.current ?? 0)
        let canTrade = wsCurrent > 0 && l1Room > 0 && tradeLeft > 0 && slotL1 != nil

        return exchangeCard(
            title: "Spend a Wild Shape use → +1 L1 spell slot",
            subtitle: slotL1 == nil
                ? "No L1 slot resource on this character."
                : "Restores 1 L1 slot up to max.",
            statusLine: reverseStatusLine(
                wsCurrent: wsCurrent,
                slotL1: slotL1,
                tradeLeft: tradeLeft
            ),
            actionLabel: "Trade Wild Shape → L1 slot",
            actionEnabled: canTrade,
            tint: .purple,
            action: {
                guard let slot = slotL1 else { return }
                var copy = character
                _ = ResourceCalculator.consume(
                    amount: 1, from: Self.wildShapeResourceID, in: &copy, content: content
                )
                ResourceCalculator.setCurrent(
                    min(slot.current + 1, slot.max), for: slot.id,
                    in: &copy, content: content
                )
                _ = ResourceCalculator.consume(
                    amount: 1, from: Self.tradeResourceID, in: &copy, content: content
                )
                character = copy
            }
        )
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live state")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            resourceRow("Wild Shape", id: Self.wildShapeResourceID)
            resourceRow("Trade Available (LR)", id: Self.tradeResourceID)
            ForEach(slotResources(), id: \.definition.id) { slot in
                HStack {
                    Text("L\(slotLevel(of: slot) ?? 0) slot").font(.caption)
                    Spacer()
                    Text("\(slot.current) / \(slot.max)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resourceRow(_ label: String, id: String) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            let pool = currentPool(id: id)
            Text("\(pool?.current ?? 0) / \(pool?.max ?? 0)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: - Reusable card

    private func exchangeCard(
        title: String,
        subtitle: String,
        statusLine: String,
        actionLabel: String,
        actionEnabled: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Text(statusLine).font(.caption).foregroundStyle(actionEnabled ? tint : .secondary)
            Button(action: action) {
                Label(actionLabel, systemImage: "arrow.left.arrow.right")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        (actionEnabled ? tint : Color.gray).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(actionEnabled ? tint : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!actionEnabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status lines

    private func statusLine(
        wsAtZero: Bool, usableSlot: (id: String, level: Int)?, alreadyUsedThisTurn: Bool
    ) -> String {
        if alreadyUsedThisTurn { return "Already traded this turn." }
        if !wsAtZero { return "Wild Shape must be at 0 to trade a slot for it." }
        if usableSlot == nil { return "No spell slots to spend." }
        return "Ready — trade eligible."
    }

    private func reverseStatusLine(
        wsCurrent: Int, slotL1: ResolvedResource?, tradeLeft: Int
    ) -> String {
        if tradeLeft <= 0 { return "Already used this Long Rest." }
        if wsCurrent <= 0 { return "Need at least one Wild Shape use." }
        if let s = slotL1, s.current >= s.max { return "L1 slot is already full." }
        return "Ready — trade eligible."
    }

    // MARK: - Resource lookups

    private func currentPool(id: String) -> ResolvedResource? {
        allResources().first { $0.definition.id == id }
    }

    private func slotResources() -> [ResolvedResource] {
        allResources().filter { slotLevel(of: $0) != nil }
            .sorted { (slotLevel(of: $0) ?? 0) < (slotLevel(of: $1) ?? 0) }
    }

    /// Lowest-level slot the character currently has a use of. Prefers
    /// L1 → L9. Returns nil when no slots are available.
    private func lowestAvailableSlot() -> (id: String, level: Int)? {
        for slot in slotResources() where slot.current > 0 {
            if let level = slotLevel(of: slot) {
                return (slot.definition.id, level)
            }
        }
        return nil
    }

    private func currentPool(matchingSlotLevel level: Int) -> ResolvedResource? {
        slotResources().first { slotLevel(of: $0) == level }
    }

    private func slotLevel(of resolved: ResolvedResource) -> Int? {
        if case .spellSlot(let level) = resolved.definition.displayHint { return level }
        return nil
    }

    private func allResources() -> [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: content)
    }
}
