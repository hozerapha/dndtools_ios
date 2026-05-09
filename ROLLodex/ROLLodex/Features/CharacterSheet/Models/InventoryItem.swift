import Foundation

struct InventoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var itemID: String
    var quantity: Int
    var equipped: Bool
    var attuned: Bool

    init(
        id: UUID = UUID(),
        itemID: String,
        quantity: Int = 1,
        equipped: Bool = false,
        attuned: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.quantity = quantity
        self.equipped = equipped
        self.attuned = attuned
    }
}
