import SwiftUI

/// Collapsible inventory list. Equipped items sit on top, the rest underneath,
/// with a total weight footer. Items are tagged with a small kind icon
/// (weapon / armor / gear) so the list scans quickly. Editing arrives in Phase G.
struct InventoryView: View {
    let character: Character
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 6) {
                if equippedRows.isEmpty && carriedRows.isEmpty {
                    Text("Inventory is empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } else {
                    if !equippedRows.isEmpty {
                        SubsectionHeader("Equipped")
                        ForEach(equippedRows) { ItemRow(row: $0) }
                    }
                    if !carriedRows.isEmpty {
                        SubsectionHeader("Carried")
                            .padding(.top, equippedRows.isEmpty ? 0 : 8)
                        ForEach(carriedRows) { ItemRow(row: $0) }
                    }
                    Divider().padding(.top, 6)
                    HStack {
                        Text("Total weight")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f lb", totalWeight))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Inventory", systemImage: "bag.fill")
                .font(.headline)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Derived rows

    private var allRows: [InventoryRow] {
        character.inventory.map { item in
            InventoryRow(
                id: item.id,
                name: content.itemName(forItemID: item.itemID) ?? item.itemID,
                quantity: item.quantity,
                equipped: item.equipped,
                attuned: item.attuned,
                weight: content.itemWeight(forItemID: item.itemID) ?? 0,
                kind: itemKind(for: item.itemID)
            )
        }
    }

    private var equippedRows: [InventoryRow] {
        allRows.filter(\.equipped).sorted { $0.name < $1.name }
    }

    private var carriedRows: [InventoryRow] {
        allRows.filter { !$0.equipped }.sorted { $0.name < $1.name }
    }

    private var totalWeight: Double {
        allRows.reduce(0) { $0 + $1.weight * Double($1.quantity) }
    }

    private func itemKind(for id: String) -> InventoryRow.Kind {
        if content.weaponDefinition(id: id) != nil { return .weapon }
        if content.armorDefinition(id: id) != nil { return .armor }
        return .gear
    }
}

// MARK: - Row model + view

private struct InventoryRow: Identifiable {
    let id: UUID
    let name: String
    let quantity: Int
    let equipped: Bool
    let attuned: Bool
    let weight: Double
    let kind: Kind

    enum Kind {
        case weapon, armor, gear

        var systemImage: String {
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

private struct ItemRow: View {
    let row: InventoryRow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.kind.systemImage)
                .foregroundStyle(row.kind.tint)
                .font(.caption)
                .frame(width: 18)
            Text(row.name)
                .font(.subheadline)
            if row.quantity > 1 {
                Text("× \(row.quantity)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if row.attuned {
                Text("attuned")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.18), in: Capsule())
                    .foregroundStyle(.purple)
            }
            Spacer()
            if row.weight > 0 {
                Text(String(format: "%.1f lb", row.weight * Double(row.quantity)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SubsectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
