import Foundation

enum RollMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case normal
    case advantage
    case disadvantage

    var id: Self { self }

    var shortLabel: String {
        switch self {
        case .normal:       "Normal"
        case .advantage:    "Adv."
        case .disadvantage: "Dis."
        }
    }

    var label: String {
        switch self {
        case .normal:       "Normal"
        case .advantage:    "Advantage"
        case .disadvantage: "Disadvantage"
        }
    }
}
