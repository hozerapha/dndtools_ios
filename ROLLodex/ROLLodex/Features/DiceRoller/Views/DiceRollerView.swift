import SwiftUI

struct DiceRollerView: View {
    @State private var formula = DiceFormula()
    @State private var lastResult: RollResult?
    @State private var mode: RollMode = .normal
    @State private var showHistory = false
    @State private var showSavePreset = false
    @State private var isRolling = false
    @State private var controller = DiceSceneController()
    /// Indices in the controller's `dice` array currently being magnified
    /// (press-and-hold). Empty when no finger is pressing a settled die. One
    /// element for standalone kinds, two for a d100 (tens then ones) — the
    /// SwiftUI overlay walks this and stamps one circular `MagnifierView` per
    /// element. Set on the first onChanged of the magnifier gesture, cleared
    /// on release / new roll / formula change.
    @State private var magnifyingDieIndices: [Int] = []

    @Environment(HistoryStore.self) private var history
    @Environment(PresetStore.self) private var presets

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                FormulaBarView(formula: formula, mode: mode) { parsed in
                    formula = parsed
                }
                .disabled(isRolling)

                tray
                    .frame(maxHeight: .infinity)

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
                    formula = selected.formula
                    mode = selected.mode
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
            }
            .onChange(of: formula) { _, new in
                // Reset the visible tray + last result whenever the formula changes
                // (picker tap, paste into the bar, history tap, preset tap, etc.).
                guard !isRolling else { return }
                controller.setDice(formula: new)
                lastResult = nil
                magnifyingDieIndices = []
            }
            .onChange(of: formula.supportsAdvantage) { _, supports in
                if !supports { mode = .normal }
            }
            .animation(.snappy, value: formula.supportsAdvantage)
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
                Text("\(result.total)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(totalColor(for: result))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 16)
                    .contentTransition(.numericText())
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

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 10) {
            if !presets.presets.isEmpty {
                PresetRowView(formula: $formula)
            }

            if formula.supportsAdvantage {
                Picker("Mode", selection: $mode) {
                    ForEach(RollMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .transition(.opacity.combined(with: .move(edge: .top)))
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

    @MainActor
    private func roll() async {
        guard !isRolling,
              formula.totalDiceCount > 0,
              formula.allKinds3DSupported else { return }
        isRolling = true
        lastResult = nil
        magnifyingDieIndices = []

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
        let result = dr.resultFrom(formula: formula, values: values, mode: mode)

        // 4. Visually dim the dropped dice. Done after the result is computed so the
        //    fade kicks in once everything has settled and we know what's kept.
        let droppedFormulaIndices = Set(
            result.dieRolls.enumerated().compactMap { i, roll in roll.isKept ? nil : i }
        )
        controller.setDimmed(formulaIndices: droppedFormulaIndices)

        lastResult = result
        history.record(result)
        isRolling = false
    }
}
