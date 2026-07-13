import SwiftUI

/// Read-only browser for every bundled feat, grouped by SRD category.
/// Reached from Settings → About. Provides the player with a reference
/// alongside the pickers that will land in later tasks — the same content,
/// browsable without a character context.
struct FeatCatalogView: View {
    @Environment(ContentStore.self) private var content

    var body: some View {
        List {
            ForEach(FeatCategory.allCases, id: \.self) { category in
                let feats = content.feats(in: category)
                if !feats.isEmpty {
                    Section {
                        ForEach(feats) { feat in
                            NavigationLink {
                                FeatDetailView(feat: feat)
                            } label: {
                                FeatCatalogRow(feat: feat)
                            }
                        }
                    } header: {
                        Text(category.displayName)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Feats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatCatalogRow: View {
    let feat: FeatDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(feat.name).font(.body)
                if feat.repeatable {
                    Text("Repeatable")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if !feat.prerequisiteText.isEmpty {
                Text(feat.prerequisiteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Single-feat reference sheet. Renders the SRD description verbatim above
/// a compact "mechanical hooks" summary. Anything the app can enforce shows
/// as a bullet; the rest remains honor-system prose in the description.
struct FeatDetailView: View {
    let feat: FeatDefinition

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                Text(feat.description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if !mechanicalHooks.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mechanical hooks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(mechanicalHooks, id: \.self) { hook in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(hook)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(feat.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(feat.category.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryTint.opacity(0.18), in: Capsule())
                    .foregroundStyle(categoryTint)
                if feat.repeatable {
                    Text("Repeatable")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if !feat.prerequisiteText.isEmpty {
                Text("Prerequisite: \(feat.prerequisiteText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryTint: Color {
        switch feat.category {
        case .origin:        return .green
        case .general:       return .blue
        case .fightingStyle: return .orange
        case .epicBoon:      return .purple
        }
    }

    private var mechanicalHooks: [String] {
        var hooks: [String] = []
        if let bonus = feat.abilityScoreBonus {
            let names = bonus.abilities.map(\.abbreviation).joined(separator: " / ")
            let cap = feat.abilityScoreCapOverride ?? 20
            let shape = bonus.distribute == .oneAbility
                ? "+\(bonus.amount) to one of \(names) (max \(cap))"
                : "Distribute \(bonus.amount) points across \(names) (max \(cap))"
            hooks.append(shape)
        }
        if feat.initiativeProficiencyBonus {
            hooks.append("Adds Proficiency Bonus to Initiative")
        }
        if feat.skillOrToolProficiencyCount > 0 {
            hooks.append("Pick \(feat.skillOrToolProficiencyCount) skills or tools")
        }
        if let range = feat.truesightRange {
            hooks.append("Truesight \(range) ft")
        }
        if feat.armorClassBonusInArmor > 0 {
            hooks.append("+\(feat.armorClassBonusInArmor) AC while wearing armor")
        }
        if feat.rangedAttackBonus > 0 {
            hooks.append("+\(feat.rangedAttackBonus) to Ranged weapon attack rolls")
        }
        if feat.grantsGWFDamageReroll {
            hooks.append("Treats 1s and 2s as 3s on two-handed melee damage dice")
        }
        if feat.grantsTWFOffHandModifier {
            hooks.append("Ability modifier applies to Light-weapon extra attack damage")
        }
        if let mi = feat.magicInitiate {
            let list = mi.classListOptions.map { $0.capitalized }.joined(separator: " / ")
            hooks.append("\(mi.cantripCount) cantrips + \(mi.leveledSpellCount) L\(mi.leveledSpellLevel) spell from \(list) list")
            if mi.leveledSpellHasFreeCast {
                hooks.append("Leveled spell: once-per-Long-Rest free cast")
            }
        }
        return hooks
    }
}

