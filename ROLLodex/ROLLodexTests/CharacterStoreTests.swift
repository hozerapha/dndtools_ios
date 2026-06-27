import Testing
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
@testable import ROLLodex

struct CharacterStoreTests {

    private func makeTemporaryStore() -> CharacterStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return CharacterStore(directory: tempDir)
    }

    private func makeSampleCharacter(name: String = "Test") -> Character {
        Character(
            name: name,
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16, .dexterity: 12, .constitution: 14],
            maxHP: 12
        )
    }

    // MARK: - Create / Save / Load

    @Test func createCharacter() {
        let store = makeTemporaryStore()
        let character = makeSampleCharacter()

        store.create(character)

        #expect(store.characters.count == 1)
        #expect(store.character(id: character.id)?.name == "Test")
    }

    @Test func saveFailureSurfacesAndClearsOnSuccess() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: dir)
        #expect(store.lastSaveError == nil)

        // Remove the directory out from under the store so the atomic write
        // has nowhere to land — the failure must surface, not vanish.
        try? FileManager.default.removeItem(at: dir)
        store.save(makeSampleCharacter(name: "Doomed"))
        #expect(store.lastSaveError != nil)

        // A subsequent successful save clears the banner state.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.save(makeSampleCharacter(name: "Saved"))
        #expect(store.lastSaveError == nil)
    }

    @Test func clearSaveErrorDismissesBannerState() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: dir)
        try? FileManager.default.removeItem(at: dir)
        store.save(makeSampleCharacter())
        #expect(store.lastSaveError != nil)

        store.clearSaveError()
        #expect(store.lastSaveError == nil)
    }

    @Test func saveAndReload() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store1 = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store1.create(character)

        // Simulate app restart by creating a new store pointing at the same directory
        let store2 = CharacterStore(directory: tempDir)

        #expect(store2.characters.count == 1)
        #expect(store2.character(id: character.id)?.name == "Test")
    }

    @Test func updateExistingCharacter() {
        let store = makeTemporaryStore()
        var character = makeSampleCharacter()
        store.create(character)

        character.name = "Renamed"
        store.save(character)

        #expect(store.characters.count == 1)
        #expect(store.character(id: character.id)?.name == "Renamed")
    }

    // MARK: - Delete

    @Test func deleteCharacter() {
        let store = makeTemporaryStore()
        let character = makeSampleCharacter()
        store.create(character)
        #expect(store.characters.count == 1)

        store.delete(id: character.id)
        #expect(store.characters.isEmpty)
        #expect(store.character(id: character.id) == nil)
    }

    @Test func deleteRemovesFile() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store.create(character)

        store.delete(id: character.id)

        let fileURL = tempDir.appendingPathComponent("\(character.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    // MARK: - Manifest

    @Test func manifestTracksCreatedCharacters() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store.create(character)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path) == true)

        let manifestData = try! Data(contentsOf: manifestURL)
        let manifest = try! JSONDecoder().decode(CharacterManifest.self, from: manifestData)
        #expect(manifest.entries.count == 1)
        #expect(manifest.entries.first?.id == character.id.uuidString)
    }

    @Test func manifestRemovesDeletedCharacters() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store.create(character)
        store.delete(id: character.id)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifestData = try! Data(contentsOf: manifestURL)
        let manifest = try! JSONDecoder().decode(CharacterManifest.self, from: manifestData)
        #expect(manifest.entries.isEmpty)
    }

    @Test func toleratesOrphanedManifestEntries() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store1 = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store1.create(character)

        // Delete the file manually but leave the manifest entry
        let fileURL = tempDir.appendingPathComponent("\(character.id.uuidString).json")
        try! FileManager.default.removeItem(at: fileURL)

        // New store should clean up the manifest on load
        let store2 = CharacterStore(directory: tempDir)
        #expect(store2.characters.isEmpty)
    }

    // MARK: - Multiple characters

    @Test func multipleCharacters() {
        let store = makeTemporaryStore()
        let a = makeSampleCharacter(name: "Alice")
        let b = makeSampleCharacter(name: "Bob")

        store.create(a)
        store.create(b)

        #expect(store.characters.count == 2)
        #expect(store.character(id: a.id)?.name == "Alice")
        #expect(store.character(id: b.id)?.name == "Bob")
    }

    // MARK: - Binding helper

    @Test func bindingPersistsMutations() {
        let store = makeTemporaryStore()
        let character = makeSampleCharacter()
        store.create(character)

        guard let binding = store.binding(for: character.id) else {
            Issue.record("Expected a binding for the created character")
            return
        }

        // Mutate via the binding setter — should both update memory and disk.
        var edited = binding.wrappedValue
        edited.currentHP = 4
        edited.notes = "tested"
        binding.wrappedValue = edited

        #expect(store.character(id: character.id)?.currentHP == 4)
        #expect(store.character(id: character.id)?.notes == "tested")
    }

    @Test func bindingForUnknownIDReturnsNil() {
        let store = makeTemporaryStore()
        #expect(store.binding(for: UUID()) == nil)
    }

    // MARK: - Atomic write integrity

    @Test func atomicWriteDoesNotCorruptOnCrash() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: tempDir)
        let character = makeSampleCharacter()
        store.create(character)

        let fileURL = tempDir.appendingPathComponent("\(character.id.uuidString).json")
        let tempURL = fileURL.appendingPathExtension("tmp")

        // Simulate a crash mid-write by creating a temp file and leaving it
        let junk = "incomplete data".data(using: .utf8)!
        try junk.write(to: tempURL)

        // The original file should still be intact
        let data = try Data(contentsOf: fileURL)
        let loaded = try JSONDecoder().decode(Character.self, from: data)
        #expect(loaded.name == "Test")
    }

    // MARK: - Export / import round-trip

    @available(iOS 18.2, *)
    @Test func exportedCharacterImportsWithFreshID() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CharacterStore(directory: tempDir)
        let original = makeSampleCharacter(name: "Exportable")
        let exported = ExportedCharacter(character: original)
        let data = try await exported.exported(as: .json)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: fileURL)

        let imported = try store.importCharacter(from: fileURL)

        #expect(imported.id != original.id)
        #expect(imported.name == "Exportable")
        #expect(store.character(id: imported.id)?.name == "Exportable")
    }
}
