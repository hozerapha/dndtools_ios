import SwiftUI

/// Small typed-damage chip rendered alongside a roll's total. Shows "11 slashing"
/// for single-type rolls and "8 force + 3 necrotic" for multi-type ones; falls
/// back to nothing for fully untyped rolls (ability checks, manual tray rolls).
struct DamageBreakdownView: View {
    let result: RollResult
    var foreground: Color = .secondary

    var body: some View {
        if let text = Self.text(for: result) {
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Public + static so non-View surfaces (accessibility labels, future
    /// share sheets) can reuse the same formatting without duplicating logic.
    static func text(for result: RollResult) -> String? {
        let subtotals = result.subtotalsByType
        let typedBuckets = subtotals
            .compactMap { (key, value) -> (DamageType, Int)? in
                guard let key else { return nil }
                return (key, value)
            }
            .sorted { $0.1 > $1.1 } // descending by value for stable order
        guard !typedBuckets.isEmpty else { return nil }
        let typedPart = typedBuckets
            .map { "\($0.1) \($0.0.rawValue)" }
            .joined(separator: " + ")
        if let untyped = subtotals[nil], untyped != 0 {
            let sign = untyped > 0 ? "+" : "−"
            return "\(typedPart) \(sign) \(abs(untyped))"
        }
        return typedPart
    }
}
