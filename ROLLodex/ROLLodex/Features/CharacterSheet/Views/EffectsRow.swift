import SwiftUI

/// Compact row of effect pills shown under the conditions row in the sheet
/// header. Splits into two stripes:
///   - **Toggles**: features the character can flip on (Rage, etc.). Tapping
///     pays the resource (if any) and adds an `ActiveEffect`.
///   - **Active**: currently-running effects (Hex, Hunter's Mark, active
///     Rage). Each shows a menu with description + Dismiss; round-limited
///     effects also show "Nr" remaining.
///
/// The whole row hides when there's nothing in either stripe so casual
/// fighters never see an empty band.
struct EffectsRow: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content

    var body: some View {
        if !character.activeEffects.isEmpty || !availableToggles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableToggles, id: \.feature.id) { entry in
                        togglePill(for: entry)
                    }
                    ForEach(character.activeEffects) { active in
                        activePill(for: active)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Active-effect pill

    private func activePill(for active: ActiveEffect) -> some View {
        let resolved = resolved(for: active)
        let label = resolved?.name ?? active.effectID
        return Menu {
            if let resolved {
                Text(descriptionLine(for: resolved, source: active.source))
            }
            Button(role: .destructive) {
                character.dismissActiveEffect(active.effectID)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(.semibold))
                if let rounds = active.roundsRemaining {
                    Text("\(rounds)r")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.35), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.22), in: Capsule())
            .foregroundStyle(.purple)
        }
    }

    // MARK: - Toggle pill (inactive feature ready to activate)

    private func togglePill(for entry: ToggleEntry) -> some View {
        let usesLeft = entry.resourceID.map {
            ResourceCalculator.current(character: character, content: content, resourceID: $0)
        }
        let disabled = (usesLeft ?? 1) <= 0
        return Button {
            activate(entry)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.circle")
                    .font(.caption2)
                Text(entry.feature.name)
                    .font(.caption.weight(.semibold))
                if let usesLeft {
                    Text("\(usesLeft)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.35), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(disabled ? Color.secondary : Color.orange)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func activate(_ entry: ToggleEntry) {
        if let resourceID = entry.resourceID {
            guard ResourceCalculator.consume(
                amount: 1,
                from: resourceID,
                in: &character,
                content: content
            ) else { return }
        }
        let rounds: Int?
        switch entry.effect.lifecycle {
        case .persistent(.rounds(let n)): rounds = n
        case .persistent(.concentrationEnds), .persistent(.manual), .oneShot:
            rounds = nil
        }
        character.toggleFeatureEffect(
            effectID: entry.effect.id,
            featureID: entry.feature.id,
            roundsRemaining: rounds
        )
    }

    // MARK: - Available toggles

    /// Toggleable feature effects the character has but hasn't activated yet.
    /// Pulled from class features (base + subclass) so Rage shows up for an
    /// L1 Barbarian. Active toggles are excluded — the active pill already
    /// covers them.
    private var availableToggles: [ToggleEntry] {
        var out: [ToggleEntry] = []
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
                      effect.activation == .toggle else { continue }
                if character.activeEffects.contains(where: { $0.effectID == effect.id }) {
                    continue
                }
                out.append(ToggleEntry(
                    feature: resolved.feature,
                    effect: effect,
                    resourceID: resolved.feature.resource?.id
                ))
            }
        }
        return out
    }

    private struct ToggleEntry {
        let feature: FeatureDefinition
        let effect: TriggeredEffect
        let resourceID: String?
    }

    // MARK: - Description lines

    /// Look up the matching `TriggeredEffect` payload. Mirrors the resolver's
    /// dispatch so the badge label / description stay in sync with what
    /// actually fires on damage rolls.
    private func resolved(for active: ActiveEffect) -> TriggeredEffect? {
        switch active.source {
        case .spell(let id):
            return content.spellDefinition(id: id)?.grantsTriggeredEffect
        case .feature(let id):
            return classFeature(id: id)?.triggeredEffect
        case .item:
            return nil
        }
    }

    private func classFeature(id: String) -> FeatureDefinition? {
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                if resolved.feature.id == id { return resolved.feature }
            }
        }
        return nil
    }

    private func descriptionLine(for effect: TriggeredEffect, source: EffectSource) -> String {
        var parts: [String] = []
        switch effect.effect {
        case .addDamageDice(let dice, let typed):
            parts.append(diceLine(dice: dice, typed: typed))
        case .addScaledDamageDice(_, let die, let typed):
            parts.append(diceLine(dice: "N\(die)", typed: typed))
        case .addFlatDamage(_, let typed):
            parts.append(flatLine(typed: typed))
        }
        switch effect.lifecycle {
        case .persistent(.concentrationEnds):
            parts.append("Ends when concentration drops")
        case .persistent(.rounds(let n)):
            parts.append("Lasts \(n) rounds")
        case .persistent(.manual):
            parts.append("Until you dismiss it")
        case .oneShot:
            parts.append("One-shot (per attack)")
        }
        if case .spell(let id) = source {
            parts.append("Source: \(id)")
        }
        return parts.joined(separator: "\n")
    }

    private func diceLine(dice: String, typed: TypedOrMatch) -> String {
        switch typed {
        case .fixed(let dt):
            return "+\(dice) \(dt.rawValue) on each damage roll"
        case .matchWeapon:
            return "+\(dice) matching the weapon's damage type"
        }
    }

    private func flatLine(typed: TypedOrMatch?) -> String {
        switch typed {
        case nil:
            return "Flat damage bonus on each qualifying roll"
        case .fixed(let dt)?:
            return "Flat \(dt.rawValue) damage bonus on each qualifying roll"
        case .matchWeapon?:
            return "Flat damage matching the weapon's type"
        }
    }
}
