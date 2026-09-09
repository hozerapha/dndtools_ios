import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: UserDefaults decode-failure handling for BOTH stores
/// (`HistoryStoreTests` covered malformed history JSON; `PresetStoreTests`
/// had no failure-path coverage at all), and mutation-persistence
/// guarantees — deletes and the 200-entry cap must survive an app restart,
/// not just hold in memory.
///
/// Both stores swallow decode errors and fall back to an empty collection
/// (`try?` in `load()`); these tests pin that fail-safe contract, including
/// the all-or-nothing behavior when a single entry is corrupt.
@MainActor
struct StoreDecodeFailureTests {

    private func withSuite(_ test: (UserDefaults) throws -> Void) rethrows {
        let name = "rollodex.tests.stores.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        try test(defaults)
    }

    private func sampleResult(label: String = "Sample") -> RollResult {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        return RollResult(formula: formula, dieRolls: [DieRoll(kind: .d20, value: 15)], label: label)
    }

    private func sampleFormula() -> DiceFormula {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2))
        return formula
    }

    // MARK: - PresetStore failure paths

    @Test func presetStoreMalformedJSONFallsBackToEmpty() {
        withSuite { defaults in
            defaults.set("not valid json".data(using: .utf8)!, forKey: "presets.v2")
            let store = PresetStore(storage: defaults)
            #expect(store.presets.isEmpty)
        }
    }

    @Test func presetStoreWrongShapeJSONFallsBackToEmpty() {
        withSuite { defaults in
            // Valid JSON, wrong shape — a dictionary where an array belongs.
            defaults.set("{\"presets\": []}".data(using: .utf8)!, forKey: "presets.v2")
            let store = PresetStore(storage: defaults)
            #expect(store.presets.isEmpty)
        }
    }

    @Test func presetStoreOneCorruptEntryDropsWholeLoad() {
        withSuite { defaults in
            // All-or-nothing: a single preset missing its `formula` poisons
            // the array decode; the store must come up empty, not half-loaded
            // or crashed.
            let json = """
            [
              {
                "id": "00000000-0000-0000-0000-000000000001",
                "name": "Good",
                "formula": { "groups": [ { "id": "00000000-0000-0000-0000-000000000002", "kind": 6, "count": 2 } ], "modifier": 0 }
              },
              {
                "id": "00000000-0000-0000-0000-000000000003",
                "name": "Broken"
              }
            ]
            """.data(using: .utf8)!
            defaults.set(json, forKey: "presets.v2")
            let store = PresetStore(storage: defaults)
            #expect(store.presets.isEmpty)
        }
    }

    @Test func presetStoreRecoversAndSavesAfterCorruption() {
        withSuite { defaults in
            defaults.set("garbage".data(using: .utf8)!, forKey: "presets.v2")
            let store = PresetStore(storage: defaults)
            #expect(store.presets.isEmpty)
            // A corrupt on-disk blob must not wedge the store forever —
            // adding a preset overwrites it and reloads cleanly.
            store.add(name: "Recovered", formula: sampleFormula())
            let reloaded = PresetStore(storage: defaults)
            #expect(reloaded.presets.count == 1)
            #expect(reloaded.presets.first?.name == "Recovered")
        }
    }

    // MARK: - PresetStore mutation persistence

    @Test func presetDeletePersistsAcrossReload() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            store.add(name: "A", formula: sampleFormula())
            store.add(name: "B", formula: sampleFormula())
            let toDelete = store.presets.first { $0.name == "A" }!
            store.delete(toDelete)

            let reloaded = PresetStore(storage: defaults)
            #expect(reloaded.presets.count == 1)
            #expect(reloaded.presets.first?.name == "B")
        }
    }

    @Test func presetDeleteOfUnknownPresetIsNoOp() {
        withSuite { defaults in
            let store = PresetStore(storage: defaults)
            store.add(name: "A", formula: sampleFormula())
            // A preset that was never added (fresh UUID) deletes nothing.
            store.delete(Preset(name: "Ghost", formula: sampleFormula()))
            #expect(store.presets.count == 1)
            #expect(store.presets.first?.name == "A")
        }
    }

    // MARK: - HistoryStore failure paths

    @Test func historyStoreOneCorruptEntryDropsWholeLoad() {
        withSuite { defaults in
            // Second entry is missing `dieRolls` (required) — the whole
            // history must fail safe to empty rather than crash on launch.
            let json = """
            [
              {
                "id": "00000000-0000-0000-0000-000000000001",
                "formula": { "groups": [ { "id": "00000000-0000-0000-0000-000000000002", "kind": 20, "count": 1 } ], "modifier": 0 },
                "dieRolls": [ { "id": "00000000-0000-0000-0000-000000000003", "kind": 20, "value": 11, "isKept": true } ],
                "timestamp": 750000000.0
              },
              {
                "id": "00000000-0000-0000-0000-000000000004",
                "formula": { "groups": [], "modifier": 0 },
                "timestamp": 750000001.0
              }
            ]
            """.data(using: .utf8)!
            defaults.set(json, forKey: "history.rolls.v2")
            let store = HistoryStore(storage: defaults)
            #expect(store.rolls.isEmpty)
        }
    }

    // MARK: - HistoryStore mutation persistence

    @Test func historyRemoveFirstPersistsAcrossReload() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            store.record(sampleResult(label: "Old"))
            store.record(sampleResult(label: "New"))
            store.removeFirst()

            let reloaded = HistoryStore(storage: defaults)
            #expect(reloaded.rolls.count == 1)
            #expect(reloaded.rolls.first?.label == "Old")
        }
    }

    @Test func historyCapPersistsAcrossReload() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            for i in 0..<205 {
                store.record(sampleResult(label: "\(i)"))
            }
            // The on-disk blob itself must be capped — a restart loads the
            // same newest-200 window, not the pre-cap tail.
            let reloaded = HistoryStore(storage: defaults)
            #expect(reloaded.rolls.count == 200)
            #expect(reloaded.rolls.first?.label == "204")
            #expect(reloaded.rolls.last?.label == "5")
        }
    }
}
