import Foundation

struct CharacterManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: String
        let lastEdited: Date
    }

    var entries: [Entry]
}
