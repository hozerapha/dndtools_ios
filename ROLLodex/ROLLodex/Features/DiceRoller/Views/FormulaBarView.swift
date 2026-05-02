import SwiftUI

struct FormulaBarView: View {
    let formula: DiceFormula
    let mode: RollMode
    let onSubmit: (DiceFormula) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if isEditing {
                    TextField("e.g. 1d20+3", text: $draft)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit { commit() }
                        .font(.system(.title3, design: .rounded, weight: .semibold))

                    Button("Done") { commit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button {
                        cancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text(formula.displayString)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: formula.displayString)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditing() }

                    if mode != .normal {
                        Text(mode.shortLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(mode == .advantage ? Color.green : Color.red,
                                        in: Capsule())
                    }

                    Button {
                        startEditing()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit formula")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: isEditing)
        .animation(.snappy, value: errorMessage)
    }

    private func startEditing() {
        draft = formula.isEmpty ? "" : sanitized(formula.displayString)
        errorMessage = nil
        isEditing = true
        DispatchQueue.main.async { focused = true }
    }

    private func sanitized(_ s: String) -> String {
        s.replacingOccurrences(of: "−", with: "-")
         .replacingOccurrences(of: " ", with: "")
    }

    private func commit() {
        do {
            let parsed = try DiceFormulaParser().parse(draft)
            onSubmit(parsed)
            isEditing = false
            errorMessage = nil
            focused = false
        } catch let error as DiceFormulaParser.ParseError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't parse formula."
        }
    }

    private func cancel() {
        isEditing = false
        errorMessage = nil
        focused = false
    }
}
