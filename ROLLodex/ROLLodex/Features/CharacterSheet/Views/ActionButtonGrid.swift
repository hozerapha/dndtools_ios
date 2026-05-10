import SwiftUI

/// Grouped grid of action buttons on the character sheet. Tapping a button
/// hands the resolved action off to the dice tab via `PendingRollStore` and
/// flips `selectedTab` to `.dice`. Save-DC style rows have no formula and are
/// rendered as info chips instead of buttons.
struct ActionButtonGrid: View {
    let sections: [ActionSection]
    let onTap: (ResolvedAction) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(sections) { section in
                SheetCard(title: section.title, systemImage: section.systemImage) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(section.rows) { row in
                            ActionTile(row: row, onTap: onTap)
                        }
                    }
                }
            }
        }
    }
}

private struct ActionTile: View {
    let row: ActionRow
    let onTap: (ResolvedAction) -> Void

    var body: some View {
        // Info-only rows (no formula and no resource cost) — e.g. save DC —
        // render as a flat chip. Anything actionable is a button. The
        // `isExhausted` flag greys it out in either case.
        if row.action.formula == nil && row.action.resourceCost == nil {
            tileBody
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                onTap(row.action)
            } label: {
                tileBody
            }
            .buttonStyle(ActionTileButtonStyle())
            .disabled(row.isExhausted)
            .opacity(row.isExhausted ? 0.45 : 1)
        }
    }

    private var tileBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.action.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let badge = row.badge {
                Text(badge)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct ActionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.28 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
