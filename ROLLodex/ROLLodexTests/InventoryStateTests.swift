import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct InventoryStateTests {

    private let content = ContentStore(importedContentDirectory: Self.makeTempDir())

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeCharacter(inventory: [InventoryItem] = []) -> Character {
        Character(
            name: "Pack Mule",
            level: 5,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 40,
            inventory: inventory
        )
    }

    // MARK: - Equip / unequip

    @Test func equipToggleFlipsEquippedState() {
        var item = InventoryItem(itemID: "longsword")
        #expect(item.equipped == false)

        item.equipped = true
        #expect(item.equipped == true)

        item.equipped = false
        #expect(item.equipped == false)
    }

    @Test func attunedStateCanBeToggled() {
        var item = InventoryItem(itemID: "longsword")
        item.attuned = true
        #expect(item.attuned == true)
    }

    // MARK: - Attunement slots

    @Test func baseAttunementLimitIsThree() {
        let character = makeCharacter()
        #expect(CharacterCalculator.attunementLimit(character: character, content: content) == 3)
    }

    @Test func overrideAttunementLimitWins() {
        var character = makeCharacter()
        character.attunementSlotsOverride = 5
        #expect(CharacterCalculator.attunementLimit(character: character, content: content) == 5)
    }

    @Test func attunedItemCountCanExceedBaseLimit() {
        let items = (0..<4).map { _ in InventoryItem(itemID: "amulet", attuned: true) }
        let character = makeCharacter(inventory: items)
        let attunedCount = character.inventory.filter(\.attuned).count
        #expect(attunedCount == 4)
        #expect(CharacterCalculator.attunementLimit(character: character, content: content) == 3)
    }

    // MARK: - Attunement eligibility

    @Test func nonAttunementItemIsNotRequired() {
        let character = makeCharacter()
        let eligibility = CharacterCalculator.attunementEligibility(
            itemID: "longsword",
            character: character,
            content: content
        )
        #expect(eligibility == .notRequired)
    }

    @Test func attunementEligibilityRespectsRestrictions() throws {
        let dir = makeTempDir()
        try writeAttunementPack(to: dir)
        let store = ContentStore(importedContentDirectory: dir)
        let weakCharacter = makeCharacter()
        var strongCharacter = makeCharacter()
        strongCharacter.abilityScores[.strength] = 18

        let amulet = CharacterCalculator.attunementEligibility(
            itemID: "amulet_of_health",
            character: weakCharacter,
            content: store
        )
        let beltWeak = CharacterCalculator.attunementEligibility(
            itemID: "belt_of_giant_strength",
            character: weakCharacter,
            content: store
        )
        let beltStrong = CharacterCalculator.attunementEligibility(
            itemID: "belt_of_giant_strength",
            character: strongCharacter,
            content: store
        )

        #expect(amulet == .eligible)
        if case .blocked = beltWeak {
            // Expected
        } else {
            Issue.record("Expected belt to be blocked for low-Strength character")
        }
        #expect(beltStrong == .eligible)
    }

    // MARK: - Currency

    @Test func totalCopperConversion() {
        let purse = Currency(cp: 7, sp: 5, ep: 2, gp: 3, pp: 1)
        // 7 + 50 + 100 + 300 + 1000 = 1457
        #expect(purse.totalCopper == 1457)
    }

    @Test func emptyCurrencyIsZeroCopper() {
        #expect(Currency().totalCopper == 0)
    }

    // MARK: - Weight & quantity

    @Test func itemQuantityAffectsTotalWeight() {
        let longsword = InventoryItem(itemID: "longsword", quantity: 2)
        let weight = content.itemWeight(forItemID: longsword.itemID) ?? 0
        let total = weight * Double(longsword.quantity)
        #expect(total == 6.0)
    }

    @Test func inventoryWeightTotalsAcrossItems() {
        let items = [
            InventoryItem(itemID: "longsword", quantity: 1),
            InventoryItem(itemID: "chain_mail", quantity: 1)
        ]
        let total = items.reduce(0.0) { sum, item in
            let unit = content.itemWeight(forItemID: item.itemID) ?? 0
            return sum + unit * Double(item.quantity)
        }
        #expect(total == 58.0)
    }

    @Test func stackIdentityIsUUIDBased() {
        let a = InventoryItem(itemID: "longsword", quantity: 1)
        let b = InventoryItem(itemID: "longsword", quantity: 1)
        #expect(a.id != b.id)
        #expect(a != b)
        #expect(a.itemID == b.itemID)
        #expect(a.quantity + b.quantity == 2)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeAttunementPack(to dir: URL) throws {
        let json = """
        {
          "name": "Attunement Test Pack",
          "gear": [
            {
              "id": "amulet_of_health",
              "name": "Amulet of Health",
              "description": "Requires attunement.",
              "cost": 1000,
              "weight": 0.5,
              "category": "magic_item",
              "attunement": {}
            },
            {
              "id": "belt_of_giant_strength",
              "name": "Belt of Giant Strength",
              "description": "Requires attunement and STR 13.",
              "cost": 1000,
              "weight": 1.0,
              "category": "magic_item",
              "attunement": {
                "restrictions": {
                  "abilityScoreMinimums": { "strength": 13 }
                }
              }
            }
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("attunement.json"))
    }
}
