import SwiftUI

enum DieKind: Int, CaseIterable, Identifiable, Codable, Hashable {
    case d4 = 4
    case d6 = 6
    case d8 = 8
    case d10 = 10
    case d12 = 12
    case d20 = 20
    case d100 = 100

    var id: Int { rawValue }
    var label: String { "d\(rawValue)" }
    var sides: Int { rawValue }

    var color: Color {
        switch self {
        case .d4:   .red
        case .d6:   .orange
        case .d8:   .yellow
        case .d10:  .green
        case .d12:  .teal
        case .d20:  .blue
        case .d100: .purple
        }
    }
}
