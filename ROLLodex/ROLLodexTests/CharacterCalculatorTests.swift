import Testing
import Foundation
@testable import ROLLodex

struct CharacterCalculatorTests {

    @Test func abilityModifiers() {
        #expect(CharacterCalculator.abilityModifier(score: 1) == -5)
        // Odd scores below 10 are the floor-vs-truncate trap: 9 is −1, not 0.
        #expect(CharacterCalculator.abilityModifier(score: 3) == -4)
        #expect(CharacterCalculator.abilityModifier(score: 7) == -2)
        #expect(CharacterCalculator.abilityModifier(score: 9) == -1)
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

    @Test func classSkillSelectionGrantsProficiencyLive() {
        // Proficiency comes from a class skill-choice selection (not the
        // stored proficiencies dict), resolved live by marker.
        let character = Character(
            name: "Test", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "rogue", level: 1)],
            abilityScores: [.dexterity: 16],
            maxHP: 8,
            featureSelections: ["rogue_class_skills": ["stealth", "perception"]]
        )
        #expect(CharacterCalculator.skillProficiencyLevel(character: character, skill: .stealth) == .proficient)
        #expect(CharacterCalculator.skillModifier(character: character, skill: .stealth) == 5) // +3 DEX + 2 PB
        // A skill not picked stays unproficient.
        #expect(CharacterCalculator.skillProficiencyLevel(character: character, skill: .acrobatics) == .none)
    }

    @Test func jackOfAllTradesAddsHalfPBToNonProficientSkillsOnly() {
        // Level 5 → PB 4, half-PB = 2. DEX 14 → +2.
        let character = Character(
            name: "Bard", level: 5, speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "bard", level: 5)],
            abilityScores: [.dexterity: 14, .strength: 10], maxHP: 30,
            proficiencies: [.skill(.acrobatics): .proficient]
        )
        // Not proficient in Stealth (DEX): +2 ability + 2 half-PB = +4.
        #expect(CharacterCalculator.skillModifier(character: character, skill: .stealth, jackOfAllTrades: true) == 4)
        // Without the flag, just the ability mod.
        #expect(CharacterCalculator.skillModifier(character: character, skill: .stealth, jackOfAllTrades: false) == 2)
        // Proficient skill does NOT get the half-PB stacked: +2 + 4 PB = +6.
        #expect(CharacterCalculator.skillModifier(character: character, skill: .acrobatics, jackOfAllTrades: true) == 6)
        // The ½ indicator shows only on non-proficient skills.
        #expect(CharacterCalculator.appliesJackOfAllTrades(character: character, skill: .stealth, hasFeature: true))
        #expect(!CharacterCalculator.appliesJackOfAllTrades(character: character, skill: .acrobatics, hasFeature: true))
        #expect(!CharacterCalculator.appliesJackOfAllTrades(character: character, skill: .stealth, hasFeature: false))
    }

    @MainActor
    @Test func bardHasJackOfAllTradesFromLevel2() {
        let store = ContentStore()
        func bard(_ level: Int) -> Character {
            Character(name: "B", level: level, speciesID: "human", backgroundID: "sage",
                      classEntries: [ClassEntry(classID: "bard", level: level)],
                      abilityScores: [:], maxHP: 20)
        }
        #expect(!CharacterCalculator.hasJackOfAllTrades(character: bard(1), content: store))
        #expect(CharacterCalculator.hasJackOfAllTrades(character: bard(2), content: store))
        // A Fighter never has it.
        let fighter = Character(name: "F", level: 5, speciesID: "human", backgroundID: "soldier",
                                classEntries: [ClassEntry(classID: "fighter", level: 5)],
                                abilityScores: [:], maxHP: 40)
        #expect(!CharacterCalculator.hasJackOfAllTrades(character: fighter, content: store))
    }

    @Test func expertiseUpgradesAClassSkillGrant() {
        // Class skill grants proficiency; an expertise selection upgrades it
        // even though it's never in the stored proficiencies dict.
        let character = Character(
            name: "Test", level: 5,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "rogue", level: 5)],
            abilityScores: [.dexterity: 16],
            maxHP: 30,
            featureSelections: [
                "rogue_class_skills": ["stealth"],
                "expertise": ["stealth"]
            ]
        )
        #expect(CharacterCalculator.skillProficiencyLevel(character: character, skill: .stealth) == .expertise)
        #expect(CharacterCalculator.skillModifier(character: character, skill: .stealth) == 9) // +3 + 6
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

    // MARK: - Unarmored Defense

    @MainActor
    @Test func unarmoredDefenseResolvesAbilityAndComputesAC() {
        let store = ContentStore()
        // Barbarian: Unarmored Defense (CON). DEX 14 (+2), CON 16 (+3) → AC 15.
        let barb = Character(
            name: "B", level: 1, speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "barbarian", level: 1)],
            abilityScores: [.dexterity: 14, .constitution: 16], maxHP: 14
        )
        #expect(CharacterCalculator.unarmoredDefenseAbility(character: barb, content: store) == .constitution)
        #expect(CharacterCalculator.armorClass(
            dexMod: 2, armor: nil, hasShield: false, unarmoredDefenseBonus: 3
        ) == 15)

        // Draconic Sorcerer: Unarmored Defense (CHA), once the subclass is set.
        let sorc = Character(
            name: "S", level: 3, speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "sorcerer", level: 3)],
            abilityScores: [.dexterity: 14, .charisma: 16], maxHP: 18,
            featureSelections: ["sorcerer_subclass": ["draconic_sorcery"]]
        )
        #expect(CharacterCalculator.unarmoredDefenseAbility(character: sorc, content: store) == .charisma)
        // Without the subclass chosen, no Unarmored Defense.
        var sorcNoSub = sorc; sorcNoSub.featureSelections = [:]
        #expect(CharacterCalculator.unarmoredDefenseAbility(character: sorcNoSub, content: store) == nil)

        // A plain Fighter has no Unarmored Defense.
        let fighter = Character(
            name: "F", level: 1, speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.dexterity: 14], maxHP: 10
        )
        #expect(CharacterCalculator.unarmoredDefenseAbility(character: fighter, content: store) == nil)
    }

    // MARK: - Feature HP bonuses

    @MainActor
    @Test func featureHitPointBonusScalesByLevelAndSource() {
        let store = ContentStore()
        // Dwarven Toughness: +1 per character level.
        func dwarf(_ level: Int) -> Character {
            Character(name: "D", level: level, speciesID: "dwarf", backgroundID: "soldier",
                      classEntries: [ClassEntry(classID: "fighter", level: level)],
                      abilityScores: [:], maxHP: 10)
        }
        #expect(CharacterCalculator.featureHitPointBonus(character: dwarf(1), content: store) == 1)
        #expect(CharacterCalculator.featureHitPointBonus(character: dwarf(5), content: store) == 5)

        // Draconic Resilience: +1 per sorcerer level, only once chosen (L3+).
        func draconic(_ level: Int, sub: Bool) -> Character {
            Character(name: "S", level: level, speciesID: "human", backgroundID: "sage",
                      classEntries: [ClassEntry(classID: "sorcerer", level: level)],
                      abilityScores: [:], maxHP: 6 * level,
                      featureSelections: sub ? ["sorcerer_subclass": ["draconic_sorcery"]] : [:])
        }
        #expect(CharacterCalculator.featureHitPointBonus(character: draconic(2, sub: true), content: store) == 0) // not yet (L3 feature)
        #expect(CharacterCalculator.featureHitPointBonus(character: draconic(3, sub: true), content: store) == 3) // +3 catch-up at L3
        #expect(CharacterCalculator.featureHitPointBonus(character: draconic(5, sub: true), content: store) == 5)
        #expect(CharacterCalculator.featureHitPointBonus(character: draconic(5, sub: false), content: store) == 0) // no subclass

        // Dwarf Draconic Sorcerer at L5: both stack → +10.
        let both = Character(
            name: "DS", level: 5, speciesID: "dwarf", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "sorcerer", level: 5)],
            abilityScores: [:], maxHP: 30,
            featureSelections: ["sorcerer_subclass": ["draconic_sorcery"]]
        )
        #expect(CharacterCalculator.featureHitPointBonus(character: both, content: store) == 10)
    }

    // MARK: - Condition enforcement on rolls

    @MainActor
    @Test func conditionsImposeAdvantageDisadvantageByContext() {
        let store = ContentStore()
        func pc(_ conditions: [String]) -> Character {
            Character(name: "C", level: 5, speciesID: "human", backgroundID: "soldier",
                      classEntries: [ClassEntry(classID: "fighter", level: 5)],
                      abilityScores: [.dexterity: 14], maxHP: 40,
                      conditions: conditions.map { CharacterCondition(id: $0) })
        }
        func mode(_ conds: [String], _ ctx: CharacterCalculator.ConditionRollContext) -> (Bool, Bool) {
            CharacterCalculator.conditionRollMode(character: pc(conds), content: store, context: ctx)
        }

        // Poisoned → attack disadvantage + all ability checks disadvantage.
        #expect(mode(["poisoned"], .attack) == (false, true))
        #expect(mode(["poisoned"], .abilityCheck(.strength)) == (false, true))
        // Invisible → attack advantage.
        #expect(mode(["invisible"], .attack) == (true, false))
        // Restrained → DEX saves disadvantage, but not other saves.
        #expect(mode(["restrained"], .savingThrow(.dexterity)) == (false, true))
        #expect(mode(["restrained"], .savingThrow(.wisdom)) == (false, false))
        // Frightened → attack disadvantage; no condition gives check advantage.
        #expect(mode(["frightened"], .attack) == (false, true))
        // No conditions → nothing.
        #expect(mode([], .attack) == (false, false))
    }

    @Test func combineRollModeCancelsAdvantageAndDisadvantage() {
        // 5e: any advantage + any disadvantage → normal.
        #expect(CharacterCalculator.combineRollMode(.normal, advantage: true, disadvantage: true) == .normal)
        #expect(CharacterCalculator.combineRollMode(.advantage, advantage: false, disadvantage: true) == .normal)
        #expect(CharacterCalculator.combineRollMode(.normal, advantage: true, disadvantage: false) == .advantage)
        #expect(CharacterCalculator.combineRollMode(.normal, advantage: false, disadvantage: true) == .disadvantage)
        // User advantage + condition advantage stays advantage (no double).
        #expect(CharacterCalculator.combineRollMode(.advantage, advantage: true, disadvantage: false) == .advantage)
        #expect(CharacterCalculator.combineRollMode(.normal, advantage: false, disadvantage: false) == .normal)
    }

    @MainActor
    @Test func conditionAdjustedModeMapsRecipesAndCancels() {
        let store = ContentStore()
        let poisoned = Character(
            name: "P", level: 5, speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [:], maxHP: 40, conditions: [CharacterCondition(id: "poisoned")]
        )
        // Skill check (maps to its ability) → disadvantage from Poisoned.
        #expect(CharacterCalculator.conditionAdjustedMode(
            for: .skillCheck(skill: .perception), userMode: .normal, character: poisoned, content: store) == .disadvantage)
        // User picks advantage on a Poisoned attack → cancels to normal.
        #expect(CharacterCalculator.conditionAdjustedMode(
            for: .weaponAttack(abilityOverride: nil, finesse: false), userMode: .advantage,
            character: poisoned, content: store) == .normal)
        // Damage rolls are untouched by conditions.
        #expect(CharacterCalculator.conditionAdjustedMode(
            for: .weaponDamage(dieOverride: nil, addAbility: true, versatile: false), userMode: .advantage,
            character: poisoned, content: store) == .advantage)
    }
}
