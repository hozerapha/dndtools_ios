import SwiftUI

/// Grouped grid of action buttons on the character sheet. Tapping a button
/// hands the row to the sheet, which routes it: most rows push their resolved
/// action onto the dice tab (and pay any `resourceCost`); rows tagged with
/// `castFromItem` open the spell-cast sheet instead. Save-DC style rows have
/// no formula, no cost, and no item context — they render as info chips.
struct ActionButtonGrid: View {
    let sections: [ActionSection]
    let onTap: (ActionRow) -> Void

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
    let onTap: (ActionRow) -> Void

    /// A row is interactive when it has *anything* to do on tap: a roll to
    /// hand off, a resource to consume, or a spell-cast sheet to open.
    private var isInteractive: Bool {
        row.action.formula != nil
            || row.action.resourceCost != nil
            || row.castFromItem != nil
    }

    var body: some View {
        if !isInteractive {
            tileBody
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                onTap(row)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(row.action.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = row.action.description, row.castFromItem != nil {
                    // For item rows we surface the charge cost under the label.
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
