import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SneakAttackOptInTests {

    // MARK: - Schema additions

    @Test func triggeredEffectDecodesWithoutActivationKey() throws {
        // Slice A JSON shape — no activation, no cost. Must keep working.
        let json = """
        {
          "id": "hex_rider", "name": "Hex",
          "trigger": { "type": "onDamageRoll" },
          "effect": { "type": "addDamageDice", "dice": "1d6", "damageType": "necrotic" },
          "lifecycle": { "type": "persistent", "until": { "type": "concentrationEnds" } }
        }
        """.data(using: .utf8)!
        let effect = try JSONDecoder().decode(TriggeredEffect.self, from: json)
        #expect(effect.activation == .automatic)
        #expect(effect.cost == nil)
    }

    @Test func triggeredEffectRoundTripsOptInWithCost() throws {
        let original = TriggeredEffect(
            id: "sneak_attack_rider",
            name: "Sneak Attack",
            trigger: .onAttackHit(filter: .weaponHasProperty([.finesse, .ammunition])),
            effect: .addScaledDamageDice(
                count: .byClassLevel([1: 1, 3: 2, 5: 3]),
                die: "d6",
                damageType: .matchWeapon
            ),
            lifecycle: .oneShot,
            activation: .optIn,
            cost: .oncePerTurn(flagID: "sneak_attack")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TriggeredEffect.self, from: data)
        #expect(decoded == original)
    }

    @Test func attackFilterMatchesAnyOfProperties() {
        let filter = AttackFilter.weaponHasProperty([.finesse, .ammunition])
        #expect(filter.matches(weapon: Self.rapier()))      // .finesse
        #expect(filter.matches(weapon: Self.shortbow()))    // .ammunition
        #expect(!filter.matches(weapon: Self.greataxe()))   // neither
        #expect(!filter.matches(weapon: nil))               // no weapon
    }

    @Test func attackFilterAllOfRequiresEveryChild() {
        let filter = AttackFilter.allOf([
            .weaponHasProperty([.finesse]),
            .weaponHasProperty([.light])
        ])
        #expect(filter.matches(weapon: Self.rapier()) == false)  // finesse but not light
        // (rapier is finesse only — fine for showing allOf semantics)
    }

    @Test func attackFilterAnyOfShortCircuits() {
        let filter = AttackFilter.anyOf([
            .weaponHasProperty([.heavy]),
            .weaponHasProperty([.finesse])
        ])
        #expect(filter.matches(weapon: Self.rapier()))       // matches second
        #expect(filter.matches(weapon: Self.greataxe()))     // matches first
    }

    // MARK: - Bundled rogue content

    @Test func bundledRogueLoadsWithSneakAttack() {
        let store = ContentStore()
        let rogue = store.classDefinition(id: "rogue")
        #expect(rogue?.name == "Rogue")
        let sneak = rogue?.levelFeatures[1]?.first { $0.id == "sneak_attack" }
        let effect = sneak?.triggeredEffect
        #expect(effect?.activation == .optIn)
        if case .onAttackHit(let filter)? = effect?.trigger {
            #expect(filter != nil)
        } else {
            Issue.record("Expected onAttackHit trigger on Sneak Attack")
        }
        if case .oncePerTurn(let flag)? = effect?.cost {
            #expect(flag == "sneak_attack")
        } else {
            Issue.record("Expected oncePerTurn cost on Sneak Attack")
        }
    }

    // MARK: - Resolver: opt-in chips from features

    @Test func optInRidersIncludesSneakAttackWithFinesseWeapon() {
        let store = ContentStore()
        let character = Self.makeRogue(level: 1)
        let chips = TriggeredEffectResolver.optInRiders(
            weapon: Self.rapier(),
            baseDamage: Self.baseDamage(),
            character: character,
            content: store
        )
        #expect(chips.count == 1)
        #expect(chips.first?.id == "rider_sneak_attack_rider")
        // Merged formula: base 1d8 piercing + 1d6 piercing rider, both groups
        // present, both damage-typed.
        let formula = chips.first?.action.formula
        #expect(formula?.groups.count == 2)
        #expect(formula?.groups.allSatisfy { $0.damageType == .piercing } == true)
        let riderGroup = formula?.groups.first { $0.kind == .d6 }
        #expect(riderGroup?.count == 1)
    }

    @Test func optInRidersScalesSneakAttackByClassLevel() {
        let store = ContentStore()
        let l5Rogue = Self.makeRogue(level: 5)
        let chips = TriggeredEffectResolver.optInRiders(
            weapon: Self.rapier(),
            baseDamage: Self.baseDamage(),
            character: l5Rogue,
            content: store
        )
        // Merged formula contains base 1d8 + 3d6 sneak attack at L5.
        let riderGroup = chips.first?.action.formula?.groups.first { $0.kind == .d6 }
        #expect(riderGroup?.count == 3)
    }

    @Test func optInRidersSkipsSneakAttackForGreataxe() {
        let store = ContentStore()
        let character = Self.makeRogue(level: 1)
        let chips = TriggeredEffectResolver.optInRiders(
            weapon: Self.greataxe(),
            baseDamage: Self.baseDamage(),
            character: character,
            content: store
        )
        // Greataxe is neither finesse nor ranged → filter blocks Sneak Attack.
        #expect(chips.isEmpty)
    }

    @Test func optInRidersSkipsWhenTurnFlagAlreadySet() {
        let store = ContentStore()
        var character = Self.makeRogue(level: 1)
        character.setTurnFlag("sneak_attack")
        let chips = TriggeredEffectResolver.optInRiders(
            weapon: Self.rapier(),
            baseDamage: Self.baseDamage(),
            character: character,
            content: store
        )
        #expect(chips.isEmpty)
    }

    @Test func optInRidersReturnsEmptyForCharacterWithoutFeature() {
        let store = ContentStore()
        let fighter = Self.makeFighter()
        let chips = TriggeredEffectResolver.optInRiders(
            weapon: Self.rapier(),
            baseDamage: Self.baseDamage(),
            character: fighter,
            content: store
        )
        // Fighter doesn't have Sneak Attack — no chips.
        #expect(chips.isEmpty)
    }

    // MARK: - Character turn-flag helpers

    @Test func startNewTurnClearsAllFlags() {
        var character = Self.makeRogue(level: 1)
        character.setTurnFlag("sneak_attack")
        character.setTurnFlag("lucky_feat")
        #expect(character.turnFlags == ["sneak_attack", "lucky_feat"])
        character.startNewTurn()
        #expect(character.turnFlags.isEmpty)
    }

    @Test func setTurnFlagIsIdempotent() {
        var character = Self.makeRogue(level: 1)
        character.setTurnFlag("sneak_attack")
        character.setTurnFlag("sneak_attack")
        #expect(character.turnFlags == ["sneak_attack"])
    }

    @Test func characterCodableBackwardsCompatTurnFlagsAbsent() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Bruenor", "level": 1,
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "strength": 16, "dexterity": 12, "constitution": 14, "intelligence": 10, "wisdom": 13, "charisma": 8 },
          "maxHP": 12, "currentHP": 12, "tempHP": 0,
          "inventory": [], "currency": { "platinum": 0, "gold": 0, "electrum": 0, "silver": 0, "copper": 0 },
          "notes": "", "resources": {},
          "spells": { "prepared": [], "known": [], "spellbook": [] },
          "featureSelections": {}, "conditions": [],
          "manifestVersion": 1, "proficiencies": {}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Character.self, from: json)
        #expect(decoded.turnFlags.isEmpty)
    }

    @Test func characterEncodeOmitsTurnFlagsWhenEmpty() throws {
        let character = Self.makeRogue(level: 1)
        let raw = String(data: try JSONEncoder().encode(character), encoding: .utf8) ?? ""
        #expect(!raw.contains("turnFlags"))
    }

    // MARK: - Helpers

    private static func makeRogue(level: Int) -> Character {
        Character(
            name: "Lazlo",
            level: level,
            speciesID: "human",
            backgroundID: "criminal",
            classEntries: [ClassEntry(classID: "rogue", level: level)],
            abilityScores: [
                .strength: 10, .dexterity: 17, .constitution: 14,
                .intelligence: 12, .wisdom: 13, .charisma: 10
            ],
            maxHP: 8 + 2 * level
        )
    }

    private static func makeFighter() -> Character {
        Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [
                .strength: 16, .dexterity: 12, .constitution: 14,
                .intelligence: 10, .wisdom: 13, .charisma: 8
            ],
            maxHP: 12
        )
    }

    /// Shared stub for a freshly-resolved weapon damage roll — the canonical
    /// 1d8 piercing rapier swing the merged chips will compose against.
    private static func baseDamage() -> ResolvedAction {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .piercing))
        formula.modifier = 3
        return ResolvedAction(
            id: "weapon_rapier_damage",
            label: "Rapier Damage",
            formula: formula,
            description: "1d8 + DEX"
        )
    }

    private static func rapier() -> WeaponDefinition {
        WeaponDefinition(
            id: "rapier", name: "Rapier", description: "",
            cost: 2500, weight: 2,
            weaponCategory: .martial,
            damage: "1d8", damageType: .piercing, damageAbility: .dexterity,
            properties: [.finesse],
            versatileDamage: nil, range: nil,
            masteryProperty: .vex,
            actionRecipes: []
        )
    }

    private static func shortbow() -> WeaponDefinition {
        WeaponDefinition(
            id: "shortbow", name: "Shortbow", description: "",
            cost: 2500, weight: 2,
            weaponCategory: .simple,
            damage: "1d6", damageType: .piercing, damageAbility: .dexterity,
            properties: [.ammunition, .twoHanded],
            versatileDamage: nil, range: "80/320",
            masteryProperty: .vex,
            actionRecipes: []
        )
    }

    private static func greataxe() -> WeaponDefinition {
        WeaponDefinition(
            id: "greataxe", name: "Greataxe", description: "",
            cost: 3000, weight: 7,
            weaponCategory: .martial,
            damage: "1d12", damageType: .slashing, damageAbility: .strength,
            properties: [.heavy, .twoHanded],
            versatileDamage: nil, range: nil,
            masteryProperty: .cleave,
            actionRecipes: []
        )
    }
}
