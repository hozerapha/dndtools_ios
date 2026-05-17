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
    /// feature / item sources land with Slice B & C.
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
}
