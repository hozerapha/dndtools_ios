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
            VStack(alignment: .leading, spacing: 4) {
                Text(result.formula.displayString)
                    .font(.headline)
                HStack(spacing: 6) {
                    if result.mode != .normal {
                        Text(result.mode.shortLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                result.mode == .advantage ? Color.green : Color.red,
                                in: Capsule()
                            )
                    }
                    Text(result.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(result.total)")
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(totalColor(for: result))
        }
        .padding(.vertical, 4)
    }

    private func totalColor(for result: RollResult) -> Color {
        if result.hasCriticalSuccess { return .yellow }
        if result.hasCriticalFail    { return .red }
        return .primary
    }
}
