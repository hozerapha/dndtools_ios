import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SpellTests {

    // MARK: - Codable round-trips

    @Test func spellDefinitionDecodes() throws {
        let json = """
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
        let spell = try JSONDecoder().decode(SpellDefinition.self, from: json)
        #expect(spell.name == "Magic Missile")
        #expect(spell.level == 1)
        #expect(spell.school == .evocation)
        #expect(spell.actionRecipes.count == 1)
        if case .extraDicePerLevel(let index, let dice, let interval)? = spell.upcastEffect {
            #expect(index == 0)
            #expect(dice == "1d4+1")
            #expect(interval == 1)  // default when JSON omits levelsPerBonus
        } else {
            Issue.record("Expected extraDicePerLevel upcastEffect")
        }
    }

    @Test func cantripDecodesWithLevelZero() throws {
        let json = """
        {
          "id": "fire_bolt",
          "name": "Fire Bolt",
          "level": 0,
          "school": "evocation",
          "castingTime": { "type": "action" },
          "range": { "type": "feet", "value": 120 },
          "components": { "verbal": true, "somatic": true },
          "duration": { "type": "instantaneous" },
          "description": "...",
          "actionRecipes": [
            { "type": "rawDamage", "dice": "1d10", "damageType": "fire", "label": "Fire Bolt" }
          ]
        }
        """.data(using: .utf8)!
        let spell = try JSONDecoder().decode(SpellDefinition.self, from: json)
        #expect(spell.isCantrip)
        #expect(spell.upcastEffect == nil)
    }

    // MARK: - Slot table

    @Test func slotTableLookupForFullCaster() {
        // Wizard at L3: 4 L1 slots, 2 L2 slots.
        let table = SlotTable.fullCaster([
            1: [1: 2],
            3: [1: 4, 2: 2],
            5: [1: 4, 2: 3, 3: 2]
        ])
        let slots = table.slots(atClassLevel: 3)
        #expect(slots[1] == 4)
        #expect(slots[2] == 2)
        #expect(slots[3] == nil)
    }

    @Test func slotTableHandlesGapInClassLevels() {
        // L1 entry, no L2 entry, L3 entry. At L2 the lookup should fall back
        // to the highest key ≤ 2, which is 1.
        let table = SlotTable.fullCaster([
            1: [1: 2],
            3: [1: 4]
        ])
        let l2 = table.slots(atClassLevel: 2)
        #expect(l2[1] == 2)
    }

    @Test func pactMagicCollapsesToSingleSlotLevel() {
        let table = SlotTable.pactMagic([
            1: PactSlots(slotLevel: 1, count: 1),
            3: PactSlots(slotLevel: 2, count: 2)
        ])
        let l3 = table.slots(atClassLevel: 3)
        #expect(l3.count == 1)
        #expect(l3[2] == 2)
    }

    // MARK: - Slot synthesis through the resource calculator

    @Test func wizardL1HasTwoFirstLevelSlots() {
        let store = ContentStore()
        let character = makeWizard(level: 1)
        let resources = ResourceCalculator.availableResources(character: character, content: store)
        let l1Slot = resources.first { $0.definition.id == "wizard_slot_1" }
        #expect(l1Slot?.max == 2)
        #expect(l1Slot?.current == 2)
        // displayHint should categorize it as a spell slot for the UI.
        if case .spellSlot(let level)? = l1Slot?.definition.displayHint {
            #expect(level == 1)
        } else {
            Issue.record("Expected spellSlot displayHint")
        }
    }

    @Test func slotConsumeDecrementsCurrent() {
        let store = ContentStore()
        var character = makeWizard(level: 1)
        let ok = ResourceCalculator.consume(
            amount: 1, from: "wizard_slot_1",
            in: &character, content: store
        )
        #expect(ok)
        #expect(character.resources["wizard_slot_1"]?.current == 1)
    }

    @Test func longRestRestoresSpellSlots() {
        let store = ContentStore()
        var character = makeWizard(level: 1)
        _ = ResourceCalculator.consume(amount: 1, from: "wizard_slot_1", in: &character, content: store)
        _ = ResourceCalculator.consume(amount: 1, from: "wizard_slot_1", in: &character, content: store)
        let pending = ResourceCalculator.applyRest(.long, to: &character, content: store)
        #expect(pending.isEmpty)
        #expect(character.resources["wizard_slot_1"]?.current == 2)
    }

    @Test func shortRestDoesNotRestoreFullCasterSlots() {
        let store = ContentStore()
        var character = makeWizard(level: 1)
        _ = ResourceCalculator.consume(amount: 1, from: "wizard_slot_1", in: &character, content: store)
        let pending = ResourceCalculator.applyRest(.short, to: &character, content: store)
        #expect(pending.isEmpty)
        // Wizard slots refresh on long rest only.
        #expect(character.resources["wizard_slot_1"]?.current == 1)
    }

    // MARK: - Upcast scaling

    @Test func upcastAtBaseLevelLeavesRecipesUnchanged() {
        let spell = SpellDefinition(
            id: "magic_missile",
            name: "Magic Missile",
            level: 1,
            school: .evocation,
            castingTime: .action,
            range: .feet(120),
            components: SpellComponents(verbal: true, somatic: true),
            duration: .instantaneous,
            description: "",
            actionRecipes: [.rawDamage(dice: "3d4+3", damageType: .force, label: "Magic Missile")],
            upcastEffect: .extraDicePerLevel(recipeIndex: 0, dice: "1d4+1")
        )
        let recipes = spell.recipes(castAtLevel: 1)
        if case .rawDamage(let dice, _, _, _) = recipes[0] {
            #expect(dice == "3d4+3")
        } else {
            Issue.record("Expected rawDamage at base level")
        }
    }

    @Test func upcastAddsExtraDicePerLevel() {
        // Magic Missile at L3 = base 3d4+3 + 2 × (1d4+1) → "3d4+3+1d4+1+1d4+1".
        let spell = SpellDefinition(
            id: "magic_missile",
            name: "Magic Missile",
            level: 1,
            school: .evocation,
            castingTime: .action,
            range: .feet(120),
            components: SpellComponents(verbal: true, somatic: true),
            duration: .instantaneous,
            description: "",
            actionRecipes: [.rawDamage(dice: "3d4+3", damageType: .force, label: "Magic Missile")],
            upcastEffect: .extraDicePerLevel(recipeIndex: 0, dice: "1d4+1")
        )
        let recipes = spell.recipes(castAtLevel: 3)
        guard case .rawDamage(let dice, _, _, _) = recipes[0] else {
            Issue.record("Expected rawDamage")
            return
        }
        // Verify the parser can resolve the extended formula (5 d4 + 5 mod).
        let formula = try? DiceFormulaParser().parse(dice)
        #expect(formula?.groups.first?.kind == .d4)
        #expect(formula?.groups.first?.count == 5)
        #expect(formula?.modifier == 5)
    }

    @Test func upcastEveryTwoLevelsHoldsAtIntermediateSlots() {
        // Flame Blade / Spiritual Weapon shape: +1d6 every two slot levels
        // above base. L2 = 3d6, L3 = 3d6 (no bonus yet), L4 = 4d6, L5 = 4d6,
        // L6 = 5d6, L8 = 6d6. Integer-divided extras.
        let spell = SpellDefinition(
            id: "flame_blade_fixture",
            name: "Flame Blade",
            level: 2,
            school: .evocation,
            castingTime: .action,
            range: .targetSelf,
            components: SpellComponents(verbal: true, somatic: true),
            duration: .instantaneous,
            description: "",
            actionRecipes: [.rawDamage(dice: "3d6", damageType: .fire, label: "Flame Blade")],
            upcastEffect: .extraDicePerLevel(recipeIndex: 0, dice: "1d6", levelsPerBonus: 2)
        )
        func d6Count(atLevel level: Int) -> Int? {
            let recipes = spell.recipes(castAtLevel: level)
            guard case .rawDamage(let dice, _, _, _) = recipes[0],
                  let formula = try? DiceFormulaParser().parse(dice) else { return nil }
            return formula.groups.reduce(0) { $0 + ($1.kind == .d6 ? $1.count : 0) }
        }
        #expect(d6Count(atLevel: 2) == 3)  // base
        #expect(d6Count(atLevel: 3) == 3)  // holds — only 1 extra level
        #expect(d6Count(atLevel: 4) == 4)  // +1d6 (2 extra levels ÷ 2 = 1)
        #expect(d6Count(atLevel: 5) == 4)  // holds
        #expect(d6Count(atLevel: 6) == 5)  // +2d6
        #expect(d6Count(atLevel: 8) == 6)  // +3d6
    }

    @Test func bundledEveryTwoLevelsSpellsUseLevelsPerBonusTwo() {
        // Guardrail: Flame Blade + Spiritual Weapon are the only bundled
        // spells with per-two-levels scaling; both should ship with the new
        // levelsPerBonus field. If a future author adds another such spell
        // without the field, its damage will over-scale by 2×.
        let store = ContentStore()
        for id in ["flame_blade", "spiritual_weapon"] {
            let spell = store.spellDefinition(id: id)
            guard case .extraDicePerLevel(_, _, let interval)? = spell?.upcastEffect else {
                Issue.record("\(id) missing extraDicePerLevel upcast"); continue
            }
            #expect(interval == 2, "\(id) should scale every 2 levels")
        }
    }

    @Test func upcastIsNoOpForSpellsWithoutEffect() {
        let spell = SpellDefinition(
            id: "fire_bolt",
            name: "Fire Bolt",
            level: 0,
            school: .evocation,
            castingTime: .action,
            range: .feet(120),
            components: SpellComponents(verbal: true, somatic: true),
            duration: .instantaneous,
            description: "",
            actionRecipes: [.rawDamage(dice: "1d10", damageType: .fire, label: "Fire Bolt")]
        )
        let recipes = spell.recipes(castAtLevel: 5)
        if case .rawDamage(let dice, _, _, _) = recipes[0] {
            #expect(dice == "1d10")
        } else {
            Issue.record("Expected rawDamage")
        }
    }

    // MARK: - Spell attack recipe

    @Test func spellAttackRecipeRoundTrips() throws {
        let recipe = ActionRecipe.spellAttack(label: "Fire Bolt Attack")
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(ActionRecipe.self, from: data)
        #expect(decoded == recipe)
    }

    @Test func spellAttackResolvesWithSpellcastingAbility() {
        // Wizard L1, INT 16 (+3 mod) + prof bonus (+2) = +5 spell attack.
        let character = makeWizard(level: 1)
        let recipe = ActionRecipe.spellAttack(label: "Fire Bolt Attack")
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: character,
            weapon: nil,
            spellcastingAbility: .intelligence
        )
        #expect(resolved.formula?.groups.first?.kind == .d20)
        #expect(resolved.formula?.groups.first?.count == 1)
        #expect(resolved.formula?.modifier == 5)
    }

    @Test func spellAttackWithoutAbilityReturnsNoFormula() {
        // Defensive: if the caller forgets to pass a spellcasting ability we
        // return an action with no formula rather than rolling +0.
        let character = makeWizard(level: 1)
        let recipe = ActionRecipe.spellAttack(label: "Fire Bolt Attack")
        let resolved = ActionInterpreter.resolve(
            recipe: recipe,
            character: character,
            weapon: nil,
            spellcastingAbility: nil
        )
        #expect(resolved.formula == nil)
    }

    @Test func fireBoltSpellHasBothAttackAndDamageRecipes() throws {
        let json = """
        {
          "id": "fire_bolt",
          "name": "Fire Bolt",
          "level": 0,
          "school": "evocation",
          "castingTime": { "type": "action" },
          "range": { "type": "feet", "value": 120 },
          "components": { "verbal": true, "somatic": true },
          "duration": { "type": "instantaneous" },
          "description": "...",
          "actionRecipes": [
            { "type": "spellAttack", "label": "Fire Bolt Attack" },
            { "type": "rawDamage", "dice": "1d10", "damageType": "fire", "label": "Fire Bolt Damage" }
          ]
        }
        """.data(using: .utf8)!
        let spell = try JSONDecoder().decode(SpellDefinition.self, from: json)
        #expect(spell.actionRecipes.count == 2)
        if case .spellAttack = spell.actionRecipes[0] {} else {
            Issue.record("Expected spellAttack as first recipe")
        }
        if case .rawDamage = spell.actionRecipes[1] {} else {
            Issue.record("Expected rawDamage as second recipe")
        }
    }

    // MARK: - rawDamage recipe

    @Test func rawDamageRecipeRoundTrips() throws {
        let recipe = ActionRecipe.rawDamage(dice: "3d4+3", damageType: .force, label: "Magic Missile")
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(ActionRecipe.self, from: data)
        #expect(decoded == recipe)
    }

    @Test func actionInterpreterResolvesRawDamageWithInlineModifier() {
        let character = makeWizard(level: 1)
        let recipe = ActionRecipe.rawDamage(dice: "3d4+3", damageType: .force, label: "Magic Missile")
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: character, weapon: nil)
        // 3d4 group + modifier of +3.
        #expect(resolved.formula?.groups.first?.kind == .d4)
        #expect(resolved.formula?.groups.first?.count == 3)
        #expect(resolved.formula?.modifier == 3)
    }

    // MARK: - Ritual casting

    @Test func castingTimeRitualRoundTrips() throws {
        let times: [CastingTime] = [
            .ritual(base: .action),
            .ritual(base: .bonusAction),
            .ritual(base: .minutes(10))
        ]
        for time in times {
            let data = try JSONEncoder().encode(time)
            let decoded = try JSONDecoder().decode(CastingTime.self, from: data)
            #expect(decoded == time)
        }
    }

    @Test func bundledDetectMagicIsTaggedRitual() {
        let store = ContentStore()
        guard let spell = store.spellDefinition(id: "detect_magic") else {
            Issue.record("Detect Magic not in bundled content")
            return
        }
        if case .ritual = spell.castingTime {
            // ok
        } else {
            Issue.record("Detect Magic should be tagged as ritual")
        }
        // Detect Magic has no recipes — slot-tap should cast immediately in the UI.
        #expect(spell.actionRecipes.isEmpty)
    }

    @Test func bundledWizardHasRitualCasting() {
        let store = ContentStore()
        let block = store.classDefinition(id: "wizard")?.spellcasting
        #expect(block?.ritualCasting == true)
    }

    // MARK: - Spell effects (on-cast sheet state)

    @Test func spellEffectRoundTrips() throws {
        let cases: [SpellEffect] = [
            .tempHP(dice: "2d4+4"),
            .selfCondition(id: "invisible"),
            .targetCondition(id: "paralyzed"),
        ]
        for effect in cases {
            let data = try JSONEncoder().encode(effect)
            #expect(try JSONDecoder().decode(SpellEffect.self, from: data) == effect)
        }
    }

    @Test func bundledSpellsCarryTheirEffects() {
        let store = ContentStore()
        if case .tempHP(let dice)? = store.spellDefinition(id: "false_life")?.effects.first {
            #expect(dice == "2d4+4")
        } else {
            Issue.record("false_life missing tempHP effect")
        }
        func targetCond(_ spellID: String) -> String? {
            guard case .targetCondition(let id)? = store.spellDefinition(id: spellID)?.effects.first else { return nil }
            return id
        }
        #expect(targetCond("hold_person") == "paralyzed")
        #expect(targetCond("fear") == "frightened")
        #expect(targetCond("ray_of_sickness") == "poisoned")
        #expect(targetCond("charm_monster") == "charmed")
        // A damage cantrip with no sheet effect stays empty.
        #expect(store.spellDefinition(id: "fire_bolt")?.effects.isEmpty == true)
    }

    // MARK: - Helpers

    private func makeWizard(level: Int) -> Character {
        Character(
            name: "Mordenkainen", level: level,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: level)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 16, .wisdom: 12, .charisma: 10
            ],
            maxHP: 6
        )
    }
}
