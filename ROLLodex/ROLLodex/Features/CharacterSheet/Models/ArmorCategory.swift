import Foundation

// `nonisolated`: pure leaf enum used inside other nonisolated model
// types (ProficiencyKey) despite the target's MainActor default isolation.
nonisolated enum ArmorCategory: String, Codable, Hashable {
    case light
    case medium
    case heavy
    case shield
}
