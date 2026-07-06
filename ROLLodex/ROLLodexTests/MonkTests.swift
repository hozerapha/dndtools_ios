import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct MonkTests {

    // MARK: - Fixtures

    private func makeMonk(level: Int, openHand: Bool = false) -> Character {
        var selections: [String: [String]] = [:]
        if openHand {
            selections["monk_subclass"] = ["warrior_of_the_open_hand"]
        }
        return Character(
            name: "Ip", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "monk", level: level)],
            abilityScores: [
                .strength: 12, .dexterity: 16, .constitution: 14,
                .intelligence: 10, .wisdom: 16, .charisma: 8
            ],
            maxHP: 8,
            proficiencies: [.weapon(.simple): .proficient],
            featureSelections: selections
        )
    }

    // MARK: - Engine: scaling die + ability modifier on scaledDamage

    @Test func scaledDamageDieSizeGrowsWithLevel() {
        let recipe = ActionRecipe.scaledDamage(
            dieKind: .byClassLevel([1: 6, 5: 8, 11: 10, 17: 12]),
            count: .flat(1),
            damageType: .bludgeoning,
            addAbility: .dexterity,
            label: "Unarmed Strike"
        )
        let l1 = ActionInterpreter.resolve(recipe: recipe, character: makeMonk(level: 1), weapon: nil)
        #expect(l1.formula?.groups.first?.kind == .d6)
        #expect(l1.formula?.modifier == 3) // DEX +3
        let l5 = ActionInterpreter.resolve(recipe: recipe, character: makeMonk(level: 5), weapon: nil)
        #expect(l5.formula?.groups.first?.kind == .d8)
        let l17 = ActionInterpreter.resolve(recipe: recipe, character: makeMonk(level: 17), weapon: nil)
        #expect(l17.formula?.groups.first?.kind == .d12)
    }

    @Test func bareIntDieKindStillDecodes() throws {
        // Backward compat: pre-Monk content writes "dieKind": 10.
        let json = """
        {"type": "scaledDamage", "dieKind": 10, "count": {"byClassLevel": {"1": 1}}, "label": "Breath"}
        """.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(ActionRecipe.self, from: json)
        guard case .scaledDamage(let dieKind, _, _, let addAbility, _) = recipe else {
            Issue.record("wrong case"); return
        }
        #expect(dieKind == .flat(10))
        #expect(addAbility == nil)
    }

    @Test func abilityRollAddLevelAddsCharacterLevel() {
        let recipe = ActionRecipe.abilityRoll(
            dice: "1d10", ability: .dexterity, addLevel: true, label: "Deflect Attacks"
        )
        let resolved = ActionInterpreter.resolve(recipe: recipe, character: makeMonk(level: 5), weapon: nil)
        // 1d10 + DEX (+3) + level (5) = modifier 8.
        #expect(resolved.formula?.modifier == 8)
    }

    @Test func unarmedAttackAddsProficiencyBonus() {
        // weaponAttack with no weapon = unarmed strike; everyone is proficient.
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponAttack(abilityOverride: nil, finesse: true),
            character: makeMonk(level: 5),
            weapon: nil
        )
        // DEX +3 + PB +3 (L5) = +6.
        #expect(resolved.formula?.modifier == 6)
    }

    // MARK: - Class load

    @Test func loadsMonkWithFocusPool() {
        let store = ContentStore()
        let monk = store.classDefinition(id: "monk")
        #expect(monk?.hitDie == .d8)
        #expect(monk?.primaryAbility == .dexterity)
        #expect(monk?.spellcasting == nil)
        #expect(monk?.subclassLevel == 3)
        #expect(monk?.subclasses.first?.id == "warrior_of_the_open_hand")

        // Focus points = monk level, short-rest refresh.
        let l5 = makeMonk(level: 5)
        let focus = ResourceCalculator.availableResources(character: l5, content: store)
            .first { $0.definition.id == "monk_focus" }
        #expect(focus?.max == 5)
        #expect(focus?.definition.refreshOn == .shortRest)
    }

    @Test func monkACUsesWisdomUnarmoredDefense() {
        let store = ContentStore()
        let monk = makeMonk(level: 1)
        #expect(CharacterCalculator.unarmoredDefenseAbility(character: monk, content: store) == .wisdom)
    }

    // MARK: - Shared-pool costs (Focus spends)

    @Test func flurryOfBlowsSpendsFromTheFocusPool() {
        let store = ContentStore()
        let sections = CharacterActionDeriver.sections(for: makeMonk(level: 2), content: store)
        let rows = sections.flatMap(\.rows)
        let flurry = rows.first { $0.action.label.contains("Flurry") || $0.title?.contains("Flurry") == true }
        #expect(flurry != nil)
        #expect(flurry?.action.resourceCost == ResourceCost(resourceID: "monk_focus", amount: 1))
        // Badge reflects the SHARED pool, not a per-feature one.
        #expect(flurry?.badge == "2 / 2")
    }

    @Test func superiorDefenseExhaustsWhenPoolBelowCost() {
        let store = ContentStore()
        var monk = makeMonk(level: 18)
        monk.resources["monk_focus"] = ResourceState(current: 2) // needs 3
        let rows = CharacterActionDeriver.sections(for: monk, content: store).flatMap(\.rows)
        let superior = rows.first { $0.title?.contains("Superior Defense") == true }
        #expect(superior?.isExhausted == true)
    }

    // MARK: - Unarmored Movement

    @Test func unarmoredMovementScalesAndRequiresNoArmor() {
        let store = ContentStore()
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeMonk(level: 2), content: store, unarmored: true) == 10)
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeMonk(level: 6), content: store, unarmored: true) == 15)
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeMonk(level: 18), content: store, unarmored: true) == 30)
        // Armored: no bonus.
        #expect(CharacterCalculator.featureSpeedBonus(
            character: makeMonk(level: 6), content: store, unarmored: false) == 0)
    }

    // MARK: - Open Hand

    @Test func wholenessOfBodyPoolIsWisdomMod() {
        let store = ContentStore()
        let monk = makeMonk(level: 6, openHand: true)
        let pool = ResourceCalculator.availableResources(character: monk, content: store)
            .first { $0.definition.id == "monk_wholeness_of_body" }
        #expect(pool?.max == 3) // WIS 16 → +3
    }

    @Test func quiveringPalmCostsFourFocus() {
        let store = ContentStore()
        let monk = makeMonk(level: 17, openHand: true)
        let rows = CharacterActionDeriver.sections(for: monk, content: store).flatMap(\.rows)
        let palm = rows.first { $0.title?.contains("Quivering Palm") == true }
        #expect(palm?.action.resourceCost == ResourceCost(resourceID: "monk_focus", amount: 4))
    }
}
