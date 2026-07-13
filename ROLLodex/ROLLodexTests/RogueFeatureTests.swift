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
        // Per SRD: expertise doubles Proficiency Bonus, but you must be
        // proficient in the skill first. Without base proficiency, the
        // expertise selection is a no-op and the modifier is just the ability
        // mod. The picker enforces this at pick time; the calculator enforces
        // it here as a defense-in-depth.
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
        // +3 DEX only — no proficiency, so no PB, no doubled PB from expertise.
        #expect(mod == 3)
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

    // End-to-end against bundled content: the floor is now feature-derived
    // (Rogue L7 `reliable_talent` carries `skillCheckMinimum`), computed by
    // `CharacterCalculator.skillCheckFloor` and applied by the interpreter.

    @Test @MainActor func reliableTalentFloorsProficientSkillForRogue7() {
        let content = ContentStore()
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let floor = CharacterCalculator.skillCheckFloor(character: character, content: content)
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character, weapon: nil,
            skillCheckFloor: floor
        )
        #expect(resolved.formula?.groups.first?.minimumValue == 10)
    }

    @Test @MainActor func reliableTalentSkippedForNonProficientSkill() {
        let content = ContentStore()
        let character = Character(
            name: "Lazlo", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.strength: 10],
            maxHP: 10,
            proficiencies: [:]
        )
        let floor = CharacterCalculator.skillCheckFloor(character: character, content: content)
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .athletics),
            character: character, weapon: nil,
            skillCheckFloor: floor
        )
        #expect(resolved.formula?.groups.first?.minimumValue == nil)
    }

    @Test @MainActor func reliableTalentSkippedBelowRogue7() {
        let content = ContentStore()
        let character = Character(
            name: "Lazlo", level: 6,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 6)],
            abilityScores: [.dexterity: 16],
            maxHP: 10,
            proficiencies: [.skill(.stealth): .proficient]
        )
        let floor = CharacterCalculator.skillCheckFloor(character: character, content: content)
        #expect(floor == nil)
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .stealth),
            character: character, weapon: nil,
            skillCheckFloor: floor
        )
        #expect(resolved.formula?.groups.first?.minimumValue == nil)
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

    // MARK: - Granted actions (feature-conferred turn options)

    @Test func grantedActionDecodesWithAndWithoutRecipe() throws {
        let json = """
        [
          { "name": "Dash", "cost": "bonusAction", "description": "Move again." },
          { "name": "Hide", "cost": "bonusAction", "recipe": { "type": "skillCheck", "skill": "stealth" } }
        ]
        """.data(using: .utf8)!
        let actions = try JSONDecoder().decode([GrantedAction].self, from: json)
        #expect(actions.count == 2)
        #expect(actions[0].recipe == nil)
        #expect(actions[0].description == "Move again.")
        #expect(actions[1].recipe == .skillCheck(skill: .stealth))
    }

    @Test func cunningActionSurfacesAsGrantedBonusOptionsNotAStealthButton() {
        let store = ContentStore()
        let rogue = Character(
            name: "Lazlo", level: 5,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 5)],
            abilityScores: [.dexterity: 16],
            maxHP: 28
        )
        let granted = CharacterActionDeriver.grantedActions(for: rogue, content: store)
        let names = Set(granted.map(\.action.name))
        #expect(names.isSuperset(of: ["Dash", "Disengage", "Hide", "Uncanny Dodge"]))

        // Hide rolls Stealth as a Bonus Action; Dash is informational.
        let hide = granted.first { $0.action.name == "Hide" }
        #expect(hide?.cost == .bonusAction)
        #expect(hide?.action.recipe == .skillCheck(skill: .stealth))
        #expect(granted.first { $0.action.name == "Dash" }?.action.recipe == nil)
        // Uncanny Dodge is a Reaction.
        #expect(granted.first { $0.action.name == "Uncanny Dodge" }?.cost == .reaction)

        // Cunning Action no longer mis-renders as a "Stealth" button in the grid.
        let featureLabels = CharacterActionDeriver.sections(for: rogue, content: store)
            .first { $0.id == "features" }?.rows.map(\.action.label) ?? []
        #expect(!featureLabels.contains { $0.contains("Cunning Action") })
    }
}
