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
        // 2024 class skill choice (modeled as an L1 .skillsFrom selection).
        #expect(fighter?.skillProficiencySelection?.selection.count.value(classLevel: 1, characterLevel: 1) == 2)
    }

    @Test func rogueSkillChoiceIsChooseFourOfTen() {
        let store = ContentStore()
        let sel = store.classDefinition(id: "rogue")?.skillProficiencySelection
        #expect(sel?.selection.count.value(classLevel: 1, characterLevel: 1) == 4)
        #expect(sel?.options.count == 10)
        #expect(sel?.options.contains(.stealth) == true)
        #expect(sel?.options.contains(.sleightOfHand) == true)
        // Selection id carries the marker the calculator resolves on.
        #expect(sel?.selection.id.contains("class_skills") == true)
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
        // Criminal completes the SRD's 4 backgrounds.
        let criminal = store.backgroundDefinition(id: "criminal")
        #expect(criminal?.feat == "alert")
        #expect(criminal?.skillProficiencies.contains(.stealth) == true)
        #expect(criminal?.skillProficiencies.contains(.sleightOfHand) == true)
        // 2024 backgrounds list three boostable abilities (player distributes).
        #expect(criminal?.abilityScoreOptions == [.dexterity, .constitution, .intelligence])
        #expect(store.backgroundDefinition(id: "soldier")?.abilityScoreOptions.count == 3)
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
