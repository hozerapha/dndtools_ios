import Foundation

/// Folds matching `TriggeredEffect`s from `character.activeEffects` into an
/// in-flight weapon damage roll. Slice A only handles `.automatic` riders on
/// `.onDamageRoll` triggers — the Hex / Hunter's Mark shape. Slice B will
/// extend this to surface `.optIn` chips for Sneak Attack / Divine Smite.
///
/// The resolver runs AFTER `ActionInterpreter.resolve(...)` produces the
/// primary damage `ResolvedAction` — it composes on top rather than
/// rewriting the interpreter.
@MainActor
enum TriggeredEffectResolver {
    /// Returns a copy of `damage` with any matching rider dice appended to
    /// the formula (tagged with the rider's damage type so Phase N's
    /// breakdown renders the split). Riders without a matching trigger /
    /// weapon are skipped silently. When no riders fire, the original action
    /// is returned unchanged.
    static func applyAutomaticDamageRiders(
        to damage: ResolvedAction,
        weapon: WeaponDefinition?,
        character: Character,
        content: ContentStore
    ) -> ResolvedAction {
        guard var formula = damage.formula else { return damage }
        var firedNames: [String] = []

        for active in character.activeEffects {
            guard let effect = effect(for: active, in: content) else { continue }
            guard case .onDamageRoll = effect.trigger else { continue }
            guard case .addDamageDice(let dice, let typed) = effect.effect else { continue }

            // Resolve the damage type. `.matchWeapon` requires a wielded
            // weapon — without one the rider just doesn't fire (e.g. Hunter's
            // Mark on an unarmed strike would have no type to copy).
            let damageType: DamageType
            switch typed {
            case .fixed(let dt):
                damageType = dt
            case .matchWeapon:
                guard let weaponDT = weapon?.damageType else { continue }
                damageType = weaponDT
            }

            // Parse the rider's dice into a sub-formula so it can carry its
            // own modifiers and groups (today just "1d6", but the schema
            // tolerates richer strings for future homebrew riders).
            guard var rider = try? DiceFormulaParser().parse(dice) else { continue }
            rider.applyDamageType(damageType)

            formula.groups.append(contentsOf: rider.groups)
            for (type, value) in rider.typedModifiers {
                formula.typedModifiers[type, default: 0] += value
                if formula.typedModifiers[type] == 0 {
                    formula.typedModifiers.removeValue(forKey: type)
                }
            }
            // Untyped flat on a rider is unusual but handle it consistently.
            formula.modifier += rider.modifier

            firedNames.append(effect.name)
        }

        guard !firedNames.isEmpty else { return damage }
        return ResolvedAction(
            id: damage.id,
            label: damage.label + " +" + firedNames.joined(separator: ", "),
            formula: formula,
            description: damage.description,
            resourceCost: damage.resourceCost,
            actionCost: damage.actionCost
        )
    }

    /// Maps an `ActiveEffect` back to the `TriggeredEffect` payload that
    /// lives on its content source. Slice A only resolves spell sources;
    /// feature / item sources land with later slices.
    private static func effect(
        for active: ActiveEffect,
        in content: ContentStore
    ) -> TriggeredEffect? {
        switch active.source {
        case .spell(let id):
            return content.spellDefinition(id: id)?.grantsTriggeredEffect
        case .feature, .item:
            return nil
        }
    }

    // MARK: - Slice B: opt-in riders from class features

    /// Walk the character's class features and produce one chip per qualifying
    /// `TriggeredEffect` with `.optIn` activation + `.onAttackHit` trigger.
    /// Each chip's formula is the BASE weapon damage merged with the rider's
    /// extra dice, so tapping "Use Sneak Attack" rolls weapon + rider in one
    /// pass — the player picks one chip from the rail instead of rolling
    /// damage and Sneak Attack separately. Features already spent this turn
    /// (`.oncePerTurn` flag already set) are filtered out so the chip doesn't
    /// reappear.
    static func optInRiders(
        weapon: WeaponDefinition?,
        baseDamage: ResolvedAction,
        character: Character,
        content: ContentStore
    ) -> [PendingFollowUp] {
        var out: [PendingFollowUp] = []
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                guard let effect = resolved.feature.triggeredEffect,
                      effect.activation == .optIn,
                      case .onAttackHit(let filter) = effect.trigger else { continue }
                if let filter, !filter.matches(weapon: weapon) { continue }
                // Once-per-turn cost: skip if the flag is already set.
                if case .oncePerTurn(let flag)? = effect.cost,
                   character.hasTurnFlag(flag) { continue }
                guard let chip = buildChip(
                    for: effect,
                    weapon: weapon,
                    baseDamage: baseDamage,
                    character: character,
                    classLevel: entry.level
                ) else { continue }
                out.append(chip)
            }
        }
        return out
    }

    /// Merge the rider's dice into the base weapon-damage formula, then wrap
    /// the result as a chip whose tap rolls the combined damage in one go.
    /// Returns nil when the effect can't produce a usable rider (no formula
    /// to merge, no weapon for `.matchWeapon`, scaling table at 0).
    private static func buildChip(
        for effect: TriggeredEffect,
        weapon: WeaponDefinition?,
        baseDamage: ResolvedAction,
        character: Character,
        classLevel: Int
    ) -> PendingFollowUp? {
        guard let baseFormula = baseDamage.formula else { return nil }

        // Resolve the rider's contribution into its own DiceFormula first.
        let damageType: DamageType
        var rider: DiceFormula

        switch effect.effect {
        case .addDamageDice(let dice, let typed):
            guard let resolvedType = resolveDamageType(typed, weapon: weapon) else { return nil }
            damageType = resolvedType
            rider = (try? DiceFormulaParser().parse(dice)) ?? DiceFormula()

        case .addScaledDamageDice(let count, let die, let typed):
            guard let resolvedType = resolveDamageType(typed, weapon: weapon) else { return nil }
            damageType = resolvedType
            let n = count.value(classLevel: classLevel, characterLevel: character.level)
            guard n > 0 else { return nil }
            rider = (try? DiceFormulaParser().parse("\(n)\(die)")) ?? DiceFormula()
        }

        rider.applyDamageType(damageType)
        guard !rider.groups.isEmpty else { return nil }

        // Merge: base + rider groups, sum typed modifiers, sum untyped flat.
        var merged = baseFormula
        merged.groups.append(contentsOf: rider.groups)
        for (type, value) in rider.typedModifiers {
            merged.typedModifiers[type, default: 0] += value
            if merged.typedModifiers[type] == 0 {
                merged.typedModifiers.removeValue(forKey: type)
            }
        }
        merged.modifier += rider.modifier

        let mergedAction = ResolvedAction(
            id: "merged_\(baseDamage.id)_\(effect.id)",
            label: "\(baseDamage.label) + \(effect.name)",
            formula: merged,
            description: merged.displayString
        )
        return PendingFollowUp(
            id: "rider_\(effect.id)",
            action: mergedAction,
            cost: effect.cost,
            chipPrompt: effect.name
        )
    }

    private static func resolveDamageType(
        _ typed: TypedOrMatch,
        weapon: WeaponDefinition?
    ) -> DamageType? {
        switch typed {
        case .fixed(let dt): return dt
        case .matchWeapon:  return weapon?.damageType
        }
    }

    // MARK: - Turn-flag labels

    /// Find the human-readable name behind a `turnFlag` id by scanning the
    /// character's class features and spell-sourced active effects for the
    /// effect that set it ("sneak_attack" → "Sneak Attack"). Falls back to
    /// title-casing the id so a flag from a removed feature still renders
    /// something readable in the "Used this turn" pill.
    static func turnFlagDisplayName(
        _ flagID: String,
        character: Character,
        content: ContentStore
    ) -> String {
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                if let effect = resolved.feature.triggeredEffect,
                   case .oncePerTurn(let id) = effect.cost,
                   id == flagID {
                    return effect.name
                }
            }
        }
        for active in character.activeEffects {
            if case .spell(let spellID) = active.source,
               let spell = content.spellDefinition(id: spellID),
               let effect = spell.grantsTriggeredEffect,
               case .oncePerTurn(let id) = effect.cost,
               id == flagID {
                return effect.name
            }
        }
        return flagID
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
