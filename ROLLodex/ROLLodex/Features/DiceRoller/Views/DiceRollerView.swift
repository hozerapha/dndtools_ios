import SwiftUI

struct DiceRollerView: View {
    @State private var formula = DiceFormula()
    @State private var lastResult: RollResult?
    @State private var showHistory = false
    @State private var showSavePreset = false
    @State private var isRolling = false
    @State private var controller = DiceSceneController()
    /// Friendly label for the current formula — set by sheet handoffs, preset
    /// taps, and history rerolls. Cleared automatically when the user edits
    /// the formula directly (picker, formula bar, clear, etc.). Stamped onto
    /// the resulting RollResult so the history sheet can show "Sleight of
    /// Hand Check (adv): 25" instead of just "2d20kh1+5: 25".
    @State private var pendingLabel: String?
    /// Snapshot of the formula at the moment `pendingLabel` was set. If the
    /// live formula drifts away from this snapshot, the label has gone stale
    /// (the user reshaped the dice) and we drop it.
    @State private var labelBoundFormula: DiceFormula?
    /// Indices in the controller's `dice` array currently being magnified
    /// (press-and-hold). Empty when no finger is pressing a settled die. One
    /// element for standalone kinds, two for a d100 (tens then ones) — the
    /// SwiftUI overlay walks this and stamps one circular `MagnifierView` per
    /// element. Set on the first onChanged of the magnifier gesture, cleared
    /// on release / new roll / formula change.
    @State private var magnifyingDieIndices: [Int] = []
    /// Secondary actions handed in alongside the primary — e.g. the damage
    /// chained after a weapon attack, plus any opt-in riders (Sneak Attack,
    /// Divine Smite) the character qualifies for. Rendered as chips under the
    /// tray once the primary roll settles. Each chip pays its `cost` (if any)
    /// when tapped, then drops out of the list so it can't double-fire. Any
    /// manual formula edit clears the whole rail — the queued chips stop
    /// matching the dice once the player has touched the picker.
    @State private var pendingFollowUps: [PendingFollowUp] = []
    /// Opt-in damage riders for the current attack, and which the player has
    /// toggled on. The base damage chip rolls the base + active riders combined.
    @State private var pendingRiders: [DamageRider] = []
    @State private var activeRiderIDs: Set<String> = []
    @State private var showStrokeOfLuckPrompt = false
    @State private var strokeOfLuckContext: StrokeOfLuckContext?
    @State private var rollingCharacterID: UUID?
    @State private var rollCameFromCharacterSheet = false

    /// Snapshot of a settled roll + raw physics values so Stroke of Luck can
    /// rebuild the result with a forced 20 on the d20 group.
    private struct StrokeOfLuckContext {
        let result: RollResult
        let values: [Int]
    }

    @Environment(HistoryStore.self) private var history
    @Environment(PresetStore.self) private var presets
    @Environment(PendingRollStore.self) private var pendingRoll
    @Environment(CharacterStore.self) private var characterStore
    @Environment(ContentStore.self) private var contentStore

    @AppStorage("character.autoRoll.enabled") private var autoRollEnabled = false
    @AppStorage(CritStyle.storageKey) private var critStyleRaw = CritStyle.default.rawValue
    private var critStyle: CritStyle { CritStyle(rawValue: critStyleRaw) ?? .default }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                FormulaBarView(formula: formula) { parsed in
                    formula = parsed
                }
                .disabled(isRolling)

                tray
                    .frame(maxHeight: .infinity)

                followUpRail

                bottomControls
                    .disabled(isRolling)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .navigationTitle("ROLLodex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
            }
            .sheet(isPresented: $showHistory) {
                HistorySheet { selected in
                    applyLabeled(formula: selected.formula, label: selected.label)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSavePreset) {
                SavePresetSheet(formula: formula)
                    .presentationDetents([.medium])
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: lastResult?.id)
            .onAppear {
                // Only seed the tray if the controller is empty — re-entering the tab
                // shouldn't reset dice that are already showing a previous roll.
                if controller.diceCount == 0 && formula.totalDiceCount > 0 {
                    controller.setDice(formula: formula)
                }
                consumePendingRollIfNeeded()
            }
            .onChange(of: pendingRoll.pending) { _, _ in
                consumePendingRollIfNeeded()
            }
            .onChange(of: formula) { _, new in
                // Reset the visible tray + last result whenever the formula changes
                // (picker tap, paste into the bar, history tap, preset tap, etc.).
                guard !isRolling else { return }
                controller.setDice(formula: new)
                lastResult = nil
                magnifyingDieIndices = []
                // Drop a stale label if the user reshaped the formula manually.
                // Labeled handoffs always set labelBoundFormula == new, so this
                // only fires for direct picker / formula-bar / clear edits.
                if labelBoundFormula != new {
                    pendingLabel = nil
                    labelBoundFormula = nil
                    // Once the user has touched the dice manually, queued
                    // chips no longer pair with what's in the tray.
                    pendingFollowUps = []
                    pendingRiders = []
                    activeRiderIDs = []
                }
            }
        }
    }

    @ViewBuilder
    private var tray: some View {
        ZStack(alignment: .top) {
            SceneKitView(controller: controller, allowsCameraControl: false)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .gesture(magnifierPressGesture)

            if isRolling {
                Text("Rolling…")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.top, 16)
                    .transition(.opacity)
            } else if let result = lastResult {
                VStack(spacing: 6) {
                    Text("\(result.total)")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(totalColor(for: result))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .contentTransition(.numericText())
                    if result.hasTypedDamage {
                        DamageBreakdownView(result: result, neutralForeground: .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    if showStrokeOfLuckPrompt {
                        strokeOfLuckChip
                    }
                }
                .padding(.top, 16)
                .transition(.scale.combined(with: .opacity))
            }

            if !magnifyingDieIndices.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(magnifyingDieIndices.enumerated()), id: \.offset) { offset, _ in
                        MagnifierView(controller: controller, slot: offset)
                            .frame(width: 130, height: 130)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                // The magnifier sits on top of the tray and must NOT capture the
                // press — otherwise sliding a finger over it would cancel the
                // gesture and the magnifier would flicker.
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: magnifyingDieIndices.isEmpty)
    }

    /// Press-and-hold on the tray: hit-test once at the press start, snap one
    /// magnifier camera per die in the tapped formula slot (1 for standalone,
    /// 2 for a d100 pair), and show those overlays until release.
    /// `minimumDistance: 0` so it fires immediately on touch-down rather than
    /// waiting for movement.
    private var magnifierPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isRolling, magnifyingDieIndices.isEmpty else { return }
                let indices = controller.diceInSlot(at: value.startLocation)
                guard !indices.isEmpty else { return }
                for (slot, idx) in indices.enumerated() {
                    controller.positionMagnifier(slot: slot, forDieIndex: idx)
                }
                magnifyingDieIndices = indices
            }
            .onEnded { _ in
                magnifyingDieIndices = []
            }
    }

    private func totalColor(for result: RollResult) -> Color {
        if result.hasCriticalSuccess { return .green }
        if result.hasCriticalFail { return .red }
        return .white
    }

    private var strokeOfLuckAvailable: Bool {
        guard let characterID = rollingCharacterID,
              let character = characterStore.character(id: characterID) else { return false }
        let current = ResourceCalculator.current(
            character: character,
            content: contentStore,
            resourceID: "rogue_stroke_of_luck"
        )
        return current > 0
    }

    private var strokeOfLuckChip: some View {
        Button {
            applyStrokeOfLuck()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Stroke of Luck")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyStrokeOfLuck() {
        guard let ctx = strokeOfLuckContext,
              let characterID = rollingCharacterID,
              var character = characterStore.character(id: characterID) else {
            showStrokeOfLuckPrompt = false
            strokeOfLuckContext = nil
            return
        }

        let ok = ResourceCalculator.consume(
            amount: 1,
            from: "rogue_stroke_of_luck",
            in: &character,
            content: contentStore
        )
        guard ok else {
            showStrokeOfLuckPrompt = false
            strokeOfLuckContext = nil
            return
        }
        characterStore.save(character)

        var overriddenValues = ctx.values
        var cursor = 0
        for group in ctx.result.formula.groups {
            let endIndex = min(cursor + group.count, overriddenValues.count)
            if group.kind == .d20 {
                for i in cursor..<endIndex {
                    overriddenValues[i] = 20
                }
                break
            }
            cursor += group.count
        }

        let dr = DiceRoller()
        let newResult = dr.resultFrom(
            formula: ctx.result.formula,
            values: overriddenValues,
            mode: ctx.result.mode,
            label: ctx.result.label
        )

        history.removeFirst()
        history.record(newResult)

        lastResult = newResult
        showStrokeOfLuckPrompt = false
        strokeOfLuckContext = nil

        let droppedFormulaIndices = Set(
            newResult.dieRolls.enumerated().compactMap { i, roll in roll.isKept ? nil : i }
        )
        controller.setDimmed(formulaIndices: droppedFormulaIndices)
    }

    /// Rail of chips below the tray once an attack has landed: a "Roll damage"
    /// chip plus a toggle per opt-in rider (Sneak Attack, Divine Smite, …).
    /// Riders are independent toggles — turn on any combination, and the
    /// "Roll damage" chip rolls the base damage plus every active rider as a
    /// single (crit-aware) roll, spending their costs only then. Manual formula
    /// edits clear the rail.
    @ViewBuilder
    private var followUpRail: some View {
        if !pendingFollowUps.isEmpty, lastResult != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingFollowUps) { rollDamageChip(for: $0.action) }
                    ForEach(pendingRiders) { riderToggleChip(for: $0) }
                }
                .padding(.vertical, 2)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Crit transform applies when a crit style is on, the settled roll was a
    /// crit, and this is a damage roll (not a heal).
    private func critApplies(to base: ResolvedAction) -> Bool {
        guard critStyle != .off, lastResult?.hasCriticalSuccess == true else { return false }
        return !base.label.lowercased().contains("heal")
    }

    private var activeRiders: [DamageRider] {
        pendingRiders.filter { activeRiderIDs.contains($0.id) }
    }

    /// Base damage + every active rider's dice, crit-transformed if applicable.
    private func combinedDamageFormula(base: ResolvedAction) -> DiceFormula? {
        guard var formula = base.formula else { return nil }
        for rider in activeRiders { formula = formula.merging(rider.formula) }
        if critApplies(to: base) { formula = formula.applyingCrit(critStyle.rule) }
        return formula
    }

    /// The primary "Roll damage" chip. Its subtitle reflects whatever riders are
    /// toggled on (and crit), so it updates live as the player picks.
    private func rollDamageChip(for base: ResolvedAction) -> some View {
        let crit = critApplies(to: base)
        let prompt = crit ? "Roll critical damage" : followUpPrompt(for: base)
        let subtitle = combinedDamageFormula(base: base)?.compactDisplayString ?? base.label
        return Button {
            rollDamage(base: base)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(prompt).font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// A toggleable rider chip — tap to include/exclude it in the damage roll.
    private func riderToggleChip(for rider: DamageRider) -> some View {
        let active = activeRiderIDs.contains(rider.id)
        return Button {
            if active { activeRiderIDs.remove(rider.id) } else { activeRiderIDs.insert(rider.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(rider.label).font(.subheadline.weight(.semibold))
                    Text(rider.formula.compactDisplayString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func followUpPrompt(for action: ResolvedAction) -> String {
        let label = action.label.lowercased()
        if label.contains("damage") { return "Roll damage" }
        if label.contains("heal")   { return "Roll heal" }
        return "Roll next"
    }

    /// Fire the damage roll: base + active riders combined (crit-aware), paying
    /// each active rider's cost now (only when the roll actually happens), then
    /// clear the rail.
    private func rollDamage(base: ResolvedAction) {
        let crit = critApplies(to: base)
        let riders = activeRiders
        guard let nextFormula = combinedDamageFormula(base: base) else { return }
        // Pay costs only at roll time — abandoning the rail spends nothing.
        for rider in riders {
            if let cost = rider.cost { pendingRoll.pendingCostsToApply.append(cost) }
        }
        var parts = [base.label]
        parts.append(contentsOf: riders.map(\.label))
        var label = parts.joined(separator: " + ")
        if crit { label += " (Critical)" }

        pendingFollowUps = []
        pendingRiders = []
        activeRiderIDs = []
        applyLabeled(formula: nextFormula, label: label)
        if autoRollEnabled {
            Task { await roll() }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 10) {
            if !presets.presets.isEmpty {
                PresetRowView { preset in
                    applyLabeled(formula: preset.formula, label: preset.name)
                }
            }

            modifierRow
            DiePickerView(formula: $formula)
            actionRow
        }
    }

    private var modifierRow: some View {
        HStack(spacing: 12) {
            Text("Modifier")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formattedModifier)
                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
                .contentTransition(.numericText())
            Stepper("Modifier", value: $formula.modifier, in: -50...50)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var formattedModifier: String {
        if formula.modifier > 0 { return "+\(formula.modifier)" }
        if formula.modifier < 0 { return "−\(abs(formula.modifier))" }
        return "0"
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                formula.clear()
                lastResult = nil
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(isRolling)

            Button {
                showSavePreset = true
            } label: {
                Label("Save", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .disabled(isRolling || formula.totalDiceCount == 0)

            Spacer()

            Button {
                Task { await roll() }
            } label: {
                Label("Roll", systemImage: "dice.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRolling || formula.totalDiceCount == 0 || !formula.allKinds3DSupported)
        }
    }

    /// Drain any pending ResolvedAction handed off from the character sheet:
    /// prefill the formula, park any queued follow-up roll, then clear both
    /// store slots. Adv/dis is encoded directly in the formula (e.g. 2d20kh1)
    /// by the caller, so no separate mode is needed. If the user has opted
    /// into auto-roll, kick off a roll immediately.
    private func consumePendingRollIfNeeded() {
        guard !isRolling, let resolved = pendingRoll.pending else { return }
        // Snapshot the follow-ups first; always clear both store slots so a
        // later handoff with no follow-ups doesn't inherit a stale rail.
        let nextFollowUps = pendingRoll.followUps
        let nextRiders = pendingRoll.pendingRiders
        rollingCharacterID = pendingRoll.pendingCharacterID
        rollCameFromCharacterSheet = true
        pendingRoll.pending = nil
        pendingRoll.followUps = []
        pendingRoll.pendingRiders = []
        pendingRoll.pendingCharacterID = nil

        // saveDC and other info-only actions have no formula — nothing to load.
        guard let resolvedFormula = resolved.formula else { return }
        applyLabeled(formula: resolvedFormula, label: resolved.label)
        // Set the follow-ups AFTER applyLabeled so the formula's onChange
        // (which would have cleared a stale rail on manual edits) sees the
        // new labelBoundFormula match and leaves us alone.
        pendingFollowUps = nextFollowUps
        pendingRiders = nextRiders
        activeRiderIDs = []
        if autoRollEnabled {
            Task { await roll() }
        }
    }

    /// Set the formula AND remember that the supplied label should ride along
    /// to the next roll. The matching `labelBoundFormula` snapshot lets the
    /// `onChange(of: formula)` observer tell apart "labeled handoff" from
    /// "user edited the formula manually" — only the latter clears the label.
    private func applyLabeled(formula newFormula: DiceFormula, label: String?) {
        pendingLabel = label
        labelBoundFormula = (label == nil) ? nil : newFormula
        formula = newFormula
    }

    @MainActor
    private func roll() async {
        // If a Stroke of Luck prompt is still showing from a prior roll, commit
        // that result to history before starting a new one.
        if showStrokeOfLuckPrompt, let ctx = strokeOfLuckContext {
            history.record(ctx.result)
            showStrokeOfLuckPrompt = false
            strokeOfLuckContext = nil
        }

        guard !isRolling,
              formula.totalDiceCount > 0,
              formula.allKinds3DSupported else { return }
        isRolling = true
        lastResult = nil
        magnifyingDieIndices = []
        // Strip any glow from the prior settled state — otherwise the colored
        // lights would tumble with the dice mid-roll. We re-apply on settle.
        controller.clearGlow()

        // Only trust rollingCharacterID when this roll was triggered by a
        // character-sheet handoff. Manual rolls clear the context.
        if !rollCameFromCharacterSheet {
            rollingCharacterID = nil
        }
        rollCameFromCharacterSheet = false

        let dr = DiceRoller()

        // 1. Physics-roll every die. Values come back in formula order.
        var values = await controller.rollAllAsync()

        // 2. r2 modifier: physically rethrow any dice that need it. Updated values
        //    replace the originals at the same formula indices.
        let rerollIndices = dr.rerollIndices(formula: formula, values: values)
        if !rerollIndices.isEmpty {
            values = await controller.rethrowDiceAsync(at: Set(rerollIndices))
        }

        // 3. Build the RollResult — applies kh/kl/dh/dl per group to mark kept/dropped.
        let result = dr.resultFrom(formula: formula, values: values, label: pendingLabel)

        // 4. Visually dim the dropped dice. Done after the result is computed so the
        //    fade kicks in once everything has settled and we know what's kept.
        let droppedFormulaIndices = Set(
            result.dieRolls.enumerated().compactMap { i, roll in roll.isKept ? nil : i }
        )
        controller.setDimmed(formulaIndices: droppedFormulaIndices)

        // 5. Damage-type halo: one omni light per die, colored by the source
        //    group's `damageType`. Only typed dice get lights — manual rolls,
        //    ability checks, etc. stay plain.
        controller.setGlow(glowColorsByFormulaIndex())

        // 6. Offer Stroke of Luck if the active character has a charge and this
        //    roll included a d20. Defer history recording until the player
        //    decides (or the prompt is implicitly dismissed by a new roll).
        if strokeOfLuckAvailable,
           result.formula.groups.contains(where: { $0.kind == .d20 }) {
            lastResult = result
            strokeOfLuckContext = StrokeOfLuckContext(result: result, values: values)
            showStrokeOfLuckPrompt = true
            isRolling = false
            return
        }

        lastResult = result
        history.record(result)
        isRolling = false
    }

    /// Walk the live formula and build the per-die map the controller uses to
    /// stamp glow lights. Each group's `damageType` (if any) is assigned to
    /// every die index that group covers.
    private func glowColorsByFormulaIndex() -> [Int: UIColor] {
        var result: [Int: UIColor] = [:]
        var idx = 0
        for group in formula.groups {
            let color = group.damageType?.glowColor
            for _ in 0..<group.count {
                if let color { result[idx] = color }
                idx += 1
            }
        }
        return result
    }
}
