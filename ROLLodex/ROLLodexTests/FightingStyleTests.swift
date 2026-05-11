import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct FightingStyleTests {

    // MARK: - Schema

    @Test func fixedOptionsSelectionSourceRoundTrips() throws {
        let source = SelectionSource.fixedOptions(options: [
            SelectionOption(id: "archery", name: "Archery", description: "+2 ranged attack"),
            SelectionOption(id: "defense", name: "Defense", description: "+1 AC in armor")
        ])
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SelectionSource.self, from: data)
        #expect(decoded == source)
    }

    @Test func bundledFighterFightingStyleExposesFiveOptions() {
        let store = ContentStore()
        let cls = store.classDefinition(id: "fighter")
        let feature = cls?.levelFeatures[1]?.first { $0.id == "fighting_style" }
        #expect(feature?.kind == .selection)
        guard case .fixedOptions(let options)? = feature?.selection?.optionsSource else {
            Issue.record("Expected fixedOptions for Fighting Style")
            return
        }
        // SRD 2024 Fighter Fighting Styles.
        #expect(options.map(\.id).sorted() == [
            "archery", "defense", "dueling", "great_weapon_fighting", "two_weapon_fighting"
        ])
        #expect(feature?.selection?.count.value(classLevel: 1, characterLevel: 1) == 1)
    }

    // MARK: - Defense AC bonus

    @Test func defenseGrantsPlusOneACWhenWearingArmor() {
        let character = makeFighter(style: "defense")
        let bonus = CharacterCalculator.defenseACBonus(character: character, wearingArmor: true)
        #expect(bonus == 1)
    }

    @Test func defenseGrantsNoBonusWithoutArmor() {
        let character = makeFighter(style: "defense")
        let bonus = CharacterCalculator.defenseACBonus(character: character, wearingArmor: false)
        #expect(bonus == 0)
    }

    @Test func defenseGrantsNoBonusForOtherStyles() {
        let character = makeFighter(style: "dueling")
        let bonus = CharacterCalculator.defenseACBonus(character: character, wearingArmor: true)
        #expect(bonus == 0)
    }

    @Test func defenseGrantsNoBonusBeforePicking() {
        let character = makeFighter(style: nil)
        let bonus = CharacterCalculator.defenseACBonus(character: character, wearingArmor: true)
        #expect(bonus == 0)
    }

    // MARK: - Archery attack bonus

    @Test func archeryAddsTwoToRangedAttack() {
        let store = ContentStore()
        let character = makeFighter(style: "archery", equipped: ["shortbow"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "shortbow")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponAttack(abilityOverride: nil, finesse: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        // DEX 14 (+2) + prof (+2) + archery (+2) = +6.
        #expect(resolved.formula?.modifier == 6)
    }

    @Test func archeryDoesNothingToMeleeAttack() {
        let store = ContentStore()
        let character = makeFighter(style: "archery", equipped: ["longsword"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "longsword")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponAttack(abilityOverride: nil, finesse: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        // STR 16 (+3) + prof (+2) = +5; no archery bonus.
        #expect(resolved.formula?.modifier == 5)
    }

    @Test func nonArcheryStyleDoesNotAffectRangedAttack() {
        let store = ContentStore()
        let character = makeFighter(style: "defense", equipped: ["shortbow"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "shortbow")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponAttack(abilityOverride: nil, finesse: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        #expect(resolved.formula?.modifier == 4) // DEX (+2) + prof (+2)
    }

    // MARK: - Dueling damage bonus

    @Test func duelingAddsTwoDamageWhenSingleWieldingMelee() {
        let store = ContentStore()
        let character = makeFighter(style: "dueling", equipped: ["longsword"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "longsword")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponDamage(dieOverride: nil, addAbility: true, versatile: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        // 1d8 + STR (+3) + Dueling (+2) → modifier 5.
        #expect(resolved.formula?.modifier == 5)
    }

    @Test func duelingDoesNotApplyWithTwoWeapons() {
        let store = ContentStore()
        let character = makeFighter(style: "dueling", equipped: ["longsword", "dagger"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        #expect(fs.onlyOneWeaponEquipped == false)
        let weapon = store.weaponDefinition(id: "longsword")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponDamage(dieOverride: nil, addAbility: true, versatile: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        #expect(resolved.formula?.modifier == 3) // STR only
    }

    @Test func duelingDoesNotApplyToVersatileTwoHandedSwing() {
        let store = ContentStore()
        let character = makeFighter(style: "dueling", equipped: ["longsword"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "longsword")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponDamage(dieOverride: nil, addAbility: true, versatile: true),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        // 1d10 (versatile) + STR (+3); no Dueling bonus because we're 2-handing.
        #expect(resolved.formula?.modifier == 3)
    }

    @Test func duelingDoesNotApplyToRangedWeapon() {
        let store = ContentStore()
        let character = makeFighter(style: "dueling", equipped: ["shortbow"])
        let fs = CharacterCalculator.fightingStyleEffects(character: character, content: store)
        let weapon = store.weaponDefinition(id: "shortbow")!
        let resolved = ActionInterpreter.resolve(
            recipe: .weaponDamage(dieOverride: nil, addAbility: true, versatile: false),
            character: character,
            weapon: weapon,
            fightingStyle: fs
        )
        #expect(resolved.formula?.modifier == 2) // DEX (+2), no Dueling
    }

    // MARK: - Helpers

    private func makeFighter(
        style: String?,
        equipped: [String] = ["longsword"]
    ) -> Character {
        var selections: [String: [String]] = [:]
        if let style { selections["fighting_style"] = [style] }
        return Character(
            name: "Bruenor", level: 1,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 1)],
            abilityScores: [
                .strength: 16, .dexterity: 14, .constitution: 14,
                .intelligence: 10, .wisdom: 13, .charisma: 8
            ],
            maxHP: 12,
            proficiencies: [
                .weapon(.simple): .proficient,
                .weapon(.martial): .proficient
            ],
            inventory: equipped.map { id in
                InventoryItem(itemID: id, quantity: 1, equipped: true, attuned: false)
            },
            featureSelections: selections
        )
    }
}
