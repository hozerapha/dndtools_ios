import Foundation

/// JSON-driven flag that an item requires attunement, with optional
/// restrictions on who can attune to it. The presence of the `attunement`
/// key on an item *is* the requirement — even an empty `{}` means "needs
/// attunement, no restrictions". Absence (nil) means the item is freely usable.
struct AttunementRule: Codable, Equatable {
    let restrictions: AttunementRestrictions?

    init(restrictions: AttunementRestrictions? = nil) {
        self.restrictions = restrictions
    }
}

/// Optional per-restriction filter on attunement eligibility. Multiple fields
/// are AND-combined; values within a list field are OR-combined (the character
/// needs at least one matching class, species, etc.). Absent fields mean
/// "no constraint on this dimension".
struct AttunementRestrictions: Codable, Equatable {
    /// Class IDs (any-of). Matches if the character has at least one of these
    /// in their `classEntries`.
    let classes: [String]?
    /// Minimum overall character level.
    let minLevel: Int?
    /// Species IDs (any-of).
    let species: [String]?
    /// Per-ability minimums (all-of). e.g. `{"strength": 13}` for Belt of Giant Strength.
    let abilityScoreMinimums: [Ability: Int]?

    init(
        classes: [String]? = nil,
        minLevel: Int? = nil,
        species: [String]? = nil,
        abilityScoreMinimums: [Ability: Int]? = nil
    ) {
        self.classes = classes
        self.minLevel = minLevel
        self.species = species
        self.abilityScoreMinimums = abilityScoreMinimums
    }

    /// Returns the first restriction the character fails (in a stable order),
    /// formatted as a human-readable reason. Nil means all restrictions pass.
    /// `content` is consulted to display class/species names instead of raw IDs.
    @MainActor
    func firstUnmetReason(for character: Character, content: ContentStore) -> String? {
        if let minLevel, character.level < minLevel {
            return "Requires level \(minLevel)+"
        }
        if let classes, !classes.isEmpty {
            let owned = Set(character.classEntries.map(\.classID))
            if owned.isDisjoint(with: classes) {
                let names = classes.map { content.classDefinition(id: $0)?.name ?? $0.capitalized }
                return "Requires class: \(names.joined(separator: ", "))"
            }
        }
        if let species, !species.isEmpty {
            if !species.contains(character.speciesID) {
                let names = species.map { content.speciesDefinition(id: $0)?.name ?? $0.capitalized }
                return "Requires species: \(names.joined(separator: ", "))"
            }
        }
        if let abilityScoreMinimums {
            // Sort to keep the "first failure" deterministic across runs.
            for (ability, minimum) in abilityScoreMinimums.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                if (character.abilityScores[ability] ?? 10) < minimum {
                    return "Requires \(ability.abbreviation) \(minimum)+"
                }
            }
        }
        return nil
    }
}
