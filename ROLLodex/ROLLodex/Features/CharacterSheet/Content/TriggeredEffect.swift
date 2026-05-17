import Foundation

/// A single magical/feature/item rider that hooks into the action pipeline:
/// "when X happens, modify the roll." The canonical Slice A case is Hex —
/// when the caster damages a target with a weapon, add 1d6 necrotic.
///
/// Slice A intentionally ships only the shapes Hex and Hunter's Mark need:
/// `TriggerCondition.onDamageRoll`, `TriggerEffect.addDamageDice`, a
/// concentration-tied lifecycle. Sneak Attack / Divine Smite / GWM in later
/// slices will extend the enums (opt-in chips, attack-time filters, etc.).
struct TriggeredEffect: Codable, Equatable {
    /// Stable id used by `ActiveEffect.effectID` for state tracking. Must be
    /// unique across the spell/feature/item that defines the effect.
    let id: String
    /// Player-facing label for the badge ("Hex", "Hunter's Mark").
    let name: String
    let trigger: TriggerCondition
    let effect: TriggerEffect
    let lifecycle: TriggerLifecycle
}

// MARK: - TriggerCondition

/// *When* the effect fires. Slice A only covers `.onDamageRoll`; the rest of
/// the sketch in `PLAN_CharacterSheet.md` lands as later slices need it.
enum TriggerCondition: Equatable {
    /// Fires on every weapon-damage roll the affected character makes. No
    /// filter in Slice A — Hex / Hunter's Mark match all weapon damage.
    case onDamageRoll
}

extension TriggerCondition: Codable {
    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "onDamageRoll": self = .onDamageRoll
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
        case .onDamageRoll: try c.encode("onDamageRoll", forKey: .type)
        }
    }
}

// MARK: - TriggerEffect

/// *What* the effect does to the in-flight roll. Slice A only covers
/// `.addDamageDice` (extra typed dice on a damage roll).
enum TriggerEffect: Equatable {
    /// Append extra dice to the damage formula. `dice` is the same string
    /// format the parser accepts ("1d6", "2d4+1"). The damage type is either
    /// fixed (Hex → necrotic) or matches the weapon's own type
    /// (Hunter's Mark → matches the weapon).
    case addDamageDice(dice: String, damageType: TypedOrMatch)
}

extension TriggerEffect: Codable {
    private enum CodingKeys: String, CodingKey { case type, dice, damageType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "addDamageDice":
            let dice = try c.decode(String.self, forKey: .dice)
            let dmg = try c.decode(TypedOrMatch.self, forKey: .damageType)
            self = .addDamageDice(dice: dice, damageType: dmg)
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

/// How long the effect sticks around once it's been granted. Slice A only
/// covers concentration-tied persistence — the same lifecycle that Hex,
/// Hunter's Mark, Bless, and most 5e buffs share.
enum TriggerLifecycle: Equatable {
    case persistent(until: PersistenceEnd)
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
        }
    }
}

// MARK: - PersistenceEnd

/// What ends a persistent effect. Slice A only ships `.concentrationEnds`;
/// `.rounds`, `.shortRest`, `.longRest`, `.manual` land with Rage / Battle
/// Master / GWM later.
enum PersistenceEnd: Equatable {
    case concentrationEnds
}

extension PersistenceEnd: Codable {
    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "concentrationEnds": self = .concentrationEnds
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
        }
    }
}
