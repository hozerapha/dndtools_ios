import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: ActionInterpreter fighting-style interactions — Great Weapon
/// Fighting reroll logic, Two-Weapon Fighting mod restoration, Dueling's
/// one-weapon gate, Archery's ammunition restriction. The basic paths are
/// covered in FightingStyleTests; these pin the boundary conditions and
/// exclusions that a plausible change could break.
@MainActor
struct FightingStyleEdgeCaseTests {

    private func makeFighter(styles: [String]) -> Character {
        Character(
            name: "Fighter",
            level: 5,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.strength: 14, .dexterity: 16],  // Swap: DEX higher for finesse
            maxHP: 40,
            proficiencies: [
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ],
            featureSelections: ["fighting_style": styles]
        )
    }

    private func longsword() -> WeaponDefinition {
        WeaponDefinition(
            id: "longsword",
            name: "Longsword",
            description: "",
            cost: 1500,
            weight: 3,
            weaponCategory: .martial,
            damage: "1d8",
            damageType: .slashing,
            damageAbility: nil,
            properties: [.versatile],
            versatileDamage: "1d10"
        )
    }

    private func greatsword() -> WeaponDefinition {
        WeaponDefinition(
            id: "greatsword",
            name: "Greatsword",
            description: "",
            cost: 5000,
            weight: 6,
            weaponCategory: .martial,
            damage: "2d6",
            damageType: .slashing,
            damageAbility: nil,
            properties: [.twoHanded, .heavy]
        )
    }

    private func dagger() -> WeaponDefinition {
        WeaponDefinition(
            id: "dagger",
            name: "Dagger",
            description: "",
            cost: 200,
            weight: 1,
            weaponCategory: .simple,
            damage: "1d4",
            damageType: .piercing,
            damageAbility: nil,
            properties: [.finesse, .light, .thrown]
        )
    }

    private func shortbow() -> WeaponDefinition {
        WeaponDefinition(
            id: "shortbow",
            name: "Shortbow",
            description: "",
            cost: 2500,
            weight: 2,
            weaponCategory: .simple,
            damage: "1d6",
            damageType: .piercing,
            damageAbility: .dexterity,
            properties: [.ammunition, .twoHanded]
        )
    }

    // MARK: - Great Weapon Fighting

    @Test func greatWeaponFightingAppliesRerollToTwoHandedWeapon() {
        let char = makeFighter(styles: ["great_weapon_fighting"])
        let weapon = greatsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // Greatsword 2d6 with GWF → each die should have rerollOnceIfAtMost(2)
        #expect(resolved.formula?.groups.count == 1)
        #expect(resolved.formula?.groups[0].modifier == .rerollOnceIfAtMost(2))
    }

    @Test func greatWeaponFightingAppliesRerollToVersatileTwoHandedSwing() {
        let char = makeFighter(styles: ["great_weapon_fighting"])
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        // versatile: true means wielding two-handed → GWF applies
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: true)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.groups[0].modifier == .rerollOnceIfAtMost(2))
    }

    @Test func greatWeaponFightingDoesNotApplyToOneHandedSwing() {
        let char = makeFighter(styles: ["great_weapon_fighting"])
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        // versatile: false means wielding one-handed → GWF doesn't apply
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.groups[0].modifier == nil)
    }

    @Test func greatWeaponFightingDoesNotApplyToRangedWeapon() {
        let char = makeFighter(styles: ["great_weapon_fighting"])
        let weapon = shortbow()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // Shortbow has ammunition property → not melee → no GWF
        #expect(resolved.formula?.groups[0].modifier == nil)
    }

    @Test func greatWeaponFightingPreservesExistingModifier() {
        // GWF only stamps reroll onto PLAIN groups — a group with an existing
        // modifier (from a homebrew weapon or feature) is left alone.
        let char = makeFighter(styles: ["great_weapon_fighting"])
        // Create a weapon with a modified die string
        let weapon = WeaponDefinition(
            id: "greatsword",
            name: "Greatsword",
            description: "",
            cost: 5000,
            weight: 6,
            weaponCategory: .martial,
            damage: "2d6kh1",  // Homebrew die with keep modifier
            damageType: .slashing,
            damageAbility: nil,
            properties: [.twoHanded, .heavy]
        )
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // Parser will yield keepHighest(1); GWF doesn't clobber it
        #expect(resolved.formula?.groups[0].modifier == .keepHighest(1))
    }
    @Test func twoWeaponFightingRestoresModOnLightMeleeWeapon() {
        let char = makeFighter(styles: ["two_weapon_fighting"])
        let weapon = dagger()  // Light, melee
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        // addAbility: false simulates an off-hand attack that normally omits the mod
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: false, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // DEX 16 → +3; TWF should restore it
        #expect(resolved.formula?.modifier == 3)
    }

    @Test func twoWeaponFightingDoesNotRestoreWhenAddAbilityTrue() {
        let char = makeFighter(styles: ["two_weapon_fighting"])
        let weapon = dagger()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        // addAbility: true means the mod was already included → TWF is a no-op
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 3)  // DEX mod once, not doubled
    }

    @Test func twoWeaponFightingDoesNotRestoreOnRangedWeapon() {
        let char = makeFighter(styles: ["two_weapon_fighting"])
        let weapon = shortbow()  // Not melee → TWF doesn't apply
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: false, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 0)  // No mod without TWF
    }

    @Test func twoWeaponFightingDoesNotRestoreOnNonLightWeapon() {
        let char = makeFighter(styles: ["two_weapon_fighting"])
        let weapon = longsword()  // Not light → TWF doesn't apply
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: false, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 0)  // No mod without TWF
    }


    @Test func duelingAppliesBonusWhenOnlyOneWeaponEquipped() {
        var char = makeFighter(styles: ["dueling"])
        char.inventory = [InventoryItem(itemID: "longsword", quantity: 1, equipped: true)]
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // STR 14 → +2, +2 Dueling = 4
        #expect(resolved.formula?.modifier == 4)
    }

    @Test func duelingDoesNotApplyWhenTwoWeaponsEquipped() {
        var char = makeFighter(styles: ["dueling"])
        char.inventory = [
            InventoryItem(itemID: "longsword", quantity: 1, equipped: true),
            InventoryItem(itemID: "dagger", quantity: 1, equipped: true)
        ]
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 2)  // STR only, no Dueling
    }

    @Test func duelingDoesNotApplyToTwoHandedWeapon() {
        var char = makeFighter(styles: ["dueling"])
        char.inventory = [InventoryItem(itemID: "greatsword", quantity: 1, equipped: true)]
        let weapon = greatsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 2)  // STR only, no Dueling
    }


    @Test func duelingDoesNotApplyToVersatileTwoHandedSwing() {
        var char = makeFighter(styles: ["dueling"])
        char.inventory = [InventoryItem(itemID: "longsword", quantity: 1, equipped: true)]
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        // versatile: true means wielding two-handed → Dueling doesn't apply
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: true)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 2)  // STR only, no Dueling
    }

    @Test func duelingDoesNotApplyToRangedWeapon() {
        var char = makeFighter(styles: ["dueling"])
        char.inventory = [InventoryItem(itemID: "shortbow", quantity: 1, equipped: true)]
        let weapon = shortbow()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        #expect(resolved.formula?.modifier == 3)  // DEX 16 → +3, no Dueling
    }

    // MARK: - Archery

    @Test func archeryAppliesBonusToAmmunitionWeapon() {
        let char = makeFighter(styles: ["archery"])
        let weapon = shortbow()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // DEX 16 → +3, Prof 3, Archery +2 = +8
        #expect(resolved.formula?.modifier == 8)
    }

    @Test func archeryDoesNotApplyToMeleeWeapon() {
        let char = makeFighter(styles: ["archery"])
        let weapon = longsword()
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: false)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // STR 14 → +2, Prof 3 = +5 (no Archery)
        #expect(resolved.formula?.modifier == 5)
    }

    @Test func archeryDoesNotApplyToThrownWeapon() {
        let char = makeFighter(styles: ["archery"])
        let weapon = dagger()  // Thrown but not ammunition → no Archery
        let fs = CharacterCalculator.fightingStyleEffects(character: char, content: ContentStore())

        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: true)
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: char, weapon: weapon, fightingStyle: fs)

        // Finesse picks DEX 16 → +3, Prof 3 = +6 (no Archery)
        #expect(resolved.formula?.modifier == 6)
    }
}
