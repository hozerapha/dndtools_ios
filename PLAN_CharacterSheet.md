# ROLLodex — Character Sheet Implementation Plan

> Detailed plan for the multi-character D&D 5.2.1 (5.5e SRD) character manager.
> This document replaces the Character Sheet section of `PLAN.md` with granular, implementation-ready phases.

---

## Locked-In Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Action recipes** | Data-driven tagged enums in JSON | Homebrew works automatically. v1 primitives: `weaponAttack`, `weaponDamage`, `abilityCheck`, `skillCheck`, `savingThrow`, `saveDC`. |
| **Content packs** | Category-split JSON (`weapons.json`, `classes.json`, etc.) in bundle; import accepts `.zip` or single `.json` | Easy to maintain bundled SRD; users can share packs as zips. |
| **Character storage** | One JSON per character in `Documents/Characters/<uuid>.json` + `manifest.json` | Atomic writes, shareable, diff-able, future-proof for converters. |
| **Derived state** | Recompute at runtime from base scores + content definitions | No stale data when homebrew changes; JSON stays small and honest. |
| **Inventory** | Full inventory (weight, cost, quantity, categories) from v1 | Foundation for a full toolkit; action-bearing items are a subset. |
| **Dice handoff** | `PendingRollStore` carries `(label, formula, mode)`; Dice tab **prefills and waits** by default | User can add modifiers or change mind. Optional setting for auto-roll. |
| **Persistence** | CharacterStore → file system; HistoryStore/PresetStore stay on UserDefaults | Characters are documents; dice state is app state. |
| **Tests** | Swift Testing (`@Test`, `#expect`) for all pure model + interpreter logic | Follows existing convention. No XCTest. |
| **Resources (charges/uses/slots)** | Defined inline on the owning feature/item; character JSON only stores `{ resourceID: { current: Int } }` | One mental model for Second Wind, item charges, spell slots. Definitions move with the content that owns them; per-character state stays minimal and survives content edits. |
| **Spell slots** | Modeled as resources (one per class+level, e.g. `wizard_slot_l3`); rendered with bespoke "slots row" UI | Re-uses the rest cycle, the roll-resolution prompt, and persistence. UI layer can still group slots together without the data being a separate type. |
| **Roll resolution mode** | Global default in Settings (`manual` / `tray` / `behindTheScenes`) with a per-prompt override | Supports physical-dice tables, virtual-roll fans, and speed-runners in the same app. One `RollPrompt` view used by every random outcome (rest refresh, healing, hit dice, item charge regen). |
| **Rest cycle** | User-triggered via a "Rest" button on the sheet (no auto-detect) | Predictable. Walks every resource the character has access to and refreshes whatever matches the trigger. Roll-typed refreshes go through the resolution prompt. |
| **Action recipe composition** | Recipes are sequences of effects, not single rolls | A feature like Second Wind is `[consumeResource, heal]`. Lets us model upcasting, multi-die spells, item charges + spell access, all without bespoke types per case. |

---

## Project Structure ( additions )

```
ROLLodex/ROLLodex/
  App/
    RootView.swift              # Add Characters tab; inject new stores
  Features/
    CharacterSheet/
      Models/                   # Pure Swift, no UI imports
        Character.swift, Ability.swift, Skill.swift, ProficiencyLevel.swift,
        ProficiencyKey.swift, InventoryItem.swift, Currency.swift,
        CharacterCalculator.swift
      Content/                  # Content definitions (pure Swift models)
        ClassDefinition.swift, SpeciesDefinition.swift, BackgroundDefinition.swift,
        FeatureDefinition.swift, ItemDefinition.swift, WeaponDefinition.swift,
        ArmorDefinition.swift, WeaponProperty.swift, WeaponMastery.swift,
        ActionRecipe.swift, ResolvedAction.swift
      State/                    # @Observable stores
        ContentStore.swift, CharacterStore.swift, PendingRollStore.swift
      Views/
        CharacterListView.swift, CharacterCreationView.swift,
        CharacterSheetView.swift, ActionButtonGrid.swift, AbilityBlockView.swift,
        SkillListView.swift, InventoryView.swift, EquipmentDetailView.swift
      Resources/Content/        # Bundled SRD JSON files
        classes.json, species.json, backgrounds.json, weapons.json, armor.json, gear.json
    DiceRoller/Views/DiceRollerView.swift   # Observe PendingRollStore
  ROLLodexApp.swift
```

---

## Content JSON Schemas

Bundled and imported content packs use these schemas. Each file is an array of objects.

### `classes.json`
```json
[
  {
    "id": "fighter",
    "name": "Fighter",
    "hitDie": "d10",
    "primaryAbility": "strength",
    "savingThrows": ["strength", "constitution"],
    "armorProficiencies": ["light", "medium", "heavy", "shield"],
    "weaponProficiencies": ["simple", "martial"],
    "levelFeatures": {
      "1": [
        { "id": "fighting_style", "name": "Fighting Style", "description": "...", "actionRecipes": [] },
        {
          "id": "second_wind", "name": "Second Wind", "description": "...",
          "actionRecipes": [ { "type": "heal", "dice": "1d10", "addLevel": true, "label": "Second Wind" } ]
        }
      ]
    },
    "masteryCount": 3,
    "masteryRestrictions": []
  }
]
```

### `species.json`
```json
[
  { "id": "human", "name": "Human", "size": "medium", "speed": 30,
    "traits": [ { "id": "resourceful", "name": "Resourceful", "description": "...", "actionRecipes": [] } ] }
]
```

### `backgrounds.json`
```json
[
  { "id": "soldier", "name": "Soldier",
    "abilityScoreIncreases": { "strength": 2, "constitution": 1 },
    "skillProficiencies": ["athletics", "intimidation"],
    "feat": "savage_attacker", "toolProficiency": "gaming_set",
    "equipment": ["common_clothes", "insignia_of_rank", "gaming_set"] }
]
```

### `weapons.json`
```json
[
  { "id": "longsword", "name": "Longsword", "category": "weapon", "cost": 1500, "weight": 3.0,
    "weaponCategory": "martial", "damage": "1d8", "damageType": "slashing", "damageAbility": "strength",
    "properties": ["versatile"], "versatileDamage": "1d10", "masteryProperty": "sap",
    "actionRecipes": [
      { "type": "weaponAttack", "finesse": false, "label": "Longsword Attack" },
      { "type": "weaponDamage", "label": "Longsword Damage" }
    ] }
]
```

### `armor.json`
```json
[
  { "id": "chain_mail", "name": "Chain Mail", "category": "armor", "cost": 7500, "weight": 55.0,
    "armorCategory": "heavy", "acBase": 16, "dexCap": null, "stealthDisadvantage": true, "strengthRequirement": 13 }
]
```

### `gear.json`
```json
[
  { "id": "backpack", "name": "Backpack", "category": "adventuring_gear", "cost": 200, "weight": 5.0 }
]
```

---

## Character JSON Schema

Stored at `Documents/Characters/<uuid>.json`. Recomputed at runtime — no derived caches.

```json
{
  "id": "uuid-string",
  "name": "Bruenor",
  "level": 1,
  "speciesID": "dwarf",
  "backgroundID": "soldier",
  "classID": "fighter",
  "abilityScores": { "strength": 16, "dexterity": 12, "constitution": 14, "intelligence": 10, "wisdom": 13, "charisma": 8 },
  "maxHP": 12, "currentHP": 12, "tempHP": 0,
  "proficiencies": {
    "savingThrow_strength": "proficient", "savingThrow_constitution": "proficient",
    "skill_athletics": "proficient", "skill_intimidation": "proficient",
    "armor_heavy": "proficient", "armor_shield": "proficient", "weapon_martial": "proficient"
  },
  "inventory": [
    { "itemID": "longsword", "quantity": 1, "equipped": true, "attuned": false },
    { "itemID": "chain_mail", "quantity": 1, "equipped": true, "attuned": false },
    { "itemID": "healing_potion", "quantity": 3, "equipped": false, "attuned": false }
  ],
  "currency": { "cp": 0, "sp": 0, "ep": 0, "gp": 15, "pp": 0 },
  "notes": "",
  "manifestVersion": 1
}
```

---

## Swift Model Specifications

### `ActionRecipe` (tagged enum, Codable)

```swift
enum ActionRecipe: Codable, Equatable {
    case weaponAttack(abilityOverride: Ability?, finesse: Bool)
    case weaponDamage(dieOverride: String?, addAbility: Bool, versatile: Bool)
    case abilityCheck(ability: Ability)
    case skillCheck(skill: Skill)
    case savingThrow(ability: Ability)
    case saveDC(ability: Ability)
    case heal(dice: String, addLevel: Bool, label: String)
}
```

Custom `init(from decoder:)` decodes the `"type"` discriminator key.

### `ResolvedAction`

```swift
struct ResolvedAction: Identifiable, Equatable {
    let id: String          // composite: "weapon_longsword_attack"
    let label: String       // "Longsword Attack +5"
    let formula: DiceFormula?   // nil for saveDC, info-only features
    let mode: RollMode?     // one-shot overrides (e.g. advantage from feature)
    let description: String?    // "1d20 + STR (+3) + Prof (+2)"
}
```

### `CharacterCalculator` (pure functions, no UI)

Key functions: `abilityModifier(score:)`, `proficiencyBonus(level:)`, `skillModifier(character:content:skill:)`, `saveBonus(character:content:ability:)`, `armorClass(character:content:)`, `initiativeBonus(character:content:)`, `passivePerception(character:content:)`, `isProficient(character:key:)`, `resolveAction(recipe:character:content:)`.

---

## Phase Breakdown

All phases A–O are shipped. Terse trace below; see "Out-of-Scope Additions", the Phase O "Shipped reality" callout, and the Status table for details. The full original phase specs (deliverables, test lists, sub-step breakdowns) lived here historically and have been condensed — the schemas/models above plus the changelog capture the surviving contract.

- **Phase A — Domain Models & Content Schema** — shipped. Pure Swift types (Ability, Skill, ProficiencyLevel/Key, Currency, InventoryItem, Character), content definitions, `ActionRecipe`/`ResolvedAction`/`CharacterCalculator`/`ActionInterpreter`, test fixtures + Codable/calculator/interpreter tests.
- **Phase B — Content Loader** — shipped. `@Observable ContentStore` loads bundled SRD JSON (classes/species/backgrounds/weapons/armor/gear) into id-keyed dicts; injected at root.
- **Phase C — CharacterStore & File I/O** — shipped (atomic write via `Data.write(.atomic)`). Manifest + one JSON per character, create/save/delete/load round-trip, manifest tolerates orphans.
- **Phase D — Characters Tab & Creation Flow** — shipped. Characters tab, list with swipe-delete, multi-step creator (Name → Species → Background → Class → Ability Scores → Equipment → Review). `CharacterDraft` with point-buy validation.
- **Phase E — Read-Only Character Sheet** — shipped. Header (HP/AC/speed/init), ability block, skills, senses, proficiencies, inventory, features, all derived at runtime.
- **Phase F — Action Engine, Buttons, Dice Handoff** — shipped. `PendingRollStore`; sheet derives `[ResolvedAction]` grouped by category; tap → prefill dice tab (no auto-roll by default; `character.autoRoll.enabled` setting).
- **Phase G — Editing Characters** — shipped (death saves shipped 2026-06-09). Inline name/HP/notes edit, full inventory management (equip/attune/quantity), AC/actions update live.
- **Phase H — Custom Content Import / Export** — shipped 2026-06-13. `ContentPack` JSON envelope, `ContentValidator`, imported layer in `Documents/Content/` (imported shadows bundled by id), `ExportedCharacter` Transferable, Settings-tab import flows. `.zip` deferred (needs a zip dependency).
- **Phase I — Resources & Rest Cycle** — shipped. Generic `ResourceDefinition` (`LevelScaledValue` max, `RefreshTrigger`, `RefreshAmount`, `displayHint`) declared inline on features/items; character JSON stores only `current`. `ResourceCalculator`, rest cycle (short/long) with `RefreshResolutionSheet`, `RollResolutionMode` (manual/tray/behindTheScenes), `RollPrompt`, composable recipe effects (`consumeResource`, `prompt`) + `EffectRunner`. ResourcesView card + Rest button on sheet.
- **Phase J — Spells** — shipped (incl. `spellAttack` recipe + attack→damage follow-up chip). `SpellDefinition`, `spells.json`, `SpellcastingBlock` + `PreparedRule` on `ClassDefinition`, spell slots synthesized as resources (`<classID>_slot_<level>`; warlock pact slots short-rest), character spell lists (prepared/known/spellbook), `SpellCastSheet` cast/upcast flow, `SpellListView` (slots + spell list).
- **Phase K — Items With Charges & Spell Access** — shipped 2026-05-10 (Wand of Magic Missiles end-to-end). `ItemDefinition`/`Weapon`/`Armor` accept optional `resource` + `uses: [ItemUse]`; `ItemUseEffect.castSpell`/`.actionRecipes`; `ResourceCalculator` walks inventory and de-dupes pools by id; `CharacterActionDeriver` emits an "Item Uses" section routing `.castSpell` into `SpellCastSheet` with the item pool replacing the slot picker. Deviation: Wand needs no attunement (2024 SRD); attunement-gating code retained for the next attunement-required item.
- **Phase L — Conditions, Concentration, Action Economy** — shipped. 14 SRD conditions (`ConditionDefinition` + typed `effects`), concentration tracking (`Character.concentratingSpellID`), damage-triggered Con save (DC = `max(10, dmg/2)`), action-cost tags + grid grouping by economy. (Conditions are tracked but **not yet mechanically enforced** — see QA P1.)
- **Phase M — Choices & Multi-step Prompts** — shipped (architecture complete; Slices A+B+C). `FeatureSelection` + 4 `SelectionSource` cases (weapons/fixedOptions/subclasses/abilityScoreIncrease), `SubclassDefinition`, `ClassDefinition.resolvedFeatures` aggregator, `LevelUpSheet` (HP roll/average), ASI mutators with caps. **Still to author (not blocking):** more subclasses, sorcerer metamagic via `.fixedOptions`, ASI prompts on every class at L4/8/12/16/19, feat catalog + Origin/General feat picker. **Deferred architecture:** the recursive `ChoicePromptDefinition`/`ChoiceOutcome` model — pushed until a real nested-choice use case (e.g. Feat → "+1 ability" sub-prompt) needs it.
- **Phase N — Damage Typing in the Dice Tray** — shipped. `DiceGroup.damageType: DamageType?` (backwards-compat), `DiceFormula.applyDamageType`/`displayStringWithTypes`, `RollResult.subtotalsByType`, interpreter stamps weapon/raw damage types, upcast preserves type, `DamageBreakdownView`. **Known wart:** opening the formula-bar editor on a typed roll re-parses untyped text, losing the type (acceptable — typed rolls come from recipe dispatch, not bar edits).
- **Phase O — Triggered Effects & Active Statuses** — shipped (Slices A+B+C, 2026-05-17). Hex/Hunter's Mark (automatic riders), Sneak Attack (canonical `.optIn` chip), Rage (canonical `.toggle` rider, 10-round timer + per-LR resource). See "Phase O Shipped reality" below for the actual schema and **what's still open** (Divine Smite shipped 2026-06-09; Battle Master/superiority dice, GWM, attack-roll triggers, etc. remain).

> The deferred `ChoicePromptDefinition` / `ChoiceOutcome` recursive model from the original Phase M sketch (kinds `.pickOne`/`.pickN`/`.distribute`; recursive outcomes `.grantFeature`/`.grantProficiency`/`.grantSpell`/`.modifyAbilityScore`/`.spawnChoice`/`.composite`; `resolvedChoices` keyed character state) is **not yet built** — it lands only when a real nested-choice case needs it.

---

## Out-of-Scope Additions (shipped between phases)

Small changes that landed outside any single phase. One-line trace each.

- **Tabbed character sheet** — reshaped the single scroll into a fixed header + segmented 5-tab picker (Actions / Abilities / Features / Inventory / Spells). Spells tab hidden for non-casters (with an `onChange` guard). `navigationBarTitleDisplayMode = .inline`.
- **Bespoke `AttacksView`** — one row per equipped weapon (name + mastery chip + inline pill buttons 🎯/💧/2H), replacing per-recipe grid tiles. `CharacterActionDeriver.weaponAttacks(for:content:)` builds it; weapons no longer in `sections(...)`.
- **Attack → damage follow-up chip** — tapping a weapon/spell Attack queues the damage roll on `PendingRollStore.followUp`; dice tab shows a "Roll damage?" pill. One pattern for any primary+follow-up pair.
- **Weapon roll breakdowns + item descriptions in inventory** — expanded inventory row shows JSON `description` and (weapons) a `WeaponRollBreakdown` (attack/damage/2H lines via `CharacterCalculator.weaponRollBreakdown`, routed through the same `ActionInterpreter` as the dice handoff).
- **`WeaponMastery` display data** — added `displayName` + `summary` (SRD-style paragraph per property), surfaced in the mastery sheet + weapon picker.
- **Data-driven Features tab (partial Phase M)** — JSON-sourced feature/trait cards (name, source, kind chip, description, optional resource pool, selection picker). Schema: `FeatureKind` (passive/active/selection/toggle, auto-inferred when omitted), `FeatureSelection {id, prompt, count, optionsSource: SelectionSource}` (first case `.weapons(proficientOnly:)`), `Character.featureSelections: [String:[String]]` (migrates legacy `chosenWeaponMasteries`). Fighter L1 `weapon_mastery` is now a JSON feature with a selection block; `CharacterCalculator.weaponMasterySlotCount` reads the feature (legacy `masteryCount` parsed but unused). **Phase M still needs:** generalize `SelectionSource` (spells/skills/feats/ASI), nested choice prompts, a level-up-driven flow, versioned re-entry. Persistence + picker plumbing already exist.

---

## Phase O — Shipped reality (Slices A + B + C, 2026-05-17)

Actual schema in `Features/CharacterSheet/Content/TriggeredEffect.swift`:

```swift
struct TriggeredEffect: Codable, Equatable {
    let id: String
    let name: String
    let trigger: TriggerCondition
    let effect: TriggerEffect
    let lifecycle: TriggerLifecycle
    let activation: TriggerActivation   // default .automatic, omitted from JSON when default
    let cost: TriggerCost?
}

enum TriggerCondition: Equatable {
    case onDamageRoll(filter: AttackFilter?)   // Hex/Hunter's Mark = nil; Rage = melee filter
    case onAttackHit(filter: AttackFilter?)    // Sneak Attack
}

indirect enum AttackFilter: Equatable {
    case weaponHasProperty([WeaponProperty])    // Sneak Attack: [.finesse, .ammunition]
    case weaponLacksProperty([WeaponProperty])  // Rage: [.ammunition] (= melee)
    case anyOf([AttackFilter])
    case allOf([AttackFilter])
}

enum TriggerActivation: String, Codable {
    case automatic    // folds silently (Hex / Hunter's Mark)
    case optIn        // chip rail after the trigger (Sneak Attack)
    case toggle       // player flips on, stays on until lifecycle ends (Rage)
}

enum TriggerCost: Equatable {
    case oncePerTurn(flagID: String)   // Sneak Attack
}

enum TriggerEffect: Equatable {
    case addDamageDice(dice: String, damageType: TypedOrMatch)
    case addScaledDamageDice(count: LevelScaledValue, die: String, damageType: TypedOrMatch)
    case addFlatDamage(amount: LevelScaledValue, damageType: TypedOrMatch?)
}

enum TypedOrMatch: Equatable { case fixed(DamageType); case matchWeapon }  // JSON: "necrotic" or "$weapon"

enum TriggerLifecycle: Equatable {
    case persistent(until: PersistenceEnd)
    case oneShot
}

enum PersistenceEnd: Equatable {
    case concentrationEnds
    case rounds(_ count: Int)
    case manual
}
```

**Character state additions** (all backwards-compat — `decodeIfPresent` / encode-when-non-default):
- `Character.activeEffects: [ActiveEffect]`, `Character.turnFlags: Set<String>` + `setTurnFlag`/`hasTurnFlag`.
- `startNewTurn()` clears turn flags AND decrements `roundsRemaining`, dropping expired effects.
- `toggleFeatureEffect(effectID:featureID:roundsRemaining:)` (idempotent), `startConcentrating(on:grantsEffect:)` / `stopConcentrating()` / `dismissActiveEffect(_:)` (drops spell-sourced effects).
- `ActiveEffect { effectID, source: EffectSource, roundsRemaining: Int?, metadata: [String:Int] }`; `EffectSource` = `.spell`/`.feature`/`.item` (item stubbed).

**Resolver — `TriggeredEffectResolver` (MainActor):** `applyAutomaticDamageRiders(...)` folds `.automatic`+`.toggle` riders into in-flight damage; `optInRiders(...)` produces one merged-formula `PendingFollowUp` per qualifying `.optIn` rider (mutually exclusive with the default "Roll damage" chip); `turnFlagDisplayName(...)`; private `effectContext(...)` returns effect + owning class level so `byClassLevel` resolves per-class for multiclass.

**UI shipped:** `EffectsRow` (orange available-toggles stripe + purple active pills with `Nr` round badge, menu Description/Dismiss); deriver toggle row (`ToggleEffectContext`, label flips Rage/End Rage, tappable at 0 uses to end); `handleActionTap` diverts to toggle path; `ActionTile.isInteractive` includes `toggleEffect != nil`; `turnFlagsRow` is a turn tracker with Start New Turn; dice tab `followUpRail` (chip per `PendingFollowUp`, `compactDisplayString`, bolt vs arrow icons).

**Content authored:** `spells.json` Hex + Hunter's Mark; `classes.json` Rogue L1 Sneak Attack + Barbarian L1 Rage (+ descriptive Unarmored Defense).

**Tests:** `TriggeredEffectTests`, `SneakAttackOptInTests` (14), `RageToggleTests` (13), `DamageTypingTests`.

**Divergences from the original sketch — still potential work:**

| Sketch | Shipped | Notes |
|---|---|---|
| `TriggerActivation.toggleBeforeRoll` | `.toggle` (sticky on/off) | GWM's `-5/+10` pre-roll trade-off needs a separate per-turn-reset `.toggleBeforeRoll`. |
| `TriggerCondition.onAttackRoll(filter:)` | not shipped | Needed for GWM-style attack-roll penalties. |
| `TriggerCondition.onSpellAttackHit(filter:)` | folded into `.onDamageRoll` | Real spell-attack-hit triggers need a distinct condition. |
| `TriggerCondition.onTurnStart` | not shipped | Reserved for Rage's "do nothing → end"; honor-system Start New Turn used instead. |
| `AttackFilter.weaponCategory` / `.weaponDamageType` / `.hadAdvantage` / `.allyWithin5ft` | not shipped | Sneak Attack's "advantage OR ally within 5 ft" approximated by property filter alone; no trust/checkbox prompt. |
| `TriggerEffect.advantage` / `.disadvantage` / `.rerollOne` / `.attackPenalty` | not shipped | Reckless Attack, Halfling Lucky, GWM penalty need these. Resolver only folds into damage, not attack-mode/reroll. |
| `TriggerCost.spellSlot(minLevel:maxLevel:)` | **shipped 2026-06-09** | Divine Smite live. Lowest-available-slot policy; resolver concretizes cost to chosen level. Paired with `TriggerEffect.addSlotScaledDamageDice`. |
| `TriggerCost.resource(id:amount:)` | not shipped | Blocks Battle Master maneuvers / once-per-something-else costs. |
| `TypedOrMatch.matchSpell` | not shipped | Only matters for spell-sourced opt-in riders (Divine Smite +1d8 vs undead/fiend). |
| `PersistenceEnd.endOfTurn` / `.shortRest` / `.longRest` | not shipped | Current effects only use `.concentrationEnds`, `.rounds(_)`, `.manual`. |

---

## Integration with Existing Dice Roller

### What already exists
- `DiceFormula` + `RollMode` are the canonical inputs.
- `DiceRollerView` owns `@State var formula: DiceFormula` and `@State var mode: RollMode`.
- `PresetRowView` demonstrates programmatic formula replacement: `formula = preset.formula`.
- `HistoryStore` can receive `RollResult` after any roll.

### What we add
- `PendingRollStore` injected at root.
- `DiceRollerView` adds `@Environment(PendingRollStore.self) private var pendingRoll`.
- `DiceRollerView` adds `.onChange(of: pendingRoll.pending)` observer.
- When pending arrives: `formula = pending.formula; mode = pending.mode ?? .normal; pendingRoll.pending = nil`.
- `RootView` binds `TabView(selection:)` so `CharacterSheetView` can switch tabs.

### No changes needed to
- `DiceRoller.swift` (pure rolling logic)
- `Dice3DPlaygroundView.swift` / `DiceSceneController`
- `HistoryStore` or `PresetStore`

---

## SRD Content Reference (verified against SRD 5.2.1, 2026-06-13)

> Authoritative inventory from the actual SRD 5.2.1 PDF (CC-BY-4.0). The
> bundled core app must stay within this list; PHB / expansion content is
> importable-pack-only. **CC-BY attribution is mandatory** — the exact
> statement (see "Attribution" below) must appear in-app.

### Classes (12) and their ONE SRD subclass each
The SRD includes all 12 classes but exactly one subclass per class. Bundled
core content may use **only these subclasses**; any other subclass (Battle
Master, Eldritch Knight, Arcane Trickster, etc.) is PHB-only.

| Class | SRD subclass | Bundled? |
|---|---|---|
| Barbarian | Path of the Berserker | class ✓ / subclass ✗ |
| Bard | College of Lore | ✓ ✓ |
| Cleric | Life Domain | ✓ ✓ |
| Druid | Circle of the Land | ✗ |
| Fighter | Champion | ✓ ✓ |
| Monk | Warrior of the Open Hand | ✗ |
| Paladin | Oath of Devotion | class ✓ / subclass ✗ |
| Ranger | Hunter | ✗ |
| Rogue | Thief | ✓ ✓ |
| Sorcerer | Draconic Sorcery | ✓ ✓ |
| Warlock | Fiend Patron | ✗ |
| Wizard | Evoker | class ✓ / subclass ✗ |

### Classes (Level 1)
| Class | Hit Die | Primary | Saves | Armor | Weapons | Mastery |
|---|---|---|---|---|---|---|
| Barbarian | d12 | STR | STR, CON | Light, Medium, Shields | Simple, Martial | 2 melee |
| Bard | d8 | CHA | DEX, CHA | Light | Simple, Hand Xbow, Longsword, Rapier, Shortsword | — |
| Cleric | d8 | WIS | WIS, CHA | Light, Medium, Shields | Simple | — |
| Druid | d8 | WIS | INT, WIS | Light, Shields | Simple | — |
| Fighter | d10 | STR/DEX | STR, CON | Light, Medium, Heavy, Shields | Simple, Martial | 3 |
| Monk | d8 | DEX/WIS | STR, DEX | None | Simple, Martial (light) | — |
| Paladin | d10 | STR/CHA | WIS, CHA | Light, Medium, Heavy, Shields | Simple, Martial | 2 |
| Ranger | d10 | DEX/WIS | STR, DEX | Light, Medium, Shields | Simple, Martial | 2 |
| Rogue | d8 | DEX | DEX, INT | Light | Simple, Hand Xbow, Longsword, Rapier, Shortsword | 2 |
| Sorcerer | d6 | CHA | CON, CHA | None | Simple | — |
| Warlock | d8 | CHA | WIS, CHA | Light | Simple | — |
| Wizard | d6 | INT | INT, WIS | None | Daggers, Darts, Slings, Quarterstaff, Light Xbow | — |

### Species (9 in the SRD)
Dragonborn, Dwarf, Elf, Gnome, **Goliath**, Halfling, Human, Orc, Tiefling.
> The SRD has **Goliath, not Goblin**. **Shipped 2026-06-17: all 9 SRD species bundled + mechanically wired.**
>
> **Architecture:** a species trait IS a `FeatureDefinition` (`typealias TraitDefinition = FeatureDefinition`), so all class-feature machinery (pickers, resource pools, action rows) applies to species. `ResourceCalculator.availableResources`, `CharacterActionDeriver` (feature rows + granted actions), and `FeaturesView` all walk species traits.
> **Pickers (`.fixedOptions`, editable from Features tab):** Draconic Ancestry (10 dragons), Elven Lineage (Drow/High/Wood), Gnomish Lineage (Forest/Rock), Giant Ancestry (6 giants), Fiendish Legacy (Abyssal/Chthonic/Infernal).
> **Formulas / usable traits:** Dragonborn Breath Weapon (`ActionRecipe.scaledDamage`, 1d10→4d10 by level, PB-many uses/LR, typed via chosen ancestry); Orc Adrenaline Rush / Goliath Large Form / Dwarf Stonecunning (Bonus Actions w/ use pools). Elf gained the missing Elven Lineage; Dwarf Stonecunning rewritten to 5.2.1 Bonus-Action Tremorsense.
> **Lineage/legacy spell grants (shipped 2026-06-17):** `SpellGrant` (spellID + minCharacterLevel) on `SelectionOption` (choice-gated) and `FeatureDefinition` (flat); `CharacterSpellGrants.resolve` derives always-prepared spells live; `SpellListView` shows a level-gated "Granted" section (also for non-casters). Authored the 19 missing SRD lineage spells; content-lint asserts every granted id resolves.
> **Granted-spell casting (2026-06-17):** `CharacterSpellGrants.innateSpellcastingAbility` (explicit per-species INT/WIS/CHA picker via `<species>_spell_ability` selection, falling back to highest-mental) feeds `SpellCastSheet`; `ResourceCalculator` synthesizes a 1/LR `grant_<spellID>` pool for each leveled granted spell ("Cast free (Innate)"); cantrips stay at-will. Breath Weapon damage type stamped from `SelectionOption.damageType`.
> **Creation-wizard species pickers (2026-06-17):** `SpeciesChoicesStep` after Species selection for species with fixed-option choices; writes to `CharacterDraft.featureSelections`. Plain species skip it; switching species clears stale picks; picks stay optional/editable on Features tab. Added DEBUG-only "Autofill" on the Ability Scores step.
> **Giant Ancestry combat (2026-06-17):** `SelectionOption` carries per-option `grantedActions` + `triggeredEffect` (picked option only): Cloud's Jaunt (Bonus), Stone's Endurance (Reaction, new `ActionRecipe.abilityRoll` → 1d12+CON), Storm's Thunder (Reaction, 1d8 thunder) as granted-action rows; Fire's Burn (+1d10 fire) / Frost's Chill (+1d6 cold) as opt-in on-hit riders; Hill's Tumble descriptive.
>
> **Remaining nicety:** the giant benefits' "PB uses per Long Rest" limit isn't metered (actions/riders always available; player tracks uses) — a shared per-pick use pool spanning the granted-action + rider paths is a follow-up.

### Backgrounds (only 4 in the SRD)
Acolyte, Criminal, Sage, Soldier — all 4 bundled (Criminal added 2026-06-13; backgrounds SRD-complete).
> The earlier "16 backgrounds" list was the PHB roster, NOT the SRD. The bundled background feats (Savage Attacker, Magic Initiate) are SRD feats. (QA note: background feats/equipment not yet applied at creation — QA P3.)

### Weapon Mastery (8 properties)
Cleave, Graze, Nick, Push, Sap, Slow, Topple, Vex.

### Skills (18)
Acrobatics(DEX), Animal Handling(WIS), Arcana(INT), Athletics(STR), Deception(CHA), History(INT), Insight(WIS), Intimidation(CHA), Investigation(INT), Medicine(WIS), Nature(INT), Perception(WIS), Performance(CHA), Persuasion(CHA), Religion(INT), Sleight of Hand(DEX), Stealth(DEX), Survival(WIS).

### Attribution (MANDATORY — CC-BY-4.0)
Using SRD content **requires** displaying this exact statement in-app (it's the license condition). Home: Settings → About / Credits.

> This work includes material from the System Reference Document 5.2.1
> ("SRD 5.2.1") by Wizards of the Coast LLC, available at
> https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative
> Commons Attribution 4.0 International License, available at
> https://creativecommons.org/licenses/by/4.0/legalcode.

Per the license: do **not** add any other WotC attribution beyond the above, and don't imply endorsement. "Compatible with fifth edition" / "5E compatible" is permitted. (Shipped 2026-06-13 in Settings → Legal & Attribution; item 16.)

### Audit verdict (2026-06-13, updated 2026-06-27)
Bundle is SRD-clean at the inventory level: 8 classes (all SRD), 5 subclasses (Champion/Thief/Life Domain/College of Lore/Draconic Sorcery — exactly the SRD ones), 9 species (all SRD), 4 backgrounds (all 4 SRD), 43 spells (all SRD), all weapons/armor/conditions/gear, the 2 referenced feats. Attribution notice shipped. Description-text wording should track SRD phrasing (CC-licensed) — never PHB-exclusive wording.

---

## Testing Strategy

| Layer | What to test | How |
|---|---|---|
| **Models** | Codable round-trip for every type | Decode test fixtures, re-encode, assert equal |
| **Calculator** | Ability mods, proficiency bonus, AC, skill mods | Parameterized `@Test` with known inputs/outputs |
| **Interpreter** | ActionRecipe → ResolvedAction for all primitives | Create test character + content, assert formula string |
| **Store** | Save/load/delete round-trip, atomic writes, manifest recovery | Temporary directory, FileManager operations |
| **ContentStore** | Bundle decode succeeds, lookups work | Load from test bundle |

No UI tests in v1. Pure model + store tests only.

> **Test-coverage expansion (QA team, 2026-06-27 — committed):** 11 new test
> files landed in `ROLLodexTests/` (HistoryStore, PresetStore, PendingRollStore,
> DiceFormulaParserError, CharacterCreationFinalization, InventoryState,
> CharacterSpells, ContentStoreEdgeCase, RollResolutionMode, Currency,
> DamageTypeColor) plus updates to DiceRollerTests, CharacterStoreTests,
> DamageTypingTests, and the placeholder smoke test. No production code was
> changed by that pass — see `rollodex_tdd_summary.md`.

---

## QA Findings & Remediation Plan (2026-06-27)

Source reports in repo root: `rollodex_qa_audit.md` (static correctness audit,
40 items), `rollodex_ttrpg_playtest.md` (rules-fidelity playtest), and
`rollodex_tdd_summary.md` (test additions). The items below are **deduped and
merged** across the audit + playtest, prioritized, each with a concrete fix
approach that fits the existing architecture. Status legend: ☐ open · ◐ partial
· ✅ done. None are started yet unless marked.

### P0 — Correctness / data-integrity (do first)

- ✅ **Resource consumed before the roll resolves** (audit #2). *Fixed
  2026-06-27.* Riders pay at "Roll damage" time (rider refactor); rollable
  feature actions (Second Wind, etc.) now defer too — the cost rides the
  `ResolvedAction` to the dice tab and is parked on
  `PendingRollStore.pendingResourceCostsToApply` only when the roll fires (the
  sheet applies it). Tap-to-consume kept for no-formula actions (Action Surge)
  and toggles (Rage). `handleActionTap` guards an exhausted pool up front.
- ✅ **Stroke of Luck corrupts history** (audit #1, #14, #19). *Fixed
  2026-06-27.* The triggering roll is recorded lazily (not yet in history), so
  `applyStrokeOfLuck` just records the forced-20 result — dropped the bogus
  `history.removeFirst()`. Forces *every* d20 group (removed the `break`), and
  the rolling-character context is set only after the formula guard so info-only
  actions can't leak Stroke of Luck onto the next manual roll.
- ✅ **Bundled-content decode `fatalError` bricks launch** (audit #3). *Fixed
  2026-06-27.* `loadDictionary` records to `ContentStore.loadErrors` and returns
  empty instead of crashing; Settings shows a "Content Problems" warning when
  non-empty. (Imported-pack skip surfacing #21 + corrupt-character quarantine
  #22 still open.)
- ✅ **Imported packs silently overwrite on slug collision** (audit #4, #37).
  *Fixed 2026-06-27.* Filename = sanitized slug + a stable FNV-1a hash of the
  display name, so distinct names that sanitize alike stay distinct while the
  same name still overwrites (intended re-import). (Overwrite *confirmation*
  #37 still a nicety.)
- ✅ **`min` floor can't combine with keep/drop** (audit #5, #25). *Fixed
  2026-06-27:* `parseModifiers` now extracts the `minN` token wherever it sits
  (reads only the digit run after `min`) and parses the remainder as the
  group modifier, so `1d20kh1min10` and `1d20min10kh2` both parse.
- ✅ **Advantage silently dropped when Reliable Talent applies** (audit #6).
  *Fixed 2026-06-27:* this was really a symptom of #7 — `isPlain` ignores
  `minimumValue`, so advantage already expanded floored groups once the floor
  was actually set. Hardened anyway: advantage logic extracted into the pure,
  unit-tested `DiceFormula.applyingAdvantage(_:)` which provably preserves the
  floor on the expanded `2d20kh1min10` group.
- ✅ **Class-skill proficiency ignored for Reliable Talent** (audit #7).
  *Fixed 2026-06-27:* `resolveSkillCheck` now gates the floor via
  `CharacterCalculator.skillProficiencyLevel(character:skill:)` (the same
  content-free source of truth the skills table uses), so proficiency from a
  class-skill selection counts. This was the actual root cause behind #6.

### P1 — Rules fidelity that shows at the table (playtest priorities)

- ✅ **Critical hits don't double damage dice** (playtest #1). *Done 2026-06-27,
  configurable.* New **Settings page → Combat → "Natural 20 style"**
  (`@AppStorage` — the first general app preference). Crit handling is modeled
  composably (`CritRule` = dice mode × modifier multiplier) with named presets
  (`CritStyle`: Off / Double dice (RAW, default) / Double rolled value / Max die
  + roll / Maximize / Double total) — the foundation for a future custom editor,
  "like the dice formulas." `DiceFormula.applyingCrit(_:)` transforms the damage
  formula (incl. a new `diceResultMultiplier` honored by `RollResult` for the
  "double the rolled value" style); `DiceRollerView` applies it to the
  attack→damage follow-up when `lastResult.hasCriticalSuccess` (weapon + spell).
  *Remaining nicety:* a "Custom" style exposing the `CritRule` knobs directly.
- ☐ **Damage chip offered on a natural 1** (playtest #2). **Fix:** suppress the
  follow-up rail when `lastResult.hasCriticalFail`.
- ☐ **Choose-damage spells locked to fire** (playtest, audit-adjacent).
  Chromatic Orb / Dragon's Breath hard-code `fire`. **Fix (small):** give each a
  `rawDamage` recipe per allowed type and let the player pick; **(richer):** a
  damage-type picker in `SpellCastSheet`. Same mechanism would let
  Elemental Affinity / Transmuted Spell choose a type.
- ✅ **`resolveRawDamage` overwrites an inline `[type]` prefix** (audit #16).
  *Fixed 2026-06-27:* uses the new `DiceFormula.fillDamageType(_:)` (fills only
  untyped groups) instead of `applyDamageType`, so an inline `[type]` wins.
- ✅ **Weapon damage strings with inline modifiers mis-parse** (audit #15).
  *Fixed 2026-06-27:* `resolveWeaponDamage` now routes the dice string through
  `DiceFormulaParser` (handles `1d8+2` + typed prefixes), then fills the weapon
  type onto untyped groups. Unblocks homebrew/import.
- ☐ **Conditions tracked but not enforced** (playtest 3.5). `conditions.json`
  carries rich `effects` arrays nothing consumes. **Fix:** have
  `CharacterCalculator`/`ActionInterpreter` read `character.conditions` and apply
  advantage/disadvantage/auto-fail to attacks, saves, and skill checks
  (Poisoned → attack disadvantage, Restrained → DEX-save disadvantage, etc.).
  Also surface armor `stealthDisadvantage` on Stealth.
- ☐ **Fighting Styles: Great Weapon Fighting & Two-Weapon Fighting inert**
  (playtest 3.3). Archery/Dueling/Defense work. **Fix:** GWF rerolls 1s/2s on
  eligible two-handed damage dice; TWF adds the ability mod to off-hand damage —
  both in `ActionInterpreter` using existing weapon properties.
- ☐ **Weapon Mastery properties are display-only** (playtest 3.3). **Fix:** start
  with the tractable ones via the existing rider system — Vex (advantage on next
  attack after a hit), Graze (ability-mod damage on miss), Sap, Topple, Nick,
  Slow.
- ☐ **High-impact buff/debuff spells don't touch the sheet** (playtest 3.4).
  **Fix incrementally on existing systems:** False Life → set `tempHP`;
  Ray of Sickness/Hold Person/Fear/Charm Monster → apply the matching condition
  on cast (honor-system save); Shield/Bless/Shield of Faith → short-lived
  `activeEffects` modifying AC/attack once condition automation exists. Depends
  on the conditions-enforcement item above.

### P2 — High-priority engine / UX (audit #8–19)

- ✅ **`PendingRollStore.followUps` not cleared on every handoff** (audit #8).
  *Fixed 2026-06-27:* the dice tab clears both `followUps` and the new
  `pendingRiders` when it consumes a handoff, and the rider refactor below resets
  the local rail state on consume / manual edit / roll.
- ☐ **Level-up doesn't apply all new grants** (audit #10, playtest) — generalize
  commit to sync spells, resources, and subclass grants, not just proficiencies;
  prompt for subclass at the level it unlocks.
- ☐ **Level-up HP preview ignores feature HP delta** (audit #9) — run the
  `featureHitPointBonus` diff in the preview so it matches the committed max.
- ☐ **Multiclass: duplicate resources + unmerged slots** (audit #11, #28,
  playtest) — dedupe feature resources by `definition.id`; implement the 5e
  multiclass slot table; resolve spellcasting ability per source class.
- ☐ **`grantedActions` can produce duplicate `ForEach` IDs** (audit #18) — index
  the id and content-lint duplicate granted-action names per feature.
- ☐ **3D dice misalignment / re-entrant roll** (audit #12, #13, #26, #33) — keep
  a strict 1:1 formula-slot↔value mapping; guard `rollAll` against re-entry via
  the existing `currentRollId`; make `attach` precede `roll()`; defensive
  optionals on `DiceSceneController`.
- ☐ **Multiple armors equippable; only first counts** (audit #17) — auto-unequip
  other armor on equip, or warn.
- ☐ **Spell follow-up pairs only the first damage roll** (audit #27) — return all
  eligible follow-ups.

### P3 — Creation / content fidelity (playtest §3.2, audit #20, #30)

- ☐ **Background feats & equipment ignored at creation** — apply
  `backgrounds.json` `equipment` (items) + `feat` (proficiency/feat); if feats
  aren't modeled, surface a review-step note.
- ☐ **Starting spell seeding ignores class spell list** — add a `spellIDs`
  allow-list (or per-class list) so `seedStartingSpells` only grants
  class-appropriate spells; let prepared casters curate (Add Spell currently
  writes all three lists).
- ☐ **Species skill-choice traits not resolved** (Elf Keen Senses, etc.) — model
  as a `.fixedOptions`/skills selection recorded in `featureSelections`, like
  class skills.
- ☐ **`CharacterDraft.toCharacter()` hardcodes HP & omits background ASI** (audit
  #30) — fold the background-bonus + real hit-die logic into `toCharacter()` so
  the draft is self-contained (today only `finalizeDraft` is correct).
- ☐ **`ContentValidator` gaps** (audit #20) — validate cross-references (spell/
  subclass/feature/condition/resource IDs), all `ActionRecipe` dice types,
  damage-type strings, `min ∈ 1...sides`, and cross-category duplicate IDs.

### P4 — Medium / polish (audit #22–24, #29, #31, #32–40)

- ☐ Quarantine corrupt character files + banner (audit #22); `binding(for:)`
  returns stale character after deletion (audit #23).
- ☐ Death save: auto-crit (two failures) when hit at 0 HP (audit #24).
- ☐ Presets: require non-empty/unique names (audit #29).
- ☐ Inventory weight is informational — document or add encumbrance (audit #31).
- ☐ Polish bucket (audit #32–40): history optional-unwrap cleanup, d4/d100
  magnifier face, delete-character 500ms delay, typed-flat display rounding,
  tool-proficiency validation, dice-picker badge per-group removal, light-mode
  crit color contrast.

### Sequencing note
P0 first (data integrity / no lost charges / no launch crash), then P1 (table
credibility: crits, choose-damage, conditions, fighting styles). P1's
buff-spell item depends on the conditions-enforcement item, so do conditions
before wiring debuff spells. Several P0/P1 items (advantage+floor, class-skill
proficiency, raw-damage type, weapon-damage parsing) are small and localized to
`ActionInterpreter` + the parser — a good first batch.

---

## Status (as of 2026-06-27)

All phases A–O shipped. Key per-phase notes:

| Phase | Status |
|---|---|
| A–G (models, content loader, store, creation, sheet, action engine, editing) | shipped (death saves shipped 2026-06-09) |
| H — import / export | shipped 2026-06-13 (`ContentPack` envelope, `ContentValidator`, imported layer shadows bundled by id, `ExportedCharacter` Transferable, Settings tab; `.zip` deferred) |
| I — resources & rest cycle | shipped |
| J — spells | shipped (incl. `spellAttack` + attack→damage follow-up chip) |
| K — items with charges & spell access | shipped (Wand of Magic Missiles end-to-end) |
| L — conditions, concentration, action economy | shipped (14 SRD conditions tracked, **not yet enforced** — QA P1; concentration + damage Con save + action-cost chips) |
| M — choices & multi-step prompts | shipped (architecture complete, Slices A+B+C). Open: more subclasses, sorcerer metamagic, per-class ASI prompts, feat catalog; deferred `ChoicePromptDefinition` recursive model |
| N — damage typing in the dice tray | shipped. Known wart: formula-bar editor re-parses typed rolls as untyped (accepted) |
| O — triggered effects & active statuses | shipped (Slices A+B+C). See "Phase O Shipped reality" for open items (Divine Smite shipped 2026-06-09; Battle Master/superiority dice, GWM, attack-roll triggers still open) |

**Shipped changelog (reverse-chronological highlights; reusable infra in `code`):**
- **2026-06-27 — Structural P0 fixes.** Stroke of Luck records the forced-20 result without deleting an unrelated history entry + forces every d20 + no longer leaks onto manual rolls (audit #1/#14/#19); `ContentStore` degrades on bad bundled JSON via `loadErrors` (surfaced in Settings) instead of `fatalError` (#3); imported-pack filenames get a stable name-hash so distinct names don't collide (#4); rollable feature resource costs deferred to roll time via `PendingRollStore.pendingResourceCostsToApply` (#2 fully closed).
- **2026-06-27 — Expertise picker** locks skills already granted in another expertise selection (Rogue/Bard) via marker-driven `lockReason`.
- **2026-06-27 — Settings page + configurable Natural 20 crit, then stackable damage riders.** `@AppStorage`-backed Settings → Combat "Natural 20 style"; composable `CritRule` (dice mode × modifier multiplier) with presets via `CritStyle`; `DiceFormula.applyingCrit(_:)` + `diceResultMultiplier`. **Rider refactor:** opt-in riders (Sneak Attack, Divine Smite, Fire's Burn) now carry their OWN dice (`DamageRider`, via `TriggeredEffectResolver.optInRiders` + `DiceFormula.merging`) and surface as independent **toggles** in the dice tab — stack any combination onto one crit-aware damage roll, costs paid only at roll time (fixes audit #8, rider half of #2). `PendingRollStore.pendingRiders` carries them.
- **2026-06-27 — QA P0 quick batch.** Parser min+keep/drop, class-skill Reliable Talent floor, advantage+floor compose (`DiceFormula.applyingAdvantage`), weapon inline-modifier parsing, `fillDamageType`.
- **2026-06-27 — Sorcerer (8th class) + Draconic Sorcery (5th subclass), full L1–20.** Sorcery Points = level-scaled counter on Font of Magic (`surfacesAsAction:false`); Metamagic = `.fixedOptions` count 2→4→6; Dragon Wings = Bonus-Action pool. Mechanics pass added reusable infra (each fixed an existing descriptive feature):
  - `FeatureDefinition.unarmoredDefenseAbility` + `CharacterCalculator.unarmoredDefenseAbility` (no-armor AC = 10 + DEX + ability; also fixed Barbarian CON).
  - `FeatureDefinition.hitPointBonus` (flat/perLevel) folded into `rolledHP` at creation + level-up (diffed) via `CharacterCalculator.featureHitPointBonus`; also fixed Dwarven Toughness.
  - `CharacterSpellGrants.resolve` now walks class/subclass features (Draconic Spells always-prepared L3/5/7/9; 10 Draconic spells authored).
  - `TriggerCondition.whileActive` + `TriggerEffect.spellcastingBuff` (Innate Sorcery): toggle → `activeEffects` → `CharacterCalculator.spellcastingBuff`; `SpellCastSheet` shows Spell Save DC +1 and rolls spell attacks with Advantage while active.
  - *Still manual:* SP spending (Metamagic, slot conversion/creation), Sorcerous Restoration short-rest recovery; Summon Dragon stat block text; buff scope = all character spells (single-class assumption). *Edge:* swapping subclass via Features tab (not at level-up) doesn't retro-adjust HP — re-level/rebuild to resync.
- **Bard + College of Lore (4th subclass).** Introduced `ResourceDefinition.maxAbilityModifier` (pool size = ability modifier, min 1; for 2024 "uses = your X modifier" pools). **Jack of All Trades wired (2026-06-18):** half PB (round down) on non-proficient checks via `CharacterCalculator.skillModifier(..., jackOfAllTrades:)` + `hasJackOfAllTrades`; ½ chip on skills table, flows into checks + passive Perception. *Known simplifications:* Font of Inspiration short-rest recovery + Magical Secrets/Discoveries cross-list spells are descriptive.
- **2026-06-17 — Species 9/9 complete + mechanically wired** (see SRD Content Reference → Species).
- **2026-06-13 — Backgrounds 4/4 complete** (Criminal added). Player-chosen background ability bonuses (2024 distribute rule): `BackgroundDefinition.abilityScoreOptions`, `CharacterDraft.backgroundAbilityBonuses` + `isValidBackgroundBonus`, creation focused/balanced picker, `finalizeDraft` clamps to 20. **Class skill-proficiency choice:** new `SelectionSource.skillsFrom([Skill])`, per-class L1 "Skill Proficiencies" feature (`<class>_class_skills`; Rogue 4/10, others 2), resolved content-free by `CharacterCalculator.skillProficiencyLevel` via a `class_skills` marker; editable on Features tab + at creation. Tool-name display fix (`ToolNames`).
- **2026-06-13 — engine de-hardcoding (9a–9d):** `FeatureDefinition.skillCheckMinimum` + `CharacterCalculator.skillCheckFloor` (Reliable Talent); `FeatureDefinition.surfacesAsAction` (Stroke of Luck skip); `FeatureIDs` namespace (fighting style / mastery / expertise strings); `CharacterStore.lastSaveError` + sheet banner.
- **2026-06-13 — Actions tab unified** into one economy-grouped list (`ActionEconomyView`, was `GrantedActionsView`): interactive feature/item rows + granted options grouped by Action/Bonus/Reaction/Free/Movement. Weapon attacks keep bespoke `AttacksView`. `ActionButtonGrid.swift` now dead code (deletion candidate, kept per no-delete rule). New `GrantedAction {name, description?, cost, recipe?}` + `FeatureDefinition.grantedActions`; Cunning Action now declares Dash/Disengage (info) + Hide (rolls Stealth).
- **2026-06-13 — SRD attribution notice** in Settings → Legal & Attribution.
- **2026-06-13 — Phase H (import/export)** shipped (see Status row).
- **2026-06-13 — DiceRoller core unit tests** (`DiceRollerTests.swift`).
- **2026-06-10 — Cleric (6th class) + Life Domain.** First `preparedFromAll` caster. Channel Divinity short-rest resource; Divine Spark = heal + radiant recipes. Engine: `ActionRecipe.heal`/`.rawDamage` gained `addSpellcastingMod`; deriver passes owning class's casting stat. `ClericTests` (11).
- **2026-06-09 — Paladin (item 1+11b) + Divine Smite.** `TriggerCost.spellSlot(minLevel:maxLevel:)` + `TriggerEffect.addSlotScaledDamageDice`; `ResourceCalculator.lowestAvailableSlotLevel`/`consumeSpellSlot`; lowest-slot policy. *Deferred:* `TypedOrMatch.matchSpell` (+1d8 vs undead/fiend), pick-your-slot upcast UI, Aura of Protection / Radiant Strikes auto-riders. `DivineSmiteTests` (11).
- **2026-06-09 — HP retroactive recalc re-landed (v2 of reverted `131da6d`).** `Character.rolledHP` (die-only); `recalculateHP()` derives `maxHP = max(level, rolledHP + level × CON mod)`, shifts `currentHP` by delta; decode migration back-derives `rolledHP`; ASI mutators recalc on CON change; `setMaxHP(_:)` writes through `rolledHP`; creation seeds from real class hit die + post-ASI CON. *Accepted edge:* severe CON penalties enforce ≥1-HP/level as a total floor, not per-level. `HPRecalculationTests` + updated `LevelUpTests`. **Deletion UI** also shipped (context-menu + staged-confirmation swipe + toolbar overflow delete).
- **2026-06-09 — Death saves (Phase G).** `DeathSaveState` on `Character.deathSaves`; auto-reset on heal to positive; `applyDamage` at 0 HP records a failure. `DeathSavesRow` (header, 0 HP only), honor-system. `DeathSaveTests` (10).
- **2026-06-09 — Quick Roll mini tray.** `DiceSceneController` extracted to its own file (14a; `TrayFraming.standard`/`.compact`, tuned compact camera/physics/throw + fixed standard throw). `QuickRollView`/`QuickRollOverlay` (compact-framed 3D card, records to `HistoryStore`, `onResult` once). Adopted at death saves, level-up HP, concentration saves, refresh rolls. Weapon/check/save rolls keep the full-tray handoff. *Later (14d):* per-prompt roll-resolution preference (realizes Phase I.5 `RollPrompt`, absorbs open decision #8). *Still wanted:* Reduce Motion numbers-only fallback.
- **2026-06-09 — Ability score generation methods** (`AbilityScoreMethod`): Point Buy (default), Standard Array, Rolled (editable house formula via mini tray). `AbilityScoreMethodTests` (12).
- **2026-06-09 — code health fixes:** `CharacterStore.save` no longer re-reads disk; `load()` manifest-cleanup no longer rewrites on every launch (now atomic); `DiceSceneController` force-unwrap removed; `CharacterCalculator.abilityModifier` corrected to `score/2 - 5` (was truncating, off-by-one for odd scores < 10).
- **2026-06-09 — content lint (9e)** `ContentLintTests.swift` walks all bundled JSON (id uniqueness, dice parse, upcast bounds, byClassLevel reachability, item-use/spell resolution, subclass wiring). Phase H reuses these as the import validator.
- **2026-05-17 — Rogue & Barbarian full progression** (`65213dd`). Rogue L1–20 (Expertise, Sneak Attack scaling, Cunning Action, Uncanny Dodge, Evasion, Reliable Talent via `DiceGroup.minimumValue` + `1d20min10` parser, Slippery Mind via `grantsProficiencies`, Stroke of Luck reactive d20→20). Thief subclass (L3/9/13/17, Use Magic Device 4 attunement slots). Barbarian through L20. ~40 tests.

**Code-health debt still open** (each maps to "What's left" items):
- Backgrounds reference feats (`savage_attacker`, `magic_initiate_*`) that exist nowhere as content definitions (`backgrounds.json`; item 11g).
- `ContentStore` `fatalError`s on bad JSON — right for bundled, fatal for imports (also QA P0; `ContentStore.swift`).
- `ForEach(… id: \.offset)` on the level-up new-features list — fragile identity (`FeaturesView.swift`; item 13).
- Spell long-press "forget" still unconfirmed; no spell search/description preview in the add-spell picker (`SpellListView`; item 13).

**Verified-correct during the 2026-06-09 review (false alarms):** Stroke of Luck override loop is bounds-checked; `RefreshResolutionSheet` `rolls` cache resets per presentation; 5e math audit clean (prof bonus, save DC, spell attack, AC, concentration DC, level-up HP avg ≥1 clamp, Archery/Dueling gating, dice keep/drop/reroll/advantage, crit-on-kept-dice, multiclass `LevelScaledValue`).

**Deletion candidates** (zero references; flag only — deletions happen in Xcode by hand): `DiceTrayView.swift` (2D fallback) + `DieTokenView.swift` (only used by it); the `Dice3DPlaygroundView` *view struct* (controller already split out); `ClassDefinition.masteryCount`/`masteryRestrictions` (parsed, unused); `ActionButtonGrid.swift` (superseded by `ActionEconomyView`). **Keep:** `Character`'s legacy `chosenWeaponMasteries` CodingKey (migration path until a save-format bump).

## Open Decisions

1. **Tab layout:** 3D playground tab removed; legacy file kept for reference. (Resolved.)
2. **Character portrait:** placeholder shipped; camera/photo picker deferred.
3. **Death saves:** shipped 2026-06-09 as a header tracker row. (Resolved.)
4. **Multi-classing:** character JSON already stores `classEntries: [ClassEntry]`; multi-class UI + proficiency/slot reconciliation still open (lands with Phase M level-up flow; see QA P2 audit #11/#28).
5. **Resource ID collisions across packs:** imported ids shadow bundled by id (deliberate override). `<pack>.<id>` namespace still deferred; revisit only if different third-party packs collide. The importer/validator is the seam.
6. **Per-stack item charges:** two of the same wand share one pool. Revisit if a real case appears.
7. **`dawn` refresh trigger:** folded into long rest for now (K.5). Add a separate "advance time" button only if a use case demands it.
8. **Roll-prompt label matching:** when `RollResolutionMode == .tray`, the prompt waits for a matching label — exact-string vs ID-based contract still to nail down (absorbed by item 14d / Phase I.5 `RollPrompt`).

---

## What's left — cold-start hand-off

Live threads, ordered roughly by self-containment. The QA Findings section above is the current top priority; the items below are the longer-running feature threads.

**Phase O polish — visuals + content (small, parallelizable)**
- `EffectsRow` two-stripe layout: separate the orange "available toggles" from the purple "active" pills with a visual gap/divider (they jam together when both present).
- Chip-rail wording sweep: "Roll damage" / "Sneak Attack" / "End Rage" are inconsistent — converge on one verb pattern.
- Author two more `.toggle` features to prove the substrate generalises:
  - **Bless** (already a Phase J spell, lacks a triggered effect) — concentration buff +1d4 to attack rolls. Needs `TriggerCondition.onAttackRoll(filter:)` (NOT shipped) + `TriggerEffect.addAttackBonus(dice:)` (NOT shipped). Bigger lift.
  - **Reckless Attack** (Barbarian L2) — `.toggle`, advantage on STR melee + to attacks against you. Needs `TriggerEffect.advantage(target:)` (NOT shipped).

**Phase M open content debt (architecture done, catalog isn't)**
- Subclasses at the right level for every bundled class.
- ASI prompts at L4/L8/L12/L16/L19 for every class (only the shape exists; per-class wiring lands when each class is authored).
- Sorcerer metamagic *spending* (the picker uses `.fixedOptions`; SP spend is still manual).
- Feat catalog (Origin feats from backgrounds, General feats from ASI trade-ins). May force the deferred `ChoicePromptDefinition` / `ChoiceOutcome` recursive model if any feat carries sub-prompts.

**Bigger architectural threads that haven't started**
- **Initiative / combat tracker** (separate top-level feature; out of scope per PLAN.md).
- **Replace the "Start New Turn" honor-system button** with initiative-aware turn advancement once a tracker exists.
- **In-app content editor** — substantial UI; only worth it if hand-editing JSON starts to hurt.

**Test gaps (beyond content lint + DiceRoller core, both done)**
- `CharacterStore.load()` manifest-cleanup regression test (the every-launch rewrite bug).
- Spell-preparation rule enforcement (`PreparedRule`) once more casters land.

**Content authoring catalog — SRD 5.2.1 ONLY (JSON-only, no Swift). Goal: 100% of SRD 5.2.1 and nothing beyond it.**
- **Classes 8/12 done** (Fighter, Wizard, Rogue, Barbarian, Paladin, Cleric, Bard, Sorcerer). **Remaining: Druid, Monk, Ranger, Warlock** (one full class per turn).
- **Subclasses 5/12 done** (Champion, Thief, Life Domain, College of Lore, Draconic Sorcery). **Remaining SRD one-per-class:** Berserker, Circle of the Land, Warrior of the Open Hand, **Oath of Devotion** (Paladin), Hunter, Fiend Patron, **Evoker** (Wizard). NO Battle Master / EK / Arcane Trickster (PHB-only → importable pack only). New subclasses ship with their parent class.
- **Species 9/9 done ✅**, **Backgrounds 4/4 done ✅**, **Armor 8/8 ✅**, **conditions 14/14 ✅** (tracked, not yet enforced — QA P1), weapons + gear nearly complete, **43 spells** of the (large) SRD list.

Authoring order, each batch shippable alone:
- **11d. Weapons + gear sweep** — remaining ~22 SRD weapons (all have existing property/mastery vocabulary), standard adventuring gear.
- **11e. Spell batches** — all SRD cantrips, then L1, then L2–L3, gated per bundled caster class. **Prereq:** decide how class spell lists are encoded (per-spell `classes: [...]` vs per-class list) — the add-spell picker needs it to filter once the catalog grows. (Overlaps QA P3 "starting spell seeding".)
- **11f. ASI prompts audit** — Fighter currently has ASI at 4/13/19; SRD 5.2.1 Fighter gets 4/6/8/12/14/16/19. Audit every bundled class's ASI levels against the SRD while authoring.
- **11g. Feat catalog** — Origin feats first (backgrounds already reference `savage_attacker`, `magic_initiate_*` as dangling ids — flagged by the content lint). General feats need the ASI-vs-feat fork in `LevelUpSheet`; may force the deferred `ChoicePromptDefinition` recursive model (a feat granting a +1 ability sub-choice).
- **11h. More subclasses — SRD one-per-class ONLY** (Berserker, Circle of the Land, Warrior of the Open Hand, Oath of Devotion, Hunter, Fiend Patron, Evoker). Battle Master / Eldritch Knight / Arcane Trickster are PHB-only — importable pack only. (Battle Master's superiority dice still motivate `TriggerCost.resource(id:amount:)` as engine groundwork for the pack, not bundled content.)

**14d. Quick Roll polish (later)** — per-prompt "roll resolution" preference (mini tray / full tray / type manually); realizes Phase I.5's `RollPrompt` and absorbs open decision #8.

**UX + structure polish backlog (small, parallelizable)**
- Spell "forget" confirmation still open; empty-name guard on character rename.
- `.searchable` on the add-spell picker; spell-description preview without opening the cast sheet (long-press / info button).
- Attunement-cap feedback: tapping attune at 3/3 currently no-ops silently — show a brief explanation.
- Stable identity for the level-up new-features `ForEach` (use feature id, not `\.offset`).
- EffectsRow two-stripe divider + chip-rail wording sweep (also under Phase O polish).

### How to resume
In a new session, opening with "let's continue from PLAN_CharacterSheet's QA Findings (or 'What's left'), pick #N" is enough — every entry lists the files / schema cases / tests that would change. `git log --oneline -10` shows the recent shipping cadence; note `131da6d` (HP recalc) was reverted and re-landed 2026-06-09.

> This document is mutable. As new SRD / expansion content surfaces edge cases
> the schema doesn't cover, update the relevant section in place rather than
> spawning a parallel document.

---

## Appendix A — Exact Integration Points (Validated against codebase)

### A.1 RootView changes

```swift
enum Tab: String, Hashable { case dice, characters }

struct RootView: View {
    @State private var history = HistoryStore()
    @State private var presets = PresetStore()
    @State private var contentStore = ContentStore()
    @State private var characterStore = CharacterStore()
    @State private var pendingRollStore = PendingRollStore()
    @State private var selectedTab: Tab = .dice

    var body: some View {
        TabView(selection: $selectedTab) {
            DiceRollerView().tabItem { Label("Dice", systemImage: "dice") }.tag(Tab.dice)
            CharacterListView().tabItem { Label("Characters", systemImage: "person.2") }.tag(Tab.characters)
        }
        .environment(history).environment(presets).environment(contentStore)
        .environment(characterStore).environment(pendingRollStore)
    }
}
```

### A.2 DiceRollerView integration

`DiceRollerView` owns `@State var formula` + `@State var mode`. It already reseeds the tray on `formula` change:

```swift
.onChange(of: formula) { _, new in
    guard !isRolling else { return }
    controller.setDice(formula: new)
    lastResult = nil
    magnifyingDieIndices = []
}
```

Add one observer for `PendingRollStore` (existing `.onChange(of: formula)` seeds the tray; no changes to `DiceSceneController`, `DiceRoller`, or `HistoryStore`):

```swift
@Environment(PendingRollStore.self) private var pendingRoll

.onChange(of: pendingRoll.pending) { _, new in
    guard let resolved = new else { return }
    formula = resolved.formula ?? DiceFormula()
    mode = resolved.mode ?? .normal
    pendingRoll.pending = nil
}
```

### A.3 Auto-roll setting

```swift
@AppStorage("character.autoRoll.enabled") private var autoRollEnabled = false

// inside the .onChange(of: pendingRoll.pending) block:
if autoRollEnabled, resolved.formula != nil { Task { await roll() } }
```

### A.4 Tab layout note
The 3D playground tab has been removed from `RootView`; `Dice3DPlaygroundView.swift` is preserved for legacy reference.

### A.5 Test target
Add a **Unit Testing Bundle** target via Xcode (`File > New > Target > Unit Testing Bundle`) once before Phase A tests can run (the `.xcodeproj` isn't hand-edited). New test files in the synchronized group may need a quit-and-relaunch of Xcode to be detected.

---

## Appendix B — ActionRecipe → DiceFormula Examples

What `ActionInterpreter.resolve()` produces for common cases.

### Fighter with longsword (STR 16, +3 mod, proficient)
- **weaponAttack**: `DiceFormula(groups: [DiceGroup(kind: .d20, count: 1)], modifier: 5)` → "1d20 + 5"
- **weaponDamage**: `DiceFormula(groups: [DiceGroup(kind: .d8, count: 1)], modifier: 3)` → "1d8 + 3"
- **versatile damage**: `DiceFormula(groups: [DiceGroup(kind: .d10, count: 1)], modifier: 3)` → "1d10 + 3"

### Rogue with rapier (DEX 16, STR 10, proficient)
- **weaponAttack** (finesse): uses DEX mod (+3) because DEX > STR; modifier = 5 (3 + 2 prof).

### Skill check (Athletics, STR 16, proficient)
- **skillCheck**: modifier 5 → "1d20 + 5"

### Saving throw (Constitution, CON 14, proficient)
- **savingThrow**: modifier 4 → "1d20 + 4" (2 mod + 2 prof)

### Save DC display (Wizard, INT 16)
- **saveDC**: `formula = nil`, label = "Spell Save DC 13" (8 + 3 mod + 2 prof)

---

## Appendix C — Character JSON Future-Proofing

To avoid a breaking migration when multi-classing arrives, store class as an array even in v1:

```json
{ "classEntries": [ { "classID": "fighter", "level": 1 } ] }
```

```swift
struct ClassEntry: Codable, Equatable { let classID: String; let level: Int }

struct Character: Codable, Identifiable, Equatable {
    // ... other fields ...
    var classEntries: [ClassEntry]  // v1 always has exactly 1 element
}
```

`classID` is never a top-level string in the JSON. Same approach for species traits that grant choices — arrays with single elements in v1.

---

*End of plan.*
