import SwiftUI

struct RootView: View {
    @State private var history = HistoryStore()
    @State private var presets = PresetStore()
    @State private var contentStore = ContentStore()
    @State private var characterStore = CharacterStore()

    var body: some View {
        TabView {
            DiceRollerView()
                .tabItem {
                    Label("Dice", systemImage: "dice")
                }

            // Future tabs (initiative, character sheet, etc.) plug in here.
        }
        .environment(history)
        .environment(presets)
        .environment(contentStore)
        .environment(characterStore)
    }
}

#Preview {
    RootView()
}
