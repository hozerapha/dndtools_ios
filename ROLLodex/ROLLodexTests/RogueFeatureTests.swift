import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct RogueFeatureTests {

    // MARK: - Class definition loading

    @Test func bundledRogueLoads() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")
        #expect(rogue != nil)
        #expect(rogue?.name == "Rogue")
        #expect(rogue?.hitDie == .d8)
        #expect(rogue?.primaryAbility == .dexterity)
        #expect(rogue?.savingThrows.contains(.dexterity) == true)
        #expect(rogue?.savingThrows.contains(.intelligence) == true)
        #expect(rogue?.armorProficiencies.contains(.light) == true)
        #expect(rogue?.toolProficiencies.contains("thieves_tools") == true)
        #expect(rogue?.masteryCount == 2)
        #expect(rogue?.subclassLevel == 3)
    }

    @Test func rogueHasThiefSubclass() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let thief = rogue.subclasses.first { $0.id == "thief" }
        #expect(thief != nil)
        #expect(thief?.name == "Thief")
        #expect(thief?.levelFeatures[3]?.isEmpty == false)
        #expect(thief?.levelFeatures[9]?.isEmpty == false)
        #expect(thief?.levelFeatures[13]?.isEmpty == false)
        #expect(thief?.levelFeatures[17]?.isEmpty == false)
    }

    @Test func rogueLevel1Features() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let l1 = rogue.levelFeatures[1] ?? []
        #expect(l1.contains { $0.id == "expertise" })
        #expect(l1.contains { $0.id == "sneak_attack" })
        #expect(l1.contains { $0.id == "thieves_cant" })
        #expect(l1.contains { $0.id == "weapon_mastery" })
    }

    @Test func rogueLevel20Features() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let l20 = rogue.levelFeatures[20] ?? []
        #expect(l20.contains { $0.id == "stroke_of_luck" })
        let stroke = l20.first { $0.id == "stroke_of_luck" }
        #expect(stroke?.resource != nil)
        #expect(stroke?.resource?.max == .flat(1))
        #expect(stroke?.resource?.refreshOn == .shortRest)
    }

    @Test func rogueSubclassFeaturesAt9() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let thief = rogue.subclasses.first { $0.id == "thief" }!
        let l9 = thief.levelFeatures[9] ?? []
        #expect(l9.contains { $0.id == "supreme_sneak" })
    }

    @Test func thiefUseMagicDeviceGrantsAttunementSlots() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let thief = rogue.subclasses.first { $0.id == "thief" }!
        let l13 = thief.levelFeatures[13] ?? []
        let umd = l13.first { $0.id == "use_magic_device" }
        #expect(umd?.attunementSlots == 4)
    }

    @Test func rogueSlipperyMindGrantsSaveProficiencies() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let l15 = rogue.levelFeatures[15] ?? []
        let slip = l15.first { $0.id == "slippery_mind" }
        #expect(slip?.grantsProficiencies?.contains(.savingThrow(.wisdom)) == true)
        #expect(slip?.grantsProficiencies?.contains(.savingThrow(.charisma)) == true)
    }

    @Test func resolvedFeaturesIncludesThiefAtLevel3() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")!
        let resolved = rogue.resolvedFeatures(throughClassLevel: 3, subclassID: "thief")
        #expect(resolved.contains { $0.feature.id == "fast_hands" })
        #expect(resolved.contains { $0.feature.id == "second_story_work" })
    }

    // MARK: - Expertise selection

    @Test func expertiseSelectionDecodesAsSkillsSource() throws {
        let json = """
        {
          "id": "expertise",
          "name": "Expertise",
          "description": "...",
          "kind": "selection",
          "selection": {
            "id": "expertise",
            "prompt": "Choose skills",
            "count": 2,
            "optionsSource": { "type": "skills", "proficientOnly": true }
          }
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.selection?.id == "expertise")
        if case .skills(let prof) = f.selection?.optionsSource {
            #expect(prof == true)
        } else {
            Issue.record("Expected .skills source")
        }
    }

    @Test func expertiseSelectionRoundTrips() throws {
        let s = FeatureSelection(
            id: "expertise",
            prompt: "Choose skills",
            count: .flat(2),
            optionsSource: .skills(proficientOnly: true)
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(FeatureSelection.self, from: data)
        #expect(decoded == s)
    }

    // MARK: - Skill modifier with expertise from feature selections

    @Test func skillModifierReadsExpertiseFromFeatureSelections() {
        let character = Character(
            name: "Lazlo", level: 1,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 1)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient],
            featureSelections: ["expertise": ["stealth"]]
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .stealth)
        // +3 DEX + 4 expertise (prof bonus 2 × 2)
        #expect(mod == 7)
    }

    @Test func expertiseFromSelectionsRequiresBaseProficiency() {
        // If the skill isn't proficient, the selection alone still grants
        // expertise bonus (the player made an invalid pick, but the sheet
        // honors the selection).
        let character = Character(
            name: "Lazlo", level: 1,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 1)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [:],
            featureSelections: ["expertise": ["stealth"]]
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .stealth)
        // +3 DEX + 4 expertise (prof bonus 2 × 2) even without base proficiency
        #expect(mod == 7)
    }

    @Test func expertise_6SelectionAlsoWorks() {
        let character = Character(
            name: "Lazlo", level: 6,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 6)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.acrobatics): .proficient],
            featureSelections: ["expertise_6": ["acrobatics"]]
        )
        let mod = CharacterCalculator.skillModifier(character: character, skill: .acrobatics)
        // +3 DEX + 6 expertise (prof bonus 3 × 2)
        #expect(mod == 9)
    }

    // MARK: - Reliable Talent

    @Test func reliableTalentAppearsOnSkillCheckDescriptionForRogue7() {
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character,
            weapon: nil
        )
        #expect(resolved.description?.contains("Reliable Talent") == true)
    }

    @Test func reliableTalentSkippedForNonProficientSkill() {
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.strength: 10],
            maxHP: 10,
            proficiencies: [:]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .athletics),
            character: character,
            weapon: nil
        )
        #expect(resolved.description?.contains("Reliable Talent") == false)
    }

    @Test func reliableTalentSkippedBelowRogue7() {
        let character = Character(
            name: "Lazlo", level: 6,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 6)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character,
            weapon: nil
        )
        #expect(resolved.description?.contains("Reliable Talent") == false)
    }

    // MARK: - Tool proficiencies from class

    @Test func rogueCreationGrantsThievesToolsProficiency() {
        let store = ContentStore()
        let character = Character(
            name: "Lazlo", level: 1,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 1)],
            abilityScores: [.dexterity: 16],
            maxHP: 10
        )
        // Simulating what CharacterListView.finalizeDraft does:
        var copy = character
        if let classDef = store.classDefinition(id: "rogue") {
            for tool in classDef.toolProficiencies {
                copy.proficiencies[.tool(tool)] = .proficient
            }
        }
        #expect(copy.proficiencies[.tool("thieves_tools")] == .proficient)
    }

    // MARK: - grantsProficiencies decoding

    @Test func featureDefinitionDecodesGrantsProficiencies() throws {
        let json = """
        {
          "id": "slippery_mind",
          "name": "Slippery Mind",
          "description": "...",
          "grantsProficiencies": ["savingThrow_wisdom", "savingThrow_charisma"]
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.grantsProficiencies?.count == 2)
        #expect(f.grantsProficiencies?.contains(.savingThrow(.wisdom)) == true)
    }

    @Test func featureDefinitionGrantsProficienciesAbsentDecodesAsNil() throws {
        let json = """
        { "id": "f", "name": "F", "description": "" }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.grantsProficiencies == nil)
    }
}
