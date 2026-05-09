import Foundation

enum ItemCategory: String, Codable, Hashable {
    case weapon
    case armor
    case adventuringGear = "adventuring_gear"
    case tool
    case consumable
    case treasure
}
