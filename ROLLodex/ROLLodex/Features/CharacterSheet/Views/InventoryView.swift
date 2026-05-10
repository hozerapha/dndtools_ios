import SwiftUI

/// Editable inventory list. Equipped items sit on top, the rest underneath,
/// with a total weight footer and an attunement counter. Each row exposes
/// equip/attune/qty/delete controls; the "+" in the header opens a search
/// sheet over the full content store. Equipment changes immediately
/// re-derive AC and the action grid since both read from the bound character.
struct InventoryView: View {
    @Binding var character: Character
    @Environment(ContentStore.self) private var content
    @State private var expanded: Bool = true
    @State private var showAddSheet = false

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
                        ForEach(equippedRows) { row in
                            inventoryRow(for: row)
                        }
                    }
                    if !carriedRows.isEmpty {
                        SubsectionHeader("Carried")
                            .padding(.top, equippedRows.isEmpty ? 0 : 8)
                        ForEach(carriedRows) { row in
                            inventoryRow(for: row)
                        }
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
                    HStack {
                        Text("Attunement")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(attunedCount) / \(attunementLimit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(attunedCount > attunementLimit ? .red : .primary)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Inventory", systemImage: "bag.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add item")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showAddSheet) {
            ItemPickerSheet { itemID in
                addItem(itemID: itemID)
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Derived rows

    private var allRows: [InventoryRow] {
        character.inventory.map { item in
            InventoryRow(
                id: item.id,
                itemID: item.itemID,
                name: content.itemName(forItemID: item.itemID) ?? item.itemID,
                description: content.itemDescription(forItemID: item.itemID) ?? "",
                quantity: item.quantity,
                equipped: item.equipped,
                attuned: item.attuned,
                weight: content.itemWeight(forItemID: item.itemID) ?? 0,
                kind: itemKind(for: item.itemID),
                weaponBreakdown: CharacterCalculator.weaponRollBreakdown(
                    weaponID: item.itemID,
                    character: character,
                    content: content
                )
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

    private var attunedCount: Int {
        character.inventory.filter(\.attuned).count
    }

    private var attunementLimit: Int {
        CharacterCalculator.attunementLimit(character: character, content: content)
    }

    private func hasAttunementSlot(for row: InventoryRow) -> Bool {
        row.attuned || attunedCount < attunementLimit
    }

    private func eligibility(for row: InventoryRow) -> CharacterCalculator.AttunementEligibility {
        CharacterCalculator.attunementEligibility(
            itemID: row.itemID,
            character: character,
            content: content
        )
    }

    /// Builds an `ItemRow` with the eligibility + slot-cap context plumbed in.
    /// Extracted so the equipped and carried lists don't repeat the closures.
    @ViewBuilder
    private func inventoryRow(for row: InventoryRow) -> some View {
        ItemRow(
            row: row,
            attunementAvailable: hasAttunementSlot(for: row),
            attunementEligibility: eligibility(for: row),
            onToggleEquip: { toggleEquip(itemUUID: row.id) },
            onToggleAttune: { toggleAttune(itemUUID: row.id) },
            onAdjustQuantity: { delta in adjustQuantity(itemUUID: row.id, delta: delta) },
            onDelete: { delete(itemUUID: row.id) }
        )
    }

    private func itemKind(for id: String) -> InventoryRow.Kind {
        if content.weaponDefinition(id: id) != nil { return .weapon }
        if content.armorDefinition(id: id) != nil { return .armor }
        return .gear
    }

    // MARK: - Mutations

    private func toggleEquip(itemUUID: UUID) {
        guard let i = character.inventory.firstIndex(where: { $0.id == itemUUID }) else { return }
        character.inventory[i].equipped.toggle()
    }

    private func toggleAttune(itemUUID: UUID) {
        guard let i = character.inventory.firstIndex(where: { $0.id == itemUUID }) else { return }
        let item = character.inventory[i]
        // Always allow unattuning. Block attuning if either the slot cap is
        // reached OR the item's restrictions exclude this character.
        if !item.attuned {
            if attunedCount >= attunementLimit { return }
            switch CharacterCalculator.attunementEligibility(
                itemID: item.itemID, character: character, content: content
            ) {
            case .notRequired, .blocked: return
            case .eligible: break
            }
        }
        character.inventory[i].attuned.toggle()
    }

    private func adjustQuantity(itemUUID: UUID, delta: Int) {
        guard let i = character.inventory.firstIndex(where: { $0.id == itemUUID }) else { return }
        let newQty = character.inventory[i].quantity + delta
        if newQty <= 0 {
            character.inventory.remove(at: i)
        } else {
            character.inventory[i].quantity = newQty
        }
    }

    private func delete(itemUUID: UUID) {
        character.inventory.removeAll { $0.id == itemUUID }
    }

    /// Add a stack from the picker. If the user already owns the item, bump
    /// the quantity instead of creating a duplicate stack.
    private func addItem(itemID: String) {
        if let i = character.inventory.firstIndex(where: { $0.itemID == itemID }) {
            character.inventory[i].quantity += 1
        } else {
            character.inventory.append(InventoryItem(itemID: itemID, quantity: 1))
        }
    }
}

// MARK: - Row model + view

private struct InventoryRow: Identifiable {
    let id: UUID
    let itemID: String
    let name: String
    let description: String
    let quantity: Int
    let equipped: Bool
    let attuned: Bool
    let weight: Double
    let kind: Kind
    /// Per-character attack/damage breakdown for weapons. Nil for non-weapons.
    let weaponBreakdown: WeaponRollBreakdown?

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

/// Tap the row to expand its edit panel (equip / attune / qty / delete).
/// Keeping the controls hidden until expansion keeps the list tight when the
/// user is just reading their inventory.
private struct ItemRow: View {
    let row: InventoryRow
    let attunementAvailable: Bool
    let attunementEligibility: CharacterCalculator.AttunementEligibility
    let onToggleEquip: () -> Void
    let onToggleAttune: () -> Void
    let onAdjustQuantity: (Int) -> Void
    let onDelete: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                rowSummary
            }
            .buttonStyle(.plain)
            if expanded {
                editPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    private var rowSummary: some View {
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
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.description.isEmpty {
                Text(row.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let breakdown = row.weaponBreakdown {
                weaponBreakdownBlock(breakdown)
            }
            HStack(spacing: 12) {
                Toggle(isOn: equipBinding) {
                    Label("Equipped", systemImage: row.equipped ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .tint(.blue)

                if attunementEligibility != .notRequired {
                    Toggle(isOn: attuneBinding) {
                        Label("Attuned", systemImage: row.attuned ? "sparkles" : "sparkle")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .tint(.purple)
                    .disabled(!attunementAvailable || isBlockedByRestriction)
                }
            }

            if case .blocked(let reason) = attunementEligibility {
                Label(reason, systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Qty").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Button { onAdjustQuantity(-1) } label: {
                        Image(systemName: "minus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Text("\(row.quantity)").font(.subheadline.monospacedDigit()).frame(minWidth: 20)
                    Button { onAdjustQuantity(+1) } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.top, 6)
        .padding(.leading, 26)
    }

    // SwiftUI Toggles want a Binding<Bool>. The underlying state lives on the
    // character, so we synthesize bindings that fan out to the parent's
    // `onToggle…` closures.
    private var equipBinding: Binding<Bool> {
        Binding(get: { row.equipped }, set: { _ in onToggleEquip() })
    }

    private var attuneBinding: Binding<Bool> {
        Binding(get: { row.attuned }, set: { _ in onToggleAttune() })
    }

    private var isBlockedByRestriction: Bool {
        if case .blocked = attunementEligibility { return true }
        return false
    }

    @ViewBuilder
    private func weaponBreakdownBlock(_ b: WeaponRollBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            breakdownLine(label: "Attack", line: b.attack)
            breakdownLine(label: "Damage", line: b.damage, trailing: b.damageType)
            if let v = b.versatile {
                breakdownLine(label: "2H", line: v, trailing: b.damageType)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func breakdownLine(label: String, line: WeaponRollLine, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(line.formula)
                .font(.subheadline.monospacedDigit().weight(.semibold))
            if let trailing {
                Text(trailing.lowercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(line.breakdown)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
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
