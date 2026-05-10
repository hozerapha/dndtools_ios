import SwiftUI

/// Free-form notes section (campaign reminders, character backstory, anything
/// the user types). Collapsed by default to keep the sheet tight.
struct NotesEditorView: View {
    @Binding var notes: String
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Tap to add notes…")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .font(.subheadline)
                    .frame(minHeight: 120)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                if !notes.isEmpty {
                    Text("\(notes.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
