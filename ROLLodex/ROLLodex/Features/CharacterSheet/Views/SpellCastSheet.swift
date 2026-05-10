import SwiftUI

/// Single-stage spell modal. The rolls are visible immediately as separate
/// buttons (Roll Spell Attack, Roll Damage, Roll Heal) so the player can fire
/// each one with a single tap — no Cast confirmation step.
///
/// For leveled spells the slot is consumed lazily on the first roll tap (so
/// dismissing the sheet without rolling spends nothing); the slot picker then
/// locks to the chosen level. Cantrips skip slot logic entirely.
///
/// When the player taps Spell Attack and the spell also has a damage roll, the
/// damage action is handed to the dice tab as a `followUp`; the tab surfaces a
/// "Roll damage?" chip after the attack settles.
struct SpellCastSheet: View {
    @Binding var character: Character
    let spell: SpellDefinition
    /// When non-nil, this cast is paid from an item's charge pool — the slot
    /// picker shows charge costs per level and the consumed pool is the item's
    /// resource, not the character's spell slots.
    let itemContext: ItemSpellCastContext?
    /// Called for each roll tap. `followUp` is non-nil when the primary roll
    /// has a natural next step (attack → damage); the dice tab parks it until
    /// the primary lands.
    let onRoll: (_ action: ResolvedAction, _ followUp: ResolvedAction?) -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: Int
    /// Set once the first roll button is tapped — locks the slot picker so the
    /// player can't switch slot levels mid-cast.
    @State private var slotConsumed: Bool = false

    init(
        character: Binding<Character>,
        spell: SpellDefinition,
        itemContext: ItemSpellCastContext? = nil,
        onRoll: @escaping (_ action: ResolvedAction, _ followUp: ResolvedAction?) -> Void
    ) {
        self._character = character
        self.spell = spell
        self.itemContext = itemContext
        self.onRoll = onRoll
        // Item-driven cast starts at the item's base level; otherwise the
        // spell's natural base.
        let startLevel = itemContext?.baseLevel ?? spell.level
        self._selectedLevel = State(initialValue: startLevel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGrid
                    if showsPicker { slotPicker }
                    if !rollEntries.isEmpty { rollsSection }
                    descriptionCard
                    if let higher = spell.higherLevel, !higher.isEmpty {
                        higherLevelCard(higher)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(spell.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Picker is shown when there's a choice to make: leveled spells cast from
    /// slots always show it; item-driven casts show it whenever the item
    /// supports more than one level. Cantrips with no item context skip it.
    private var showsPicker: Bool {
        if let ctx = itemContext {
            return ctx.maxLevel > ctx.baseLevel
        }
        return !spell.isCantrip
    }

    // MARK: - Subviews

    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                MetadataChip(label: "Level", value: spell.isCantrip ? "Cantrip" : "\(spell.level)")
                MetadataChip(label: "School", value: spell.school.displayName)
                MetadataChip(label: "Time", value: spell.castingTime.shortLabel)
            }
            HStack(spacing: 14) {
                MetadataChip(label: "Range", value: spell.range.shortLabel)
                MetadataChip(label: "Comp", value: spell.components.shortLabel)
                MetadataChip(label: "Dur", value: spell.duration.shortLabel)
            }
        }
        .padding(.top, 4)
    }

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pickerTitle)
                    .font(.subheadline.weight(.semibold))
                if slotConsumed {
                    Text("· locked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let subtitle = pickerSubtitle {
                    Text(subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(availableLevels, id: \.self) { level in
                    Button {
                        guard !slotConsumed else { return }
                        selectedLevel = level
                    } label: {
                        VStack(spacing: 2) {
                            Text("L\(level)")
                                .font(.subheadline.weight(.semibold))
                            Text(pickerSubLabel(forLevel: level))
                                .font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            level == selectedLevel
                                ? Color.accentColor.opacity(0.22)
                                : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(level == selectedLevel ? Color.accentColor : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    level == selectedLevel ? Color.accentColor.opacity(0.5) : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(slotConsumed || !hasSlotAtLevel(level))
                    .opacity(hasSlotAtLevel(level) ? 1 : 0.45)
                }
            }
        }
    }

    private var pickerTitle: String {
        itemContext == nil ? "Cast at slot level" : "Charges per cast"
    }

    private var pickerSubtitle: String? {
        guard let pool = chargePool else { return nil }
        return "\(pool.current) / \(pool.max) chg"
    }

    private func pickerSubLabel(forLevel level: Int) -> String {
        if let ctx = itemContext {
            let cost = ctx.cost(forLevel: level)
            return cost == 1 ? "1 chg" : "\(cost) chg"
        }
        if let slot = slotResource(forLevel: level) {
            return "\(slot.current) / \(slot.max)"
        }
        return ""
    }

    private var rollsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rolls")
                .font(.subheadline.weight(.semibold))
            VStack(spacing: 8) {
                ForEach(rollEntries) { entry in
                    RollButton(
                        title: buttonTitle(for: entry),
                        subtitle: entry.action.description,
                        disabled: !canTapRolls
                    ) {
                        handleRollTap(entry)
                    }
                }
            }
            if !canTapRolls {
                Text(unavailableNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableNotice: String {
        if itemContext != nil {
            return "Not enough charges for L\(selectedLevel)."
        }
        return "No slot available at L\(selectedLevel)."
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spell.description)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func higherLevelCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("At Higher Levels")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Roll handling

    /// Sheet-side button label. Distinct from the action's own `label` field
    /// (which is what shows up in the dice tab + history).
    private func buttonTitle(for entry: RollEntry) -> String {
        switch entry.recipe {
        case .spellAttack:                return "Roll Spell Attack"
        case .rawDamage:                  return "Roll Damage"
        case .heal:                       return "Roll Heal"
        case .weaponAttack:               return "Roll Attack"
        case .weaponDamage:               return "Roll Weapon Damage"
        case .abilityCheck, .skillCheck:  return "Roll Check"
        case .savingThrow:                return "Roll Save"
        case .saveDC:                     return "Roll"
        }
    }

    private func handleRollTap(_ entry: RollEntry) {
        if !slotConsumed && needsPayment {
            let ok = payForCast()
            guard ok else { return }
            slotConsumed = true
        }
        onRoll(entry.action, followUp(for: entry))
        // The dice tab takes it from here — chained damage rolls surface as a
        // follow-up chip there, so there's nothing left for this sheet to do.
        dismiss()
    }

    /// Whether the first roll tap should pay a cost. Cantrips cast from spell
    /// slots are free; everything else (leveled slot cast, any item cast) pays.
    private var needsPayment: Bool {
        if itemContext != nil { return true }
        return !spell.isCantrip
    }

    /// Charge the appropriate pool for the chosen level. Returns whether the
    /// consumption succeeded — false short-circuits the roll.
    private func payForCast() -> Bool {
        if let ctx = itemContext {
            return ResourceCalculator.consume(
                amount: ctx.cost(forLevel: selectedLevel),
                from: ctx.resourceID,
                in: &character,
                content: content
            )
        }
        guard let resolved = slotResource(forLevel: selectedLevel) else { return false }
        return ResourceCalculator.consume(
            amount: 1,
            from: resolved.definition.id,
            in: &character,
            content: content
        )
    }

    /// If the primary is a spell attack, surface the first non-attack rollable
    /// in the same spell as the chained damage roll. Other recipes have no
    /// natural pairing (yet).
    private func followUp(for entry: RollEntry) -> ResolvedAction? {
        guard case .spellAttack = entry.recipe else { return nil }
        return rollEntries.first { other in
            switch other.recipe {
            case .rawDamage, .heal: return true
            default: return false
            }
        }?.action
    }

    // MARK: - Slot context

    private var slotResources: [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: content)
            .filter {
                if case .spellSlot = $0.definition.displayHint { return true }
                return false
            }
    }

    /// The item's charge pool, looked up by id. Nil for slot-based casts.
    private var chargePool: ResolvedResource? {
        guard let ctx = itemContext else { return nil }
        return ResourceCalculator.availableResources(character: character, content: content)
            .first { $0.definition.id == ctx.resourceID }
    }

    private var availableLevels: [Int] {
        if let ctx = itemContext {
            return Array(ctx.baseLevel...ctx.maxLevel)
        }
        guard !spell.isCantrip else { return [] }
        let maxLevel = slotResources.compactMap { resolved -> Int? in
            guard case .spellSlot(let level) = resolved.definition.displayHint else { return nil }
            return level
        }.max() ?? spell.level
        return Array(spell.level...max(spell.level, maxLevel))
    }

    private func slotResource(forLevel level: Int) -> ResolvedResource? {
        slotResources.first {
            if case .spellSlot(let l) = $0.definition.displayHint { return l == level }
            return false
        }
    }

    private func hasSlotAtLevel(_ level: Int) -> Bool {
        if let ctx = itemContext {
            let cost = ctx.cost(forLevel: level)
            return (chargePool?.current ?? 0) >= cost
        }
        guard let resolved = slotResource(forLevel: level) else { return false }
        return resolved.current > 0
    }

    /// Cantrips cast from slots can always roll. Anything else (leveled slot
    /// cast, any item cast) requires a free slot / enough charges at the
    /// selected level — until the first roll, after which the cost has already
    /// been paid and follow-up rolls (e.g. damage after attack) are free.
    private var canTapRolls: Bool {
        if !needsPayment { return true }
        if slotConsumed { return true }
        return hasSlotAtLevel(selectedLevel)
    }

    /// The character's spellcasting ability — the first class with a
    /// spellcasting block. Multi-class casters with diverging abilities will
    /// need a per-class picker in a later phase.
    private var spellcastingAbility: Ability? {
        for entry in character.classEntries {
            if let block = content.classDefinition(id: entry.classID)?.spellcasting {
                return block.ability
            }
        }
        return nil
    }

    // MARK: - Roll entries

    /// Pairs each spell recipe with its resolved action so the view can
    /// distinguish attack rows from damage rows when wiring follow-ups.
    private struct RollEntry: Identifiable {
        let id: String
        let recipe: ActionRecipe
        let action: ResolvedAction
    }

    private var rollEntries: [RollEntry] {
        let scaledRecipes = spell.recipes(castAtLevel: selectedLevel)
        let upcastSuffix: String? = (spell.isCantrip || selectedLevel == spell.level)
            ? nil
            : "L\(selectedLevel)"
        let ability = spellcastingAbility

        return scaledRecipes.enumerated().compactMap { offset, recipe in
            let resolved = ActionInterpreter.resolve(
                recipe: recipe,
                character: character,
                weapon: nil,
                spellcastingAbility: ability
            )
            guard resolved.formula != nil else { return nil }
            let label: String
            if let upcastSuffix {
                label = "\(resolved.label) (\(upcastSuffix))"
            } else {
                label = resolved.label
            }
            let stamped = ResolvedAction(
                id: "spell_\(spell.id)_l\(selectedLevel)_\(resolved.id)",
                label: label,
                formula: resolved.formula,
                description: resolved.description
            )
            return RollEntry(
                id: "\(spell.id)_\(offset)",
                recipe: recipe,
                action: stamped
            )
        }
    }
}

private struct MetadataChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RollButton: View {
    let title: String
    let subtitle: String?
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "dice.fill")
                    .font(.title3)
                    .foregroundStyle(disabled ? Color.secondary.opacity(0.5) : Color.accentColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}
