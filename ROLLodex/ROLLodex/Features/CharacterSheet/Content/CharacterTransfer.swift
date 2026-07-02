import CoreTransferable
import UniformTypeIdentifiers

/// `ShareLink`-friendly wrapper that exports a character as a `.json` file.
/// Lives apart from `Character.swift` so the model stays free of UI /
/// transfer imports (per the project's pure-model convention). The share
/// sheet offers it as `<name>.json`, which `CharacterStore.importCharacter`
/// reads straight back.
struct ExportedCharacter: Transferable {
    let character: Character

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { exported in
            // Character (like the whole model layer) is MainActor-isolated by
            // the target's default isolation, but this export closure runs
            // nonisolated — hop to the main actor to encode.
            try await MainActor.run {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(exported.character)
            }
        }
        .suggestedFileName { exported in
            let safe = exported.character.name
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(safe.isEmpty ? "character" : safe).json"
        }
    }
}
