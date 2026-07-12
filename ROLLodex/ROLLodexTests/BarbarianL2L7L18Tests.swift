import Testing
import Foundation
@testable import ROLLodex

/// Covers the Barbarian L2 / L7 / L18 mechanical wire-ups shipped 2026-07-11:
/// Reckless Attack (opt-in Advantage on weapon attacks via a whileActive
/// TriggeredEffect), Feral Instinct (Bool → Initiative Advantage flag),
/// Indomitable Might (AbilityCheckFloor → pre-flooring the d20 on STR
/// checks and saves).
@MainActor
struct BarbarianL2L7L18Tests {

    // MARK: - Schema round-trips

    @Test func recklessAttackTriggerEffectRoundTrips() throws {
        let original = TriggerEffect.recklessAttack
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TriggerEffect.self, from: data)
        #expect(decoded == original)
    }

    @Test func abilityCheckFloorRoundTrips() throws {
        let original = AbilityCheckFloor(ability: .strength, floorFromAbilityScore: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AbilityCheckFloor.self, from: data)
        #expect(decoded == original)
    }

    @Test func featureDefinitionDecodesInitiativeAdvantageDefaultFalse() throws {
        // Missing key = false, matching the memory that legacy content decodes
        // without breakage.
        let json = """
        {
          "id": "no_init_adv",
          "name": "Not Feral Instinct",
          "description": "Nothing to see here."
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.initiativeAdvantage == false)
        #expect(f.abilityCheckFloor == nil)
    }

    @Test func featureDefinitionDecodesInitiativeAdvantageTrueFromJSON() throws {
        // Mirrors the actual feral_instinct blob shipped in classes.json.
        let json = """
        {
          "id": "feral_instinct",
          "name": "Feral Instinct",
          "description": "You have Advantage on Initiative rolls.",
          "kind": "passive",
          "initiativeAdvantage": true
        }
        """.data(using: .utf8)!
        let f = try JSONDecoder().decode(FeatureDefinition.self, from: json)
        #expect(f.initiativeAdvantage == true, "explicit true in JSON should decode to true")
    }

    // MARK: - Content shape (Barbarian JSON wired end-to-end)

    @Test func barbarianRecklessAttackJSONWiresToggleTrigger() {
        let content = ContentStore()
        let cls = content.classDefinition(id: "barbarian")!
        let features = cls.levelFeatures[2] ?? []
        let ra = features.first { $0.id == "reckless_attack" }!
        #expect(ra.triggeredEffect != nil)
        #expect(ra.triggeredEffect?.effect == .recklessAttack)
        #expect(ra.triggeredEffect?.activation == .toggle)
    }

    @Test func barbarianFeralInstinctJSONWiresInitiativeAdvantage() {
        let content = ContentStore()
        let allClassIDs = content.allClasses.map(\.id).sorted()
        let barbCount = content.allClasses.filter { $0.id == "barbarian" }.count
        #expect(barbCount == 1,
                "barbarian not loaded — content has classes: \(allClassIDs), loadErrors: \(content.loadErrors)")
        guard let cls = content.classDefinition(id: "barbarian") else {
            #expect(Bool(false), "abort: no barbarian")
            return
        }
        let l7 = cls.levelFeatures[7] ?? []
        let fi = l7.first { $0.id == "feral_instinct" }
        #expect(fi?.initiativeAdvantage == true,
                "feral_instinct.initiativeAdvantage was \(fi?.initiativeAdvantage ?? false)")
    }

    @Test func barbarianIndomitableMightJSONWiresSTRFloor() {
        let content = ContentStore()
        let cls = content.classDefinition(id: "barbarian")!
        let features = cls.levelFeatures[18] ?? []
        let im = features.first { $0.id == "indomitable_might" }!
        let floor = im.abilityCheckFloor
        #expect(floor?.ability == .strength)
        #expect(floor?.floorFromAbilityScore == true)
    }

    // MARK: - Feral Instinct: initiative-advantage query

    @Test func hasInitiativeAdvantageFalseBeforeL7() {
        let content = ContentStore()
        var pc = Self.makeBarbarian(level: 6)
        #expect(!CharacterCalculator.hasInitiativeAdvantage(character: pc, content: content))
        pc = Self.makeBarbarian(level: 7)
        #expect(CharacterCalculator.hasInitiativeAdvantage(character: pc, content: content))
    }

    @Test func hasInitiativeAdvantageFalseForNonBarbarian() {
        let content = ContentStore()
        // Fighter L20 — should not have Feral Instinct.
        let pc = Self.makeFighter(level: 20)
        #expect(!CharacterCalculator.hasInitiativeAdvantage(character: pc, content: content))
    }

    // MARK: - Indomitable Might: ability-check-floor query + interpreter

    @Test func abilityCheckFloorNilBeforeL18() {
        let content = ContentStore()
        let pc = Self.makeBarbarian(level: 17)
        #expect(CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength) == nil)
    }

    @Test func abilityCheckFloorAtL18ScalesWithSTR() {
        let content = ContentStore()
        // STR 20 → mod +5 → d20 floor 15 (so d20+5 ≥ 20 = STR).
        let pc = Self.makeBarbarian(level: 18, str: 20)
        let floor = CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength)
        #expect(floor == 15)
    }

    @Test func abilityCheckFloorClampedToTwentyForOverfloor() {
        // STR 24 (Primal Champion cap territory) → mod +7 → floor 17. Still
        // clamped ≤ 20 defensively (17 is well inside range but the clamp
        // protects against odd-score arithmetic drift).
        let content = ContentStore()
        let pc = Self.makeBarbarian(level: 20, str: 24)
        let floor = CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength)
        #expect(floor == 17)
    }

    @Test func abilityCheckFloorAppliesOnlyToDesignatedAbility() {
        // Indomitable Might is STR-scoped; DEX/CON/etc. checks are unaffected.
        let content = ContentStore()
        let pc = Self.makeBarbarian(level: 18, str: 20)
        #expect(CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .dexterity) == nil)
        #expect(CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .constitution) == nil)
        #expect(CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength) != nil)
    }

    @Test func interpreterFloorsSTRCheckD20() {
        // ActionInterpreter should surface the floor as a d20 minimumValue so
        // the roll engine clamps low rolls.
        var pc = Self.makeBarbarian(level: 18, str: 18)
        pc.rolledHP = 100
        let content = ContentStore()
        let floor = CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: .abilityCheck(ability: .strength),
            character: pc,
            weapon: nil,
            abilityCheckFloor: floor
        )
        let d20Group = resolved.formula?.groups.first { $0.kind == .d20 }
        #expect(d20Group?.minimumValue == 14)  // STR 18 → mod +4 → floor 14
    }

    @Test func interpreterFloorsSTRSaveD20() {
        var pc = Self.makeBarbarian(level: 18, str: 20)
        pc.rolledHP = 100
        let content = ContentStore()
        let floor = CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: .savingThrow(ability: .strength),
            character: pc,
            weapon: nil,
            abilityCheckFloor: floor
        )
        let d20Group = resolved.formula?.groups.first { $0.kind == .d20 }
        #expect(d20Group?.minimumValue == 15)
    }

    @Test func interpreterFloorsSTRSkillCheckWhenNoReliableTalent() {
        var pc = Self.makeBarbarian(level: 18, str: 20)
        pc.rolledHP = 100
        let content = ContentStore()
        let floor = CharacterCalculator.abilityCheckFloor(
            character: pc, content: content, ability: .strength)
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .athletics),
            character: pc,
            weapon: nil,
            skillCheckFloor: nil,
            abilityCheckFloor: floor
        )
        let d20Group = resolved.formula?.groups.first { $0.kind == .d20 }
        #expect(d20Group?.minimumValue == 15)  // STR 20 → floor 15
    }

    @Test func interpreterFloorsUseHigherOfReliableTalentAndAbilityCheckFloor() {
        // Reliable Talent floor = 10 (Rogue L7); Indomitable Might floor = 15
        // (STR 20). Both fire on a STR-based skill check → take the higher.
        // We're not actually making a rogue-barbarian; just testing the max
        // logic in the interpreter path.
        var pc = Self.makeBarbarian(level: 18, str: 20)
        pc.rolledHP = 100
        // Force proficiency so Reliable Talent is not gated out.
        pc.proficiencies[.skill(.athletics)] = .proficient
        let resolved = ActionInterpreter.resolve(
            recipe: .skillCheck(skill: .athletics),
            character: pc,
            weapon: nil,
            skillCheckFloor: 10,
            abilityCheckFloor: 15
        )
        let d20Group = resolved.formula?.groups.first { $0.kind == .d20 }
        #expect(d20Group?.minimumValue == 15)
    }

    // MARK: - Reckless Attack: toggle → active effect → advantage

    @Test func recklessAttackInactiveByDefault() {
        let content = ContentStore()
        let pc = Self.makeBarbarian(level: 5)
        #expect(!CharacterCalculator.recklessAttackActive(character: pc, content: content))
    }

    @Test func recklessAttackActiveWhileToggleOn() {
        let content = ContentStore()
        var pc = Self.makeBarbarian(level: 5)
        pc.activeEffects = [
            ActiveEffect(
                effectID: "reckless_attack_toggle",
                source: .feature(featureID: "reckless_attack"),
                roundsRemaining: 1
            )
        ]
        #expect(CharacterCalculator.recklessAttackActive(character: pc, content: content))
    }

    @Test func recklessAttackIgnoresUnrelatedActiveEffects() {
        let content = ContentStore()
        var pc = Self.makeBarbarian(level: 5)
        pc.activeEffects = [
            ActiveEffect(
                effectID: "some_other_effect",
                source: .feature(featureID: "unrelated"),
                roundsRemaining: 10
            )
        ]
        #expect(!CharacterCalculator.recklessAttackActive(character: pc, content: content))
    }

    // MARK: - Helpers

    private static func makeBarbarian(level: Int, str: Int = 16) -> Character {
        Character(
            name: "Reg",
            level: level,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "barbarian", level: level)],
            abilityScores: [
                .strength: str, .dexterity: 14, .constitution: 14,
                .intelligence: 10, .wisdom: 12, .charisma: 8,
            ],
            maxHP: level * 8,
            rolledHP: level * 8
        )
    }

    private static func makeFighter(level: Int) -> Character {
        Character(
            name: "Fig",
            level: level,
            speciesID: "human",
            backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: level)],
            abilityScores: [
                .strength: 16, .dexterity: 14, .constitution: 14,
                .intelligence: 10, .wisdom: 12, .charisma: 8,
            ],
            maxHP: level * 8,
            rolledHP: level * 8
        )
    }
}
