import SwiftUI

struct DiceTrayView: View {
    let formula: DiceFormula
    let mode: RollMode
    let result: RollResult?
    let isRolling: Bool
    let animationTick: Int

    var body: some View {
        ZStack {
            TrayBackground()
            content
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if formula.totalDiceCount == 0 {
            VStack(spacing: 8) {
                Image(systemName: "dice")
                    .font(.system(size: 44))
                    .foregroundStyle(Self.feltMuted)
                Text("Tap dice below to build a formula")
                    .font(.subheadline)
                    .foregroundStyle(Self.feltSecondary)
            }
        } else {
            VStack(spacing: 14) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    tokenGrid
                }
                if !isRolling, let r = settledResult {
                    Text(breakdown(for: r))
                        .font(.caption)
                        .foregroundStyle(Self.feltSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if isRolling {
            Text("Rolling…")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Self.feltSecondary)
        } else if let r = settledResult {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(Self.feltSecondary)
                    Spacer()
                    Text("\(r.total)")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(totalColor(for: r))
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                        .contentTransition(.numericText())
                }
                DamageBreakdownView(result: r, foreground: Self.feltSecondary)
            }
        } else {
            Text("Tap Roll")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Self.feltSecondary)
        }
    }

    private var tokenGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 70, maximum: 80), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(displayedTokens) { token in
                DieTokenView(kind: token.kind, value: token.value, isKept: token.isKept)
            }
        }
    }

    private var settledResult: RollResult? {
        guard let result, result.formula == formula, result.mode == mode else { return nil }
        return result
    }

    private var displayedTokens: [TrayToken] {
        _ = animationTick

        if isRolling {
            return plannedTokens(valueProvider: { kind in Int.random(in: 1...kind.sides) })
        }
        if let r = settledResult {
            return r.dieRolls.enumerated().map { idx, roll in
                TrayToken(id: "result-\(idx)", kind: roll.kind, value: roll.value, isKept: roll.isKept)
            }
        }
        return plannedTokens(valueProvider: { _ in nil })
    }

    private func plannedTokens(valueProvider: (DieKind) -> Int?) -> [TrayToken] {
        var tokens: [TrayToken] = []
        let advDouble = mode != .normal && formula.supportsAdvantage

        for group in formula.groups {
            let renderCount: Int = {
                if advDouble && group.kind == .d20 && group.count == 1 && group.isPlain {
                    return 2
                }
                return group.count
            }()

            for dieIndex in 0..<renderCount {
                tokens.append(
                    TrayToken(
                        id: "\(group.id.uuidString)-\(dieIndex)",
                        kind: group.kind,
                        value: valueProvider(group.kind),
                        isKept: true
                    )
                )
            }
        }
        return tokens
    }

    private func totalColor(for result: RollResult) -> Color {
        if result.hasCriticalSuccess { return .yellow }
        if result.hasCriticalFail    { return Color(red: 1.0, green: 0.45, blue: 0.42) }
        return Self.feltPrimary
    }

    private func breakdown(for result: RollResult) -> String {
        let kept = result.dieRolls.filter(\.isKept)
        let parts = kept.map { "\($0.kind.label):\($0.value)" }
        var line = parts.joined(separator: ", ")
        if result.modifier > 0 {
            line += " + \(result.modifier)"
        } else if result.modifier < 0 {
            line += " − \(abs(result.modifier))"
        }
        return line
    }

    private static let feltPrimary:   Color = Color(red: 0.96, green: 0.95, blue: 0.88)
    private static let feltSecondary: Color = Color(red: 0.96, green: 0.95, blue: 0.88).opacity(0.65)
    private static let feltMuted:     Color = Color(red: 0.96, green: 0.95, blue: 0.88).opacity(0.35)
}

private struct TrayToken: Identifiable {
    let id: String
    let kind: DieKind
    let value: Int?
    let isKept: Bool
}

// MARK: - Wood + felt tray background (image-textured, with procedural lighting on top).

private struct TrayBackground: View {
    var body: some View {
        ZStack {
            WoodFrame()
            FeltSurface()
                .padding(14)
        }
    }
}

private struct WoodFrame: View {
    var body: some View {
        ZStack {
            // Fallback color shows if the image asset is missing or while it loads.
            Color(red: 0.36, green: 0.21, blue: 0.10)
            Image("tray-wood")
                .resizable()
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            // Top-edge highlight + bottom-edge shadow ring for the bevel illusion.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.32),
                            .white.opacity(0.05),
                            .clear,
                            .black.opacity(0.30)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: .black.opacity(0.30), radius: 4, y: 2)
    }
}

private struct FeltSurface: View {
    var body: some View {
        ZStack {
            ZStack {
                Color(red: 0.09, green: 0.27, blue: 0.16)
                Image("tray-felt")
                    .resizable()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Inner shadow — blurred dark stroke clipped to the felt's bounds.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.black.opacity(0.65), lineWidth: 10)
                .blur(radius: 6)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)

            // Corner vignette to push the dice toward visual center.
            RadialGradient(
                colors: [.clear, .black.opacity(0.40)],
                center: .center,
                startRadius: 60,
                endRadius: 380
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            // Crisp dark seam where felt meets wood.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.black.opacity(0.55), lineWidth: 0.8)
        }
    }
}
