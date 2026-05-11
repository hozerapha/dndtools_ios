import SwiftUI

/// Sheet card listing every feature a character has access to — class
/// features at or below their level, plus species traits — alongside the
/// state knobs each one exposes. Data comes entirely from the bundled
/// JSON: a feature with a `resource` shows current/max, a feature with a
/// `selection` shows a picker chip, and all features show their description.
struct FeaturesView: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true
    @State private var editingSelection: PendingSelection?

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 14) {
                    ForEach(rows) { row in
                        FeatureCard(
                            character: character,
                            row: row,
                            resolvedPool: resolvedPool(for: row.feature),
                            picksCount: row.feature.selection.map { picksCount(for: $0) } ?? 0,
                            onEditSelection: { selection, classLevel in
                                editingSelection = PendingSelection(
                                    featureID: row.id,
                                    selection: selection,
                                    classLevel: classLevel,
                                    sourceLabel: row.sourceLabel
                                )
                            }
                        )
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Features", systemImage: "sparkles")
                    .font(.headline)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .sheet(item: $editingSelection) { pending in
                SelectionSheet(
                    character: $character,
                    selection: pending.selection,
                    classLevel: pending.classLevel,
                    sourceLabel: pending.sourceLabel
                )
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Row derivation

    /// Class features (at or below each class entry's level) followed by
    /// species traits. Traits are wrapped into a synthesized
    /// `FeatureDefinition` so the card UI stays uniform.
    private var rows: [FeatureRowModel] {
        var rows: [FeatureRowModel] = []
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                let sourceName = resolved.subclassName ?? cls.name
                let idPrefix = resolved.subclassName == nil ? "class" : "subclass"
                rows.append(FeatureRowModel(
                    id: "\(idPrefix)_\(entry.classID)_\(resolved.feature.id)",
                    feature: resolved.feature,
                    sourceLabel: "\(sourceName) · L\(resolved.grantedAtLevel)",
                    classLevel: entry.level
                ))
            }
        }
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits {
                let synthesized = FeatureDefinition(
                    id: trait.id,
                    name: trait.name,
                    description: trait.description,
                    actionRecipes: trait.actionRecipes
                )
                rows.append(FeatureRowModel(
                    id: "species_\(trait.id)",
                    feature: synthesized,
                    sourceLabel: species.name,
                    classLevel: character.level
                ))
            }
        }
        return rows
    }

    private func resolvedPool(for feature: FeatureDefinition) -> ResolvedResource? {
        guard let def = feature.resource else { return nil }
        return ResourceCalculator.availableResources(character: character, content: content)
            .first { $0.definition.id == def.id }
    }

    private func picksCount(for selection: FeatureSelection) -> Int {
        (character.featureSelections[selection.id] ?? []).count
    }
}

/// Internal row wrapper carrying the feature plus the source-label / class
/// level context the card needs.
private struct FeatureRowModel: Identifiable {
    let id: String
    let feature: FeatureDefinition
    let sourceLabel: String
    let classLevel: Int
}

/// Payload for the `.sheet(item:)` binding when the player opens a picker.
private struct PendingSelection: Identifiable {
    let id = UUID()
    let featureID: String
    let selection: FeatureSelection
    let classLevel: Int
    let sourceLabel: String
}

private struct FeatureCard: View {
    let character: Character
    let row: FeatureRowModel
    let resolvedPool: ResolvedResource?
    let picksCount: Int
    let onEditSelection: (FeatureSelection, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(row.feature.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let pool = resolvedPool {
                resourceBlock(pool)
            }
            if let selection = row.feature.selection {
                selectionBlock(selection)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: row.feature.kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.feature.kind.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.feature.name)
                    .font(.subheadline.weight(.semibold))
                Text(row.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(row.feature.kind.displayName)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(row.feature.kind.tint.opacity(0.18), in: Capsule())
                .foregroundStyle(row.feature.kind.tint)
        }
    }

    @ViewBuilder
    private func resourceBlock(_ pool: ResolvedResource) -> some View {
        HStack(spacing: 8) {
            Text(pool.definition.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(pool.current) / \(pool.max)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(pool.isExhausted ? .secondary : .primary)
        }
    }

    @ViewBuilder
    private func selectionBlock(_ selection: FeatureSelection) -> some View {
        let max = selection.count.value(
            classLevel: row.classLevel,
            characterLevel: row.classLevel
        )
        Button {
            onEditSelection(selection, row.classLevel)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption)
                Text(selection.prompt)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(picksCount) / \(max)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.background, in: Capsule())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.orange)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selection sheet

/// Modal for editing the picks of one `FeatureSelection`. The picker UI
/// switches on `optionsSource`: weapons show a checklist filtered by
/// proficiency. Future cases (spells, skills, free-form lists) plug in here.
struct SelectionSheet: View {
    @Binding var character: Character
    let selection: FeatureSelection
    let classLevel: Int
    let sourceLabel: String

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            body(for: selection.optionsSource)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(selection.prompt)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(sourceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.bold()
                    }
                }
        }
    }

    @ViewBuilder
    private func body(for source: SelectionSource) -> some View {
        switch source {
        case .weapons(let proficientOnly):
            WeaponSelectionList(
                character: $character,
                selectionID: selection.id,
                max: maxPicks,
                proficientOnly: proficientOnly
            )
        case .fixedOptions(let options):
            FixedOptionsSelectionList(
                character: $character,
                selectionID: selection.id,
                max: maxPicks,
                options: options
            )
        case .subclasses(let parentClassID):
            SubclassSelectionList(
                character: $character,
                selectionID: selection.id,
                parentClassID: parentClassID
            )
        case .abilityScoreIncrease(let perAbilityMax):
            AbilityScoreIncreaseList(
                character: $character,
                selectionID: selection.id,
                totalPoints: maxPicks,
                perAbilityMax: perAbilityMax
            )
        }
    }

    private var maxPicks: Int {
        selection.count.value(classLevel: classLevel, characterLevel: classLevel)
    }
}

/// Checklist for `.weapons` selection sources. Each row is a weapon name,
/// its mastery property (when present), and a check mark. Tapping toggles
/// the id in `character.featureSelections[selectionID]` up to `max`.
private struct WeaponSelectionList: View {
    @Binding var character: Character
    let selectionID: String
    let max: Int
    let proficientOnly: Bool

    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(eligibleWeapons, id: \.id) { weapon in
                    weaponRow(weapon)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Text("Picked \(picks.count) of \(max)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
        }
    }

    private var eligibleWeapons: [WeaponDefinition] {
        let all = Array(content.weapons.values).sorted { $0.name < $1.name }
        guard proficientOnly else { return all }
        return all.filter { weapon in
            let level = character.proficiencies[.weapon(weapon.weaponCategory)] ?? .none
            return level == .proficient || level == .expertise
        }
    }

    private var picks: [String] {
        character.featureSelections[selectionID] ?? []
    }

    private func isPicked(_ weapon: WeaponDefinition) -> Bool {
        picks.contains(weapon.id)
    }

    private func togglePick(_ weapon: WeaponDefinition) {
        var current = picks
        if let i = current.firstIndex(of: weapon.id) {
            current.remove(at: i)
        } else if current.count < max {
            current.append(weapon.id)
        } else {
            return
        }
        character.featureSelections[selectionID] = current
    }

    @ViewBuilder
    private func weaponRow(_ weapon: WeaponDefinition) -> some View {
        Button {
            togglePick(weapon)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPicked(weapon) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked(weapon) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weapon.name)
                        .font(.subheadline.weight(.semibold))
                    if let mastery = weapon.masteryProperty {
                        Text("Mastery: \(mastery.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No mastery property")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(weapon.weaponCategory.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(weapon.masteryProperty == nil)
        .opacity(weapon.masteryProperty == nil ? 0.45 : 1)
    }
}

/// Picker for a `.fixedOptions` selection (Fighting Style, etc.). When `max`
/// is 1 the list acts like a radio group — tapping a different option swaps
/// the pick rather than ignoring the tap.
private struct FixedOptionsSelectionList: View {
    @Binding var character: Character
    let selectionID: String
    let max: Int
    let options: [SelectionOption]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(options) { option in
                    optionRow(option)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Text(headerLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
        }
    }

    private var headerLabel: String {
        max == 1 ? "Pick one" : "Picked \(picks.count) of \(max)"
    }

    private var picks: [String] {
        character.featureSelections[selectionID] ?? []
    }

    private func isPicked(_ option: SelectionOption) -> Bool {
        picks.contains(option.id)
    }

    /// Radio behavior at max=1 (tap to swap); checklist behavior above that.
    private func togglePick(_ option: SelectionOption) {
        if max == 1 {
            character.featureSelections[selectionID] = isPicked(option) ? [] : [option.id]
            return
        }
        var current = picks
        if let i = current.firstIndex(of: option.id) {
            current.remove(at: i)
        } else if current.count < max {
            current.append(option.id)
        } else {
            return
        }
        character.featureSelections[selectionID] = current
    }

    @ViewBuilder
    private func optionRow(_ option: SelectionOption) -> some View {
        Button {
            togglePick(option)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isPicked(option) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked(option) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(.subheadline.weight(.semibold))
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Radio-style picker for choosing a subclass. Lists every subclass declared
/// on the parent class, with name + description rows. Tap to swap (max = 1).
private struct SubclassSelectionList: View {
    @Binding var character: Character
    let selectionID: String
    let parentClassID: String

    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if subclasses.isEmpty {
                    Text("No subclasses authored yet for this class.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(subclasses) { sub in
                        row(sub)
                    }
                }
            }
            .padding()
        }
    }

    private var subclasses: [SubclassDefinition] {
        content.classDefinition(id: parentClassID)?.subclasses ?? []
    }

    private var pickedID: String? {
        character.featureSelections[selectionID]?.first
    }

    private func isPicked(_ sub: SubclassDefinition) -> Bool { pickedID == sub.id }

    private func togglePick(_ sub: SubclassDefinition) {
        if isPicked(sub) {
            character.featureSelections[selectionID] = []
        } else {
            character.featureSelections[selectionID] = [sub.id]
        }
    }

    private func row(_ sub: SubclassDefinition) -> some View {
        Button { togglePick(sub) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isPicked(sub) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked(sub) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.name)
                        .font(.subheadline.weight(.semibold))
                    Text(sub.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Ability-Score Improvement picker. Distributes `totalPoints` across the six
/// abilities, capped at `perAbilityMax` per ability. Each row shows the
/// current effective score with `-` / `+` steppers; both halves stay disabled
/// when the constraint they'd break is in force. Mutates `character.abilityScores`
/// inline so spell save DCs, attack bonuses, etc. see the bump immediately.
private struct AbilityScoreIncreaseList: View {
    @Binding var character: Character
    let selectionID: String
    let totalPoints: Int
    let perAbilityMax: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Ability.allCases, id: \.self) { ability in
                    row(for: ability)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Text("Points spent: \(picks.count) / \(totalPoints)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
        }
    }

    private var picks: [String] {
        character.featureSelections[selectionID] ?? []
    }

    private func picks(for ability: Ability) -> Int {
        picks.filter { $0 == ability.rawValue }.count
    }

    private func increment(_ ability: Ability) {
        var copy = character
        copy.applyASIIncrement(
            ability: ability,
            selectionID: selectionID,
            totalPoints: totalPoints,
            perAbilityMax: perAbilityMax
        )
        character = copy
    }

    private func decrement(_ ability: Ability) {
        var copy = character
        copy.applyASIDecrement(ability: ability, selectionID: selectionID)
        character = copy
    }

    private func row(for ability: Ability) -> some View {
        let score = character.abilityScores[ability] ?? 10
        let picksHere = picks(for: ability)
        let canIncrement = picks.count < totalPoints
            && picksHere < perAbilityMax
            && score < Character.abilityScoreCeiling
        let canDecrement = picksHere > 0

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ability.rawValue.uppercased().prefix(3))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(score)")
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(width: 56, alignment: .leading)
            Spacer()
            if picksHere > 0 {
                Text("+\(picksHere)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.22), in: Capsule())
                    .foregroundStyle(.green)
            }
            Button {
                decrement(ability)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!canDecrement)
            .opacity(canDecrement ? 1 : 0.3)

            Button {
                increment(ability)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
            .opacity(canIncrement ? 1 : 0.3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - FeatureKind UI

private extension FeatureKind {
    var displayName: String {
        switch self {
        case .passive:   return "Passive"
        case .active:    return "Active"
        case .selection: return "Selection"
        case .toggle:    return "Toggle"
        }
    }

    var systemImage: String {
        switch self {
        case .passive:   return "text.alignleft"
        case .active:    return "bolt.circle.fill"
        case .selection: return "checklist"
        case .toggle:    return "switch.2"
        }
    }

    var tint: Color {
        switch self {
        case .passive:   return .secondary
        case .active:    return .blue
        case .selection: return .orange
        case .toggle:    return .purple
        }
    }
}
