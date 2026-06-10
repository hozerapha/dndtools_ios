import SwiftUI

/// Death-save tracker, shown in the sheet header only while the character is
/// at 0 HP. Honor-system: the player rolls (the chip hands a d20 to the dice
/// tab) and taps the matching circle. Damage taken while dying auto-fills a
/// failure (`Character.applyDamage`); regaining any HP clears the row.
struct DeathSavesRow: View {
    @Binding var character: Character
    let onRoll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Death Saves", systemImage: "heart.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                statusBadge
            }
            HStack(spacing: 14) {
                counterRow(label: "Saves", count: character.deathSaves.successes, tint: .green) {
                    character.deathSaves.successes = $0
                }
                counterRow(label: "Fails", count: character.deathSaves.failures, tint: .red) {
                    character.deathSaves.failures = $0
                }
                Spacer()
                Button(action: onRoll) {
                    Label("Roll", systemImage: "dice")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(character.deathSaves.isStable || character.deathSaves.isDead)
            }
            Text("10+ succeeds · nat 1 = 2 fails · nat 20 = regain 1 HP")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        if character.deathSaves.isDead {
            badge("Dead", tint: .red)
        } else if character.deathSaves.isStable {
            badge("Stable", tint: .green)
        } else {
            badge("Dying", tint: .orange)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    /// Three tappable circles. Tapping circle N sets the count to N+1;
    /// re-tapping the highest filled circle takes it back down, so a mistap
    /// is undoable in place.
    private func counterRow(
        label: String,
        count: Int,
        tint: Color,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { i in
                Button {
                    set(count == i + 1 ? i : i + 1)
                } label: {
                    Image(systemName: i < count ? "circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) \(i + 1)")
            }
        }
    }
}
