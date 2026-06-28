import SwiftUI

/// Sheet card listing every equipped weapon as a compact row. Each row shows
/// the weapon name, its optional mastery property (tappable for a description
/// popover), and inline icon buttons for the attack roll, the damage roll,
/// and — when applicable — the versatile (two-handed) damage roll.
///
/// Tapping the attack button queues the matching damage roll as a follow-up,
/// using the same `PendingRollStore.followUp` plumbing that spells use; the
/// player can roll the attack, see if it hit, then tap the "Roll damage?"
/// chip in the dice tab to chain the damage roll without coming back here.
struct AttacksView: View {
    let rows: [WeaponAttackRow]
    /// Called when the player taps Attack — the sheet sets up the attack +
    /// follow-up damage handoff and switches to the dice tab.
    let onAttack: (WeaponAttackRow) -> Void
    /// Called when the player taps Damage directly (no preceding attack).
    let onDamage: (ResolvedAction) -> Void

    @State private var masteryDetail: MasteryDetail?
    @State private var expanded: Bool = true

    /// Carries both the mastery and its character-resolved mechanic text into
    /// the detail sheet so it can show the filled-in numbers (Topple DC, etc.).
    struct MasteryDetail: Identifiable {
        let mastery: WeaponMastery
        let mechanic: String?
        var id: String { mastery.rawValue }
    }

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        WeaponRow(
                            row: row,
                            onMasteryTap: { mastery in
                                masteryDetail = MasteryDetail(mastery: mastery, mechanic: row.masteryMechanic)
                            },
                            onAttackTap: { onAttack(row) },
                            onDamageTap: { onDamage(row.damage) },
                            onVersatileDamageTap: row.versatileDamage.map { v in
                                { onDamage(v) }
                            }
                        )
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Attacks", systemImage: "burst")
                    .font(.headline)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .sheet(item: $masteryDetail) { detail in
                MasteryDetailSheet(mastery: detail.mastery, mechanic: detail.mechanic)
                    .presentationDetents([.fraction(0.35), .medium])
            }
        }
    }
}

private struct WeaponRow: View {
    let row: WeaponAttackRow
    let onMasteryTap: (WeaponMastery) -> Void
    let onAttackTap: () -> Void
    let onDamageTap: () -> Void
    /// Nil for non-versatile weapons.
    let onVersatileDamageTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.weaponName)
                    .font(.subheadline.weight(.semibold))
                if let mastery = row.mastery {
                    Button {
                        onMasteryTap(mastery)
                    } label: {
                        HStack(spacing: 3) {
                            Text(mastery.displayName)
                            Image(systemName: "info.circle")
                                .font(.caption2)
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mastery.displayName) mastery — tap for description")
                }
            }
            Spacer(minLength: 8)
            AttackChip(
                systemImage: "scope",
                primary: attackBonusLabel,
                accessibilityLabel: "Roll \(row.weaponName) attack",
                action: onAttackTap
            )
            AttackChip(
                systemImage: "drop.fill",
                primary: damageFormulaLabel,
                accessibilityLabel: "Roll \(row.weaponName) damage",
                action: onDamageTap
            )
            if let onVersatileDamageTap, let versatile = row.versatileDamage {
                AttackChip(
                    systemImage: "drop.fill",
                    primary: formulaLabel(versatile.formula),
                    secondary: "2H",
                    accessibilityLabel: "Roll \(row.weaponName) two-handed damage",
                    action: onVersatileDamageTap
                )
            }
        }
        .padding(.vertical, 2)
    }

    /// "+5" style modifier for the attack chip.
    private var attackBonusLabel: String {
        let mod = row.attack.formula?.modifier ?? 0
        return mod >= 0 ? "+\(mod)" : "−\(abs(mod))"
    }

    /// "1d8+3" style formula for the damage chip.
    private var damageFormulaLabel: String {
        formulaLabel(row.damage.formula)
    }

    private func formulaLabel(_ formula: DiceFormula?) -> String {
        guard let formula else { return "—" }
        let dice = formula.groups
            .map { "\($0.count)d\($0.kind.rawValue)" }
            .joined(separator: "+")
        let mod = formula.modifier
        if mod == 0 { return dice }
        return mod > 0 ? "\(dice)+\(mod)" : "\(dice)−\(abs(mod))"
    }
}

/// Pill-shaped button used inline on the weapon row. Compact enough that
/// attack + damage + optional 2H fit on a single line on iPhone.
private struct AttackChip: View {
    let systemImage: String
    let primary: String
    var secondary: String? = nil
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 0) {
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(primary)
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MasteryDetailSheet: View {
    let mastery: WeaponMastery
    /// Character-resolved mechanic ("…DC 13 Constitution save…"); nil falls
    /// back to the generic rule text only.
    let mechanic: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let mechanic {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("For this weapon")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(mechanic)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text(mastery.summary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(mastery.displayName + " Mastery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension WeaponMastery: Identifiable {
    public var id: String { rawValue }
}
