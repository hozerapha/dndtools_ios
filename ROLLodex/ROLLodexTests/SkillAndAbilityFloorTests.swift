import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: ActionInterpreter integration with `skillCheckFloor` and
/// `abilityCheckFloor` — Reliable Talent and Indomitable Might. The calculator
/// methods are tested in isolation; these pin the interpreter's application of
/// the floors to resolved formulas, proficiency gates, and precedence rules.
struct SkillAndAbilityFloorTests {

    private func makeRogue(level: Int, dex: Int = 16) -> Character {
        Character(
            name: "Rogue",
            level: level,
            speciesID: "human",
            backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: level)],
            abilityScores: [.dexterity: dex],
            maxHP: 8 * level,
            proficiencies: [.skill(.stealth): .proficient]
        )
    }

    private func makeBarbarian(level: Int, str: Int = 18) -> Character {
        Character(
            name: "Barbarian",
            level: level,
            speciesID: "human",
            backgroundID: "outlander",
            classEntries: [ClassEntry(classID: "barbarian", level: level)],
            abilityScores: [.strength: str],
            maxHP: 12 * level,
            proficiencies: [.skill(.athletics): .proficient]
        )
    }

    // MARK: - Skill check floor (Reliable Talent)

    @Test func skillCheckFloorAppliesOnlyToProficientSkills() {
        let rogue = makeRogue(level: 7, dex: 16)  // Reliable Talent at L7

        // Stealth is proficient → floor applies
        let stealthRecipe = ActionRecipe.skillCheck(skill: .stealth)
        let stealthResolved = ActionInterpreter.resolve(
            recipe: stealthRecipe,
            character: rogue,
            weapon: nil,
            skillCheckFloor: 10
        )
        #expect(stealthResolved.formula?.groups[0].minimumValue == 10)

        // Acrobatics is NOT proficient → floor is ignored
        let acrobaticsRecipe = ActionRecipe.skillCheck(skill: .acrobatics)
        let acrobaticsResolved = ActionInterpreter.resolve(
            recipe: acrobaticsRecipe,
            character: rogue,
            weapon: nil,
            skillCheckFloor: 10
        )
        #expect(acrobaticsResolved.formula?.groups[0].minimumValue == nil)
    }

    @Test func skillCheckFloorPresentInDescription() {
        let rogue = makeRogue(level: 7, dex: 16)
        let recipe = ActionRecipe.skillCheck(skill: .stealth)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: rogue,
            weapon: nil,
            skillCheckFloor: 10
        )
        #expect(resolved.description?.contains("floor 10") == true)
    }

    @Test func skillCheckFloorNilWhenFeatureAbsent() {
        let rogue = makeRogue(level: 6, dex: 16)  // No Reliable Talent yet
        let recipe = ActionRecipe.skillCheck(skill: .stealth)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: rogue,
            weapon: nil,
            skillCheckFloor: nil
        )
        #expect(resolved.formula?.groups[0].minimumValue == nil)
    }

    // MARK: - Ability check floor (Indomitable Might)

    @Test func abilityCheckFloorAppliesDirectly() {
        let barb = makeBarbarian(level: 18, str: 20)  // Indomitable Might at L18
        let recipe = ActionRecipe.abilityCheck(ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: barb,
            weapon: nil,
            abilityCheckFloor: 15  // Computed as score(20) - mod(5) = 15
        )
        #expect(resolved.formula?.groups[0].minimumValue == 15)
    }

    @Test func abilityCheckFloorPresentInDescription() {
        let barb = makeBarbarian(level: 18, str: 20)
        let recipe = ActionRecipe.abilityCheck(ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: barb,
            weapon: nil,
            abilityCheckFloor: 15
        )
        #expect(resolved.description?.contains("floor 15") == true)
        #expect(resolved.description?.contains("Indomitable Might") == true)
    }

    @Test func abilityCheckFloorAppliesOnSavingThrows() {
        let barb = makeBarbarian(level: 18, str: 20)
        let recipe = ActionRecipe.savingThrow(ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: barb,
            weapon: nil,
            abilityCheckFloor: 15
        )
        #expect(resolved.formula?.groups[0].minimumValue == 15)
    }

    // MARK: - Floor precedence: Reliable Talent vs Indomitable Might

    @Test func bothFloorsApplyTakeHigher() {
        // A multiclass Rogue 7 / Barbarian 18 with STR 20 on an Athletics check:
        // Reliable Talent floor 10, Indomitable Might floor 15 → take 15.
        var char = makeBarbarian(level: 18, str: 20)
        char.classEntries.append(ClassEntry(classID: "rogue", level: 7))
        char.proficiencies[.skill(.athletics)] = .proficient

        let recipe = ActionRecipe.skillCheck(skill: .athletics)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: char,
            weapon: nil,
            skillCheckFloor: 10,
            abilityCheckFloor: 15
        )
        #expect(resolved.formula?.groups[0].minimumValue == 15)
    }

    @Test func skillFloorWinsWhenHigher() {
        // Hypothetical: Reliable Talent 10, Indomitable Might computed as 8
        // (STR 16 → mod 3 → floor 16-3=13, but let's pretend it's 8 for the
        // contract). The interpreter takes max(10, 8) = 10.
        var char = makeBarbarian(level: 18, str: 14)
        char.classEntries.append(ClassEntry(classID: "rogue", level: 7))
        char.proficiencies[.skill(.athletics)] = .proficient

        let recipe = ActionRecipe.skillCheck(skill: .athletics)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: char,
            weapon: nil,
            skillCheckFloor: 10,
            abilityCheckFloor: 8
        )
        #expect(resolved.formula?.groups[0].minimumValue == 10)
    }

    // MARK: - Class-skill selection proficiency (audit #7 regression)

    @Test func skillFloorAppliesToClassSkillSelection() {
        // A Rogue whose Stealth proficiency comes from the class-skill
        // selection (stored in featureSelections, not proficiencies dict) must
        // still get the Reliable Talent floor. This is a regression catch from
        // audit #7 where the gate checked stored proficiencies only.
        var rogue = Character(
            name: "Rogue", level: 7,
            speciesID: "human", backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: 7)],
            abilityScores: [.dexterity: 16],
            maxHP: 56,
            featureSelections: ["rogue_class_skills": ["stealth"]]
        )
        // Proficiency comes from the selection, NOT from proficiencies dict
        #expect(rogue.proficiencies[.skill(.stealth)] == nil)

        let recipe = ActionRecipe.skillCheck(skill: .stealth)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: rogue,
            weapon: nil,
            skillCheckFloor: 10
        )
        #expect(resolved.formula?.groups[0].minimumValue == 10)
    }

    // MARK: - Jack of All Trades + floor

    @Test func jackOfAllTradesDoesNotTriggerFloor() {
        // A Bard with Jack of All Trades on a non-proficient skill gets the
        // half-PB bonus, but does NOT get a Reliable Talent floor (which only
        // applies to proficient skills).
        var bard = Character(
            name: "Bard", level: 7,
            speciesID: "human", backgroundID: "entertainer",
            classEntries: [ClassEntry(classID: "bard", level: 7)],
            abilityScores: [.dexterity: 14],
            maxHP: 49,
            proficiencies: [:]
        )
        // Stealth is NOT proficient
        #expect(CharacterCalculator.skillProficiencyLevel(character: bard, skill: .stealth) == .none)

        let recipe = ActionRecipe.skillCheck(skill: .stealth)
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: bard,
            weapon: nil,
            skillCheckFloor: 10,
            jackOfAllTrades: true
        )
        #expect(resolved.formula?.groups[0].minimumValue == nil)
    }
}
