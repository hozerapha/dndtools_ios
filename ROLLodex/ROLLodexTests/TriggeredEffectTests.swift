import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct TriggeredEffectTests {

    // MARK: - Schema Codable

    @Test func triggeredEffectRoundTripsThroughJSON() throws {
        let original = TriggeredEffect(
            id: "hex_damage_rider",
            name: "Hex",
            trigger: .onDamageRoll(filter: nil),
            effect: .addDamageDice(dice: "1d6", damageType: .fixed(.necrotic)),
            lifecycle: .persistent(until: .concentrationEnds)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TriggeredEffect.self, from: data)
        #expect(decoded == original)
    }

    @Test func typedOrMatchEncodesFixedAsRawDamageTypeString() throws {
        let value = TypedOrMatch.fixed(.necrotic)
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"necrotic\"")
    }

    @Test func typedOrMatchEncodesMatchWeaponAsSentinel() throws {
        let value = TypedOrMatch.matchWeapon
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"$weapon\"")
    }

    @Test func typedOrMatchRejectsUnknownString() {
        let json = "\"not_a_real_type\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TypedOrMatch.self, from: json)
        }
    }

    @Test func activeEffectRoundTripsWithSpellSource() throws {
        let original = ActiveEffect(
            effectID: "hex_damage_rider",
            source: .spell(spellID: "hex")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActiveEffect.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Bundled content

    @Test func bundledHexLoadsWithTriggeredEffect() {
        let store = ContentStore()
        let hex = store.spellDefinition(id: "hex")
        #expect(hex?.name == "Hex")
        let effect = hex?.grantsTriggeredEffect
        #expect(effect?.id == "hex_damage_rider")
        #expect(effect?.trigger == .onDamageRoll(filter: nil))
        if case .addDamageDice(let dice, let typed)? = effect?.effect {
            #expect(dice == "1d6")
            #expect(typed == .fixed(.necrotic))
        } else {
            Issue.record("Expected addDamageDice effect on Hex")
        }
    }

    @Test func bundledHuntersMarkUsesMatchWeapon() {
        let store = ContentStore()
        let mark = store.spellDefinition(id: "hunters_mark")
        if case .addDamageDice(_, let typed)? = mark?.grantsTriggeredEffect?.effect {
            #expect(typed == .matchWeapon)
        } else {
            Issue.record("Expected addDamageDice with matchWeapon on Hunter's Mark")
        }
    }

    // MARK: - Character Codable backwards-compat

    @Test func characterDecodesWithoutActiveEffectsKey() throws {
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Bruenor",
          "level": 1,
          "speciesID": "human",
          "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "strength": 16, "dexterity": 12, "constitution": 14, "intelligence": 10, "wisdom": 13, "charisma": 8 },
          "maxHP": 12,
          "currentHP": 12,
          "tempHP": 0,
          "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "resources": {},
          "spells": { "prepared": [], "known": [], "spellbook": [] },
          "featureSelections": {},
          "conditions": [],
          "manifestVersion": 1,
          "proficiencies": {}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Character.self, from: legacyJSON)
        #expect(decoded.activeEffects.isEmpty)
    }

    @Test func characterEncodeOmitsActiveEffectsWhenEmpty() throws {
        let character = Self.makeFighter()
        let data = try JSONEncoder().encode(character)
        let raw = String(data: data, encoding: .utf8) ?? ""
        #expect(!raw.contains("activeEffects"))
    }

    // MARK: - Concentration helpers

    @Test func startConcentratingAppendsGrantedEffect() {
        var character = Self.makeFighter()
        let effect = Self.hexEffect()
        character.startConcentrating(on: "hex", grantsEffect: effect)
        #expect(character.concentratingSpellID == "hex")
        #expect(character.activeEffects.count == 1)
        #expect(character.activeEffects.first?.effectID == "hex_damage_rider")
        if case .spell(let id)? = character.activeEffects.first?.source {
            #expect(id == "hex")
        } else {
            Issue.record("Expected spell source")
        }
    }

    @Test func startConcentratingDedupesRepeatedCasts() {
        var character = Self.makeFighter()
        let effect = Self.hexEffect()
        character.startConcentrating(on: "hex", grantsEffect: effect)
        character.startConcentrating(on: "hex", grantsEffect: effect)
        #expect(character.activeEffects.count == 1)
    }

    @Test func startConcentratingDropsPriorSpellsEffectOnSwap() {
        var character = Self.makeFighter()
        character.startConcentrating(on: "hex", grantsEffect: Self.hexEffect())
        character.startConcentrating(on: "hunters_mark", grantsEffect: Self.huntersMarkEffect())
        // Hex's rider should be gone; only Hunter's Mark should remain.
        #expect(character.activeEffects.count == 1)
        #expect(character.activeEffects.first?.effectID == "hunters_mark_damage_rider")
        #expect(character.concentratingSpellID == "hunters_mark")
    }

    @Test func stopConcentratingDropsSpellSourcedEffects() {
        var character = Self.makeFighter()
        character.startConcentrating(on: "hex", grantsEffect: Self.hexEffect())
        character.stopConcentrating()
        #expect(character.concentratingSpellID == nil)
        #expect(character.activeEffects.isEmpty)
    }

    @Test func dismissActiveEffectAlsoDropsMatchingConcentration() {
        var character = Self.makeFighter()
        character.startConcentrating(on: "hex", grantsEffect: Self.hexEffect())
        character.dismissActiveEffect("hex_damage_rider")
        #expect(character.concentratingSpellID == nil)
        #expect(character.activeEffects.isEmpty)
    }

    @Test func dismissActiveEffectLeavesUnrelatedConcentrationAlone() {
        var character = Self.makeFighter()
        // Player is concentrating on a different spell than the effect being dismissed.
        character.concentratingSpellID = "bless"
        character.activeEffects = [
            ActiveEffect(effectID: "homebrew_rider", source: .feature(featureID: "fighter_rage"))
        ]
        character.dismissActiveEffect("homebrew_rider")
        #expect(character.concentratingSpellID == "bless")
        #expect(character.activeEffects.isEmpty)
    }

    // MARK: - Resolver

    @Test func resolverAppendsHexNecroticDieToWeaponDamage() throws {
        let store = ContentStore()
        var character = Self.makeFighter()
        character.startConcentrating(on: "hex", grantsEffect: Self.hexEffect())
        let weapon = Self.longsword()
        let base = ResolvedAction(
            id: "weapon_longsword_damage",
            label: "Longsword Damage",
            formula: try DiceFormulaParser().parse("[slashing]1d8+3"),
            description: "1d8 + STR"
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: base, weapon: weapon, character: character, content: store
        )
        let formula = try #require(enriched.formula)
        // Expect: original slashing 1d8 + necrotic 1d6 group from Hex.
        let necroticGroup = formula.groups.first { $0.damageType == .necrotic }
        #expect(necroticGroup?.kind == .d6)
        #expect(necroticGroup?.count == 1)
        #expect(enriched.label.contains("Hex"))
    }

    @Test func resolverUsesWeaponDamageTypeForHuntersMark() throws {
        let store = ContentStore()
        var character = Self.makeFighter()
        character.startConcentrating(on: "hunters_mark", grantsEffect: Self.huntersMarkEffect())
        let weapon = Self.longsword()
        let base = ResolvedAction(
            id: "weapon_longsword_damage",
            label: "Longsword Damage",
            formula: try DiceFormulaParser().parse("[slashing]1d8+3"),
            description: nil
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: base, weapon: weapon, character: character, content: store
        )
        let formula = try #require(enriched.formula)
        // The rider should have stamped slashing too (matching the longsword).
        let slashingGroups = formula.groups.filter { $0.damageType == .slashing }
        #expect(slashingGroups.count == 2) // 1d8 base + 1d6 rider
    }

    @Test func resolverIsNoOpWhenNoActiveEffectsMatch() throws {
        let store = ContentStore()
        let character = Self.makeFighter()  // no active effects
        let base = ResolvedAction(
            id: "weapon_dagger_damage",
            label: "Dagger Damage",
            formula: try DiceFormulaParser().parse("[piercing]1d4+2"),
            description: nil
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: base, weapon: Self.longsword(), character: character, content: store
        )
        #expect(enriched.formula == base.formula)
        #expect(enriched.label == base.label)
    }

    @Test func resolverSkipsMatchWeaponWhenWeaponIsNil() throws {
        let store = ContentStore()
        var character = Self.makeFighter()
        character.startConcentrating(on: "hunters_mark", grantsEffect: Self.huntersMarkEffect())
        let base = ResolvedAction(
            id: "unarmed_strike",
            label: "Unarmed Strike",
            formula: try DiceFormulaParser().parse("1d4+3"),
            description: nil
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: base, weapon: nil, character: character, content: store
        )
        // Hunter's Mark can't infer a type without a weapon — skip silently.
        #expect(enriched.formula == base.formula)
    }

    // MARK: - Helpers

    private static func hexEffect() -> TriggeredEffect {
        TriggeredEffect(
            id: "hex_damage_rider",
            name: "Hex",
            trigger: .onDamageRoll(filter: nil),
            effect: .addDamageDice(dice: "1d6", damageType: .fixed(.necrotic)),
            lifecycle: .persistent(until: .concentrationEnds)
        )
    }

    private static func huntersMarkEffect() -> TriggeredEffect {
        TriggeredEffect(
            id: "hunters_mark_damage_rider",
            name: "Hunter's Mark",
            trigger: .onDamageRoll(filter: nil),
            effect: .addDamageDice(dice: "1d6", damageType: .matchWeapon),
            lifecycle: .persistent(until: .concentrationEnds)
        )
    }

    private static func makeFighter() -> Character {
        Character(
            name: "Bruenor",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [
                .strength: 16, .dexterity: 12, .constitution: 14,
                .intelligence: 10, .wisdom: 13, .charisma: 8
            ],
            maxHP: 12
        )
    }

    private static func longsword() -> WeaponDefinition {
        WeaponDefinition(
            id: "longsword",
            name: "Longsword",
            description: "",
            cost: 1500,
            weight: 3,
            weaponCategory: .martial,
            damage: "1d8",
            damageType: .slashing,
            damageAbility: .strength,
            properties: [.versatile],
            versatileDamage: "1d10",
            range: nil,
            masteryProperty: .sap,
            actionRecipes: []
        )
    }
}
