import SwiftUI

struct DiceRollerView: View {
    @State private var formula = DiceFormula()
    @State private var lastResult: RollResult?
    @State private var mode: RollMode = .normal
    @State private var showHistory = false
    @State private var showSavePreset = false

    @Environment(HistoryStore.self) private var history
    @Environment(PresetStore.self) private var presets

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormulaBarView(formula: formula, mode: mode) { parsed in
                        formula = parsed
                    }

                    DiceTrayView(result: lastResult)

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
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
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
            .onChange(of: formula.supportsAdvantage) { _, supports in
                if !supports { mode = .normal }
            }
            .animation(.snappy, value: formula.supportsAdvantage)
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

            Button {
                showSavePreset = true
            } label: {
                Label("Save", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .disabled(formula.totalDiceCount == 0)

            Spacer()

            Button {
                roll()
            } label: {
                Label("Roll", systemImage: "dice.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(formula.totalDiceCount == 0)
        }
    }

    private func roll() {
        let result = DiceRoller().roll(formula, mode: mode)
        lastResult = result
        history.record(result)
    }
}
