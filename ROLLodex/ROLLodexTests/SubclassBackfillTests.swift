import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct SubclassBackfillTests {

    // MARK: - Fixtures

    private func makeCharacter(
        classID: String, level: Int, subclassID: String? = nil,
        equipped: [String] = []
    ) -> Character {
        var selections: [String: [String]] = [:]
        if let subclassID {
            selections[ClassDefinition.subclassSelectionID(forClassID: classID)] = [subclassID]
        }
        return Character(
            name: "Backfill", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: classID, level: level)],
            abilityScores: [
                .strength: 16, .dexterity: 12, .constitution: 14,
                .intelligence: 14, .wisdom: 10, .charisma: 16
            ],
            maxHP: 30,
            proficiencies: [.weapon(.simple): .proficient, .weapon(.martial): .proficient],
            inventory: equipped.map { InventoryItem(itemID: $0, quantity: 1, equipped: true) },
            featureSelections: selections
        )
    }

    // MARK: - Wiring: every class now has a subclass

    @Test func allTenClassesHaveASubclassAndPicker() {
        let store = ContentStore()
        for cls in store.allClasses {
            #expect(!cls.subclasses.isEmpty, "\(cls.id) has no subclass")
            #expect(cls.subclassLevel != nil, "\(cls.id) has no subclassLevel")
            // The unlock level's features include a subclass picker.
            let unlock = cls.subclassLevel ?? 0
            let hasPicker = (cls.levelFeatures[unlock] ?? []).contains { feature in
                if case .subclasses? = feature.selection?.optionsSource { return true }
                return false
            }
            #expect(hasPicker, "\(cls.id) missing subclass picker at L\(unlock)")
        }
    }

    @Test func backfilledSubclassesLoad() {
        let store = ContentStore()
        #expect(store.classDefinition(id: "barbarian")?.subclasses.first?.id == "path_of_the_berserker")
        #expect(store.classDefinition(id: "paladin")?.subclasses.first?.id == "oath_of_devotion")
        #expect(store.classDefinition(id: "wizard")?.subclasses.first?.id == "evoker")
    }

    // MARK: - Berserker: Frenzy rider

    @Test func frenzyRiderAppearsForRagingBerserker() {
        let store = ContentStore()
        let berserker = makeCharacter(
            classID: "barbarian", level: 3,
            subclassID: "path_of_the_berserker", equipped: ["longsword"]
        )
        let weapon = store.weaponDefinition(id: "longsword")!
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: weapon, character: berserker, content: store
        )
        let frenzy = riders.first { $0.label == "Frenzy" }
        #expect(frenzy != nil)
        // 2d6 at L3, matching the weapon's damage type.
        #expect(frenzy?.formula.groups.first?.count == 2)
        #expect(frenzy?.formula.groups.first?.kind == .d6)
        #expect(frenzy?.formula.groups.first?.damageType == weapon.damageType)
    }

    @Test func frenzyScalesAtLevelNine() {
        let store = ContentStore()
        let berserker = makeCharacter(
            classID: "barbarian", level: 9,
            subclassID: "path_of_the_berserker", equipped: ["longsword"]
        )
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: store.weaponDefinition(id: "longsword"), character: berserker, content: store
        )
        #expect(riders.first { $0.label == "Frenzy" }?.formula.groups.first?.count == 3)
    }

    @Test func frenzyIsOncePerTurn() {
        let store = ContentStore()
        var berserker = makeCharacter(
            classID: "barbarian", level: 3,
            subclassID: "path_of_the_berserker", equipped: ["longsword"]
        )
        berserker.setTurnFlag("frenzy")
        let riders = TriggeredEffectResolver.optInRiders(
            weapon: store.weaponDefinition(id: "longsword"), character: berserker, content: store
        )
        #expect(!riders.contains { $0.label == "Frenzy" })
        berserker.startNewTurn()
        let after = TriggeredEffectResolver.optInRiders(
            weapon: store.weaponDefinition(id: "longsword"), character: berserker, content: store
        )
        #expect(after.contains { $0.label == "Frenzy" })
    }

    // MARK: - Devotion: oath spells + resources

    @Test func devotionGrantsShieldOfFaith() {
        let store = ContentStore()
        let paladin = makeCharacter(classID: "paladin", level: 3, subclassID: "oath_of_devotion")
        let granted = CharacterSpellGrants.resolve(character: paladin, content: store)
        #expect(granted.contains { $0.spell.id == "shield_of_faith" })
        // Not granted without the oath.
        let oathless = makeCharacter(classID: "paladin", level: 3)
        #expect(!CharacterSpellGrants.resolve(character: oathless, content: store)
            .contains { $0.spell.id == "shield_of_faith" })
    }

    @Test func holyNimbusAndIntimidatingPresenceResourcesResolve() {
        let store = ContentStore()
        let paladin = makeCharacter(classID: "paladin", level: 20, subclassID: "oath_of_devotion")
        let paladinResources = ResourceCalculator.availableResources(character: paladin, content: store)
        #expect(paladinResources.first { $0.definition.id == "paladin_holy_nimbus" }?.max == 1)

        let berserker = makeCharacter(
            classID: "barbarian", level: 14, subclassID: "path_of_the_berserker"
        )
        let barbResources = ResourceCalculator.availableResources(character: berserker, content: store)
        #expect(barbResources.first { $0.definition.id == "barbarian_intimidating_presence" }?.max == 1)
    }

    // MARK: - Evoker

    @Test func evokerFeaturesResolveThroughLevels() {
        let store = ContentStore()
        let wizard = store.classDefinition(id: "wizard")!
        let features = wizard.resolvedFeatures(throughClassLevel: 14, subclassID: "evoker")
        let ids = features.map(\.feature.id)
        #expect(ids.contains("evocation_savant"))
        #expect(ids.contains("potent_cantrip"))
        #expect(ids.contains("sculpt_spells"))
        #expect(ids.contains("empowered_evocation"))
        #expect(ids.contains("overchannel"))
    }
}
