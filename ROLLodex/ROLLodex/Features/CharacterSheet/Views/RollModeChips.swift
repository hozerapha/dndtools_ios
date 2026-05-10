import SwiftUI

/// A trio of small chip buttons — Normal / Advantage / Disadvantage — that
/// dispatch a single roll on tap. Used by skill rows and ability cards so the
/// mode choice is one explicit tap with no menu, no long-press, and a clear
/// visual mapping (blue d20, green up, red down).
struct RollModeChips: View {
    let accessibilityRoot: String
    let onRoll: (RollMode) -> Void
    var size: Size = .regular

    enum Size {
        case regular
        case compact

        var iconFont: Font {
            switch self {
            case .regular: return .subheadline
            case .compact: return .caption
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .regular: return 9
            case .compact: return 6
            }
        }

        var vPadding: CGFloat {
            switch self {
            case .regular: return 6
            case .compact: return 4
            }
        }

        var spacing: CGFloat {
            switch self {
            case .regular: return 6
            case .compact: return 4
            }
        }
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            chip(
                icon: "dice.fill",
                tint: Color.accentColor,
                accessibility: "\(accessibilityRoot) (normal)"
            ) {
                onRoll(.normal)
            }
            chip(
                icon: "chevron.up.circle.fill",
                tint: .green,
                accessibility: "\(accessibilityRoot) with advantage"
            ) {
                onRoll(.advantage)
            }
            chip(
                icon: "chevron.down.circle.fill",
                tint: .red,
                accessibility: "\(accessibilityRoot) with disadvantage"
            ) {
                onRoll(.disadvantage)
            }
        }
    }

    private func chip(
        icon: String,
        tint: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size.iconFont.weight(.semibold))
                .padding(.horizontal, size.hPadding)
                .padding(.vertical, size.vPadding)
                .background(tint.opacity(0.18), in: Capsule())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}
