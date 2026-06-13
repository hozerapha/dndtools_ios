import Testing
import Foundation
@testable import ROLLodex

/// Cleric (roadmap item 11a): first `preparedFromAll` caster, Channel
/// Divinity with Divine Spark recipes, Life Domain subclass, and the
/// `addSpellcastingMod` recipe flag that 2024 healing math needs.
@MainActor
struct ClericTests {

    // MARK: - addSpellcastingMod schema

    @Test func healDecodesSpellcastingModFlag() throws {
        let json = """
        { "type": "heal", "dice": "2d8", "addSpellcastingMod": true, "label": "Cure Wounds" }
        """.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(ActionRecipe.self, from: json)
        let shape: Bool
        if case .heal(let dice, let addLevel, let addMod, _) = recipe {
            shape = dice == "2d8" && !addLevel && addMod
        } else {
            shape = false
        }
        #expect(shape)

        // Round-trip keeps the flag.
        let reencoded = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(ActionRecipe.self, from: reencoded)
        let stable = decoded == recipe
        #expect(stable)
    }

    @Test func legacyHealJSONDefaultsFlagOff() throws {
        let json = """
        { "type": "heal", "dice": "1d10", "addLevel": true, "label": "Second Wind" }
        """.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(ActionRecipe.self, from: json)
        let flagOff: Bool
        if case .heal(_, _, let addMod, _) = recipe {
            flagOff = !addMod
        } else {
            flagOff = false
        }
        #expect(flagOff)
    }

    // MARK: - Interpreter math

    @Test func healAddsSpellcastingModifier() {
        let cleric = makeCleric(level: 1) // WIS 16 → +3
        let resolved = ActionInterpreter.resolve(
            recipe: .heal(dice: "2d8", addLevel: false, addSpellcastingMod: true, label: "Cure Wounds"),
            character: cleric,
            weapon: nil,
            spellcastingAbility: .wisdom
        )
        #expect(resolved.formula?.modifier == 3)
        #expect(resolved.formula?.groups.first?.count == 2)
    }

    @Test func healWithoutAbilityDegradesToBareDice() {
        let cleric = makeCleric(level: 1)
        let resolved = ActionInterpreter.resolve(
            recipe: .heal(dice: "2d8", addLevel: false, addSpellcastingMod: true, label: "Cure Wounds"),
            character: cleric,
            weapon: nil,
            spellcastingAbility: nil
        )
        // No ability supplied → no guessing, just the dice.
        #expect(resolved.formula?.modifier == 0)
    }

    @Test func rawDamageAddsSpellcastingModifier() {
        let cleric = makeCleric(level: 2)
        let resolved = ActionInterpreter.resolve(
            recipe: .rawDamage(dice: "1d8", damageType: .radiant, addSpellcastingMod: true, label: "Divine Spark (Damage)"),
            character: cleric,
            weapon: nil,
            spellcastingAbility: .wisdom
        )
        #expect(resolved.formula?.modifier == 3)
        let radiant = resolved.formula?.groups.first?.damageType == .radiant
        #expect(radiant)
    }

    // MARK: - Bundled Cleric

    @Test func bundledClericLoads() {
        let content = ContentStore()
        let cleric = content.classDefinition(id: "cleric")
        #expect(cleric != nil)
        let isD8 = cleric?.hitDie == .d8
        #expect(isD8)
        let savesMatch = cleric?.savingThrows == [.wisdom, .charisma]
        #expect(savesMatch)
        let prepared = cleric?.spellcasting?.preparedRule == .preparedFromAll
        #expect(prepared)
        let wisCaster = cleric?.spellcasting?.ability == .wisdom
        #expect(wisCaster)
        #expect(cleric?.subclassLevel == 3)
        #expect(cleric?.masteryCount == nil)
    }

    @Test func channelDivinityScalesUses() {
        let content = ContentStore()
        let cd = content.classDefinition(id: "cleric")?
            .levelFeatures[2]?
            .first { $0.id == "channel_divinity" }?
            .resource
        #expect(cd?.id == "cleric_channel_divinity")
        #expect(cd?.max.value(classLevel: 2, characterLevel: 2) == 2)
        #expect(cd?.max.value(classLevel: 6, characterLevel: 6) == 3)
        #expect(cd?.max.value(classLevel: 18, characterLevel: 18) == 4)
    }

    @Test func clericSlotsSynthesize() {
        let content = ContentStore()
        let cleric = makeCleric(level: 1)
        let slots = ResourceCalculator.availableResources(character: cleric, content: content)
            .filter { resolved in
                if case .spellSlot = resolved.definition.displayHint { return true }
                return false
            }
        #expect(slots.count == 1)
        #expect(slots.first?.id == "cleric_slot_1")
        #expect(slots.first?.max == 2)
    }

    @Test func divineSparkRowsCarryChannelDivinityCost() {
        let content = ContentStore()
        let cleric = makeCleric(level: 2) // WIS 16 → +3
        let rows = CharacterActionDeriver.sections(for: cleric, content: content)
            .first { $0.id == "features" }?
            .rows ?? []

        let sparkRows = rows.filter { $0.action.label.contains("Divine Spark") }
        #expect(sparkRows.count == 2)
        let allCostCD = sparkRows.allSatisfy { $0.action.resourceCost?.resourceID == "cleric_channel_divinity" }
        #expect(allCostCD)
        // Divine Spark = 1d8 + WIS mod, resolved against the class's casting stat.
        let healRow = sparkRows.first { $0.action.label.contains("Heal") }
        #expect(healRow?.action.formula?.modifier == 3)
    }

    // MARK: - Bundled spells

    @Test func healingWordHealsWithModifierAndUpcasts() {
        let content = ContentStore()
        let spell = content.spellDefinition(id: "healing_word")
        #expect(spell?.level == 1)

        let cleric = makeCleric(level: 1)
        let baseRecipes = spell?.recipes(castAtLevel: 1) ?? []
        #expect(baseRecipes.count == 1)
        let base = ActionInterpreter.resolve(
            recipe: baseRecipes[0],
            character: cleric,
            weapon: nil,
            spellcastingAbility: .wisdom
        )
        // 2d4 + 3
        #expect(base.formula?.modifier == 3)
        #expect(base.formula?.groups.reduce(0) { $0 + $1.count } == 2)

        // Cast at 3rd level: +2d4 per level above 1st → 6d4 + 3.
        let upcast = spell?.recipes(castAtLevel: 3) ?? []
        let resolved = ActionInterpreter.resolve(
            recipe: upcast[0],
            character: cleric,
            weapon: nil,
            spellcastingAbility: .wisdom
        )
        #expect(resolved.formula?.groups.reduce(0) { $0 + $1.count } == 6)
        #expect(resolved.formula?.modifier == 3)
    }

    @Test func cureWoundsUsesTwentyTwentyFourNumbers() {
        let content = ContentStore()
        let spell = content.spellDefinition(id: "cure_wounds")
        let shape: Bool
        if case .heal(let dice, _, let addMod, _)? = spell?.actionRecipes.first {
            shape = dice == "2d8" && addMod
        } else {
            shape = false
        }
        #expect(shape)
    }

    // MARK: - Life Domain

    @Test func lifeDomainFeaturesGateByLevel() {
        let content = ContentStore()
        guard let cleric = content.classDefinition(id: "cleric") else {
            Issue.record("cleric missing")
            return
        }
        let atThree = cleric.resolvedFeatures(throughClassLevel: 3, subclassID: "life_domain")
            .map(\.feature.id)
        #expect(atThree.contains("disciple_of_life"))
        #expect(atThree.contains("preserve_life"))
        #expect(!atThree.contains("blessed_healer"))

        let atSix = cleric.resolvedFeatures(throughClassLevel: 6, subclassID: "life_domain")
            .map(\.feature.id)
        #expect(atSix.contains("blessed_healer"))
    }

    // MARK: - Helpers

    private func makeCleric(level: Int) -> Character {
        Character(
            name: "Pike", level: level,
            speciesID: "human", backgroundID: "acolyte",
            classEntries: [ClassEntry(classID: "cleric", level: level)],
            abilityScores: [.wisdom: 16, .strength: 12, .constitution: 14],
            maxHP: 8 + 5 * level,
            currentHP: 8 + 5 * level
        )
    }
}
