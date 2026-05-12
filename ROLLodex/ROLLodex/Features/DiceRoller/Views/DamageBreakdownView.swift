import SwiftUI

/// Small typed-damage chip rendered alongside a roll's total. Shows "11 slashing"
/// for single-type rolls and "8 force + 3 necrotic" for multi-type ones, with
/// each typed segment tinted to match its die's glow color. Falls back to
/// nothing for fully untyped rolls (ability checks, manual tray rolls).
struct DamageBreakdownView: View {
    let result: RollResult
    /// Color used for untyped pieces ("+", "−", trailing flat modifier). Lives
    /// here because the tray (dark capsule) and history row (system bg) want
    /// different defaults.
    var neutralForeground: Color = .secondary

    var body: some View {
        let parts = Self.segments(for: result)
        if !parts.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, segment in
                    Text(segment.text)
                        .foregroundStyle(segment.color ?? neutralForeground)
                }
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// One piece of the breakdown line. `color == nil` means "use the caller's
    /// neutral foreground" — applied to "+" separators and the untyped trailing
    /// modifier so they don't fight with the typed segments for attention.
    struct Segment {
        let text: String
        let color: Color?
    }

    /// Split the breakdown into per-segment pieces so each typed bucket can be
    /// rendered in its damage color. The text-only helper joins these for
    /// accessibility / share use cases that can't carry color.
    static func segments(for result: RollResult) -> [Segment] {
        let subtotals = result.subtotalsByType
        let typedBuckets = subtotals
            .compactMap { (key, value) -> (DamageType, Int)? in
                guard let key else { return nil }
                return (key, value)
            }
            .sorted { $0.1 > $1.1 } // descending by value for stable order
        guard !typedBuckets.isEmpty else { return [] }

        var out: [Segment] = []
        for (i, bucket) in typedBuckets.enumerated() {
            if i > 0 {
                out.append(Segment(text: "+", color: nil))
            }
            out.append(Segment(
                text: "\(bucket.1) \(bucket.0.rawValue)",
                color: Color(uiColor: bucket.0.glowColor)
            ))
        }
        if let untyped = subtotals[nil], untyped != 0 {
            let sign = untyped > 0 ? "+" : "−"
            out.append(Segment(text: sign, color: nil))
            out.append(Segment(text: "\(abs(untyped))", color: nil))
        }
        return out
    }

    /// Plain-text rendering of the breakdown — used where SwiftUI text styling
    /// isn't available (accessibility, future share sheets) and by tests.
    static func text(for result: RollResult) -> String? {
        let segs = segments(for: result)
        guard !segs.isEmpty else { return nil }
        return segs.map(\.text).joined(separator: " ")
    }
}
