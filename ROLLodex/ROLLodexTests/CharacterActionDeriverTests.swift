import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct CharacterActionDeriverTests {

    private func makeFighter(
        equipped: Bool = true,
        masteringLongsword: Bool = true
    ) -> Character {
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
            ],
            featureSelections: masteringLongsword ? ["weapon_mastery": ["longsword"]] : [:]
        )
    }

    @Test func actionGridOmitsAttacksAndInlineRolls() {
        // Ability checks, saves, skills are surfaced inline on their own cards.
        // Weapon attacks now have a bespoke `weaponAttacks(...)` API rather
        // than living in `sections(...)`. The grid should hold only features
        // and item uses.
        let store = ContentStore()
        let character = makeFighter(equipped: false)
        let sections = CharacterActionDeriver.sections(for: character, content: store)

        let ids = sections.map(\.id)
        #expect(!ids.contains("checks"))
        #expect(!ids.contains("saves"))
        #expect(!ids.contains("skills"))
        #expect(!ids.contains("attacks"))
        // Fighter L1 has Second Wind (heal recipe), so features should remain.
        #expect(ids.contains("features"))
    }

    @Test func equippedWeaponProducesAttackDamageAndVersatileRows() {
        let store = ContentStore()
        let character = makeFighter()
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)

        #expect(rows.count == 1)
        let row = rows.first
        #expect(row?.weaponName == "Longsword")
        #expect(row?.attack.label == "Longsword Attack +5")
        #expect(row?.damage.label == "Longsword Damage")
        #expect(row?.versatileDamage?.label == "Longsword Damage (2H)")
    }

    @Test func unequippedWeaponProducesNoAttackRow() {
        let store = ContentStore()
        let character = makeFighter(equipped: false)
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)
        #expect(rows.isEmpty)
    }

    @Test func weaponAttackRowCarriesMasteryWhenChosen() {
        let store = ContentStore()
        let character = makeFighter(masteringLongsword: true)
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)
        // Longsword's mastery property is `.sap`. Fighter selected it → shown.
        #expect(rows.first?.mastery == .sap)
    }

    @Test func weaponAttackRowOmitsMasteryWhenNotChosen() {
        let store = ContentStore()
        let character = makeFighter(masteringLongsword: false)
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)
        // Fighter has the Weapon Mastery feature but hasn't picked the
        // longsword — badge shouldn't display.
        #expect(rows.first?.mastery == nil)
    }

    @Test func weaponAttackRowOmitsMasteryForCharacterWithoutFeature() {
        // Wizard has no Weapon Mastery feature in JSON, so even putting the
        // longsword into featureSelections shouldn't surface the badge.
        let store = ContentStore()
        let character = Character(
            name: "Mordenkainen", level: 1,
            speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "wizard", level: 1)],
            abilityScores: [
                .strength: 8, .dexterity: 14, .constitution: 14,
                .intelligence: 16, .wisdom: 12, .charisma: 10
            ],
            maxHP: 6,
            inventory: [InventoryItem(itemID: "longsword", quantity: 1, equipped: true)],
            featureSelections: ["weapon_mastery": ["longsword"]]
        )
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)
        #expect(rows.first?.mastery == nil)
    }

    @Test func weaponRowCarriesResolvedMasteryMechanic() {
        let store = ContentStore()
        let character = makeFighter(masteringLongsword: true)
        let rows = CharacterActionDeriver.weaponAttacks(for: character, content: store)
        // Longsword → Sap: target has disadvantage on its next attack.
        #expect(rows.first?.masteryMechanic?.contains("Disadvantage") == true)
    }

    @Test func grazeMechanicFillsInAbilityModDamage() {
        let store = ContentStore()
        let weapon = store.weaponDefinition(id: "greatsword")! // graze, slashing
        let character = makeFighter()                          // STR 16 → +3
        let text = CharacterCalculator.masteryMechanic(weapon: weapon, mastery: .graze, character: character)
        #expect(text.contains("3 slashing"))
    }

    @Test func toppleMechanicComputesSaveDC() {
        let store = ContentStore()
        let weapon = store.weaponDefinition(id: "quarterstaff")! // topple
        let character = makeFighter()  // STR 16 (+3), L1 PB +2 → DC 13
        let text = CharacterCalculator.masteryMechanic(weapon: weapon, mastery: .topple, character: character)
        #expect(text.contains("DC 13"))
        #expect(text.contains("Constitution"))
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
