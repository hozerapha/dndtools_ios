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

    @Test func saveBonusWithExpertiseDoublesProficiency() {
        let character = Character(
            name: "Test",
            level: 5,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.strength: 16],
            maxHP: 40,
            proficiencies: [.savingThrow(.strength): .expertise]
        )
        // +3 STR + 6 expertise (prof bonus 3 × 2)
        #expect(CharacterCalculator.saveBonus(character: character, ability: .strength) == 9)
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

    // MARK: - Attunement

    @Test func attunementLimitDefaultsToThree() {
        let store = ContentStore()
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16],
            maxHP: 10
        )
        #expect(CharacterCalculator.attunementLimit(character: character, content: store) == 3)
    }

    @Test func attunementLimitHonorsCharacterOverride() {
        let store = ContentStore()
        let character = Character(
            name: "Test",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16],
            maxHP: 10,
            attunementSlotsOverride: 6
        )
        #expect(CharacterCalculator.attunementLimit(character: character, content: store) == 6)
    }

    @Test func featureDefinitionDecodesAttunementSlots() throws {
        // Verifies the JSON key the calculator relies on. Class-feature data
        // loaded from `classes.json` flows through this same decoder, so a
        // feature like Artificer's Magic Item Adept can simply add
        // `"attunementSlots": 4` and the limit will pick it up at runtime.
        let json = """
        {
            "id": "magic_item_adept",
            "name": "Magic Item Adept",
            "description": "...",
            "actionRecipes": [],
            "attunementSlots": 4
        }
        """.data(using: .utf8)!
        let feature = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(feature.attunementSlots == 4)
    }

    @Test func featureDefinitionAttunementSlotsAbsentDecodesAsNil() throws {
        let json = """
        { "id": "f", "name": "F", "description": "", "actionRecipes": [] }
        """.data(using: .utf8)!
        let feature = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(feature.attunementSlots == nil)
    }

    // MARK: - Attunement restrictions

    @MainActor
    @Test func attunementRestrictionsClassMismatch() {
        let store = ContentStore()
        let character = Character(
            name: "Test", level: 5,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.strength: 16], maxHP: 40
        )
        let restrictions = AttunementRestrictions(classes: ["wizard", "sorcerer"])
        let reason = restrictions.firstUnmetReason(for: character, content: store)
        #expect(reason == "Requires class: Wizard, Sorcerer")
    }

    @MainActor
    @Test func attunementRestrictionsClassMatchPasses() {
        let store = ContentStore()
        let character = Character(
            name: "Test", level: 5,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 5)],
            abilityScores: [.intelligence: 16], maxHP: 30
        )
        let restrictions = AttunementRestrictions(classes: ["wizard"])
        #expect(restrictions.firstUnmetReason(for: character, content: store) == nil)
    }

    @MainActor
    @Test func attunementRestrictionsBelowMinLevel() {
        let store = ContentStore()
        let character = Character(
            name: "Test", level: 3,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.strength: 16], maxHP: 24
        )
        let restrictions = AttunementRestrictions(minLevel: 5)
        #expect(restrictions.firstUnmetReason(for: character, content: store) == "Requires level 5+")
    }

    @MainActor
    @Test func attunementRestrictionsAbilityScoreShortfall() {
        let store = ContentStore()
        let character = Character(
            name: "Test", level: 1,
            speciesID: "halfling", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "rogue", level: 1)],
            abilityScores: [.strength: 10, .dexterity: 16], maxHP: 8
        )
        // Belt of Giant Strength style requirement.
        let restrictions = AttunementRestrictions(abilityScoreMinimums: [.strength: 13])
        #expect(restrictions.firstUnmetReason(for: character, content: store) == "Requires STR 13+")
    }

    @MainActor
    @Test func attunementRestrictionsCombineAsAndPriority() {
        // Multiple unmet restrictions: report the first failure in the
        // calculator's documented order — minLevel, classes, species, ability.
        let store = ContentStore()
        let character = Character(
            name: "Test", level: 2,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 2)],
            abilityScores: [.strength: 8], maxHP: 16
        )
        let restrictions = AttunementRestrictions(
            classes: ["wizard"],
            minLevel: 5,
            abilityScoreMinimums: [.strength: 13]
        )
        #expect(restrictions.firstUnmetReason(for: character, content: store) == "Requires level 5+")
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

    // MARK: - Weapon Mastery

    @MainActor
    @Test func weaponMasterySlotCountForFighter() {
        let store = ContentStore()
        let fighter = Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16], maxHP: 10
        )
        #expect(CharacterCalculator.weaponMasterySlotCount(character: fighter, content: store) == 3)
    }

    @MainActor
    @Test func weaponMasterySlotCountForWizardIsZero() {
        let store = ContentStore()
        let wizard = Character(
            name: "Mordenkainen", level: 1,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 1)],
            abilityScores: [.intelligence: 16], maxHP: 6
        )
        #expect(CharacterCalculator.weaponMasterySlotCount(character: wizard, content: store) == 0)
    }

    @MainActor
    @Test func hasActiveMasteryRequiresBothFeatureAndSelection() {
        let store = ContentStore()
        let fighter = Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16], maxHP: 10,
            featureSelections: ["weapon_mastery": ["longsword"]]
        )
        #expect(CharacterCalculator.hasActiveMastery(weaponID: "longsword", character: fighter, content: store))
        // Not in the chosen list → no active mastery.
        #expect(!CharacterCalculator.hasActiveMastery(weaponID: "dagger", character: fighter, content: store))
    }

    @MainActor
    @Test func hasActiveMasteryFalseForCharacterWithoutFeature() {
        let store = ContentStore()
        let wizard = Character(
            name: "Mordenkainen", level: 1,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 1)],
            abilityScores: [.intelligence: 16], maxHP: 6,
            featureSelections: ["weapon_mastery": ["longsword"]] // populated, but no Mastery feature
        )
        #expect(!CharacterCalculator.hasActiveMastery(weaponID: "longsword", character: wizard, content: store))
    }

    // MARK: - Weapon roll breakdown

    @MainActor
    @Test func weaponBreakdownForLongswordSTR16Fighter() {
        let store = ContentStore()
        let fighter = Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16, .dexterity: 12],
            maxHP: 10,
            proficiencies: [.weapon(.martial): .proficient]
        )
        let b = CharacterCalculator.weaponRollBreakdown(
            weaponID: "longsword", character: fighter, content: store
        )
        // Attack: 1d20 + STR (+3) + Prof (+2) → +5
        #expect(b?.attack.formula == "+5")
        // Damage: 1d8 + STR (+3)
        #expect(b?.damage.formula == "1d8+3")
        // Versatile (2H): 1d10 + 3
        #expect(b?.versatile?.formula == "1d10+3")
        #expect(b?.damageType == "Slashing")
    }

    @MainActor
    @Test func weaponBreakdownReturnsNilForNonWeapon() {
        let store = ContentStore()
        let character = Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16], maxHP: 10
        )
        #expect(CharacterCalculator.weaponRollBreakdown(
            weaponID: "backpack", character: character, content: store
        ) == nil)
    }
}
