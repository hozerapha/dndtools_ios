import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct HistoryStoreTests {

    private func withSuite(_ test: (UserDefaults) -> Void) {
        let name = "rollodex.tests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        test(defaults)
        UserDefaults.standard.removePersistentDomain(forName: name)
    }

    private func sampleResult(label: String = "Sample") -> RollResult {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.modifier = 5
        return RollResult(formula: formula, dieRolls: [DieRoll(kind: .d20, value: 15)], label: label)
    }

    // MARK: - Recording

    @Test func recordInsertsAtFront() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            let first = sampleResult(label: "First")
            let second = sampleResult(label: "Second")

            store.record(first)
            store.record(second)

            #expect(store.rolls.count == 2)
            #expect(store.rolls[0].label == "Second")
            #expect(store.rolls[1].label == "First")
        }
    }

    @Test func clearRemovesAllEntriesAndPersists() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            store.record(sampleResult())
            #expect(!store.rolls.isEmpty)

            store.clear()

            #expect(store.rolls.isEmpty)
            #expect(defaults.data(forKey: "history.rolls.v2") != nil)
        }
    }

    @Test func removeFirstDropsNewestEntry() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            store.record(sampleResult(label: "A"))
            store.record(sampleResult(label: "B"))

            store.removeFirst()

            #expect(store.rolls.count == 1)
            #expect(store.rolls.first?.label == "A")
        }
    }

    @Test func removeFirstIsNoOpWhenEmpty() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            store.removeFirst()
            #expect(store.rolls.isEmpty)
        }
    }

    // MARK: - Cap & persistence

    @Test func twoHundredEntryCapKeepsNewest() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            for i in 0..<205 {
                store.record(sampleResult(label: "\(i)"))
            }

            #expect(store.rolls.count == 200)
            #expect(store.rolls.first?.label == "204")
            #expect(store.rolls.last?.label == "5")
        }
    }

    @Test func userDefaultsRoundTripRestoresRolls() {
        withSuite { defaults in
            let store1 = HistoryStore(storage: defaults)
            let entry = sampleResult(label: "Round-trip")
            store1.record(entry)

            let store2 = HistoryStore(storage: defaults)

            #expect(store2.rolls.count == 1)
            let equal = store2.rolls[0] == entry
            #expect(equal)
        }
    }

    @Test func malformedJSONFallsBackToEmpty() {
        withSuite { defaults in
            defaults.set("not valid json".data(using: .utf8)!, forKey: "history.rolls.v2")

            let store = HistoryStore(storage: defaults)
            #expect(store.rolls.isEmpty)
        }
    }

    @Test func duplicateResultsAreRecordedSeparately() {
        withSuite { defaults in
            let store = HistoryStore(storage: defaults)
            let entry = sampleResult(label: "Dup")
            store.record(entry)
            store.record(entry)

            #expect(store.rolls.count == 2)
            #expect(store.rolls[0].label == "Dup")
            #expect(store.rolls[1].label == "Dup")
        }
    }
}
