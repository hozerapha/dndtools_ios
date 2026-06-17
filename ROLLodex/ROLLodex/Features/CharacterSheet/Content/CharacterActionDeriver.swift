import Foundation

/// One actionable (or info-only) row on the character sheet. Wraps a
/// `ResolvedAction` plus optional UI extras (weapon mastery badge, resource
/// counter) and an `isExhausted` flag the tile reads to grey itself out.
///
/// When `castFromItem` is non-nil, the tap handler diverts: instead of pushing
/// the action onto the dice tab, the character sheet opens `SpellCastSheet`
/// with the item context so the user can pick an upcast level and the sheet
/// pays the charge cost.
struct ActionRow: Identifiable, Equatable {
    let action: ResolvedAction
    let badge: String?
    let isExhausted: Bool
    let castFromItem: ItemSpellCastContext?
    /// When set, the row's tap doesn't roll — it flips a toggleable
    /// `TriggeredEffect` on/off (Barbarian Rage). The handler reads this
    /// to skip the dice handoff and call `Character.toggleFeatureEffect`.
    let toggleEffect: ToggleEffectContext?
    /// Display fields for the economy list, mirroring `GrantedAction` so
    /// interactive rows render with the same shape as granted options:
    /// a clean title, a gray subtitle (the roll/cost summary), and a rules
    /// `detail` behind an info disclosure. `title` falls back to the action
    /// label (used for the dice-history handoff) when not set.
    let title: String?
    let subtitle: String?
    let detail: String?

    init(
        action: ResolvedAction,
        badge: String?,
        isExhausted: Bool = false,
        castFromItem: ItemSpellCastContext? = nil,
        toggleEffect: ToggleEffectContext? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        detail: String? = nil
    ) {
        self.action = action
        self.badge = badge
        self.isExhausted = isExhausted
        self.castFromItem = castFromItem
        self.toggleEffect = toggleEffect
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
    }

    var id: String { action.id }
    var displayTitle: String { title ?? action.label }
}

/// Routing payload for a "toggle a feature effect" row. The sheet uses this
/// to spend the resource (only when activating, not when ending), then call
/// `character.toggleFeatureEffect(...)` to add or remove the rider.
struct ToggleEffectContext: Equatable {
    let effectID: String
    let featureID: String
    /// Initial countdown for round-limited effects (Rage = 10). Nil for
    /// `.manual` toggles that only end on dismiss.
    let roundsRemaining: Int?
    /// Resource the toggle's activation spends, if any. Nil = free toggle.
    let resourceID: String?
    /// True when the toggle is currently active on the character. Drives the
    /// label flip ("End Rage" vs "Rage") and suppresses the resource spend
    /// on the deactivate tap.
    let isActive: Bool
}

/// Routing payload for an "Item: Cast X" row. The sheet uses this to open
/// `SpellCastSheet` with the item's pool driving the slot-picker UI.
struct ItemSpellCastContext: Equatable {
    /// Spell to cast.
    let spellID: String
    /// Item the use comes from (for labeling).
    let itemName: String
    /// Resource the cast consumes (charges).
    let resourceID: String
    /// Slot level the spell goes off at when the use fires at its base cost.
    let baseLevel: Int
    /// Highest level the use can upcast to. Equal to `baseLevel` when there's
    /// no upcast support.
    let maxLevel: Int
    /// Base charge cost (the `amount` from `ItemUseCost`).
    let baseCost: Int
    /// Extra charges per slot level above `baseLevel`. Zero when there's no
    /// upcast support.
    let extraCostPerLevel: Int

    /// Charge cost for a cast at `level`. Clamped to baseCost at base level.
    func cost(forLevel level: Int) -> Int {
        let extra = max(0, level - baseLevel)
        return baseCost + extra * extraCostPerLevel
    }
}

/// A grouped section of action rows (Features, Item Uses). Weapon attacks
/// have their own bespoke view, so they're not emitted here. Ability/skill/save
/// rolls are surfaced inline in their respective cards.
struct ActionSection: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    var rows: [ActionRow]
}

/// Bundle of every roll one equipped weapon can produce, plus its mastery
/// metadata. Distinct from `ActionRow` because the weapon view renders this
/// as a single row with multiple icon buttons rather than one tile per roll.
struct WeaponAttackRow: Identifiable, Equatable {
    let id: String
    let weaponName: String
    let mastery: WeaponMastery?
    /// d20 attack roll. Always present (every weapon can swing).
    let attack: ResolvedAction
    /// Standard damage roll. Always present.
    let damage: ResolvedAction
    /// Two-handed damage roll for versatile weapons (longsword, etc.). Nil
    /// when the weapon isn't versatile.
    let versatileDamage: ResolvedAction?
    /// Opt-in rider chips the character qualifies for on this attack —
    /// Sneak Attack (when the weapon has finesse/ranged), Divine Smite, etc.
    /// Already filtered by `AttackFilter` and once-per-turn flags. The sheet
    /// pushes these into `PendingRollStore.followUps` alongside the chained
    /// damage roll.
    let optInRiders: [PendingFollowUp]
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

        // Weapons have their own bespoke `WeaponAttackRow` rendering — see
        // `weaponAttacks(for:content:)`. They don't go through the grid.
        // Ability/skill/save rolls live inline on their own cards.

        let features = featureRows(for: character, content: content)
        if !features.isEmpty {
            sections.append(ActionSection(
                id: "features",
                title: "Features",
                systemImage: "sparkles",
                rows: features
            ))
        }

        let itemUses = itemUseRows(for: character, content: content)
        if !itemUses.isEmpty {
            sections.append(ActionSection(
                id: "item_uses",
                title: "Item Uses",
                systemImage: "wand.and.stars",
                rows: itemUses
            ))
        }

        return sections
    }

    // MARK: - Weapon Attacks

    /// One row per equipped weapon. Each row carries both rolls (attack +
    /// damage, plus an optional versatile damage variant) so the weapon view
    /// can lay them out as inline icon buttons.
    static func weaponAttacks(
        for character: Character,
        content: ContentStore
    ) -> [WeaponAttackRow] {
        var rows: [WeaponAttackRow] = []
        let fsEffects = CharacterCalculator.fightingStyleEffects(character: character, content: content)
        for inv in character.inventory where inv.equipped {
            guard let weapon = content.weaponDefinition(id: inv.itemID) else { continue }

            // Pull the attack + damage + (versatile) recipes. Trust the
            // weapon's declared recipes when present; otherwise synthesize a
            // sensible default for homebrew that omits them.
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

            var attack: ResolvedAction?
            var damage: ResolvedAction?
            var versatile: ResolvedAction?

            for (index, recipe) in recipes.enumerated() {
                let resolved = ActionInterpreter.resolve(
                    recipe: recipe,
                    character: character,
                    weapon: weapon,
                    fightingStyle: fsEffects
                )
                switch recipe {
                case .weaponAttack:
                    attack = resolved
                case .weaponDamage(_, _, true):
                    // Versatile (two-handed) — disambiguate the label so the
                    // dice tab / history doesn't show two identical entries.
                    versatile = ResolvedAction(
                        id: "\(resolved.id)_v\(index)",
                        label: "\(weapon.name) Damage (2H)",
                        formula: resolved.formula,
                        description: resolved.description
                    )
                case .weaponDamage:
                    damage = resolved
                default:
                    // Some homebrew weapons might inline a heal/save effect.
                    // Phase L+ will surface those properly; skip for now.
                    break
                }
            }

            // A weapon without both an attack and a damage roll is effectively
            // unusable in the sheet — skip it.
            guard let attack, var damage else { continue }
            var versatileEnriched = versatile

            // Fold any active automatic damage riders (Hex, Hunter's Mark)
            // into both the standard and versatile damage actions. Riders are
            // damage-only — the d20 attack roll is untouched.
            damage = TriggeredEffectResolver.applyAutomaticDamageRiders(
                to: damage, weapon: weapon, character: character, content: content
            )
            if let v = versatileEnriched {
                versatileEnriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
                    to: v, weapon: weapon, character: character, content: content
                )
            }

            // Mastery only displays when the character has both the Weapon
            // Mastery feature (via class) AND has chosen this weapon as one
            // of their active masteries (5e 2024).
            let activeMastery: WeaponMastery? = {
                guard let property = weapon.masteryProperty else { return nil }
                guard CharacterCalculator.hasActiveMastery(
                    weaponID: weapon.id, character: character, content: content
                ) else { return nil }
                return property
            }()

            let optInRiders = TriggeredEffectResolver.optInRiders(
                weapon: weapon,
                baseDamage: damage,
                character: character,
                content: content
            )

            rows.append(WeaponAttackRow(
                id: "weapon_\(inv.id.uuidString)",
                weaponName: weapon.name,
                mastery: activeMastery,
                attack: attack,
                damage: damage,
                versatileDamage: versatileEnriched,
                optInRiders: optInRiders
            ))
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
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolvedFeature in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                let feature = resolvedFeature.feature
                // Reactive features (Stroke of Luck) own a resource but get no
                // action-grid row — the dice tab handles them after a roll.
                // Data-driven now, no feature-id string match.
                guard feature.surfacesAsAction else { continue }
                let cost = feature.resource.map { ResourceCost(resourceID: $0.id, amount: 1) }
                let resolvedResource = feature.resource.flatMap { def in
                    ResourceCalculator.availableResources(character: character, content: content)
                        .first { $0.definition.id == def.id }
                }
                let badge = resolvedResource.map { "\($0.current) / \($0.max)" }
                let isExhausted = resolvedResource?.isExhausted ?? false

                // Toggleable triggered-effect features (Rage) get a bespoke
                // row whose tap flips the effect on/off via toggleEffect, not
                // a roll. Resource spend is handled in the tap path so we
                // don't pay on the deactivate tap.
                if let trig = feature.triggeredEffect, trig.activation == .toggle {
                    let isActive = character.activeEffects.contains { $0.effectID == trig.id }
                    let rounds: Int?
                    switch trig.lifecycle {
                    case .persistent(.rounds(let n)): rounds = n
                    case .persistent(.concentrationEnds), .persistent(.manual), .oneShot:
                        rounds = nil
                    }
                    let action = ResolvedAction(
                        id: "feature_\(feature.id)_toggle",
                        label: isActive ? "End \(feature.name)" : feature.name,
                        formula: nil,
                        description: feature.description,
                        actionCost: feature.actionCost
                    )
                    rows.append(ActionRow(
                        action: action,
                        badge: badge,
                        // When active, the row should always be tappable (to
                        // end the toggle). Only grey when exhausted AND we'd
                        // be activating — can't start Rage with 0 uses left.
                        isExhausted: !isActive && isExhausted,
                        toggleEffect: ToggleEffectContext(
                            effectID: trig.id,
                            featureID: feature.id,
                            roundsRemaining: rounds,
                            resourceID: feature.resource?.id,
                            isActive: isActive
                        ),
                        title: isActive ? "End \(feature.name)" : feature.name,
                        subtitle: isActive ? "Active" : nil,
                        detail: feature.description
                    ))
                    continue
                }

                if feature.actionRecipes.isEmpty, cost != nil {

                    // Resource-only feature (e.g. Action Surge): no roll, but
                    // tapping the button still consumes a charge.
                    let action = ResolvedAction(
                        id: "feature_\(feature.id)_consume",
                        label: feature.name,
                        formula: nil,
                        description: nil,
                        resourceCost: cost,
                        actionCost: feature.actionCost
                    )
                    rows.append(ActionRow(
                        action: action, badge: badge, isExhausted: isExhausted,
                        title: feature.name, detail: feature.description
                    ))
                    continue
                }

                for recipe in feature.actionRecipes {
                    let resolved = ActionInterpreter.resolve(
                        recipe: recipe,
                        character: character,
                        weapon: nil,
                        // Lets feature recipes flagged addSpellcastingMod
                        // (Divine Spark's 1d8 + WIS) resolve against the
                        // owning class's casting stat.
                        spellcastingAbility: cls.spellcasting?.ability
                    )
                    // Prefer the feature name as the label so the button reads
                    // "Second Wind" rather than the interpreter's generic title.
                    let labeled = ResolvedAction(
                        id: "feature_\(feature.id)_\(resolved.id)",
                        label: featureButtonLabel(feature: feature, resolved: resolved),
                        formula: resolved.formula,
                        description: resolved.description,
                        resourceCost: cost,
                        actionCost: feature.actionCost
                    )
                    // Clean title (feature name) + gray subtitle (the roll
                    // summary, when distinct) + rules detail — matches the
                    // granted-option row shape for a cohesive list.
                    let summary = resolved.label == feature.name ? nil : resolved.label
                    rows.append(ActionRow(
                        action: labeled, badge: badge, isExhausted: isExhausted,
                        title: feature.name, subtitle: summary, detail: feature.description
                    ))
                }
            }
        }

        if let species = content.speciesDefinition(id: character.speciesID) {
            // A chosen ancestry option (Draconic Ancestry) sets the damage type
            // of the species' otherwise-untyped scaling rolls (Breath Weapon).
            let ancestryType = ancestryDamageType(species: species, character: character)
            for trait in species.traits {
                guard trait.surfacesAsAction else { continue }
                let cost = trait.resource.map { ResourceCost(resourceID: $0.id, amount: 1) }
                let resolvedResource = trait.resource.flatMap { def in
                    ResourceCalculator.availableResources(character: character, content: content)
                        .first { $0.definition.id == def.id }
                }
                let badge = resolvedResource.map { "\($0.current) / \($0.max)" }
                let isExhausted = resolvedResource?.isExhausted ?? false

                // Usable trait with a pool but no roll (Stonecunning's Bonus
                // Action tremorsense, Orc Adrenaline Rush, Goliath Large Form):
                // a tap spends a charge.
                if trait.actionRecipes.isEmpty {
                    guard cost != nil else { continue }
                    let action = ResolvedAction(
                        id: "trait_\(trait.id)_consume",
                        label: trait.name,
                        formula: nil,
                        description: nil,
                        resourceCost: cost,
                        actionCost: trait.actionCost
                    )
                    rows.append(ActionRow(
                        action: action, badge: badge, isExhausted: isExhausted,
                        title: trait.name, detail: trait.description
                    ))
                    continue
                }

                for recipe in trait.actionRecipes {
                    let resolved = ActionInterpreter.resolve(
                        recipe: typedForAncestry(recipe, ancestryType),
                        character: character,
                        weapon: nil
                    )
                    let labeled = ResolvedAction(
                        id: "trait_\(trait.id)_\(resolved.id)",
                        label: trait.name,
                        formula: resolved.formula,
                        description: resolved.description,
                        resourceCost: cost,
                        actionCost: trait.actionCost
                    )
                    let summary = resolved.label == trait.name ? nil : resolved.label
                    rows.append(ActionRow(
                        action: labeled, badge: badge, isExhausted: isExhausted,
                        title: trait.name, subtitle: summary, detail: trait.description
                    ))
                }
            }
        }

        return rows
    }

    /// The damage type a chosen species selection-option imparts to a sibling
    /// roll (Draconic Ancestry → Breath Weapon / Damage Resistance). First
    /// match across the species' fixed-option selections, or nil if unchosen.
    private static func ancestryDamageType(
        species: SpeciesDefinition, character: Character
    ) -> DamageType? {
        for trait in species.traits {
            guard let selection = trait.selection,
                  case .fixedOptions(let options) = selection.optionsSource else { continue }
            let picked = Set(character.featureSelections[selection.id] ?? [])
            for option in options where picked.contains(option.id) {
                if let type = option.damageType { return type }
            }
        }
        return nil
    }

    /// Stamps an untyped scaling-damage recipe (Breath Weapon's 1d10→4d10) with
    /// the chosen ancestry's damage type. Every other recipe passes through.
    private static func typedForAncestry(
        _ recipe: ActionRecipe, _ type: DamageType?
    ) -> ActionRecipe {
        guard let type,
              case .scaledDamage(let dieKind, let count, nil, let label) = recipe else { return recipe }
        return .scaledDamage(dieKind: dieKind, count: count, damageType: type, label: label)
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

    // MARK: - Item Uses

    /// Build the action grid's "Items" section. Only equipped, attuned-if-required
    /// items contribute — carried-but-unequipped items still live in the resources
    /// card so the player can spend them ad-hoc, just not as a primary action.
    private static func itemUseRows(
        for character: Character,
        content: ContentStore
    ) -> [ActionRow] {
        var rows: [ActionRow] = []

        for inv in character.inventory {
            guard inv.equipped else { continue }
            let needsAttunement = content.attunementRule(forItemID: inv.itemID) != nil
            if needsAttunement && !inv.attuned { continue }

            let uses = content.itemUses(forItemID: inv.itemID)
            guard !uses.isEmpty else { continue }
            let itemName = content.itemName(forItemID: inv.itemID) ?? inv.itemID

            for use in uses {
                let resolvedResource = ResourceCalculator.availableResources(character: character, content: content)
                    .first { $0.definition.id == use.cost.resourceID }
                let badge = resolvedResource.map { "\($0.current) / \($0.max)" }
                // Exhausted if the pool can't even cover the base cost.
                let isExhausted = (resolvedResource?.current ?? 0) < use.cost.amount

                switch use.effect {
                case .castSpell(let spellID, let baseLevel):
                    let maxLevel = use.upcastChoice?.maxLevel ?? baseLevel
                    let extra    = use.upcastChoice?.extraCostPerLevel ?? 0
                    let context = ItemSpellCastContext(
                        spellID: spellID,
                        itemName: itemName,
                        resourceID: use.cost.resourceID,
                        baseLevel: baseLevel,
                        maxLevel: maxLevel,
                        baseCost: use.cost.amount,
                        extraCostPerLevel: extra
                    )
                    // Formula stays nil; the cast sheet owns the rolls. The
                    // resourceCost field is also nil — the cast sheet pays the
                    // charge cost itself based on the chosen slot level.
                    let action = ResolvedAction(
                        id: "itemUse_\(inv.itemID)_\(use.id)",
                        label: use.name,
                        formula: nil,
                        description: costSubtitle(amount: use.cost.amount, extraPerLevel: extra),
                        resourceCost: nil,
                        actionCost: use.actionCost
                    )
                    rows.append(ActionRow(
                        action: action,
                        badge: badge,
                        isExhausted: isExhausted,
                        castFromItem: context,
                        title: use.name,
                        subtitle: costSubtitle(amount: use.cost.amount, extraPerLevel: extra),
                        detail: content.itemDescription(forItemID: inv.itemID)
                    ))

                case .actionRecipes(let recipes):
                    let cost = ResourceCost(resourceID: use.cost.resourceID, amount: use.cost.amount)
                    for recipe in recipes {
                        let resolved = ActionInterpreter.resolve(
                            recipe: recipe,
                            character: character,
                            weapon: nil
                        )
                        let labeled = ResolvedAction(
                            id: "itemUse_\(inv.itemID)_\(use.id)_\(resolved.id)",
                            label: use.name,
                            formula: resolved.formula,
                            description: resolved.description,
                            resourceCost: cost,
                            actionCost: use.actionCost
                        )
                        rows.append(ActionRow(
                            action: labeled,
                            badge: badge,
                            isExhausted: isExhausted,
                            title: use.name,
                            subtitle: resolved.label == use.name ? nil : resolved.label,
                            detail: content.itemDescription(forItemID: inv.itemID)
                        ))
                    }
                }
            }
        }

        return rows
    }

    private static func costSubtitle(amount: Int, extraPerLevel: Int) -> String {
        let basePart = amount == 1 ? "1 charge" : "\(amount) charges"
        if extraPerLevel > 0 {
            return "\(basePart) (+\(extraPerLevel)/lvl)"
        }
        return basePart
    }

    // MARK: - Granted actions (feature-conferred turn options)

    /// Every named action option the character's features confer (Cunning
    /// Action → Dash / Disengage / Hide), flattened and tagged with the
    /// source feature. The Actions tab groups these by economy so the player
    /// can see their whole turn — including non-rollable options that never
    /// appeared before. Resolved through the same feature walk as everything
    /// else, so subclass grants are included.
    static func grantedActions(for character: Character, content: ContentStore) -> [GrantedActionRow] {
        var rows: [GrantedActionRow] = []
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                for granted in resolved.feature.grantedActions {
                    rows.append(GrantedActionRow(
                        id: "\(resolved.feature.id)_\(granted.name)",
                        featureName: resolved.feature.name,
                        action: granted
                    ))
                }
            }
        }
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits {
                for granted in trait.grantedActions {
                    rows.append(GrantedActionRow(
                        id: "trait_\(trait.id)_\(granted.name)",
                        featureName: trait.name,
                        action: granted
                    ))
                }
            }
        }
        return rows
    }
}

/// One flattened granted-action option for the Actions-tab economy view.
struct GrantedActionRow: Identifiable, Equatable {
    let id: String
    let featureName: String
    let action: GrantedAction
    var cost: ActionCost { action.cost }
}
