import SwiftUI

struct HistorySheet: View {
    @Environment(HistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    let onReroll: (RollResult) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if history.rolls.isEmpty {
                    ContentUnavailableView(
                        "No rolls yet",
                        systemImage: "clock",
                        description: Text("Your roll history will show up here.")
                    )
                } else {
                    List {
                        ForEach(history.rolls) { result in
                            HistoryRow(result: result)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onReroll(result)
                                    dismiss()
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !history.rolls.isEmpty {
                        Button("Clear", role: .destructive) {
                            history.clear()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let result: RollResult

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .lineLimit(2)
                Text(result.formula.displayString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(result.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            Spacer()
            Text("\(result.total)")
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(totalColor(for: result))
        }
        .padding(.vertical, 4)
    }

    /// Composed headline: friendly label (or "Custom roll") + an "(adv)" /
    /// "(dis)" suffix derived from the formula itself, so adv/dis is always
    /// readable even on rerolled or restored entries.
    private var headline: String {
        let base = result.label?.isEmpty == false ? result.label! : "Custom roll"
        switch result.formula.encodedAdvantageMode {
        case .advantage:    return "\(base) (adv)"
        case .disadvantage: return "\(base) (dis)"
        case .normal, .none: return base
        }
    }

    private func totalColor(for result: RollResult) -> Color {
        if result.hasCriticalSuccess { return .yellow }
        if result.hasCriticalFail    { return .red }
        return .primary
    }
}
