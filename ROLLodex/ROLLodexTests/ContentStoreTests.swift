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
        // All 9 SRD 5.2.1 species present.
        for id in ["dragonborn", "gnome", "goliath", "halfling", "orc", "tiefling"] {
            #expect(store.speciesDefinition(id: id) != nil, "missing species \(id)")
        }
        #expect(store.speciesDefinition(id: "gnome")?.size == "small")
        #expect(store.speciesDefinition(id: "goliath")?.speed == 35)
        #expect(store.speciesDefinition(id: "dragonborn")?.traits.contains { $0.id == "breath_weapon" } == true)
    }

    @MainActor
    @Test func speciesTraitChoicesAndFormulas() {
        let store = ContentStore()

        func optionCount(species: String, trait: String) -> Int? {
            let t = store.speciesDefinition(id: species)?.traits.first { $0.id == trait }
            guard case .fixedOptions(let options)? = t?.selection?.optionsSource else { return nil }
            return options.count
        }

        // Elf gained the previously-missing Elven Lineage picker.
        #expect(store.speciesDefinition(id: "elf")?.traits.first { $0.id == "elven_lineage" }?
            .selection?.id == "elf_lineage")
        #expect(optionCount(species: "elf", trait: "elven_lineage") == 3)

        // Lineage / ancestry / legacy pickers across the new species.
        #expect(optionCount(species: "dragonborn", trait: "draconic_ancestry") == 10)
        #expect(optionCount(species: "gnome", trait: "gnomish_lineage") == 2)
        #expect(optionCount(species: "goliath", trait: "giant_ancestry") == 6)
        #expect(optionCount(species: "tiefling", trait: "fiendish_legacy") == 3)

        // Dragonborn Breath Weapon: Action cost, scaledDamage recipe, PB pool.
        let breath = store.speciesDefinition(id: "dragonborn")?.traits.first { $0.id == "breath_weapon" }
        let breathCost = breath?.actionCost
        #expect(breathCost == .action)
        #expect(breath?.resource?.id == "dragonborn_breath_weapon")
        var breathScales = false
        if case .scaledDamage(let dieKind, _, _, _)? = breath?.actionRecipes.first {
            breathScales = dieKind == 10
        }
        #expect(breathScales)

        // Dwarf Stonecunning is now the 5.2.1 Bonus Action with a pool.
        let stone = store.speciesDefinition(id: "dwarf")?.traits.first { $0.id == "stonecunning" }
        let stoneCost = stone?.actionCost
        #expect(stoneCost == .bonusAction)
        #expect(stone?.resource?.id == "dwarf_stonecunning")

        // The Breath Weapon pool resolves to PB-many uses (3 at level 5).
        let pc = Character(
            name: "Drogon", level: 5, speciesID: "dragonborn", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.constitution: 14], maxHP: 30
        )
        let pools = ResourceCalculator.availableResources(character: pc, content: store)
        #expect(pools.first { $0.definition.id == "dragonborn_breath_weapon" }?.max == 3)
    }

    @MainActor
    @Test func speciesSpellGrantsResolveByLevelAndChoice() {
        let store = ContentStore()
        func infernalTiefling(level: Int, legacy: String? = "infernal") -> Character {
            var c = Character(
                name: "Zariel", level: level, speciesID: "tiefling", backgroundID: "acolyte",
                classEntries: [ClassEntry(classID: "fighter", level: level)],
                abilityScores: [.charisma: 14], maxHP: 10
            )
            if let legacy { c.featureSelections["tiefling_legacy"] = [legacy] }
            return c
        }
        func grants(_ c: Character) -> [String] {
            CharacterSpellGrants.resolve(character: c, content: store).map(\.spell.id)
        }

        // Level 1 Infernal Tiefling: Fire Bolt (legacy cantrip) + Thaumaturgy
        // (Otherworldly Presence, flat) — but NOT the level 3 / 5 spells yet.
        let l1 = grants(infernalTiefling(level: 1))
        #expect(l1.contains("fire_bolt"))
        #expect(l1.contains("thaumaturgy"))
        #expect(!l1.contains("hellish_rebuke"))
        #expect(!l1.contains("darkness"))

        // The leveled grants unlock at their minCharacterLevel.
        #expect(grants(infernalTiefling(level: 3)).contains("hellish_rebuke"))
        #expect(!grants(infernalTiefling(level: 3)).contains("darkness"))
        #expect(grants(infernalTiefling(level: 5)).contains("darkness"))

        // No legacy chosen: choice-gated grants vanish, flat Thaumaturgy stays.
        let none = grants(infernalTiefling(level: 5, legacy: nil))
        #expect(!none.contains("fire_bolt"))
        #expect(none.contains("thaumaturgy"))

        // A different legacy grants its own cantrip, not the Infernal one.
        var abyssal = infernalTiefling(level: 1, legacy: "abyssal")
        abyssal.featureSelections["tiefling_legacy"] = ["abyssal"]
        #expect(grants(abyssal).contains("poison_spray"))
        #expect(!grants(abyssal).contains("fire_bolt"))

        // Non-species-granting character gets nothing.
        let human = Character(
            name: "H", level: 5, speciesID: "human", backgroundID: "acolyte",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [:], maxHP: 10
        )
        #expect(CharacterSpellGrants.resolve(character: human, content: store).isEmpty)
    }

    @MainActor
    @Test func innateSpellAbilityAndFreeCastPools() {
        let store = ContentStore()
        func tiefling(level: Int, scores: [Ability: Int]) -> Character {
            var c = Character(
                name: "Z", level: level, speciesID: "tiefling", backgroundID: "acolyte",
                classEntries: [ClassEntry(classID: "fighter", level: level)],
                abilityScores: scores, maxHP: 10
            )
            c.featureSelections["tiefling_legacy"] = ["infernal"]
            return c
        }

        // Hole 1: innate casting ability = highest of INT/WIS/CHA.
        let chaPC = tiefling(level: 5, scores: [.intelligence: 10, .wisdom: 12, .charisma: 16])
        #expect(CharacterSpellGrants.innateSpellcastingAbility(character: chaPC) == .charisma)
        let intPC = tiefling(level: 5, scores: [.intelligence: 15, .wisdom: 12, .charisma: 8])
        #expect(CharacterSpellGrants.innateSpellcastingAbility(character: intPC) == .intelligence)
        // And it resolves a real spell-attack roll for a non-caster.
        let attack = ActionInterpreter.resolve(
            recipe: .spellAttack(label: "Fire Bolt Attack"),
            character: chaPC, weapon: nil,
            spellcastingAbility: CharacterSpellGrants.innateSpellcastingAbility(character: chaPC)
        )
        #expect(attack.formula != nil)

        // Hole 2: leveled grants get a 1/Long-Rest free-cast pool; cantrips don't.
        #expect(CharacterSpellGrants.hasFreeCast(spellID: "hellish_rebuke", character: chaPC, content: store))
        #expect(!CharacterSpellGrants.hasFreeCast(spellID: "fire_bolt", character: chaPC, content: store))
        let pools = ResourceCalculator.availableResources(character: chaPC, content: store)
        #expect(pools.first { $0.definition.id == "grant_hellish_rebuke" }?.max == 1)
        #expect(pools.contains { $0.definition.id == "grant_darkness" })   // L5 grant
        #expect(!pools.contains { $0.definition.id == "grant_fire_bolt" }) // cantrip → no pool

        // Pool (and free cast) only once the leveled grant is unlocked.
        let l1 = tiefling(level: 1, scores: [.charisma: 16])
        #expect(!CharacterSpellGrants.hasFreeCast(spellID: "hellish_rebuke", character: l1, content: store))
        #expect(!ResourceCalculator.availableResources(character: l1, content: store)
            .contains { $0.definition.id == "grant_hellish_rebuke" })
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
