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

        // A feature can grant spells flatly, or gate them behind a fixed-option
        // pick (a lineage / Elemental Affinity); only the picked option counts.
        func addFeatureGrants(_ feature: FeatureDefinition, source: String) {
            add(feature.grantsSpells, source: source)
            if let selection = feature.selection,
               case .fixedOptions(let options) = selection.optionsSource {
                let picked = Set(character.featureSelections[selection.id] ?? [])
                for option in options where picked.contains(option.id) {
                    add(option.grantsSpells, source: source)
                }
            }
        }

        // Species traits (lineages, Otherworldly Presence, …).
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits { addFeatureGrants(trait, source: trait.name) }
        }

        // Class + subclass features (Draconic Spells, future subclass spell
        // lists). Walked through the same resolver as everything else, so a
        // subclass grant only appears once its level is reached.
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                addFeatureGrants(resolved.feature, source: resolved.subclassName ?? cls.name)
            }
        }

        // Background-granted Magic Initiate — the player-picked cantrips +
        // leveled spell become always-prepared grants (leveled = free-cast
        // pool synthesized via the usual SpellGrant path).
        if let bg = content.backgroundDefinition(id: character.backgroundID),
           bg.feat == "magic_initiate" {
            let key = MagicInitiateSetupSheet.Keys.spellsKey(for: MagicInitiateSetupSheet.Keys.background)
            let picked = character.featureSelections[key] ?? []
            add(picked.map { SpellGrant(spellID: $0) }, source: "\(bg.name) · Magic Initiate")
        }

        return out.sorted { lhs, rhs in
            if lhs.spell.level != rhs.spell.level { return lhs.spell.level < rhs.spell.level }
            return lhs.spell.name < rhs.spell.name
        }
    }

    /// The ability used to cast species-granted spells. The SRD lets the player
    /// choose Intelligence, Wisdom, or Charisma per lineage; if they've made
    /// that pick (a species selection whose id carries the `spell_ability`
    /// marker) we honor it, otherwise we default to the character's highest of
    /// the three (ties favor INT, then WIS). Only consulted when the character
    /// has no class spellcasting ability of its own.
    static func innateSpellcastingAbility(character: Character, content: ContentStore) -> Ability {
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits {
                guard let selection = trait.selection,
                      selection.id.contains(FeatureIDs.spellAbilityMarker),
                      let pick = character.featureSelections[selection.id]?.first,
                      let ability = Ability(rawValue: pick) else { continue }
                return ability
            }
        }
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

    /// True when `spellID` is currently granted to the character as a leveled
    /// spell AND a free-cast pool exists for it. Species grants (Tiefling
    /// Hellish Rebuke, Elven Lineage Faerie Fire) synthesize a
    /// `grant_<spellID>` pool at level-up. Class/subclass grants like the
    /// Druid Circle-of-the-Land Circle Spells do NOT — they're
    /// always-prepared but consume normal slots. This gates the "Cast free
    /// (Innate)" affordance to grants that actually have a pool.
    static func hasFreeCast(spellID: String, character: Character, content: ContentStore) -> Bool {
        guard resolve(character: character, content: content)
            .contains(where: { $0.spell.id == spellID && !$0.spell.isCantrip })
        else { return false }
        let poolID = freeCastResourceID(spellID: spellID)
        return ResourceCalculator.availableResources(character: character, content: content)
            .contains { $0.definition.id == poolID }
    }
}
