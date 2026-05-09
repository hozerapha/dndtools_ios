import Foundation

enum WeaponProperty: String, Codable, Hashable {
    case finesse
    case light
    case heavy
    case twoHanded = "two_handed"
    case thrown
    case versatile
    case loading
    case ammunition
    case reach
}
