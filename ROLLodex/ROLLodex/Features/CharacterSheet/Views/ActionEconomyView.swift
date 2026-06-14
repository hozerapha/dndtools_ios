import SwiftUI

/// The whole Actions tab as ONE cohesive list grouped by turn economy
/// (Action / Bonus / Reaction / Free / Movement). Interactive feature & item
/// rows (Second Wind, Rage, Fast Hands, Cast …) and feature-granted options
/// (Cunning Action → Dash / Disengage / Hide) share ONE row layout: a clean
/// title, a gray subtitle (the roll/cost summary or source), an info
/// disclosure for the rules, and a trailing control to actually do it. Weapon
/// attacks keep their bespoke view above this.
struct ActionEconomyView: View {
    let interactiveRows: [ActionRow]
    let grantedRows: [GrantedActionRow]
    let onTap: (ActionRow) -> Void
    let onRoll: (ActionRecipe) -> Void

    @State private var expanded: Set<String> = []

    private let economyOrder: [ActionCost] = [.action, .bonusAction, .reaction, .free, .movement]

    var body: some View {
        if interactiveRows.isEmpty && grantedRows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(economyOrder, id: \.self) { cost in
                    let interactive = interactiveRows.filter { ($0.action.actionCost ?? .action) == cost }
                    let granted = grantedRows.filter { $0.cost == cost }
                    if !interactive.isEmpty || !granted.isEmpty {
                        section(cost, interactive: interactive, granted: granted)
                    }
                }
            }
        }
    }

    private func section(_ cost: ActionCost, interactive: [ActionRow], granted: [GrantedActionRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(cost.shortLabel, systemImage: cost.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(interactive) { interactiveRow($0) }
                ForEach(granted) { grantedRow($0) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared row layout

    /// One row: title + optional gray subtitle, an info disclosure when there
    /// are rules to read, and a caller-supplied trailing control. Tapping the
    /// row body toggles the rules; the trailing control performs the action.
    @ViewBuilder
    private func row<Trailing: View>(
        id: String,
        title: String,
        subtitle: String?,
        detail: String?,
        dimmed: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if detail != nil {
                    Image(systemName: expanded.contains(id) ? "chevron.up" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                trailing()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard detail != nil else { return }
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            }

            if expanded.contains(id), let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
    }

    // MARK: - Interactive (feature / item) rows

    private func isInteractive(_ row: ActionRow) -> Bool {
        row.action.formula != nil
            || row.action.resourceCost != nil
            || row.castFromItem != nil
            || row.toggleEffect != nil
    }

    private func trailingIcon(_ row: ActionRow) -> String {
        if row.toggleEffect != nil { return row.toggleEffect?.isActive == true ? "power.circle.fill" : "power.circle" }
        if row.castFromItem != nil { return "wand.and.stars" }
        if row.action.formula != nil { return "dice" }
        return "bolt.fill" // resource-only (Action Surge, etc.)
    }

    @ViewBuilder
    private func interactiveRow(_ action: ActionRow) -> some View {
        let active = isInteractive(action)
        row(
            id: action.id,
            title: action.displayTitle,
            subtitle: action.subtitle,
            detail: action.detail,
            dimmed: action.isExhausted
        ) {
            if let badge = action.badge {
                Text(badge)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            if active {
                Button { onTap(action) } label: { Image(systemName: trailingIcon(action)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(action.isExhausted)
            }
        }
    }

    // MARK: - Granted (feature-conferred) rows

    @ViewBuilder
    private func grantedRow(_ granted: GrantedActionRow) -> some View {
        row(
            id: granted.id,
            title: granted.action.name,
            // Gray source line (Cunning Action) when the option is named
            // differently from its feature.
            subtitle: granted.action.name == granted.featureName ? nil : granted.featureName,
            detail: granted.action.description
        ) {
            if let recipe = granted.action.recipe {
                Button { onRoll(recipe) } label: { Image(systemName: "dice") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
