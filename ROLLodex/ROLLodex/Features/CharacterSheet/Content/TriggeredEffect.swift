import Foundation

/// A single magical/feature/item rider that hooks into the action pipeline:
/// "when X happens, modify the roll." Slice A covered persistent automatic
/// riders (Hex, Hunter's Mark); Slice B adds opt-in chips (Sneak Attack,
/// future Divine Smite) and post-hit triggers with weapon filters.
struct TriggeredEffect: Codable, Equatable {
    /// Stable id used by `ActiveEffect.effectID` for state tracking. Must be
    /// unique across the spell/feature/item that defines the effect.
    let id: String
    /// Player-facing label for the badge / chip ("Hex", "Sneak Attack").
    let name: String
    let trigger: TriggerCondition
    let effect: TriggerEffect
    let lifecycle: TriggerLifecycle
    /// How the player engages — `.automatic` folds silently, `.optIn` surfaces
    /// a chip after the trigger fires. Defaults to `.automatic` so pre-Slice-B
    /// JSON (Hex, Hunter's Mark) decodes unchanged.
    let activation: TriggerActivation
    /// What the player spends to use this effect (Sneak Attack's once-per-turn
    /// flag, Divine Smite's spell slot). Nil for free riders like Hex.
    let cost: TriggerCost?

    init(
        id: String,
        name: String,
        trigger: TriggerCondition,
        effect: TriggerEffect,
        lifecycle: TriggerLifecycle,
        activation: TriggerActivation = .automatic,
        cost: TriggerCost? = nil
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.effect = effect
        self.lifecycle = lifecycle
        self.activation = activation
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, trigger, effect, lifecycle, activation, cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.trigger = try c.decode(TriggerCondition.self, forKey: .trigger)
        self.effect = try c.decode(TriggerEffect.self, forKey: .effect)
        self.lifecycle = try c.decode(TriggerLifecycle.self, forKey: .lifecycle)
        self.activation = try c.decodeIfPresent(TriggerActivation.self, forKey: .activation) ?? .automatic
        self.cost = try c.decodeIfPresent(TriggerCost.self, forKey: .cost)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(effect, forKey: .effect)
        try c.encode(lifecycle, forKey: .lifecycle)
        // Omit `activation` when it's the default to keep Slice A content
        // round-tripping byte-for-byte (and JSON authoring uncluttered).
        if activation != .automatic {
            try c.encode(activation, forKey: .activation)
        }
        try c.encodeIfPresent(cost, forKey: .cost)
    }
}

// MARK: - TriggerCondition

/// *When* the effect fires. Slice A covers automatic damage riders;
/// Slice B adds the post-hit trigger Sneak Attack and Divine Smite need;
/// Slice C extends `onDamageRoll` with an optional filter so Rage can scope
/// its flat damage bonus to STR melee weapon attacks.
enum TriggerCondition: Equatable {
    /// Fires on weapon-damage rolls. Optional filter narrows which weapons
    /// qualify — nil (Hex / Hunter's Mark) matches every weapon damage roll;
    /// `.weaponLacksProperty([.ammunition])` (Rage) restricts to melee.
    case onDamageRoll(filter: AttackFilter?)
    /// Fires after a confirmed weapon hit, before the damage roll. The filter
    /// optionally restricts which weapons / circumstances qualify (Sneak
    /// Attack needs finesse or ranged; Smite needs melee).
    case onAttackHit(filter: AttackFilter?)
    /// Applies continuously while the effect is active (a toggled buff that
    /// other calculators query, e.g. Innate Sorcery's spell save DC / attack
    /// advantage). The damage resolver ignores it; consumers read it from
    /// `activeEffects` directly.
    case whileActive
}

extension TriggerCondition: Codable {
    private enum CodingKeys: String, CodingKey { case type, filter }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "onDamageRoll":
            // Filter is optional so pre-Slice-C Hex / Hunter's Mark JSON
            // (which has no filter key) still decodes.
            let filter = try c.decodeIfPresent(AttackFilter.self, forKey: .filter)
            self = .onDamageRoll(filter: filter)
        case "onAttackHit":
            let filter = try c.decodeIfPresent(AttackFilter.self, forKey: .filter)
            self = .onAttackHit(filter: filter)
        case "whileActive":
            self = .whileActive
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown TriggerCondition: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .onDamageRoll(let filter):
            try c.encode("onDamageRoll", forKey: .type)
            try c.encodeIfPresent(filter, forKey: .filter)
        case .onAttackHit(let filter):
            try c.encode("onAttackHit", forKey: .type)
            try c.encodeIfPresent(filter, forKey: .filter)
        case .whileActive:
            try c.encode("whileActive", forKey: .type)
        }
    }
}

// MARK: - AttackFilter

/// Composable predicate for matching attacks. Slice B ships the minimum needed
/// for Sneak Attack (finesse OR ranged) — the other shapes from the plan
/// (damage type, ally-within-5ft, hadAdvantage) land when content needs them.
indirect enum AttackFilter: Equatable {
    /// Weapon must have at least one of the listed properties (Sneak Attack:
    /// `[.finesse, .ammunition]` — any of which qualifies).
    case weaponHasProperty([WeaponProperty])
    /// Weapon must have NONE of the listed properties. The complement of
    /// `weaponHasProperty` — used for "melee" (`.weaponLacksProperty([.ammunition])`)
    /// since we don't carry an explicit `.melee` flag.
    case weaponLacksProperty([WeaponProperty])
    /// Logical OR over child filters.
    case anyOf([AttackFilter])
    /// Logical AND over child filters.
    case allOf([AttackFilter])
}

extension AttackFilter: Codable {
    private enum CodingKeys: String, CodingKey { case type, properties, filters }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "weaponHasProperty":
            let props = try c.decode([WeaponProperty].self, forKey: .properties)
            self = .weaponHasProperty(props)
        case "weaponLacksProperty":
            let props = try c.decode([WeaponProperty].self, forKey: .properties)
            self = .weaponLacksProperty(props)
        case "anyOf":
            let filters = try c.decode([AttackFilter].self, forKey: .filters)
            self = .anyOf(filters)
        case "allOf":
            let filters = try c.decode([AttackFilter].self, forKey: .filters)
            self = .allOf(filters)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown AttackFilter: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .weaponHasProperty(let props):
            try c.encode("weaponHasProperty", forKey: .type)
            try c.encode(props, forKey: .properties)
        case .weaponLacksProperty(let props):
            try c.encode("weaponLacksProperty", forKey: .type)
            try c.encode(props, forKey: .properties)
        case .anyOf(let filters):
            try c.encode("anyOf", forKey: .type)
            try c.encode(filters, forKey: .filters)
        case .allOf(let filters):
            try c.encode("allOf", forKey: .type)
            try c.encode(filters, forKey: .filters)
        }
    }

    /// True when `weapon` satisfies this predicate. A nil weapon never
    /// matches a property check — opt-in chips silently don't fire on
    /// unarmed strikes (Sneak Attack: no weapon, no chip). `weaponLacksProperty`
    /// also requires a weapon — Rage's flat bonus shouldn't accidentally fire
    /// on unarmed strikes either; the resolver gates that explicitly.
    func matches(weapon: WeaponDefinition?) -> Bool {
        switch self {
        case .weaponHasProperty(let needed):
            guard let weapon else { return false }
            return needed.contains { weapon.properties.contains($0) }
        case .weaponLacksProperty(let forbidden):
            guard let weapon else { return false }
            return forbidden.allSatisfy { !weapon.properties.contains($0) }
        case .anyOf(let children):
            return children.contains { $0.matches(weapon: weapon) }
        case .allOf(let children):
            return children.allSatisfy { $0.matches(weapon: weapon) }
        }
    }
}

// MARK: - TriggerActivation

/// How the player engages with a TriggeredEffect.
enum TriggerActivation: String, Codable, Equatable {
    /// Folds silently into the matching roll (Hex's necrotic die).
    case automatic
    /// Surfaces a chip after the trigger fires; firing the chip applies the
    /// effect and pays the cost. Sneak Attack, Divine Smite.
    case optIn
    /// Player flips on (paying the cost) and the effect persists until its
    /// lifecycle ends — Barbarian Rage, Bless concentration, etc. While
    /// active, the effect behaves exactly like an `.automatic` rider.
    case toggle
}

// MARK: - TriggerCost

/// What it costs to invoke an opt-in (or auto) effect. Free riders like Hex
/// declare no cost.
enum TriggerCost: Equatable {
    /// One use per turn, tracked via `Character.turnFlags`. The flag is set
    /// when the player fires the chip and cleared by Start New Turn.
    case oncePerTurn(flagID: String)
    /// Consume one spell slot of level `minLevel...maxLevel` (Divine Smite:
    /// 1–5). v1 policy: the LOWEST currently-available slot in range is
    /// consumed; effects that scale by slot level use that same level. The
    /// resolver concretizes the range to the chosen level before parking the
    /// cost on a chip, so the slot paid always matches the dice shown.
    case spellSlot(minLevel: Int, maxLevel: Int)
}

extension TriggerCost: Codable {
    private enum CodingKeys: String, CodingKey { case type, flagID, minLevel, maxLevel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "oncePerTurn":
            let flag = try c.decode(String.self, forKey: .flagID)
            self = .oncePerTurn(flagID: flag)
        case "spellSlot":
            let minLevel = try c.decode(Int.self, forKey: .minLevel)
            let maxLevel = try c.decode(Int.self, forKey: .maxLevel)
            self = .spellSlot(minLevel: minLevel, maxLevel: maxLevel)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown TriggerCost: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .oncePerTurn(let flag):
            try c.encode("oncePerTurn", forKey: .type)
            try c.encode(flag, forKey: .flagID)
        case .spellSlot(let minLevel, let maxLevel):
            try c.encode("spellSlot", forKey: .type)
            try c.encode(minLevel, forKey: .minLevel)
            try c.encode(maxLevel, forKey: .maxLevel)
        }
    }
}

// MARK: - TriggerEffect

/// *What* the effect does to the in-flight roll. Slice A covered fixed dice;
/// Slice B adds class-level-scaled dice (Sneak Attack's Nd6); Slice C adds
/// flat damage bonuses (Rage's +2 / +3 STR melee).
enum TriggerEffect: Equatable {
    /// Append extra dice to the damage formula. `dice` is the same string
    /// format the parser accepts ("1d6", "2d4+1"). The damage type is either
    /// fixed (Hex → necrotic) or matches the weapon's own type
    /// (Hunter's Mark → matches the weapon).
    case addDamageDice(dice: String, damageType: TypedOrMatch)
    /// Append `count` dice of `die` (e.g. "d6") to the damage. `count` is a
    /// `LevelScaledValue` so Sneak Attack (1d6 → 10d6 across rogue levels)
    /// and similar scaling features share the same shape.
    case addScaledDamageDice(count: LevelScaledValue, die: String, damageType: TypedOrMatch)
    /// Add a flat number to the damage total. `damageType` nil routes through
    /// the formula's untyped modifier (Rage's +2 just adds to whatever damage
    /// type the weapon already deals); a fixed type routes through
    /// `typedModifiers` so the breakdown can attribute it.
    case addFlatDamage(amount: LevelScaledValue, damageType: TypedOrMatch?)
    /// Append dice that scale with the SPELL SLOT paid via the effect's
    /// `.spellSlot` cost (not class level): `baseDice` when the lowest-eligible
    /// slot is used, plus `extraDicePerSlotLevel` once per slot level above
    /// the cost's `minLevel`. Divine Smite: base `2d8`, `1d8` extra, radiant.
    /// Only meaningful with a `.spellSlot` cost — the resolver skips it
    /// otherwise.
    case addSlotScaledDamageDice(baseDice: String, extraDicePerSlotLevel: String, damageType: TypedOrMatch)
    /// A non-damage spellcasting buff applied while the effect is active
    /// (Innate Sorcery): raise the caster's spell save DC by `saveDCBonus`, and
    /// grant Advantage on the caster's spell attack rolls when `attackAdvantage`
    /// is true. Queried by `CharacterCalculator.spellcastingBuff`; the damage
    /// resolver ignores it.
    case spellcastingBuff(saveDCBonus: Int, attackAdvantage: Bool)
    /// While active: grant Advantage on the character's weapon attack rolls
    /// (Barbarian Reckless Attack at L2 — the SRD says only STR-based melee,
    /// but the app has no reliable "is this a STR melee?" gate that fires
    /// AFTER the recipe resolves, so we grant it on all weapon attacks and
    /// note the SRD scope in the feature description). The "attackers gain
    /// Advantage against you" downside stays honor-system since there's no
    /// enemy sheet.
    case recklessAttack
}

extension TriggerEffect: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, dice, damageType, count, die, amount
        case baseDice, extraDicePerSlotLevel
        case saveDCBonus, attackAdvantage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "addDamageDice":
            let dice = try c.decode(String.self, forKey: .dice)
            let dmg = try c.decode(TypedOrMatch.self, forKey: .damageType)
            self = .addDamageDice(dice: dice, damageType: dmg)
        case "addScaledDamageDice":
            let count = try c.decode(LevelScaledValue.self, forKey: .count)
            let die = try c.decode(String.self, forKey: .die)
            let dmg = try c.decode(TypedOrMatch.self, forKey: .damageType)
            self = .addScaledDamageDice(count: count, die: die, damageType: dmg)
        case "addFlatDamage":
            let amount = try c.decode(LevelScaledValue.self, forKey: .amount)
            let dmg = try c.decodeIfPresent(TypedOrMatch.self, forKey: .damageType)
            self = .addFlatDamage(amount: amount, damageType: dmg)
        case "addSlotScaledDamageDice":
            let base = try c.decode(String.self, forKey: .baseDice)
            let extra = try c.decode(String.self, forKey: .extraDicePerSlotLevel)
            let dmg = try c.decode(TypedOrMatch.self, forKey: .damageType)
            self = .addSlotScaledDamageDice(baseDice: base, extraDicePerSlotLevel: extra, damageType: dmg)
        case "spellcastingBuff":
            let dc = try c.decodeIfPresent(Int.self, forKey: .saveDCBonus) ?? 0
            let adv = try c.decodeIfPresent(Bool.self, forKey: .attackAdvantage) ?? false
            self = .spellcastingBuff(saveDCBonus: dc, attackAdvantage: adv)
        case "recklessAttack":
            self = .recklessAttack
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown TriggerEffect: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addDamageDice(let dice, let dmg):
            try c.encode("addDamageDice", forKey: .type)
            try c.encode(dice, forKey: .dice)
            try c.encode(dmg, forKey: .damageType)
        case .addScaledDamageDice(let count, let die, let dmg):
            try c.encode("addScaledDamageDice", forKey: .type)
            try c.encode(count, forKey: .count)
            try c.encode(die, forKey: .die)
            try c.encode(dmg, forKey: .damageType)
        case .addFlatDamage(let amount, let dmg):
            try c.encode("addFlatDamage", forKey: .type)
            try c.encode(amount, forKey: .amount)
            try c.encodeIfPresent(dmg, forKey: .damageType)
        case .addSlotScaledDamageDice(let base, let extra, let dmg):
            try c.encode("addSlotScaledDamageDice", forKey: .type)
            try c.encode(base, forKey: .baseDice)
            try c.encode(extra, forKey: .extraDicePerSlotLevel)
            try c.encode(dmg, forKey: .damageType)
        case .spellcastingBuff(let dc, let adv):
            try c.encode("spellcastingBuff", forKey: .type)
            try c.encode(dc, forKey: .saveDCBonus)
            try c.encode(adv, forKey: .attackAdvantage)
        case .recklessAttack:
            try c.encode("recklessAttack", forKey: .type)
        }
    }
}

// MARK: - TypedOrMatch

/// Where the damage type for an injected die comes from. Encoded as a single
/// string in JSON: the damage-type rawValue for `.fixed`, or the sentinel
/// `"$weapon"` for `.matchWeapon` — keeps spell JSON terse.
enum TypedOrMatch: Equatable {
    case fixed(DamageType)
    /// Resolves to the wielded weapon's `damageType` at attack time. Used by
    /// Hunter's Mark (the +1d6 deals the weapon's own damage type, not a
    /// fixed magical type).
    case matchWeapon
}

extension TypedOrMatch: Codable {
    private static let matchWeaponSentinel = "$weapon"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == Self.matchWeaponSentinel {
            self = .matchWeapon
        } else if let dt = DamageType(rawValue: raw) {
            self = .fixed(dt)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown TypedOrMatch: \(raw). Expected a damage type or '\(Self.matchWeaponSentinel)'."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .fixed(let dt):   try container.encode(dt.rawValue)
        case .matchWeapon:     try container.encode(Self.matchWeaponSentinel)
        }
    }
}

// MARK: - TriggerLifecycle

/// How long the effect sticks around once it's been granted. Slice A covered
/// concentration-tied persistence; Slice B adds the one-shot lifecycle that
/// per-attack opt-in effects (Sneak Attack, Divine Smite) use.
enum TriggerLifecycle: Equatable {
    case persistent(until: PersistenceEnd)
    /// Applied once when the trigger fires, then done. The resolver doesn't
    /// add anything to `Character.activeEffects` for these — they're
    /// per-action choices, not standing buffs.
    case oneShot
}

extension TriggerLifecycle: Codable {
    private enum CodingKeys: String, CodingKey { case type, until }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "persistent":
            let end = try c.decode(PersistenceEnd.self, forKey: .until)
            self = .persistent(until: end)
        case "oneShot":
            self = .oneShot
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown TriggerLifecycle: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .persistent(let end):
            try c.encode("persistent", forKey: .type)
            try c.encode(end, forKey: .until)
        case .oneShot:
            try c.encode("oneShot", forKey: .type)
        }
    }
}

// MARK: - PersistenceEnd

/// What ends a persistent effect. Slice A shipped `.concentrationEnds`;
/// Slice C adds `.rounds(_)` for Rage's 10-round timer and `.manual` for
/// buffs the player has to end themselves.
enum PersistenceEnd: Equatable {
    case concentrationEnds
    /// Lasts `count` rounds. The character ticks down on Start New Turn and
    /// the resolver drops the effect when the counter hits zero.
    case rounds(_ count: Int)
    /// No automatic end — the player drops it via the EffectsRow dismiss
    /// menu. Used for "until you dismiss" buffs.
    case manual
}

extension PersistenceEnd: Codable {
    private enum CodingKeys: String, CodingKey { case type, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "concentrationEnds": self = .concentrationEnds
        case "rounds":
            let n = try c.decode(Int.self, forKey: .count)
            self = .rounds(n)
        case "manual": self = .manual
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown PersistenceEnd: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .concentrationEnds: try c.encode("concentrationEnds", forKey: .type)
        case .rounds(let n):
            try c.encode("rounds", forKey: .type)
            try c.encode(n, forKey: .count)
        case .manual: try c.encode("manual", forKey: .type)
        }
    }
}
