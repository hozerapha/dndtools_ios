import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct ContentStoreEdgeCaseTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ contents: String, to dir: URL, as name: String) throws {
        try contents.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
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
        let nameLine = packName.map { "\"name\": \"\($0)\"" } ?? ""
        let prefix = nameLine.isEmpty ? "" : "\(nameLine), "
        return "{ \(prefix)\"spells\": [ \(spellEntry(id: id, name: name)) ] }"
    }

    // MARK: - Loading

    @Test func bundledContentLoadsIntoAllCategories() {
        let store = ContentStore(importedContentDirectory: makeTempDir())
        #expect(!store.classes.isEmpty)
        #expect(!store.species.isEmpty)
        #expect(!store.backgrounds.isEmpty)
        #expect(!store.weapons.isEmpty)
        #expect(!store.armor.isEmpty)
        #expect(!store.gear.isEmpty)
        #expect(!store.spells.isEmpty)
        #expect(!store.conditions.isEmpty)
        // Bundled content loaded cleanly — no degraded-load errors (audit #3).
        #expect(store.loadErrors.isEmpty)
    }

    // MARK: - Imported pack handling

    @Test func malformedImportedPackIsIgnored() {
        let dir = makeTempDir()
        try! write("this is not json", to: dir, as: "bad.json")

        let store = ContentStore(importedContentDirectory: dir)

        #expect(store.importedPacks.isEmpty)
        #expect(store.classDefinition(id: "fighter") != nil)
    }

    @Test func filenameSanitizationCleansDisplayName() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)
        let data = spellPackJSON(id: "sanity", name: "Sanity Bolt", packName: "My Pack!!!").data(using: .utf8)!

        _ = try store.importPack(data: data, suggestedName: nil)

        #expect(store.importedPacks.count == 1)
        // Filename = sanitized slug + a stable name hash (audit #4).
        #expect(store.importedPacks.first?.fileName.hasPrefix("my-pack-") == true)
        #expect(store.importedPacks.first?.fileName.hasSuffix(".json") == true)
        #expect(store.spellDefinition(id: "sanity")?.name == "Sanity Bolt")
    }

    @Test func distinctNamesThatSanitizeAlikeDoNotCollide() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)
        // "Pack 1" and "Pack!1" both sanitize to "pack-1" — must stay distinct.
        _ = try store.importPack(
            data: spellPackJSON(id: "a", name: "A", packName: "Pack 1").data(using: .utf8)!,
            suggestedName: nil)
        _ = try store.importPack(
            data: spellPackJSON(id: "b", name: "B", packName: "Pack!1").data(using: .utf8)!,
            suggestedName: nil)
        #expect(store.importedPacks.count == 2)
        #expect(store.spellDefinition(id: "a") != nil)
        #expect(store.spellDefinition(id: "b") != nil)

        // Re-importing the SAME name overwrites its own file (no third pack).
        _ = try store.importPack(
            data: spellPackJSON(id: "a2", name: "A2", packName: "Pack 1").data(using: .utf8)!,
            suggestedName: nil)
        #expect(store.importedPacks.count == 2)
        #expect(store.spellDefinition(id: "a2") != nil)
        #expect(store.spellDefinition(id: "a") == nil)   // overwritten
    }

    @Test func importedEntriesShadowBundledByID() throws {
        let dir = makeTempDir()
        try write(spellPackJSON(id: "fire_bolt", name: "Custom Bolt"), to: dir, as: "pack.json")
        let store = ContentStore(importedContentDirectory: dir)

        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Custom Bolt")
    }

    @Test func shadowOrderingFavorsLastFilename() throws {
        let dir = makeTempDir()
        try write(spellPackJSON(id: "shadow", name: "A"), to: dir, as: "a.json")
        try write(spellPackJSON(id: "shadow", name: "B"), to: dir, as: "b.json")
        let store = ContentStore(importedContentDirectory: dir)

        #expect(store.spellDefinition(id: "shadow")?.name == "B")
    }

    @Test func removingImportedPackRestoresBundledContent() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)
        let data = spellPackJSON(id: "fire_bolt", name: "Custom Bolt").data(using: .utf8)!
        _ = try store.importPack(data: data, suggestedName: "custom")

        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Custom Bolt")

        // Filenames now carry a stable name-hash suffix (audit #4 —
        // "custom-2cf74e.json"), so removing by hard-coded "custom.json"
        // doesn't touch anything. Take the actual filename from importedPacks.
        let importedFileName = store.importedPacks.first!.fileName
        store.removeImportedPack(fileName: importedFileName)

        #expect(store.spellDefinition(id: "fire_bolt")?.name == "Fire Bolt")
        #expect(store.importedPacks.isEmpty)
    }

    @Test func reloadIsIdempotent() throws {
        let dir = makeTempDir()
        let store = ContentStore(importedContentDirectory: dir)
        let data = spellPackJSON(id: "stable", name: "Stable Spell").data(using: .utf8)!
        _ = try store.importPack(data: data, suggestedName: "stable")

        let beforeClasses = store.classes
        let beforeSpells = store.spells

        store.reload()

        #expect(store.classes == beforeClasses)
        #expect(store.spells == beforeSpells)
    }
}
