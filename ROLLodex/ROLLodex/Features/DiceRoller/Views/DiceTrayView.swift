import SwiftUI

struct DiceTrayView: View {
    let result: RollResult?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)

            if let result {
                content(for: result)
            } else {
                Text("Tap dice below, then Roll")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    @ViewBuilder
    private func content(for result: RollResult) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.total)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(totalColor(for: result))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(result.dieRolls) { roll in
                        DieTokenView(roll: roll)
                    }
                }
                .padding(.horizontal)
            }

            Text(breakdown(for: result))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 14)
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
