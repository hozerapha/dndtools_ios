import SwiftUI

struct PresetRowView: View {
    let onSelect: (Preset) -> Void
    @Environment(PresetStore.self) private var presets

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets.presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(preset.formula.displayString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.thinMaterial,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            presets.delete(preset)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
