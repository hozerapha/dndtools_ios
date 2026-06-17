import Foundation

/// Resolves the spells a character is granted by their species traits — both
/// flat grants (Tiefling Otherworldly Presence → Thaumaturgy) and choice-gated
/// grants (the lineage / legacy the player picked). These are *always
/// prepared*: surfaced on the sheet without spending any known/prepared
/// budget, and gated by `SpellGrant.minCharacterLevel` so a lineage's 3rd- and
/// 5th-level spells appear only once the character reaches those levels.
///
/// Content-free resolution, mirroring how proficiencies / expertise resolve:
/// nothing is written onto `character.spells`; the list is derived live from
/// the species definition + the player's recorded picks.
@MainActor
enum CharacterSpellGrants {
    /// One granted spell plus the trait it came from (for the source label).
    struct GrantedSpell: Identifiable, Equatable {
        let spell: SpellDefinition
        let sourceLabel: String
        var id: String { spell.id }
    }

    static func resolve(character: Character, content: ContentStore) -> [GrantedSpell] {
        guard let species = content.speciesDefinition(id: character.speciesID) else { return [] }

        var out: [GrantedSpell] = []
        var seen = Set<String>()

        func add(_ grants: [SpellGrant], source: String) {
            for grant in grants where grant.minCharacterLevel <= character.level {
                guard !seen.contains(grant.spellID),
                      let spell = content.spellDefinition(id: grant.spellID) else { continue }
                seen.insert(grant.spellID)
                out.append(GrantedSpell(spell: spell, sourceLabel: source))
            }
        }

        for trait in species.traits {
            // Flat grants (no choice).
            add(trait.grantsSpells, source: trait.name)
            // Choice-gated grants: only the option the player picked contributes.
            if let selection = trait.selection,
               case .fixedOptions(let options) = selection.optionsSource {
                let picked = Set(character.featureSelections[selection.id] ?? [])
                for option in options where picked.contains(option.id) {
                    add(option.grantsSpells, source: trait.name)
                }
            }
        }

        return out.sorted { lhs, rhs in
            if lhs.spell.level != rhs.spell.level { return lhs.spell.level < rhs.spell.level }
            return lhs.spell.name < rhs.spell.name
        }
    }

    /// The ability used to cast species-granted spells. The SRD lets the player
    /// choose Intelligence, Wisdom, or Charisma per lineage; until that pick has
    /// its own UI we default to the character's highest of the three (ties
    /// favor INT, then WIS). Only used as a fallback when the character has no
    /// class spellcasting ability of its own.
    static func innateSpellcastingAbility(character: Character) -> Ability {
        let order: [Ability] = [.intelligence, .wisdom, .charisma]
        var best = order[0]
        for ability in order.dropFirst()
        where (character.abilityScores[ability] ?? 10) > (character.abilityScores[best] ?? 10) {
            best = ability
        }
        return best
    }

    /// Stable resource id for a leveled grant's once-per-Long-Rest free cast.
    static func freeCastResourceID(spellID: String) -> String { "grant_\(spellID)" }

    /// True when `spellID` is currently granted to the character as a *leveled*
    /// spell — i.e. it has a once-per-Long-Rest free cast (cantrips are at-will
    /// and need no pool).
    static func hasFreeCast(spellID: String, character: Character, content: ContentStore) -> Bool {
        resolve(character: character, content: content)
            .contains { $0.spell.id == spellID && !$0.spell.isCantrip }
    }
}
