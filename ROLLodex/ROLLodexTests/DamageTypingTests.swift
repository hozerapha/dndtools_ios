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

    // MARK: - displayString round-trips through the parser

    @Test func displayStringIncludesBracketPrefixWhenTyped() {
        let typed = DiceGroup(kind: .d10, count: 1, damageType: .fire)
        let untyped = DiceGroup(kind: .d10, count: 1)
        #expect(typed.displayString == "[fire]1d10")
        #expect(untyped.displayString == "1d10")
    }

    @Test func formulaDisplayStringRoundTripsThroughParser() throws {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .necrotic))
        formula.modifier = 3
        #expect(formula.displayString == "[slashing]1d8 + [necrotic]1d6 + 3")

        let reparsed = try DiceFormulaParser().parse(formula.displayString)
        #expect(reparsed.groups.count == 2)
        #expect(reparsed.groups[0].damageType == .slashing)
        #expect(reparsed.groups[1].damageType == .necrotic)
        #expect(reparsed.modifier == 3)
    }

    // MARK: - compactDisplayString (chip subtitle helper)

    @Test func compactDisplayStringCollapsesSharedType() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .piercing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .piercing))
        formula.modifier = 3
        #expect(formula.compactDisplayString == "1d8 + 1d6 + 3 piercing")
    }

    @Test func compactDisplayStringPreservesPrefixesWhenMixed() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .slashing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1, damageType: .necrotic))
        formula.modifier = 3
        // Mixed types — keep the per-group prefixes; nothing to collapse.
        #expect(formula.compactDisplayString == formula.displayString)
    }

    @Test func compactDisplayStringFallsBackWhenAGroupIsUntyped() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .piercing))
        formula.groups.append(DiceGroup(kind: .d6, count: 1))  // untyped
        // One untyped group would silently inherit the trailing type — leave
        // the verbose form so the player sees exactly which dice are typed.
        #expect(formula.compactDisplayString == formula.displayString)
    }

    @Test func compactDisplayStringFoldsTypedFlatModifier() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d8, count: 1, damageType: .fire))
        formula.typedModifiers[.fire] = 2
        formula.modifier = 1
        // 1d8 fire + +2 fire + +1 untyped (sole type) → "1d8 + 3 fire"
        #expect(formula.compactDisplayString == "1d8 + 3 fire")
    }

    @Test func applyDamageTypeStampsAllGroups() {
        var formula = try! DiceFormulaParser().parse("2d6+3")
        formula.applyDamageType(.fire)
        #expect(formula.groups.allSatisfy { $0.damageType == .fire })
    }

    // MARK: - Parser bracket / parens support

    @Test func parserReadsBracketDamageTypePrefix() throws {
        let formula = try DiceFormulaParser().parse("[fire]2d6+3")
        #expect(formula.groups.count == 1)
        #expect(formula.groups[0].damageType == .fire)
        #expect(formula.groups[0].kind == .d6)
        #expect(formula.groups[0].count == 2)
        #expect(formula.modifier == 3)
    }

    @Test func parserStripsParensForVisualGrouping() throws {
        let formula = try DiceFormulaParser().parse("([fire]2d6 + 2) + ([bludgeoning]3d8)")
        #expect(formula.groups.count == 2)
        #expect(formula.groups[0].damageType == .fire)
        #expect(formula.groups[0].count == 2)
        #expect(formula.groups[1].damageType == .bludgeoning)
        #expect(formula.groups[1].count == 3)
        #expect(formula.modifier == 2)
    }

    @Test func parserMergesSameTypedPlainGroups() throws {
        let formula = try DiceFormulaParser().parse("[fire]1d6 + [fire]2d6")
        #expect(formula.groups.count == 1)
        #expect(formula.groups[0].count == 3)
        #expect(formula.groups[0].damageType == .fire)
    }

    @Test func parserKeepsDifferentTypesSeparate() throws {
        let formula = try DiceFormulaParser().parse("[fire]1d6 + [cold]1d6 + 1d6")
        #expect(formula.groups.count == 3)
        #expect(formula.groups[0].damageType == .fire)
        #expect(formula.groups[1].damageType == .cold)
        #expect(formula.groups[2].damageType == nil)
    }

    @Test func parserRejectsUnknownDamageType() {
        do {
            _ = try DiceFormulaParser().parse("[nope]1d6")
            Issue.record("Expected unknownDamageType error")
        } catch let error as DiceFormulaParser.ParseError {
            if case .unknownDamageType(let name) = error {
                #expect(name == "nope")
            } else {
                Issue.record("Expected .unknownDamageType, got \(error)")
            }
        } catch {
            Issue.record("Expected DiceFormulaParser.ParseError, got \(error)")
        }
    }

    // MARK: - Typed flat modifiers

    @Test func parserRoutesBracketedFlatNumberIntoTypedModifiers() throws {
        let formula = try DiceFormulaParser().parse("[fire]5")
        #expect(formula.groups.isEmpty)
        #expect(formula.modifier == 0)
        #expect(formula.typedModifiers == [.fire: 5])
    }

    @Test func parserCombinesTypedDiceAndTypedFlatModifier() throws {
        // `[force]1d12 + [force]5 + [necrotic]1d6` — Magic-Missile-shaped
        // typed flat modifier on the same type as a dice group.
        let formula = try DiceFormulaParser().parse("[force]1d12+[force]5+[necrotic]1d6")
        #expect(formula.groups.count == 2)
        #expect(formula.groups[0].damageType == .force)
        #expect(formula.groups[1].damageType == .necrotic)
        #expect(formula.typedModifiers == [.force: 5])
        #expect(formula.modifier == 0)
    }

    @Test func parserCollapsesRepeatedTypedFlatModifiers() throws {
        let formula = try DiceFormulaParser().parse("[fire]2+[fire]3")
        #expect(formula.typedModifiers == [.fire: 5])
    }

    @Test func parserHandlesNegativeTypedFlatModifier() throws {
        let formula = try DiceFormulaParser().parse("[fire]5-[fire]2")
        #expect(formula.typedModifiers == [.fire: 3])
    }

    @Test func displayStringRoundTripsTypedFlatModifier() throws {
        let original = try DiceFormulaParser().parse("[force]1d12+[force]5+[necrotic]1d6")
        let reparsed = try DiceFormulaParser().parse(original.displayString)
        #expect(reparsed.groups.count == original.groups.count)
        #expect(reparsed.typedModifiers == original.typedModifiers)
        #expect(reparsed.modifier == original.modifier)
    }

    @Test func subtotalsByTypeAddsTypedFlatModifierToBucket() {
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d12, count: 1, damageType: .force))
        formula.groups.append(DiceGroup(kind: .d6,  count: 1, damageType: .necrotic))
        formula.typedModifiers = [.force: 5]
        let result = RollResult(
            formula: formula,
            dieRolls: [
                DieRoll(kind: .d12, value: 8),
                DieRoll(kind: .d6,  value: 4)
            ]
        )
        // force = d12(8) + flat 5 = 13; necrotic = d6(4)
        #expect(result.subtotalsByType == [.force: 13, .necrotic: 4])
    }

    @Test func subtotalsByTypeAttachesUntypedModifierWhenAllShareSingleTypeIncludingTypedMod() {
        // groups all force AND typed-modifier all force → untyped +2 also
        // attaches to force.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d12, count: 1, damageType: .force))
        formula.typedModifiers = [.force: 5]
        formula.modifier = 2
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d12, value: 8)]
        )
        #expect(result.subtotalsByType == [.force: 15])
    }

    @Test func subtotalsByTypeFallsToNilWhenTypedModBreaksSingleTypeRule() {
        // groups all force but typed mod is necrotic → untyped +2 falls to nil.
        var formula = DiceFormula()
        formula.groups.append(DiceGroup(kind: .d12, count: 1, damageType: .force))
        formula.typedModifiers = [.necrotic: 5]
        formula.modifier = 2
        let result = RollResult(
            formula: formula,
            dieRolls: [DieRoll(kind: .d12, value: 8)]
        )
        #expect(result.subtotalsByType == [.force: 8, .necrotic: 5, nil: 2])
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
        guard case .rawDamage(_, let damageType, _, _) = recipes.first else {
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
