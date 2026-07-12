import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct PresetStoreTests {

    private func withSuite(_ test: (UserDefaults) throws -> Void) rethrows {
        let name = "rollodex.tests.presets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        try test(defaults)
    }

    private func sampleFormula() -> DiceFormula {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2))
        formula.modifier = 3
        return formula
    }

    // MARK: - CRUD

    @Test func addStoresPreset() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            store.add(name: "Fireball", formula: sampleFormula())

            #expect(store.presets.count == 1)
            #expect(store.presets.first?.name == "Fireball")
        }
    }

    @Test func deleteRemovesMatchingPreset() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            store.add(name: "A", formula: sampleFormula())
            store.add(name: "B", formula: sampleFormula())
            let toDelete = store.presets.first { $0.name == "A" }!

            store.delete(toDelete)

            #expect(store.presets.count == 1)
            #expect(store.presets.first?.name == "B")
        }
    }

    @Test func loadRestoresSavedPresets() {
        withSuite { defaults in
            let store1 = PresetStore(storage: defaults)
            store1.add(name: "Saved", formula: sampleFormula())

            let store2 = PresetStore(storage: defaults)

            #expect(store2.presets.count == 1)
            #expect(store2.presets.first?.name == "Saved")
        }
    }

    @Test func duplicateNamesAreAllowed() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            store.add(name: "Same", formula: sampleFormula())
            store.add(name: "Same", formula: sampleFormula())

            #expect(store.presets.count == 2)
            #expect(store.presets.allSatisfy { $0.name == "Same" })
        }
    }

    // MARK: - Default & migration

    @Test func defaultStateIsEmpty() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            #expect(store.presets.isEmpty)
        }
    }

    @Test func legacyPresetWithoutTypedModifiersDecodes() throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "formula": {
              "groups": [
                { "id": "00000000-0000-0000-0000-000000000002", "kind": 6, "count": 2 }
              ],
              "modifier": 3
            }
          }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([Preset].self, from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].formula.modifier == 3)
        #expect(decoded[0].formula.typedModifiers.isEmpty)
    }

    @Test func presetRoundTripsThroughEncoder() throws {
        try withSuite { defaults in
            let store = PresetStore(storage: defaults)
            var formula = DiceFormula()
            formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .fire))
            formula.typedModifiers[.fire] = 2
            store.add(name: "Flame", formula: formula)

            let data = try JSONEncoder().encode(store.presets)
            let decoded = try JSONDecoder().decode([Preset].self, from: data)

            #expect(decoded.count == 1)
            #expect(decoded[0].name == "Flame")
            #expect(decoded[0].formula.typedModifiers == [.fire: 2])
        }
    }
}
