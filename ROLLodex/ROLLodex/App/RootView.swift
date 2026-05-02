import SwiftUI

struct RootView: View {
    @State private var history = HistoryStore()
    @State private var presets = PresetStore()

    var body: some View {
        TabView {
            DiceRollerView()
                .tabItem {
                    Label("Dice", systemImage: "dice")
                }

            Dice3DPlaygroundView()
                .tabItem {
                    Label("3D", systemImage: "cube")
                }

            // Future tabs (initiative, character sheet, etc.) plug in here.
        }
        .environment(history)
        .environment(presets)
    }
}

#Preview {
    RootView()
}
