import SwiftUI

/// Sheet card listing every pool the character has access to (features now;
/// items + spell slots in later phases). Each row shows current/max and
/// `−` / `+` chips for ad-hoc adjustment (DM correction). Tapping the source
/// label reveals the refresh rule.
struct ResourcesView: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true

    var body: some View {
        let resources = ResourceCalculator.availableResources(
            character: character,
            content: content
        )
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 6) {
                if resources.isEmpty {
                    Text("No resources yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } else {
                    ForEach(resources) { resource in
                        ResourceRow(
                            resource: resource,
                            onAdjust: { delta in adjust(resource: resource, by: delta) }
                        )
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Resources", systemImage: "bolt.circle.fill")
                .font(.headline)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func adjust(resource: ResolvedResource, by delta: Int) {
        ResourceCalculator.setCurrent(
            resource.current + delta,
            for: resource.id,
            in: &character,
            content: content
        )
    }
}

private struct ResourceRow: View {
    let resource: ResolvedResource
    let onAdjust: (Int) -> Void
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.definition.name)
                        .font(.subheadline.weight(.semibold))
                    Button {
                        showDetail.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(resource.sourceLabel)
                            Image(systemName: showDetail ? "chevron.down" : "chevron.right")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                AdjustChip(systemImage: "minus.circle.fill", disabled: resource.isExhausted) {
                    onAdjust(-1)
                }
                Text("\(resource.current) / \(resource.max)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 48)
                AdjustChip(systemImage: "plus.circle.fill", disabled: resource.isFull) {
                    onAdjust(+1)
                }
            }
            if showDetail {
                Text(refreshDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    /// Plain-English version of the refresh rule for the disclosure detail.
    private var refreshDescription: String {
        let trigger: String
        switch resource.definition.refreshOn {
        case .shortRest: trigger = "short or long rest"
        case .longRest:  trigger = "long rest"
        case .dawn:      trigger = "dawn (folded into long rest)"
        case .encounter: trigger = "every encounter"
        case .never:     trigger = "never"
        }
        let amount: String
        switch resource.definition.refreshAmount {
        case .all:                 amount = "to full"
        case .fixed(let n):        amount = "by \(n)"
        case .byClassLevel:        amount = "by class-level table"
        case .roll(let formula):   amount = "by \(formula) roll"
        }
        return "Refreshes \(amount) on \(trigger)"
    }
}

private struct AdjustChip: View {
    let systemImage: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
