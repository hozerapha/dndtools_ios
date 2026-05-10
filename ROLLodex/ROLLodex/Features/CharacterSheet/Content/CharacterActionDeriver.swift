import Foundation

/// One actionable (or info-only) row on the character sheet. Wraps a
/// `ResolvedAction` plus optional UI extras (weapon mastery badge, resource
/// counter) and an `isExhausted` flag the tile reads to grey itself out.
struct ActionRow: Identifiable, Equatable {
    let action: ResolvedAction
    let badge: String?
    let isExhausted: Bool

    init(action: ResolvedAction, badge: String?, isExhausted: Bool = false) {
        self.action = action
        self.badge = badge
        self.isExhausted = isExhausted
    }

    var id: String { action.id }
}

/// A grouped section of action rows (Attacks, Features). Ability/skill/save
/// rolls are surfaced inline in their respective cards, not in the action grid.
struct ActionSection: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    var rows: [ActionRow]
}

/// Pure derivation of the action button list for a character, given the
/// content store. Called from `CharacterSheetView`. Output is consumed by
/// `ActionButtonGrid`. MainActor-isolated to match the @Observable
/// `ContentStore` it reads from.
@MainActor
enum CharacterActionDeriver {
    static func sections(
        for character: Character,
        content: ContentStore
    ) -> [ActionSection] {
        var sections: [ActionSection] = []

        let attacks = attackRows(for: character, content: content)
        if !attacks.isEmpty {
            sections.append(ActionSection(id: "attacks", title: "Attacks", systemImage: "burst", rows: attacks))
        }

        // Ability checks, saving throws, and skill checks live inline on the
        // ability cards / skills card with their own adv/dis menus, so they're
        // not duplicated here.

        let features = featureRows(for: character, content: content)
        if !features.isEmpty {
            sections.append(ActionSection(
                id: "features",
                title: "Features",
                systemImage: "sparkles",
                rows: features
            ))
        }

        return sections
    }

    // MARK: - Attacks

    private static func attackRows(
        for character: Character,
        content: ContentStore
    ) -> [ActionRow] {
        var rows: [ActionRow] = []
        for inv in character.inventory where inv.equipped {
            guard let weapon = content.weaponDefinition(id: inv.itemID) else { continue }
            let badge = weapon.masteryProperty.map { $0.rawValue.capitalized }
            // Trust the weapon's recipes when present; fall back to a sensible
            // attack+damage(+versatile) trio for homebrew that omits them.
            let recipes: [ActionRecipe]
            if weapon.actionRecipes.isEmpty {
                var fallback: [ActionRecipe] = [
                    .weaponAttack(abilityOverride: nil, finesse: weapon.properties.contains(.finesse)),
                    .weaponDamage(dieOverride: nil, addAbility: true, versatile: false)
                ]
                if weapon.versatileDamage != nil {
                    fallback.append(.weaponDamage(dieOverride: nil, addAbility: true, versatile: true))
                }
                recipes = fallback
            } else {
                recipes = weapon.actionRecipes
            }

            for (index, recipe) in recipes.enumerated() {
                let resolved = ActionInterpreter.resolve(
                    recipe: recipe,
                    character: character,
                    weapon: weapon
                )
                // The interpreter labels both versatile and non-versatile damage
                // rows identically ("Longsword Damage"); disambiguate the
                // two-handed variant in the button list.
                let row: ResolvedAction
                if case .weaponDamage(_, _, true) = recipe {
                    row = ResolvedAction(
                        id: "\(resolved.id)_v\(index)",
                        label: "\(weapon.name) Damage (2H)",
                        formula: resolved.formula,
                        description: resolved.description
                    )
                } else {
                    row = resolved
                }
                rows.append(ActionRow(action: row, badge: badge))
            }
        }
        return rows
    }

    // MARK: - Features

    private static func featureRows(
        for character: Character,
        content: ContentStore
    ) -> [ActionRow] {
        var rows: [ActionRow] = []

        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            for level in 1...max(entry.level, 1) {
                for feature in cls.levelFeatures[level] ?? [] {
                    let cost = feature.resource.map { ResourceCost(resourceID: $0.id, amount: 1) }
                    let resolvedResource = feature.resource.flatMap { def in
                        ResourceCalculator.availableResources(character: character, content: content)
                            .first { $0.definition.id == def.id }
                    }
                    let badge = resolvedResource.map { "\($0.current) / \($0.max)" }
                    let isExhausted = resolvedResource?.isExhausted ?? false

                    if feature.actionRecipes.isEmpty, cost != nil {
                        // Resource-only feature (e.g. Action Surge): no roll, but
                        // tapping the button still consumes a charge.
                        let action = ResolvedAction(
                            id: "feature_\(feature.id)_consume",
                            label: feature.name,
                            formula: nil,
                            description: nil,
                            resourceCost: cost
                        )
                        rows.append(ActionRow(action: action, badge: badge, isExhausted: isExhausted))
                        continue
                    }

                    for recipe in feature.actionRecipes {
                        let resolved = ActionInterpreter.resolve(
                            recipe: recipe,
                            character: character,
                            weapon: nil
                        )
                        // Prefer the feature name as the label so the button reads
                        // "Second Wind" rather than the interpreter's generic title.
                        let labeled = ResolvedAction(
                            id: "feature_\(feature.id)_\(resolved.id)",
                            label: featureButtonLabel(feature: feature, resolved: resolved),
                            formula: resolved.formula,
                            description: resolved.description,
                            resourceCost: cost
                        )
                        rows.append(ActionRow(action: labeled, badge: badge, isExhausted: isExhausted))
                    }
                }
            }
        }

        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits {
                for recipe in trait.actionRecipes {
                    let resolved = ActionInterpreter.resolve(
                        recipe: recipe,
                        character: character,
                        weapon: nil
                    )
                    let labeled = ResolvedAction(
                        id: "trait_\(trait.id)_\(resolved.id)",
                        label: trait.name,
                        formula: resolved.formula,
                        description: resolved.description
                    )
                    rows.append(ActionRow(action: labeled, badge: nil))
                }
            }
        }

        return rows
    }

    private static func featureButtonLabel(
        feature: FeatureDefinition,
        resolved: ResolvedAction
    ) -> String {
        // For heal recipes the resolved.label is already the user-facing label
        // ("Second Wind"); for everything else, prepend the feature name so the
        // button conveys its source.
        if resolved.label == feature.name { return feature.name }
        return "\(feature.name): \(resolved.label)"
    }

}
