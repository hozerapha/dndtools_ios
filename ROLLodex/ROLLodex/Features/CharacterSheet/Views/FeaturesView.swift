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
    /// Direction toggle for level-based sort. Persisted so it survives
    /// re-launches. Default ascending — L1 traits and origin features up top
    /// mirror how the level-up sheet reveals features chronologically.
    @AppStorage("featuresSortDescending") private var sortDescending = false

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 14) {
                    sortToggle
                    ForEach(sortedRows) { row in
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
            // 5e multiclass rule: a class you multiclassed INTO doesn't grant
            // its L1 skill choices — hide that picker for every class after
            // the first so the player isn't offered skills they shouldn't have.
            let isFirstClass = entry.classID == character.classEntries.first?.classID
            for resolved in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                if !isFirstClass, resolved.grantedAtLevel == 1,
                   let selection = resolved.feature.selection,
                   case .skillsFrom = selection.optionsSource { continue }
                let sourceName = resolved.subclassName ?? cls.name
                let idPrefix = resolved.subclassName == nil ? "class" : "subclass"
                rows.append(FeatureRowModel(
                    id: "\(idPrefix)_\(entry.classID)_\(resolved.feature.id)",
                    feature: resolved.feature,
                    sourceLabel: "\(sourceName) · L\(resolved.grantedAtLevel)",
                    classLevel: entry.level,
                    grantedAtLevel: resolved.grantedAtLevel
                ))
            }
        }
        if let species = content.speciesDefinition(id: character.speciesID) {
            // A trait IS a FeatureDefinition, so its picker (lineage / ancestry)
            // and resource pool render through the same card as class features.
            // Species traits ride along at L1 so the sort keeps them anchored
            // to the earliest slot.
            for trait in species.traits {
                rows.append(FeatureRowModel(
                    id: "species_\(trait.id)",
                    feature: trait,
                    sourceLabel: species.name,
                    classLevel: character.level,
                    grantedAtLevel: 1
                ))
            }
        }
        // Background-granted Origin feat (SRD 5.2.1: each background locks
        // one Origin feat: Soldier → Savage Attacker, Sage/Acolyte → Magic
        // Initiate, Criminal → Alert). Synthesize a passive feature card
        // from the feat so it renders alongside class/species features.
        if let bg = content.backgroundDefinition(id: character.backgroundID),
           let featID = bg.feat,
           let feat = content.featDefinition(id: featID) {
            let feature = FeatureDefinition(
                id: "background_feat_\(featID)",
                name: feat.name,
                description: feat.description
            )
            rows.append(FeatureRowModel(
                id: "background_feat_\(featID)",
                feature: feature,
                sourceLabel: "\(bg.name) · Origin Feat",
                classLevel: character.level,
                grantedAtLevel: 1
            ))
        }
        return rows
    }

    /// Stable sort by unlock level. Swift's `sorted(by:)` is stable, so ties
    /// keep the source-derivation order (class L1 features before species
    /// L1 traits, subclasses interleaved by grant level).
    private var sortedRows: [FeatureRowModel] {
        rows.sorted { lhs, rhs in
            sortDescending
                ? lhs.grantedAtLevel > rhs.grantedAtLevel
                : lhs.grantedAtLevel < rhs.grantedAtLevel
        }
    }

    private var sortToggle: some View {
        HStack(spacing: 6) {
            Text("Sorted by level")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                sortDescending.toggle()
            } label: {
                Label(
                    sortDescending ? "High → Low" : "Low → High",
                    systemImage: sortDescending
                        ? "arrow.down.circle.fill"
                        : "arrow.up.circle.fill"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    private func resolvedPool(for feature: FeatureDefinition) -> ResolvedResource? {
        guard let def = feature.resource else { return nil }
        return ResourceCalculator.availableResources(character: character, content: content)
            .first { $0.definition.id == def.id }
    }

    private func picksCount(for selection: FeatureSelection) -> Int {
        let outer = (character.featureSelections[selection.id] ?? []).count
        // Feat picks are 2-stage: outer picks the feat, inner distributes the
        // ability bump. The outer pick doesn't count as satisfied until the
        // inner budget is fully spent — otherwise the "1 pending" banner in
        // the level-up sheet clears prematurely.
        if case .feat = selection.optionsSource, outer > 0 {
            let featID = character.featureSelections[selection.id]?.first ?? ""
            if let feat = content.featDefinition(id: featID),
               let bonus = feat.abilityScoreBonus {
                let subKey = SelectionSource.abilitySubpickKey(for: selection.id)
                let sub = (character.featureSelections[subKey] ?? []).count
                return sub >= bonus.amount ? 1 : 0
            }
        }
        return outer
    }
}

/// Internal row wrapper carrying the feature plus the source-label / class
/// level context the card needs.
private struct FeatureRowModel: Identifiable {
    let id: String
    let feature: FeatureDefinition
    let sourceLabel: String
    let classLevel: Int
    /// The class-level (or species L1) at which the feature was granted —
    /// used purely for the Features tab's sort ordering.
    let grantedAtLevel: Int
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
    @Environment(ContentStore.self) private var content

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
        // A selection whose picks are complete gets the calmer secondary tint
        // used by passive features — the eye-grabbing orange is reserved for
        // "you still need to pick".
        let calmDown = row.feature.kind == .selection && isSelectionSatisfied
        let tint = calmDown ? Color.secondary : row.feature.kind.tint
        let icon = calmDown ? "checkmark.seal.fill" : row.feature.kind.systemImage
        let badge = calmDown ? "Selected" : row.feature.kind.displayName
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.feature.name)
                    .font(.subheadline.weight(.semibold))
                Text(row.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(badge)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18), in: Capsule())
                .foregroundStyle(tint)
        }
    }

    /// True when the feature carries a selection AND every pick slot is
    /// filled at the current class level. Used to dim the orange elements —
    /// picked selections read as calmly as passive features.
    private var isSelectionSatisfied: Bool {
        guard let selection = row.feature.selection else { return false }
        let max = selection.count.value(
            classLevel: row.classLevel,
            characterLevel: row.classLevel
        )
        return picksCount >= max
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
        // Loud orange draws the eye to unfilled pickers. Once every pick is
        // in, drop to a muted "Change" affordance so the card reads as a
        // resolved feature (the picked options above already show what was
        // chosen and what it does).
        let satisfied = picksCount >= max
        VStack(alignment: .leading, spacing: 6) {
            // Show what the character has ALREADY picked (name + option
            // description) so the player doesn't have to open Change to see
            // what their choice does. Only the fixedOptions / subclass paths
            // have a name+description to show; the other picker sources are
            // handled elsewhere in the sheet (skills tab, ability card).
            pickedOptionsSummary(for: selection)
            Button {
                onEditSelection(selection, row.classLevel)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: satisfied ? "pencil" : "checklist")
                        .font(.caption)
                    Text(picksCount == 0 ? selection.prompt : "Change")
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
                .background(
                    satisfied
                        ? Color.secondary.opacity(0.10)
                        : Color.orange.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(satisfied ? Color.secondary : Color.orange)
            }
            .buttonStyle(.plain)
        }
    }

    /// Inline "you picked …" line(s) for the selection. Shows the picked
    /// option's name + description for `.fixedOptions` (Fighting Style,
    /// Primal Order, Metamagic) and the picked subclass for `.subclasses`.
    /// Renders nothing for `.weapons`, `.skills`, `.abilityScoreIncrease`
    /// selections since the picks land elsewhere on the sheet (attacks,
    /// skills table, ability card) — surfacing them here would duplicate.
    @ViewBuilder
    private func pickedOptionsSummary(for selection: FeatureSelection) -> some View {
        let pickedIDs = character.featureSelections[selection.id] ?? []
        if pickedIDs.isEmpty {
            EmptyView()
        } else {
            switch selection.optionsSource {
            case .fixedOptions(let options):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(options.filter { pickedIDs.contains($0.id) }) { opt in
                        pickedOptionRow(name: opt.name, description: opt.description)
                    }
                }
            case .subclasses(let parentClassID):
                if let picked = pickedIDs.first,
                   let sub = content.classDefinition(id: parentClassID)?
                                    .subclasses.first(where: { $0.id == picked }) {
                    pickedOptionRow(name: sub.name, description: sub.description)
                }
            case .feat:
                if let picked = pickedIDs.first,
                   let feat = content.featDefinition(id: picked) {
                    pickedOptionRow(name: feat.name, description: featSummary(feat, selectionID: selection.id))
                }
            default:
                EmptyView()
            }
        }
    }

    /// Compose a summary line for a picked feat that includes any ability
    /// sub-picks (e.g. "Ability Score Improvement — +2 STR"). Falls back to
    /// the feat description when the feat has no bump or no sub-picks yet.
    private func featSummary(_ feat: FeatDefinition, selectionID: String) -> String {
        guard feat.abilityScoreBonus != nil else { return feat.description }
        let subKey = SelectionSource.abilitySubpickKey(for: selectionID)
        let picks = character.featureSelections[subKey] ?? []
        guard !picks.isEmpty else { return "Pick ability score bump →" }
        let counts = Dictionary(grouping: picks, by: { $0 }).mapValues(\.count)
        let parts = counts
            .compactMap { key, count -> String? in
                guard let ability = Ability(rawValue: key) else { return nil }
                return "+\(count) \(ability.abbreviation)"
            }
            .sorted()
        return parts.joined(separator: ", ")
    }

    private func pickedOptionRow(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(name)
                    .font(.caption.weight(.semibold))
            }
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
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
        case .skills(let proficientOnly):
            SkillSelectionList(
                character: $character,
                selectionID: selection.id,
                max: maxPicks,
                proficientOnly: proficientOnly
            )
        case .skillsFrom(let options):
            SkillSelectionList(
                character: $character,
                selectionID: selection.id,
                max: maxPicks,
                proficientOnly: false,
                explicitOptions: options
            )
        case .feat(let category):
            FeatSelectionList(
                character: $character,
                selectionID: selection.id,
                category: category,
                characterLevel: classLevel
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
    /// Restrict the row list to a subset of abilities (Grappler → STR/DEX,
    /// Boon of Spell Recall → INT/WIS/CHA). Nil = every ability (default ASI).
    var allowedAbilities: [Ability]? = nil
    /// Per-ability cap. Default 20 for General feats; Epic Boons raise to 30.
    var scoreCeiling: Int = Character.abilityScoreCeiling

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(rowAbilities, id: \.self) { ability in
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

    private var rowAbilities: [Ability] {
        allowedAbilities ?? Ability.allCases
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
            perAbilityMax: perAbilityMax,
            ceiling: scoreCeiling
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
            && score < scoreCeiling
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

// MARK: - Feat Selection List

/// Picker for `.feat(category)` selections. Renders the eligible feats
/// (post-prereq filter) as tappable cards; on pick, the feat's id lands in
/// `featureSelections[selectionID]`. If the picked feat has an
/// `abilityScoreBonus`, a second step appears inline to distribute the
/// bump — reusing the ASI point-buy list scoped to the feat's ability list.
/// Switching feats first rolls back the previous feat's ability picks so
/// the character's scores stay consistent with the persisted selection.
private struct FeatSelectionList: View {
    @Binding var character: Character
    let selectionID: String
    let category: FeatCategory
    let characterLevel: Int

    @Environment(ContentStore.self) private var content

    private var pickedFeatID: String? {
        character.featureSelections[selectionID]?.first
    }

    private var pickedFeat: FeatDefinition? {
        pickedFeatID.flatMap { content.featDefinition(id: $0) }
    }

    private var abilitySubpickKey: String {
        SelectionSource.abilitySubpickKey(for: selectionID)
    }

    private var eligibleFeats: [FeatDefinition] {
        content.feats(in: category).filter { meetsPrerequisites($0) }
    }

    /// Structured prereq gate. Any-of ability scores means the character
    /// meets the prereq if AT LEAST ONE listed score is at the threshold.
    /// A feat that requires "the Fighting Style Feature" is considered met
    /// when the picker itself is granting a Fighting Style feat — the
    /// picker IS the feature. Spellcasting prereqs are deferred to the
    /// Epic Boon picker (task #24) where they carry mechanical weight.
    private func meetsPrerequisites(_ feat: FeatDefinition) -> Bool {
        let p = feat.prerequisites
        if let min = p.minLevel, characterLevel < min { return false }
        if !p.minAbilityScoresAnyOf.isEmpty {
            let anyMet = p.minAbilityScoresAnyOf.contains { key, threshold in
                guard let ability = Ability(rawValue: key) else { return false }
                return (character.abilityScores[ability] ?? 10) >= threshold
            }
            if !anyMet { return false }
        }
        if p.requiresFightingStyleFeature, category != .fightingStyle {
            return false
        }
        if p.requiresSpellcastingFeature, !characterHasSpellcasting {
            return false
        }
        return true
    }

    private var characterHasSpellcasting: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting != nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let feat = pickedFeat {
                    pickedFeatCard(feat)
                    if let bonus = feat.abilityScoreBonus {
                        abilityStep(feat: feat, bonus: bonus)
                    }
                    changeButton
                } else {
                    ForEach(eligibleFeats) { feat in
                        featCard(feat)
                    }
                    if eligibleFeats.isEmpty {
                        Text("No eligible \(category.displayName.lowercased()) feats.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
        }
    }

    private func featCard(_ feat: FeatDefinition) -> some View {
        Button {
            selectFeat(feat)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(feat.name).font(.headline)
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
                Text(feat.description)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func pickedFeatCard(_ feat: FeatDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(feat.name).font(.headline)
            }
            if !feat.prerequisiteText.isEmpty {
                Text(feat.prerequisiteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(feat.description)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func abilityStep(feat: FeatDefinition, bonus: FeatAbilityBonus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(abilityStepHeading(bonus))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AbilityScoreIncreaseList(
                character: $character,
                selectionID: abilitySubpickKey,
                totalPoints: bonus.amount,
                perAbilityMax: perAbilityMax(for: bonus),
                allowedAbilities: bonus.abilities,
                scoreCeiling: feat.abilityScoreCapOverride ?? Character.abilityScoreCeiling
            )
            .frame(minHeight: CGFloat(bonus.abilities.count) * 68 + 40)
        }
    }

    private func abilityStepHeading(_ bonus: FeatAbilityBonus) -> String {
        let names = bonus.abilities.map(\.abbreviation).joined(separator: " / ")
        switch bonus.distribute {
        case .oneAbility:
            return "+\(bonus.amount) to one of \(names)"
        case .pointBuy:
            return "Distribute \(bonus.amount) points across \(names)"
        }
    }

    private func perAbilityMax(for bonus: FeatAbilityBonus) -> Int {
        switch bonus.distribute {
        case .oneAbility: return bonus.amount
        case .pointBuy:   return bonus.amount
        }
    }

    private var changeButton: some View {
        Button {
            clearFeat()
        } label: {
            Label("Change feat", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    private func selectFeat(_ feat: FeatDefinition) {
        var copy = character
        // Clear any prior ability sub-picks from a previous feat before
        // recording the new outer pick.
        copy.resetASIPicks(selectionID: abilitySubpickKey)
        copy.featureSelections[selectionID] = [feat.id]
        character = copy
    }

    private func clearFeat() {
        var copy = character
        copy.resetASIPicks(selectionID: abilitySubpickKey)
        copy.featureSelections[selectionID] = []
        character = copy
    }
}

// MARK: - Skill Selection List

private struct SkillSelectionList: View {
    @Binding var character: Character
    let selectionID: String
    let max: Int
    let proficientOnly: Bool
    /// When set (`.skillsFrom`), the picker offers exactly these skills (a
    /// class's level-1 list). Nil falls back to the full list / proficient
    /// filter (`.skills`, used by Expertise).
    var explicitOptions: [Skill]? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(eligibleSkills, id: \.self) { skill in
                    skillRow(skill)
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

    private var eligibleSkills: [Skill] {
        if let explicitOptions {
            return explicitOptions.sorted { $0.displayName < $1.displayName }
        }
        let all = Skill.allCases.sorted { $0.displayName < $1.displayName }
        guard proficientOnly else { return all }
        // Resolve via the calculator so a skill made proficient by a class
        // skill-choice (not stored in `proficiencies`) is still expertise-able.
        return all.filter { skill in
            CharacterCalculator.skillProficiencyLevel(character: character, skill: skill) != .none
        }
    }

    private var picks: [String] {
        character.featureSelections[selectionID] ?? []
    }

    private func isPicked(_ skill: Skill) -> Bool {
        picks.contains(skill.rawValue)
    }

    private func togglePick(_ skill: Skill) {
        var current = picks
        if let i = current.firstIndex(of: skill.rawValue) {
            current.remove(at: i)
        } else if current.count < max {
            current.append(skill.rawValue)
        } else {
            return
        }
        character.featureSelections[selectionID] = current
    }

    /// Why this skill is locked in the current picker (nil = selectable). A
    /// pick shouldn't re-grant something the character already has from another
    /// source, so the gate depends on what this picker grants:
    /// - **Class-skill grant** (`.skillsFrom`): lock a skill already proficient
    ///   anywhere (background, or another class-skill selection).
    /// - **Expertise** (`.skills`, proficient-only): lock a skill that already
    ///   has expertise from another expertise selection (Rogue L1+L6, Bard
    ///   L2+L9, …) or stored expertise. The current picker's own picks stay
    ///   selectable (so they can be toggled off) via the `key != selectionID`
    ///   guard. Marker-driven, so it works for any class without naming IDs.
    private func lockReason(_ skill: Skill) -> String? {
        if explicitOptions != nil {
            if (character.proficiencies[.skill(skill)] ?? .none) != .none { return "Already proficient" }
            let elsewhere = character.featureSelections.contains { key, values in
                key != selectionID
                    && key.contains(FeatureIDs.classSkillsMarker)
                    && values.contains(skill.rawValue)
            }
            return elsewhere ? "Already proficient" : nil
        }
        if proficientOnly {
            if character.proficiencies[.skill(skill)] == .expertise { return "Already expertise" }
            let elsewhere = character.featureSelections.contains { key, values in
                key != selectionID
                    && key.contains(FeatureIDs.expertiseMarker)
                    && values.contains(skill.rawValue)
            }
            return elsewhere ? "Already expertise" : nil
        }
        return nil
    }

    @ViewBuilder
    private func skillRow(_ skill: Skill) -> some View {
        let reason = lockReason(skill)
        let locked = reason != nil
        Button {
            togglePick(skill)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPicked(skill) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked(skill) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("(\(skill.ability.abbreviation))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
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
