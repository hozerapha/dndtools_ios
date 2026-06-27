# ROLLodex TTRPG Playtest Report

**Date:** 2026-06-27  
**Ruleset lens:** D&D 5e / 5.5e SRD (2024 flavor for backgrounds, weapon mastery, and Fighting Styles)  
**Scope reviewed:** Dice roller, character creation, character sheet, bundled content, and cross-tab roll handoff.  
**Methodology:** Static code/table-read playtest against the shipped Swift/SwiftUI codebase and bundled JSON content. No new classes, species, spells, or major systems are proposed; all findings and recommendations stay within the existing content and architecture.

---

## 1. Executive Summary

ROLLodex is already a genuinely usable table companion. The 3D physics dice tray feels like a real dice box, the formula parser covers the most common D&D notation, and the character sheet → dice tab handoff (weapon attack → damage chip, spell attack → damage chip, opt-in riders like Sneak Attack) is the strongest feature for actual play.

The gaps that would show up most quickly at a real table are:

1. **Critical hits do not double damage dice** — a nat-20 Longsword still rolls `1d8+3`.
2. **Choose-your-damage spells are locked to one type** — *Chromatic Orb* and *Dragon’s Breath* are hard-coded to fire damage.
3. **Fighting Styles and Weapon Masteries are informational only** — selecting Great Weapon Fighting or Vex does not change rolls.
4. **Conditions are tracked but not enforced** — the app knows you are Poisoned, but the attack roll does not take Disadvantage.
5. **Many buff/debuff spells are castable but do not alter the sheet** — *Shield*, *Bless*, *False Life*, *Longstrider*, etc.

These are all fixable inside the existing JSON + `ActionInterpreter` / `CharacterCalculator` framework without adding new classes or spells.

---

## 2. Content Audit

| Content | Shipped | Notes |
|---|---|---|
| Classes | 8 | Fighter, Wizard, Rogue, Barbarian, Paladin, Cleric, Bard, Sorcerer |
| Subclasses | 5 | Champion (Fighter), Thief (Rogue), Life Domain (Cleric), College of Lore (Bard), Draconic Sorcery (Sorcerer) |
| Species | 9 | Human, Elf, Dwarf, Dragonborn, Gnome, Goliath, Halfling, Orc, Tiefling |
| Backgrounds | 4 | Soldier, Sage, Acolyte, Criminal (background feats/equipment not applied) |
| Weapons | 10 | Club, Dagger, Mace, Quarterstaff, Longsword, Rapier, Greatsword, Shortbow, Longbow, Light Crossbow |
| Armor | 8 | Padded, Leather, Studded Leather, Hide, Chain Shirt, Breastplate, Chain Mail, Shield |
| Gear | 8 | Backpack, Bedroll, Rope, Torch, Rations, Waterskin, Potion of Healing, Wand of Magic Missiles |
| Spells | 43 | Cantrips through 5th level |
| Conditions | 14 | Blinded, Charmed, Deafened, Frightened, Grappled, Incapacitated, Invisible, Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious |

High-level class coverage is shallow beyond the low levels: only Fighter, Rogue, and Wizard have features defined past level 4–5, while Barbarian stops at level 1. That is consistent with the phased plan and not flagged as a defect here.

---

## 3. System-by-System Findings

### 3.1 Dice Roller (`DiceRollerView` / `DiceSceneController`)

**What works well**

- Procedural 3D dice for d4–d20 and d100-as-two-d10s, physics rest detection (0.5 s of stillness), press-and-hold magnifier, and per-damage-type glow.
- Formula parser supports `NdX`, `kh`/`kl`/`dh`/`dl`, `rX` (reroll once), typed dice (`[fire]2d6`), and typed flat modifiers (`[force]5`).
- History, presets, adv/dis encoding (`2d20kh1` / `2d20kl1`), and damage-type breakdowns in the HUD.
- Cross-tab handoff consumes a `ResolvedAction`, prefills the tray, and surfaces follow-up chips.

**Friction points**

- **Follow-up damage is offered even on a natural 1.** `handleWeaponAttack` always queues the damage chip, and `DiceRollerView` shows the rail whenever `lastResult != nil` without checking `hasCriticalFail` (`DiceRollerView.swift:310`, `CharacterSheetView.swift:433`). A nat-1 is an automatic miss in 5e, so the chip should at least be suppressed in that case.
- **No critical damage handling.** There is no path that doubles weapon or spell damage dice when the preceding attack is a natural 20. The damage roll uses the same formula as a normal hit.
- **Stroke of Luck only appears for sheet handoffs.** `rollingCharacterID` is set only from `consumePendingRollIfNeeded`, so a Rogue player who manually types a d20 in the dice tab will never see the Stroke of Luck prompt (`DiceRollerView.swift:217`, `:460`).

### 3.2 Character Creation (`CharacterCreationView` / `CharacterDraft` / `CharacterListView`)

**What works well**

- Clean step-by-step flow: name → species → species choices → background → class → class skills → ability scores → review.
- Ability generation supports Point Buy, Standard Array, and rolled (`4d6kh3` or house formula), all validated.
- Background ASIs, skill proficiencies, class saving-throw/armor/weapon/tool proficiencies, and species choices are applied correctly in `CharacterListView.finalizeDraft` (`CharacterListView.swift:77–155`).
- Starting HP uses the real class hit die and Dwarven Toughness/Draconic Resilience bonuses are folded in.

**Friction points**

- **Background feats and equipment are not applied.** `backgrounds.json` declares a `feat` and `equipment` array, but neither is granted to the character. New characters start with an empty inventory even though the Criminal background lists a dagger, thieves’ tools, etc.
- **Starting spell seeding gives casters every L1 spell in the store.** `seedStartingSpells` adds all cantrips up to the budget and every leveled spell the store has at that level, with no class-list filtering (`CharacterListView.swift:161–194`). A Wizard starts knowing every bundled L1 spell.
- **Species traits that grant skill proficiency are not resolved.** Elf `keen_senses` says “proficiency in Insight, Perception, or Survival,” but there is no picker or automatic grant.

### 3.3 Character Sheet — Actions (`CharacterSheetView` / `ActionEconomyView` / `AttacksView`)

**What works well**

- Equipped weapons render attack / damage / 2H chips with correct ability mods, proficiency, Archery, and Dueling bonuses.
- The Actions tab groups feature and item uses by economy (Action / Bonus / Reaction / Free / Movement).
- Resource counters (Second Wind, Rage, spell slots, Stonecunning, Wand charges) are live and exhaust correctly.
- Turn tracker clears once-per-turn flags and decrements round-limited effects with one “Start New Turn” tap.

**Friction points**

- **Rage is toggle-only; most of its rules are not modeled.** The Barbarian Rage toggle spends a use and starts a 10-round countdown, but it does not grant advantage on Strength checks/saves, damage resistance, or restrict actions/spells.
- **Fighting Style effects are partial.** Archery and Dueling are implemented in `ActionInterpreter.resolveWeaponAttack` / `resolveWeaponDamage` (`ActionInterpreter.swift:232–305`). Defense gives +1 AC via `CharacterCalculator.defenseACBonus`. **Great Weapon Fighting and Two-Weapon Fighting are not enforced** — there is no code path that rerolls 1s/2s or adds ability mod to off-hand damage.
- **Weapon Mastery properties are display-only.** `AttacksView` shows the mastery badge and a description sheet, but properties such as Vex, Graze, Sap, Topple, Nick, and Slow do not alter rolls (`AttacksView.swift:69–85`, `CharacterActionDeriver.swift:251–257`).
- **Action Surge is a resource button, not an extra action.** The player must remember to take a second action after tapping it.
- **Uncanny Dodge, Evasion, Steady Aim, Cunning Strike, Divine Smite** (if present) are descriptive or partially wired but do not mechanically resolve damage reduction, evasion, advantage, or conditions.

### 3.4 Character Sheet — Spells (`SpellListView` / `SpellCastSheet`)

**What works well**

- Slot picker, upcasting (`extraDicePerLevel`), ritual casting, concentration-swap prompt, and concentration-save sheet.
- Spell attack → damage follow-up works like weapon attack → damage.
- Innate Sorcery correctly expands a spell attack d20 to `2d20kh1` while active (`SpellCastSheet.swift:693–698`).
- Species-granted spells and once-per-Long-Rest free casts are surfaced.

**Friction points**

- **Variable-damage spells are locked to a single type.** *Chromatic Orb* and *Dragon’s Breath* carry a `rawDamage` recipe with `"damageType": "fire"` and a label saying “choose type” (`spells.json:927`, `:1002`). There is no UI to pick Acid/Cold/Lightning/Poison/Thunder, so the spell always rolls fire.
- **Buff / debuff spells do not change the character state.** The JSON explicitly notes that *Shield*, *Shield of Faith*, *Bless*, and *Pass without Trace* must be added manually. In addition:
  - *False Life* does not set temp HP.
  - *Longstrider* / *Fly* / *Alter Self* do not change speed or AC.
  - *Ray of Sickness* / *Hold Person* / *Fear* / *Charm Monster* do not apply Poisoned, Paralyzed, Frightened, or Charmed.
  - *Faerie Fire* does not grant advantage against affected creatures.
- **Multiclass spellcasters use the first class’s spellcasting ability.** `SpellCastSheet.spellcastingAbility` returns the first class with a spellcasting block (`SpellCastSheet.swift:653–662`). A Wizard/Cleric would use Intelligence for everything.
- **Prepared casters cannot curate their prepared list.** Add Spell puts a spell in all three lists (`knownIDs`, `preparedIDs`, `spellbookIDs`), so Wizards and Clerics effectively always prepare every spell they add.

### 3.5 Character Sheet — Inventory, HP, Conditions

**What works well**

- Equipping armor/shield updates AC; attunement limits and eligibility are enforced.
- Weight total, quantity controls, weapon breakdown block, and item search picker.
- HP editor handles damage/healing, temp HP, and max HP edits; damage drains temp HP first and triggers concentration saves correctly.
- Death-save tracker auto-tallies physical-dice rolls and clears on healing.

**Friction points**

- **Conditions are tracked but not mechanically applied.** The condition definitions carry rich `effects` arrays (e.g., Poisoned → `attacksByHaveDisadvantage`, Restrained → `savingThrowDisadvantage` for Dex), but nothing consumes them in `CharacterCalculator` or `ActionInterpreter` (`conditions.json`, `ConditionDefinition.swift`). A Poisoned Rogue still rolls Sneak Attack at full value.
- **Stealth disadvantage from armor is not surfaced.** Armor definitions include `stealthDisadvantage`, but it is not shown on the sheet or applied to Stealth rolls.
- **Attunement slot override is manual only.** Features such as Thief’s “Use Magic Device” raise the cap via `attunementSlots`, but the player must manually toggle attunement on a 4th item.

---

## 4. Issue Summary by Severity

| Severity | Issue | File reference |
|---|---|---|
| **High** | Critical hits do not double damage dice. | `DiceRollerView.swift`, `CharacterActionDeriver.swift` |
| **High** | *Chromatic Orb* / *Dragon’s Breath* damage type is hard-coded to fire. | `spells.json:927`, `:1002` |
| **Medium** | Damage follow-up chip appears after a natural 1 (automatic miss). | `DiceRollerView.swift:310`, `CharacterSheetView.swift:433` |
| **Medium** | Great Weapon Fighting / Two-Weapon Fighting styles have no mechanical effect. | `classes.json`, `ActionInterpreter.swift` |
| **Medium** | Weapon Mastery properties do not alter rolls. | `AttacksView.swift`, `CharacterActionDeriver.swift` |
| **Medium** | Condition effects are not applied to attack rolls, saves, or speed. | `conditions.json`, `CharacterCalculator.swift` |
| **Medium** | Buff/debuff spells do not update HP, AC, speed, or apply conditions. | `SpellCastSheet.swift`, `spells.json` |
| **Low** | Background feats/equipment are ignored at creation. | `backgrounds.json`, `CharacterListView.swift` |
| **Low** | Starting spell seeding ignores class spell lists. | `CharacterListView.swift:161–194` |
| **Low** | Stroke of Luck prompt does not appear for manual dice-tab rolls. | `DiceRollerView.swift:217` |
| **Low** | Multiclass casters use the first class’s spellcasting ability. | `SpellCastSheet.swift:653–662` |

---

## 5. Recommendations (within existing content/systems)

1. **Model critical damage in the follow-up rail.** When the attack `RollResult` has `hasCriticalSuccess`, the queued damage chip should either duplicate every damage-die group in the formula or present a “Critical damage — roll twice” prompt. This can be done entirely in `CharacterActionDeriver` / `DiceRollerView` without new content.
2. **Suppress damage chips on a natural 1.** `followUpRail` should check `lastResult.hasCriticalFail` and hide the damage/options rail, because a nat-1 is a miss.
3. **Make variable-damage spells choose a type.** The smallest fix is to give *Chromatic Orb* and *Dragon’s Breath* multiple `rawDamage` recipes (one per allowed type) in `spells.json`. A richer fix adds a damage-type picker in `SpellCastSheet`, still using the existing `DamageType` enum.
4. **Enforce condition effects.** `CharacterCalculator` can read `character.conditions` when computing attack/save/skill modifiers and apply Disadvantage/Advantage or auto-fail flags. This stays within the existing condition definitions.
5. **Wire up high-impact spells to existing state.** Using the current HP/condition/concentration systems:
   - *False Life* → set `character.tempHP`.
   - *Ray of Sickness* → apply `poisoned` condition.
   - *Hold Person* / *Fear* / *Charm Monster* → apply `paralyzed` / `frightened` / `charmed` on cast (honor-system save).
   - *Shield* / *Shield of Faith* / *Bless* could create short-lived active effects that modify AC/attack rolls once condition automation exists.
6. **Implement the two missing Fighting Styles.** Great Weapon Fighting can re-roll 1s/2s on eligible two-handed weapon damage dice; Two-Weapon Fighting can add the ability modifier to the off-hand damage formula. Both use existing formulas and weapon properties.
7. **Make Weapon Masteries do something.** Start with the simple ones: Vex could grant advantage on the next attack after a hit; Graze could add ability-mod damage on a miss; Sap could reduce speed. These are small `TriggeredEffect`-style additions using the current rider system.
8. **Apply background equipment and feats at creation.** Parse `backgrounds.json` `equipment` and `feat` and add matching items/proficiencies to the new character. If feats are not modeled yet, surface a note in the review step so the player does not forget.
9. **Filter starting spells by a class spell list.** Add a `spellIDs` allow-list to each class’s `spellcasting` block (or reuse `preparedRule`) so `seedStartingSpells` only grants class-appropriate spells.
10. **Resolve species skill choices.** Add a fixed-options selection for Elf `keen_senses` and similar traits so the granted proficiency is recorded in `featureSelections` like class skills.

---

## 6. Conclusion

ROLLodex is past the “tech demo” stage and into real-play territory for martial characters and straightforward spellcasters. The dice feel good, the sheet is editable, and the attack → damage → rider workflow is genuinely faster than flipping between apps.

The most important next steps for table credibility are, in order:

1. Fix critical-hit damage.
2. Make choose-type spells actually chooseable.
3. Enforce conditions and high-impact spell effects.
4. Complete Fighting Style and Weapon Mastery mechanics.

All of these can be achieved with the current JSON schema, `DiceFormula`/`RollResult` model, `ActionInterpreter`, and `CharacterCalculator` — no new classes, species, or spells are required.
