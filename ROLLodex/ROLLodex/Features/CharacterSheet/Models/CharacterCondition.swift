import Foundation

/// One condition currently applied to a character. References a
/// `ConditionDefinition` by id; `source` is the optional free-form blurb the
/// player typed in ("Wyvern bite", "Failed save vs. Hold Person") so they can
/// remember why it's on them.
struct CharacterCondition: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var source: String?

    init(id: String, source: String? = nil) {
        self.id = id
        self.source = source
    }
}
