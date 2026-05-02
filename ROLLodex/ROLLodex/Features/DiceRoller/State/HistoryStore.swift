import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    private(set) var rolls: [RollResult] = []

    private let storage: UserDefaults
    private let key = "history.rolls.v2"
    private let maxEntries = 200

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        load()
    }

    func record(_ result: RollResult) {
        rolls.insert(result, at: 0)
        if rolls.count > maxEntries {
            rolls = Array(rolls.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        rolls.removeAll()
        save()
    }

    private func load() {
        guard
            let data = storage.data(forKey: key),
            let decoded = try? JSONDecoder().decode([RollResult].self, from: data)
        else { return }
        rolls = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rolls) else { return }
        storage.set(data, forKey: key)
    }
}
