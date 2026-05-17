import Foundation

/// One entry in `Character.activeEffects` — a TriggeredEffect that's
/// currently in play on the character along with where it came from. The
/// resolver looks the source up in the content store to find the actual
/// `TriggeredEffect` payload so we don't store schema in the character file.
struct ActiveEffect: Codable, Hashable, Identifiable {
    /// Matches the originating `TriggeredEffect.id`. Used as the dedupe key
    /// when the same effect would otherwise be added twice (re-casting Hex
    /// without dropping concentration).
    let effectID: String
    let source: EffectSource
    /// For `.persistent(.rounds(n))` effects (Rage, Bless): rounds left
    /// before the effect auto-drops. Decremented by `Character.startNewTurn()`
    /// and removed when ≤ 0. Nil for effects whose lifecycle isn't round-based
    /// (Hex/Hunter's Mark on concentration, manual buffs).
    var roundsRemaining: Int?
    /// Open-ended metadata bag for future per-effect counters that don't
    /// warrant a typed field (e.g., item-granted charges). Empty by default.
    var metadata: [String: Int]

    var id: String { effectID }

    init(
        effectID: String,
        source: EffectSource,
        roundsRemaining: Int? = nil,
        metadata: [String: Int] = [:]
    ) {
        self.effectID = effectID
        self.source = source
        self.roundsRemaining = roundsRemaining
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case effectID, source, roundsRemaining, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.effectID = try c.decode(String.self, forKey: .effectID)
        self.source = try c.decode(EffectSource.self, forKey: .source)
        // Slice C field — pre-Slice-C ActiveEffects (Hex, Hunter's Mark)
        // encoded without it, decode as nil.
        self.roundsRemaining = try c.decodeIfPresent(Int.self, forKey: .roundsRemaining)
        self.metadata = try c.decodeIfPresent([String: Int].self, forKey: .metadata) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(effectID, forKey: .effectID)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(roundsRemaining, forKey: .roundsRemaining)
        if !metadata.isEmpty {
            try c.encode(metadata, forKey: .metadata)
        }
    }
}

/// What surface granted the active effect — spell (lives on the caster until
/// concentration breaks), feature toggle (Slice C), or magic item (later).
/// The resolver dispatches on this to find the TriggeredEffect payload.
enum EffectSource: Hashable {
    case spell(spellID: String)
    case feature(featureID: String)
    case item(itemID: String)
}

extension EffectSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, spellID, featureID, itemID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "spell":
            self = .spell(spellID: try c.decode(String.self, forKey: .spellID))
        case "feature":
            self = .feature(featureID: try c.decode(String.self, forKey: .featureID))
        case "item":
            self = .item(itemID: try c.decode(String.self, forKey: .itemID))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown EffectSource: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spell(let id):
            try c.encode("spell", forKey: .type)
            try c.encode(id, forKey: .spellID)
        case .feature(let id):
            try c.encode("feature", forKey: .type)
            try c.encode(id, forKey: .featureID)
        case .item(let id):
            try c.encode("item", forKey: .type)
            try c.encode(id, forKey: .itemID)
        }
    }
}
