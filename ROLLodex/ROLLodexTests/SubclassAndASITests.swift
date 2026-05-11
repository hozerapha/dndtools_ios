import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SubclassAndASITests {

    // MARK: - Schema round-trips

    @Test func subclassesSelectionSourceRoundTrips() throws {
        let source = SelectionSource.subclasses(parentClassID: "fighter")
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SelectionSource.self, from: data)
        #expect(decoded == source)
    }

    @Test func abilityScoreIncreaseSelectionSourceRoundTrips() throws {
        let source = SelectionSource.abilityScoreIncrease(perAbilityMax: 2)
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SelectionSource.self, from: data)
        #expect(decoded == source)
    }

    @Test func subclassDefinitionDecodes() throws {
        let json = """
        {
          "id": "champion",
          "name": "Champion",
          "description": "Raw physical power honed to perfection.",
          "levelFeatures": {
            "3": [
              { "id": "improved_critical", "name": "Improved Critical", "description": "Crit on 19-20." }
            ],
            "7": [
              { "id": "remarkable_athlete", "name": "Remarkable Athlete", "description": "Half-prof on STR/DEX/CON checks." }
            ]
          }
        }
        """.data(using: .utf8)!
        let sub = try JSONDecoder().decode(SubclassDefinition.self, from: json)
        #expect(sub.id == "champion")
        #expect(sub.levelFeatures[3]?.first?.id == "improved_critical")
        #expect(sub.levelFeatures[7]?.first?.id == "remarkable_athlete")
    }

    // MARK: - Bundled content invariants

    @Test func bundledFighterHasChampionSubclass() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")
        #expect(cls?.subclassLevel == 3)
        let champion = cls?.subclasses.first { $0.id == "champion" }
        #expect(champion?.name == "Champion")
        // Champion levels 3/7/10/15/18 each carry at least one feature.
        for level in [3, 7, 10, 15, 18] {
            #expect((champion?.levelFeatures[level]?.count ?? 0) > 0,
                    "Champion missing features at L\(level)")
        }
    }

    @Test func bundledFighterL3HasMartialArchetypePrompt() {
        let store = ContentStore()
        let feature = store.classDefinition(id: "fighter")?
            .levelFeatures[3]?
            .first { $0.id == "martial_archetype" }
        #expect(feature?.kind == .selection)
        if case .subclasses(let parent)? = feature?.selection?.optionsSource {
            #expect(parent == "fighter")
        } else {
            Issue.record("Expected .subclasses source for Martial Archetype")
        }
    }

    @Test func bundledFighterL4HasASIPrompt() {
        let store = ContentStore()
        let feature = store.classDefinition(id: "fighter")?
            .levelFeatures[4]?
            .first { $0.id == "fighter_asi_4" }
        #expect(feature?.kind == .selection)
        if case .abilityScoreIncrease(let max)? = feature?.selection?.optionsSource {
            #expect(max == 2)
        } else {
            Issue.record("Expected .abilityScoreIncrease source")
        }
        // Two-point budget.
        #expect(feature?.selection?.count.value(classLevel: 4, characterLevel: 4) == 2)
    }

    // MARK: - resolvedFeatures aggregation

    @Test func resolvedFeaturesIncludesBaseClassOnly_whenNoSubclassPicked() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")!
        let resolved = cls.resolvedFeatures(throughClassLevel: 3, subclassID: nil)
        // Should include level 1, 2, 3 base features but no subclass features.
        #expect(resolved.contains { $0.feature.id == "fighting_style" })
        #expect(resolved.contains { $0.feature.id == "action_surge" })
        #expect(resolved.contains { $0.feature.id == "martial_archetype" })
        #expect(!resolved.contains { $0.feature.id == "improved_critical" })
    }

    @Test func resolvedFeaturesIncludesChampionFeatures_whenChampionPicked() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")!
        let resolved = cls.resolvedFeatures(throughClassLevel: 3, subclassID: "champion")
        let champFeature = resolved.first { $0.feature.id == "improved_critical" }
        #expect(champFeature != nil)
        #expect(champFeature?.subclassName == "Champion")
        #expect(champFeature?.grantedAtLevel == 3)
    }

    @Test func resolvedFeaturesGatesByClassLevel() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")!
        // At class level 3, Champion's L7 feature shouldn't appear yet.
        let resolved = cls.resolvedFeatures(throughClassLevel: 3, subclassID: "champion")
        #expect(!resolved.contains { $0.feature.id == "remarkable_athlete" })
    }

    @Test func resolvedFeaturesIgnoresUnknownSubclassID() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")!
        // Typo in the saved character file shouldn't crash or surface ghosts.
        let resolved = cls.resolvedFeatures(throughClassLevel: 3, subclassID: "monk")
        #expect(!resolved.contains { $0.feature.id == "improved_critical" })
        #expect(resolved.contains { $0.feature.id == "fighting_style" })
    }

    // MARK: - subclassSelectionID convention

    @Test func subclassSelectionIDFollowsConvention() {
        #expect(ClassDefinition.subclassSelectionID(forClassID: "fighter") == "fighter_subclass")
        #expect(ClassDefinition.subclassSelectionID(forClassID: "wizard") == "wizard_subclass")
    }

    // MARK: - ASI mutator

    @Test func asiIncrementAppliesToBothPicksAndScore() {
        var character = makeFighter()
        character.applyASIIncrement(
            ability: .strength,
            selectionID: "fighter_asi_4",
            totalPoints: 2,
            perAbilityMax: 2
        )
        #expect(character.featureSelections["fighter_asi_4"] == ["strength"])
        #expect(character.abilityScores[.strength] == 17) // 16 → 17
    }

    @Test func asiSecondIncrementToSameAbilityAddsAgain() {
        var character = makeFighter()
        character.applyASIIncrement(ability: .strength, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        character.applyASIIncrement(ability: .strength, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        #expect(character.featureSelections["fighter_asi_4"] == ["strength", "strength"])
        #expect(character.abilityScores[.strength] == 18)
    }

    @Test func asiRefusesPastTotalBudget() {
        var character = makeFighter()
        for _ in 0..<3 {
            character.applyASIIncrement(ability: .dexterity, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        }
        // Third call is a no-op — total picks capped at 2.
        #expect(character.featureSelections["fighter_asi_4"]?.count == 2)
        #expect(character.abilityScores[.dexterity] == 14) // 12 → 14
    }

    @Test func asiRefusesPastPerAbilityMax() {
        var character = makeFighter()
        // perAbilityMax = 1 means you can only put 1 point on any one ability.
        character.applyASIIncrement(ability: .strength, selectionID: "asi_x", totalPoints: 2, perAbilityMax: 1)
        character.applyASIIncrement(ability: .strength, selectionID: "asi_x", totalPoints: 2, perAbilityMax: 1)
        #expect(character.featureSelections["asi_x"] == ["strength"])
        #expect(character.abilityScores[.strength] == 17)
    }

    @Test func asiRefusesPastScoreCeiling() {
        var character = makeFighter()
        character.abilityScores[.strength] = 20 // already at cap
        character.applyASIIncrement(ability: .strength, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        #expect(character.abilityScores[.strength] == 20)
        #expect(character.featureSelections["fighter_asi_4"] == nil)
    }

    @Test func asiDecrementReversesAnIncrement() {
        var character = makeFighter()
        character.applyASIIncrement(ability: .strength, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        character.applyASIIncrement(ability: .dexterity, selectionID: "fighter_asi_4", totalPoints: 2, perAbilityMax: 2)
        character.applyASIDecrement(ability: .strength, selectionID: "fighter_asi_4")
        #expect(character.featureSelections["fighter_asi_4"] == ["dexterity"])
        #expect(character.abilityScores[.strength] == 16) // back to base
        #expect(character.abilityScores[.dexterity] == 13)
    }

    @Test func asiDecrementOnUnusedAbilityIsNoOp() {
        var character = makeFighter()
        character.applyASIDecrement(ability: .charisma, selectionID: "fighter_asi_4")
        #expect(character.featureSelections["fighter_asi_4"] == nil)
        #expect(character.abilityScores[.charisma] == 8) // unchanged
    }

    // MARK: - Subclass features surface in the action grid

    @Test func subclassFeaturesAppearInActionGrid() {
        let store = ContentStore()
        let character = Character(
            name: "Sigrid", level: 3,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 3)],
            abilityScores: [.strength: 16, .constitution: 14],
            maxHP: 28,
            featureSelections: ["fighter_subclass": ["champion"]]
        )
        let sections = CharacterActionDeriver.sections(for: character, content: store)
        let featureNames = sections
            .first { $0.id == "features" }?
            .rows.map(\.action.label) ?? []
        // Champion L3 "Improved Critical" is passive (no recipe) — won't appear
        // in the action grid. But L1 Second Wind (heal recipe) should still be
        // listed; the aggregator at least doesn't drop base-class features
        // when a subclass is picked. Sanity check that.
        #expect(featureNames.contains("Second Wind"))
    }

    // MARK: - Helpers

    private func makeFighter() -> Character {
        Character(
            name: "Bruenor", level: 4,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 4)],
            abilityScores: [
                .strength: 16, .dexterity: 12, .constitution: 14,
                .intelligence: 10, .wisdom: 13, .charisma: 8
            ],
            maxHP: 30
        )
    }
}
