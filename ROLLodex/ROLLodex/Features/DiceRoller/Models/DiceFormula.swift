import Foundation

enum GroupModifier: Codable, Hashable {
    case keepHighest(Int)
    case keepLowest(Int)
    case dropHighest(Int)
    case dropLowest(Int)
    case rerollOnceIfAtMost(Int)

    var suffix: String {
        switch self {
        case .keepHighest(let n):       "kh\(n)"
        case .keepLowest(let n):        "kl\(n)"
        case .dropHighest(let n):       "dh\(n)"
        case .dropLowest(let n):        "dl\(n)"
        case .rerollOnceIfAtMost(let n): "r\(n)"
        }
    }
}

struct DiceGroup: Identifiable, Codable {
    var id: UUID
    var kind: DieKind
    var count: Int
    var modifier: GroupModifier?
    /// Optional 5e damage type for this group's dice (slashing, fire, necrotic, …).
    /// Nil for non-damage rolls (ability checks, saves, manual tray rolls). When
    /// multiple groups in a formula carry different types, the result HUD surfaces
    /// a per-type breakdown so e.g. Eldritch Smite reads "8 slashing · 6 radiant"
    /// instead of one anonymous total.
    var damageType: DamageType?
    /// Minimum face value for each die in this group. When set, any rolled value
    /// below this floor is treated as the floor (e.g. Reliable Talent's min 10).
    /// Nil means no floor — standard 1…sides range.
    var minimumValue: Int?

    init(
        id: UUID = UUID(),
        kind: DieKind,
        count: Int,
        modifier: GroupModifier? = nil,
        damageType: DamageType? = nil,
        minimumValue: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.count = count
        self.modifier = modifier
        self.damageType = damageType
        self.minimumValue = minimumValue
    }

    var isPlain: Bool { modifier == nil }

    /// Dice notation with optional `[damageType]` prefix — `1d8`, `[fire]2d6`,
    /// `2d20kh1`, `[slashing]1d8`. Round-trips through `DiceFormulaParser`, so
    /// the formula bar can show typed groups and have the parser read them
    /// back identically.
    var displayString: String {
        let prefix = damageType.map { "[\($0.rawValue)]" } ?? ""
        let base = "\(count)\(kind.label)"
        let modSuffix = modifier?.suffix ?? ""
        let minSuffix = minimumValue.map { "min\($0)" } ?? ""
        return prefix + base + modSuffix + minSuffix
    }

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case id, kind, count, modifier, damageType, minimumValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.kind = try c.decode(DieKind.self, forKey: .kind)
        self.count = try c.decode(Int.self, forKey: .count)
        self.modifier = try c.decodeIfPresent(GroupModifier.self, forKey: .modifier)
        self.damageType = try c.decodeIfPresent(DamageType.self, forKey: .damageType)
        self.minimumValue = try c.decodeIfPresent(Int.self, forKey: .minimumValue)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(count, forKey: .count)
        try c.encodeIfPresent(modifier, forKey: .modifier)
        try c.encodeIfPresent(damageType, forKey: .damageType)
        try c.encodeIfPresent(minimumValue, forKey: .minimumValue)
    }
}

// Equality / Hashable ignore `id` — two groups are "the same" if their dice/modifier/type/min match,
// regardless of UUID. UUIDs are for SwiftUI identity only.
extension DiceGroup: Hashable {
    static func == (lhs: DiceGroup, rhs: DiceGroup) -> Bool {
        lhs.kind == rhs.kind
            && lhs.count == rhs.count
            && lhs.modifier == rhs.modifier
            && lhs.damageType == rhs.damageType
            && lhs.minimumValue == rhs.minimumValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(count)
        hasher.combine(modifier)
        hasher.combine(damageType)
        hasher.combine(minimumValue)
    }
}

struct DiceFormula: Codable, Hashable {
    var groups: [DiceGroup] = []
    /// Untyped flat modifier — the trailing `+ 3` in `1d8 + 3`.
    var modifier: Int = 0
    /// Flat modifiers carrying a damage type, e.g. the `+5 force` half of
    /// `[force]1d12 + [force]5 + [necrotic]1d6`. Keyed by type; values can be
    /// negative if the user typed a `-`. Empty for untyped formulas. Zero
    /// entries are pruned so a "fire: 0" key never lingers after edits.
    var typedModifiers: [DamageType: Int] = [:]
    /// Multiplier applied to the *rolled dice value* (not modifiers) when the
    /// result is computed — used by the "double the rolled value" crit style,
    /// which can't be expressed as a static dice count. Defaults to 1 (no-op).
    var diceResultMultiplier: Int = 1

    init(
        groups: [DiceGroup] = [],
        modifier: Int = 0,
        typedModifiers: [DamageType: Int] = [:],
        diceResultMultiplier: Int = 1
    ) {
        self.groups = groups
        self.modifier = modifier
        self.typedModifiers = typedModifiers
        self.diceResultMultiplier = diceResultMultiplier
    }

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case groups, modifier, typedModifiers, diceResultMultiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.groups = try c.decodeIfPresent([DiceGroup].self, forKey: .groups) ?? []
        self.modifier = try c.decodeIfPresent(Int.self, forKey: .modifier) ?? 0
        // Pre-typed-modifiers formulas (any preset / history entry saved before
        // this field existed) decode with an empty dict instead of crashing.
        self.typedModifiers = try c.decodeIfPresent([DamageType: Int].self, forKey: .typedModifiers) ?? [:]
        self.diceResultMultiplier = try c.decodeIfPresent(Int.self, forKey: .diceResultMultiplier) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groups, forKey: .groups)
        try c.encode(modifier, forKey: .modifier)
        if !typedModifiers.isEmpty {
            try c.encode(typedModifiers, forKey: .typedModifiers)
        }
        if diceResultMultiplier != 1 {
            try c.encode(diceResultMultiplier, forKey: .diceResultMultiplier)
        }
    }

    /// Returns a copy transformed for a critical hit per `rule`. Modifier
    /// multiplier is applied to the original flat modifiers first; the dice mode
    /// then either grows the dice, sets the result multiplier, or converts dice
    /// to a flat "max" amount (kept in the dice's damage-type bucket so the
    /// breakdown still reads right).
    func applyingCrit(_ rule: CritRule) -> DiceFormula {
        var copy = self
        if rule.modifierMultiplier != 1 {
            copy.modifier *= rule.modifierMultiplier
            for (type, value) in copy.typedModifiers {
                copy.typedModifiers[type] = value * rule.modifierMultiplier
            }
        }

        func addMaxFlat() {
            for group in groups {
                let maxValue = group.count * group.kind.rawValue
                if let type = group.damageType {
                    copy.typedModifiers[type, default: 0] += maxValue
                } else {
                    copy.modifier += maxValue
                }
            }
        }

        switch rule.dice {
        case .normal:
            break
        case .doubleCount:
            for i in copy.groups.indices { copy.groups[i].count *= 2 }
        case .doubleRolledValue:
            copy.diceResultMultiplier *= 2
        case .maxPlusRoll:
            addMaxFlat()  // keep the dice, add their max as a flat
        case .maximize:
            // Floor each die to its own max (minimumValue == sides) so every
            // die reads its top value. Reuses the existing floor machinery and
            // keeps the dice in the tray rather than producing an unrollable
            // zero-dice formula.
            for i in copy.groups.indices {
                copy.groups[i].minimumValue = copy.groups[i].kind.rawValue
            }
        }
        return copy
    }

    var totalDiceCount: Int {
        groups.map(\.count).reduce(0, +)
    }

    var isEmpty: Bool {
        groups.isEmpty && modifier == 0 && typedModifiers.isEmpty
    }

    /// Adv/dis only makes sense for exactly one plain d20.
    var supportsAdvantage: Bool {
        groups.count == 1
            && groups[0].kind == .d20
            && groups[0].count == 1
            && groups[0].isPlain
    }

    /// If the formula encodes a 5e advantage / disadvantage roll
    /// (`2d20kh1` / `2d20kl1`) returns the matching mode; otherwise `nil`.
    /// Used by the history sheet to decorate labels with "(adv)" / "(dis)".
    var encodedAdvantageMode: RollMode? {
        for group in groups where group.kind == .d20 && group.count == 2 {
            switch group.modifier {
            case .keepHighest(1): return .advantage
            case .keepLowest(1):  return .disadvantage
            default: continue
            }
        }
        return nil
    }

    /// Total count of dice of the given kind, summed across all groups (any modifier).
    func count(of kind: DieKind) -> Int {
        groups.filter { $0.kind == kind }.map(\.count).reduce(0, +)
    }

    /// Picker increment: bumps the first group of `kind` (any modifier), or creates a plain group.
    mutating func add(_ kind: DieKind) {
        if let i = groups.firstIndex(where: { $0.kind == kind }) {
            groups[i].count += 1
        } else {
            groups.append(DiceGroup(kind: kind, count: 1))
        }
    }

    /// Picker decrement: drops one from the first group of `kind` (any modifier).
    mutating func remove(_ kind: DieKind) {
        guard let i = groups.firstIndex(where: { $0.kind == kind }) else { return }
        if groups[i].count <= 1 {
            groups.remove(at: i)
        } else {
            groups[i].count -= 1
        }
    }

    mutating func clear() {
        groups.removeAll()
        modifier = 0
        typedModifiers.removeAll()
    }

    var displayString: String {
        var parts = groups.map(\.displayString)
        let sortedTypes = typedModifiers.keys.sorted(by: { $0.rawValue < $1.rawValue })
        // Positive typed modifiers join into the "+"-separated leading run so
        // they read naturally next to their dice groups.
        for type in sortedTypes {
            guard let value = typedModifiers[type], value > 0 else { continue }
            parts.append("[\(type.rawValue)]\(value)")
        }
        var result = parts.joined(separator: " + ")
        if result.isEmpty { result = "—" }
        // Negative typed modifiers tack on as " − [type]N" so the parser can
        // tell them apart from a "+"-sign separator (avoids a "+ −" pair).
        for type in sortedTypes {
            guard let value = typedModifiers[type], value < 0 else { continue }
            result += " − [\(type.rawValue)]\(abs(value))"
        }
        if modifier > 0 {
            result += " + \(modifier)"
        } else if modifier < 0 {
            result += " − \(abs(modifier))"
        }
        return result
    }

    /// Stamp `type` onto every group in the formula. Used by the action
    /// interpreter to apply a recipe's damage type (the weapon's or the spell
    /// recipe's) onto the parsed dice groups in one step.
    mutating func applyDamageType(_ type: DamageType) {
        for i in groups.indices {
            groups[i].damageType = type
        }
    }

    /// Apply `type` only to groups that don't already carry one, preserving any
    /// inline `[type]` prefix a recipe/weapon dice string declared. Use this
    /// when stamping a "default" damage type so an explicit per-group type wins.
    mutating func fillDamageType(_ type: DamageType) {
        for i in groups.indices where groups[i].damageType == nil {
            groups[i].damageType = type
        }
    }

    /// Returns a copy with the first plain single-d20 group expanded for
    /// advantage (`2d20kh1`) or disadvantage (`2d20kl1`). Any `minimumValue`
    /// floor on that group (Reliable Talent's "treat ≤9 as 10") is preserved on
    /// the expanded group, so advantage composes with the floor. `.normal`, a
    /// non-d20 lead group, or an already-modified group return self unchanged.
    func applyingAdvantage(_ mode: RollMode) -> DiceFormula {
        guard mode != .normal else { return self }
        var copy = self
        guard let i = copy.groups.firstIndex(where: {
            $0.kind == .d20 && $0.count == 1 && $0.isPlain
        }) else { return copy }
        copy.groups[i].count = 2
        copy.groups[i].modifier = (mode == .advantage) ? .keepHighest(1) : .keepLowest(1)
        return copy
    }

    /// Reader-friendly variant of `displayString` for compact contexts like
    /// the follow-up chip subtitle. When every dice group AND every typed
    /// modifier share a single damage type, the per-piece `[type]` prefixes
    /// are stripped and the type is appended once at the end:
    /// `[piercing]1d8 + [piercing]1d6 + 3` → `1d8 + 1d6 + 3 piercing`.
    /// Mixed-type or untyped formulas fall back to `displayString` since
    /// there's no shared trailer to collapse to.
    var compactDisplayString: String {
        // Collect the distinct damage types in play — typed groups + any
        // typed flat modifiers. Untyped groups (`damageType == nil`) abort the
        // collapse since their dice would silently inherit the trailing type.
        var types: Set<DamageType> = []
        for group in groups {
            guard let dt = group.damageType else { return displayString }
            types.insert(dt)
        }
        for (type, value) in typedModifiers where value != 0 {
            types.insert(type)
        }
        guard types.count == 1, let shared = types.first else { return displayString }

        // Re-render groups + typed modifiers + untyped flat without the
        // per-piece prefixes, then append the shared type once.
        var stripped = self
        for i in stripped.groups.indices {
            stripped.groups[i].damageType = nil
        }
        let collapsedTyped = stripped.typedModifiers.reduce(0) { $0 + $1.value }
        stripped.typedModifiers = [:]
        stripped.modifier += collapsedTyped
        let base = stripped.displayString
        return base == "—" ? base : "\(base) \(shared.rawValue)"
    }
}
