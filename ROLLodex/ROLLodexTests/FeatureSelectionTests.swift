import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct FeatureSelectionTests {

    // MARK: - Schema round-trips

    @Test func featureSelectionDecodesWeaponSource() throws {
        let json = """
        {
          "id": "weapon_mastery",
          "prompt": "Choose 3 weapons",
          "count": 3,
          "optionsSource": { "type": "weapons", "proficientOnly": true }
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(FeatureSelection.self, from: json)
        #expect(s.id == "weapon_mastery")
        #expect(s.count == .flat(3))
        if case .weapons(let prof) = s.optionsSource {
            #expect(prof == true)
        } else {
            Issue.record("Expected .weapons source")
        }
    }

    @Test func featureSelectionRoundTrips() throws {
        let s = FeatureSelection(
            id: "weapon_mastery",
            prompt: "Choose",
            count: .byClassLevel([1: 3, 4: 4]),
            optionsSource: .weapons(proficientOnly: true)
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(FeatureSelection.self, from: data)
        #expect(decoded == s)
    }

    @Test func featureDefinitionDecodesKindAndSelection() throws {
        let json = """
        {
          "id": "weapon_mastery",
          "name": "Weapon Mastery",
          "description": "...",
          "kind": "selection",
          "selection": {
            "id": "weapon_mastery",
            "prompt": "Choose 3 weapons",
            "count": 3,
            "optionsSource": { "type": "weapons", "proficientOnly": true }
          }
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.kind == .selection)
        #expect(f.selection?.id == "weapon_mastery")
    }

    @Test func featureDefinitionInfersKindFromShape() throws {
        // A feature with a resource block but no `kind` should auto-infer `.active`.
        let json = """
        {
          "id": "second_wind",
          "name": "Second Wind",
          "description": "...",
          "resource": {
            "id": "fighter_second_wind",
            "name": "Uses",
            "max": 2,
            "refreshOn": "shortRest",
            "refreshAmount": { "fixed": 1 }
          }
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.kind == .active)
    }

    @Test func featureDefinitionDefaultsToPassive() throws {
        let json = """
        {
          "id": "fighting_style",
          "name": "Fighting Style",
          "description": "..."
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.kind == .passive)
        #expect(f.selection == nil)
    }

    // MARK: - Character migration

    @Test func characterMigratesLegacyChosenWeaponMasteries() throws {
        let id = UUID().uuidString
        let json = """
        {
          "id": "\(id)",
          "name": "Bruenor",
          "level": 1,
          "speciesID": "human",
          "backgroundID": "soldier",
          "classEntries": [{ "classID": "fighter", "level": 1 }],
          "abilityScores": { "strength": 16, "dexterity": 12, "constitution": 14, "intelligence": 10, "wisdom": 13, "charisma": 8 },
          "maxHP": 12,
          "currentHP": 12,
          "tempHP": 0,
          "proficiencies": {},
          "inventory": [],
          "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 0, "pp": 0 },
          "notes": "",
          "chosenWeaponMasteries": ["longsword", "shortbow"],
          "manifestVersion": 1
        }
        """.data(using: .utf8)!
        let character = try JSONDecoder().decode(Character.self, from: json)
        #expect(character.featureSelections["weapon_mastery"] == ["longsword", "shortbow"])
    }

    @Test func characterDecodesWithNeitherLegacyNorNew() throws {
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
        #expect(character.featureSelections.isEmpty)
    }

    // MARK: - Live data wiring

    @Test func fighterL1FeaturesIncludeWeaponMasterySelection() {
        // The bundled classes.json should declare the Weapon Mastery feature
        // with a selection block. If this fails, the data has drifted from
        // the player-facing UI.
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")
        let mastery = cls?.levelFeatures[1]?.first { $0.id == "weapon_mastery" }
        #expect(mastery?.kind == .selection)
        #expect(mastery?.selection?.id == "weapon_mastery")
        // Fighter starts with 3 picks at L1.
        let count = mastery?.selection?.count.value(classLevel: 1, characterLevel: 1)
        #expect(count == 3)
    }

    @Test func masterySlotCountReadsFromFeatureNotMasteryCountField() {
        // Even though classes.json still has the legacy `masteryCount: 3` on
        // the fighter, the slot count should come from the feature's
        // selection block — confirming the calculator's source switch.
        let store = ContentStore()
        let fighter = Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [.strength: 16], maxHP: 10
        )
        #expect(CharacterCalculator.weaponMasterySlotCount(character: fighter, content: store) == 3)
    }
}
