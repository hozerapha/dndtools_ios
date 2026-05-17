import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct RageToggleTests {

    // MARK: - Schema additions (Slice C)

    @Test func triggeredEffectRoundTripsToggleActivationAndFlatDamage() throws {
        let original = TriggeredEffect(
            id: "rage_damage_bonus",
            name: "Rage",
            trigger: .onDamageRoll(filter: .weaponLacksProperty([.ammunition])),
            effect: .addFlatDamage(
                amount: .byClassLevel([1: 2, 9: 3, 16: 4]),
                damageType: nil
            ),
            lifecycle: .persistent(until: .rounds(10)),
            activation: .toggle
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TriggeredEffect.self, from: data)
        #expect(decoded == original)
    }

    @Test func onDamageRollDecodesWithoutFilterKey() throws {
        // Pre-Slice-C Hex / Hunter's Mark JSON has no `filter` key.
        let json = """
        {
          "id": "hex_damage_rider", "name": "Hex",
          "trigger": { "type": "onDamageRoll" },
          "effect": { "type": "addDamageDice", "dice": "1d6", "damageType": "necrotic" },
          "lifecycle": { "type": "persistent", "until": { "type": "concentrationEnds" } }
        }
        """.data(using: .utf8)!
        let effect = try JSONDecoder().decode(TriggeredEffect.self, from: json)
        #expect(effect.trigger == .onDamageRoll(filter: nil))
    }

    @Test func weaponLacksPropertyMatchesMeleeBlocksRanged() {
        let melee = AttackFilter.weaponLacksProperty([.ammunition])
        #expect(melee.matches(weapon: Self.greataxe()))   // no ammunition → melee
        #expect(!melee.matches(weapon: Self.shortbow()))  // has ammunition
        #expect(!melee.matches(weapon: nil))              // unarmed → blocked
    }

    @Test func persistenceEndRoundsRoundTrips() throws {
        let lifecycle = TriggerLifecycle.persistent(until: .rounds(10))
        let data = try JSONEncoder().encode(lifecycle)
        let decoded = try JSONDecoder().decode(TriggerLifecycle.self, from: data)
        #expect(decoded == lifecycle)
    }

    @Test func persistenceEndManualRoundTrips() throws {
        let lifecycle = TriggerLifecycle.persistent(until: .manual)
        let data = try JSONEncoder().encode(lifecycle)
        let decoded = try JSONDecoder().decode(TriggerLifecycle.self, from: data)
        #expect(decoded == lifecycle)
    }

    // MARK: - ActiveEffect Codable

    @Test func activeEffectRoundTripsWithRoundsRemaining() throws {
        let original = ActiveEffect(
            effectID: "rage_damage_bonus",
            source: .feature(featureID: "rage"),
            roundsRemaining: 10
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActiveEffect.self, from: data)
        #expect(decoded == original)
        #expect(decoded.roundsRemaining == 10)
    }

    @Test func activeEffectDecodesWithoutRoundsRemainingField() throws {
        // Pre-Slice-C ActiveEffect JSON (Hex sitting on a saved character)
        // didn't carry roundsRemaining.
        let json = """
        { "effectID": "hex_damage_rider", "source": { "type": "spell", "spellID": "hex" } }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActiveEffect.self, from: json)
        #expect(decoded.roundsRemaining == nil)
    }

    // MARK: - Bundled content

    @Test func bundledBarbarianLoadsWithRage() {
        let store = ContentStore()
        let barb = store.classDefinition(id: "barbarian")
        #expect(barb?.name == "Barbarian")
        let rage = barb?.levelFeatures[1]?.first { $0.id == "rage" }
        #expect(rage?.resource?.id == "barbarian_rage_uses")
        let effect = rage?.triggeredEffect
        #expect(effect?.activation == .toggle)
        if case .persistent(.rounds(let n))? = effect?.lifecycle {
            #expect(n == 10)
        } else {
            Issue.record("Expected persistent(.rounds(10)) lifecycle on Rage")
        }
        if case .addFlatDamage(_, let typed)? = effect?.effect {
            #expect(typed == nil)  // untyped — augments the weapon's own damage
        } else {
            Issue.record("Expected addFlatDamage effect on Rage")
        }
    }

    // MARK: - Character toggle helpers

    @Test func toggleFeatureEffectActivatesAndDeactivates() {
        var character = Self.makeBarbarian(level: 1)
        let activated = character.toggleFeatureEffect(
            effectID: "rage_damage_bonus",
            featureID: "rage",
            roundsRemaining: 10
        )
        #expect(activated == true)
        #expect(character.activeEffects.count == 1)
        #expect(character.activeEffects.first?.roundsRemaining == 10)

        let deactivated = character.toggleFeatureEffect(
            effectID: "rage_damage_bonus",
            featureID: "rage",
            roundsRemaining: 10
        )
        #expect(deactivated == false)
        #expect(character.activeEffects.isEmpty)
    }

    @Test func startNewTurnDecrementsRoundsAndDropsExpired() {
        var character = Self.makeBarbarian(level: 1)
        character.toggleFeatureEffect(
            effectID: "rage_damage_bonus",
            featureID: "rage",
            roundsRemaining: 2
        )
        character.startNewTurn()
        #expect(character.activeEffects.first?.roundsRemaining == 1)
        character.startNewTurn()
        // 1 → 0, removed by the auto-cleanup pass.
        #expect(character.activeEffects.isEmpty)
    }

    @Test func startNewTurnLeavesUnroundedEffectsAlone() {
        var character = Self.makeBarbarian(level: 1)
        // Hex-style effect with no round timer should survive Start New Turn.
        character.activeEffects = [
            ActiveEffect(effectID: "hex_damage_rider", source: .spell(spellID: "hex"))
        ]
        character.startNewTurn()
        #expect(character.activeEffects.count == 1)
        #expect(character.activeEffects.first?.roundsRemaining == nil)
    }

    // MARK: - Resolver: Rage flat damage on melee, skipped on ranged

    @Test func resolverFoldsRageFlatDamageOntoGreataxe() {
        let store = ContentStore()
        var character = Self.makeBarbarian(level: 1)
        character.toggleFeatureEffect(
            effectID: "rage_damage_bonus",
            featureID: "rage",
            roundsRemaining: 10
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: Self.greataxeDamage(),
            weapon: Self.greataxe(),
            character: character,
            content: store
        )
        // Base modifier was 3 (STR); Rage adds +2 untyped at L1.
        #expect(enriched.formula?.modifier == 5)
    }

    @Test func resolverSkipsRageForShortbow() {
        let store = ContentStore()
        var character = Self.makeBarbarian(level: 1)
        character.toggleFeatureEffect(
            effectID: "rage_damage_bonus",
            featureID: "rage",
            roundsRemaining: 10
        )
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: Self.shortbowDamage(),
            weapon: Self.shortbow(),
            character: character,
            content: store
        )
        // Shortbow has .ammunition — Rage's weaponLacksProperty filter blocks.
        #expect(enriched.formula?.modifier == 3)  // unchanged
    }

    @Test func resolverSkipsRageWhenNotToggledOn() {
        let store = ContentStore()
        let character = Self.makeBarbarian(level: 1)
        // No toggleFeatureEffect call — activeEffects empty.
        let enriched = TriggeredEffectResolver.applyAutomaticDamageRiders(
            to: Self.greataxeDamage(),
            weapon: Self.greataxe(),
            character: character,
            content: store
        )
        #expect(enriched.formula?.modifier == 3)
    }

    // MARK: - Helpers

    private static func makeBarbarian(level: Int) -> Character {
        Character(
            name: "Grog",
            level: level,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "barbarian", level: level)],
            abilityScores: [
                .strength: 17, .dexterity: 13, .constitution: 16,
                .intelligence: 8, .wisdom: 10, .charisma: 10
            ],
            maxHP: 14 + 3 * level
        )
    }

    private static func greataxeDamage() -> ResolvedAction {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d12, count: 1, damageType: .slashing))
        formula.modifier = 3
        return ResolvedAction(
            id: "weapon_greataxe_damage",
            label: "Greataxe Damage",
            formula: formula,
            description: "1d12 + STR"
        )
    }

    private static func shortbowDamage() -> ResolvedAction {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .piercing))
        formula.modifier = 3
        return ResolvedAction(
            id: "weapon_shortbow_damage",
            label: "Shortbow Damage",
            formula: formula,
            description: "1d6 + DEX"
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
}
