import SwiftUI

enum AppTab: String, Hashable {
    case dice, characters
}

struct RootView: View {
    @State private var history = HistoryStore()
    @State private var presets = PresetStore()
    @State private var contentStore = ContentStore()
    @State private var characterStore = CharacterStore()
    @State private var pendingRollStore = PendingRollStore()
    @State private var selectedTab: AppTab = .dice

    var body: some View {
        TabView(selection: $selectedTab) {
            DiceRollerView()
                .tabItem {
                    Label("Dice", systemImage: "dice")
                }
                .tag(AppTab.dice)

            CharacterListView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Characters", systemImage: "person.2")
                }
                .tag(AppTab.characters)
        }
        .environment(history)
        .environment(presets)
        .environment(contentStore)
        .environment(characterStore)
        .environment(pendingRollStore)
    }
}

#Preview {
    RootView()
}
