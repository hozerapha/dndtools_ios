import Foundation

// `nonisolated`: pure leaf enum used inside other nonisolated model
// types (ProficiencyKey) despite the target's MainActor default isolation.
nonisolated enum WeaponCategory: String, Codable, Hashable {
    case simple
    case martial
}
