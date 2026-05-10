import SwiftUI

/// Search-and-pick sheet that walks the entire content store (weapons + armor
/// + gear), grouped by kind, with an optional text filter. Tapping a row
/// dispatches its `itemID` and dismisses — quantity defaults to 1 (the
/// inventory view bumps the existing stack if the user taps the same item again).
struct ItemPickerSheet: View {
    let onPick: (String) -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            Button {
                                onPick(entry.id)
                                dismiss()
                            } label: {
                                ItemPickerRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search weapons, armor, gear")
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if visibleSections.allSatisfy(\.entries.isEmpty) {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    // MARK: - Filtering

    private var visibleSections: [PickerSection] {
        [
            PickerSection(title: "Weapons", entries: filter(entries(for: .weapon))),
            PickerSection(title: "Armor",   entries: filter(entries(for: .armor))),
            PickerSection(title: "Gear",    entries: filter(entries(for: .gear)))
        ]
    }

    private func entries(for kind: PickerEntry.Kind) -> [PickerEntry] {
        let ids: [String]
        switch kind {
        case .weapon: ids = Array(content.weapons.keys)
        case .armor:  ids = Array(content.armor.keys)
        case .gear:   ids = Array(content.gear.keys)
        }
        return ids.map { id in
            PickerEntry(
                id: id,
                name: content.itemName(forItemID: id) ?? id,
                weight: content.itemWeight(forItemID: id) ?? 0,
                kind: kind
            )
        }
    }

    private func filter(_ entries: [PickerEntry]) -> [PickerEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty
            ? entries
            : entries.filter { $0.name.lowercased().contains(q) }
        return filtered.sorted { $0.name < $1.name }
    }
}

private struct PickerSection {
    let title: String
    let entries: [PickerEntry]
}

private struct PickerEntry: Identifiable {
    let id: String
    let name: String
    let weight: Double
    let kind: Kind

    enum Kind {
        case weapon, armor, gear

        var icon: String {
            switch self {
            case .weapon: return "burst"
            case .armor: return "shield.fill"
            case .gear: return "shippingbox.fill"
            }
        }

        var tint: Color {
            switch self {
            case .weapon: return .red
            case .armor: return .blue
            case .gear: return .gray
            }
        }
    }
}

private struct ItemPickerRow: View {
    let entry: PickerEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.icon)
                .foregroundStyle(entry.kind.tint)
                .frame(width: 22)
            Text(entry.name)
                .font(.subheadline)
            Spacer()
            if entry.weight > 0 {
                Text(String(format: "%.1f lb", entry.weight))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
