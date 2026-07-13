import SwiftUI

/// Editable character sheet. Mutations (name, HP, inventory, notes) flow back
/// through the `@Binding`, which `CharacterStore.binding(for:)` persists on
/// every set. All derived values (AC, action grid, etc.) recompute on demand.
struct CharacterSheetView: View {
    @Binding var character: Character
    @Binding var selectedTab: AppTab
    @Environment(ContentStore.self) private var content
    @Environment(PendingRollStore.self) private var pendingRoll
    @Environment(CharacterStore.self) private var characterStore
    @Environment(\.dismiss) private var dismiss

    @State private var showRestConfirm = false
    @State private var showLevelUp = false
    @State private var showDeleteConfirm = false
    @State private var pendingRefreshes: [PendingRefresh] = []
    @State private var spellBeingCast: PendingSpellCast?
    /// Set when applying damage to a concentrating character; presents the
    /// concentration save sheet. Cleared when the player resolves the save
    /// (roll handoff or manual pass/fail).
    @State private var pendingConcentrationCheck: ConcentrationCheck?
    /// Open by `.sheet(isPresented:)` toggle; `pendingAddCondition` carries
    /// nothing on its own — the picker is one-shot.
    @State private var showAddCondition = false
    /// In-sheet mini dice tray (death saves today; level-up HP and
    /// concentration saves adopt it in 14c). Non-nil presents the overlay.
    @State private var quickRoll: QuickRollRequest?
    /// Set when the player taps a STR/DEX save that an active condition
    /// (Paralyzed, Stunned, Unconscious, …) forces to auto-fail. Presents an
    /// alert and skips the roll — the save can't succeed.
    @State private var autoFailedSave: AutoFailedSave?
    /// Level-up → spell-learning chain: set by LevelUpSheet's commit when the
    /// level grew any spell budget; consumed on its dismissal to present the
    /// spell picker so the player is prompted to learn/prepare new spells.
    @State private var promptSpellsAfterLevelUp = false
    /// Spell-picker sheet trigger. Non-nil presents; the value chooses the
    /// picker's presentation (level-up "Learn" vs post-rest "Prepare").
    @State private var spellPickerPresentation: PickerPresentation?
    /// Confirmation dialog after a Long Rest for unlimited-prep casters (the
    /// natural moment to rebuild the prep list). Not shown for fixed-table /
    /// pact classes — they can only swap on level-up.
    @State private var showPrepareAfterRest = false
    /// Which sub-tab of the character sheet is showing. The header (badges,
    /// HP bar, stat pills) stays fixed above the picker so every tab can see
    /// "who am I and how am I doing right now".
    @State private var section: SheetSection = .actions

    /// Sub-tabs of a single character sheet. The Spells tab disappears when
    /// the character has no spellcasting source — there's nothing to put in
    /// it. Features is always present (every character has at least a few).
    enum SheetSection: String, CaseIterable, Identifiable {
        case actions, abilities, features, inventory, spells

        var id: Self { self }

        var label: String {
            switch self {
            case .actions:   return "Actions"
            case .abilities: return "Abilities"
            case .features:  return "Features"
            case .inventory: return "Inventory"
            case .spells:    return "Spells"
            }
        }

        var systemImage: String {
            switch self {
            case .actions:   return "burst"
            case .abilities: return "person.fill"
            case .features:  return "sparkles"
            case .inventory: return "backpack.fill"
            case .spells:    return "wand.and.stars"
            }
        }
    }

    /// Payload for the auto-fail save alert: which save and the condition that
    /// forces the failure.
    struct AutoFailedSave: Identifiable {
        let id = UUID()
        let ability: Ability
        let conditionName: String
    }

    // The full screen is one long modifier chain; as of the multiclass pass it
    // outgrew what the type-checker will solve as a single expression. The
    // stages below (`screenContent` → change handlers → dialogs → sheets) are
    // each type-checked independently, which keeps builds fast. Add new
    // sheets/alerts to the matching stage, not to `body`.
    var body: some View {
        withSheetsAndOverlay(withDialogs(withChangeHandlers(screenContent)))
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            stickyHeader
            sectionPicker
            ScrollView {
                Group {
                    switch section {
                    case .actions:   actionsTab
                    case .abilities: abilitiesTab
                    case .features:  featuresTab
                    case .inventory: inventoryTab
                    case .spells:    spellsTab
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { sheetToolbar }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showLevelUp = true
            } label: {
                Label("Level Up", systemImage: "arrow.up.circle.fill")
            }
            .disabled(character.level >= 20)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showRestConfirm = true
            } label: {
                Label("Rest", systemImage: "moon.zzz.fill")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ShareLink(
                    item: ExportedCharacter(character: character),
                    preview: SharePreview(character.name)
                ) {
                    Label("Export Character", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Character", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func withChangeHandlers(_ content: some View) -> some View {
        content
            .onChange(of: showsSpellsTab) { _, shows in
                // Defensive: if the Spells tab disappears (class swap drops
                // casting, or a granted-spell source is removed) while the user
                // is on it, bounce them to Actions.
                if !shows && section == .spells { section = .actions }
            }
            .onChange(of: pendingRoll.pendingCostsToApply) { _, costs in
                applyPendingCosts(costs)
            }
            .onChange(of: pendingRoll.pendingResourceCostsToApply) { _, costs in
                applyPendingResourceCosts(costs)
            }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog("Rest", isPresented: $showRestConfirm, titleVisibility: .hidden) {
                Button("Short Rest") { takeRest(.short) }
                Button("Long Rest")  { takeRest(.long) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete Character", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete \(character.name)", role: .destructive) {
                    deleteCharacter()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes \(character.name) and cannot be undone.")
            }
            .alert(
                "Save auto-fails",
                isPresented: Binding(
                    get: { autoFailedSave != nil },
                    set: { if !$0 { autoFailedSave = nil } }
                ),
                presenting: autoFailedSave
            ) { _ in
                Button("OK", role: .cancel) { autoFailedSave = nil }
            } message: { save in
                Text("\(save.ability.rawValue.capitalized) saving throws automatically fail while \(save.conditionName). No roll needed.")
            }
            .confirmationDialog(
                "Long Rest complete",
                isPresented: $showPrepareAfterRest,
                titleVisibility: .visible
            ) {
                Button("Prepare Spells") { spellPickerPresentation = .dailyPrepare }
                Button("Skip", role: .cancel) {}
            } message: {
                Text("Would you like to rebuild your prepared spells now?")
            }
    }

    private func withSheetsAndOverlay(_ content: some View) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { !pendingRefreshes.isEmpty },
                set: { if !$0 { pendingRefreshes = [] } }
            )) {
                RefreshResolutionSheet(
                    character: $character,
                    pendingRefreshes: pendingRefreshes,
                    onDismiss: { pendingRefreshes = [] }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $spellBeingCast) { pending in
                SpellCastSheet(
                    character: $character,
                    spell: pending.spell,
                    itemContext: pending.itemContext,
                    innateAbility: pending.innateAbility,
                    freeCastResourceID: pending.freeCastResourceID
                ) { action, followUps in
                    handleSpellRoll(action, followUps: followUps)
                }
                .presentationDetents([.large])
            }
            .sheet(item: $pendingConcentrationCheck) { check in
                ConcentrationSaveSheet(character: $character, check: check)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAddCondition) {
                AddConditionSheet(character: $character)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showLevelUp, onDismiss: {
                // Chain the spell picker when the level grew spell budgets so
                // the player is prompted to learn/prepare their new spells.
                if promptSpellsAfterLevelUp {
                    promptSpellsAfterLevelUp = false
                    spellPickerPresentation = .learnOnLevelUp
                }
            }) {
                LevelUpSheet(
                    character: $character,
                    onSpellBudgetsGrew: { promptSpellsAfterLevelUp = true }
                )
                .presentationDetents([.large])
            }
            .sheet(item: $spellPickerPresentation) { presentation in
                // Level-up-triggered picker → "Learn Spells"; post-long-rest
                // prompt → "Prepare Spells". The regular Spells card button
                // opens its OWN sheet (with class-derived title).
                AddSpellSheet(character: $character, presentation: presentation)
                    .presentationDetents([.medium, .large])
            }
            .overlay {
                if let request = quickRoll {
                    QuickRollOverlay(
                        request: request,
                        onResult: { applyDeathSaveResult($0) },
                        onDismiss: { quickRoll = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.snappy(duration: 0.2), value: quickRoll != nil)
    }

    /// Apply each cost the dice tab parked to the bound character, then clear
    /// the queue so the same chip can't double-debit on a re-render.
    private func applyPendingCosts(_ costs: [TriggerCost]) {
        guard !costs.isEmpty else { return }
        for cost in costs {
            switch cost {
            case .oncePerTurn(let flag):
                character.setTurnFlag(flag)
            case .spellSlot(let minLevel, let maxLevel):
                // The resolver concretizes the range to one level before
                // parking the chip, so this consumes exactly the slot the
                // player saw. If it was spent elsewhere in between (edge
                // case), the consume no-ops rather than over-charging.
                if let level = ResourceCalculator.lowestAvailableSlotLevel(
                    min: minLevel, max: maxLevel,
                    character: character, content: content
                ) {
                    ResourceCalculator.consumeSpellSlot(
                        level: level, in: &character, content: content
                    )
                }
            }
        }
        pendingRoll.pendingCostsToApply = []
    }

    /// Feature resource costs the dice tab parked when a rollable action
    /// actually fired (Second Wind, etc.) — debit now, then clear.
    private func applyPendingResourceCosts(_ costs: [ResourceCost]) {
        guard !costs.isEmpty else { return }
        for cost in costs {
            _ = ResourceCalculator.consume(
                amount: cost.amount, from: cost.resourceID, in: &character, content: content
            )
        }
        pendingRoll.pendingResourceCostsToApply = []
    }

    /// Persistent-error banner: edits flow through `binding(for:)` → `save`,
    /// so a failed write would otherwise vanish into a console print. This
    /// keeps it in the player's face until a save succeeds or they dismiss.
    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                characterStore.clearSaveError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Deletion

    /// Pop back to the list FIRST, then remove the character. Deleting while
    /// this screen is still on the stack re-renders it as "Character not
    /// found" mid-pop (the store removal invalidates the binding), so the
    /// store mutation waits out the pop animation.
    private func deleteCharacter() {
        let id = character.id
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            characterStore.delete(id: id)
        }
    }

    // MARK: - Layout chrome

    /// Sticky bit at the top of every tab: name editor, badges, HP, conditions,
    /// stat pills. Sits outside the ScrollView so it never scrolls away.
    private var stickyHeader: some View {
        VStack(spacing: 10) {
            if let saveError = characterStore.lastSaveError {
                saveErrorBanner(saveError)
            }
            headerCard
            if character.currentHP == 0 {
                DeathSavesRow(character: $character, onRoll: rollDeathSave)
            }
            ConditionsRow(character: $character) {
                showAddCondition = true
            }
            EffectsRow(character: $character)
            statPillRow
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(availableSections) { sec in
                Text(sec.label).tag(sec)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var availableSections: [SheetSection] {
        SheetSection.allCases.filter {
            $0 != .spells || showsSpellsTab
        }
    }

    private var hasSpellcasting: Bool {
        character.classEntries.contains { entry in
            content.classDefinition(id: entry.classID)?.spellcasting != nil
        }
    }

    /// The Spells tab shows for any caster, OR any character with species-
    /// granted spells (a Tiefling Fighter's Fiendish Legacy cantrip lives here).
    private var showsSpellsTab: Bool {
        hasSpellcasting
            || !CharacterSpellGrants.resolve(character: character, content: content).isEmpty
    }

    // MARK: - Tab content

    private var actionsTab: some View {
        VStack(spacing: 14) {
            ResourcesView(character: $character)
            turnFlagsRow
            AttacksView(
                rows: weaponAttackRows,
                onAttack: handleWeaponAttack,
                onDamage: handleStandaloneRoll
            )
            // One cohesive economy-grouped list: interactive feature/item
            // rows and feature-granted options together, by turn cost.
            ActionEconomyView(
                interactiveRows: actionSections.flatMap(\.rows),
                grantedRows: CharacterActionDeriver.grantedActions(for: character, content: content),
                onTap: handleActionTap,
                onRoll: { dispatchRoll($0, mode: .normal) }
            )
        }
    }

    /// Turn tracker shown when there's something to advance: once-per-turn
    /// flags spent (Sneak Attack, etc.) and/or round-limited effects ticking
    /// down (Rage). The Start New Turn button clears flags AND decrements all
    /// round counters in one go — that's the natural "I just ended my turn"
    /// pulse the player needs to keep Rage's 10-round clock honest.
    /// Hidden when there's nothing to track so a casual fighter never sees it.
    @ViewBuilder
    private var turnFlagsRow: some View {
        if !character.turnFlags.isEmpty || !timedEffectLabels.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "hourglass.tophalf.filled")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This turn")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(turnTrackerLabels.joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Button("Start New Turn") {
                    character.startNewTurn()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var weaponAttackRows: [WeaponAttackRow] {
        CharacterActionDeriver.weaponAttacks(for: character, content: content)
    }

    /// Human-readable labels for the flags currently set this turn. Sorted by
    /// the resolved label so the row reads alphabetically by name, not by
    /// internal id (avoids "sneak_attack" jumping around when other flags land).
    private var turnFlagLabels: [String] {
        character.turnFlags
            .map { TriggeredEffectResolver.turnFlagDisplayName($0, character: character, content: content) }
            .sorted()
    }

    /// "Rage 9r" style labels for active effects with a round counter. Lets
    /// the turn-tracker row show what's ticking down alongside the once-per-
    /// turn flags. Names come from the resolved triggered effect when we can
    /// find it, falling back to the effect id.
    private var timedEffectLabels: [String] {
        character.activeEffects
            .compactMap { active -> String? in
                guard let rounds = active.roundsRemaining else { return nil }
                let name = effectDisplayName(for: active) ?? active.effectID
                return "\(name) \(rounds)r"
            }
            .sorted()
    }

    /// Merged tracker line: once-per-turn flags first, then round-ticking
    /// effects. Both clear/decrement when the player taps Start New Turn.
    private var turnTrackerLabels: [String] {
        turnFlagLabels + timedEffectLabels
    }

    /// Lookup the effect name for an `ActiveEffect`, mirroring the resolver
    /// dispatch. Used only for label rendering in the turn-tracker row, so a
    /// nil result is fine — the caller falls back to the effect id.
    private func effectDisplayName(for active: ActiveEffect) -> String? {
        switch active.source {
        case .spell(let id):
            return content.spellDefinition(id: id)?.grantsTriggeredEffect?.name
        case .feature(let id):
            for entry in character.classEntries {
                guard let cls = content.classDefinition(id: entry.classID) else { continue }
                let subclassID = character.featureSelections[
                    ClassDefinition.subclassSelectionID(forClassID: entry.classID)
                ]?.first
                for resolved in cls.resolvedFeatures(
                    throughClassLevel: entry.level,
                    subclassID: subclassID
                ) {
                    if resolved.feature.id == id {
                        return resolved.feature.triggeredEffect?.name ?? resolved.feature.name
                    }
                }
            }
            return nil
        case .item:
            return nil
        }
    }

    /// Tap on a weapon's Attack chip: push the d20 attack onto the dice tab
    /// AND queue the matching damage as a follow-up — same pattern spell
    /// attacks use, so the dice tab's "Roll damage?" chip appears after the
    /// attack lands.
    private func handleWeaponAttack(_ row: WeaponAttackRow) {
        pendingRoll.pendingCharacterID = character.id
        // Conditions can force advantage/disadvantage on the attack (Poisoned,
        // Blinded → disadvantage; Invisible → advantage). Weapon attacks have no
        // adv/dis chips, so apply it here.
        let (conditionAdv, dis) = CharacterCalculator.conditionRollMode(
            character: character, content: content, context: .attack
        )
        // Reckless Attack (Barbarian L2): while active, grant Advantage on
        // weapon attacks. Downside ("attackers gain Advantage against you") is
        // honor-system since the app has no enemy sheet.
        let recklessAdv = CharacterCalculator.recklessAttackActive(character: character, content: content)
        let adv = conditionAdv || recklessAdv
        let attackMode = CharacterCalculator.combineRollMode(.normal, advantage: adv, disadvantage: dis)
        // Bless adds 1d4 to attack rolls. Fold it (and any adv/dis) into a
        // single resolved attack so the dice tab rolls it all at once.
        let blessDice = CharacterCalculator.attackSaveBuffDiceGroups(character: character, content: content)
        var attackFormula = applyAdvantage(to: row.attack.formula, mode: attackMode) ?? row.attack.formula
        if !blessDice.isEmpty { attackFormula?.groups.append(contentsOf: blessDice) }
        var label = row.attack.label
        if attackMode == .disadvantage { label += " (Disadvantage)" }
        else if attackMode == .advantage { label += " (Advantage)" }
        if !blessDice.isEmpty { label += " +Bless" }
        if attackMode != .normal || !blessDice.isEmpty {
            pendingRoll.pending = ResolvedAction(
                id: row.attack.id,
                label: label,
                formula: attackFormula,
                description: row.attack.description
            )
        } else {
            pendingRoll.pending = row.attack
        }
        // The base damage is the chained "Roll damage" follow-up; opt-in riders
        // (Sneak Attack, Divine Smite, …) are independent toggles the dice tab
        // stacks onto it. Riders already fired this turn are filtered out by the
        // resolver.
        pendingRoll.followUps = [.chainedDamage(row.damage)]
        pendingRoll.pendingRiders = row.riders
        selectedTab = .dice
    }

    /// Standalone damage / versatile-damage tap: no follow-up, just roll.
    private func handleStandaloneRoll(_ action: ResolvedAction) {
        pendingRoll.pendingCharacterID = character.id
        pendingRoll.pending = action
        pendingRoll.followUps = []
        selectedTab = .dice
    }

    private var abilitiesTab: some View {
        VStack(spacing: 14) {
            AbilityBlockView(
                character: character,
                onRollCheck: { ability, mode in
                    dispatchRoll(.abilityCheck(ability: ability), mode: mode)
                },
                onRollSave: { ability, mode in
                    dispatchRoll(.savingThrow(ability: ability), mode: mode)
                }
            )
            SkillListView(character: character) { skill, mode in
                dispatchRoll(.skillCheck(skill: skill), mode: mode)
            }
            sensesCard
            proficienciesCard
            NotesEditorView(notes: $character.notes)
        }
    }

    private var featuresTab: some View {
        FeaturesView(character: $character)
    }

    private var inventoryTab: some View {
        InventoryView(character: $character)
    }

    private var spellsTab: some View {
        VStack(spacing: 14) {
            ConcentrationPin(character: $character)
            SpellListView(character: $character) { spell, _ in
                spellBeingCast = PendingSpellCast(
                    spell: spell,
                    itemContext: nil,
                    innateAbility: CharacterSpellGrants.innateSpellcastingAbility(character: character, content: content),
                    freeCastResourceID: CharacterSpellGrants.hasFreeCast(
                        spellID: spell.id, character: character, content: content
                    ) ? CharacterSpellGrants.freeCastResourceID(spellID: spell.id) : nil
                )
            }
        }
    }

    /// Apply the rest, then either show the refresh-resolution sheet (if any
    /// pools refresh by dice roll) or just commit silently. After a Long Rest,
    /// unlimited-prep casters (cleric/druid/paladin/wizard) get prompted to
    /// rebuild their prep list — the natural moment for it. Fixed-table /
    /// pact casters aren't asked (they only swap on level-up).
    private func takeRest(_ kind: RestKind) {
        let pending = ResourceCalculator.applyRest(kind, to: &character, content: content)
        if !pending.isEmpty {
            pendingRefreshes = pending
        }
        if kind == .long && hasUnlimitedPrepCaster {
            showPrepareAfterRest = true
        }
    }

    /// Any of the character's classes rebuild their prep list from scratch
    /// (cleric/druid/paladin from the whole class list, wizard from spellbook).
    /// Fixed-table classes (bard/sorcerer/ranger/warlock) are excluded — they
    /// swap on level-up, so a long-rest prompt would misinform.
    private var hasUnlimitedPrepCaster: Bool {
        character.classEntries.contains { entry in
            guard let block = content.classDefinition(id: entry.classID)?.spellcasting
            else { return false }
            let isPrep = block.preparedRule == .preparedFromAll
                || block.preparedRule == .preparedFromBook
            return isPrep && block.spellsKnown == nil
        }
    }

    private var actionSections: [ActionSection] {
        CharacterActionDeriver.sections(for: character, content: content)
    }

    private func handleActionTap(_ row: ActionRow) {
        // Cast-from-item rows divert to the spell cast sheet — the sheet
        // pays the charge cost itself based on the chosen slot level.
        if let ctx = row.castFromItem {
            guard let spell = content.spellDefinition(id: ctx.spellID) else { return }
            spellBeingCast = PendingSpellCast(spell: spell, itemContext: ctx)
            return
        }

        // Toggle rows (Rage) flip an effect on/off instead of rolling. The
        // activate tap pays the resource cost; the deactivate tap is free
        // (Rage doesn't refund a use when you drop it early).
        if let toggle = row.toggleEffect {
            if !toggle.isActive, let resourceID = toggle.resourceID {
                let ok = ResourceCalculator.consume(
                    amount: 1,
                    from: resourceID,
                    in: &character,
                    content: content
                )
                guard ok else { return }
            }
            character.toggleFeatureEffect(
                effectID: toggle.effectID,
                featureID: toggle.featureID,
                roundsRemaining: toggle.roundsRemaining
            )
            return
        }

        let action = row.action

        // No-formula action (Action Surge): nothing to roll, so the tap IS the
        // commitment — spend the resource now.
        guard action.formula != nil else {
            if let cost = action.resourceCost {
                _ = ResourceCalculator.consume(
                    amount: cost.amount, from: cost.resourceID, in: &character, content: content
                )
            }
            return
        }

        // Rollable action (Second Wind, etc.): don't spend the resource on tap.
        // The cost rides along on the ResolvedAction; the dice tab parks it and
        // we debit only when the roll actually fires (audit #2). Guard against
        // an exhausted pool up front so a 0-charge action can't be queued.
        if let cost = action.resourceCost {
            let available = ResourceCalculator.current(
                character: character, content: content, resourceID: cost.resourceID
            )
            guard available >= cost.amount else { return }
        }
        pendingRoll.pendingCharacterID = character.id
        pendingRoll.pending = action
        selectedTab = .dice
    }

    /// Sheet hands us one roll at a time plus the list of chained damage /
    /// heal follow-ups. Each follow-up lands on the store as a chip; the
    /// dice tab pulls them out after the primary roll settles and surfaces
    /// them as "Roll damage?" prompts. Ice Knife emits two chips
    /// (piercing + cold explosion); Fire Bolt emits one; Detect Magic emits
    /// none.
    private func handleSpellRoll(_ action: ResolvedAction, followUps: [ResolvedAction]) {
        pendingRoll.pendingCharacterID = character.id
        pendingRoll.pending = action
        pendingRoll.followUps = followUps.map { .chainedDamage($0) }
        selectedTab = .dice
    }

    /// Resolve a recipe and hand it to the dice tab. If the user picked
    /// advantage/disadvantage, the formula's plain d20 group is expanded to
    /// 2d20kh1 / 2d20kl1 so the tray actually rolls two dice and drops one.
    private func dispatchRoll(_ recipe: ActionRecipe, mode: RollMode) {
        // A STR/DEX save under Paralyzed/Stunned/etc. auto-fails — surface that
        // instead of rolling a die that can't matter.
        if case .savingThrow(let ability) = recipe,
           let condition = CharacterCalculator.autoFailedSaveCondition(
               character: character, content: content, ability: ability
           ) {
            autoFailedSave = AutoFailedSave(ability: ability, conditionName: condition)
            return
        }
        // Indomitable Might: pre-flooring the d20 so `d20 + mod ≥ ability
        // score` holds. Applies to ability checks, STR/DEX/… saves, and
        // ability-scoped skill checks (Athletics under STR floor).
        let abilityFloor: Int? = {
            switch recipe {
            case .abilityCheck(let a):
                return CharacterCalculator.abilityCheckFloor(character: character, content: content, ability: a)
            case .savingThrow(let a):
                return CharacterCalculator.abilityCheckFloor(character: character, content: content, ability: a)
            case .skillCheck(let s):
                return CharacterCalculator.abilityCheckFloor(character: character, content: content, ability: s.ability)
            default:
                return nil
            }
        }()
        // Feature-selection option bonuses on skill checks (Druid Primal Order
        // Magician → +WIS on Arcana/Nature). Only meaningful for skillCheck
        // recipes; zero for everything else.
        let optionSkillBonus: Int = {
            if case .skillCheck(let s) = recipe {
                return CharacterCalculator.optionSkillAbilityBonus(
                    character: character, content: content, skill: s
                )
            }
            return 0
        }()
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: character,
            weapon: nil,
            // Reliable Talent et al. — feature-derived skill-check floor.
            skillCheckFloor: CharacterCalculator.skillCheckFloor(character: character, content: content),
            // Bard's Jack of All Trades — half PB on non-proficient checks.
            jackOfAllTrades: CharacterCalculator.hasJackOfAllTrades(character: character, content: content),
            abilityCheckFloor: abilityFloor,
            optionSkillBonus: optionSkillBonus
        )
        // Fold the character's conditions into the roll mode (Poisoned →
        // disadvantage on attacks/checks, Restrained → DEX-save disadvantage,
        // Invisible → attack advantage; adv + dis cancels).
        let effectiveMode = CharacterCalculator.conditionAdjustedMode(
            for: recipe, userMode: mode, character: character, content: content
        )
        var formula = applyAdvantage(to: resolved.formula, mode: effectiveMode)
        // Bless and similar buffs add dice (1d4) to saving throws. Attack rolls
        // get theirs in handleWeaponAttack / the spell sheet; ability & skill
        // checks don't qualify.
        if case .savingThrow = recipe {
            let blessDice = CharacterCalculator.attackSaveBuffDiceGroups(character: character, content: content)
            if !blessDice.isEmpty, formula != nil {
                formula?.groups.append(contentsOf: blessDice)
            }
        }
        // The interpreter's label includes the modifier ("Athletics +5") for
        // the on-sheet button, but in history that just duplicates the formula
        // line, so we use a cleaner recipe-based name there. Note when a
        // condition forced adv/dis the user didn't pick, so it isn't silent.
        var historyLabel = historyLabel(for: recipe) ?? resolved.label
        if effectiveMode != mode {
            historyLabel += effectiveMode == .disadvantage ? " (Disadvantage)"
                : effectiveMode == .advantage ? " (Advantage)" : ""
        }
        pendingRoll.pendingCharacterID = character.id
        pendingRoll.pending = ResolvedAction(
            id: resolved.id,
            label: historyLabel,
            formula: formula,
            description: resolved.description
        )
        selectedTab = .dice
    }

    /// Roll a death-save d20 in the in-sheet mini tray. The app rolled the
    /// die, so the result is trusted — `applyDeathSaveResult` tallies it
    /// automatically (the manual circles remain for physical-dice tables).
    private func rollDeathSave() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        quickRoll = QuickRollRequest(formula: formula, label: "Death Save")
    }

    private func applyDeathSaveResult(_ result: RollResult) {
        let die = result.dieRolls.first?.value ?? result.total
        character.applyDeathSaveRoll(die)
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
        // Delegated to the pure, unit-tested `DiceFormula.applyingAdvantage`,
        // which preserves a Reliable Talent `minimumValue` floor on the
        // expanded 2d20kh1/kl1 group (a plain group's `isPlain` ignores the
        // floor, so advantage + floor compose).
        base?.applyingAdvantage(mode)
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
            HPEditorSheet(
                character: $character,
                onConcentrationCheck: { pendingConcentrationCheck = $0 }
            )
            .presentationDetents([.medium])
        }
    }

    /// Header `-` button. Routes through the model so concentration prompts
    /// surface even on incremental clicks.
    private func applyHeaderDamage(_ amount: Int) {
        var copy = character
        let pendingCheck = copy.applyDamage(amount)
        character = copy
        if let pendingCheck {
            pendingConcentrationCheck = pendingCheck
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
                    applyHeaderDamage(1)
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
            StatChip(label: "Init", value: initiativeLabel, systemImage: "bolt.fill", tint: .yellow)
        }
    }

    /// Init modifier with an "(Adv)" suffix when the character has a feature
    /// granting Initiative Advantage (Barbarian Feral Instinct at L7). No
    /// tappable roll yet — the chip stays informational.
    private var initiativeLabel: String {
        let base = initiativeBonus.formattedModifier
        return CharacterCalculator.hasInitiativeAdvantage(character: character, content: content)
            ? "\(base) (Adv)"
            : base
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

    // MARK: - Derived values

    private var primaryClassName: String? {
        // "Druid" single-class, "Druid 3 / Cleric 2" once multiclassed.
        CharacterCalculator.classSummary(character: character, content: content)
    }

    private var speciesName: String? {
        content.speciesDefinition(id: character.speciesID)?.name
    }

    private var speedFt: Int {
        let base = content.speciesDefinition(id: character.speciesID)?.speed ?? 30
        // Unarmored Movement (Monk) / Fast Movement (Barbarian) apply only
        // with no body armor and no shield.
        let featureBonus = CharacterCalculator.featureSpeedBonus(
            character: character, content: content,
            unarmored: equippedArmor == nil && !hasShield
        )
        return base + featureBonus + CharacterCalculator.spellSpeedBonus(character: character, content: content)
    }

    private var armorClass: Int {
        let dexScore = character.abilityScores[.dexterity] ?? 10
        let dexMod = CharacterCalculator.abilityModifier(score: dexScore)
        let fsBonus = CharacterCalculator.defenseACBonus(
            character: character,
            wearingArmor: equippedArmor != nil
        )
        // Unarmored Defense (Barbarian/Draconic Sorcerer/Monk): the granting
        // feature's ability mod, applied only while no armor is worn.
        var unarmoredBonus = 0
        if equippedArmor == nil,
           let ability = CharacterCalculator.unarmoredDefenseAbility(character: character, content: content) {
            unarmoredBonus = CharacterCalculator.abilityModifier(score: character.abilityScores[ability] ?? 10)
        }
        return CharacterCalculator.armorClass(
            dexMod: dexMod,
            armor: equippedArmor,
            hasShield: hasShield,
            fightingStyleBonus: fsBonus,
            unarmoredDefenseBonus: unarmoredBonus,
            // Active buff spells: flat AC (Shield, Shield of Faith) + an
            // unarmored base override (Mage Armor → 13 + DEX, no armor only).
            spellACBonus: CharacterCalculator.spellACBonus(character: character, content: content),
            unarmoredACBase: equippedArmor == nil
                ? CharacterCalculator.spellUnarmoredACBase(character: character, content: content)
                : nil
        )
    }

    private var initiativeBonus: Int {
        CharacterCalculator.initiativeBonus(character: character)
    }

    private var passivePerception: Int {
        CharacterCalculator.passivePerception(character: character, content: content)
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
            return ToolNames.display(name)
        }.sorted()
    }

}

/// Sheet `item:` binding payload. Wraps the spell with an optional item
/// context so the cast sheet can swap its slot picker for an item-charges
/// picker when the cast originated from a magic item.
struct PendingSpellCast: Identifiable, Equatable {
    let id: String
    let spell: SpellDefinition
    let itemContext: ItemSpellCastContext?
    /// Casting ability for species-granted spells (used by the sheet only when
    /// the character has no class spellcasting ability). Nil for class casts.
    let innateAbility: Ability?
    /// Resource id of the spell's once-per-Long-Rest free cast, when it's a
    /// leveled species grant. Nil for cantrips, class spells, and item casts.
    let freeCastResourceID: String?

    init(
        spell: SpellDefinition,
        itemContext: ItemSpellCastContext?,
        innateAbility: Ability? = nil,
        freeCastResourceID: String? = nil
    ) {
        self.spell = spell
        self.itemContext = itemContext
        self.innateAbility = innateAbility
        self.freeCastResourceID = freeCastResourceID
        // Stable id per invocation source — re-tapping the same row reuses
        // the same id so SwiftUI doesn't double-present.
        if let ctx = itemContext {
            self.id = "item_\(ctx.resourceID)_\(spell.id)"
        } else {
            self.id = "slot_\(spell.id)"
        }
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


// MARK: - Module-wide formatting helper

extension Int {
    /// Formats an ability/skill/save modifier as "+5" or "−2". Uses U+2212 MINUS
    /// SIGN for negatives so it lines up nicely with the "+" in monospaced fonts.
    var formattedModifier: String {
        self >= 0 ? "+\(self)" : "−\(abs(self))"
    }
}
