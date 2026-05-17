import SwiftUI

/// Compact row of condition pills shown under the HP bar. Each pill displays
/// the condition name; tapping it removes the condition, long-press opens a
/// description. An "Add" pill on the right opens the picker sheet.
struct ConditionsRow: View {
    @Binding var character: Character
    let onAdd: () -> Void
    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(character.conditions) { cond in
                    pill(for: cond)
                }
                addPill
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func pill(for cond: CharacterCondition) -> some View {
        let def = content.conditionDefinition(id: cond.id)
        return Menu {
            if let def {
                Text(def.description)
            }
            Button(role: .destructive) {
                character.removeCondition(id: cond.id)
            } label: {
                Label("Remove", systemImage: "xmark.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(def?.name ?? cond.id.capitalized)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.22), in: Capsule())
            .foregroundStyle(.orange)
        }
    }

    private var addPill: some View {
        Button(action: onAdd) {
            Label("Add", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Picker for applying a new condition. Lists all definitions from the content
/// store; tapping one applies it and dismisses.
struct AddConditionSheet: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(content.allConditions) { def in
                Button {
                    character.applyCondition(id: def.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(def.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if character.conditions.contains(where: { $0.id == def.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(def.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Banner pinned above the spells list when the character is concentrating.
/// Tappable Drop button clears concentration manually (separate from the
/// damage-triggered save).
struct ConcentrationPin: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content

    var body: some View {
        if let spellID = character.concentratingSpellID,
           let spell = content.spellDefinition(id: spellID) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Concentrating")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(spell.name)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button("Drop") {
                    character.stopConcentrating()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.purple)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.purple.opacity(0.35), lineWidth: 0.5)
            )
        }
    }
}
