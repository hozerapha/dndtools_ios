import Testing
import Foundation
@testable import ROLLodex

struct ContentStoreTests {

    @Test func loadsFighterClass() {
        let store = ContentStore()
        let fighter = store.classDefinition(id: "fighter")
        #expect(fighter != nil)
        #expect(fighter?.name == "Fighter")
        #expect(fighter?.hitDie == .d10)
        #expect(fighter?.primaryAbility == .strength)
        #expect(fighter?.savingThrows.contains(.strength) == true)
        #expect(fighter?.armorProficiencies.contains(.heavy) == true)
        #expect(fighter?.weaponProficiencies.contains(.martial) == true)
        #expect(fighter?.masteryCount == 3)
    }

    @Test func loadsWizardClass() {
        let store = ContentStore()
        let wizard = store.classDefinition(id: "wizard")
        #expect(wizard != nil)
        #expect(wizard?.name == "Wizard")
        #expect(wizard?.hitDie == .d6)
        #expect(wizard?.primaryAbility == .intelligence)
        #expect(wizard?.armorProficiencies.isEmpty == true)
        #expect(wizard?.masteryCount == nil)
    }

    @Test func loadsSpecies() {
        let store = ContentStore()
        #expect(store.speciesDefinition(id: "human")?.name == "Human")
        #expect(store.speciesDefinition(id: "elf")?.name == "Elf")
        #expect(store.speciesDefinition(id: "dwarf")?.name == "Dwarf")
    }

    @Test func loadsBackgrounds() {
        let store = ContentStore()
        #expect(store.backgroundDefinition(id: "soldier")?.name == "Soldier")
        #expect(store.backgroundDefinition(id: "sage")?.skillProficiencies.contains(.arcana) == true)
        #expect(store.backgroundDefinition(id: "acolyte")?.feat == "magic_initiate_cleric")
    }

    @Test func loadsWeapons() {
        let store = ContentStore()
        let longsword = store.weaponDefinition(id: "longsword")
        #expect(longsword != nil)
        #expect(longsword?.damage == "1d8")
        #expect(longsword?.versatileDamage == "1d10")
        #expect(longsword?.masteryProperty == .sap)
        #expect(longsword?.properties.contains(.versatile) == true)

        let rapier = store.weaponDefinition(id: "rapier")
        #expect(rapier?.properties.contains(.finesse) == true)
        #expect(rapier?.masteryProperty == .vex)
    }

    @Test func loadsArmor() {
        let store = ContentStore()
        let chainMail = store.armorDefinition(id: "chain_mail")
        #expect(chainMail?.acBase == 16)
        #expect(chainMail?.dexCap == 0)
        #expect(chainMail?.armorCategory == .heavy)

        let leather = store.armorDefinition(id: "leather")
        #expect(leather?.dexCap == nil)
        #expect(leather?.armorCategory == .light)
    }

    @Test func itemNameLookup() {
        let store = ContentStore()
        #expect(store.itemName(forItemID: "longsword") == "Longsword")
        #expect(store.itemName(forItemID: "chain_mail") == "Chain Mail")
        #expect(store.itemName(forItemID: "backpack") == "Backpack")
        #expect(store.itemName(forItemID: "nonexistent") == nil)
    }
}
