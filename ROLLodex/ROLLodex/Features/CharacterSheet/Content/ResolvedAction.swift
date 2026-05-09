import Foundation

struct ResolvedAction: Identifiable, Equatable {
    let id: String
    let label: String
    let formula: DiceFormula?
    let mode: RollMode?
    let description: String?
}
