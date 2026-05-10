import Foundation

/// What gets handed off when the user taps an action button. The `formula`
/// is the dice payload; `resourceCost`, when present, names a pool that gets
/// debited before the dice handoff. A button with a cost but no formula
/// (e.g., Action Surge) just consumes the resource and is otherwise a no-op.
struct ResolvedAction: Identifiable, Equatable {
    let id: String
    let label: String
    let formula: DiceFormula?
    let description: String?
    let resourceCost: ResourceCost?

    init(
        id: String,
        label: String,
        formula: DiceFormula?,
        description: String?,
        resourceCost: ResourceCost? = nil
    ) {
        self.id = id
        self.label = label
        self.formula = formula
        self.description = description
        self.resourceCost = resourceCost
    }
}

struct ResourceCost: Equatable {
    let resourceID: String
    let amount: Int
}
