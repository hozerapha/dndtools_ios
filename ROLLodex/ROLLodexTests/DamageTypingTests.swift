import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct DamageTypingTests {

    // MARK: - DiceGroup Codable

    @Test func diceGroupRoundTripsWithDamageType() throws {
        let group = DiceGroup(kind: .d8, count: 1, damageType: .slashing)
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(DiceGroup.self, from: data)
        #expect(decoded.damageType == .slashing)
        #expect(decoded.kind == .d8)
        #expect(decoded.count == 1)
    }

    @Test func diceGroupDecodesLegacyJSONWithoutDamageType() throws {
        // Pre-Phase-N JSON: groups had no `damageType` field. Existing histories
        // and saved presets must keep decoding cleanly.
        let json = """
        { "id": "00000000-0000-0000-0000-000000000001", "kind": 8, "count": 1 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DiceGroup.self, from: json)
        #expect(decoded.damageType == nil)
        #expect(decoded.kind == .d8)
        #expect(decoded.count == 1)
    }

    // MARK: - DiceGroup equality / hashability

    @Test func diceGroupEqualityIncludesDamageType() {
        let slash = DiceGroup(kind: .d8, count: 1, damageType: .slashing)
        let fire = DiceGroup(kind: .d8, count: 1, damageType: .fire)
        let untyped = DiceGroup(kind: .d8, count: 1)
        #expect(slash != fire)
        #expect(slash != untyped)
    }

    // MARK: - displayString variants

    @Test func displayStringStaysUntypedForParserRoundTrip() {
        let group = DiceGroup(kind: .d10, count: 1, damageType: .fire)
        #expect(group.displayString == "1d10")
        #expect(group.displayStringWithType == "1d10 fire")
    }

    @Test func formulaDisplayStringWithTypesPrintsEachGroup() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .necrotic))
        formula.modifier = 3
        #expect(formula.displayString == "1d8 + 1d6 + 3")
        #expect(formula.displayStringWithTypes == "1d8 slashing + 1d6 necrotic + 3")
    }

    @Test func applyDamageTypeStampsAllGroups() {
        var formula = try! DiceFormulaParser().parse("2d6+3")
        formula.applyDamageType(.fire)
        #expect(formula.groups.allSatisfy { $0.damageType == .fire })
    }

    // MARK: - RollResult.subtotalsByType

    @Test func subtotalsByTypeUntypedFormulaBucketsToNil() {
        // 1d20+3 ability check — all under nil.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.modifier = 3
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d20, value: 14)]
        )
        #expect(result.subtotalsByType == [nil: 17])
    }

    @Test func subtotalsByTypeSingleTypedFormulaAttachesModifierToType() {
        // Longsword: 1d8+3 slashing. STR bonus belongs to the slashing total.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.modifier = 3
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d8, value: 5)]
        )
        #expect(result.subtotalsByType == [.slashing: 8])
        #expect(result.total == 8)
    }

    @Test func subtotalsByTypeMixedTypesBucketModifierToNil() {
        // Hypothetical Eldritch Smite: 1d8 slashing + 1d6 radiant + 3.
        // With mixed types, the flat +3 is ambiguous — falls under nil.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .radiant))
        formula.modifier = 3
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d8, value: 5),
                DieRoll(kind: .d6, value: 4)
            ]
        )
        #expect(result.subtotalsByType == [.slashing: 5, .radiant: 4, nil: 3])
    }

    @Test func subtotalsByTypeAggregatesGroupsOfSameType() {
        // 2d6 fire + 1d6 fire should collapse to a single fire bucket.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d6, count: 2, damageType: .fire))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .fire))
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d6, value: 3),
                DieRoll(kind: .d6, value: 4),
                DieRoll(kind: .d6, value: 2)
            ]
        )
        #expect(result.subtotalsByType == [.fire: 9])
    }

    @Test func subtotalsByTypeIgnoresDroppedDice() {
        // 2d20kh1 — only the kept d20 counts toward the bucket.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 2, modifier: .keepHighest(1)))
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d20, value: 8,  isKept: false),
                DieRoll(kind: .d20, value: 17, isKept: true)
            ]
        )
        #expect(result.subtotalsByType == [nil: 17])
    }

    @Test func subtotalsByTypeStripsZeroValueBuckets() {
        // A typed group that rolls all-dropped + zero modifier should not surface.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d8, value: 4, isKept: false)]
        )
        #expect(result.subtotalsByType.isEmpty)
    }

    @Test func subtotalsByTypeHandlesAdvantageDoubleD20() {
        // adv/dis path: one d20 group, two dieRolls. Cursor must consume both.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        formula.modifier = 5
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d20, value: 18, isKept: true),
                DieRoll(kind: .d20, value: 6,  isKept: false)
            ],
            mode: .advantage
        )
        #expect(result.subtotalsByType == [nil: 23])
    }

    @Test func hasTypedDamageReflectsBuckets() {
        var typed = DiceFormula()
        typed.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        let typedResult = RollResult(
            formula: typed,
            dieRolls: [DieRoll(kind: .d8, value: 5)]
        )
        #expect(typedResult.hasTypedDamage == true)

        var untyped = DiceFormula()
        untyped.groups.append(DiceGroup(kind: .d20, count: 1))
        let untypedResult = RollResult(
            formula: untyped,
            dieRolls: [DieRoll(kind: .d20, value: 12)]
        )
        #expect(untypedResult.hasTypedDamage == false)
    }

    // MARK: - ActionInterpreter wires damage type through

    @Test func weaponDamageStampsWeaponDamageTypeOntoGroups() {
        let character = Self.makeFighter()
        let weapon = Self.makeLongsword()
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponDamage(dieOverride: nil, addAbility: true, versatile: false),
            character: character,
            weapon: weapon
        )
        let formula = resolved.formula
        #expect(formula?.groups.first?.damageType == .slashing)
    }

    @Test func rawDamageStampsRecipeDamageTypeOntoAllGroups() {
        let character = Self.makeFighter()
        // Magic Missile shape — 3d4+3 force. Parser yields one d4 group; modifier
        // lives on the formula. The damage type should land on the group.
        let resolved = ActionInterpreter.resolve(
            recipe: .rawDamage(dice: "3d4+3", damageType: .force, label: "Magic Missile"),
            character: character,
            weapon: nil
        )
        let formula = resolved.formula
        #expect(formula?.groups.allSatisfy { $0.damageType == .force } == true)
        #expect(formula?.modifier == 3)
    }

    @Test func healDoesNotStampDamageType() {
        let character = Self.makeFighter()
        let resolved = ActionInterpreter.resolve(
            recipe: .heal(dice: "1d8", addLevel: true, label: "Cure Wounds"),
            character: character,
            weapon: nil
        )
        let formula = resolved.formula
        #expect(formula?.groups.first?.damageType == nil)
    }

    // MARK: - Spell upcast preserves damage type

    @Test func upcastScalingPreservesDamageTypeThroughInterpreter() throws {
        // Magic Missile cast at L3 → 3d4+3 + 1d4+1 + 1d4+1 force. The parser
        // produces a single d4 group from the combined string; what matters is
        // that the interpreter still stamps `force` onto the parsed groups.
        let spell = try JSONDecoder().decode(SpellDefinition.self, from: Self.magicMissileJSON)
        let recipes = spell.recipes(castAtLevel: 3)
        // Sanity: still rawDamage carrying the same damage type.
        guard case .rawDamage(_, let damageType, _) = recipes.first else {
            Issue.record("Expected rawDamage recipe")
            return
        }
        #expect(damageType == .force)

        let character = Self.makeFighter()
        let resolved = ActionInterpreter.resolve(
            recipe: recipes[0],
            character: character,
            weapon: nil
        )
        #expect(resolved.formula?.groups.allSatisfy { $0.damageType == .force } == true)
    }

    // MARK: - DamageBreakdownView text formatting

    @Test func breakdownTextIsNilForUntypedRolls() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d20, count: 1))
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d20, value: 14)]
        )
        #expect(DamageBreakdownView.text(for: result) == nil)
    }

    @Test func breakdownTextSingleTypeReadsAsTotalAndType() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.modifier = 3
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d8, value: 5)]
        )
        #expect(DamageBreakdownView.text(for: result) == "8 slashing")
    }

    @Test func breakdownTextMultiTypeJoinsByPlus() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .radiant))
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d8, value: 5),
                DieRoll(kind: .d6, value: 4)
            ]
        )
        // Sorted descending by value: slashing(5) first, radiant(4) second.
        #expect(DamageBreakdownView.text(for: result) == "5 slashing + 4 radiant")
    }

    @Test func breakdownTextAppendsUntypedTrailingChunkWithMixedTypes() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .radiant))
        formula.modifier = 3 // mixed types → modifier lands under nil
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d8, value: 5),
                DieRoll(kind: .d6, value: 4)
            ]
        )
        #expect(DamageBreakdownView.text(for: result) == "5 slashing + 4 radiant + 3")
    }

    // MARK: - Helpers

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
            maxHP: 12,
            proficiencies: [
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ]
        )
    }

    private static func makeLongsword() -> WeaponDefinition {
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

    private static let magicMissileJSON: Data = """
    {
      "id": "magic_missile",
      "name": "Magic Missile",
      "level": 1,
      "school": "evocation",
      "castingTime": { "type": "action" },
      "range": { "type": "feet", "value": 120 },
      "components": { "verbal": true, "somatic": true },
      "duration": { "type": "instantaneous" },
      "description": "...",
      "actionRecipes": [
        { "type": "rawDamage", "dice": "3d4+3", "damageType": "force", "label": "Magic Missile" }
      ],
      "upcastEffect": { "type": "extraDicePerLevel", "recipeIndex": 0, "dice": "1d4+1" }
    }
    """.data(using: .utf8)!
}
