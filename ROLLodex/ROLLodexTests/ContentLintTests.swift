import Testing
import Foundation
@testable import ROLLodex

/// Cross-reference lint over ALL bundled content (roadmap item 9e).
///
/// The decoders already reject malformed JSON; this suite catches what they
/// can't — references that point nowhere, dice strings that don't parse,
/// upcast indices out of range, level tables that resolve to 0 at the level
/// the feature unlocks. Every content edit gets validated by ⌘U instead of
/// failing silently at runtime. When Phase H (homebrew import) lands, these
/// same invariants become the import validator.
@MainActor
struct ContentLintTests {

    /// Ids referenced by bundled JSON that intentionally have no definition
    /// yet. Feats await the feat catalog (roadmap item 11g); the equipment
    /// entries are background flavor items awaiting the gear sweep (11d).
    /// `allowListStaysHonest` fails when one of these gains a real
    /// definition — remove it from this list at that point.
    static let knownUnauthoredIDs: Set<String> = [
        // Feats — no feat catalog exists yet.
        "savage_attacker", "magic_initiate_wizard", "magic_initiate_cleric", "alert",
        // Background equipment flavor items.
        "common_clothes", "insignia_of_rank", "gaming_set",
        "bottle_of_ink", "small_knife", "letter_from_colleague",
        "holy_symbol", "prayer_book",
        "thieves_tools", "crowbar", "pouch", "travelers_clothes",
    ]

    // MARK: - Id uniqueness

    @Test func idsAreUniqueWithinEachFile() throws {
        for file in ["classes", "species", "backgrounds", "weapons", "armor", "gear", "spells", "conditions"] {
            let ids = try rawIDs(file)
            let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys
            #expect(dupes.isEmpty, "\(file).json has duplicate ids: \(dupes.sorted())")
        }
    }

    @Test func itemIDsAreUniqueAcrossItemFiles() throws {
        // gear / weapons / armor share one item-id namespace —
        // ContentStore.itemName(forItemID:) checks them in order, so a
        // collision silently shadows one definition.
        let all = try rawIDs("gear") + rawIDs("weapons") + rawIDs("armor")
        let dupes = Dictionary(grouping: all, by: { $0 }).filter { $1.count > 1 }.keys
        #expect(dupes.isEmpty, "item id collision across gear/weapons/armor: \(dupes.sorted())")
    }

    @Test func resourceAndEffectIDsAreGloballyUnique() {
        let content = ContentStore()
        var resourceIDs: [String] = []
        var effectIDs: [String] = []
        for entry in allClassFeatures(content) {
            if let r = entry.feature.resource { resourceIDs.append(r.id) }
            if let e = entry.feature.triggeredEffect { effectIDs.append(e.id) }
        }
        for surface in allItemSurfaces(content) {
            if let r = surface.resource { resourceIDs.append(r.id) }
        }
        for spell in content.spells.values {
            if let e = spell.grantsTriggeredEffect { effectIDs.append(e.id) }
        }
        let resourceDupes = Dictionary(grouping: resourceIDs, by: { $0 }).filter { $1.count > 1 }.keys
        #expect(resourceDupes.isEmpty,
                "resource ids collide: \(resourceDupes.sorted()) — they key Character.resources, so two owners would share one pool")
        let effectDupes = Dictionary(grouping: effectIDs, by: { $0 }).filter { $1.count > 1 }.keys
        #expect(effectDupes.isEmpty,
                "triggered-effect ids collide: \(effectDupes.sorted()) — they key ActiveEffect.effectID state tracking")
    }

    // MARK: - Dangling references

    @Test func backgroundReferencesResolveOrAreAllowListed() {
        let content = ContentStore()
        for bg in content.backgrounds.values {
            if let feat = bg.feat {
                // No feat catalog exists yet, so every feat reference must be
                // declared as known debt. When feats become real content,
                // replace this with a lookup against the feat store.
                #expect(Self.knownUnauthoredIDs.contains(feat),
                        "background \(bg.id) references feat \"\(feat)\" — author it or add it to knownUnauthoredIDs")
            }
            for itemID in bg.equipment {
                let resolves = content.itemName(forItemID: itemID) != nil
                #expect(resolves || Self.knownUnauthoredIDs.contains(itemID),
                        "background \(bg.id) equipment \"\(itemID)\" has no definition — author it or add it to knownUnauthoredIDs")
            }
        }
    }

    @Test func allowListStaysHonest() {
        let content = ContentStore()
        for id in Self.knownUnauthoredIDs.sorted() {
            #expect(content.itemName(forItemID: id) == nil,
                    "\"\(id)\" now has a real definition — remove it from knownUnauthoredIDs")
        }
    }

    @Test func itemUsesResolve() {
        let content = ContentStore()
        let resourceIDs = globalResourceIDs(content)
        for surface in allItemSurfaces(content) {
            for use in surface.uses {
                #expect(resourceIDs.contains(use.cost.resourceID),
                        "\(surface.context)/\(use.id) costs unknown resource \"\(use.cost.resourceID)\"")
                if case .castSpell(let spellID, let atLevel) = use.effect {
                    #expect(content.spellDefinition(id: spellID) != nil,
                            "\(surface.context)/\(use.id) casts unknown spell \"\(spellID)\"")
                    if let choice = use.upcastChoice {
                        #expect(choice.maxLevel >= atLevel,
                                "\(surface.context)/\(use.id) upcast maxLevel \(choice.maxLevel) is below the base cast level \(atLevel)")
                    }
                }
            }
        }
    }

    // MARK: - Dice strings

    @Test func allDiceStringsParse() {
        let content = ContentStore()
        for entry in allClassFeatures(content) {
            for dice in diceStrings(in: entry.feature.actionRecipes) {
                assertParses(dice, context: entry.context)
            }
            // Granted-action options can carry their own rolls.
            let grantedRecipes = entry.feature.grantedActions.compactMap(\.recipe)
            for dice in diceStrings(in: grantedRecipes) {
                assertParses(dice, context: "\(entry.context) granted action")
            }
            if let resource = entry.feature.resource {
                lintResource(resource, grantLevel: entry.grantLevel, context: entry.context)
            }
            if let effect = entry.feature.triggeredEffect {
                lintTriggeredEffect(effect, grantLevel: entry.grantLevel, context: entry.context)
            }
            if let selection = entry.feature.selection {
                lintLevelTable(selection.count, grantLevel: entry.grantLevel,
                               context: "\(entry.context) selection \(selection.id)")
            }
            // Class/subclass feature spell grants (flat + per-option) must
            // resolve to a bundled spell — otherwise they silently never show.
            var spellGrants = entry.feature.grantsSpells
            if case .fixedOptions(let options)? = entry.feature.selection?.optionsSource {
                spellGrants += options.flatMap(\.grantsSpells)
            }
            for grant in spellGrants {
                #expect(content.spellDefinition(id: grant.spellID) != nil,
                        "\(entry.context) grants missing spell \(grant.spellID)")
            }
        }
        for species in content.species.values {
            for trait in species.traits {
                for dice in diceStrings(in: trait.actionRecipes) {
                    assertParses(dice, context: "species/\(species.id)/\(trait.id)")
                }
                // Scaled-damage recipes (Breath Weapon, Martial Arts) carry a
                // die size (flat or level-scaled) + a level→count table
                // instead of a parseable dice string. Every size the scaling
                // can produce must be a real die.
                for recipe in trait.actionRecipes {
                    if case .scaledDamage(let dieKind, _, _, _, _) = recipe {
                        for level in 1...20 {
                            let sides = dieKind.value(classLevel: level, characterLevel: level)
                            #expect(DieKind(rawValue: sides) != nil,
                                    "invalid dieKind \(sides) at L\(level) in species/\(species.id)/\(trait.id)")
                        }
                    }
                }
                // Every granted spell (flat + per-lineage-option) must resolve
                // to a bundled spell, or it silently never shows on the sheet.
                var grants = trait.grantsSpells
                if case .fixedOptions(let options)? = trait.selection?.optionsSource {
                    grants += options.flatMap(\.grantsSpells)
                    // Option-level granted-action recipes (Giant Ancestry's
                    // Stone's Endurance / Storm's Thunder) must parse too.
                    for option in options {
                        let recipes = option.grantedActions.compactMap(\.recipe)
                        for dice in diceStrings(in: recipes) {
                            assertParses(dice, context: "species/\(species.id)/\(trait.id)/\(option.id)")
                        }
                    }
                }
                for grant in grants {
                    #expect(content.spellDefinition(id: grant.spellID) != nil,
                            "species/\(species.id)/\(trait.id) grants missing spell \(grant.spellID)")
                }
            }
        }
        for spell in content.spells.values {
            for dice in diceStrings(in: spell.actionRecipes) {
                assertParses(dice, context: "spell/\(spell.id)")
            }
            if let effect = spell.grantsTriggeredEffect {
                // Spell riders scale by the CASTER's class level; grant level
                // 1 is the strictest check (a table starting above 1 would be
                // 0 for a low-level caster).
                lintTriggeredEffect(effect, grantLevel: 1, context: "spell/\(spell.id)")
            }
        }
        for surface in allItemSurfaces(content) {
            if let resource = surface.resource {
                // Items have no grant level — only the refresh-roll formula
                // is meaningfully lintable, so pass the loosest level.
                lintResource(resource, grantLevel: 20, context: surface.context)
            }
            for use in surface.uses {
                if case .actionRecipes(let recipes) = use.effect {
                    for dice in diceStrings(in: recipes) {
                        assertParses(dice, context: "\(surface.context)/\(use.id)")
                    }
                }
            }
        }
        for weapon in content.weapons.values {
            assertParses(weapon.damage, context: "weapon/\(weapon.id) damage")
            if let versatile = weapon.versatileDamage {
                assertParses(versatile, context: "weapon/\(weapon.id) versatile")
            }
        }
    }

    @Test func spellUpcastEffectsAreInBoundsAndScale() {
        let content = ContentStore()
        for spell in content.spells.values {
            guard let upcast = spell.upcastEffect else { continue }
            switch upcast {
            case .extraDicePerLevel(let index, let dice, let levelsPerBonus):
                assertParses(dice, context: "spell/\(spell.id) upcast dice")
                #expect(levelsPerBonus >= 1,
                        "spell/\(spell.id) upcast levelsPerBonus must be ≥ 1 (got \(levelsPerBonus))")
                let inBounds = spell.actionRecipes.indices.contains(index)
                #expect(inBounds,
                        "spell/\(spell.id) upcast recipeIndex \(index) is out of bounds (\(spell.actionRecipes.count) recipes) — upcasting silently no-ops")
                if inBounds {
                    switch spell.actionRecipes[index] {
                    case .rawDamage, .heal:
                        break
                    default:
                        Issue.record("spell/\(spell.id) upcast targets recipe \(index), which is not a rawDamage/heal and cannot scale")
                    }
                }
                // The composed max-upcast formula must round-trip the parser.
                for composed in diceStrings(in: spell.recipes(castAtLevel: 9)) {
                    assertParses(composed, context: "spell/\(spell.id) cast at 9")
                }
            case .extraTargetsPerLevel:
                break
            }
        }
    }

    // MARK: - Structural consistency

    @Test func subclassWiringIsConsistent() {
        let content = ContentStore()
        for cls in content.classes.values {
            guard !cls.subclasses.isEmpty else { continue }
            #expect(cls.subclassLevel != nil,
                    "\(cls.id) bundles subclasses but declares no subclassLevel")
            let subIDs = cls.subclasses.map(\.id)
            let dupes = Dictionary(grouping: subIDs, by: { $0 }).filter { $1.count > 1 }.keys
            #expect(dupes.isEmpty, "\(cls.id) has duplicate subclass ids: \(dupes.sorted())")

            // The aggregator reads the chosen subclass from the convention
            // key, so the picker feature must store under exactly that id.
            let conventionID = ClassDefinition.subclassSelectionID(forClassID: cls.id)
            var foundPicker = false
            for (_, features) in cls.levelFeatures {
                for feature in features {
                    guard let selection = feature.selection,
                          case .subclasses(let parent) = selection.optionsSource else { continue }
                    foundPicker = true
                    #expect(parent == cls.id,
                            "\(cls.id)/\(feature.id) subclass selection points at \"\(parent)\"")
                    #expect(selection.id == conventionID,
                            "\(cls.id)/\(feature.id) stores picks under \"\(selection.id)\" but the aggregator reads \"\(conventionID)\"")
                }
            }
            #expect(foundPicker, "\(cls.id) bundles subclasses but no feature offers the subclass selection")
        }
    }

    // MARK: - Helpers

    private struct IDOnly: Decodable { let id: String }

    private func rawIDs(_ filename: String) throws -> [String] {
        // Same lookup order as ContentStore.loadDictionary.
        let candidates = [
            Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Content"),
            Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Resources/Content"),
            Bundle.main.url(forResource: filename, withExtension: "json"),
        ]
        let url = try #require(candidates.compactMap { $0 }.first,
                               "missing bundled \(filename).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([IDOnly].self, from: data).map(\.id)
    }

    private struct FeatureEntry {
        let context: String
        let grantLevel: Int
        let feature: FeatureDefinition
    }

    private func allClassFeatures(_ content: ContentStore) -> [FeatureEntry] {
        var out: [FeatureEntry] = []
        for cls in content.classes.values {
            for (level, features) in cls.levelFeatures {
                for feature in features {
                    out.append(FeatureEntry(
                        context: "\(cls.id) L\(level) \(feature.id)",
                        grantLevel: level,
                        feature: feature
                    ))
                }
            }
            for sub in cls.subclasses {
                for (level, features) in sub.levelFeatures {
                    for feature in features {
                        out.append(FeatureEntry(
                            context: "\(cls.id)/\(sub.id) L\(level) \(feature.id)",
                            grantLevel: level,
                            feature: feature
                        ))
                    }
                }
            }
        }
        return out
    }

    private struct ItemSurface {
        let context: String
        let resource: ResourceDefinition?
        let uses: [ItemUse]
    }

    private func allItemSurfaces(_ content: ContentStore) -> [ItemSurface] {
        var out: [ItemSurface] = []
        for item in content.gear.values {
            out.append(ItemSurface(context: "gear/\(item.id)", resource: item.resource, uses: item.uses))
        }
        for weapon in content.weapons.values {
            out.append(ItemSurface(context: "weapon/\(weapon.id)", resource: weapon.resource, uses: weapon.uses))
        }
        for armor in content.armor.values {
            out.append(ItemSurface(context: "armor/\(armor.id)", resource: armor.resource, uses: armor.uses))
        }
        return out
    }

    private func globalResourceIDs(_ content: ContentStore) -> Set<String> {
        var ids = Set<String>()
        for entry in allClassFeatures(content) {
            if let r = entry.feature.resource { ids.insert(r.id) }
        }
        for surface in allItemSurfaces(content) {
            if let r = surface.resource { ids.insert(r.id) }
        }
        return ids
    }

    private func diceStrings(in recipes: [ActionRecipe]) -> [String] {
        recipes.compactMap { recipe in
            switch recipe {
            case .heal(let dice, _, _, _):      return dice
            case .rawDamage(let dice, _, _, _): return dice
            case .abilityRoll(let dice, _, _):  return dice
            default:                            return nil
            }
        }
    }

    private func assertParses(_ dice: String, context: String) {
        #expect((try? DiceFormulaParser().parse(dice)) != nil,
                "unparseable dice \"\(dice)\" in \(context)")
    }

    private func lintResource(_ resource: ResourceDefinition, grantLevel: Int, context: String) {
        lintLevelTable(resource.max, grantLevel: grantLevel,
                       context: "\(context) resource \(resource.id) max")
        switch resource.refreshAmount {
        case .roll(let formula):
            assertParses(formula, context: "\(context) resource \(resource.id) refresh")
        case .byClassLevel(let table):
            #expect((table.keys.min() ?? Int.max) <= grantLevel,
                    "\(context) resource \(resource.id) refresh table starts above its grant level L\(grantLevel)")
        case .all, .fixed:
            break
        }
    }

    private func lintTriggeredEffect(_ effect: TriggeredEffect, grantLevel: Int, context: String) {
        switch effect.effect {
        case .addDamageDice(let dice, _):
            assertParses(dice, context: "\(context) effect \(effect.id)")
        case .addScaledDamageDice(let count, let die, _):
            #expect(DieKind.allCases.map(\.label).contains(die),
                    "\(context) effect \(effect.id) die token \"\(die)\" is not a valid die kind")
            lintLevelTable(count, grantLevel: grantLevel, context: "\(context) effect \(effect.id) count")
        case .addFlatDamage(let amount, _):
            lintLevelTable(amount, grantLevel: grantLevel, context: "\(context) effect \(effect.id) amount")
        case .addSlotScaledDamageDice(let base, let extra, _):
            assertParses(base, context: "\(context) effect \(effect.id) baseDice")
            assertParses(extra, context: "\(context) effect \(effect.id) extraDicePerSlotLevel")
            // Slot scaling is meaningless without a slot cost to set the level.
            if case .spellSlot? = effect.cost {} else {
                Issue.record("\(context) effect \(effect.id) uses addSlotScaledDamageDice without a spellSlot cost")
            }
        case .spellcastingBuff(let dc, let adv):
            // A buff that does nothing is a content error.
            #expect(dc != 0 || adv,
                    "\(context) effect \(effect.id) is a spellcastingBuff with no DC bonus or advantage")
        }
    }

    /// A `byClassLevel` table whose lowest key is above the level its owner
    /// unlocks at resolves to 0 the moment the player gains the feature —
    /// always a content-author mistake.
    private func lintLevelTable(_ value: LevelScaledValue, grantLevel: Int, context: String) {
        if case .byClassLevel(let table) = value {
            #expect((table.keys.min() ?? Int.max) <= grantLevel,
                    "\(context): byClassLevel table starts at L\(table.keys.min() ?? -1) but the owner unlocks at L\(grantLevel) — value is 0 when granted")
        }
    }
}
