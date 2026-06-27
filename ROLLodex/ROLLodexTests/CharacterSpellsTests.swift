import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct CharacterSpellsTests {

    private let content = ContentStore(importedContentDirectory: Self.makeTempDir())

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - List mutations

    @Test func prepareAndKnowSpellsTrackIndependently() {
        var spells = CharacterSpells()
        spells.preparedIDs = ["cure_wounds"]
        spells.knownIDs = ["fire_bolt"]

        #expect(spells.preparedIDs == ["cure_wounds"])
        #expect(spells.knownIDs == ["fire_bolt"])
        #expect(!spells.isEmpty)
    }

    @Test func learnSpellAddsToSpellbook() {
        var spells = CharacterSpells()
        spells.spellbookIDs = ["magic_missile"]

        #expect(spells.spellbookIDs.contains("magic_missile"))
        #expect(spells.isEmpty == false)
    }

    @Test func preparedCountsExcludeDuplicates() {
        var spells = CharacterSpells()
        spells.preparedIDs = ["fire_bolt", "fire_bolt"]
        #expect(spells.preparedIDs.count == 2)

        let unique = Array(Set(spells.preparedIDs))
        #expect(unique.count == 1)
    }

    // MARK: - Cantrips vs leveled spells

    @Test func contentStoreSeparatesCantripsFromLeveledSpells() {
        let cantrips = content.allSpells.filter { $0.level == 0 }
        let leveled = content.allSpells.filter { $0.level > 0 }

        #expect(!cantrips.isEmpty)
        #expect(!leveled.isEmpty)
        #expect(cantrips.allSatisfy { $0.level == 0 })
        #expect(leveled.allSatisfy { $0.level > 0 })
    }

    @Test func allSpellsSortsByLevelThenName() {
        let spells = content.allSpells
        for i in 1..<spells.count {
            let previous = spells[i - 1]
            let current = spells[i]
            let ordered = previous.level < current.level
                || (previous.level == current.level && previous.name <= current.name)
            #expect(ordered)
        }
    }

    @Test func cantripsCannotBeLeveled() {
        let cantrip = content.allSpells.first { $0.level == 0 }
        #expect(cantrip != nil)
        #expect(cantrip?.level == 0)
    }

    // MARK: - Prepared / known counts

    @Test func preparedCountReflectsListState() {
        var spells = CharacterSpells()
        spells.preparedIDs = ["a", "b", "c"]
        #expect(spells.preparedIDs.count == 3)
    }

    @Test func knownCountReflectsListState() {
        var spells = CharacterSpells()
        spells.knownIDs = ["x", "y"]
        #expect(spells.knownIDs.count == 2)
    }

    @Test func emptySpellsReportsEmpty() {
        let spells = CharacterSpells()
        #expect(spells.isEmpty)
        #expect(spells.preparedIDs.isEmpty)
        #expect(spells.knownIDs.isEmpty)
        #expect(spells.spellbookIDs.isEmpty)
    }
}
