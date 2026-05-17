import Foundation

struct CharacterDraft {
    var name: String = ""
    var speciesID: String = ""
    var backgroundID: String = ""
    var classID: String = ""
    /// All six abilities seeded to 8 so the ability-step's row bindings have
    /// a backing entry from the start. Without this, the UI showed an 8 via
    /// the binding's `default:` arg but never wrote it to the dict, so
    /// `isValidPointBuy` failed on `count == 6` until the player nudged
    /// every stepper.
    var abilityScores: [Ability: Int] = Dictionary(
        uniqueKeysWithValues: Ability.allCases.map { ($0, 8) }
    )

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
            rolledHP: hitDieMax(),
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

    /// The raw hit-die maximum for the chosen class (without CON mod).
    /// Simplified: hard-coded to 10 (d10) until we wire up ClassDefinition.
    private func hitDieMax() -> Int {
        10
    }

    private func startingHP() -> Int {
        hitDieMax() + CharacterCalculator.abilityModifier(score: abilityScores[.constitution] ?? 10)
    }
}
