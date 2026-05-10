import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class CharacterStore {
    private(set) var characters: [Character] = []

    private let directory: URL
    private let manifestURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("Characters")
        self.init(directory: directory)
    }

    init(directory: URL) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        self.encoder.outputFormatting = .sortedKeys

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - CRUD

    func create(_ character: Character) {
        save(character)
    }

    func save(_ character: Character) {
        let url = fileURL(for: character.id)
        do {
            let data = try encoder.encode(character)
            // `.atomic` writes through a sibling temp file and renames over
            // the destination, which works whether or not the file exists —
            // unlike our previous moveItem dance that 17/EEXISTed when an
            // earlier save left a `.tmp` orphan around.
            try data.write(to: url, options: .atomic)
            updateManifest(id: character.id, lastEdited: Date())
            reloadCharacter(id: character.id)
        } catch {
            print("Failed to save character: \(error)")
        }
    }

    func delete(id: UUID) {
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        removeFromManifest(id: id)
        characters.removeAll { $0.id == id }
    }

    func character(id: UUID) -> Character? {
        characters.first { $0.id == id }
    }

    /// SwiftUI `Binding` over a stored character. Reads return the live value;
    /// writes persist via `save`, which round-trips through the file system
    /// and refreshes `characters` in-place. Used by the character sheet so
    /// every inline edit (name tap, HP stepper, equip toggle, …) is durable.
    func binding(for id: UUID) -> Binding<Character>? {
        guard let initial = character(id: id) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.character(id: id) ?? initial
            },
            set: { [weak self] newValue in
                self?.save(newValue)
            }
        )
    }

    // MARK: - Loading

    private func load() {
        var manifest = readManifest()
        var loaded: [Character] = []

        // Load each character referenced in the manifest.
        // Remove manifest entries for missing files.
        manifest.entries = manifest.entries.filter { entry in
            let url = fileURL(for: UUID(uuidString: entry.id) ?? UUID())
            guard let data = try? Data(contentsOf: url),
                  let character = try? decoder.decode(Character.self, from: data) else {
                return false
            }
            loaded.append(character)
            return true
        }

        // If manifest was cleaned up, rewrite it.
        if loaded.count != characters.count {
            try? encoder.encode(manifest).write(to: manifestURL)
        }

        characters = loaded
    }

    private func reloadCharacter(id: UUID) {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let character = try? decoder.decode(Character.self, from: data) else {
            return
        }

        if let index = characters.firstIndex(where: { $0.id == id }) {
            characters[index] = character
        } else {
            characters.append(character)
        }
    }

    // MARK: - Manifest

    private func readManifest() -> CharacterManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(CharacterManifest.self, from: data) else {
            return CharacterManifest(entries: [])
        }
        return manifest
    }

    private func writeManifest(_ manifest: CharacterManifest) {
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            print("Failed to write manifest: \(error)")
        }
    }

    private func updateManifest(id: UUID, lastEdited: Date) {
        var manifest = readManifest()
        let entryID = id.uuidString

        if let index = manifest.entries.firstIndex(where: { $0.id == entryID }) {
            manifest.entries[index] = CharacterManifest.Entry(id: entryID, lastEdited: lastEdited)
        } else {
            manifest.entries.append(CharacterManifest.Entry(id: entryID, lastEdited: lastEdited))
        }

        writeManifest(manifest)
    }

    private func removeFromManifest(id: UUID) {
        var manifest = readManifest()
        manifest.entries.removeAll { $0.id == id.uuidString }
        writeManifest(manifest)
    }

    // MARK: - Helpers

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
