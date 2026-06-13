import Testing
import Foundation
@testable import ROLLodex

/// Phase H — homebrew content packs and character import. Covers the
/// validator, the bundled+imported merge (imported shadows bundled by id),
/// pack import/remove round-trips, and character import with fresh-id safety.
@MainActor
struct ContentImportTests {

    // MARK: - Validator

    @Test func emptyPackIsInvalid() {
        #expect(!ContentValidator.validate(ContentPack()).isEmpty)
    }

    @Test func validSpellPackPasses() throws {
        let pack = try decodePack(spellPackJSON(id: "test_bolt", name: "Test Bolt"))
        #expect(ContentValidator.validate(pack).isEmpty)
    }

    @Test func duplicateIDsAreFlagged() throws {
        let json = """
        { "spells": [
          \(spellEntry(id: "dup", name: "One")),
          \(spellEntry(id: "dup", name: "Two"))
        ] }
        """
        let pack = try decodePack(json)
        let issues = ContentValidator.validate(pack)
        #expect(issues.contains { $0.contains("Duplicate") && $0.contains("dup") })
    }

    @Test func unparseableDiceIsFlagged() throws {
        // A heal recipe with a junk dice string.
        let json = """
        { "spells": [ {
          "id": "bad_heal", "name": "Bad Heal", "level": 1, "school": "abjuration",
          "castingTime": {"type":"action"}, "range": {"type":"touch"},
          "components": {"verbal": true}, "duration": {"type":"instantaneous"},
          "description": "x",
          "actionRecipes": [ {"type":"heal","dice":"notdice","label":"Oops"} ]
        } ] }
        """
        let pack = try decodePack(json)
        let issues = ContentValidator.validate(pack)
        #expect(issues.contains { $0.contains("Unparseable dice") })
    }

    // MARK: - Merge / shadowing

    @Test func importedSpellAppearsAlongsideBundled() throws {
        let dir = makeTempDir()
        try write(spellPackJSON(id: "test_bolt", name: "Test Bolt"), to: dir, as: "pack.json")
        let store = ContentStore(importedContentDirectory: dir)

        #expect(store.spellDefinition(id: "test_bolt")?.name == "Test Bolt")
        // Bundled content is still present.
        #expect(store.spellDefinition(id: "fire_bolt") != nil)
    }

    @Test func importedEntryShadowsBundledByID() throws {
        let dir = makeTempDir()
        // A pack redefining the bundled "fire_bolt" with a new name.
        try write(spellPackJSON(id: "fire_bolt", name: "Custom Bolt"), to: dir, as: "pack.json")
        let store = ContentStore(importedContentDirectory: dir)

        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Custom Bolt")
    }

    @Test func removingPackRestoresBundledContent() throws {
        let dir = makeTempDir()
        try write(spellPackJSON(id: "fire_bolt", name: "Custom Bolt"), to: dir, as: "pack.json")
        let store = ContentStore(importedContentDirectory: dir)
        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Custom Bolt")

        store.removeImportedPack(fileName: "pack.json")
        // Bundled Fire Bolt re-surfaces; the homebrew-only id is gone.
        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Fire Bolt")
    }

    // MARK: - importPack(from:)

    @Test func importPackPersistsAndLists() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)
        #expect(store.importedPacks.isEmpty)

        let src = makeTempDir().appendingPathComponent("incoming.json")
        try write(spellPackJSON(id: "test_bolt", name: "Test Bolt", packName: "My Pack"), to: src)

        let imported = try store.importPack(from: src)
        #expect(imported.summary == "1 spell")
        #expect(store.spellDefinition(id: "test_bolt") != nil)
        #expect(store.importedPacks.count == 1)
        #expect(store.importedPacks.first?.name == "My Pack")
    }

    @Test func importPackRejectsInvalidContent() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)

        let src = makeTempDir().appendingPathComponent("bad.json")
        try write("{ \"spells\": [] }", to: src) // empty → invalid

        #expect(throws: ContentStore.ImportError.self) {
            try store.importPack(from: src)
        }
        #expect(store.importedPacks.isEmpty)
    }

    @Test func importPackRejectsMalformedJSON() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)

        let src = makeTempDir().appendingPathComponent("junk.json")
        try write("not json at all", to: src)

        #expect(throws: ContentStore.ImportError.self) {
            try store.importPack(from: src)
        }
    }

    // MARK: - ContentPack round-trip

    @Test func packRoundTripsAndSummarizes() throws {
        let pack = try decodePack(spellPackJSON(id: "a", name: "A", packName: "Pack"))
        let data = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(ContentPack.self, from: data)
        #expect(decoded == pack)
        #expect(decoded.entryCount == 1)
        #expect(decoded.summary == "1 spell")
    }

    // MARK: - Character import

    @Test func characterImportAssignsFreshIDAndSaves() throws {
        let store = CharacterStore(directory: makeTempDir())
        let original = Character(
            name: "Imported Hero", level: 3,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 28
        )
        let src = makeTempDir().appendingPathComponent("hero.json")
        try JSONEncoder().encode(original).write(to: src)

        let imported = try store.importCharacter(from: src)
        #expect(imported.id != original.id)        // fresh id, never clobbers
        #expect(imported.name == "Imported Hero")
        #expect(store.characters.contains { $0.id == imported.id })
    }

    @Test func characterImportRejectsJunk() throws {
        let store = CharacterStore(directory: makeTempDir())
        let src = makeTempDir().appendingPathComponent("junk.json")
        try write("{ \"not\": \"a character\" }", to: src)

        #expect(throws: CharacterStore.ImportError.self) {
            try store.importCharacter(from: src)
        }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ contents: String, to dir: URL, as name: String) throws {
        try contents.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.data(using: .utf8)!.write(to: url)
    }

    private func decodePack(_ json: String) throws -> ContentPack {
        try JSONDecoder().decode(ContentPack.self, from: json.data(using: .utf8)!)
    }

    private func spellEntry(id: String, name: String) -> String {
        """
        {
          "id": "\(id)", "name": "\(name)", "level": 0, "school": "evocation",
          "castingTime": {"type":"action"}, "range": {"type":"feet","value":30},
          "components": {"verbal":true}, "duration": {"type":"instantaneous"},
          "description": "A test spell.", "actionRecipes": []
        }
        """
    }

    private func spellPackJSON(id: String, name: String, packName: String? = nil) -> String {
        let nameLine = packName.map { "\"name\": \"\($0)\"," } ?? ""
        return "{ \(nameLine) \"spells\": [ \(spellEntry(id: id, name: name)) ] }"
    }
}
