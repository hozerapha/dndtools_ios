import SwiftUI

struct DieTokenView: View {
    let kind: DieKind
    let value: Int?     // nil → render "?"
    let isKept: Bool

    init(kind: DieKind, value: Int?, isKept: Bool = true) {
        self.kind = kind
        self.value = value
        self.isKept = isKept
    }

    init(roll: DieRoll) {
        self.kind = roll.kind
        self.value = roll.value
        self.isKept = roll.isKept
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(kind.color.gradient)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

            VStack(spacing: -2) {
                Text(value.map(String.init) ?? "?")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(kind.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 64, height: 64)
        .overlay {
            if isCriticalSuccess {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.yellow, lineWidth: 3)
                    .shadow(color: .yellow, radius: 6)
            } else if isCriticalFail {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.red, lineWidth: 3)
            }
        }
        .opacity(isKept ? 1.0 : 0.35)
        .animation(.snappy, value: isKept)
    }

    private var isCriticalSuccess: Bool {
        kind == .d20 && value == 20 && isKept
    }

    private var isCriticalFail: Bool {
        kind == .d20 && value == 1 && isKept
    }
}
