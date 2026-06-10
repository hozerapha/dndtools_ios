import Testing
import Foundation
@testable import ROLLodex

/// Paladin + Divine Smite (Phase O's spell-slot cost path). Covers the new
/// `TriggerCost.spellSlot` / `TriggerEffect.addSlotScaledDamageDice` schema,
/// half-caster slot synthesis, chip gating by slot availability, slot-level
/// dice scaling, and slot consumption.
@MainActor
struct DivineSmiteTests {

    // MARK: - Schema

    @Test func spellSlotCostRoundTrips() throws {
        let json = #"{"type":"spellSlot","minLevel":1,"maxLevel":5}"#.data(using: .utf8)!
        let cost = try JSONDecoder().decode(TriggerCost.self, from: json)
        let decodedShape: Bool
        if case .spellSlot(let lo, let hi) = cost {
            decodedShape = lo == 1 && hi == 5
        } else {
            decodedShape = false
        }
        #expect(decodedShape)

        let reencoded = try JSONEncoder().encode(cost)
        let roundTripped = try JSONDecoder().decode(TriggerCost.self, from: reencoded)
        let stable = roundTripped == cost
        #expect(stable)
    }

    @Test func slotScaledEffectRoundTrips() throws {
        let json = """
        {"type":"addSlotScaledDamageDice","baseDice":"2d8","extraDicePerSlotLevel":"1d8","damageType":"radiant"}
        """.data(using: .utf8)!
        let effect = try JSONDecoder().decode(TriggerEffect.self, from: json)
        let decodedShape: Bool
        if case .addSlotScaledDamageDice(let base, let extra, let typed) = effect {
            decodedShape = base == "2d8" && extra == "1d8" && typed == .fixed(.radiant)
        } else {
            decodedShape = false
        }
        #expect(decodedShape)

        let reencoded = try JSONEncoder().encode(effect)
        let roundTripped = try JSONDecoder().decode(TriggerEffect.self, from: reencoded)
        let stable = roundTripped == effect
        #expect(stable)
    }

    // MARK: - Bundled Paladin

    @Test func bundledPaladinLoads() {
        let content = ContentStore()
        let paladin = content.classDefinition(id: "paladin")
        #expect(paladin != nil)
        let isD10 = paladin?.hitDie == .d10
        #expect(isD10)
        let savesMatch = paladin?.savingThrows == [.wisdom, .charisma]
        #expect(savesMatch)
        let prepared = paladin?.spellcasting?.preparedRule == .preparedFromAll
        #expect(prepared)
        let chaCaster = paladin?.spellcasting?.ability == .charisma
        #expect(chaCaster)
        #expect(paladin?.subclassLevel == 3)
    }

    @Test func bundledSmiteFeatureIsWiredCorrectly() {
        let content = ContentStore()
        let smiteFeature = content.classDefinition(id: "paladin")?
            .levelFeatures[2]?
            .first { $0.id == "paladins_smite" }
        #expect(smiteFeature != nil)
        guard let effect = smiteFeature?.triggeredEffect else {
            Issue.record("paladins_smite has no triggered effect")
            return
        }
        let isOptIn = effect.activation == .optIn
        #expect(isOptIn)
        let costShape: Bool
        if case .spellSlot(let lo, let hi)? = effect.cost {
            costShape = lo == 1 && hi == 5
        } else {
            costShape = false
        }
        #expect(costShape)
        let effectShape: Bool
        if case .addSlotScaledDamageDice(let base, let extra, let typed) = effect.effect {
            effectShape = base == "2d8" && extra == "1d8" && typed == .fixed(.radiant)
        } else {
            effectShape = false
        }
        #expect(effectShape)
    }

    @Test func layOnHandsPoolScalesByLevel() {
        let content = ContentStore()
        let pool = content.classDefinition(id: "paladin")?
            .levelFeatures[1]?
            .first { $0.id == "lay_on_hands" }?
            .resource
        #expect(pool?.max.value(classLevel: 1, characterLevel: 1) == 5)
        #expect(pool?.max.value(classLevel: 5, characterLevel: 5) == 25)
        #expect(pool?.max.value(classLevel: 20, characterLevel: 20) == 100)
    }

    // MARK: - Half-caster slot synthesis

    @Test func halfCasterSlotsSynthesize() {
        let content = ContentStore()
        let l1 = makePaladin(level: 1)
        let l1Slots = slotResources(for: l1, content: content)
        #expect(l1Slots.count == 1)
        #expect(l1Slots.first?.id == "paladin_slot_1")
        #expect(l1Slots.first?.max == 2)

        let l5 = makePaladin(level: 5)
        let l5Slots = slotResources(for: l5, content: content)
        #expect(l5Slots.count == 2)
        #expect(l5Slots.first(where: { $0.id == "paladin_slot_1" })?.max == 4)
        #expect(l5Slots.first(where: { $0.id == "paladin_slot_2" })?.max == 2)
    }

    @Test func lowestAvailableSlotLevelPrefersCheapest() {
        let content = ContentStore()
        var paladin = makePaladin(level: 5)
        #expect(ResourceCalculator.lowestAvailableSlotLevel(
            min: 1, max: 5, character: paladin, content: content) == 1)

        // Drain the 1st-level slots — the 2nd-level pool is next-cheapest.
        paladin.resources["paladin_slot_1"] = ResourceState(current: 0)
        #expect(ResourceCalculator.lowestAvailableSlotLevel(
            min: 1, max: 5, character: paladin, content: content) == 2)

        // Nothing in range when the range sits above what the class has.
        #expect(ResourceCalculator.lowestAvailableSlotLevel(
            min: 3, max: 5, character: paladin, content: content) == nil)
    }

    @Test func consumeSpellSlotDecrements() {
        let content = ContentStore()
        var paladin = makePaladin(level: 1)
        let ok = ResourceCalculator.consumeSpellSlot(level: 1, in: &paladin, content: content)
        #expect(ok)
        #expect(ResourceCalculator.current(
            character: paladin, content: content, resourceID: "paladin_slot_1") == 1)

        // Drain and refuse overdraft.
        _ = ResourceCalculator.consumeSpellSlot(level: 1, in: &paladin, content: content)
        let overdraft = ResourceCalculator.consumeSpellSlot(level: 1, in: &paladin, content: content)
        #expect(!overdraft)
    }

    // MARK: - Chip gating + scaling

    @Test func smiteChipAppearsForMeleeHitWithSlots() {
        let content = ContentStore()
        let paladin = makePaladin(level: 2)
        let chips = smiteChips(for: paladin, weaponID: "longsword", content: content)
        #expect(chips.count == 1)
        #expect(chips.first?.chipPrompt == "Divine Smite (L1 slot)")
        // Base 2d8 radiant at the lowest (1st-level) slot.
        let radiantDice = radiantDiceCount(in: chips.first)
        #expect(radiantDice == 2)
        // The parked cost is concretized to the slot the player saw.
        let costConcretized = chips.first?.cost == .spellSlot(minLevel: 1, maxLevel: 1)
        #expect(costConcretized)
    }

    @Test func smiteChipSkipsRangedWeapons() {
        let content = ContentStore()
        let paladin = makePaladin(level: 2)
        let chips = smiteChips(for: paladin, weaponID: "shortbow", content: content)
        #expect(chips.isEmpty)
    }

    @Test func smiteChipSkipsWhenNoSlotsRemain() {
        let content = ContentStore()
        var paladin = makePaladin(level: 2)
        paladin.resources["paladin_slot_1"] = ResourceState(current: 0)
        let chips = smiteChips(for: paladin, weaponID: "longsword", content: content)
        #expect(chips.isEmpty)
    }

    @Test func smiteDiceScaleWithTheSlotActuallySpent() {
        let content = ContentStore()
        var paladin = makePaladin(level: 5)
        // Only 2nd-level slots remain → smite is 2d8 + 1d8 = 3d8 radiant.
        paladin.resources["paladin_slot_1"] = ResourceState(current: 0)
        let chips = smiteChips(for: paladin, weaponID: "longsword", content: content)
        #expect(chips.count == 1)
        #expect(chips.first?.chipPrompt == "Divine Smite (L2 slot)")
        let radiantDice = radiantDiceCount(in: chips.first)
        #expect(radiantDice == 3)
        let costConcretized = chips.first?.cost == .spellSlot(minLevel: 2, maxLevel: 2)
        #expect(costConcretized)
    }

    // MARK: - Helpers

    private func makePaladin(level: Int) -> Character {
        Character(
            name: "Uther", level: level,
            speciesID: "human", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "paladin", level: level)],
            abilityScores: [.strength: 16, .charisma: 16, .constitution: 14],
            maxHP: 10 + 6 * level,
            currentHP: 10 + 6 * level
        )
    }

    private func slotResources(for character: Character, content: ContentStore) -> [ResolvedResource] {
        ResourceCalculator.availableResources(character: character, content: content)
            .filter { resolved in
                if case .spellSlot = resolved.definition.displayHint { return true }
                return false
            }
            .sorted { $0.id < $1.id }
    }

    private func smiteChips(
        for character: Character,
        weaponID: String,
        content: ContentStore
    ) -> [PendingFollowUp] {
        let weapon = content.weaponDefinition(id: weaponID)
        var base = DiceFormula()
        base.groups.append(DiceGroup(kind: .d8, count: 1, damageType: weapon?.damageType))
        base.modifier = 3
        let damage = ResolvedAction(
            id: "weapon_\(weaponID)_damage",
            label: "Damage",
            formula: base,
            description: nil
        )
        return TriggeredEffectResolver.optInRiders(
            weapon: weapon,
            baseDamage: damage,
            character: character,
            content: content
        )
    }

    private func radiantDiceCount(in chip: PendingFollowUp?) -> Int {
        chip?.action.formula?.groups
            .filter { $0.damageType == .radiant }
            .reduce(0) { $0 + $1.count } ?? 0
    }
}
