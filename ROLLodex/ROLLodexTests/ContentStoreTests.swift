import Testing
import Foundation
@testable import ROLLodex

struct ContentStoreTests {

    @Test func loadsFighterClass() {
        let store = ContentStore()
        let fighter = store.classDefinition(id: "fighter")
        #expect(fighter != nil)
        #expect(fighter?.name == "Fighter")
        #expect(fighter?.hitDie == .d10)
        #expect(fighter?.primaryAbility == .strength)
        #expect(fighter?.savingThrows.contains(.strength) == true)
        #expect(fighter?.armorProficiencies.contains(.heavy) == true)
        #expect(fighter?.weaponProficiencies.contains(.martial) == true)
        #expect(fighter?.masteryCount == 3)
        // 2024 class skill choice (modeled as an L1 .skillsFrom selection).
        #expect(fighter?.skillProficiencySelection?.selection.count.value(classLevel: 1, characterLevel: 1) == 2)
    }

    @Test func rogueSkillChoiceIsChooseFourOfTen() {
        let store = ContentStore()
        let sel = store.classDefinition(id: "rogue")?.skillProficiencySelection
        #expect(sel?.selection.count.value(classLevel: 1, characterLevel: 1) == 4)
        #expect(sel?.options.count == 10)
        #expect(sel?.options.contains(.stealth) == true)
        #expect(sel?.options.contains(.sleightOfHand) == true)
        // Selection id carries the marker the calculator resolves on.
        #expect(sel?.selection.id.contains("class_skills") == true)
    }

    @Test func loadsWizardClass() {
        let store = ContentStore()
        let wizard = store.classDefinition(id: "wizard")
        #expect(wizard != nil)
        #expect(wizard?.name == "Wizard")
        #expect(wizard?.hitDie == .d6)
        #expect(wizard?.primaryAbility == .intelligence)
        #expect(wizard?.armorProficiencies.isEmpty == true)
        #expect(wizard?.masteryCount == nil)
    }

    @Test func loadsSpecies() {
        let store = ContentStore()
        #expect(store.speciesDefinition(id: "human")?.name == "Human")
        #expect(store.speciesDefinition(id: "elf")?.name == "Elf")
        #expect(store.speciesDefinition(id: "dwarf")?.name == "Dwarf")
        // All 9 SRD 5.2.1 species present.
        for id in ["dragonborn", "gnome", "goliath", "halfling", "orc", "tiefling"] {
            #expect(store.speciesDefinition(id: id) != nil, "missing species \(id)")
        }
        #expect(store.speciesDefinition(id: "gnome")?.size == "small")
        #expect(store.speciesDefinition(id: "goliath")?.speed == 35)
        #expect(store.speciesDefinition(id: "dragonborn")?.traits.contains { $0.id == "breath_weapon" } == true)
    }

    @MainActor
    @Test func speciesTraitChoicesAndFormulas() {
        let store = ContentStore()

        func optionCount(species: String, trait: String) -> Int? {
            let t = store.speciesDefinition(id: species)?.traits.first { $0.id == trait }
            guard case .fixedOptions(let options)? = t?.selection?.optionsSource else { return nil }
            return options.count
        }

        // Elf gained the previously-missing Elven Lineage picker.
        #expect(store.speciesDefinition(id: "elf")?.traits.first { $0.id == "elven_lineage" }?
            .selection?.id == "elf_lineage")
        #expect(optionCount(species: "elf", trait: "elven_lineage") == 3)

        // Lineage / ancestry / legacy pickers across the new species.
        #expect(optionCount(species: "dragonborn", trait: "draconic_ancestry") == 10)
        #expect(optionCount(species: "gnome", trait: "gnomish_lineage") == 2)
        #expect(optionCount(species: "goliath", trait: "giant_ancestry") == 6)
        #expect(optionCount(species: "tiefling", trait: "fiendish_legacy") == 3)

        // Dragonborn Breath Weapon: Action cost, scaledDamage recipe, PB pool.
        let breath = store.speciesDefinition(id: "dragonborn")?.traits.first { $0.id == "breath_weapon" }
        let breathCost = breath?.actionCost
        #expect(breathCost == .action)
        #expect(breath?.resource?.id == "dragonborn_breath_weapon")
        var breathScales = false
        if case .scaledDamage(let dieKind, _, _, _)? = breath?.actionRecipes.first {
            breathScales = dieKind == 10
        }
        #expect(breathScales)

        // Dwarf Stonecunning is now the 5.2.1 Bonus Action with a pool.
        let stone = store.speciesDefinition(id: "dwarf")?.traits.first { $0.id == "stonecunning" }
        let stoneCost = stone?.actionCost
        #expect(stoneCost == .bonusAction)
        #expect(stone?.resource?.id == "dwarf_stonecunning")

        // The Breath Weapon pool resolves to PB-many uses (3 at level 5).
        let pc = Character(
            name: "Drogon", level: 5, speciesID: "dragonborn", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.constitution: 14], maxHP: 30
        )
        let pools = ResourceCalculator.availableResources(character: pc, content: store)
        #expect(pools.first { $0.definition.id == "dragonborn_breath_weapon" }?.max == 3)
    }

    @MainActor
    @Test func speciesSpellGrantsResolveByLevelAndChoice() {
        let store = ContentStore()
        func infernalTiefling(level: Int, legacy: String? = "infernal") -> Character {
            var c = Character(
                name: "Zariel", level: level, speciesID: "tiefling", backgroundID: "acolyte",
                classEntries: [ClassEntry(classID: "fighter", level: level)],
                abilityScores: [.charisma: 14], maxHP: 10
            )
            if let legacy { c.featureSelections["tiefling_legacy"] = [legacy] }
            return c
        }
        func grants(_ c: Character) -> [String] {
            CharacterSpellGrants.resolve(character: c, content: store).map(\.spell.id)
        }

        // Level 1 Infernal Tiefling: Fire Bolt (legacy cantrip) + Thaumaturgy
        // (Otherworldly Presence, flat) — but NOT the level 3 / 5 spells yet.
        let l1 = grants(infernalTiefling(level: 1))
        #expect(l1.contains("fire_bolt"))
        #expect(l1.contains("thaumaturgy"))
        #expect(!l1.contains("hellish_rebuke"))
        #expect(!l1.contains("darkness"))

        // The leveled grants unlock at their minCharacterLevel.
        #expect(grants(infernalTiefling(level: 3)).contains("hellish_rebuke"))
        #expect(!grants(infernalTiefling(level: 3)).contains("darkness"))
        #expect(grants(infernalTiefling(level: 5)).contains("darkness"))

        // No legacy chosen: choice-gated grants vanish, flat Thaumaturgy stays.
        let none = grants(infernalTiefling(level: 5, legacy: nil))
        #expect(!none.contains("fire_bolt"))
        #expect(none.contains("thaumaturgy"))

        // A different legacy grants its own cantrip, not the Infernal one.
        var abyssal = infernalTiefling(level: 1, legacy: "abyssal")
        abyssal.featureSelections["tiefling_legacy"] = ["abyssal"]
        #expect(grants(abyssal).contains("poison_spray"))
        #expect(!grants(abyssal).contains("fire_bolt"))

        // Non-species-granting character gets nothing.
        let human = Character(
            name: "H", level: 5, speciesID: "human", backgroundID: "acolyte",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [:], maxHP: 10
        )
        #expect(CharacterSpellGrants.resolve(character: human, content: store).isEmpty)
    }

    @MainActor
    @Test func innateSpellAbilityAndFreeCastPools() {
        let store = ContentStore()
        func tiefling(level: Int, scores: [Ability: Int]) -> Character {
            var c = Character(
                name: "Z", level: level, speciesID: "tiefling", backgroundID: "acolyte",
                classEntries: [ClassEntry(classID: "fighter", level: level)],
                abilityScores: scores, maxHP: 10
            )
            c.featureSelections["tiefling_legacy"] = ["infernal"]
            return c
        }

        // Hole 1: innate casting ability = highest of INT/WIS/CHA.
        let chaPC = tiefling(level: 5, scores: [.intelligence: 10, .wisdom: 12, .charisma: 16])
        #expect(CharacterSpellGrants.innateSpellcastingAbility(character: chaPC, content: store) == .charisma)
        let intPC = tiefling(level: 5, scores: [.intelligence: 15, .wisdom: 12, .charisma: 8])
        #expect(CharacterSpellGrants.innateSpellcastingAbility(character: intPC, content: store) == .intelligence)
        // And it resolves a real spell-attack roll for a non-caster.
        let attack = ActionInterpreter.resolve(
            recipe: .spellAttack(label: "Fire Bolt Attack"),
            character: chaPC, weapon: nil,
            spellcastingAbility: CharacterSpellGrants.innateSpellcastingAbility(character: chaPC, content: store)
        )
        #expect(attack.formula != nil)

        // An explicit ability pick overrides the highest-stat default.
        var explicit = intPC  // highest is INT...
        explicit.featureSelections["tiefling_spell_ability"] = ["charisma"]
        #expect(CharacterSpellGrants.innateSpellcastingAbility(character: explicit, content: store) == .charisma)

        // Hole 2: leveled grants get a 1/Long-Rest free-cast pool; cantrips don't.
        #expect(CharacterSpellGrants.hasFreeCast(spellID: "hellish_rebuke", character: chaPC, content: store))
        #expect(!CharacterSpellGrants.hasFreeCast(spellID: "fire_bolt", character: chaPC, content: store))
        let pools = ResourceCalculator.availableResources(character: chaPC, content: store)
        #expect(pools.first { $0.definition.id == "grant_hellish_rebuke" }?.max == 1)
        #expect(pools.contains { $0.definition.id == "grant_darkness" })   // L5 grant
        #expect(!pools.contains { $0.definition.id == "grant_fire_bolt" }) // cantrip → no pool

        // Pool (and free cast) only once the leveled grant is unlocked.
        let l1 = tiefling(level: 1, scores: [.charisma: 16])
        #expect(!CharacterSpellGrants.hasFreeCast(spellID: "hellish_rebuke", character: l1, content: store))
        #expect(!ResourceCalculator.availableResources(character: l1, content: store)
            .contains { $0.definition.id == "grant_hellish_rebuke" })
    }

    @MainActor
    @Test func breathWeaponTakesChosenAncestryDamageType() {
        let store = ContentStore()
        func dragonborn(ancestry: String?) -> Character {
            var c = Character(
                name: "D", level: 5, speciesID: "dragonborn", backgroundID: "soldier",
                classEntries: [ClassEntry(classID: "fighter", level: 5)],
                abilityScores: [.constitution: 14], maxHP: 30
            )
            if let ancestry { c.featureSelections["dragonborn_ancestry"] = [ancestry] }
            return c
        }
        func breathGroup(_ c: Character) -> DiceGroup? {
            CharacterActionDeriver.sections(for: c, content: store)
                .flatMap(\.rows)
                .first { $0.title == "Breath Weapon" }?.action.formula?.groups.first
        }
        // Red → fire, and the die count scales to 2d10 at level 5.
        #expect(breathGroup(dragonborn(ancestry: "red"))?.damageType == .fire)
        #expect(breathGroup(dragonborn(ancestry: "red"))?.count == 2)
        // Green → poison.
        #expect(breathGroup(dragonborn(ancestry: "green"))?.damageType == .poison)
        // Unchosen → untyped, but the roll still resolves.
        #expect(breathGroup(dragonborn(ancestry: nil))?.damageType == nil)
        #expect(breathGroup(dragonborn(ancestry: nil))?.count == 2)
    }

    @Test func loadsBackgrounds() {
        let store = ContentStore()
        #expect(store.backgroundDefinition(id: "soldier")?.name == "Soldier")
        #expect(store.backgroundDefinition(id: "sage")?.skillProficiencies.contains(.arcana) == true)
        #expect(store.backgroundDefinition(id: "acolyte")?.feat == "magic_initiate_cleric")
        // Criminal completes the SRD's 4 backgrounds.
        let criminal = store.backgroundDefinition(id: "criminal")
        #expect(criminal?.feat == "alert")
        #expect(criminal?.skillProficiencies.contains(.stealth) == true)
        #expect(criminal?.skillProficiencies.contains(.sleightOfHand) == true)
        // 2024 backgrounds list three boostable abilities (player distributes).
        #expect(criminal?.abilityScoreOptions == [.dexterity, .constitution, .intelligence])
        #expect(store.backgroundDefinition(id: "soldier")?.abilityScoreOptions.count == 3)
    }

    @Test func loadsWeapons() {
        let store = ContentStore()
        let longsword = store.weaponDefinition(id: "longsword")
        #expect(longsword != nil)
        #expect(longsword?.damage == "1d8")
        #expect(longsword?.versatileDamage == "1d10")
        #expect(longsword?.masteryProperty == .sap)
        #expect(longsword?.properties.contains(.versatile) == true)

        let rapier = store.weaponDefinition(id: "rapier")
        #expect(rapier?.properties.contains(.finesse) == true)
        #expect(rapier?.masteryProperty == .vex)
    }

    @Test func loadsArmor() {
        let store = ContentStore()
        let chainMail = store.armorDefinition(id: "chain_mail")
        #expect(chainMail?.acBase == 16)
        #expect(chainMail?.dexCap == 0)
        #expect(chainMail?.armorCategory == .heavy)

        let leather = store.armorDefinition(id: "leather")
        #expect(leather?.dexCap == nil)
        #expect(leather?.armorCategory == .light)
    }

    @Test func itemNameLookup() {
        let store = ContentStore()
        #expect(store.itemName(forItemID: "longsword") == "Longsword")
        #expect(store.itemName(forItemID: "chain_mail") == "Chain Mail")
        #expect(store.itemName(forItemID: "backpack") == "Backpack")
        #expect(store.itemName(forItemID: "nonexistent") == nil)
    }

    // MARK: - Giant Ancestry mechanics

    @MainActor
    private func goliath(_ giant: String?) -> Character {
        var c = Character(
            name: "Gol", level: 5, speciesID: "goliath", backgroundID: "soldier",
            classEntries: [ClassEntry(classID: "fighter", level: 5)],
            abilityScores: [.strength: 16, .constitution: 14], maxHP: 40,
            proficiencies: [.weapon(.martial): .proficient]
        )
        if let giant { c.featureSelections["goliath_giant_ancestry"] = [giant] }
        return c
    }

    @MainActor
    @Test func giantAncestryGrantedActionsAreChoiceGated() {
        let store = ContentStore()
        func names(_ giant: String?) -> [String] {
            CharacterActionDeriver.grantedActions(for: goliath(giant), content: store)
                .map(\.action.name)
        }
        // Stone's Endurance surfaces as a Reaction, only when chosen.
        let stone = CharacterActionDeriver.grantedActions(for: goliath("stones_endurance"), content: store)
            .first { $0.action.name == "Stone's Endurance" }
        #expect(stone?.cost == .reaction)
        #expect(names("clouds_jaunt").contains("Cloud's Jaunt"))
        #expect(names("storms_thunder").contains("Storm's Thunder"))
        // A different giant doesn't leak the others' actions.
        #expect(!names("clouds_jaunt").contains("Stone's Endurance"))
        // No giant chosen → none of them.
        #expect(!names(nil).contains("Cloud's Jaunt"))
    }

    @MainActor
    @Test func giantAncestryOnHitRiderIsChoiceGated() {
        let store = ContentStore()
        guard let weapon = store.weaponDefinition(id: "longsword") else {
            Issue.record("longsword weapon missing"); return
        }
        func riderPrompts(_ giant: String?) -> [String] {
            let c = goliath(giant)
            return TriggeredEffectResolver.optInRiders(
                weapon: weapon, character: c, content: store
            ).map(\.label)
        }
        #expect(riderPrompts("fires_burn").contains("Fire's Burn"))
        #expect(riderPrompts("frosts_chill").contains("Frost's Chill"))
        // Non-rider giant → no giant rider chip.
        #expect(!riderPrompts("stones_endurance").contains("Fire's Burn"))
        #expect(!riderPrompts(nil).contains("Fire's Burn"))
    }

    // MARK: - Bard

    @MainActor
    @Test func loadsBardWithAbilityModResourceAndFullCasterSlots() {
        let store = ContentStore()
        let bard = store.classDefinition(id: "bard")
        #expect(bard?.name == "Bard")
        #expect(bard?.spellcasting?.ability == .charisma)
        #expect(bard?.subclassLevel == 3)
        #expect(bard?.subclasses.contains { $0.id == "college_of_lore" } == true)
        // Class skills = choose any 3 (skillsFrom over the full list).
        #expect(bard?.skillProficiencySelection?.options.count == 18)

        func bardicMax(cha: Int) -> Int? {
            let c = Character(
                name: "B", level: 3, speciesID: "human", backgroundID: "sage",
                classEntries: [ClassEntry(classID: "bard", level: 3)],
                abilityScores: [.charisma: cha], maxHP: 20
            )
            return ResourceCalculator.availableResources(character: c, content: store)
                .first { $0.definition.id == "bardic_inspiration" }?.max
        }
        // Bardic Inspiration uses = CHA modifier, floored at 1.
        #expect(bardicMax(cha: 16) == 3)
        #expect(bardicMax(cha: 10) == 1)

        // Full-caster progression: a level-20 Bard has a 9th-level slot.
        let c20 = Character(
            name: "B20", level: 20, speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "bard", level: 20)],
            abilityScores: [.charisma: 18], maxHP: 100
        )
        let hasNinth = ResourceCalculator.availableResources(character: c20, content: store)
            .contains { if case .spellSlot(let l) = $0.definition.displayHint { return l == 9 }; return false }
        #expect(hasNinth)
    }

    @MainActor
    @Test func reactionFeaturesSurfaceAsActionRows() {
        let store = ContentStore()
        // Level-3 College of Lore Bard: Cutting Words is a Reaction with no
        // roll and no pool of its own (it spends Bardic Inspiration) — it must
        // still appear on the Actions tab as a reaction reminder.
        let bard = Character(
            name: "Lore", level: 3, speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "bard", level: 3)],
            abilityScores: [.charisma: 16], maxHP: 20,
            featureSelections: ["bard_subclass": ["college_of_lore"]]
        )
        let rows = CharacterActionDeriver.sections(for: bard, content: store).flatMap(\.rows)
        let cuttingWords = rows.first { $0.title == "Cutting Words" }
        #expect(cuttingWords != nil)
        #expect(cuttingWords?.action.actionCost == .reaction)
        // Bardic Inspiration (a real pool) still shows as a Bonus Action.
        #expect(rows.contains { $0.title == "Bardic Inspiration" && $0.action.actionCost == .bonusAction })
        // A pure passive (Jack of All Trades) does NOT surface as an action row.
        #expect(!rows.contains { $0.title == "Jack of All Trades" })
    }

    // MARK: - Sorcerer

    @MainActor
    @Test func loadsSorcererWithScalingSorceryPointsAndMetamagic() {
        let store = ContentStore()
        let sorc = store.classDefinition(id: "sorcerer")
        #expect(sorc?.name == "Sorcerer")
        #expect(sorc?.hitDie == .d6)
        #expect(sorc?.spellcasting?.ability == .charisma)
        #expect(sorc?.armorProficiencies.isEmpty == true)
        #expect(sorc?.subclasses.contains { $0.id == "draconic_sorcery" } == true)

        func sorcerer(_ level: Int) -> Character {
            Character(
                name: "S", level: level, speciesID: "human", backgroundID: "sage",
                classEntries: [ClassEntry(classID: "sorcerer", level: level)],
                abilityScores: [.charisma: 16], maxHP: 6 * level
            )
        }

        // Sorcery Points: none at L1 (Font of Magic is L2), then = level.
        func sorceryPoints(_ level: Int) -> Int? {
            ResourceCalculator.availableResources(character: sorcerer(level), content: store)
                .first { $0.definition.id == "sorcery_points" }?.max
        }
        #expect(sorceryPoints(1) == nil)
        #expect(sorceryPoints(2) == 2)
        #expect(sorceryPoints(11) == 11)
        #expect(sorceryPoints(20) == 20)

        // Sorcery Points are a counter, NOT a tappable action row.
        let l5rows = CharacterActionDeriver.sections(for: sorcerer(5), content: store).flatMap(\.rows)
        #expect(!l5rows.contains { $0.title == "Font of Magic" })
        // Innate Sorcery IS an activatable Bonus Action with a 2-use pool.
        #expect(l5rows.contains { $0.title == "Innate Sorcery" && $0.action.actionCost == .bonusAction })

        // Metamagic known count scales 2 → 4 → 6 via the selection's count.
        func metamagicCount(_ level: Int) -> Int? {
            guard let f = sorc?.levelFeatures[2]?.first(where: { $0.id == "metamagic" }),
                  let sel = f.selection else { return nil }
            return sel.count.value(classLevel: level, characterLevel: level)
        }
        #expect(metamagicCount(2) == 2)
        #expect(metamagicCount(10) == 4)
        #expect(metamagicCount(17) == 6)

        // Full-caster slots reach 9th by L17+.
        let hasNinth = ResourceCalculator.availableResources(character: sorcerer(20), content: store)
            .contains { if case .spellSlot(let l) = $0.definition.displayHint { return l == 9 }; return false }
        #expect(hasNinth)
    }

    @MainActor
    @Test func draconicSpellsAreGrantedByLevelAndChoice() {
        let store = ContentStore()
        func draconic(_ level: Int, sub: Bool = true) -> Character {
            Character(
                name: "D", level: level, speciesID: "human", backgroundID: "sage",
                classEntries: [ClassEntry(classID: "sorcerer", level: level)],
                abilityScores: [.charisma: 16], maxHP: 6 * level,
                featureSelections: sub ? ["sorcerer_subclass": ["draconic_sorcery"]] : [:]
            )
        }
        func granted(_ c: Character) -> [String] {
            CharacterSpellGrants.resolve(character: c, content: store).map(\.spell.id)
        }
        // L3: the four level-3 Draconic spells, none of the higher ones.
        let l3 = granted(draconic(3))
        #expect(l3.contains("chromatic_orb"))
        #expect(l3.contains("dragons_breath"))
        #expect(!l3.contains("fear"))    // L5 grant
        #expect(!l3.contains("arcane_eye")) // L7 grant
        // Higher tiers unlock at their levels.
        #expect(granted(draconic(5)).contains("fear"))
        #expect(granted(draconic(7)).contains("charm_monster"))
        #expect(granted(draconic(9)).contains("summon_dragon"))
        // No grants before the subclass is chosen, or for a non-Draconic sorc.
        #expect(!granted(draconic(9, sub: false)).contains("summon_dragon"))
    }

    @MainActor
    @Test func innateSorceryBuffRaisesDCAndGrantsAdvantageWhileActive() {
        let store = ContentStore()
        // Innate Sorcery is a toggle that surfaces on the Actions tab.
        let off = Character(
            name: "S", level: 5, speciesID: "human", backgroundID: "sage",
            classEntries: [ClassEntry(classID: "sorcerer", level: 5)],
            abilityScores: [.charisma: 16], maxHP: 30
        )
        // While inactive: no buff, base DC = 8 + 3 (CHA) + 3 (PB) = 14.
        let inactiveBuff = CharacterCalculator.spellcastingBuff(character: off, content: store)
        #expect(inactiveBuff.saveDCBonus == 0)
        #expect(inactiveBuff.attackAdvantage == false)
        #expect(CharacterCalculator.spellSaveDC(
            character: off, spellcastingAbility: .charisma, bonus: inactiveBuff.saveDCBonus
        ) == 14)

        // Activate Innate Sorcery (toggle adds its effect to activeEffects).
        var on = off
        on.activeEffects = [ActiveEffect(
            effectID: "innate_sorcery_buff",
            source: .feature(featureID: "innate_sorcery"),
            roundsRemaining: 10
        )]
        let buff = CharacterCalculator.spellcastingBuff(character: on, content: store)
        #expect(buff.saveDCBonus == 1)
        #expect(buff.attackAdvantage == true)
        // DC rises to 15 with the buff.
        #expect(CharacterCalculator.spellSaveDC(
            character: on, spellcastingAbility: .charisma, bonus: buff.saveDCBonus
        ) == 15)
    }
}
