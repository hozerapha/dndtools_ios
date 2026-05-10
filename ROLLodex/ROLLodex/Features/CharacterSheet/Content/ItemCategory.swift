import Foundation

enum ItemCategory: String, Codable, Hashable {
    case weapon
    case armor
    case adventuringGear = "adventuring_gear"
    case tool
    case consumable
    case treasure
    /// Wands, rods, rings, wondrous items — magical gear with charges and/or
    /// attunement. Distinct from `.treasure` (loot you sell) and `.consumable`
    /// (potions, scrolls) so the UI can group them as "magic items" later.
    case magicItem = "magic_item"
}
