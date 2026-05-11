import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct ConditionTests {

    // MARK: - Schema

    @Test func conditionDefinitionDecodes() throws {
        let json = """
        {
          "id": "restrained",
          "name": "Restrained",
          "description": "Speed 0, attacks against advantage, attacks by disadvantage, Dex save disadvantage.",
          "effects": [
            { "type": "speedZero" },
            { "type": "attacksAgainstHaveAdvantage" },
            { "type": "attacksByHaveDisadvantage" },
            { "type": "savingThrowDisadvantage", "abilities": ["dexterity"] }
          ]
        }
        """.data(using: .utf8)!
        let def = try JSONDecoder().decode(ConditionDefinition.self, from: json)
        #expect(def.id == "restrained")
        #expect(def.effects.count == 4)
        if case .savingThrowDisadvantage(let abilities) = def.effects.last {
            #expect(abilities == [.dexterity])
        } else {
            Issue.record("Expected savingThrowDisadvantage as last effect")
        }
    }

    @Test func bundledContentLoadsAllSRDConditions() {
        let store = ContentStore()
        let all = store.allConditions
        // 14 SRD conditions.
        #expect(all.count == 14)
        #expect(store.conditionDefinition(id: "poisoned") != nil)
        #expect(store.conditionDefinition(id: "stunned")?.effects.contains(.incapacitated) == true)
    }

    // MARK: - Character state

    @Test func applyConditionAddsAndDedupes() {
        var character = makeFighter()
        character.applyCondition(id: "poisoned", source: "Goblin shaman")
        #expect(character.conditions.count == 1)
        // Re-applying replaces the source rather than stacking.
        character.applyCondition(id: "poisoned", source: "Wyvern bite")
        #expect(character.conditions.count == 1)
        #expect(character.conditions.first?.source == "Wyvern bite")
    }

    @Test func removeConditionDropsIt() {
        var character = makeFighter()
        character.applyCondition(id: "blinded")
        character.applyCondition(id: "prone")
        character.removeCondition(id: "blinded")
        #expect(character.conditions.map(\.id) == ["prone"])
    }

    @Test func characterCodableRoundTripsConditions() throws {
        var character = makeFighter()
        character.applyCondition(id: "stunned", source: "Mind Sliver")
        character.concentratingSpellID = "hex"
        let data = try JSONEncoder().encode(character)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.conditions.first?.id == "stunned")
        #expect(decoded.conditions.first?.source == "Mind Sliver")
        #expect(decoded.concentratingSpellID == "hex")
    }

    @Test func characterDecodesWithoutConditionsField() throws {
        let id = UUID().uuidString
        let json = """
        {
          "id": "\(id)",
          "name": "Old", "level": 1,
          "speciesID": "human", "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "strength": 16 },
          "maxHP": 10, "currentHP": 10, "tempHP": 0,
          "proficiencies": {}, "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        #expect(character.conditions.isEmpty)
        #expect(character.concentratingSpellID == nil)
    }

    // MARK: - Concentration

    @Test func startingConcentrationStoresSpellID() {
        var character = makeFighter()
        character.startConcentrating(on: "bless")
        #expect(character.concentratingSpellID == "bless")
    }

    @Test func startingNewConcentrationReplacesPrior() {
        var character = makeFighter()
        character.startConcentrating(on: "bless")
        character.startConcentrating(on: "hex")
        #expect(character.concentratingSpellID == "hex")
    }

    @Test func damageWhileConcentratingReturnsCheckWithDC10Floor() {
        var character = makeFighter()
        character.startConcentrating(on: "hex")
        let check = character.applyDamage(5)
        #expect(check != nil)
        // 5 damage → DC max(10, 5/2) = 10.
        #expect(check?.dc == 10)
        #expect(check?.damageTaken == 5)
        #expect(check?.spellID == "hex")
    }

    @Test func damageWhileConcentratingScalesDCAboveFloor() {
        var character = makeFighter()
        character.startConcentrating(on: "hex")
        let check = character.applyDamage(30)
        // 30 / 2 = 15, above the 10 floor.
        #expect(check?.dc == 15)
    }

    @Test func damageWhileNotConcentratingReturnsNoCheck() {
        var character = makeFighter()
        let check = character.applyDamage(20)
        #expect(check == nil)
        #expect(character.currentHP == max(0, character.maxHP - 20))
    }

    @Test func tempHPAbsorbedFullyDoesNotTriggerSave() {
        // 5e: damage absorbed entirely by temp HP doesn't break concentration.
        var character = makeFighter(maxHP: 20)
        character.tempHP = 10
        character.startConcentrating(on: "hex")
        let check = character.applyDamage(5)
        #expect(check == nil)
        #expect(character.tempHP == 5)
        #expect(character.currentHP == 20)
    }

    @Test func tempHPPartialAbsorbStillTriggersSave() {
        var character = makeFighter(maxHP: 20)
        character.tempHP = 3
        character.startConcentrating(on: "hex")
        let check = character.applyDamage(10)
        // 3 absorbed, 7 went to current HP → DC = max(10, 7/2) = 10.
        #expect(check?.damageTaken == 7)
        #expect(check?.dc == 10)
        #expect(character.tempHP == 0)
        #expect(character.currentHP == 13)
    }

    // MARK: - Action economy

    @Test func featureDefinitionDecodesActionCost() throws {
        let json = """
        {
          "id": "second_wind",
          "name": "Second Wind",
          "description": "...",
          "actionCost": "bonusAction",
          "resource": {
            "id": "fighter_second_wind", "name": "Uses",
            "max": 2, "refreshOn": "shortRest", "refreshAmount": { "fixed": 1 }
          },
          "actionRecipes": [
            { "type": "heal", "dice": "1d10", "addLevel": true, "label": "Second Wind" }
          ]
        }
        """.data(using: .utf8)!
        let feature = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(feature.actionCost == .bonusAction)
    }

    @Test func featureDefinitionDefaultsActionCostToActionWhenTappable() throws {
        let json = """
        {
          "id": "smite",
          "name": "Smite",
          "description": "...",
          "actionRecipes": [
            { "type": "rawDamage", "dice": "2d8", "damageType": "radiant", "label": "Smite" }
          ]
        }
        """.data(using: .utf8)!
        let feature = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(feature.actionCost == .action)
    }

    @Test func featureDefinitionPureWithNoRecipesHasNilCost() throws {
        let json = """
        {
          "id": "fighting_style",
          "name": "Fighting Style",
          "description": "..."
        }
        """.data(using: .utf8)!
        let feature = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(feature.actionCost == nil)
    }

    @Test func itemUseDecodesActionCostWithDefault() throws {
        // No actionCost in JSON → defaults to .action.
        let json = """
        {
          "id": "cast",
          "name": "Cast",
          "cost": { "resourceID": "wand_charges", "amount": 1 },
          "effect": { "type": "castSpell", "spellID": "magic_missile", "atLevel": 1 }
        }
        """.data(using: .utf8)!
        let use = try JSONDecoder().decode(ItemUse.self, from: json)
        #expect(use.actionCost == .action)
    }

    @Test func fighterSecondWindRowCarriesBonusActionCost() {
        let store = ContentStore()
        let character = makeFighter()
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let features = sections.first { $0.id == "features" }
        let secondWind = features?.rows.first { $0.action.label == "Second Wind" }
        #expect(secondWind?.action.actionCost == .bonusAction)
    }

    // MARK: - Concentration save action shape

    @Test func concentrationSaveActionFormsConSave() {
        let character = makeFighter()
        let resolved = ActionInterpreter.resolve(
            recipe: .savingThrow(ability: .constitution),
            character: character,
            weapon: nil
        )
        #expect(resolved.formula != nil)
        // Fighter has CON save proficiency → bonus = +2 (con mod) + 2 (prof).
        #expect(resolved.formula?.modifier == 4)
    }

    // MARK: - Helpers

    private func makeFighter(maxHP: Int = 12) -> Character {
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
            maxHP: maxHP,
            currentHP: maxHP,
            proficiencies: [
                .savingThrow(.strength): .proficient,
                .savingThrow(.constitution): .proficient
            ]
        )
    }
}
