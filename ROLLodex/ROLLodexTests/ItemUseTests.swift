import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct ItemUseTests {

    // MARK: - Codable round-trips

    @Test func wandOfMagicMissilesJSONDecodes() throws {
        // Lifted verbatim from gear.json so the test catches schema drift.
        let json = """
        {
          "id": "wand_of_magic_missiles",
          "name": "Wand of Magic Missiles",
          "description": "...",
          "cost": 800000,
          "weight": 1,
          "category": "magic_item",
          "attunement": {},
          "resource": {
            "id": "wand_of_magic_missiles_charges",
            "name": "Wand Charges",
            "max": 7,
            "refreshOn": "dawn",
            "refreshAmount": { "roll": "1d6+1" }
          },
          "uses": [
            {
              "id": "cast_magic_missile",
              "name": "Cast Magic Missile",
              "cost": { "resourceID": "wand_of_magic_missiles_charges", "amount": 1 },
              "effect": { "type": "castSpell", "spellID": "magic_missile", "atLevel": 1 },
              "upcastChoice": { "maxLevel": 3, "extraCostPerLevel": 1 }
            }
          ]
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(ItemDefinition.self, from: json)
        #expect(item.id == "wand_of_magic_missiles")
        #expect(item.attunement != nil)
        #expect(item.resource?.id == "wand_of_magic_missiles_charges")
        #expect(item.resource?.refreshOn == .dawn)
        if case .roll(let formula)? = item.resource?.refreshAmount {
            #expect(formula == "1d6+1")
        } else {
            Issue.record("Expected .roll refreshAmount")
        }
        #expect(item.uses.count == 1)
        let use = item.uses[0]
        #expect(use.cost.amount == 1)
        if case .castSpell(let spellID, let level) = use.effect {
            #expect(spellID == "magic_missile")
            #expect(level == 1)
        } else {
            Issue.record("Expected .castSpell effect")
        }
        #expect(use.upcastChoice?.maxLevel == 3)
        #expect(use.upcastChoice?.extraCostPerLevel == 1)
    }

    @Test func itemUseEffectRoundTripsCastSpell() throws {
        let effect = ItemUseEffect.castSpell(spellID: "fire_bolt", atLevel: 0)
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(ItemUseEffect.self, from: data)
        #expect(decoded == effect)
    }

    @Test func itemUseEffectRoundTripsActionRecipes() throws {
        let effect = ItemUseEffect.actionRecipes([
            .heal(dice: "2d4+2", addLevel: false, label: "Potion of Healing")
        ])
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(ItemUseEffect.self, from: data)
        #expect(decoded == effect)
    }

    @Test func itemWithoutResourceOrUsesDecodes() throws {
        // Backwards compat: existing gear without `resource` / `uses` keys.
        let json = """
        {
          "id": "torch",
          "name": "Torch",
          "description": "A wooden stick with an oil-soaked head.",
          "cost": 1,
          "weight": 1,
          "category": "adventuring_gear"
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(ItemDefinition.self, from: json)
        #expect(item.resource == nil)
        #expect(item.uses.isEmpty)
    }

    // MARK: - ItemSpellCastContext math

    @Test func itemSpellCastContextScalesCostByLevel() {
        let ctx = ItemSpellCastContext(
            spellID: "magic_missile",
            itemName: "Wand of Magic Missiles",
            resourceID: "wand_of_magic_missiles_charges",
            baseLevel: 1,
            maxLevel: 3,
            baseCost: 1,
            extraCostPerLevel: 1
        )
        #expect(ctx.cost(forLevel: 1) == 1)
        #expect(ctx.cost(forLevel: 2) == 2)
        #expect(ctx.cost(forLevel: 3) == 3)
    }

    @Test func itemSpellCastContextCostFlatWhenNoUpcast() {
        let ctx = ItemSpellCastContext(
            spellID: "magic_missile",
            itemName: "Wand of MM",
            resourceID: "x",
            baseLevel: 1,
            maxLevel: 1,
            baseCost: 1,
            extraCostPerLevel: 0
        )
        #expect(ctx.cost(forLevel: 1) == 1)
    }

    // MARK: - Resource availability

    @Test func unattunedWandHasNoResourceInPool() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: false, attuned: false)]
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let wand = resources.first { $0.definition.id == "wand_of_magic_missiles_charges" }
        #expect(wand == nil)
    }

    @Test func attunedWandSurfacesChargesPool() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let wand = resources.first { $0.definition.id == "wand_of_magic_missiles_charges" }
        #expect(wand?.max == 7)
        #expect(wand?.current == 7) // unset state defaults to full
    }

    @Test func twoWandsShareOnePool() {
        // Per Phase K.1 the resource ID is namespaced to the *item*, not the
        // inventory stack — two wands share the same charges entry.
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [
            InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true),
            InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: false, attuned: true)
        ]
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let wandPools = resources.filter { $0.definition.id == "wand_of_magic_missiles_charges" }
        #expect(wandPools.count == 1)
    }

    // MARK: - Action grid

    @Test func attunedEquippedWandShowsItemUseRow() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let items = sections.first { $0.id == "item_uses" }
        #expect(items?.rows.count == 1)
        let row = items?.rows.first
        #expect(row?.castFromItem?.spellID == "magic_missile")
        #expect(row?.castFromItem?.baseLevel == 1)
        #expect(row?.castFromItem?.maxLevel == 3)
        #expect(row?.castFromItem?.baseCost == 1)
        #expect(row?.castFromItem?.extraCostPerLevel == 1)
    }

    @Test func unattunedWandShowsNoItemUseRow() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: false)]
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let items = sections.first { $0.id == "item_uses" }
        #expect(items == nil)
    }

    @Test func unequippedWandShowsNoItemUseRow() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: false, attuned: true)]
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let items = sections.first { $0.id == "item_uses" }
        #expect(items == nil)
        // Still present in the resources card though — carried-but-not-equipped
        // items remain spendable manually.
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        #expect(resources.contains { $0.definition.id == "wand_of_magic_missiles_charges" })
    }

    @Test func exhaustedWandMarksRowExhausted() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        character.resources = ["wand_of_magic_missiles_charges": ResourceState(current: 0)]
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let row = sections.first { $0.id == "item_uses" }?.rows.first
        #expect(row?.isExhausted == true)
    }

    // MARK: - Long-rest dawn refresh

    @Test func longRestQueuesPendingRefreshForWandCharges() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        // Drain a few charges so the refresh has something to do.
        character.resources = ["wand_of_magic_missiles_charges": ResourceState(current: 3)]
        let pending = ResourceCalculator.applyRest(.long, to: &character, content: store)
        let wandRefresh = pending.first { $0.resourceID == "wand_of_magic_missiles_charges" }
        #expect(wandRefresh?.formula == "1d6+1")
    }

    @Test func shortRestDoesNotRefreshWandCharges() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        character.resources = ["wand_of_magic_missiles_charges": ResourceState(current: 3)]
        let pending = ResourceCalculator.applyRest(.short, to: &character, content: store)
        #expect(pending.contains { $0.resourceID == "wand_of_magic_missiles_charges" } == false)
        #expect(character.resources["wand_of_magic_missiles_charges"]?.current == 3) // unchanged
    }

    @Test func resolvedRefreshCapsAtMax() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        character.resources = ["wand_of_magic_missiles_charges": ResourceState(current: 5)]
        // Simulate a 1d6+1 roll of 7 (max possible) — should cap at 7, not jump to 12.
        ResourceCalculator.applyResolvedRefresh(
            resourceID: "wand_of_magic_missiles_charges",
            amount: 7,
            in: &character,
            content: store
        )
        #expect(character.resources["wand_of_magic_missiles_charges"]?.current == 7)
    }

    // MARK: - Consumption math

    @Test func consumingChargesDecrementsPool() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        // L2 cast = 2 charges (base 1 + 1 extra).
        let ok = ResourceCalculator.consume(
            amount: 2,
            from: "wand_of_magic_missiles_charges",
            in: &character,
            content: store
        )
        #expect(ok)
        #expect(character.resources["wand_of_magic_missiles_charges"]?.current == 5)
    }

    @Test func overdraftFailsAndLeavesPoolUnchanged() {
        let store = ContentStore()
        var character = makeWizard()
        character.inventory = [InventoryItem(itemID: "wand_of_magic_missiles", quantity: 1, equipped: true, attuned: true)]
        character.resources = ["wand_of_magic_missiles_charges": ResourceState(current: 1)]
        // L3 cast = 3 charges, but the wand only has 1 — should fail.
        let ok = ResourceCalculator.consume(
            amount: 3,
            from: "wand_of_magic_missiles_charges",
            in: &character,
            content: store
        )
        #expect(ok == false)
        #expect(character.resources["wand_of_magic_missiles_charges"]?.current == 1)
    }

    // MARK: - Helpers

    private func makeWizard() -> Character {
        Character(
            name: "Mordenkainen", level: 1,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 1)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 16, .wisdom: 12, .charisma: 10
            ],
            maxHP: 6
        )
    }
}
