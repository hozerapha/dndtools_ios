import Testing
import Foundation
@testable import ROLLodex

/// Ability score generation methods (roadmap item 15): point buy (default),
/// standard array, and rolled pools — method switching, multiset-aware
/// assignment, and per-method validation on `CharacterDraft`.
struct AbilityScoreMethodTests {

    // MARK: - Defaults & switching

    @Test func draftDefaultsToPointBuyWithSeededEights() {
        let draft = CharacterDraft()
        #expect(draft.abilityMethod == .pointBuy)
        #expect(draft.abilityScores.count == 6)
        #expect(draft.abilityScores.values.allSatisfy { $0 == 8 })
        #expect(draft.rollFormula == "4d6kh3")
    }

    @Test func switchingToArrayClearsAssignments() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.standardArray)
        #expect(draft.abilityScores.isEmpty)
        #expect(!draft.isAbilityAssignmentValid)
    }

    @Test func switchingBackToPointBuyReseedsEights() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.standardArray)
        draft.abilityScores[.strength] = 15
        draft.setAbilityMethod(.pointBuy)
        #expect(draft.abilityScores.count == 6)
        #expect(draft.abilityScores.values.allSatisfy { $0 == 8 })
    }

    @Test func rolledPoolSurvivesMethodRoundTrip() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([15, 12, 12, 10, 9, 8])
        draft.setAbilityMethod(.standardArray)
        draft.setAbilityMethod(.rolled)
        #expect(draft.rolledScores == [15, 12, 12, 10, 9, 8])
        // Assignments don't survive — the pool does.
        #expect(draft.abilityScores.isEmpty)
    }

    // MARK: - Point buy (unchanged behavior)

    @Test func pointBuyStillValidatesTwentySevenPoints() {
        var draft = CharacterDraft()
        // 15/15/15/8/8/8 spends exactly 9+9+9 = 27.
        draft.abilityScores = [
            .strength: 15, .dexterity: 15, .constitution: 15,
            .intelligence: 8, .wisdom: 8, .charisma: 8
        ]
        #expect(draft.isValidPointBuy)
        #expect(draft.isAbilityAssignmentValid)

        draft.abilityScores[.strength] = 14 // 27 → 25 spent
        #expect(!draft.isAbilityAssignmentValid)
    }

    // MARK: - Standard array

    @Test func standardArrayValidWhenEachValueUsedOnce() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.standardArray)
        draft.abilityScores = [
            .strength: 15, .dexterity: 14, .constitution: 13,
            .intelligence: 12, .wisdom: 10, .charisma: 8
        ]
        #expect(draft.isAbilityAssignmentValid)
    }

    @Test func standardArrayRejectsDuplicatesAndGaps() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.standardArray)
        // 15 used twice, 14 never.
        draft.abilityScores = [
            .strength: 15, .dexterity: 15, .constitution: 13,
            .intelligence: 12, .wisdom: 10, .charisma: 8
        ]
        #expect(!draft.isAbilityAssignmentValid)

        // One ability left unassigned.
        draft.abilityScores = [
            .strength: 15, .dexterity: 14, .constitution: 13,
            .intelligence: 12, .wisdom: 10
        ]
        #expect(!draft.isAbilityAssignmentValid)
    }

    // MARK: - Rolled

    @Test func rolledRequiresASixValuePool() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([15, 12, 10, 9, 8]) // only five
        draft.abilityScores = [
            .strength: 15, .dexterity: 12, .constitution: 10,
            .intelligence: 9, .wisdom: 8, .charisma: 8
        ]
        #expect(!draft.isAbilityAssignmentValid)
    }

    @Test func rolledHonorsDuplicateValuesInThePool() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])
        draft.abilityScores = [
            .strength: 12, .dexterity: 12, .constitution: 14,
            .intelligence: 10, .wisdom: 9, .charisma: 8
        ]
        #expect(draft.isAbilityAssignmentValid)
    }

    @Test func rolledRejectsValuesOutsidePool() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])
        draft.abilityScores = [
            .strength: 18, .dexterity: 12, .constitution: 14,
            .intelligence: 10, .wisdom: 9, .charisma: 8
        ]
        #expect(!draft.isAbilityAssignmentValid)
    }

    @Test func replacingOneRolledScoreFreesOnlyTheOrphanedAssignment() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])
        draft.abilityScores = [.strength: 12, .dexterity: 12, .constitution: 14]

        // Reroll one of the two 12s into a 6: exactly one 12-assignment is
        // freed, the other 12 and the 14 stay put.
        draft.replaceRolledScore(at: 0, with: 6)
        #expect(draft.rolledScores == [6, 12, 14, 10, 9, 8])
        let assignedTwelves = draft.abilityScores.values.filter { $0 == 12 }.count
        #expect(assignedTwelves == 1)
        #expect(draft.abilityScores[.constitution] == 14)
    }

    @Test func replacingAnUnassignedScoreLeavesAssignmentsAlone() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])
        draft.abilityScores = [.strength: 14, .dexterity: 10]

        draft.replaceRolledScore(at: 5, with: 17) // the unassigned 8
        #expect(draft.abilityScores[.strength] == 14)
        #expect(draft.abilityScores[.dexterity] == 10)
        #expect(draft.rolledScores.contains(17))
    }

    @Test func rerollClearsAssignments() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])
        draft.abilityScores[.strength] = 14
        draft.setRolledScores([])
        #expect(draft.rolledScores.isEmpty)
        #expect(draft.abilityScores.isEmpty)
    }

    // MARK: - Available values (assignment menus)

    @Test func availableValuesAreMultisetAware() {
        var draft = CharacterDraft()
        draft.setAbilityMethod(.rolled)
        draft.setRolledScores([12, 12, 14, 10, 9, 8])

        draft.abilityScores[.strength] = 12
        // One 12 spent, the second remains offered.
        #expect(draft.availableValues().sorted() == [8, 9, 10, 12, 14])

        // The assigning ability's own value stays available to itself so the
        // menu can re-offer (and effectively keep) the current pick.
        #expect(draft.availableValues(excluding: .strength).sorted() == [8, 9, 10, 12, 12, 14])
    }

    @Test func availableValuesEmptyForPointBuy() {
        let draft = CharacterDraft()
        #expect(draft.availableValues().isEmpty)
    }

    // MARK: - isComplete integration

    @Test func isCompleteBranchesOnMethod() {
        var draft = CharacterDraft()
        draft.name = "Vex"
        draft.speciesID = "human"
        draft.backgroundID = "soldier"
        draft.classID = "fighter"
        // Default point-buy all-8s spends 0 of 27 points.
        #expect(!draft.isComplete)

        draft.setAbilityMethod(.standardArray)
        draft.abilityScores = [
            .strength: 15, .dexterity: 14, .constitution: 13,
            .intelligence: 12, .wisdom: 10, .charisma: 8
        ]
        #expect(draft.isComplete)
    }

    // MARK: - Background ability bonus distribution (2024)

    private let soldierOptions: [Ability] = [.strength, .dexterity, .constitution]

    @Test func backgroundBonusFocusedSpreadIsValid() {
        var draft = CharacterDraft()
        draft.backgroundAbilityBonuses = [.strength: 2, .constitution: 1]
        #expect(draft.isValidBackgroundBonus(options: soldierOptions))
    }

    @Test func backgroundBonusBalancedSpreadIsValid() {
        var draft = CharacterDraft()
        draft.backgroundAbilityBonuses = [.strength: 1, .dexterity: 1, .constitution: 1]
        #expect(draft.isValidBackgroundBonus(options: soldierOptions))
    }

    @Test func emptyBonusIsInvalid() {
        let draft = CharacterDraft()
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
    }

    @Test func bonusOutsideOptionsIsInvalid() {
        var draft = CharacterDraft()
        // Intelligence isn't one of the Soldier's three options.
        draft.backgroundAbilityBonuses = [.strength: 2, .intelligence: 1]
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
    }

    // MARK: - Class skill choice

    private let rogueOptions: [Skill] = [
        .acrobatics, .athletics, .deception, .insight, .intimidation,
        .investigation, .perception, .persuasion, .sleightOfHand, .stealth
    ]

    @Test func classSkillChoiceValidWithExactDistinctPicks() {
        var draft = CharacterDraft()
        draft.classSkillChoices = [.acrobatics, .deception, .perception, .stealth]
        #expect(draft.isValidClassSkillChoice(count: 4, options: rogueOptions))
    }

    @Test func classSkillChoiceRejectsWrongCountDuplicatesAndOutsiders() {
        var draft = CharacterDraft()
        // Too few.
        draft.classSkillChoices = [.acrobatics, .deception, .perception]
        #expect(!draft.isValidClassSkillChoice(count: 4, options: rogueOptions))
        // Duplicate (4 entries, 3 distinct).
        draft.classSkillChoices = [.acrobatics, .acrobatics, .perception, .stealth]
        #expect(!draft.isValidClassSkillChoice(count: 4, options: rogueOptions))
        // A skill not on the list (Arcana isn't a rogue option).
        draft.classSkillChoices = [.acrobatics, .deception, .perception, .arcana]
        #expect(!draft.isValidClassSkillChoice(count: 4, options: rogueOptions))
    }

    @Test func emptyClassSkillChoiceIsTriviallyValid() {
        let draft = CharacterDraft()
        #expect(draft.isValidClassSkillChoice(count: 0, options: []))
    }

    @Test func incompleteOrIllegalSpreadsAreInvalid() {
        var draft = CharacterDraft()
        // Only the +2 chosen.
        draft.backgroundAbilityBonuses = [.strength: 2]
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
        // Two +2s.
        draft.backgroundAbilityBonuses = [.strength: 2, .dexterity: 2]
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
        // Only two +1s (not all three).
        draft.backgroundAbilityBonuses = [.strength: 1, .dexterity: 1]
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
        // A +3 somewhere.
        draft.backgroundAbilityBonuses = [.strength: 3]
        #expect(!draft.isValidBackgroundBonus(options: soldierOptions))
    }
}
