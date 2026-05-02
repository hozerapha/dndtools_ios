import SwiftUI

struct DiceTrayView: View {
    let formula: DiceFormula
    let mode: RollMode
    let result: RollResult?
    let isRolling: Bool
    let animationTick: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            content
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if formula.totalDiceCount == 0 {
            VStack(spacing: 8) {
                Image(systemName: "dice")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("Tap dice below to build a formula")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        } else if let r = settledResult {
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(r.total)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(totalColor(for: r))
                    .contentTransition(.numericText())
            }
        } else {
            Text("Tap Roll")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
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

    /// What goes in the tray right now.
    private var displayedTokens: [TrayToken] {
        // animationTick is referenced so SwiftUI re-evaluates this whenever it changes.
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
        if result.hasCriticalFail    { return .red }
        return .primary
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
}

private struct TrayToken: Identifiable {
    let id: String
    let kind: DieKind
    let value: Int?
    let isKept: Bool
}
