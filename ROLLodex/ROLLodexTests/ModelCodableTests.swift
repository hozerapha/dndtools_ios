import Testing
import Foundation
@testable import ROLLodex

struct ModelCodableTests {

    @Test func abilityRoundTrip() throws {
        for ability in Ability.allCases {
            let data = try JSONEncoder().encode(ability)
            let decoded = try JSONDecoder().decode(Ability.self, from: data)
            #expect(decoded == ability)
        }
    }

    @Test func skillRoundTrip() throws {
        for skill in Skill.allCases {
            let data = try JSONEncoder().encode(skill)
            let decoded = try JSONDecoder().decode(Skill.self, from: data)
            #expect(decoded == skill)
        }
    }

    @Test func proficiencyKeyRoundTrip() throws {
        let keys: [ProficiencyKey] = [
            .savingThrow(.strength),
            .skill(.athletics),
            .armor(.heavy),
            .weapon(.martial),
            .tool("thieves_tools")
        ]
        for key in keys {
            let data = try JSONEncoder().encode(key)
            let decoded = try JSONDecoder().decode(ProficiencyKey.self, from: data)
            #expect(decoded == key)
        }
    }

    @Test func proficiencyLevelRoundTrip() throws {
        let levels: [ProficiencyLevel] = [.none, .proficient, .expertise]
        for level in levels {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(ProficiencyLevel.self, from: data)
            #expect(decoded == level)
        }
    }

    @Test func characterRoundTrip() throws {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16, .dexterity: 12, .constitution: 14],
            maxHP: 12,
            proficiencies: [
                .savingThrow(.strength): .proficient,
                .skill(.athletics): .proficient
            ]
        )
        let data = try JSONEncoder().encode(character)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded == character)
    }

    @Test func actionRecipeRoundTrip() throws {
        let recipes: [ActionRecipe] = [
            .weaponAttack(abilityOverride: nil, finesse: false),
            .weaponAttack(abilityOverride: .dexterity, finesse: true),
            .weaponDamage(dieOverride: "1d8", addAbility: true, versatile: false),
            .abilityCheck(ability: .strength),
            .skillCheck(skill: .athletics),
            .savingThrow(ability: .constitution),
            .saveDC(ability: .intelligence),
            .heal(dice: "1d10", addLevel: true, label: "Second Wind")
        ]
        for recipe in recipes {
            let data = try JSONEncoder().encode(recipe)
            let decoded = try JSONDecoder().decode(ActionRecipe.self, from: data)
            #expect(decoded == recipe)
        }
    }

    @Test func weaponDefinitionRoundTrip() throws {
        let weapon = WeaponDefinition(
            id: "longsword",
            name: "Longsword",
            description: "A versatile blade.",
            cost: 1500,
            weight: 3.0,
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
        let data = try JSONEncoder().encode(weapon)
        let decoded = try JSONDecoder().decode(WeaponDefinition.self, from: data)
        #expect(decoded == weapon)
    }

    @Test func armorDefinitionRoundTrip() throws {
        let armor = ArmorDefinition(
            id: "chain_mail",
            name: "Chain Mail",
            description: "Heavy armor.",
            cost: 7500,
            weight: 55.0,
            armorCategory: .heavy,
            acBase: 16,
            dexCap: nil,
            stealthDisadvantage: true,
            strengthRequirement: 13
        )
        let data = try JSONEncoder().encode(armor)
        let decoded = try JSONDecoder().decode(ArmorDefinition.self, from: data)
        #expect(decoded == armor)
    }

    @Test func classDefinitionRoundTrip() throws {
        let fighter = ClassDefinition(
            id: "fighter",
            name: "Fighter",
            hitDie: .d10,
            primaryAbility: .strength,
            savingThrows: [.strength, .constitution],
            armorProficiencies: [.light, .medium, .heavy, .shield],
            weaponProficiencies: [.simple, .martial],
            levelFeatures: [
                1: [
                    FeatureDefinition(
                        id: "second_wind",
                        name: "Second Wind",
                        description: "Regain HP.",
                        actionRecipes: [.heal(dice: "1d10", addLevel: true, label: "Second Wind")]
                    )
                ]
            ],
            masteryCount: 3,
            masteryRestrictions: []
        )
        let data = try JSONEncoder().encode(fighter)
        let decoded = try JSONDecoder().decode(ClassDefinition.self, from: data)
        #expect(decoded == fighter)
    }
}
