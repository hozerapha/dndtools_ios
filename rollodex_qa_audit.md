# ROLLodex iOS QA Audit Report

**Project:** ROLLodex (`/Users/josecolina/gitpersonal/dndtools_ios`)  
**Date:** 2026-06-27  
**Scope:** Static analysis of Swift source for crashes, data corruption, rules/math errors, state-machine bugs, parser edge cases, and UX traps. Read-only audit; no code changes made.  
**Files reviewed:** ~90 of 115 source files, including all dice-roller/parser/store logic, character models/calculator, creation, level-up, spell casting, inventory, actions, and content import.

---

## Executive Summary

ROLLodex is a well-architected SwiftUI app with clear separation between pure model logic and UI, but several critical paths have correctness or data-integrity issues that will surface in real play. The top risks are:

1. **Stroke of Luck corrupts roll history** by blindly removing the newest history entry instead of the roll it replaced.
2. **Action handoffs consume resources before the dice roll resolves**, so a user can lose a Rage / Spell Slot / Channel Divinity charge without ever rolling.
3. **Bundled-content decode failures crash the app at launch** with `fatalError`.
4. **Imported content packs can silently overwrite each other** when their sanitized filenames collide.
5. **Advantage/Reliable Talent combination is silently discarded**; a Rogue with Reliable Talent who rolls a skill check with advantage gets a normal d20 with floor 10.
6. **Class skill proficiencies do not count for Reliable Talent** because the skill-check resolver only looks at stored proficiencies, not class-skill selections.
7. **The dice parser rejects valid combinations** of `min` with keep/drop modifiers (e.g., `1d20kh2min10`).

These are concrete, file/line-identified issues with reproduction conditions and suggested fixes below.

---

## Critical Bugs

### 1. Stroke of Luck removes the wrong history entry
- **Severity:** Critical  
- **Area:** Dice roller / history  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/DiceRollerView.swift`, `applyStrokeOfLuck()` (lines ~289–300)  
- **Description:** After forcing the d20 to 20, the code calls `history.removeFirst()` and then records the new result. `removeFirst()` always deletes the most recent history entry, not the original roll that triggered the Stroke of Luck prompt. If the user cleared history or rolled anything else in the meantime, the wrong entry is deleted or the original roll remains.
- **Reproduction:**
  1. Roll an attack from a Rogue character that triggers Stroke of Luck.
  2. Without tapping the chip, roll any other formula from the dice tab.
  3. Tap Stroke of Luck.
  4. The newer roll is removed; the original attack roll stays in history, and the new forced-20 entry is inserted at the top.
- **Expected:** The roll being modified is replaced in place.  
- **Actual:** The newest history entry is removed unconditionally.  
- **Suggested fix:** Store the `RollResult.id` of the roll that opened the Stroke of Luck prompt. Replace `history.removeFirst()` with `history.rolls.removeAll { $0.id == originalRollID }` (or add a `remove(id:)` method to `HistoryStore`).

### 2. Action handoffs consume resources before the roll is resolved
- **Severity:** Critical  
- **Area:** Character sheet → dice tab handoff  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/CharacterSheetView.swift`, `handleActionTap(_:)` (lines ~504–552)  
- **Description:** For actions with a `resourceCost`, the resource is consumed immediately when the row is tapped, before the dice tab is opened. If the user never completes the roll (switches tabs, dismisses the app, or the dice tab rejects the formula), the charge is already gone.
- **Reproduction:**
  1. Open a Barbarian with Rage charges.
  2. Tap Rage (or any feature with a resource cost and a roll).
  3. App switches to Dice tab. Force-quit or navigate away without rolling.
  4. Return to the character: the Rage charge is gone but no roll was made.
- **Expected:** Resource is spent when the dice actually roll and settle, or at least when the dice tab commits.  
- **Actual:** Resource is debited on tap.  
- **Suggested fix:** Move resource consumption into `DiceRollerView.roll()` (or a pre-roll commitment step) and pass the `resourceCost` through `PendingRollStore` so the dice tab debits only when the roll succeeds. For no-formula actions (Action Surge), keep the current tap-to-consume behavior.

### 3. Bundled content decode failures crash at launch
- **Severity:** Critical  
- **Area:** Content store / launch stability  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/State/ContentStore.swift`, `loadDictionary(from:decode:)` (lines ~127–153)  
- **Description:** Missing or malformed bundled JSON calls `fatalError`, terminating the app. This is fine for development, but any asset-catalog regression or JSON typo in a release build will brick the app for users.
- **Reproduction:** Corrupt or remove any bundled `Content/*.json` file, then launch the app.  
- **Expected:** App degrades gracefully with an error screen or empty content.  
- **Actual:** Immediate crash.  
- **Suggested fix:** Replace `fatalError` with a thrown error / empty fallback and surface a launch-time alert: "Required game data is missing. Please reinstall the app."

### 4. Imported content packs silently overwrite each other
- **Severity:** Critical  
- **Area:** Content import / data loss  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/State/ContentStore.swift`, `sanitize(_:)` and `importPack(data:suggestedName:)` (lines ~195–279)  
- **Description:** The pack filename is derived from `sanitize(displayName)`. Two different names can collide after sanitization (e.g., "Pack 1" and "Pack!1" both become `pack-1`). Importing the second overwrites the first without confirmation.
- **Reproduction:**
  1. Import a pack named "Pack 1".
  2. Import a different pack named "Pack!1".
  3. Only the second pack remains on disk; the first is gone.
- **Expected:** Collision detected and user warned, or unique filenames used.  
- **Actual:** Silent overwrite.  
- **Suggested fix:** Append a short hash of the original filename/data to the sanitized slug, or check for an existing file and prompt/append a counter.

### 5. `min` floor cannot be combined with keep/drop modifiers
- **Severity:** Critical  
- **Area:** Dice formula parser  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Models/DiceFormulaParser.swift`, `parseModifiers(_:count:sides:term:)` (lines ~180–202)  
- **Description:** The parser extracts the `minN` substring first, then tries to parse the remaining string as a group modifier. For a valid term like `1d20kh2min10`, after extracting `min10` the remaining string is `1d20kh2`, which starts with a digit and fails as an unknown modifier. Terms like `1d20min10kh2` also fail because `after` contains `10kh2`.
- **Reproduction:** Type `1d20kh1min10` or `2d6min3kh2` into the formula bar.  
- **Expected:** Parser accepts a floor on a kept/dropped group.  
- **Actual:** Parser throws `unknownModifier` / `invalidMinimum`.  
- **Suggested fix:** Parse the modifier token(s) first, then strip the trailing `minN` from the remaining suffix, or use a regex/ordered scanner that recognizes `min` as a terminal suffix.

### 6. Advantage is silently dropped when Reliable Talent applies
- **Severity:** Critical  
- **Area:** Rules / skill checks / advantage  
- **Files:**
  - `ROLLodex/ROLLodex/Features/CharacterSheet/Views/CharacterSheetView.swift`, `applyAdvantage(to:mode:)` (lines ~619–627)
  - `ROLLodex/ROLLodex/Features/CharacterSheet/Content/ActionInterpreter.swift`, `resolveSkillCheck(...)` (lines ~349–390)
- **Description:** `applyAdvantage` only expands a d20 group if it is "plain" (`modifier == nil`). `resolveSkillCheck` stamps the Reliable Talent floor onto the d20 via `minimumValue`, making the group non-plain. The user can tap the advantage chip, but the roll is sent as a single d20 with a floor.
- **Reproduction:**
  1. Create a Rogue 7+ with Reliable Talent and proficiency in a skill.
  2. Tap the skill's advantage chip.
  3. Dice tab shows `1d20min10 + mod`, not `2d20kh1min10 + mod`.
- **Expected:** Two d20s are rolled, each floored at 10, and the higher is kept.  
- **Actual:** Only one d20 is rolled with floor 10.  
- **Suggested fix:** In `applyAdvantage`, treat d20 groups with `minimumValue` as still eligible for expansion, preserving the `minimumValue` on the expanded `2d20kh1/kl1` group. Alternatively, move advantage expansion into `ActionInterpreter` before the floor is applied.

### 7. Class skill choices do not count as proficiency for Reliable Talent
- **Severity:** Critical  
- **Area:** Rules / skill proficiency resolution  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Content/ActionInterpreter.swift`, `resolveSkillCheck(...)` (lines ~349–390)  
- **Description:** The skill-check resolver computes `isProficient` only from `character.proficiencies[.skill(skill)]`. Class skill selections are stored in `character.featureSelections` (keyed by a `class_skills` marker) and resolved live by `CharacterCalculator.skillProficiencyLevel`, but `ActionInterpreter` bypasses that. A character who gained proficiency via class skill choices therefore does not receive the Reliable Talent floor.
- **Reproduction:**
  1. Create a Rogue 7 with Perception chosen as a class skill.
  2. Ensure no stored `proficiencies[.skill(.perception)]` entry.
  3. Roll Perception with advantage.
  4. The formula lacks `min10`.
- **Expected:** Proficiency from class skill choice triggers the floor.  
- **Actual:** Floor is omitted.  
- **Suggested fix:** Use `CharacterCalculator.skillProficiencyLevel(character:skill:)` in `resolveSkillCheck` to determine proficiency/expertise.

---

## High-Priority Issues

### 8. `PendingRollStore.followUps` is not cleared on generic action taps
- **Severity:** High  
- **Area:** Cross-tab handoff / stale state  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/CharacterSheetView.swift`, `handleActionTap(_:)` (lines ~504–552) and `handleSpellRoll(_:followUp:)` (line ~558–563)  
- **Description:** `handleActionTap` sets `pendingRoll.pending` but never clears `pendingRoll.followUps`. `handleSpellRoll` also sets follow-ups without first clearing old ones. If a code path ever writes `pending` without consuming the old follow-ups first, stale chips can appear on the dice tab.
- **Suggested fix:** Set `pendingRoll.followUps = []` at the start of every handoff, and only assign new follow-ups explicitly.

### 9. Level-up HP preview ignores feature-granted HP changes
- **Severity:** High  
- **Area:** Level-up / HP math  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/LevelUpSheet.swift`, `stagedSummary(gain:)` and `commit()` (lines ~145–165, ~214–231)  
- **Description:** The preview shows `maxHP + gain` where `gain = die + CON mod`. `commit()` also adds the delta from `featureHitPointBonus` (e.g., Draconic Resilience at level 3). The final max HP can be higher than previewed.
- **Suggested fix:** Compute the projected post-commit `maxHP` by running the same `featureHitPointBonus` diff logic in the preview, or display a note that feature bonuses may add extra HP.

### 10. Level-up only auto-applies proficiency grants, missing other feature effects
- **Severity:** High  
- **Area:** Level-up / feature grants  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/LevelUpSheet.swift`, `applyNewFeatureProficiencies(to:)` (lines ~235–254)  
- **Description:** The level-up sheet scans new features only for `grantsProficiencies`. It does not add new resources, spellbook entries, subclass features picked after level-up, or other automatic grants. A Wizard leveling up does not get new spells added; a subclass taken after leveling does not receive its proficiency grants.
- **Suggested fix:** Generalize level-up application to sync spell lists, resource pools, and all automatic grants, or prompt the user for new selections before committing.

### 11. Multiclass characters duplicate resources and do not merge spell slots
- **Severity:** High  
- **Area:** Multiclass / resources / slots  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Models/ResourceCalculator.swift`, `availableResources(...)` (lines ~40–154)  
- **Description:** `availableResources` appends one row per class entry without deduplicating by resource ID. Two Fighter/Barbarian multiclass entries both emit the same "Second Wind" / "Rage" pool, producing duplicate UI rows. Spell slots are also synthesized per class, so a Wizard/Cleric gets two separate slot pools instead of the 5e multiclass slot table.
- **Suggested fix:** Deduplicate feature resources by `definition.id` and implement the 5e multiclass spell-slot table.

### 12. `DiceSceneController.setDice(formula:)` misaligns values when unsupported kinds are skipped
- **Severity:** High  
- **Area:** 3D dice / formula alignment  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/DiceSceneController.swift`, `setDice(formula:)` (lines ~1932–1954)  
- **Description:** Unsupported groups are skipped but `formulaIndex` is still advanced by `group.count`. The returned values array is then shorter than the formula expects, and `DiceRoller.resultFrom` reads values out of sync with later groups.
- **Reproduction:** Build a formula containing an unsupported die kind interleaved with supported kinds (only reachable if the UI gate is bypassed or a new `DieKind` is added without 3D support).  
- **Suggested fix:** Either refuse to roll unsupported formulas, or keep a strict 1:1 mapping between formula slots and returned values (return dummy/zeroed entries for skipped slots).

### 13. Orphaned async continuation if `rollAllAsync` is re-entered
- **Severity:** High  
- **Area:** 3D dice / concurrency  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/DiceSceneController.swift`, `rollAllAsync()` and `rollAll(...)` (lines ~146–160, ~2082–2100)  
- **Description:** `currentRollId` is incremented but never read. If `rollAll` is invoked while a previous roll is still settling, the new callback overwrites the old one and the old `withCheckedContinuation` never resumes. The UI guards against this with `isRolling`, but the controller API does not.
- **Suggested fix:** Guard `rollAll`/`rethrowDice` with `isAwaitingRest`, or store the current roll ID and have `settleAllDice` only invoke the callback whose ID matches.

### 14. `applyStrokeOfLuck` only forces the first d20 group
- **Severity:** High  
- **Area:** Dice roller / Stroke of Luck  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/DiceRollerView.swift`, `applyStrokeOfLuck()` (lines ~268–279)  
- **Description:** The loop overrides dice values only for the first `DieKind.d20` group and then `break`s. If a formula contains multiple d20 groups (homebrew or future action types), only the first is forced to 20.
- **Suggested fix:** Remove the `break` and force every d20 group, or decide whether Stroke of Luck should apply to the attack die only and document/validate that assumption.

### 15. Weapon damage strings with inline modifiers are parsed incorrectly
- **Severity:** High  
- **Area:** Weapon damage / parser  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Content/ActionInterpreter.swift`, `parseDieString(_:modifier:)` (lines ~451–465)  
- **Description:** `parseDieString` only handles bare `NdM`. Any weapon damage string containing a modifier (e.g., `1d8+2`) silently produces an empty formula group and only the modifier is applied. The current SRD weapons use bare strings, but homebrew/imported content will break.
- **Suggested fix:** Route all weapon-damage die strings through `DiceFormulaParser`, which already handles modifiers and typed prefixes.

### 16. `resolveRawDamage` overwrites inline damage types in spell recipes
- **Severity:** High  
- **Area:** Spell damage / typed dice  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Content/ActionInterpreter.swift`, `resolveRawDamage(...)` (lines ~165–188)  
- **Description:** The function parses the recipe dice string (which may carry its own `[fire]` prefix) and then unconditionally calls `formula.applyDamageType(damageType)`. Any inline type is lost.
- **Suggested fix:** Only apply the recipe's damage type to groups that do not already have one, or merge types explicitly.

### 17. Multiple armors can be equipped, but only the first affects AC
- **Severity:** High  
- **Area:** Inventory / AC  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/CharacterSheetView.swift`, `equippedArmor` (lines ~831–839)  
- **Description:** The sheet iterates inventory and returns the first equipped non-shield armor. There is nothing preventing the player from equipping a second armor; the UI will silently use the first.
- **Suggested fix:** When equipping an armor, automatically unequip other armor items, or show a validation warning.

### 18. `CharacterActionDeriver.grantedActions` can produce duplicate `ForEach` IDs
- **Severity:** High  
- **Area:** Actions tab / SwiftUI identity  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Content/CharacterActionDeriver.swift`, `grantedActions(...)` (lines ~629–674)  
- **Description:** IDs are built as `"\(feature.id)_\(granted.name)"`. If a single feature lists the same granted action twice, or if two features share an ID, `ForEach` will crash at runtime with a duplicate identifier.
- **Suggested fix:** Append an index or ensure uniqueness; also validate content for duplicate granted-action names per feature.

### 19. `DiceRollerView` records an info-only handoff as a "character roll"
- **Severity:** High  
- **Area:** Cross-tab handoff  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/DiceRollerView.swift`, `consumePendingRollIfNeeded()` (lines ~460–481)  
- **Description:** `rollCameFromCharacterSheet` is set to `true` before the guard that returns for nil formulas. The next manual dice roll will therefore not clear `rollingCharacterID`, allowing Stroke of Luck to appear for unrelated manual rolls until the next real character roll.
- **Suggested fix:** Only set `rollCameFromCharacterSheet = true` when a formula is actually dispatched.

---

## Medium-Priority Issues

### 20. Content validator misses reference integrity and recipe coverage
- **Severity:** Medium  
- **Area:** Content import / validation  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Content/ContentValidator.swift`  
- **Description:** `ContentValidator` checks unique IDs and parseability of some dice strings, but does not validate:
  - Cross-references (spell IDs in item uses/grants, subclass IDs, feature IDs, condition IDs, resource IDs).
  - That `ActionRecipe` cases other than `.heal`/`.rawDamage` have valid dice strings.
  - Damage-type strings.
  - That `min` values are within `1...sides`.
  - Duplicate IDs across content categories.
- **Suggested fix:** Add reference-walking validation and cover all recipe types.

### 21. Imported malformed packs are silently ignored
- **Severity:** Medium  
- **Area:** Content import  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/State/ContentStore.swift`, `loadImportedPacks()` (lines ~250–266)  
- **Description:** If a file in `Documents/Content/` is not valid JSON or fails decode, it is skipped with no user-facing error. The user may believe the pack is active.
- **Suggested fix:** Surface a "Some imported packs could not be loaded" warning in Settings with the offending filename(s).

### 22. Corrupted character files are silently dropped
- **Severity:** Medium  
- **Area:** Persistence / data loss  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/State/CharacterStore.swift`, `load()` (lines ~160–185)  
- **Description:** During load, any character file that fails decode is removed from the manifest and discarded. There is no recovery or error banner.
- **Suggested fix:** Move unparseable files to a quarantine directory and show a banner listing affected characters.

### 23. `CharacterStore.binding(for:)` returns a stale character after deletion
- **Severity:** Medium  
- **Area:** Persistence / bindings  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/State/CharacterStore.swift`, `binding(for:)` (lines ~146–156)  
- **Description:** The `get` closure falls back to the captured `initial` value if `self` is nil or the character was deleted. A subsequent `set` would recreate the character with the stale snapshot.
- **Suggested fix:** Return `nil` from `binding(for:)` when the character no longer exists and handle the missing state in the view.

### 24. `Character.applyDamage` records only one death-save failure for hits while dying
- **Severity:** Medium  
- **Area:** Rules / death saves  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Models/Character.swift`, `applyDamage(_:)` (lines ~477–497)  
- **Description:** A hit on an unconscious creature from within 5 ft is an automatic critical, which causes two death-save failures. The app records one failure and relies on the player to tap the second manually.
- **Suggested fix:** Add a "Hit while unconscious (crit)" option that records two failures, or document the honor-system behavior clearly.

### 25. `DiceFormulaParser` finds `min` via substring search
- **Severity:** Medium  
- **Area:** Parser robustness  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Models/DiceFormulaParser.swift`, `parseModifiers(...)` (line ~190)  
- **Description:** `remaining.range(of: "min")` matches any occurrence of the substring. A contrived damage type name containing "min" could produce misleading errors; combining with the issue above, the parser is fragile.
- **Suggested fix:** Use a regex anchored to the end of the modifier suffix, or parse tokens in order.

### 26. `QuickRollOverlay` may roll before `attach` completes
- **Severity:** Medium  
- **Area:** 3D dice / lifecycle  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/QuickRollView.swift`, `roll()` (lines ~88–116)  
- **Description:** The overlay's `.task(id: request.id)` can fire `roll()` before `SceneKitView.makeUIView` has attached the controller to an `SCNView`. If that happens, `rollAllAsync`'s continuation will never resume because the rest-detection task is started by `attach`.
- **Suggested fix:** Ensure `attach` is complete before rolling, or start the rest-polling task lazily in `rollAll` if it is not already running.

### 27. Spell follow-up only pairs the first damage roll
- **Severity:** Medium  
- **Area:** Spells / follow-up rolls  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/SpellCastSheet.swift`, `followUp(for:)` (lines ~585–593)  
- **Description:** Only the first non-attack rollable recipe is surfaced as a follow-up. Spells with multiple damage components or attack rolls get incomplete follow-up chips.
- **Suggested fix:** Return all eligible follow-ups or implement a per-attack damage pairing strategy.

### 28. `SpellCastSheet` uses the first class's spellcasting ability for multiclass casters
- **Severity:** Medium  
- **Area:** Spells / multiclass  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/SpellCastSheet.swift`, `spellcastingAbility` (lines ~653–662)  
- **Description:** For a multiclass Wizard/Sorcerer, the sheet always uses the first class's ability.
- **Suggested fix:** Choose the ability based on the spell's source class or let the user pick.

### 29. Presets can be saved with empty or duplicate names
- **Severity:** Medium  
- **Area:** Presets / UX  
- **File:** `ROLLodex/ROLLodex/Features/DiceRoller/Views/SavePresetSheet.swift`  
- **Description:** Blank names fall back to the formula string, and duplicate names are allowed, making the preset row confusing.
- **Suggested fix:** Require a non-empty unique name or append a counter for duplicates.

### 30. `CharacterDraft.toCharacter()` hardcodes starting HP and omits background bonuses
- **Severity:** Medium  
- **Area:** Character creation / model  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Models/CharacterDraft.swift`, `toCharacter()` and `startingHP()` (lines ~190–229)  
- **Description:** `toCharacter()` returns a character with base scores only (no background ASI) and `startingHP()` is hardcoded to `10 + CON mod`. `CharacterListView.finalizeDraft(_:)` fixes this for normal creation, but any other caller of `toCharacter()` gets incorrect data.
- **Suggested fix:** Move the background-bonus and correct hit-die logic into `toCharacter()` so the draft is self-contained.

### 31. `InventoryView` weight counter ignores containers/carrying rules
- **Severity:** Medium  
- **Area:** Inventory  
- **File:** `ROLLodex/ROLLodex/Features/CharacterSheet/Views/InventoryView.swift`, `totalWeight` (line ~115)  
- **Description:** Weight is simply `sum(weight * qty)`. There is no encumbrance calculation or handling of items inside containers.
- **Suggested fix:** Add encumbrance thresholds or document that weight is informational only.

---

## Low-Priority / Polish Issues

32. **History row awkward optional check** — `HistorySheet.swift` uses `result.label?.isEmpty == false` with a force unwrap. Replace with a cleaner nil/coalescing expression.
33. **Implicitly unwrapped SceneKit properties** — `DiceSceneController` stores `scene!`, `cameraNode!`, `connectorContainer!`. If any public method is called before `attach`, the app crashes. Defensive optionals would be safer.
34. **D4/d100 magnifier picks an arbitrary visible face** — documented behavior, but the d4 magnifier may show a rotated digit.
35. **Delete-character 500 ms delay** — `CharacterSheetView.deleteCharacter()` waits an arbitrary half-second before deleting. This is brittle if the pop animation duration changes.
36. **`compactDisplayString` loses typed flat damage info** — it collapses typed flat modifiers into the untyped modifier for display, but the underlying formula remains correct.
37. **No confirmation before overwriting imported pack** — beyond the slug collision issue, even identical names overwrite without warning.
38. **History total color uses yellow for crit success** — consistent with tray, but in light mode the history row's white background makes yellow less readable.
39. **Tool proficiencies accept any string** — `ProficiencyKey.decode` returns `.tool(value)` without validating against a known tool list.
40. **Dice picker badge counts all dice of a kind** — if the formula has `[fire]1d6 + [cold]1d6`, the badge shows 2, but long-press only removes from the first group.

---

## Edge-Case Test Cases to Verify on Simulator/Device

### Dice Roller / Physics
1. Roll `1d20kh1min10` and `1d20kl1min10` — parser should accept both; currently both fail.
2. Roll a skill check with advantage on a Rogue 7+ with Reliable Talent — expect two d20s each floored at 10, keep highest. Currently only one d20 is rolled.
3. Roll `2d20kh1+5` from history after clearing history — ensure no crash and correct behavior.
4. Tap Stroke of Luck after rolling a second unrelated roll — verify history integrity.
5. Roll a d100 with a reroll modifier (`1d100r5`) and verify it re-rolls both physical dice.
6. Fill the tray with the maximum number of dice and repeatedly roll; watch for orphaned continuations or hangs.
7. Long-press the d4/d10 die picker to remove dice while physics is settling.

### Character Sheet / Actions
8. Tap Rage (or any resource-cost action), then switch to Settings tab and back without rolling — verify whether the charge is consumed.
9. Create a Barbarian, level up to 3 without choosing a subclass, then pick Berserker in Features — verify subclass HP/proficiencies retroactively apply.
10. Create a Wizard/Cleric multiclass — verify slot UI shows merged slots, not two independent pools.
11. Equip two suits of armor — verify AC calculation and consider warning the user.
12. Create a Rogue with class skill Perception but no stored skill proficiency — roll Perception with advantage and inspect the formula for `min10`.
13. Cast a leveled innate species spell with the free-cast pool empty — verify the slot picker correctly disables/enables levels.
14. Cast a concentration spell while already concentrating — verify the swap alert and that the prior spell's rider is removed.

### Persistence / Import
15. Corrupt one bundled JSON file (dev build only) and launch — verify graceful handling vs. crash.
16. Import two packs named "Pack 1" and "Pack!1" — verify collision/overwrite behavior.
17. Delete a character from the list, then quickly open it from a stale `NavigationLink` — verify no zombie recreation.
18. Long-rest a character with a roll-based resource refresh (e.g., Wand of Magic Missiles) — verify the refresh sheet appears and the rolled amount is clamped to max.

### Creation / Level-Up
19. Create a Wizard, then a Fighter, and compare starting HP — verify hit die is respected.
20. Use point buy, switch to rolled method, then back to point buy — verify no stale assignments block creation.
21. Level up a Sorcerer with Draconic Resilience — verify HP preview matches final max HP.

---

## Recommendations by Area

### Dice Roller
- Move advantage expansion into the interpreter so it composes cleanly with `minimumValue` floors.
- Fix `min` parsing to allow `kh`/`kl`/`dh`/`dl` + `min` combinations.
- Make Stroke of Luck history replacement id-based.
- Add a guard in `DiceSceneController` against re-entrant `rollAll` calls.

### Character Sheet / Actions
- Defer resource consumption until the dice tab actually rolls (or add a rollback if the dice tab is dismissed without rolling).
- Always clear `pendingRoll.followUps` at the start of every handoff.
- Use `CharacterCalculator.skillProficiencyLevel` in `ActionInterpreter.resolveSkillCheck`.
- Prevent equipping multiple armors or surface a warning.

### Level-Up
- Apply all new feature effects (spells, resources, proficiencies) at commit time, not just proficiencies.
- Compute the true projected max HP including feature HP deltas before showing the preview.
- Prompt for subclass selection at the level it becomes available rather than relying on post-level Features-tab edits.

### Stores / Persistence
- Replace `fatalError` in `ContentStore` with a recoverable error path.
- Make imported pack filenames unique to prevent silent overwrites.
- Quarantine corrupted character files instead of deleting them.
- Validate cross-references and all action-recipe types in `ContentValidator`.

### Multiclass (future-facing)
- Deduplicate feature resources by ID.
- Implement the 5e multiclass spell-slot table.
- Resolve spellcasting ability per class/source.

---

*End of audit.*
