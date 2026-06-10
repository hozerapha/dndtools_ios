import Foundation

/// How the player generates ability scores during creation.
enum AbilityScoreMethod: String, CaseIterable, Identifiable {
    /// 27-point buy, scores 8–15. The default.
    case pointBuy
    /// Assign 15 / 14 / 13 / 12 / 10 / 8, each exactly once.
    case standardArray
    /// Roll six values (4d6kh3 by default, any parseable house formula)
    /// in the Quick Roll mini tray, then assign them like the array.
    case rolled

    var id: Self { self }

    var label: String {
        switch self {
        case .pointBuy:      return "Point Buy"
        case .standardArray: return "Array"
        case .rolled:        return "Roll"
        }
    }
}

struct CharacterDraft {
    var name: String = ""
    var speciesID: String = ""
    var backgroundID: String = ""
    var classID: String = ""
    /// All six abilities seeded to 8 so the point-buy step's row bindings
    /// have a backing entry from the start. Without this, the UI showed an 8
    /// via the binding's `default:` arg but never wrote it to the dict, so
    /// `isValidPointBuy` failed on `count == 6` until the player nudged
    /// every stepper. In the array/rolled methods a MISSING key means
    /// "unassigned" — `setAbilityMethod` swaps between the two shapes.
    var abilityScores: [Ability: Int] = Dictionary(
        uniqueKeysWithValues: Ability.allCases.map { ($0, 8) }
    )
    var abilityMethod: AbilityScoreMethod = .pointBuy
    /// Pool of six rolled totals (`.rolled` method), in roll order. May hold
    /// duplicates — assignment matching is multiset-aware.
    var rolledScores: [Int] = []
    /// Editable house formula for `.rolled`; each of the six rolls uses it.
    var rollFormula: String = "4d6kh3"

    static let standardArray = [15, 14, 13, 12, 10, 8]

    // MARK: - Validation

    var isComplete: Bool {
        !name.isEmpty
            && !speciesID.isEmpty
            && !backgroundID.isEmpty
            && !classID.isEmpty
            && isAbilityAssignmentValid
    }

    /// Method-aware ability validation: point buy keeps its 27-point rule;
    /// the assignment methods require all six abilities set and the assigned
    /// values to exactly match the pool (as a multiset, so duplicate rolls
    /// are honored).
    var isAbilityAssignmentValid: Bool {
        switch abilityMethod {
        case .pointBuy:
            return isValidPointBuy
        case .standardArray:
            return assignedValuesMatch(Self.standardArray)
        case .rolled:
            return rolledScores.count == 6 && assignedValuesMatch(rolledScores)
        }
    }

    private func assignedValuesMatch(_ pool: [Int]) -> Bool {
        let assigned = Ability.allCases.compactMap { abilityScores[$0] }
        return assigned.count == 6 && assigned.sorted() == pool.sorted()
    }

    // MARK: - Method switching & assignment helpers

    /// Switch generation method, resetting scores to the shape the method
    /// expects (point buy: all 8s; array/rolled: everything unassigned).
    /// A rolled pool survives switching away and back.
    mutating func setAbilityMethod(_ method: AbilityScoreMethod) {
        guard method != abilityMethod else { return }
        abilityMethod = method
        switch method {
        case .pointBuy:
            abilityScores = Dictionary(
                uniqueKeysWithValues: Ability.allCases.map { ($0, 8) }
            )
        case .standardArray, .rolled:
            abilityScores = [:]
        }
    }

    /// Replace the rolled pool (a fresh set of six rolls) and clear any
    /// assignments made from the previous pool.
    mutating func setRolledScores(_ scores: [Int]) {
        rolledScores = scores
        abilityScores = [:]
    }

    /// Replace ONE rolled value (table rules like "reroll anything under 6").
    /// Assignments that no longer fit the updated pool are cleared —
    /// multiset-aware, so with two rolled 12s and one rerolled away, only
    /// one assigned 12 is freed.
    mutating func replaceRolledScore(at index: Int, with newValue: Int) {
        guard rolledScores.indices.contains(index) else { return }
        rolledScores[index] = newValue
        var remaining = rolledScores
        for ability in Ability.allCases {
            guard let value = abilityScores[ability] else { continue }
            if let i = remaining.firstIndex(of: value) {
                remaining.remove(at: i)
            } else {
                abilityScores[ability] = nil
            }
        }
    }

    /// Pool values not yet assigned to an ability, multiset-aware (two
    /// rolled 12s means 12 stays available after one is used). Pass the
    /// ability whose row is asking so its own current value stays offered.
    func availableValues(excluding ability: Ability? = nil) -> [Int] {
        let pool: [Int]
        switch abilityMethod {
        case .pointBuy:      return []
        case .standardArray: pool = Self.standardArray
        case .rolled:        pool = rolledScores
        }
        var remaining = pool
        for a in Ability.allCases where a != ability {
            if let assigned = abilityScores[a],
               let i = remaining.firstIndex(of: assigned) {
                remaining.remove(at: i)
            }
        }
        return remaining
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
