import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct CharacterActionDeriverTests {

    private func makeFighter(equipped: Bool = true) -> Character {
        Character(
            name: "Bruenor",
            level: 1,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [
                .strength: 16,
                .dexterity: 12,
                .constitution: 14,
                .intelligence: 10,
                .wisdom: 13,
                .charisma: 8
            ],
            maxHP: 12,
            proficiencies: [
                .savingThrow(.strength): .proficient,
                .savingThrow(.constitution): .proficient,
                .skill(.athletics): .proficient,
                .skill(.intimidation): .proficient,
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ],
            inventory: [
                InventoryItem(itemID: "longsword", quantity: 1, equipped: equipped, attuned: false)
            ]
        )
    }

    @Test func actionGridOnlyHoldsAttacksAndFeatures() {
        // Ability checks, saves, and skills are surfaced inline on their own
        // cards now — they should NOT appear in the action grid.
        let store = ContentStore()
        let character = makeFighter(equipped: false)
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        let ids = sections.map(\.id)
        #expect(!ids.contains("checks"))
        #expect(!ids.contains("saves"))
        #expect(!ids.contains("skills"))
        // No equipped weapons → no Attacks section.
        #expect(!ids.contains("attacks"))
        // Fighter L1 has Second Wind (heal recipe), so features should remain.
        #expect(ids.contains("features"))
    }

    @Test func equippedWeaponProducesAttackAndDamageRows() {
        let store = ContentStore()
        let character = makeFighter()
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        guard let attacks = sections.first(where: { $0.id == "attacks" }) else {
            Issue.record("Expected an attacks section")
            return
        }

        // Longsword: attack + damage + versatile damage = 3 rows
        #expect(attacks.rows.count == 3)
        let labels = attacks.rows.map(\.action.label)
        #expect(labels.contains("Longsword Attack +5"))
        #expect(labels.contains("Longsword Damage"))
        #expect(labels.contains("Longsword Damage (2H)"))
    }

    @Test func weaponMasteryAppearsAsBadge() {
        let store = ContentStore()
        let character = makeFighter()
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        guard let attacks = sections.first(where: { $0.id == "attacks" }) else {
            Issue.record("Expected an attacks section")
            return
        }
        // Longsword's mastery is "sap" → badge should be "Sap" on every row.
        #expect(attacks.rows.allSatisfy { $0.badge == "Sap" })
    }

    @Test func featureWithRecipeAppearsAsRow() {
        // Fighter level 1 includes "Second Wind" in classes.json with a heal recipe.
        let store = ContentStore()
        let character = makeFighter(equipped: false)
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        guard let features = sections.first(where: { $0.id == "features" }) else {
            Issue.record("Expected a features section")
            return
        }
        let labels = features.rows.map(\.action.label)
        #expect(labels.contains("Second Wind"))
    }
}
