import Testing
@testable import ROLLodex

struct CharacterCalculatorTests {

    @Test func abilityModifiers() {
        #expect(CharacterCalculator.abilityModifier(score: 1) == -5)
        #expect(CharacterCalculator.abilityModifier(score: 8) == -1)
        #expect(CharacterCalculator.abilityModifier(score: 10) == 0)
        #expect(CharacterCalculator.abilityModifier(score: 12) == 1)
        #expect(CharacterCalculator.abilityModifier(score: 16) == 3)
        #expect(CharacterCalculator.abilityModifier(score: 20) == 5)
        #expect(CharacterCalculator.abilityModifier(score: 30) == 10)
    }

    @Test func proficiencyBonusByLevel() {
        #expect(CharacterCalculator.proficiencyBonus(level: 1) == 2)
        #expect(CharacterCalculator.proficiencyBonus(level: 4) == 2)
        #expect(CharacterCalculator.proficiencyBonus(level: 5) == 3)
        #expect(CharacterCalculator.proficiencyBonus(level: 8) == 3)
        #expect(CharacterCalculator.proficiencyBonus(level: 9) == 4)
        #expect(CharacterCalculator.proficiencyBonus(level: 12) == 4)
        #expect(CharacterCalculator.proficiencyBonus(level: 13) == 5)
        #expect(CharacterCalculator.proficiencyBonus(level: 16) == 5)
        #expect(CharacterCalculator.proficiencyBonus(level: 17) == 6)
        #expect(CharacterCalculator.proficiencyBonus(level: 20) == 6)
    }

    @Test func skillModifierWithNoProficiency() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16],
            maxHP: 10
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .athletics)
        #expect(mod == 3)
    }

    @Test func skillModifierWithProficiency() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16],
            maxHP: 10,
            proficiencies: [.skill(.athletics): .proficient]
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .athletics)
        #expect(mod == 5) // +3 STR + 2 prof
    }

    @Test func skillModifierWithExpertise() {
        let character = Character(
            name: "Test",
            level: 5,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "rogue", level: 5)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .expertise]
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .stealth)
        #expect(mod == 7) // +3 DEX + 6 expertise (prof bonus 3 * 2)
    }

    @Test func saveBonusWithoutProficiency() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.dexterity: 12],
            maxHP: 10
        )
        let bonus = CharacterCalculator.saveBonus(character: character, ability: .dexterity)
        #expect(bonus == 1)
    }

    @Test func saveBonusWithProficiency() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16],
            maxHP: 10,
            proficiencies: [.savingThrow(.strength): .proficient]
        )
        let bonus = CharacterCalculator.saveBonus(character: character, ability: .strength)
        #expect(bonus == 5) // +3 STR + 2 prof
    }

    @Test func armorClassWithHeavyArmor() {
        let armor = ArmorDefinition(
            id: "chain_mail",
            name: "Chain Mail",
            description: "",
            cost: 7500,
            weight: 55,
            armorCategory: .heavy,
            acBase: 16,
            dexCap: 0,
            stealthDisadvantage: true,
            strengthRequirement: 13
        )
        let ac = CharacterCalculator.armorClass(dexMod: 1, armor: armor, hasShield: false)
        #expect(ac == 16) // 16 + 0 (heavy armor ignores Dex)
    }

    @Test func armorClassWithShield() {
        let armor = ArmorDefinition(
            id: "chain_mail",
            name: "Chain Mail",
            description: "",
            cost: 7500,
            weight: 55,
            armorCategory: .heavy,
            acBase: 16,
            dexCap: nil,
            stealthDisadvantage: true,
            strengthRequirement: 13
        )
        let ac = CharacterCalculator.armorClass(dexMod: 1, armor: armor, hasShield: true)
        #expect(ac == 18)
    }

    @Test func armorClassWithMediumArmorAndDexCap() {
        let armor = ArmorDefinition(
            id: "breastplate",
            name: "Breastplate",
            description: "",
            cost: 40000,
            weight: 20,
            armorCategory: .medium,
            acBase: 14,
            dexCap: 2,
            stealthDisadvantage: false,
            strengthRequirement: nil
        )
        let ac = CharacterCalculator.armorClass(dexMod: 3, armor: armor, hasShield: false)
        #expect(ac == 16) // 14 + 2 (capped)
    }

    @Test func armorClassUnarmored() {
        let ac = CharacterCalculator.armorClass(dexMod: 1, armor: nil, hasShield: false)
        #expect(ac == 11)
    }

    @Test func armorClassWithLightArmor() {
        let armor = ArmorDefinition(
            id: "leather",
            name: "Leather Armor",
            description: "",
            cost: 1000,
            weight: 10,
            armorCategory: .light,
            acBase: 11,
            dexCap: nil,
            stealthDisadvantage: false,
            strengthRequirement: nil
        )
        let ac = CharacterCalculator.armorClass(dexMod: 3, armor: armor, hasShield: false)
        #expect(ac == 14) // 11 + 3 (full Dex)
    }

    @Test func initiativeBonus() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.dexterity: 14],
            maxHP: 10
        )
        #expect(CharacterCalculator.initiativeBonus(character: character) == 2)
    }

    @Test func passivePerception() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.wisdom: 14],
            maxHP: 10,
            proficiencies: [.skill(.perception): .proficient]
        )
        #expect(CharacterCalculator.passivePerception(character: character) == 14) // 10 + 2 WIS + 2 prof
    }

    @Test func spellSaveDC() {
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 1)],
            abilityScores: [.intelligence: 16],
            maxHP: 6
        )
        #expect(CharacterCalculator.spellSaveDC(character: character, spellcastingAbility: .intelligence) == 13)
    }
}
