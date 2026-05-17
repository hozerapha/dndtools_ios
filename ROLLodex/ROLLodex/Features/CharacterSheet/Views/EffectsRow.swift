import SwiftUI

/// Compact row of active-effect pills shown under the conditions row in the
/// sheet header. Each pill displays the rider's name (Hex, Hunter's Mark,
/// later Rage / Bless / etc.); the menu shows the description and a Dismiss
/// button that drops the effect — and concentration too, when the effect is
/// spell-sourced.
///
/// Hidden when there are no active effects; the slot collapses cleanly above
/// the stat pill row so a casual fighter never sees an empty row.
struct EffectsRow: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content

    var body: some View {
        if !character.activeEffects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(character.activeEffects) { active in
                        pill(for: active)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func pill(for active: ActiveEffect) -> some View {
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.22), in: Capsule())
            .foregroundStyle(.purple)
        }
    }

    /// Look up the matching `TriggeredEffect` payload. Mirrors the resolver's
    /// dispatch so the badge label / description stay in sync with what
    /// actually fires on damage rolls.
    private func resolved(for active: ActiveEffect) -> TriggeredEffect? {
        switch active.source {
        case .spell(let id):
            return content.spellDefinition(id: id)?.grantsTriggeredEffect
        case .feature, .item:
            return nil
        }
    }

    private func descriptionLine(for effect: TriggeredEffect, source: EffectSource) -> String {
        var parts: [String] = []
        switch effect.effect {
        case .addDamageDice(let dice, let typed):
            switch typed {
            case .fixed(let dt):
                parts.append("+\(dice) \(dt.rawValue) on each damage roll")
            case .matchWeapon:
                parts.append("+\(dice) matching the weapon's damage type")
            }
        }
        switch effect.lifecycle {
        case .persistent(.concentrationEnds):
            parts.append("Ends when concentration drops")
        }
        if case .spell(let id) = source {
            parts.append("Source: \(id)")
        }
        return parts.joined(separator: "\n")
    }
}
