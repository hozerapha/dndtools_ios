import Foundation
import Observation

@MainActor
@Observable
final class PresetStore {
    private(set) var presets: [Preset] = []

    private let storage: UserDefaults
    private let key = "presets.v2"

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        load()
    }

    func add(name: String, formula: DiceFormula) {
        let preset = Preset(name: name, formula: formula)
        presets.append(preset)
        save()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    private func load() {
        guard
            let data = storage.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Preset].self, from: data)
        else { return }
        presets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        storage.set(data, forKey: key)
    }
}
