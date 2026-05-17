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

    @Environment(HistoryStore.self) private var history
    @Environment(PresetStore.self) private var presets
    @Environment(PendingRollStore.self) private var pendingRoll

    @AppStorage("character.autoRoll.enabled") private var autoRollEnabled = false

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

    /// Rail of chips that appears below the tray once the primary roll has
    /// landed: a "Roll damage" chip from the weapon-attack pairing plus any
    /// opt-in riders (Sneak Attack, Divine Smite). Each chip is an
    /// alternative damage roll for the same attack — tapping any one fires
    /// and clears the rest, so the player rolls damage once. Manual formula
    /// edits clear the rail too.
    @ViewBuilder
    private var followUpRail: some View {
        if !pendingFollowUps.isEmpty, lastResult != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingFollowUps) { followUp in
                        chip(for: followUp)
                    }
                }
                .padding(.vertical, 2)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func chip(for followUp: PendingFollowUp) -> some View {
        let prompt = followUp.chipPrompt ?? followUpPrompt(for: followUp.action)
        // Subtitle prefers the formula's display string ("1d8 + 1d6 + 3
        // piercing") so both chips read as comparable damage-roll options
        // rather than echoing their own internal action labels.
        let subtitle = followUp.action.formula?.compactDisplayString ?? followUp.action.label
        // Rider chips (any with a once-per-turn cost) get the bolt glyph to
        // telegraph "fires a finite resource" vs. the plain arrow for the
        // default chained roll.
        let icon = followUp.cost == nil ? "arrow.right.circle.fill" : "bolt.fill"
        return Button {
            consumeFollowUp(followUp)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(prompt)
                        .font(.subheadline.weight(.semibold))
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

    private func followUpPrompt(for action: ResolvedAction) -> String {
        let label = action.label.lowercased()
        if label.contains("damage") { return "Roll damage" }
        if label.contains("heal")   { return "Roll heal" }
        return "Roll next"
    }

    private func consumeFollowUp(_ followUp: PendingFollowUp) {
        // The whole rail is a single damage-roll choice for the current
        // attack (Roll Damage vs. Use Sneak Attack vs. Use Divine Smite …).
        // Whichever one fires, the rest go away — you only roll damage once.
        pendingFollowUps = []
        // Park the cost on the store so the character sheet — which owns the
        // character binding — can apply it (set turn flag, etc.). Keeps the
        // dice tab character-agnostic.
        if let cost = followUp.cost {
            pendingRoll.pendingCostsToApply.append(cost)
        }
        guard let nextFormula = followUp.action.formula else { return }
        applyLabeled(formula: nextFormula, label: followUp.action.label)
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
        pendingRoll.pending = nil
        pendingRoll.followUps = []

        // saveDC and other info-only actions have no formula — nothing to load.
        guard let resolvedFormula = resolved.formula else { return }
        applyLabeled(formula: resolvedFormula, label: resolved.label)
        // Set the follow-ups AFTER applyLabeled so the formula's onChange
        // (which would have cleared a stale rail on manual edits) sees the
        // new labelBoundFormula match and leaves us alone.
        pendingFollowUps = nextFollowUps
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
        guard !isRolling,
              formula.totalDiceCount > 0,
              formula.allKinds3DSupported else { return }
        isRolling = true
        lastResult = nil
        magnifyingDieIndices = []
        // Strip any glow from the prior settled state — otherwise the colored
        // lights would tumble with the dice mid-roll. We re-apply on settle.
        controller.clearGlow()

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
