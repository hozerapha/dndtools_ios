import SwiftUI

struct DiePickerView: View {
    @Binding var formula: DiceFormula

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DieKind.allCases) { kind in
                DiePickerButton(
                    kind: kind,
                    count: formula.counts[kind, default: 0],
                    onTap:       { formula.add(kind) },
                    onLongPress: { formula.remove(kind) }
                )
            }
        }
    }
}

private struct DiePickerButton: View {
    let kind: DieKind
    let count: Int
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(kind.label)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(kind.color.gradient,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(pressed ? 0.92 : 1.0)
                .animation(.spring(duration: 0.18), value: pressed)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    onTap()
                    pulse()
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    onLongPress()
                    pulse()
                }
                .sensoryFeedback(.impact(weight: .light), trigger: count)

            if count > 0 {
                Text("\(count)")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: Capsule())
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: count)
    }

    private func pulse() {
        pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pressed = false
        }
    }
}
