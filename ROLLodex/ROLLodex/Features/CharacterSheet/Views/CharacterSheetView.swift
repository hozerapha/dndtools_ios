import SwiftUI

/// Editable character sheet. Mutations (name, HP, inventory, notes) flow back
/// through the `@Binding`, which `CharacterStore.binding(for:)` persists on
/// every set. All derived values (AC, action grid, etc.) recompute on demand.
struct CharacterSheetView: View {
    @Binding var character: Character
    @Binding var selectedTab: AppTab
    @Environment(ContentStore.self) private var content
    @Environment(PendingRollStore.self) private var pendingRoll

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                statPillRow
                AbilityBlockView(
                    character: character,
                    onRollCheck: { ability, mode in
                        dispatchRoll(.abilityCheck(ability: ability), mode: mode)
                    },
                    onRollSave: { ability, mode in
                        dispatchRoll(.savingThrow(ability: ability), mode: mode)
                    }
                )
                ActionButtonGrid(sections: actionSections, onTap: handleActionTap)
                sensesCard
                SkillListView(character: character) { skill, mode in
                    dispatchRoll(.skillCheck(skill: skill), mode: mode)
                }
                proficienciesCard
                InventoryView(character: $character)
                featuresCard
                NotesEditorView(notes: $character.notes)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var actionSections: [ActionSection] {
        CharacterActionDeriver.sections(for: character, content: content)
    }

    private func handleActionTap(_ action: ResolvedAction) {
        guard action.formula != nil else { return }
        pendingRoll.pending = action
        selectedTab = .dice
    }

    /// Resolve a recipe and hand it to the dice tab. If the user picked
    /// advantage/disadvantage, the formula's plain d20 group is expanded to
    /// 2d20kh1 / 2d20kl1 so the tray actually rolls two dice and drops one.
    private func dispatchRoll(_ recipe: ActionRecipe, mode: RollMode) {
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: character,
            weapon: nil
        )
        let formula = applyAdvantage(to: resolved.formula, mode: mode)
        // The interpreter's label includes the modifier ("Athletics +5") for
        // the on-sheet button, but in history that just duplicates the formula
        // line, so we use a cleaner recipe-based name there.
        let historyLabel = historyLabel(for: recipe) ?? resolved.label
        pendingRoll.pending = ResolvedAction(
            id: resolved.id,
            label: historyLabel,
            formula: formula,
            description: resolved.description
        )
        selectedTab = .dice
    }

    private func historyLabel(for recipe: ActionRecipe) -> String? {
        switch recipe {
        case .skillCheck(let skill):     return "\(skill.displayName) check"
        case .abilityCheck(let ability): return "\(ability.rawValue.capitalized) check"
        case .savingThrow(let ability):  return "\(ability.rawValue.capitalized) save"
        default: return nil
        }
    }

    /// Returns a copy of `base` with its first 1-die d20 group expanded to a
    /// 2d20kh1 / 2d20kl1 group. Anything else is returned unchanged — the
    /// adv/dis menu only makes sense for plain d20 rolls.
    private func applyAdvantage(to base: DiceFormula?, mode: RollMode) -> DiceFormula? {
        guard mode != .normal, var formula = base else { return base }
        guard let i = formula.groups.firstIndex(where: {
            $0.kind == .d20 && $0.count == 1 && $0.isPlain
        }) else { return formula }
        formula.groups[i].count = 2
        formula.groups[i].modifier = (mode == .advantage) ? .keepHighest(1) : .keepLowest(1)
        return formula
    }

    // MARK: - Header

    @State private var showHPEditor = false

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Inline-editable name. The TextField looks like normal text until
            // tapped, then becomes editable. Saves on each character via the
            // CharacterStore binding.
            TextField("Name", text: $character.name)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .submitLabel(.done)

            HStack(spacing: 6) {
                if let className = primaryClassName {
                    SheetBadge(text: className, systemImage: "shield.lefthalf.filled")
                }
                SheetBadge(text: "Lvl \(character.level)", systemImage: "star.circle.fill")
                if let speciesName {
                    SheetBadge(text: speciesName, systemImage: "figure")
                }
            }
            hpBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showHPEditor) {
            HPEditorSheet(character: $character)
                .presentationDetents([.medium])
        }
    }

    private var hpBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("HP", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    character.currentHP = max(0, character.currentHP - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take 1 damage")

                Text("\(character.currentHP) / \(character.maxHP)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 56)
                    .contentShape(Rectangle())
                    .onTapGesture { showHPEditor = true }

                Button {
                    character.currentHP = min(character.maxHP, character.currentHP + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Heal 1 HP")

                if character.tempHP > 0 {
                    Text("+\(character.tempHP) temp")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            ProgressView(
                value: Double(max(character.currentHP, 0)),
                total: Double(max(character.maxHP, 1))
            )
            .tint(hpTint)
        }
    }

    private var hpTint: Color {
        let frac = Double(character.currentHP) / Double(max(character.maxHP, 1))
        if frac > 0.5 { return .green }
        if frac > 0.25 { return .yellow }
        return .red
    }

    // MARK: - Stat pills

    private var statPillRow: some View {
        HStack(spacing: 10) {
            StatChip(label: "AC", value: "\(armorClass)", systemImage: "shield.fill", tint: .blue)
            StatChip(label: "Speed", value: "\(speedFt) ft", systemImage: "figure.run", tint: .orange)
            StatChip(label: "Init", value: initiativeBonus.formattedModifier, systemImage: "bolt.fill", tint: .yellow)
        }
    }

    // MARK: - Senses

    private var sensesCard: some View {
        SheetCard(title: "Senses", systemImage: "eye.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Passive Perception") {
                    Text("\(passivePerception)").monospacedDigit().font(.subheadline.weight(.semibold))
                }
                if let darkvision = darkvisionTrait {
                    LabeledContent("Darkvision") {
                        Text(darkvision.description)
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Proficiencies

    private var proficienciesCard: some View {
        SheetCard(title: "Proficiencies", systemImage: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if !armorProfs.isEmpty {
                    ProficiencyGroup(label: "Armor", values: armorProfs)
                }
                if !weaponProfs.isEmpty {
                    ProficiencyGroup(label: "Weapons", values: weaponProfs)
                }
                if !toolProfs.isEmpty {
                    ProficiencyGroup(label: "Tools", values: toolProfs)
                }
                if armorProfs.isEmpty && weaponProfs.isEmpty && toolProfs.isEmpty {
                    Text("No proficiencies").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Features

    private var featuresCard: some View {
        SheetCard(title: "Features & Traits", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(allFeatures, id: \.id) { feature in
                    FeatureRow(name: feature.name, description: feature.description)
                }
                if let backgroundFeatName {
                    FeatureRow(
                        name: backgroundFeatName.replacingOccurrences(of: "_", with: " ").capitalized,
                        description: "From background"
                    )
                }
                if allFeatures.isEmpty && backgroundFeatName == nil {
                    Text("No features yet").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Derived values

    private var primaryClassName: String? {
        character.classEntries.first.flatMap { content.classDefinition(id: $0.classID)?.name }
    }

    private var speciesName: String? {
        content.speciesDefinition(id: character.speciesID)?.name
    }

    private var speedFt: Int {
        content.speciesDefinition(id: character.speciesID)?.speed ?? 30
    }

    private var armorClass: Int {
        let dexScore = character.abilityScores[.dexterity] ?? 10
        let dexMod = CharacterCalculator.abilityModifier(score: dexScore)
        return CharacterCalculator.armorClass(
            dexMod: dexMod,
            armor: equippedArmor,
            hasShield: hasShield
        )
    }

    private var initiativeBonus: Int {
        CharacterCalculator.initiativeBonus(character: character)
    }

    private var passivePerception: Int {
        CharacterCalculator.passivePerception(character: character)
    }

    private var equippedArmor: ArmorDefinition? {
        for item in character.inventory where item.equipped {
            if let armor = content.armorDefinition(id: item.itemID),
               armor.armorCategory != .shield {
                return armor
            }
        }
        return nil
    }

    private var hasShield: Bool {
        character.inventory.contains { item in
            item.equipped &&
                content.armorDefinition(id: item.itemID)?.armorCategory == .shield
        }
    }

    private var darkvisionTrait: TraitDefinition? {
        content.speciesDefinition(id: character.speciesID)?
            .traits.first { $0.id == "darkvision" }
    }

    private var armorProfs: [String] {
        character.proficiencies.compactMap { key, level in
            guard level != .none, case .armor(let cat) = key else { return nil }
            return cat.rawValue.capitalized
        }.sorted()
    }

    private var weaponProfs: [String] {
        character.proficiencies.compactMap { key, level in
            guard level != .none, case .weapon(let cat) = key else { return nil }
            return cat.rawValue.capitalized
        }.sorted()
    }

    private var toolProfs: [String] {
        character.proficiencies.compactMap { key, level in
            guard level != .none, case .tool(let name) = key else { return nil }
            return name
        }.sorted()
    }

    /// Class features at or below current level + species traits (excluding the
    /// darkvision trait, which is already surfaced in the Senses section).
    private var allFeatures: [FeatureDefinition] {
        var features: [FeatureDefinition] = []
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            for level in 1...max(entry.level, 1) {
                features.append(contentsOf: cls.levelFeatures[level] ?? [])
            }
        }
        if let species = content.speciesDefinition(id: character.speciesID) {
            for trait in species.traits where trait.id != "darkvision" {
                features.append(FeatureDefinition(
                    id: "species_\(trait.id)",
                    name: trait.name,
                    description: trait.description,
                    actionRecipes: trait.actionRecipes
                ))
            }
        }
        return features
    }

    private var backgroundFeatName: String? {
        content.backgroundDefinition(id: character.backgroundID)?.feat
    }
}

// MARK: - Reusable bits (file-internal — used by sub-views in other files via the same module)

/// Card container with a labeled header and arbitrary content. Other sheet
/// sub-views use it for visual consistency.
struct SheetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SheetBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.18), in: Capsule())
    }
}

private struct StatChip: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(tint)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProficiencyGroup: View {
    let label: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(values.joined(separator: ", "))
                .font(.subheadline)
        }
    }
}

private struct FeatureRow: View {
    let name: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Module-wide formatting helper

extension Int {
    /// Formats an ability/skill/save modifier as "+5" or "−2". Uses U+2212 MINUS
    /// SIGN for negatives so it lines up nicely with the "+" in monospaced fonts.
    var formattedModifier: String {
        self >= 0 ? "+\(self)" : "−\(abs(self))"
    }
}
