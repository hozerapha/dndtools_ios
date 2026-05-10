import Foundation

/// Casting time. Most spells are `.action` or `.bonusAction`; longer-form
/// rituals and prep spells use `.minutes`. Reactions carry a trigger string
/// for the spell description ("which you take when…").
enum CastingTime: Codable, Equatable {
    case action
    case bonusAction
    case reaction(trigger: String)
    case minutes(Int)
    /// Spell can be cast as a ritual (slot-free) when also tagged as such on
    /// the casting class. `base` is the normal action cost when not casting
    /// it as a ritual. `indirect` because the case references its own type.
    indirect case ritual(base: CastingTime)

    private enum CodingKeys: String, CodingKey { case type, trigger, minutes, base }
    private enum Kind: String, Codable { case action, bonusAction, reaction, minutes, ritual }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .action:       self = .action
        case .bonusAction:  self = .bonusAction
        case .reaction:     self = .reaction(trigger: try c.decodeIfPresent(String.self, forKey: .trigger) ?? "")
        case .minutes:      self = .minutes(try c.decode(Int.self, forKey: .minutes))
        case .ritual:
            // Nested base; default to .action if missing.
            if let base = try c.decodeIfPresent(CastingTime.self, forKey: .base) {
                self = .ritual(base: base)
            } else {
                self = .ritual(base: .action)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action:                   try c.encode(Kind.action, forKey: .type)
        case .bonusAction:              try c.encode(Kind.bonusAction, forKey: .type)
        case .reaction(let trigger):
            try c.encode(Kind.reaction, forKey: .type)
            try c.encode(trigger, forKey: .trigger)
        case .minutes(let n):
            try c.encode(Kind.minutes, forKey: .type)
            try c.encode(n, forKey: .minutes)
        case .ritual(let base):
            try c.encode(Kind.ritual, forKey: .type)
            try c.encode(base, forKey: .base)
        }
    }

    var shortLabel: String {
        switch self {
        case .action:               return "Action"
        case .bonusAction:          return "Bonus"
        case .reaction:             return "Reaction"
        case .minutes(let n):       return "\(n) min"
        case .ritual(let base):     return "\(base.shortLabel) (R)"
        }
    }
}

/// How far the spell reaches. `.targetSelf` avoids the Swift `.self` keyword.
enum SpellRange: Codable, Equatable {
    case targetSelf
    case touch
    case feet(Int)
    case miles(Int)
    case unlimited
    /// Spells that target self but emit an effect ("Self (15-foot cone)").
    case selfEmits(area: String)

    private enum CodingKeys: String, CodingKey { case type, value, area }
    private enum Kind: String, Codable { case targetSelf, touch, feet, miles, unlimited, selfEmits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .targetSelf: self = .targetSelf
        case .touch:      self = .touch
        case .feet:       self = .feet(try c.decode(Int.self, forKey: .value))
        case .miles:      self = .miles(try c.decode(Int.self, forKey: .value))
        case .unlimited:  self = .unlimited
        case .selfEmits:  self = .selfEmits(area: try c.decode(String.self, forKey: .area))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .targetSelf:        try c.encode(Kind.targetSelf, forKey: .type)
        case .touch:             try c.encode(Kind.touch, forKey: .type)
        case .feet(let n):
            try c.encode(Kind.feet, forKey: .type)
            try c.encode(n, forKey: .value)
        case .miles(let n):
            try c.encode(Kind.miles, forKey: .type)
            try c.encode(n, forKey: .value)
        case .unlimited:         try c.encode(Kind.unlimited, forKey: .type)
        case .selfEmits(let a):
            try c.encode(Kind.selfEmits, forKey: .type)
            try c.encode(a, forKey: .area)
        }
    }

    var shortLabel: String {
        switch self {
        case .targetSelf:           return "Self"
        case .touch:                return "Touch"
        case .feet(let n):          return "\(n) ft"
        case .miles(let n):         return "\(n) mi"
        case .unlimited:            return "Unlimited"
        case .selfEmits(let area):  return "Self (\(area))"
        }
    }
}

struct SpellComponents: Codable, Equatable {
    var verbal: Bool
    var somatic: Bool
    var material: String?     // present and non-nil → material required, with description

    init(verbal: Bool = false, somatic: Bool = false, material: String? = nil) {
        self.verbal = verbal
        self.somatic = somatic
        self.material = material
    }

    private enum CodingKeys: String, CodingKey { case verbal, somatic, material }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verbal   = try c.decodeIfPresent(Bool.self, forKey: .verbal) ?? false
        somatic  = try c.decodeIfPresent(Bool.self, forKey: .somatic) ?? false
        material = try c.decodeIfPresent(String.self, forKey: .material)
    }

    var shortLabel: String {
        var parts: [String] = []
        if verbal  { parts.append("V") }
        if somatic { parts.append("S") }
        if material != nil { parts.append("M") }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }
}

enum SpellDuration: Codable, Equatable {
    case instantaneous
    case rounds(Int)
    case minutes(Int)
    case hours(Int)
    case days(Int)
    case untilDispelled
    /// Concentration spell — caller is responsible for clearing any prior
    /// concentration and prompting a Con save when the caster takes damage
    /// (the latter lands in Phase L).
    case concentration(maxMinutes: Int?)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable {
        case instantaneous, rounds, minutes, hours, days, untilDispelled, concentration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .instantaneous:  self = .instantaneous
        case .rounds:         self = .rounds(try c.decode(Int.self, forKey: .value))
        case .minutes:        self = .minutes(try c.decode(Int.self, forKey: .value))
        case .hours:          self = .hours(try c.decode(Int.self, forKey: .value))
        case .days:           self = .days(try c.decode(Int.self, forKey: .value))
        case .untilDispelled: self = .untilDispelled
        case .concentration:  self = .concentration(maxMinutes: try c.decodeIfPresent(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .instantaneous:      try c.encode(Kind.instantaneous, forKey: .type)
        case .rounds(let n):
            try c.encode(Kind.rounds, forKey: .type)
            try c.encode(n, forKey: .value)
        case .minutes(let n):
            try c.encode(Kind.minutes, forKey: .type)
            try c.encode(n, forKey: .value)
        case .hours(let n):
            try c.encode(Kind.hours, forKey: .type)
            try c.encode(n, forKey: .value)
        case .days(let n):
            try c.encode(Kind.days, forKey: .type)
            try c.encode(n, forKey: .value)
        case .untilDispelled:     try c.encode(Kind.untilDispelled, forKey: .type)
        case .concentration(let max):
            try c.encode(Kind.concentration, forKey: .type)
            try c.encodeIfPresent(max, forKey: .value)
        }
    }

    var requiresConcentration: Bool {
        if case .concentration = self { return true }
        return false
    }

    var shortLabel: String {
        switch self {
        case .instantaneous:        return "Instant"
        case .rounds(let n):        return "\(n) rd"
        case .minutes(let n):       return "\(n) min"
        case .hours(let n):         return "\(n) hr"
        case .days(let n):          return "\(n) day"
        case .untilDispelled:       return "Dispel"
        case .concentration(let m):
            if let m { return "Conc, \(m) min" }
            return "Conc"
        }
    }
}
