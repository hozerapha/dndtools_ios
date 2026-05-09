import Foundation

struct CharacterDraft {
    var name: String = ""
    var speciesID: String = ""
    var backgroundID: String = ""
    var classID: String = ""
    var abilityScores: [Ability: Int] = [:]

    // MARK: - Validation

    var isComplete: Bool {
        !name.isEmpty
            && !speciesID.isEmpty
            && !backgroundID.isEmpty
            && !classID.isEmpty
            && abilityScores.count == 6
            && isValidPointBuy
    }

    var pointBuySpent: Int {
        abilityScores.values.reduce(0) { $0 + CharacterDraft.pointCost(for: $1) }
    }

    var isValidPointBuy: Bool {
        abilityScores.count == 6
            && abilityScores.values.allSatisfy { (8...15).contains($0) }
            && pointBuySpent == 27
    }

    var remainingPoints: Int {
        27 - pointBuySpent
    }

    // MARK: - Conversion

    func toCharacter() -> Character {
        let classEntry = ClassEntry(classID: classID, level: 1)

        // Apply background ASIs
        var finalScores = abilityScores
        // Will be applied by caller or content lookup; for now store base scores

        return Character(
            name: name,
            level: 1,
            speciesID: speciesID,
            backgroundID: backgroundID,
            classEntries: [classEntry],
            abilityScores: finalScores,
            maxHP: startingHP(),
            currentHP: startingHP()
        )
    }

    // MARK: - Helpers

    static func pointCost(for score: Int) -> Int {
        switch score {
        case 8: return 0
        case 9: return 1
        case 10: return 2
        case 11: return 3
        case 12: return 4
        case 13: return 5
        case 14: return 7
        case 15: return 9
        default: return 0
        }
    }

    private func startingHP() -> Int {
        // Simplified: max hit die + CON mod
        // Actual value would come from ClassDefinition lookup
        10 + CharacterCalculator.abilityModifier(score: abilityScores[.constitution] ?? 10)
    }
}
