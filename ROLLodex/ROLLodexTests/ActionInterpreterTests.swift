import Testing
@testable import ROLLodex

struct ActionInterpreterTests {

    private func makeSampleCharacter() -> Character {
        Character(
            name: "Bruenor",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [
                .strength: 16,
                .dexterity: 12,
                .constitution: 14,
                .intelligence: 10,
                .wisdom: 13,
                .charisma: 8
            ],
            maxHP: 12,
            proficiencies: [
                .savingThrow(.strength): .proficient,
                .savingThrow(.constitution): .proficient,
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ]
        )
    }

    private func makeLongsword() -> WeaponDefinition {
        WeaponDefinition(
            id: "longsword",
            name: "Longsword",
            description: "",
            cost: 1500,
            weight: 3,
            weaponCategory: .martial,
            damage: "1d8",
            damageType: .slashing,
            damageAbility: .strength,
            properties: [.versatile],
            versatileDamage: "1d10",
            range: nil,
            masteryProperty: .sap,
            actionRecipes: []
        )
    }

    private func makeRapier() -> WeaponDefinition {
        WeaponDefinition(
            id: "rapier",
            name: "Rapier",
            description: "",
            cost: 2500,
            weight: 2,
            weaponCategory: .martial,
            damage: "1d8",
            damageType: .piercing,
            damageAbility: .dexterity,
            properties: [.finesse],
            versatileDamage: nil,
            range: nil,
            masteryProperty: .vex,
            actionRecipes: []
        )
    }

    // MARK: - Weapon Attack

    @Test func weaponAttackWithStrength() {
        let character = makeSampleCharacter()
        let weapon = makeLongsword()
        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: false)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        #expect(action.label == "Longsword Attack +5")
        #expect(action.formula?.modifier == 5)
        #expect(action.formula?.groups.count == 1)
        #expect(action.formula?.groups.first?.kind == .d20)
    }

    @Test func weaponAttackWithFinessePrefersDex() {
        let character = makeSampleCharacter()
        let weapon = makeRapier()
        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: true)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        // DEX 12 (+1) vs STR 16 (+3) — STR is higher, so STR is used
        #expect(action.label == "Rapier Attack +5")
        #expect(action.formula?.modifier == 5)
    }

    @Test func weaponAttackWithFinessePrefersDexWhenHigher() {
        var character = makeSampleCharacter()
        character.abilityScores[.dexterity] = 18
        let weapon = makeRapier()
        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: true)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        // DEX 18 (+4) vs STR 16 (+3) — DEX is higher
        #expect(action.label == "Rapier Attack +6")
        #expect(action.formula?.modifier == 6)
    }

    @Test func weaponAttackWithoutProficiency() {
        let character = makeSampleCharacter()
        let weapon = makeLongsword()
        let recipe = ActionRecipe.weaponAttack(abilityOverride: nil, finesse: false)

        var unproficient = character
        unproficient.proficiencies.removeValue(forKey: .weapon(.martial))

        let action = ActionInterpreter.resolve(recipe: recipe, character: unproficient, weapon: weapon)
        #expect(action.label == "Longsword Attack +3")
        #expect(action.formula?.modifier == 3)
    }

    // MARK: - Weapon Damage

    @Test func weaponDamageOneHanded() {
        let character = makeSampleCharacter()
        let weapon = makeLongsword()
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        #expect(action.label == "Longsword Damage")
        #expect(action.formula?.modifier == 3)
        #expect(action.formula?.groups.first?.kind == .d8)
    }

    @Test func weaponDamageVersatile() {
        let character = makeSampleCharacter()
        let weapon = makeLongsword()
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: true)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        #expect(action.formula?.groups.first?.kind == .d10)
        #expect(action.formula?.modifier == 3)
    }

    @Test func weaponDamageWithoutAbility() {
        let character = makeSampleCharacter()
        let weapon = makeLongsword()
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: false, versatile: false)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        #expect(action.formula?.modifier == 0)
        #expect(action.formula?.groups.first?.kind == .d8)
    }

    @Test func weaponDamageFinesseUsesDex() {
        var character = makeSampleCharacter()
        character.abilityScores[.dexterity] = 18
        let weapon = makeRapier()
        let recipe = ActionRecipe.weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: weapon)

        #expect(action.formula?.modifier == 4)
    }

    // MARK: - Ability / Skill / Save

    @Test func abilityCheck() {
        let character = makeSampleCharacter()
        let recipe = ActionRecipe.abilityCheck(ability: .strength)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)

        #expect(action.label == "Strength Check +3")
        #expect(action.formula?.modifier == 3)
    }

    @Test func skillCheck() {
        let character = makeSampleCharacter()
        let recipe = ActionRecipe.skillCheck(skill: .athletics)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)

        #expect(action.label == "Athletics +5")
        #expect(action.formula?.modifier == 5)
    }

    @Test func savingThrow() {
        let character = makeSampleCharacter()
        let recipe = ActionRecipe.savingThrow(ability: .constitution)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)

        #expect(action.label == "Constitution Save +4")
        #expect(action.formula?.modifier == 4)
    }

    @Test func saveDC() {
        let character = makeSampleCharacter()
        let recipe = ActionRecipe.saveDC(ability: .intelligence)
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)

        #expect(action.label == "Intelligence Save DC 10")
        #expect(action.formula == nil)
    }

    @Test func healAction() {
        let character = makeSampleCharacter()
        let recipe = ActionRecipe.heal(dice: "1d10", addLevel: true, label: "Second Wind")
        let action = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)

        #expect(action.label == "Second Wind")
        #expect(action.formula?.groups.first?.kind == .d10)
        #expect(action.formula?.modifier == 1)
    }

    /// Dragonborn Breath Weapon: the die COUNT grows with character level
    /// (1d10 → 2d10 → 3d10 → 4d10) via the scaledDamage recipe.
    @Test func scaledDamageGrowsWithCharacterLevel() {
        let count = LevelScaledValue.byCharacterLevel([1: 1, 5: 2, 11: 3, 17: 4])
        func group(atLevel level: Int) -> DiceGroup? {
            let character = Character(
                name: "Drogon", level: level,
                speciesID: "dragonborn", backgroundID: "soldier",
                classEntries: [ClassEntry(classID: "fighter", level: level)],
                abilityScores: [.constitution: 14], maxHP: 10
            )
            let recipe = ActionRecipe.scaledDamage(
                dieKind: 10, count: count, damageType: nil, label: "Breath Weapon"
            )
            return ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)
                .formula?.groups.first
        }
        #expect(group(atLevel: 1)?.count == 1)
        #expect(group(atLevel: 4)?.count == 1)
        #expect(group(atLevel: 5)?.count == 2)
        #expect(group(atLevel: 11)?.count == 3)
        #expect(group(atLevel: 17)?.count == 4)
        #expect(group(atLevel: 20)?.count == 4)
        #expect(group(atLevel: 5)?.kind == .d10)

        // Codable round-trip preserves the scaling table.
        let recipe = ActionRecipe.scaledDamage(dieKind: 10, count: count, damageType: .fire, label: "X")
        let data = try! JSONEncoder().encode(recipe)
        let decoded = try! JSONDecoder().decode(ActionRecipe.self, from: data)
        #expect(decoded == recipe)
    }
}
