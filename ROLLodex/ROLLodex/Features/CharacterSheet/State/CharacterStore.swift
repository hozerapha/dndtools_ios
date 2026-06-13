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
            // The value we just encoded IS the file's content — update the
            // in-memory array directly instead of re-reading + re-decoding
            // from disk. save() runs on every sheet binding write (each
            // keystroke of a name edit, every HP tap), so the round-trip
            // was pure overhead.
            if let index = characters.firstIndex(where: { $0.id == character.id }) {
                characters[index] = character
            } else {
                characters.append(character)
            }
        } catch {
            print("Failed to save character: \(error)")
        }
    }

    // MARK: - Import (Phase H)

    enum ImportError: LocalizedError {
        case unreadable
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:           return "Couldn't read the selected file."
            case .malformed(let detail): return "That isn't a valid character file.\n\(detail)"
            }
        }
    }

    /// Decode a user-selected character `.json`, give it a FRESH id, and save.
    /// The new id means importing your own export makes a copy rather than
    /// clobbering the original (characters are keyed by id on disk and in the
    /// sheet's binding). Returns the imported character on success.
    @discardableResult
    func importCharacter(from url: URL) throws -> Character {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try importCharacter(data: raw)
    }

    /// Core import: validate `data` as a `Character`, reassign a fresh id, save.
    /// Shared by the file picker and the dev paste box.
    @discardableResult
    func importCharacter(data raw: Data) throws -> Character {
        // Decode once purely to validate it's a real character (clean error).
        do {
            _ = try decoder.decode(Character.self, from: raw)
        } catch {
            throw ImportError.malformed(error.localizedDescription)
        }

        let reidentified = try reassignID(raw)
        // Safe to force-try the decode: reassignID round-trips the same bytes
        // that just decoded, only swapping the id string.
        let character = try decoder.decode(Character.self, from: reidentified)
        save(character)
        return character
    }

    /// Swap the top-level `id` for a fresh UUID without touching the rest of
    /// the document — keeps us from having to thread a giant memberwise init.
    private func reassignID(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.malformed("Root is not a JSON object.")
        }
        object["id"] = UUID().uuidString
        return try JSONSerialization.data(withJSONObject: object)
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
        let entryCountBeforeCleanup = manifest.entries.count
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

        // If manifest entries were dropped (orphaned ids), rewrite it.
        // (Comparing against `characters.count` here was wrong — that's
        // always 0 during init, so the manifest was rewritten every launch.)
        if manifest.entries.count != entryCountBeforeCleanup {
            writeManifest(manifest)
        }

        characters = loaded
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
