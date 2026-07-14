import SwiftUI

/// Setup sheet for a Magic Initiate feat instance. The player picks:
///   - one of INT / WIS / CHA as this feat's spellcasting ability,
///   - two cantrips from the locked class list,
///   - one L1 spell from the same list.
///
/// Picks land under conventional keys on `character.featureSelections`:
///   - `<storageKey>_ability` (single-element array holding the picked ability)
///   - `<storageKey>_spells`  (array of picked spell IDs, mixed cantrips + L1)
///
/// The L1 spell's once-per-Long-Rest free-cast pool is synthesized by
/// `ResourceCalculator` off the standard `SpellGrant` path — nothing extra
/// to do here beyond recording the pick.
struct MagicInitiateSetupSheet: View {
    @Binding var character: Character
    /// Fixed key that identifies this Magic Initiate instance. For the
    /// background-granted case this is `Keys.background`.
    let storageKey: String
    /// The class whose spell list drives the picker (Sage → wizard,
    /// Acolyte → cleric). Locked here — the background dictates it.
    let classList: String
    /// Human-readable source label rendered in the sheet header
    /// ("Sage · Origin Feat", etc.).
    let sourceLabel: String

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    /// Storage-key conventions. Kept as a nested enum so callers (feature
    /// card wiring, spell-grant resolver) reference them symbolically.
    enum Keys {
        static let background = "background_magic_initiate"
        static func abilityKey(for storageKey: String) -> String { "\(storageKey)_ability" }
        static func spellsKey(for storageKey: String) -> String { "\(storageKey)_spells" }
    }

    private var abilityKey: String { Keys.abilityKey(for: storageKey) }
    private var spellsKey: String { Keys.spellsKey(for: storageKey) }

    private var pickedAbility: Ability? {
        (character.featureSelections[abilityKey] ?? [])
            .first.flatMap { Ability(rawValue: $0) }
    }

    private var pickedSpellIDs: [String] {
        character.featureSelections[spellsKey] ?? []
    }

    private var pickedCantrips: [String] {
        pickedSpellIDs.filter { content.spellDefinition(id: $0)?.isCantrip == true }
    }
    private var pickedLeveledSpells: [String] {
        pickedSpellIDs.filter { content.spellDefinition(id: $0)?.isCantrip == false }
    }

    private var cantripOptions: [SpellDefinition] {
        content.spells.values
            .filter { $0.isCantrip && $0.classes.contains(classList) }
            .sorted { $0.name < $1.name }
    }
    private var leveledOptions: [SpellDefinition] {
        content.spells.values
            .filter { $0.level == 1 && $0.classes.contains(classList) }
            .sorted { $0.name < $1.name }
    }

    private var isComplete: Bool {
        pickedAbility != nil
            && pickedCantrips.count == 2
            && pickedLeveledSpells.count == 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    abilitySection
                    cantripSection
                    leveledSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Magic Initiate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                        .disabled(!isComplete)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Class list: \(classList.capitalized)")
                .font(.subheadline.weight(.semibold))
            Text("Pick 2 cantrips + 1 level-1 spell from the \(classList.capitalized) spell list. Choose the ability whose modifier you'll use for these spells.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var abilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spellcasting ability")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([Ability.intelligence, .wisdom, .charisma], id: \.self) { ability in
                    abilityChip(ability)
                }
            }
        }
    }

    private func abilityChip(_ ability: Ability) -> some View {
        let selected = pickedAbility == ability
        return Button {
            character.featureSelections[abilityKey] = [ability.rawValue]
        } label: {
            Text(ability.abbreviation)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? Color.accentColor.opacity(0.22) : Color(.tertiarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
                .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var cantripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cantrips").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(pickedCantrips.count) / 2")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(pickedCantrips.count == 2 ? .green : .secondary)
            }
            ForEach(cantripOptions) { spell in
                spellRow(spell, isPicked: pickedCantrips.contains(spell.id), max: 2)
            }
            if cantripOptions.isEmpty {
                Text("No \(classList.capitalized) cantrips in the bundle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var leveledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level-1 spell").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(pickedLeveledSpells.count) / 1")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(pickedLeveledSpells.count == 1 ? .green : .secondary)
            }
            ForEach(leveledOptions) { spell in
                spellRow(spell, isPicked: pickedLeveledSpells.contains(spell.id), max: 1)
            }
            if leveledOptions.isEmpty {
                Text("No \(classList.capitalized) L1 spells in the bundle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A single toggleable spell row. Tapping selects; tapping a selected
    /// row unselects. Reaching the max (2 cantrips / 1 leveled) disables
    /// any additional un-picked rows until one is unselected.
    private func spellRow(_ spell: SpellDefinition, isPicked: Bool, max: Int) -> some View {
        let pool = spell.isCantrip ? pickedCantrips : pickedLeveledSpells
        let canPick = isPicked || pool.count < max
        return Button {
            togglePick(spell)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? Color.accentColor : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spell.name).font(.callout.weight(.semibold))
                    Text(spell.school.rawValue.capitalized + " · " + (spell.isCantrip ? "Cantrip" : "L1"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .opacity(canPick ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canPick)
    }

    private func togglePick(_ spell: SpellDefinition) {
        var picks = pickedSpellIDs
        if let idx = picks.firstIndex(of: spell.id) {
            picks.remove(at: idx)
        } else {
            picks.append(spell.id)
        }
        character.featureSelections[spellsKey] = picks
    }
}
