import Foundation

enum CharacterCalculator {
    static func abilityModifier(score: Int) -> Int {
        (score - 10) / 2
    }

    static func proficiencyBonus(level: Int) -> Int {
        (level - 1) / 4 + 2
    }

    static func skillModifier(
        character: Character,
        skill: Skill
    ) -> Int {
        let ability = skill.ability
        let score = character.abilityScores[ability] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profLevel = character.proficiencies[.skill(skill)] ?? .none
        let profBonus = proficiencyBonus(level: character.level)

        switch profLevel {
        case .none:
            return abilityMod
        case .proficient:
            return abilityMod + profBonus
        case .expertise:
            return abilityMod + (profBonus * 2)
        }
    }

    static func saveBonus(
        character: Character,
        ability: Ability
    ) -> Int {
        let score = character.abilityScores[ability] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profLevel = character.proficiencies[.savingThrow(ability)] ?? .none
        let profBonus = proficiencyBonus(level: character.level)

        switch profLevel {
        case .none:
            return abilityMod
        case .proficient, .expertise:
            return abilityMod + profBonus
        }
    }

    static func armorClass(
        dexMod: Int,
        armor: ArmorDefinition?,
        hasShield: Bool
    ) -> Int {
        let base: Int
        if let armor = armor {
            let dexContribution: Int
            if let cap = armor.dexCap {
                dexContribution = min(dexMod, cap)
            } else {
                dexContribution = dexMod // No cap = full Dex mod (light armor)
            }
            base = armor.acBase + dexContribution
        } else {
            base = 10 + dexMod
        }

        let shieldBonus = hasShield ? 2 : 0
        return base + shieldBonus
    }

    static func initiativeBonus(character: Character) -> Int {
        let dexScore = character.abilityScores[.dexterity] ?? 10
        return abilityModifier(score: dexScore)
    }

    static func passivePerception(character: Character) -> Int {
        10 + skillModifier(character: character, skill: .perception)
    }

    static func spellSaveDC(
        character: Character,
        spellcastingAbility: Ability
    ) -> Int {
        let score = character.abilityScores[spellcastingAbility] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profBonus = proficiencyBonus(level: character.level)
        return 8 + abilityMod + profBonus
    }

    static func spellAttackBonus(
        character: Character,
        spellcastingAbility: Ability
    ) -> Int {
        let score = character.abilityScores[spellcastingAbility] ?? 10
        let abilityMod = abilityModifier(score: score)
        let profBonus = proficiencyBonus(level: character.level)
        return abilityMod + profBonus
    }
}
