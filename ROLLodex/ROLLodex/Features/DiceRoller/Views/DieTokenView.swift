import SwiftUI

struct DieTokenView: View {
    let roll: DieRoll

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(roll.kind.color.gradient)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

            VStack(spacing: -2) {
                Text("\(roll.value)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(roll.kind.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 60, height: 60)
        .overlay {
            if roll.isCriticalSuccess {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.yellow, lineWidth: 3)
                    .shadow(color: .yellow, radius: 6)
            } else if roll.isCriticalFail {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.red, lineWidth: 3)
            }
        }
        .opacity(roll.isKept ? 1.0 : 0.35)
    }
}
