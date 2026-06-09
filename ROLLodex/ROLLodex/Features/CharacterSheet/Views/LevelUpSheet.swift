import SwiftUI

/// Guided level-up flow. Player picks how to gain HP (roll the class hit die
/// or take the average), the sheet stages the gain, and the Finish button
/// commits the level bump together with the HP delta. Selection prompts
/// granted at the new level are listed as a reminder; the Features tab
/// hosts the actual pickers (existing Slice A surface).
///
/// v1 single-class only: levels the first `ClassEntry`. Multi-class will
/// gain a class picker in a later slice.
struct LevelUpSheet: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    /// Set when the player picks "Roll" — opaque inline d{hitDie}.
    @State private var stagedRoll: Int?
    /// Set when the player picks "Take Average" — locks the staged gain.
    @State private var usedAverage: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    levelHeader
                    hpGainCard
                    if unresolvedPromptsCount > 0 {
                        pendingPicksBanner
                    }
                    if hasNewFeatures {
                        newFeaturesCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Level Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { commit() }
                        .bold()
                        .disabled(stagedHPGain == nil || classEntry == nil)
                }
            }
        }
    }

    // MARK: - Sections

    private var levelHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Level \(character.level) → \(newCharacterLevel)")
                .font(.title2.bold().monospacedDigit())
            if let cls = classDef, let entry = classEntry {
                Text("\(cls.name) · Class Level \(entry.level) → \(newClassLevel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hpGainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hit Points", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("Hit Die: 1d\(hitDie) + CON (\(conMod.formattedModifier))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                rollButton
                averageButton
            }
            if let gain = stagedHPGain {
                stagedSummary(gain: gain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rollButton: some View {
        Button {
            stagedRoll = Int.random(in: 1...hitDie)
            usedAverage = false
        } label: {
            VStack(spacing: 2) {
                Label("Roll", systemImage: "dice.fill")
                    .font(.subheadline.weight(.semibold))
                Text("1d\(hitDie)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(stagedHPGain != nil)
    }

    private var averageButton: some View {
        let dieAverage = hitDie / 2 + 1
        return Button {
            usedAverage = true
            stagedRoll = nil
        } label: {
            VStack(spacing: 2) {
                Label("Take Avg", systemImage: "equal")
                    .font(.subheadline.weight(.semibold))
                Text("\(dieAverage)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .disabled(stagedHPGain != nil)
    }

    private func stagedSummary(gain: Int) -> some View {
        let dieValue = stagedRoll ?? (hitDie / 2 + 1)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(usedAverage ? "Average \(dieValue)" : "Rolled \(dieValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("+\(gain) HP (max \(character.maxHP) → \(character.maxHP + gain))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Reset") {
                stagedRoll = nil
                usedAverage = false
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var pendingPicksBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .foregroundStyle(.orange)
            Text("\(unresolvedPromptsCount) selection\(unresolvedPromptsCount == 1 ? "" : "s") still pending — fill them in the Features tab after finishing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var newFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("New at \(classDef?.name ?? "this class") L\(newClassLevel)", systemImage: "sparkles")
                .font(.headline)
            ForEach(Array(newFeatures.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.feature.name)
                            .font(.subheadline.weight(.semibold))
                        if let sub = entry.subclassName {
                            Text(sub)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.18), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    Text(entry.feature.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Commit

    private func commit() {
        guard let dieGain = stagedDieGain, let entry = classEntry else { return }
        var copy = character
        // Die-only value — applyLevelUp banks it into rolledHP and
        // recalculateHP() layers the CON share on retroactively.
        CharacterCalculator.applyLevelUp(to: &copy, hpGain: dieGain, classID: entry.classID)
        applyNewFeatureProficiencies(to: &copy)
        character = copy
        dismiss()
    }

    /// Scan features that are new at the upcoming class level and apply any
    /// automatic proficiency grants (e.g. Rogue's Slippery Mind → WIS/CHA saves).
    private func applyNewFeatureProficiencies(to character: inout Character) {
        guard let cls = classDef, let entry = classEntry else { return }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: entry.classID)
        ]?.first
        // Base-class features new at this level
        for feature in cls.levelFeatures[newClassLevel] ?? [] {
            for key in feature.grantsProficiencies ?? [] {
                character.proficiencies[key] = .proficient
            }
        }
        // Subclass features new at this level
        if let subclassID, let subclass = cls.subclasses.first(where: { $0.id == subclassID }) {
            for feature in subclass.levelFeatures[newClassLevel] ?? [] {
                for key in feature.grantsProficiencies ?? [] {
                    character.proficiencies[key] = .proficient
                }
            }
        }
    }

    // MARK: - Derived state

    /// First class entry — v1 single-class assumption.
    private var classEntry: ClassEntry? { character.classEntries.first }
    private var classDef: ClassDefinition? {
        classEntry.flatMap { content.classDefinition(id: $0.classID) }
    }

    private var newClassLevel: Int { (classEntry?.level ?? 1) + 1 }
    private var newCharacterLevel: Int { character.level + 1 }
    private var hitDie: Int { classDef?.hitDie.rawValue ?? 8 }
    private var conMod: Int {
        CharacterCalculator.abilityModifier(score: character.abilityScores[.constitution] ?? 10)
    }

    /// Die-only value to bank into `rolledHP` — the roll itself or the die
    /// average, WITHOUT the CON modifier (CON is applied retroactively by
    /// `recalculateHP()` during commit).
    private var stagedDieGain: Int? {
        if let r = stagedRoll { return r }
        if usedAverage { return hitDie / 2 + 1 }
        return nil
    }

    /// What the player sees as this level's HP change: die value + CON mod.
    /// Display only — the commit path goes through `stagedDieGain`.
    private var stagedHPGain: Int? {
        stagedDieGain.map { $0 + conMod }
    }

    /// Selection prompts the character hasn't filled to capacity, across all
    /// levels through `newClassLevel`. Used for the "pending picks" banner.
    private var unresolvedPromptsCount: Int {
        guard let cls = classDef, let entry = classEntry else { return 0 }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: entry.classID)
        ]?.first
        var count = 0
        for resolved in cls.resolvedFeatures(throughClassLevel: newClassLevel, subclassID: subclassID) {
            guard let selection = resolved.feature.selection else { continue }
            let max = selection.count.value(
                classLevel: newClassLevel,
                characterLevel: newCharacterLevel
            )
            let picks = (character.featureSelections[selection.id] ?? []).count
            if picks < max { count += 1 }
        }
        return count
    }

    /// Features new at the upcoming class level — both base-class additions
    /// and (once a subclass is picked) new subclass level-features.
    private var newFeatures: [(feature: FeatureDefinition, subclassName: String?)] {
        guard let cls = classDef, let entry = classEntry else { return [] }
        var out: [(FeatureDefinition, String?)] = []
        for feature in cls.levelFeatures[newClassLevel] ?? [] {
            out.append((feature, nil))
        }
        let subclassID = character.featureSelections[
            ClassDefinition.subclassSelectionID(forClassID: entry.classID)
        ]?.first
        if let subclassID, let subclass = cls.subclasses.first(where: { $0.id == subclassID }) {
            for feature in subclass.levelFeatures[newClassLevel] ?? [] {
                out.append((feature, subclass.name))
            }
        }
        return out
    }

    private var hasNewFeatures: Bool { !newFeatures.isEmpty }
}
