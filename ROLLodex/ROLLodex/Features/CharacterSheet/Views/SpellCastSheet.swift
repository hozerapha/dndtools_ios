import SwiftUI

/// Single-stage spell modal. Three commit paths:
/// 1. **Roll-tap** (Magic Missile, Fire Bolt) — slot picker selects level,
///    Roll buttons fire the rolls and consume the slot.
/// 2. **Slot-tap cast** (Detect Magic, Identify) — when the spell has no
///    rolls, tapping a level button is itself the cast: consume slot + set
///    concentration + dismiss in one move.
/// 3. **Ritual-tap** — for ritual-tagged spells on a ritual-casting class.
///    Skips slot consumption entirely; otherwise behaves like a normal cast.
///
/// Slot/charge consumption is lazy on the first commit (so dismissing the
/// sheet without acting spends nothing). After commit the slot picker locks.
/// Cantrips skip slot logic entirely.
///
/// When the player rolls a Spell Attack and the spell also has a damage roll,
/// the damage action is handed to the dice tab as a `followUp`; the tab
/// surfaces a "Roll damage?" chip after the attack settles.
struct SpellCastSheet: View {
    @Binding var character: Character
    let spell: SpellDefinition
    /// When non-nil, this cast is paid from an item's charge pool — the slot
    /// picker shows charge costs per level and the consumed pool is the item's
    /// resource, not the character's spell slots.
    let itemContext: ItemSpellCastContext?
    /// Fallback casting ability for species-granted spells. Used only when the
    /// character has no class spellcasting ability of its own (a Tiefling
    /// Fighter casting Fire Bolt). Nil otherwise.
    let innateAbility: Ability?
    /// When non-nil, this leveled spell is a species grant with a once-per-Long-
    /// Rest free cast; the sheet shows a "Cast free" path that spends this pool
    /// instead of a slot.
    let freeCastResourceID: String?
    /// Called for each roll tap. `followUp` is non-nil when the primary roll
    /// has a natural next step (attack → damage); the dice tab parks it until
    /// the primary lands.
    let onRoll: (_ action: ResolvedAction, _ followUp: ResolvedAction?) -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: Int
    /// Chosen damage type for spells that offer a choice (Chromatic Orb,
    /// Dragon's Breath). Nil for fixed-type spells. Stamped onto the damage
    /// dice in `rollEntries`.
    @State private var selectedDamageType: DamageType?
    /// Set once the first roll button is tapped — locks the slot picker so the
    /// player can't switch slot levels mid-cast.
    @State private var slotConsumed: Bool = false
    /// Closure-based concentration-swap confirmation. When non-nil, the alert
    /// is up; confirming calls it. Generalized so the slot-tap, roll-tap, and
    /// ritual-tap paths can all reuse the same prompt.
    @State private var pendingSwapAction: PendingSwap?

    init(
        character: Binding<Character>,
        spell: SpellDefinition,
        itemContext: ItemSpellCastContext? = nil,
        innateAbility: Ability? = nil,
        freeCastResourceID: String? = nil,
        onRoll: @escaping (_ action: ResolvedAction, _ followUp: ResolvedAction?) -> Void
    ) {
        self._character = character
        self.spell = spell
        self.itemContext = itemContext
        self.innateAbility = innateAbility
        self.freeCastResourceID = freeCastResourceID
        self.onRoll = onRoll
        // Item-driven cast starts at the item's base level; otherwise the
        // spell's natural base.
        let startLevel = itemContext?.baseLevel ?? spell.level
        self._selectedLevel = State(initialValue: startLevel)
        self._selectedDamageType = State(initialValue: spell.damageTypeChoices.first)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGrid
                    if showsPicker { slotPicker }
                    if !spell.damageTypeChoices.isEmpty { damageTypePicker }
                    if canCastAsRitual { ritualSection }
                    if let pool = freeCastPool { freeCastSection(pool) }
                    if !rollEntries.isEmpty { rollsSection }
                    if !targetConditions.isEmpty { applyConditionSection }
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
            .alert(
                "Replace concentration?",
                isPresented: Binding(
                    get: { pendingSwapAction != nil },
                    set: { if !$0 { pendingSwapAction = nil } }
                )
            ) {
                Button("End \(currentConcentrationName ?? "previous spell")", role: .destructive) {
                    let pending = pendingSwapAction
                    pendingSwapAction = nil
                    pending?.commit()
                }
                Button("Cancel", role: .cancel) { pendingSwapAction = nil }
            } message: {
                Text("\(spell.name) requires concentration. Casting it ends \(currentConcentrationName ?? "your current concentration spell").")
            }
        }
    }

    /// Boxed `() -> Void` so we can hang it off `@State` and key the alert off
    /// its presence. Equatable based on identity (each request is distinct).
    private struct PendingSwap: Equatable {
        let id = UUID()
        let commit: () -> Void
        static func == (a: PendingSwap, b: PendingSwap) -> Bool { a.id == b.id }
    }

    private var currentConcentrationName: String? {
        guard let id = character.concentratingSpellID else { return nil }
        return content.spellDefinition(id: id)?.name
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
            if let dc = saveDC {
                // Caster's spell save DC, including any active buff (Innate
                // Sorcery → +1). Shown so save-based spells have a target number.
                HStack(spacing: 14) {
                    MetadataChip(
                        label: spellBuff.saveDCBonus > 0 ? "Save DC (buffed)" : "Save DC",
                        value: "\(dc)"
                    )
                    if spellBuff.attackAdvantage {
                        MetadataChip(label: "Spell Atk", value: "Advantage")
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Active spellcasting buff (Innate Sorcery): DC bonus + attack advantage.
    private var spellBuff: (saveDCBonus: Int, attackAdvantage: Bool) {
        CharacterCalculator.spellcastingBuff(character: character, content: content)
    }

    /// Caster's spell save DC for the resolved spellcasting ability, including
    /// the active buff. Nil when there's no spellcasting ability to base it on.
    private var saveDC: Int? {
        guard let ability = spellcastingAbility else { return nil }
        return CharacterCalculator.spellSaveDC(
            character: character, spellcastingAbility: ability, bonus: spellBuff.saveDCBonus
        )
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
                        if castsImmediatelyOnLevelTap {
                            handleSlotTapCast(level)
                        } else {
                            selectedLevel = level
                        }
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
            if castsImmediatelyOnLevelTap {
                Text("Tap a level to cast.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Damage-type chooser for spells that let the caster pick (Chromatic Orb,
    /// Dragon's Breath). The selection stamps the spell's damage dice in
    /// `rollEntries`. Stays editable after the slot is consumed — the SRD lets
    /// you pick at cast time, and the damage roll happens after.
    private var damageTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Damage type")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(spell.damageTypeChoices, id: \.self) { type in
                        Button {
                            selectedDamageType = type
                        } label: {
                            Text(type.rawValue.capitalized)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(
                                    type == selectedDamageType
                                        ? Color.accentColor.opacity(0.22)
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(type == selectedDamageType ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// "Cast as Ritual" affordance. Visible only when the spell is a ritual
    /// AND the character has ritual casting on at least one of their classes.
    /// Ritual casts skip slot consumption — that's the whole feature — and
    /// take 10 extra minutes in fiction (informational only here).
    private var ritualSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                handleRitualTap()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cast as Ritual")
                            .font(.subheadline.weight(.semibold))
                        Text("No slot consumed · +10 minutes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.purple.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(slotConsumed)
            .opacity(slotConsumed ? 0.5 : 1)
        }
    }

    /// "Cast free" affordance for a leveled species-granted spell — the SRD's
    /// "once per Long Rest without a slot." Spends the grant's free-use pool
    /// rather than a spell slot, then fires the spell's rolls (if any).
    private func freeCastSection(_ pool: ResolvedResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                handleFreeCastTap()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cast free (Innate)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(pool.current) / \(pool.max) per Long Rest · no slot")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.purple.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(slotConsumed || pool.current == 0)
            .opacity(slotConsumed || pool.current == 0 ? 0.5 : 1)
        }
    }

    private func handleFreeCastTap() {
        if shouldPromptConcentrationSwap {
            pendingSwapAction = PendingSwap { performFreeCast() }
            return
        }
        performFreeCast()
    }

    private func performFreeCast() {
        guard let resID = freeCastResourceID else { return }
        let ok = ResourceCalculator.consume(amount: 1, from: resID, in: &character, content: content)
        guard ok else { return }
        slotConsumed = true
        commitCast()
        // Fire the primary roll (attack or damage); a chained damage roll
        // surfaces as a follow-up in the dice tab, same as a ritual cast.
        if let primary = rollEntries.first {
            onRoll(primary.action, followUp(for: primary))
        }
        dismiss()
    }

    /// The grant's free-cast pool, when this is a leveled species grant.
    private var freeCastPool: ResolvedResource? {
        guard let id = freeCastResourceID else { return nil }
        return ResourceCalculator.availableResources(character: character, content: content)
            .first { $0.definition.id == id }
    }

    /// True when there are no roll buttons to wait on — Detect Magic, Detect
    /// Poison and Disease, Identify, etc. In that case a slot-button tap is
    /// itself the cast confirmation; the user doesn't need a second tap.
    private var castsImmediatelyOnLevelTap: Bool {
        rollEntries.isEmpty
    }

    /// Spell carries the ritual tag in its casting time.
    private var isRitualSpell: Bool {
        if case .ritual = spell.castingTime { return true }
        return false
    }

    /// Character has at least one class with the ritualCasting flag.
    private var characterCanRitualCast: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting?.ritualCasting == true
        }
    }

    private var canCastAsRitual: Bool {
        // Ritual casts originate from the prepared/known list, never from an
        // item's charge pool — items pay charges by design.
        itemContext == nil && isRitualSpell && characterCanRitualCast
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

    /// Condition ids this spell imposes on a target (Hold Person → paralyzed).
    private var targetConditions: [String] {
        spell.effects.compactMap { if case .targetCondition(let id) = $0 { return id } else { return nil } }
    }

    /// Manual "apply to this character" affordance for a spell's imposed
    /// condition. There's no enemy sheet in a one-PC app, so this is for when
    /// the player is the target (honor-system) — or to track it yourself.
    private var applyConditionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Imposes")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(targetConditions, id: \.self) { id in
                let name = content.conditionDefinition(id: id)?.name ?? id.capitalized
                let alreadyOn = character.conditions.contains { $0.id == id }
                Button {
                    character.applyCondition(id: id, source: spell.name)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: alreadyOn ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(alreadyOn ? .green : Color.accentColor)
                        Text(alreadyOn ? "\(name) applied" : "Apply \(name) to this character")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(alreadyOn)
            }
            Text("On a failed save. For when you're the target — there's no enemy sheet.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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
        case .rawDamage, .scaledDamage:   return "Roll Damage"
        case .heal:                       return "Roll Heal"
        case .weaponAttack:               return "Roll Attack"
        case .weaponDamage:               return "Roll Weapon Damage"
        case .abilityCheck, .skillCheck:  return "Roll Check"
        case .savingThrow:                return "Roll Save"
        case .saveDC:                     return "Roll"
        case .abilityRoll:                return "Roll"
        }
    }

    private func handleRollTap(_ entry: RollEntry) {
        if shouldPromptConcentrationSwap {
            pendingSwapAction = PendingSwap { performRoll(entry) }
            return
        }
        performRoll(entry)
    }

    private func performRoll(_ entry: RollEntry) {
        if !slotConsumed && needsPayment {
            let ok = payForCast()
            guard ok else { return }
            slotConsumed = true
        }
        commitCast()
        onRoll(entry.action, followUp(for: entry))
        // The dice tab takes it from here — chained damage rolls surface as a
        // follow-up chip there, so there's nothing left for this sheet to do.
        dismiss()
    }

    /// Slot-tap shortcut: when the spell has no rolls, tapping a level button
    /// commits the cast (consume slot + maybe set concentration + dismiss)
    /// without a separate roll button. Detect Magic is the prototypical case.
    private func handleSlotTapCast(_ level: Int) {
        if shouldPromptConcentrationSwap {
            pendingSwapAction = PendingSwap { performCastWithoutRoll(at: level) }
            return
        }
        performCastWithoutRoll(at: level)
    }

    private func performCastWithoutRoll(at level: Int) {
        selectedLevel = level
        if !slotConsumed && needsPayment {
            let ok = payForCast()
            guard ok else { return }
            slotConsumed = true
        }
        commitCast()
        dismiss()
    }

    /// Ritual-tap path: skip slot payment entirely, optionally set
    /// concentration, dismiss. Rituals with rolls (uncommon) still get their
    /// rolls handed off after.
    private func handleRitualTap() {
        if shouldPromptConcentrationSwap {
            pendingSwapAction = PendingSwap { performRitualCast() }
            return
        }
        performRitualCast()
    }

    private func performRitualCast() {
        commitCast()
        // Fire any rolls anyway (Detect Magic has none; a hypothetical homebrew
        // ritual with damage would still work). No slot consumption — that's
        // the whole point of casting as ritual.
        if let primary = rollEntries.first {
            onRoll(primary.action, followUp(for: primary))
        }
        dismiss()
    }

    /// True when the cast would replace an existing concentration spell. The
    /// three commit paths (roll, slot-tap, ritual-tap) all reuse this.
    private var shouldPromptConcentrationSwap: Bool {
        guard !slotConsumed,
              spell.duration.requiresConcentration,
              let active = character.concentratingSpellID,
              active != spell.id else { return false }
        return true
    }

    /// Everything a confirmed cast does to the caster's own sheet:
    /// concentration + caster-targeted spell effects (temp HP, self conditions).
    /// `targetCondition` effects are NOT applied here — they're offered as a
    /// button (the spell hits a target, not the caster).
    private func commitCast() {
        if spell.duration.requiresConcentration {
            // Routes through the helper so any persistent rider on this spell
            // (Hex's necrotic damage, Hunter's Mark, etc.) attaches to the
            // character — and any rider from the previously concentrated spell
            // gets dropped at the same moment as the swap.
            character.startConcentrating(
                on: spell.id,
                grantsEffect: spell.grantsTriggeredEffect
            )
        }
        for effect in spell.effects {
            switch effect {
            case .tempHP(let dice):
                // Temp HP doesn't stack — keep the higher value.
                let rolled = (try? DiceFormulaParser().parse(dice)).map { DiceRoller().roll($0).total } ?? 0
                character.tempHP = max(character.tempHP, rolled)
            case .selfCondition(let id):
                character.applyCondition(id: id, source: spell.name)
            case .targetCondition:
                break  // offered via applyTargetConditionSection, not auto-applied
            case .selfBuff(let buff):
                // Park the buff as a spell-sourced active effect: it ticks down
                // with rounds (Shield → 1) and is dropped with concentration
                // (Bless, Shield of Faith) by removeSpellSourcedEffects.
                character.applySpellBuff(spellID: spell.id, rounds: buff.rounds)
            }
        }
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
        // No class caster: fall back to the species innate ability so a
        // granted spell-attack (Fire Bolt) still resolves a to-hit roll.
        return innateAbility
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
            guard var formula = resolved.formula else { return nil }
            // Stamp the chosen damage type onto the spell's damage dice,
            // overriding the recipe's placeholder type (Chromatic Orb, Dragon's
            // Breath). Only damage recipes carry a type to override.
            if let chosen = selectedDamageType, !spell.damageTypeChoices.isEmpty {
                switch recipe {
                case .rawDamage, .scaledDamage:
                    formula.applyDamageType(chosen)
                default:
                    break
                }
            }
            var label = resolved.label
            if let upcastSuffix { label = "\(resolved.label) (\(upcastSuffix))" }
            // Spell attack roll mode: Innate Sorcery grants advantage; the
            // character's conditions can add advantage (Invisible) or
            // disadvantage (Poisoned, Blinded). Combine per 5e (adv+dis cancel)
            // and expand the d20 accordingly.
            if case .spellAttack = recipe {
                let (cAdv, cDis) = CharacterCalculator.conditionRollMode(
                    character: character, content: content, context: .attack
                )
                let mode = CharacterCalculator.combineRollMode(
                    .normal, advantage: cAdv || spellBuff.attackAdvantage, disadvantage: cDis
                )
                if mode != .normal,
                   let i = formula.groups.firstIndex(where: { $0.kind == .d20 && $0.count == 1 && $0.isPlain }) {
                    formula.groups[i].count = 2
                    formula.groups[i].modifier = (mode == .advantage) ? .keepHighest(1) : .keepLowest(1)
                    label += mode == .advantage ? " (Adv)" : " (Dis)"
                }
                // Bless and similar buffs add dice (1d4) to the spell attack roll.
                let blessDice = CharacterCalculator.attackSaveBuffDiceGroups(character: character, content: content)
                if !blessDice.isEmpty {
                    formula.groups.append(contentsOf: blessDice)
                    label += " +Bless"
                }
            }
            let stamped = ResolvedAction(
                id: "spell_\(spell.id)_l\(selectedLevel)_\(resolved.id)",
                label: label,
                formula: formula,
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
