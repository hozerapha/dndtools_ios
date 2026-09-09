import Testing
import Foundation
@testable import ROLLodex

/// Coverage gap: `CharacterCalculator.masteryMechanic` — generates
/// character-specific mechanic text for each of the 8 weapon mastery
/// properties. The slot-count and active-mastery helpers are covered; this
/// pins the text generation so a typo or stat-reference swap is caught.
struct WeaponMasteryMechanicTests {

    private func makeFighter(str: Int = 16, dex: Int = 10, level: Int = 5) -> Character {
        Character(
            name: "Fighter",
            level: level,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: level)],
            abilityScores: [.strength: str, .dexterity: dex],
            maxHP: 10
        )
    }

    private func longsword() -> WeaponDefinition {
        WeaponDefinition(
            id: "longsword",
            name: "Longsword",
            description: "",
            cost: 1500,
            weight: 3,
            weaponCategory: .martial,
            damage: "1d8",
            damageType: .slashing,
            damageAbility: nil,
            properties: [.versatile],
            versatileDamage: "1d10"
        )
    }

    private func dagger() -> WeaponDefinition {
        WeaponDefinition(
            id: "dagger",
            name: "Dagger",
            description: "",
            cost: 200,
            weight: 1,
            weaponCategory: .simple,
            damage: "1d4",
            damageType: .piercing,
            damageAbility: nil,
            properties: [.finesse, .light]
        )
    }

    private func shortbow() -> WeaponDefinition {
        WeaponDefinition(
            id: "shortbow",
            name: "Shortbow",
            description: "",
            cost: 2500,
            weight: 2,
            weaponCategory: .simple,
            damage: "1d6",
            damageType: .piercing,
            damageAbility: .dexterity,
            properties: [.ammunition]
        )
    }

    // MARK: - Vex

    @Test func vexMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .vex, character: char
        )
        #expect(text.contains("Advantage"))
        #expect(text.contains("next attack"))
    }

    // MARK: - Graze

    @Test func grazeMechanicShowsAbilityModDamage() {
        let char = makeFighter(str: 16)  // STR 16 → +3
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .graze, character: char
        )
        #expect(text.contains("3"))
        #expect(text.contains("slashing"))
    }

    @Test func grazeMechanicShowsZeroForNegativeMod() {
        let char = makeFighter(str: 8)  // STR 8 → -1
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .graze, character: char
        )
        // Negative damage is clamped to 0 (max(0, -1) = 0)
        #expect(text.contains("0"))
    }

    @Test func grazeMechanicUsesDexForFinesseWeapon() {
        let char = makeFighter(str: 10, dex: 18)  // DEX 18 → +4, STR 10 → 0
        let weapon = dagger()  // finesse
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .graze, character: char
        )
        #expect(text.contains("4"))
        #expect(text.contains("piercing"))
    }

    @Test func grazeMechanicUsesDexForRangedWeapon() {
        let char = makeFighter(str: 16, dex: 14)  // DEX 14 → +2
        let weapon = shortbow()  // damageAbility: dexterity
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .graze, character: char
        )
        #expect(text.contains("2"))
        #expect(text.contains("piercing"))
    }

    // MARK: - Topple

    @Test func toppleMechanicShowsCalculatedSaveDC() {
        let char = makeFighter(str: 16, level: 5)  // +3 STR, +3 PB → DC 14
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .topple, character: char
        )
        #expect(text.contains("DC 14"))
        #expect(text.contains("Constitution"))
    }

    @Test func toppleMechanicReflectsAbilityChange() {
        let char = makeFighter(str: 20, level: 9)  // +5 STR, +4 PB → DC 17
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .topple, character: char
        )
        #expect(text.contains("DC 17"))
    }

    @Test func toppleMechanicUsesDexForFinesseWeapon() {
        let char = makeFighter(str: 10, dex: 18, level: 5)  // +4 DEX, +3 PB → DC 15
        let weapon = dagger()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .topple, character: char
        )
        #expect(text.contains("DC 15"))
    }

    // MARK: - Sap

    @Test func sapMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .sap, character: char
        )
        #expect(text.contains("Disadvantage"))
        #expect(text.contains("next attack"))
    }

    // MARK: - Slow

    @Test func slowMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .slow, character: char
        )
        #expect(text.contains("Speed"))
        #expect(text.contains("−10"))
    }

    // MARK: - Push

    @Test func pushMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .push, character: char
        )
        #expect(text.contains("10 ft"))
        #expect(text.contains("Large"))
    }

    // MARK: - Nick

    @Test func nickMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .nick, character: char
        )
        #expect(text.contains("Light"))
        #expect(text.contains("Attack action"))
    }

    // MARK: - Cleave

    @Test func cleaveMechanicIsDescriptive() {
        let char = makeFighter()
        let weapon = longsword()
        let text = CharacterCalculator.masteryMechanic(
            weapon: weapon, mastery: .cleave, character: char
        )
        #expect(text.contains("5 ft"))
        #expect(text.contains("no ability mod"))
    }
}
