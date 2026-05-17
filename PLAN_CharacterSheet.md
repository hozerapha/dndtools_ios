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
        Character.swift
        Ability.swift
        Skill.swift
        ProficiencyLevel.swift
        ProficiencyKey.swift
        InventoryItem.swift
        Currency.swift
        CharacterCalculator.swift   # Pure derived-value functions
      Content/                  # Content definitions (pure Swift models)
        ClassDefinition.swift
        SpeciesDefinition.swift
        BackgroundDefinition.swift
        FeatureDefinition.swift
        ItemDefinition.swift
        WeaponDefinition.swift
        ArmorDefinition.swift
        WeaponProperty.swift
        WeaponMastery.swift
        ActionRecipe.swift
        ResolvedAction.swift
      State/                    # @Observable stores
        ContentStore.swift      # Loads bundled + imported SRD content
        CharacterStore.swift    # Reads/writes character JSON files
        PendingRollStore.swift  # Cross-tab handoff queue
      Views/
        CharacterListView.swift
        CharacterCreationView.swift
        CharacterSheetView.swift
        ActionButtonGrid.swift  # Grouped action buttons on sheet
        AbilityBlockView.swift
        SkillListView.swift
        InventoryView.swift
        EquipmentDetailView.swift
      Resources/
        Content/                # Bundled SRD JSON files
          classes.json
          species.json
          backgrounds.json
          weapons.json
          armor.json
          gear.json
    DiceRoller/
      Views/
        DiceRollerView.swift    # Observe PendingRollStore
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
        {
          "id": "fighting_style",
          "name": "Fighting Style",
          "description": "...",
          "actionRecipes": []
        },
        {
          "id": "second_wind",
          "name": "Second Wind",
          "description": "...",
          "actionRecipes": [
            {
              "type": "heal",
              "dice": "1d10",
              "addLevel": true,
              "label": "Second Wind"
            }
          ]
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
  {
    "id": "human",
    "name": "Human",
    "size": "medium",
    "speed": 30,
    "traits": [
      {
        "id": "resourceful",
        "name": "Resourceful",
        "description": "...",
        "actionRecipes": []
      }
    ]
  }
]
```

### `backgrounds.json`
```json
[
  {
    "id": "soldier",
    "name": "Soldier",
    "abilityScoreIncreases": {
      "strength": 2,
      "constitution": 1
    },
    "skillProficiencies": ["athletics", "intimidation"],
    "feat": "savage_attacker",
    "toolProficiency": "gaming_set",
    "equipment": ["common_clothes", "insignia_of_rank", "gaming_set"]
  }
]
```

### `weapons.json`
```json
[
  {
    "id": "longsword",
    "name": "Longsword",
    "category": "weapon",
    "cost": 1500,
    "weight": 3.0,
    "weaponCategory": "martial",
    "damage": "1d8",
    "damageType": "slashing",
    "damageAbility": "strength",
    "properties": ["versatile"],
    "versatileDamage": "1d10",
    "masteryProperty": "sap",
    "actionRecipes": [
      {
        "type": "weaponAttack",
        "finesse": false,
        "label": "Longsword Attack"
      },
      {
        "type": "weaponDamage",
        "label": "Longsword Damage"
      }
    ]
  }
]
```

### `armor.json`
```json
[
  {
    "id": "chain_mail",
    "name": "Chain Mail",
    "category": "armor",
    "cost": 7500,
    "weight": 55.0,
    "armorCategory": "heavy",
    "acBase": 16,
    "dexCap": null,
    "stealthDisadvantage": true,
    "strengthRequirement": 13
  }
]
```

### `gear.json`
```json
[
  {
    "id": "backpack",
    "name": "Backpack",
    "category": "adventuring_gear",
    "cost": 200,
    "weight": 5.0
  }
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
  "abilityScores": {
    "strength": 16,
    "dexterity": 12,
    "constitution": 14,
    "intelligence": 10,
    "wisdom": 13,
    "charisma": 8
  },
  "maxHP": 12,
  "currentHP": 12,
  "tempHP": 0,
  "proficiencies": {
    "savingThrow_strength": "proficient",
    "savingThrow_constitution": "proficient",
    "skill_athletics": "proficient",
    "skill_intimidation": "proficient",
    "armor_heavy": "proficient",
    "armor_shield": "proficient",
    "weapon_martial": "proficient"
  },
  "inventory": [
    {
      "itemID": "longsword",
      "quantity": 1,
      "equipped": true,
      "attuned": false
    },
    {
      "itemID": "chain_mail",
      "quantity": 1,
      "equipped": true,
      "attuned": false
    },
    {
      "itemID": "healing_potion",
      "quantity": 3,
      "equipped": false,
      "attuned": false
    }
  ],
  "currency": {
    "cp": 0,
    "sp": 0,
    "ep": 0,
    "gp": 15,
    "pp": 0
  },
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
    // v1: heal has no dice impact, just displays. Included for schema completeness.
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

Key functions:
- `abilityModifier(score: Int) -> Int`
- `proficiencyBonus(level: Int) -> Int`
- `skillModifier(character:content:skill:) -> Int`
- `saveBonus(character:content:ability:) -> Int`
- `armorClass(character:content:) -> Int`
- `initiativeBonus(character:content:) -> Int`
- `passivePerception(character:content:) -> Int`
- `isProficient(character:key:) -> Bool`
- `resolveAction(recipe:character:content:) -> ResolvedAction`

---

## Phase Breakdown

### Phase A — Domain Models & Content Schema

**Goal:** All pure Swift types and JSON schemas. No UI, no I/O. Everything testable.

**A.1 Core character state**
- `Ability.swift` — enum `str, dex, con, int, wis, cha`. `modifier` computed property.
- `Skill.swift` — enum of 18 skills, each with `ability: Ability`.
- `ProficiencyLevel.swift` — `.none`, `.proficient`, `.expertise`.
- `ProficiencyKey.swift` — tagged enum for saves, skills, armor categories, weapon categories, tools.
- `Currency.swift` — cp, sp, ep, gp, pp.
- `InventoryItem.swift` — `itemID`, `quantity`, `equipped`, `attuned`.
- `Character.swift` — full schema matching JSON above. `Codable`, `Identifiable`, `Equatable`.

**A.2 Content definitions**
- `FeatureDefinition.swift` — `id`, `name`, `description`, `[ActionRecipe]`.
- `ClassDefinition.swift` — full class schema. `levelFeatures: [Int: [FeatureDefinition]]`.
- `SpeciesDefinition.swift` — `id`, `name`, `size`, `speed`, `[TraitDefinition]`.
- `BackgroundDefinition.swift` — `id`, `name`, `abilityScoreIncreases`, `skillProficiencies`, `featID`, `toolProficiency`, `equipment`.
- `ItemDefinition.swift` — base class for all items (or protocol if we want polymorphism). `id`, `name`, `description`, `cost`, `weight`, `category`.
- `WeaponDefinition.swift` — extends base: `damage`, `damageType`, `damageAbility`, `properties`, `versatileDamage`, `masteryProperty`, `actionRecipes`.
- `ArmorDefinition.swift` — extends base: `armorCategory`, `acBase`, `dexCap`, `stealthDisadvantage`, `strengthRequirement`.
- `WeaponProperty.swift` — `.finesse`, `.versatile(DieKind)`, `.thrown(range)`, `.twoHanded`, `.light`, `.heavy`, `.loading`, `.ammunition(range)`, `.reach`.
- `WeaponMastery.swift` — `.cleave`, `.graze`, `.nick`, `.push`, `.sap`, `.slow`, `.topple`, `.vex`.

**A.3 Action recipe system**
- `ActionRecipe.swift` — tagged enum with all v1 cases. Custom Codable for discriminator `"type"`.
- `ResolvedAction.swift` — output of the interpreter.
- `CharacterCalculator.swift` — pure functions for all derived values.
- `ActionInterpreter.swift` — `resolve(recipe:character:content:) -> ResolvedAction`. Handles finesse logic, proficiency checks, versatile toggles.

**A.4 Test fixtures**
- `Resources/TestFixtures/`:
  - `fighter.json` (class)
  - `human.json` (species)
  - `soldier.json` (background)
  - `longsword.json` (weapon)
  - `chain_mail.json` (armor)
  - `sample_character.json` (full character)

**A.5 Tests**
- Codable round-trip for every model.
- Decode every test fixture.
- `CharacterCalculator` tests: ability mods, proficiency bonus at levels 1–20.
- `ActionInterpreter` tests: fighter with longsword → attack formula `1d20+5`, damage `1d8+3`.
- Finesse test: rogue with rapier → attack uses DEX if higher.

**Deliverable:** All model files compile. All tests pass. No UI.

---

### Phase B — Content Loader

**Goal:** Load bundled SRD into memory at startup.

**B.1 Bundle content**
- `Resources/Content/`:
  - `classes.json` — all 12 classes, level 1 features only.
  - `species.json` — all 9 species.
  - `backgrounds.json` — all 16 backgrounds.
  - `weapons.json` — all SRD weapons with mastery properties.
  - `armor.json` — all SRD armor.
  - `gear.json` — basic adventuring gear.

**B.2 ContentStore**
- `@Observable ContentStore`:
  - `classes: [String: ClassDefinition]`
  - `species: [String: SpeciesDefinition]`
  - `backgrounds: [String: BackgroundDefinition]`
  - `weapons: [String: WeaponDefinition]`
  - `armor: [String: ArmorDefinition]`
  - `gear: [String: ItemDefinition]`
  - `allItems: [String: ItemDefinition]` (merged lookup)
- `init()` loads each JSON from `Bundle.main`. Build-time failure if decode fails.
- `func definition(forItemID: String) -> ItemDefinition?`
- `func weapon(forID: String) -> WeaponDefinition?`
- `func armor(forID: String) -> ArmorDefinition?`

**B.3 Environment injection**
- `RootView` instantiates `ContentStore()` as `@State`.
- Injected via `.environment(contentStore)`.

**Deliverable:** App launches. ContentStore is populated. No UI.

---

### Phase C — CharacterStore & File I/O

**Goal:** Read/write character JSON files atomically.

**C.1 File layout**
```
Documents/Characters/
  manifest.json
  <uuid-1>.json
  <uuid-2>.json
```

**C.2 Manifest**
- `CharacterManifest.swift` — `[String: CharacterMeta]`
- `CharacterMeta` — `lastEdited: Date`, `displayOrder: Int`

**C.3 CharacterStore**
- `@Observable CharacterStore`:
  - `private(set) var characters: [Character]` (ordered by manifest)
- `init()` reads manifest → loads each referenced file. Missing files removed from manifest.
- `create(_ draft: CharacterDraft) -> Character` — assigns UUID, atomic write, updates manifest.
- `save(_ character: Character)` — re-encodes, atomic write, updates manifest `lastEdited`.
- `delete(id:)` — removes file, updates manifest.
- `character(id:)` → `Character?`

**C.4 Atomic write helper**
```swift
func atomicWrite(_ data: Data, to url: URL) throws {
    let temp = url.appendingPathExtension("tmp")
    try data.write(to: temp)
    try FileManager.default.moveItem(at: temp, to: url)
}
```

**C.5 Tests**
- Save → load round-trip.
- Save mid-rename simulation → verify file integrity.
- Manifest tolerates orphaned entries.

**Deliverable:** Can programmatically create, save, load, delete characters. Tests pass.

---

### Phase D — Characters Tab & Creation Flow

**Goal:** New tab with list and step-by-step creator.

**D.1 RootView changes**
- Add `@State private var selectedTab: Tab = .dice` (enum `Tab`).
- Bind `TabView(selection: $selectedTab)`.
- Add `Characters` tab.
- Instantiate and inject `CharacterStore`, `ContentStore`, `PendingRollStore`.

**D.2 CharacterListView**
- `NavigationStack`.
- List rows: name, class/summary, level, species.
- Swipe-to-delete (calls `characterStore.delete`).
- "+" button opens `CharacterCreationView`.

**D.3 CharacterDraft**
- `CharacterDraft.swift` — mutable mirror of `Character` for creation.
- `var isComplete: Bool` — all required fields set.
- `var pointBuySpent: Int` — tracks ability score point cost.
- `var isValidPointBuy: Bool` — exactly 27 points, no score < 8 or > 15 before racial ASIs.

**D.4 CharacterCreationView** (multi-step `NavigationStack`)
1. **Name** — `TextField`, non-empty validation.
2. **Species** — list from `ContentStore.species`, detail row with traits summary.
3. **Background** — list from `ContentStore.backgrounds`, detail row with ASIs + skills + feat.
4. **Class** — list from `ContentStore.classes`, detail row with hit die + saves + proficiencies.
5. **Ability Scores** — point-buy only. Six rows with steppers (8–15). Running total. Preview of modifiers after racial ASIs applied.
6. **Equipment** — auto-assigned from background + class starting gear. Show summary, no choice in v1.
7. **Review** — full summary. "Create" button commits.

**D.5 Post-creation**
- On submit: `characterStore.create(draft.toCharacter())`.
- Dismiss creation flow, navigate to new character's sheet.

**Deliverable:** Can create a level 1 character through UI. List shows created characters.

---

### Phase E — Read-Only Character Sheet

**Goal:** Tap character → see full sheet. No editing, no actions yet.

**E.1 CharacterSheetView**
- Header: name, class badge, level badge, species. HP bar (current / max + temp). AC, speed, initiative.
- Ability block: 2×3 grid. Score, modifier, save bonus. Proficient saves highlighted.
- Skills section: collapsible. Sorted by ability then alphabetically. Total bonus, proficiency/expertise indicator.
- Senses: passive perception, darkvision range from species.
- Proficiencies: armor, weapons, tools (grouped lists).
- Inventory: equipped items at top, rest below. Weight total.
- Features: level-1 class features + species traits + background feat. Text only.

**E.2 Derived value engine**
- `CharacterCalculator` computes everything at runtime.
- AC calculation: base 10 + DEX mod, or armor base + min(DEX mod, dex cap), + shield if equipped.
- Weapon attack bonus: ability mod + proficiency if proficient in weapon category.
- Weapon damage: die + ability mod (if applicable).

**Deliverable:** Accurate read-only sheet for any character.

---

### Phase F — Action Engine, Buttons, and Dice Handoff

**Goal:** Buttons on the sheet prefill the Dice Roller.

**F.1 PendingRollStore**
```swift
@Observable class PendingRollStore {
    var pending: ResolvedAction?
}
```

**F.2 Action derivation**
- `CharacterSheetView` computes `[ResolvedAction]` from:
  - Equipped weapons: attack roll + damage roll per weapon.
  - All skills: skill check buttons.
  - All abilities: raw ability check + saving throw buttons.
  - Class features: any with `actionRecipes`.
- Grouped by category: Attacks, Checks, Saves, Features.

**F.3 Action buttons**
- `ActionButtonGrid.swift` — sectioned grid of buttons.
- Each button shows label + resolved bonus (e.g., "Longsword Attack +5").
- Weapon mastery shown as small badge (e.g., "Vex").
- Save DCs shown as info labels, not buttons.

**F.4 Dice handoff**
- Tap action → `pendingRollStore.pending = resolvedAction` → `selectedTab = .dice`.
- `DiceRollerView` observes `PendingRollStore`:
  - On `onAppear` + `onChange`: if `pending != nil`, set `formula = pending.formula`, `mode = pending.mode ?? .normal`, clear `pending`.
- Does **not** auto-roll (respects the setting; v1 default is off).

**F.5 Auto-roll setting**
- `SettingsStore` (or `@AppStorage`) key: `character.autoRoll.enabled`.
- If enabled, DiceRollerView also triggers `roll()` immediately after consuming the pending action.

**F.6 Tests**
- `ActionInterpreter` against fighter + longsword → expected formulas.
- Finesse weapon with DEX > STR → uses DEX mod.
- Non-proficient weapon → no proficiency bonus.

**Deliverable:** Tap "Longsword Attack" → Dice tab opens with `1d20+5` preloaded. Roll works.

---

### Phase G — Editing Characters

**Goal:** Round-trip edits, inventory management, HP tracking.

**G.1 Inline editing**
- Tap name → edit inline.
- Tap HP → `Stepper` or number pad for current/temp HP.
- Long-press ability score → manual override (rare, but needed for magic items).
- Notes field: editable `TextEditor`.

**G.2 Inventory management**
- `InventoryView` — full inventory list.
- Add items: search `ContentStore.allItems`, pick, set quantity.
- Equip/unequip toggle per item.
- Attune toggle (max 3 attuned).
- Delete items.
- Auto-update AC and actions when equipment changes.

**G.3 Death saves / conditions (optional v1.1)**
- Track death save successes/failures when currentHP ≤ 0.

**Deliverable:** Character sheet is fully editable. Inventory changes reflect immediately in actions and AC.

---

### Phase H — Custom Content Import / Export

> **Implementation note:** Hold this phase until **after Phases I–M** land. The
> import contract should ship against the stabilized content schema (resources,
> spells, item charges, conditions, choices). Shipping it earlier locks in a
> shape we'll have to migrate later — a recurring cost for every external pack.

**Goal:** Homebrew JSON and character sharing.

**H.1 Import content**
- Settings screen → "Import Content Pack".
- `UIDocumentPicker` for `.json` or `.zip`.
- Unzip if needed → validate each JSON file decodes into known content arrays.
- Copy valid files to `Documents/Content/`. Reject invalid with error sheet.
- `ContentStore.reload()` merges bundled + imported content (imported shadows bundled on ID collision).

**H.2 Character export**
- Share button on character sheet → `ShareLink` with character JSON.

**H.3 Character import**
- "Import Character" via document picker.
- Validate JSON → copy to `Documents/Characters/` → update manifest.

**Deliverable:** Users can share characters and import homebrew content packs.

---

### Phase I — Resources & Rest Cycle

**Goal:** Introduce a generic `Resource` primitive that backs every charge-based
mechanic in the system (Second Wind uses, Action Surge, Hit Dice, item charges,
spell slots). Add a rest cycle that refreshes resources on the appropriate
trigger. Add a single `RollPrompt` view that respects the user's resolution-mode
preference, used by every refresh roll and any future random outcome.

**I.1 Resource definition**

`ResourceDefinition.swift`:
- `id: String` — unique within content (`fighter_second_wind`, `wand_of_mm_charges`, …)
- `name: String` — display name on the sheet
- `max: LevelScaledValue`
- `refreshOn: RefreshTrigger`
- `refreshAmount: RefreshAmount`
- `displayHint: ResourceDisplayHint?` — optional UI grouping (e.g., `.spellSlot(level: 3)` so the spells UI can collect slot resources together)

`LevelScaledValue.swift` — the same sparse-table pattern used by `attunementSlotsByLevel`:
- `.flat(Int)`
- `.byClassLevel([Int: Int])` — applies to whichever class owns the resource; take highest key ≤ entry.level
- `.byCharacterLevel([Int: Int])` — applies to overall character level (rare; useful for racial features)

`RefreshTrigger.swift`: `.shortRest`, `.longRest`, `.dawn`, `.encounter`, `.never`. Anything refreshed by `.shortRest` *also* refreshes on long rest unless the rule explicitly opts out.

`RefreshAmount.swift` — tagged enum:
- `.all` — fill to max (e.g., spell slots on long rest, Second Wind on long rest)
- `.fixed(Int)` — exact amount (Second Wind on short rest = +1)
- `.byClassLevel([Int: Int])` — scaled (Hit Dice regen = half class level)
- `.roll(formula: String)` — refresh via dice roll (Wand of MM = `1d6+1`)

**I.2 Resource ownership**

Resources are declared inline on the entity that grants them — no central
registry, per the locked-in decision:

```swift
struct FeatureDefinition {
    var resource: ResourceDefinition?
}

struct ItemDefinition { /* + Weapon, Armor */
    var resource: ResourceDefinition?
}

struct ClassDefinition {
    var spellcasting: SpellcastingBlock?  // synthesizes spell-slot resources, see Phase J
}
```

The character JSON only stores `current` values:

```json
"resources": {
  "fighter_second_wind": { "current": 1 },
  "wand_of_mm_charges":  { "current": 5 }
}
```

If a referenced resource ID disappears from content (item deleted, class
removed), the entry is silently dropped on next save. If a new resource appears
the character has access to, it defaults to `current = max` until the next
rest. This keeps content edits non-destructive to character files.

**I.3 ResourceCalculator (pure, MainActor for content access)**

- `availableResources(character:content:) -> [ResolvedResource]` — every pool the character has access to right now, with computed `max`, `refreshOn`, etc.
- `current(character:resourceID:) -> Int` — clamped to `[0, max]`
- `consume(_ amount: Int, from resourceID:, in: inout Character) -> Bool` — returns whether consumption succeeded
- `applyRest(_ kind:, to: inout Character) -> [PendingRefresh]` — refreshes anything matching the trigger; returns pending dice rolls for the UI to resolve

`ResolvedResource`:
- `id`, `name`, `current`, `max`
- `refreshOn`, `refreshAmount`
- `sourceLabel: String` — "Fighter (L1)", "Wand of Magic Missiles", etc.
- `displayHint: ResourceDisplayHint?`

**I.4 Rest cycle**

`RestKind`: `.short`, `.long`.

Flow:
1. User taps "Rest" → action sheet picks short or long.
2. `applyRest` walks resources, builds `[PendingRefresh]` for any with `.roll(...)` amount.
3. If `pendingRefreshes` is empty: HUD confirmation, done.
4. Otherwise: `RefreshResolutionSheet` opens with one row per pending refresh. Each row has the user's roll-resolution mode prefilled, with a per-row override. User confirms; rolled values are applied; sheet dismisses.

Long rest also restores HP to max, clears temp HP, and resets death save state (when introduced in Phase L).

**I.5 RollResolutionMode + RollPrompt**

`RollResolutionMode.swift`:
- `.manual` — number-pad input for the user to type a result rolled IRL
- `.tray` — push the formula into the dice tab; wait for the result
- `.behindTheScenes` — `Int.random(in:…)` and use it directly

Stored in `@AppStorage("roll.resolution.default")`. Default `.tray` (matches the existing "prefill and wait" handoff for action buttons).

`RollPrompt.swift` — a SwiftUI view with:
- `formula: DiceFormula`
- `label: String`
- `onResolve: (Int) -> Void`

Renders the active mode and shows a "switch mode" button next to the formula so the user can deviate per-roll. Used everywhere a random outcome surfaces:
- Refresh rolls (Phase I)
- Healing from features like Second Wind (Phase I)
- Hit Dice spend on short rest (Phase I)
- Spell damage / healing (Phase J onward)

When the user has set `.tray`, the prompt holds open until a result arrives via `PendingRollStore` with a matching label. Manually closing the sheet cancels.

**I.6 Action recipe extensions**

Recipes become composable sequences of effects. Add to `ActionRecipe`:
- `consumeResource(resourceID: String, amount: Int)` — subtracts from a pool; if `current < amount`, the rest of the recipe sequence aborts.
- `prompt(steps: [PromptStep])` — multi-step UI for choices ("cast at level 1, 2, or 3"; each option carries its own consume + roll effects).

A feature like Second Wind becomes:

```json
"actionRecipes": [
  { "type": "consumeResource", "resourceID": "fighter_second_wind", "amount": 1 },
  { "type": "heal", "dice": "1d10", "addLevel": true, "label": "Second Wind" }
]
```

`ActionInterpreter.resolve` returns a `ResolvedAction` whose `effects: [ResolvedEffect]` describes the sequence. When tapped, a small `EffectRunner` executes them in order: applies `consumeResource` (mutates the character), hands roll-typed effects to `RollPrompt`, records the outcome to history with a composed label.

**I.7 Sheet integration**

- New `ResourcesView` card on the sheet, between `AbilityBlockView` and `ActionButtonGrid`. Shows all `ResolvedResource`s grouped by source, with `current / max` and `−` / `+` for ad-hoc adjustment (e.g., DM gives back a charge). Tapping the source name links to a detail showing the refresh rule.
- "Rest" button in the sheet's toolbar (or as a floating action). Opens the rest action sheet.
- `ActionButtonGrid` rows display the cost ("Second Wind · uses 1") and grey out when the resource is exhausted.

**I.8 Migration of existing content**

- Fighter `second_wind` feature gains a `resource` block: `max: { byClassLevel: { "1": 2, "4": 3, "10": 4 } }`, `refreshOn: shortRest`, `refreshAmount: fixed(1)`. Long rest implicitly refreshes to max. Recipe updated to consume the resource before healing.
- Action Surge, Hit Dice, Channel Divinity, Bardic Inspiration: same treatment.
- The existing `attunementSlots` field on `FeatureDefinition` stays — it's a different concept (informational, not consumable).

**I.9 Tests**

- `ResourceCalculator.availableResources` for a multi-class character.
- `applyRest` correctly fills `.all`, applies `.fixed`, defers `.roll`.
- `consume` clamps at zero, refuses overdraft.
- `EffectRunner` aborts subsequent effects when a `consumeResource` fails.
- `RollPrompt` round-trip for each mode (manual / tray / hidden) with a stub `PendingRollStore`.
- Backwards-compat: characters without a `resources` block decode and get `current = max` for every available resource.

**Deliverable:** A character can spend Second Wind, see the charge consumed, take a short rest, and see one charge restored. The "Rest" button surfaces refresh-roll prompts when relevant. The roll-resolution mode setting actually changes how rolls are resolved.

---

### Phase J — Spells

**Goal:** First-class spell support — definitions, slots (as resources),
prepared / known lists, casting flow, upcasting.

**J.1 Spell definition**

`SpellDefinition.swift`:
- `id`, `name`, `level: Int` (0 = cantrip)
- `school: SpellSchool` — abjuration, conjuration, etc.
- `castingTime: CastingTime` — `.action`, `.bonusAction`, `.reaction(trigger:)`, `.minutes(Int)`, `.ritual(Bool)`
- `range: SpellRange` — `.targetSelf`, `.touch`, `.feet(Int)`, `.unlimited` (avoiding `.self` since it's a Swift keyword)
- `components: SpellComponents` — `verbal`, `somatic`, `material(String?)`
- `duration: SpellDuration` — `.instantaneous`, `.rounds(Int)`, `.minutes(Int)`, `.concentration(maxMinutes: Int?)`
- `description: String`
- `higherLevel: String?` — text describing upcast effect
- `actionRecipes: [ActionRecipe]` — damage, healing, save DC, etc.
- `upcastEffect: UpcastEffect?` — typed scaling

`UpcastEffect`:
- `.extraDicePerLevel(damageRecipeIndex: Int, dice: String)` — Magic Missile adds 1d4+1 per level
- `.extraTargetsPerLevel(Int)` — informational
- `.scaledDice(baseLevel: Int, dicePerExtraLevel: String)` — generic

**J.2 Spell list JSON**

`spells.json` in the bundle. Initial seed: PHB SRD spells (cantrips + L1–L3 minimum, expand from there).

```json
{
  "id": "magic_missile",
  "name": "Magic Missile",
  "level": 1,
  "school": "evocation",
  "castingTime": { "type": "action" },
  "range": { "type": "feet", "value": 120 },
  "components": { "verbal": true, "somatic": true },
  "duration": { "type": "instantaneous" },
  "description": "...",
  "higherLevel": "When you cast this spell using a spell slot of 2nd level or higher, the spell creates one more dart for each slot level above 1st.",
  "actionRecipes": [
    { "type": "rawDamage", "dice": "3d4+3", "damageType": "force", "label": "Magic Missile darts" }
  ],
  "upcastEffect": { "type": "extraDicePerLevel", "damageRecipeIndex": 0, "dice": "1d4+1" }
}
```

**J.3 SpellcastingBlock on ClassDefinition**

```swift
struct SpellcastingBlock: Codable, Equatable {
    let ability: Ability                      // INT for wizard, WIS for cleric, …
    let preparedRule: PreparedRule
    let cantripsKnown: LevelScaledValue
    let spellsKnown: LevelScaledValue?        // nil if uses preparation
    let preparedCount: PreparedFormula?       // e.g., wizard = INT mod + class level
    let slotTable: SlotTable
    let ritualCasting: Bool
    let spellcastingFocus: Bool
}
```

`PreparedRule`:
- `.knownList` — bards, sorcerers, rangers (fixed known list, no daily prep)
- `.preparedFromBook` — wizards (prepare from spellbook each long rest)
- `.preparedFromAll` — clerics, druids, paladins (prepare from full class list)
- `.pactMagic` — warlocks (special slot rules)

**J.4 Spell slots as resources**

Each spell-slot level becomes its own `ResourceDefinition` synthesized from the
`SlotTable`. ID convention: `<classID>_slot_<level>` → `wizard_slot_3`. Pact
magic warlocks get a single `warlock_pact_slot` whose level scales by class level.

`SlotTable.swift`:
- `byClassLevel: [Int: [Int: Int]]` — class level → (spell level → slot count)
- `pactMagic: PactMagicTable?` — alt for warlocks (single slot level + count, both scaling)

The synthesizer:
- Refresh trigger: `.longRest` for full casters, `.shortRest` for warlock pact slots
- Refresh amount: `.all`
- `displayHint: .spellSlot(level: N)` so the spells UI can group them

**J.5 Character spell list**

```json
"spells": {
  "preparedIDs": ["magic_missile", "shield", "detect_magic"],
  "knownIDs": [],
  "spellbookIDs": ["magic_missile", "shield", "detect_magic", "feather_fall"]
}
```

Different classes use different lists (wizard reads `spellbookIDs` to populate
`prepared`; sorcerer's `knownIDs` is fixed; etc.). The `SpellListView`
understands the per-class rule.

**J.6 Cast flow**

Tap a spell:
1. `SpellCastSheet` opens with the spell text.
2. Slot-level picker (greyed-out levels with no remaining slots; user picks ≥ spell.level).
3. "Cast" button → consume one slot of the chosen level via `consumeResource`, then run the spell's `actionRecipes` through the `EffectRunner`. Damage / save prompts route through `RollPrompt`.

Cantrips skip the slot picker. Ritual casting offers an optional "Cast as ritual (no slot)" toggle when `ritualCasting && spell.castingTime.ritual`.

Concentration spells (Phase L) flip `Character.concentratingSpellID` and break any prior concentration.

**J.7 Spells UI**

New `SpellListView` on the sheet, after the inventory. Two sections:
- **Slots** (top): a row per spell level with `current / max` dots. Long-press a slot to manually toggle (DM correction).
- **Spells** (collapsible, by level): prepared / known list, sorted by level then name. Each row shows name, school icon, casting time, and a cast button.

Add a "+ Spells" button that opens a search picker over `ContentStore.spells`, filtered by the class spell list when the character has a spellcasting block.

**J.8 Tests**

- `SpellDefinition` Codable round-trip.
- `SlotTable` synthesizes the right resources for wizard L1, L5, L11.
- Warlock pact magic: short-rest refreshes pact slots; long-rest also refreshes them.
- `SpellCastSheet` flow: cast at base level vs. upcast → resource consumption + upcast scaling on the recipe.
- `PreparedRule` enforcement: wizard can't cast a spell that's not in `spellbookIDs`.

**Deliverable:** A wizard can prepare spells, see slots, cast at base level, upcast to consume a higher slot. Cantrips work without slot consumption. Slots refresh on long rest. Warlock pact slots refresh on short rest.

---

### Phase K — Items With Charges & Spell Access

**Goal:** Item JSON declares charges and grants spell access. Wand of Magic
Missiles works end-to-end.

**K.1 Item resource block**

Items already have an optional `attunement: AttunementRule?`. Add `resource: ResourceDefinition?`. Same shape as feature resources; ID is namespaced to the item (`<itemID>_charges` by convention) so a character carrying two of the same wand currently shares the pool. Per-stack charges deferred — track as a follow-up if a real case appears (rare in 5e RAW).

**K.2 ItemUse schema**

```swift
struct ItemUse: Codable, Equatable {
    let id: String
    let name: String
    let cost: ResourceCost
    let effect: ItemUseEffect    // .castSpell or .actionRecipes
    let upcastChoice: UpcastChoice?
}

enum ItemUseEffect: Codable {
    case castSpell(spellID: String, atLevel: Int)
    case actionRecipes([ActionRecipe])
}

struct UpcastChoice: Codable {
    let maxLevel: Int
    let extraCostPerLevel: Int   // additional charges per level above base
}
```

```json
"uses": [
  {
    "id": "cast_magic_missile",
    "name": "Cast Magic Missile",
    "cost": { "resourceID": "wand_of_mm_charges", "amount": 1 },
    "effect": { "type": "castSpell", "spellID": "magic_missile", "atLevel": 1 },
    "upcastChoice": { "maxLevel": 3, "extraCostPerLevel": 1 }
  }
]
```

**K.3 Inventory + action grid integration**

- Equipped items with `uses` contribute new rows to the action grid under an "Item Uses" section.
- The cost is shown next to the action ("Cast Magic Missile · 1 charge").
- Tap → if `upcastChoice`, prompt for level (uses the same `prompt` recipe step from I.6); otherwise execute directly.
- `ItemUseEffect.castSpell` chains into the spell-casting flow but consumes the item's resource instead of a spell slot.

**K.4 Resource enumeration**

`ResourceCalculator.availableResources` already walks features. Extend it to walk equipped items' `resource`. Carried-but-unequipped items are excluded from the action grid but still appear in the resources card so the user can spend them (e.g., consumable scrolls).

**K.5 `dawn` refresh handling**

`RestKind` doesn't include "dawn" (rest is user-action). For MVP, any `.dawn` refresh also fires on long rest — covers the common case. A separate "advance time" button can land later if needed.

**K.6 Tests**

- Wand of Magic Missiles JSON round-trips.
- Eligibility chain: attunement gates the item; once attuned, the use becomes available; once charges are spent, the use greys out.
- Upcast choice consumes the right number of charges and applies upcast scaling to the spell's recipe.
- `.dawn` refresh fires on long rest.

**Deliverable:** Equip and attune a Wand of Magic Missiles. Cast Magic Missile from the action grid; charges decrement; upcast to consume 2 or 3. Long-rest restores 1d6+1 charges through the roll-resolution prompt.

> **Shipped 2026-05-10.** Implemented as specified, with two deviations:
> - **Wand of Magic Missiles requires no attunement.** Per the 2024 SRD it's
>   freely usable; `attunement: {}` was dropped from `gear.json`. The
>   attunement-gating code in `ResourceCalculator.availableResources` stays
>   in place for the next attunement-required magic item.
> - **Item description shown in inventory.** Beyond the action grid wiring,
>   the inventory row's expanded edit panel now displays the item's
>   description text and (for weapons) a per-character formula breakdown so
>   the player can audit attack/damage numbers against the rules.
>
> Behavior delivered:
> - `ItemDefinition` / `WeaponDefinition` / `ArmorDefinition` accept optional
>   `resource: ResourceDefinition` and `uses: [ItemUse]`.
> - `ItemUseEffect` supports `.castSpell(spellID:atLevel:)` and
>   `.actionRecipes([ActionRecipe])`; only the former is exercised by
>   bundled content so far.
> - `ResourceCalculator.availableResources` walks inventory and de-dupes
>   pools by id (two stacks of the same wand share one charge pool).
> - `CharacterActionDeriver` emits an "Item Uses" section in the action
>   grid; rows with `.castSpell` carry an `ItemSpellCastContext` that the
>   character sheet routes into `SpellCastSheet` with the item's pool
>   replacing the slot picker.

---

## Out-of-Scope Additions (shipped between phases)

A handful of changes landed that weren't called out in any single phase. They
were small, contained, and unblocked future work, so they shipped opportunistically.
Notes here so the plan stays an accurate map of the codebase.

### Tabbed character sheet

The original sheet was one long vertical scroll. It was already cramped after
Phase J's spell card and intolerable after Phase K's item-uses + resources
additions. Reshaped into a fixed header (name, badges, HP bar, AC/Speed/Init
pills) over a segmented picker with five tabs:

- **Actions** — Resources card, Attacks card, action grid (Features + Item Uses).
- **Abilities** — ability block (with adv/dis chips), skills, senses, proficiencies, notes.
- **Features** — every feature with description, kind, charges, and selection picker. See "Data-driven Features tab" below.
- **Inventory** — full inventory editor with weapon breakdowns and item descriptions.
- **Spells** — slot dots + spell list. Hidden entirely for non-casters; an `onChange` guard kicks the user to Actions if they somehow lose spellcasting while sitting on this tab.

`navigationBarTitleDisplayMode` is now `.inline` (was `.large`) to reclaim
vertical space. The picker uses text-only labels — adding icons collided with
smaller iPhone widths.

### Bespoke `AttacksView` for weapons

Weapon attacks used to flow through the generic `ActionButtonGrid` as one tile
per recipe — Attack / Damage / Damage (2H) for a longsword was three tiles in a
2-column grid. Replaced with a `AttacksView` that emits one row per equipped
weapon, with name + mastery chip + inline pill buttons (`🎯 +5`,
`💧 1d8+3`, optional `2H 1d10+3`). The mastery chip taps to a sheet with the
SRD rule summary. `CharacterActionDeriver.weaponAttacks(for:content:)` builds
the typed model; weapons no longer appear in `sections(...)`.

### Attack → damage follow-up chip

Tapping a weapon Attack chip (and tapping Spell Attack in the cast sheet)
queues the damage roll on `PendingRollStore.followUp`. The dice tab shows a
small accent-tinted "Roll damage?" pill below the tray once the attack roll
lands. Tap → load the damage formula; X → dismiss; touching the picker manually
also clears it (so the chip stops appearing once the player has reshaped the
dice). One UX pattern serves spell attacks, weapon attacks, and any future
"primary + follow-up" pair.

### Weapon roll breakdowns + item descriptions in inventory

The inventory row's expanded edit panel now shows:

- The item's `description` text (from JSON, looked up via `ContentStore.itemDescription`).
- For weapons, a `WeaponRollBreakdown` block with attack/damage/(2H) lines.
  Each line shows the resolved formula ("+5", "1d8+3"), the damage type
  ("slashing"), and the derivation ("1d8 + STR (+3)"). Built by
  `CharacterCalculator.weaponRollBreakdown(...)`, which routes through the
  same `ActionInterpreter` the dice handoff uses, so the displayed math always
  matches what gets rolled.

### `WeaponMastery` got display data

The enum used to be bare cases. Added `displayName` and a `summary` (one short
SRD-style paragraph per property — Cleave, Graze, Nick, Push, Sap, Slow,
Topple, Vex). Surfaced in the `AttacksView` mastery sheet and in the weapon
selection picker.

### Data-driven Features tab (partial Phase M)

A `Features` tab was added that lists every class feature and species trait
sourced entirely from JSON. Each card shows the feature's name, source label,
kind chip, description, optional resource pool, and a selection picker when
applicable. The schema additions to support this:

- `FeatureKind` enum — `.passive` / `.active` / `.selection` / `.toggle`. Pure
  presentation tag; mechanical behavior still comes from the surface (`resource`,
  `actionRecipes`, `selection`). When JSON omits `kind`, the decoder auto-infers
  from shape so existing data needs no updates.
- `FeatureSelection { id, prompt, count: LevelScaledValue, optionsSource: SelectionSource }`
  attached optionally to a `FeatureDefinition`. The first `SelectionSource`
  case is `.weapons(proficientOnly: Bool)`. Future cases (spells, skills, free-form
  option lists) plug in here without code changes to consumers.
- `Character.featureSelections: [String: [String]]` — generic selection storage
  keyed by `FeatureSelection.id`. Replaces the short-lived `chosenWeaponMasteries`
  field; legacy saves are migrated on decode.

Fighter L1's `weapon_mastery` is now a JSON-declared feature with a selection
block. `CharacterCalculator.weaponMasterySlotCount` reads from the feature
rather than from `ClassDefinition.masteryCount` (the legacy field is still
parsed but no longer consulted). Mastery picking moved entirely from the
inventory row (deleted) to the Features tab's picker.

**Impact on Phase M:** the FeatureSelection schema is a starting substrate for
Phase M's choice system. Phase M still needs to: (a) generalize
`SelectionSource` to spells, skills, feats, ASI distribution; (b) add nested
choice prompts (`.composite`, `.spawnChoice`); (c) drive the choices from a
level-up flow rather than ad-hoc per-feature edits; (d) record version history
for re-entry. But the persistence layer + the picker plumbing already exist.

---

### Phase L — Conditions, Concentration, Action Economy

**Goal:** Track conditions (poisoned, stunned, etc.). Track concentration. Tag
actions with their action-economy cost.

**L.1 Condition catalog**

`ConditionDefinition.swift` in content:
- `id`, `name`, `description`
- `effects: [ConditionEffect]` — typed list:
  - `.attacksAgainstHaveAdvantage`
  - `.attacksByHaveDisadvantage`
  - `.savingThrowDisadvantage(abilities: [Ability])`
  - `.cantTakeActions`, `.cantTakeReactions`, `.cantMove`
  - `.speedZero`, `.speedHalved`
  - `.autoFailStrengthAndDexSaves`
  - …

Initial set: SRD's 14 conditions (Blinded, Charmed, Deafened, Frightened, Grappled, Incapacitated, Invisible, Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious).

**L.2 Character condition state**

```json
"conditions": [
  { "id": "poisoned", "source": "Wyvern bite" },
  { "id": "concentrating_on", "spellID": "bless" }
]
```

The `concentrating_on` pseudo-condition is special: only one at a time, dropping the previous when set.

**L.3 Concentration**

`Character.concentratingSpellID: String?`. Casting a concentration spell sets this (and pins the spell card to the sheet). Taking damage prompts a Constitution save (DC = `max(10, damageDealt / 2)`). Failure clears concentration. Casting a new concentration spell drops the old one with a confirmation prompt.

**L.4 Action economy tags**

Add `actionCost: ActionCost?` to `ActionRecipe` (or to `ResolvedAction`):
- `.action`, `.bonusAction`, `.reaction`, `.free`, `.movement`

`ResolvedAction.actionCost` derived from the recipe set's max. The action grid groups by cost (Actions / Bonus Actions / Reactions / Free) so the player sees their economy at a glance.

Per-turn tracking is out of scope for v1 (no initiative tracker yet). The cost is informational.

**L.5 UI surfaces**

- New `ConditionsRow` on the sheet, between the HP bar and the ability block. Pills for active conditions (tap to dismiss, long-press for description).
- "Add Condition" button opens a picker.
- Concentration pin (if active) appears at the top of the spells section.
- When taking damage via the HP editor sheet, automatically prompt a Con save when concentrating.

**L.6 Tests**

- Condition decode round-trip.
- Adding a `concentrating_on` condition drops a prior one.
- Damage flow triggers a concentration save.
- `actionCost` decode (defaults to `.action` if absent).

**Deliverable:** Conditions can be applied and removed manually. Casting a concentration spell pins it. Taking damage prompts a Con save when concentrating. The action grid groups by economy cost.

---

### Phase M — Choices & Multi-step Prompts

**Goal:** Anything where the player makes a permanent decision that mutates
the character: level-up, fighting style, metamagic selection, feat picks,
ASI vs. feat at L4 / L8 / etc.

> **Already in place (see "Out-of-Scope Additions" → "Data-driven Features tab"):**
> a `FeatureSelection` schema attached to features, a `SelectionSource.weapons`
> case, generic per-feature picker UI, and `Character.featureSelections` as the
> persistence layer for picks. Phase M extends this — it does not replace it.
>
> What Phase M still needs to add: more `SelectionSource` cases (spells, skills,
> feats, ASI distribution), nested / cascading choice outcomes, a guided
> level-up flow, and re-entry support with versioned outcomes.

**M.1 Choice prompt model**

`ChoicePromptDefinition.swift` (lives in content; attached to features or class level entries):
- `id`, `name`, `description`
- `kind: ChoiceKind` — `.pickOne(options:)`, `.pickN(count:, options:)`, `.distribute(points:, slots:)`
- `outcome: ChoiceOutcome` — applied when the user picks

`ChoiceOption`:
- `id`, `name`, `description`
- `outcome: ChoiceOutcome`

`ChoiceOutcome` (recursive — outcomes can spawn nested choices):
- `.grantFeature(FeatureDefinition)`
- `.grantProficiency(ProficiencyKey)`
- `.grantSpell(spellID:)`
- `.modifyAbilityScore(ability:, delta:)`
- `.spawnChoice(ChoicePromptDefinition)`
- `.composite([ChoiceOutcome])`

**M.2 Character choice state**

```json
"resolvedChoices": {
  "fighter_l1_fighting_style": "defense",
  "asi_4": { "kind": "asi", "increases": { "strength": 2 } },
  "asi_8": { "kind": "feat", "featID": "great_weapon_master" }
}
```

The character carries a record of every choice made, keyed by prompt ID. Re-entering the level-up flow with existing data pre-fills prior choices but allows changes. A "this will reset downstream choices" warning appears if the change cascades.

**M.3 Level-up flow**

When the user bumps level on the sheet:
1. `LevelUpSheet` walks every prompt the new level grants.
2. For each prompt: present the picker, save into `resolvedChoices`.
3. On finish: apply outcomes (grant features, etc.). Update `level`, `classEntries[i].level`, `maxHP`.

Hit-point gain at level-up is itself a `RollPrompt` for the class hit die, with "average" available as the per-prompt resolution-mode override.

**M.4 SRD content seeded with prompts**

- Fighter L1: Fighting Style (Archery, Defense, Dueling, Great Weapon Fighting, Two-Weapon Fighting)
- Champion / Battle Master / Eldritch Knight: subclass at L3
- Wizard: Arcane Tradition at L2
- All classes L4 / L8 / L12 / L16 / L19: ASI vs. Feat
- Sorcerer: Metamagic options
- Cleric: Divine Domain
- Etc.

Each is JSON in `levelFeatures[N]` extended with a `prompts: [ChoicePromptDefinition]?` field.

**M.5 Tests**

- `ChoicePromptDefinition` round-trip.
- Applying a Fighting Style choice grants the matching feature.
- ASI distribution validates total spend (+2 to one or +1 to two distinct).
- Re-entering level-up shows existing picks pre-filled.
- Cascading reset: changing a foundational choice clears downstream ones.

**Deliverable:** Level-up is a guided flow. Every meaningful character choice is persisted and re-editable. New SRD class content can declare its own prompts without code changes.

---

### Phase N — Damage Typing in the Dice Tray

**Goal:** Rolls can carry per-group damage type metadata so a mixed-damage
attack (Meteor Swarm bludgeoning + fire; Eldritch Blast force + Hex necrotic;
a longsword Divine Smite slashing + radiant) displays a breakdown instead of a
single anonymous total. Untyped rolls (manual rolls, history rerolls, ability
checks, saves) keep working unchanged.

This is a substrate change. It's small on its own, but Phase O leans on it —
"+1d6 necrotic" only reads correctly when the tray knows what "necrotic" is.

> **Note:** the follow-up chip pattern is already in place (Phase J / Phase K
> wired it for attack→damage chaining on both spells and weapons). Phase N's
> result HUD breakdown will sit alongside that chip, not replace it.

**N.1 DiceGroup gains an optional damage type**

```swift
struct DiceGroup: Codable, Equatable {
    var kind: DieKind
    var count: Int
    var modifier: GroupModifier?   // kh1, kl1, etc. — existing
    var damageType: DamageType?    // new; nil = untyped
}
```

Backwards-compat: existing JSON without `damageType` decodes as nil; existing
formulas (presets, history, ad-hoc picker rolls) stay untyped. The dice tab's
modifier stepper is a single integer and stays untyped — it's added to the
"untyped" bucket.

**N.2 RollResult subtotals**

`RollResult` adds:

```swift
/// Total per damage type. Untyped dice + the flat modifier land under nil.
var subtotalsByType: [DamageType?: Int] { ... }
```

The grand total stays as-is (sum across types). When `subtotalsByType` has
more than one non-nil key, the UI surfaces the breakdown; otherwise it just
shows the total like today.

**N.3 Recipe → group plumbing**

The damage-type info already exists upstream — it just gets dropped when we
collapse to a plain `DiceFormula`. The fix is mechanical:

- `weaponDamage` interpreter writes `weapon.damageType` onto the group(s) it
  produces.
- `rawDamage` interpreter writes the recipe's `damageType` onto its group.
- `heal` writes nothing (healing is its own visual treatment, not a damage type).
- Spell upcast scaling (`SpellDefinition.recipes(castAtLevel:)`) preserves the
  damage type when it appends extra dice to a typed recipe.

**N.4 Tray rendering**

The 3D physics stays a single bag of dice — all groups bounce in the same
tray. The HUD changes:

- Big total stays centered.
- Below it (or as a chip below the tray), a small breakdown: "12 force · 4 necrotic"
  when there's >1 type.
- The result chip in history shows the same breakdown.
- Per-die coloring on the 3D models is a stretch goal — start with HUD only;
  reach for SCNMaterial tinting later if mixed-damage rolls feel ambiguous.

**N.5 Formula bar pretty-printing**

Currently the bar reads `1d10+1d6+3`. With damage typing it reads
`1d10 fire + 1d6 necrotic + 3`. Parser stays tolerant of both shapes; the
pretty-printer emits the type only when present.

**N.6 History line**

`RollResult.subtotalsByType` flows into the history rendering. A typed Fire
Bolt result reads "Fire Bolt Damage: 7 fire". Untyped rolls render exactly as
today.

**N.7 Tests**

- `DiceGroup` round-trip with and without `damageType`.
- `RollResult.subtotalsByType` for a typed-only formula, mixed-typed, and
  fully untyped formula.
- Weapon damage interpreter stamps the weapon's damage type onto its group.
- Spell upcast preserves the damage type across the appended dice.
- Backwards-compat: an existing untyped formula decodes and rolls correctly.

**Deliverable:** Casting Fire Bolt shows "7 fire" in the tray and history.
Magic Missile shows "9 force". A weapon attack with `1d8+3` damage shows
"11 slashing". Manual rolls and ability checks are unchanged. The infra is in
place for Phase O to attach typed extra dice ("+1d6 necrotic from Hex").

---

### Phase O — Triggered Effects & Active Statuses

**Goal:** One mechanism that covers every "modify a roll based on a trigger"
mechanic in 5e — persistent riders (Hex, Hunter's Mark, Rage, Bless),
attack-time opt-ins (Sneak Attack, Divine Smite), pre-roll toggles
(Great Weapon Master, Sharpshooter), and resource-gated reactions (Battle
Master maneuvers, Lucky). Concentration (Phase L) gates the persistent ones;
damage typing (Phase N) makes their extra dice render correctly.

This phase is design-heavy. The shape below is a sketch; pieces will move as
we encode real content.

> **Already in place:** `FeatureKind.toggle` is declared on `FeatureDefinition`
> as a UI tag, the Features tab knows how to render a toggleable card, and
> the follow-up-chip plumbing in the dice tab is the right substrate for
> Phase O's `.optIn` activation. Phase O fills in the actual `TriggeredEffect`
> data and the resolver pass that consumes it.

**O.1 TriggeredEffect schema**

```swift
struct TriggeredEffect: Codable, Equatable {
    let id: String
    let name: String
    let trigger: TriggerCondition
    let activation: TriggerActivation
    let cost: TriggerCost?
    let effect: TriggerEffect
    let lifecycle: TriggerLifecycle
}
```

`TriggerCondition` — *when* it can fire:
- `.onAttackRoll(filter:)` — fires after the d20 lands, before damage. GWM penalty case.
- `.onAttackHit(filter:)` — fires after a confirmed hit. Sneak Attack, Divine Smite.
- `.onDamageRoll(filter:)` — auto-attaches to a damage roll. Hex, Hunter's Mark.
- `.onSpellAttackHit(filter:)` — variant for spell attacks.
- `.onTurnStart` — Rage end-of-turn maintenance, etc.

`AttackFilter` (composable):
- `.weaponHasProperty([WeaponProperty])` — Sneak Attack: finesse OR ranged.
- `.weaponCategory([WeaponCategory])`
- `.weaponDamageType([DamageType])`
- `.hadAdvantage`, `.didNotHaveDisadvantage`
- `.allyWithin5ft` — manual checkbox in the prompt; gated by trust ("you say there's an ally").
- `.allOf([AttackFilter])`, `.anyOf([AttackFilter])`

`TriggerActivation` — *how* the player engages with it:
- `.automatic` — always applies when the trigger matches. Hex's damage rider, Rage's bonus.
- `.optIn` — surfaces an opt-in chip after the trigger fires (same UI as the Phase J
  "Roll damage?" chip). Divine Smite, Sneak Attack.
- `.toggleBeforeRoll` — a chip on the action button. GWM's `-5 to hit / +10 damage`.

`TriggerCost`:
- `.spellSlot(minLevel: Int, maxLevel: Int)` — Divine Smite (1–5).
- `.resource(id: String, amount: Int)` — superiority die.
- `.oncePerTurn(flagID: String)` — Sneak Attack.
- `.none` — Hex (cost was paid when the spell was originally cast).

`TriggerEffect` — *what* it does to the in-flight roll:
- `.addDamageDice(formula: LevelScaledValue, damageType: TypedOrMatch)` — Hex `1d6 necrotic`; Sneak Attack scales by class level, type matches the weapon.
- `.addFlat(Int)` — Rage damage bonus.
- `.advantage(target: TriggerTarget)` / `.disadvantage(target:)` — Reckless Attack.
- `.rerollOne` — Halfling Lucky / Lucky feat.
- `.attackPenalty(Int)` — GWM `-5` paired with `+10` damage.

`TypedOrMatch`:
- `.fixed(DamageType)` — Hex deals necrotic.
- `.matchWeapon` — Sneak Attack matches the weapon's damage type.
- `.matchSpell` — Divine Smite's `+1d8 vs undead` rider matches radiant.

`TriggerLifecycle`:
- `.oneShot` — Divine Smite, Sneak Attack (cleared after a single application).
- `.persistent(until: PersistenceEnd)` — Hex until concentration drops, Rage until 10 rounds or unconscious.

`PersistenceEnd`:
- `.concentrationEnds` (Phase L tracks concentration)
- `.endOfTurn` / `.rounds(Int)`
- `.shortRest` / `.longRest`
- `.manual` — player ends it explicitly

**O.2 Where TriggeredEffects come from**

- **Features** declare them inline: Rogue L1 ships a Sneak Attack
  `TriggeredEffect` whose effect formula scales by class level via the existing
  `LevelScaledValue` type. Paladin L1 ships Divine Smite.
- **Spells** can grant a persistent `TriggeredEffect` when cast: Hex declares a
  `grantsTriggeredEffect: TriggeredEffect` field; casting the spell activates
  the effect on the character, casting another concentration spell drops it.
- **Items** can do the same (e.g., a ring of accuracy gives a one-shot reroll
  per long rest as a `.optIn` effect with a resource cost).

**O.3 Character state**

```json
"activeEffects": [
  { "effectID": "hex", "source": { "kind": "spell", "spellID": "hex" } },
  { "effectID": "rage", "source": { "kind": "feature", "featureID": "barbarian_rage" }, "metadata": { "roundsRemaining": 8 } }
],
"turnFlags": ["sneak_attack_used"]
```

- `activeEffects` is the persistent rider list, populated by spell casts and
  feature toggles.
- `turnFlags` tracks once-per-turn opt-ins. Cleared by a "Start new turn"
  button on the sheet (MVP; replaced by initiative-aware reset when the combat
  tracker lands).

**O.4 UI surfaces**

- **Effect badges** in the sheet header (below HP, above abilities): one pill
  per active persistent effect. Tap to dismiss (drops the effect; for spell
  sources also drops concentration). Long-press for description.
- **Opt-in chips in the dice tab.** Reuses the Phase J follow-up chip
  pattern. After an attack roll lands, the resolver inspects matching
  `TriggeredEffect`s with `.optIn` activation and renders one chip per option
  ("Sneak Attack +2d6 piercing?", "Divine Smite (L1) +2d8 radiant?").
- **Pre-roll toggles on action buttons.** A GWM-eligible weapon attack gets a
  small inline "Heavy" chip the player can toggle before tapping the attack
  button.

**O.5 Resolver wiring**

`ActionInterpreter` already produces a `ResolvedAction`. Add a sibling pass:

```swift
struct ResolvedActionWithRiders {
    let primary: ResolvedAction
    let autoRiders: [ResolvedAction]      // appended automatically
    let optInRiders: [OptInRider]         // surfaced as chips after primary
}
```

- `autoRiders` get folded into the primary's `DiceFormula` *with their
  damageType set* (Phase N's payoff) so the result HUD shows the breakdown
  naturally.
- `optInRiders` are parked on `PendingRollStore.followUp` (or its successor —
  this phase generalizes it to `followUps: [ResolvedAction]`) so the dice tab
  can render multiple chips after the primary lands.

**O.6 Concentration handoff**

When the player casts Hex:
1. The spell-cast flow consumes the slot.
2. The spell's `grantsTriggeredEffect` is appended to `activeEffects`.
3. `Character.concentratingSpellID = "hex"` (Phase L).

When the player casts a second concentration spell, Phase L's concentration
break drops the existing concentration spell, which in turn removes its
`TriggeredEffect`. When concentration breaks from damage, same path.

**O.7 Once-per-turn tracking**

`TriggerCost.oncePerTurn(flagID:)` checks `character.turnFlags`. After
applying the effect, the flag is added to the set. A "Start new turn" button
clears all turn flags. (Long rest also clears them defensively.)

This is an honor-system MVP — the app doesn't know whose turn it is. Replaced
when an initiative/combat tracker lands.

**O.8 Initial content**

- **Rogue Sneak Attack** — `TriggeredEffect` on Rogue L1 feature. Filter:
  weapon with finesse or ranged; had advantage OR (no disadvantage AND ally
  within 5 ft). Effect: `Nd6` matching weapon damage type, where N scales by
  class level. Activation: `.optIn`. Cost: `.oncePerTurn("sneak_attack")`.
- **Paladin Divine Smite** — `TriggeredEffect` on Paladin L1 feature. Filter:
  melee weapon hit. Effect: `2d8 radiant` + `1d8` per slot level above 1
  (max 5d8) + `1d8` vs undead/fiend (max 6d8). Activation: `.optIn`. Cost:
  `.spellSlot(minLevel: 1, maxLevel: 5)`.
- **Hex** — spell that grants a `TriggeredEffect` on the caster. Filter:
  weapon damage roll from caster. Effect: `1d6 necrotic`. Activation:
  `.automatic`. Cost: none. Lifecycle: `.persistent(until: .concentrationEnds)`.
- **Hunter's Mark** — same shape as Hex, but damage type is the weapon's own
  (no extra type — just an extra d6 of the weapon's damage type).
- **Battle Master Riposte / Disarm / etc.** — features with `.optIn`
  activation and `.resource("battle_master_superiority")` cost.
- **Great Weapon Master** — feat with `.toggleBeforeRoll` activation. Effect
  combines `.attackPenalty(-5)` with a paired `.addFlat(10)` on damage.
- **Rage** — feature toggle. `.automatic` rider for melee STR damage; expires
  on a `.persistent(until: .rounds(10))` timer with a "maintain rage" prompt.

**O.9 Tests**

- Hex damage rider is auto-applied to a weapon damage roll, tagged necrotic,
  surfaced in the HUD breakdown.
- Sneak Attack opt-in chip appears only when the filter matches; the
  `once_per_turn` flag suppresses it until "Start new turn" is tapped.
- Divine Smite consumes the picked slot level and applies the right number of
  dice (including the +1d8 vs undead/fiend variant).
- Casting Hex then Hunter's Mark drops Hex (concentration handoff).
- Persistent effect survives a short rest, drops on long rest or when
  manually dismissed.
- Backwards-compat: a character without `activeEffects` / `turnFlags` decodes
  cleanly (defaults to empty).

**Deliverable:** A Rogue/Paladin/Warlock multiclass actually plays right. Hex
adds 1d6 necrotic to every attack roll's damage breakdown. Sneak Attack pops
up after a qualifying hit (max once per turn). Divine Smite asks for a slot
level after a melee hit. Each of these reuses the same `TriggeredEffect`
schema — adding a new feature is a JSON edit, not a code edit.

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

## SRD Content Reference (v1)

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

### Species
Dragonborn, Dwarf, Elf, Gnome, Goblin, Halfling, Human, Orc, Tiefling.

### Backgrounds (16)
Acolyte, Artisan, Charlatan, Criminal, Entertainer, Farmer, Guard, Guide, Hermit, Merchant, Noble, Sage, Sailor, Scribe, Soldier, Wayfarer.

### Weapon Mastery (8 properties)
Cleave, Graze, Nick, Push, Sap, Slow, Topple, Vex.

### Skills (18)
Acrobatics(DEX), Animal Handling(WIS), Arcana(INT), Athletics(STR), Deception(CHA), History(INT), Insight(WIS), Intimidation(CHA), Investigation(INT), Medicine(WIS), Nature(INT), Perception(WIS), Performance(CHA), Persuasion(CHA), Religion(INT), Sleight of Hand(DEX), Stealth(DEX), Survival(WIS).

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

---

## Status (as of 2026-05-10)

| Phase | Status |
|---|---|
| A — Domain models & content schema | shipped |
| B — Content loader | shipped |
| C — CharacterStore & file I/O | shipped (atomic write fixed via `Data.write(.atomic)`) |
| D — Characters tab & creation flow | shipped |
| E — Read-only character sheet | shipped |
| F — Action engine, buttons, dice handoff | shipped |
| G — Editing characters | shipped (death saves still deferred) |
| H — Custom content import / export | **deferred** until I–O stabilize the schema |
| I — Resources & rest cycle | shipped |
| J — Spells | shipped (incl. `spellAttack` recipe + attack→damage follow-up chip) |
| K — Items with charges & spell access | shipped (Wand of Magic Missiles end-to-end) |
| Post-J UX polish | shipped — see "Out-of-Scope Additions" below |
| L — Conditions, concentration, action economy | shipped (14 SRD conditions + concentration tracking + damage-triggered Con save + action-cost chips) |
| M — Choices & multi-step prompts | **shipped (architecture complete)** — Slices A + B + C all landed. Substrate: `FeatureSelection` + 4 `SelectionSource` cases (weapons / fixedOptions / subclasses / abilityScoreIncrease), `SubclassDefinition` schema, `ClassDefinition.resolvedFeatures` aggregator threaded through every feature-walking site, `LevelUpSheet` with HP roll/average, and ASI mutators with score-cap + per-ability-cap enforcement. **Incremental content still to author** (not blocking): more subclasses (Battle Master / Eldritch Knight / wizard arcane traditions / cleric domains), sorcerer metamagic via existing `.fixedOptions`, ASI prompts on every class at L4/L8/L12/L16/L19, and a feat catalog + Origin/General feat picker. **Deferred architecture**: the heavier `ChoicePromptDefinition` / `ChoiceOutcome` recursive model the plan describes — pushed until a real use case needs nested choices (Feat → "+1 ability" sub-prompt, etc.). |
| N — Damage typing in the dice tray | **shipped** — `DiceGroup` gained `damageType: DamageType?` (Codable optional, backwards-compat for legacy JSON), `DiceFormula.applyDamageType(_:)` + `displayStringWithTypes`, `RollResult.subtotalsByType` bucketing kept dice + flat modifier (modifier attaches to a sole damage type when groups share one; falls under `nil` for mixed/untyped). `ActionInterpreter.resolveWeaponDamage` stamps `weapon.damageType` onto produced groups; `resolveRawDamage` stamps the recipe's `damageType`. Spell upcast preserves the type implicitly because `SpellDefinition.scaledRecipe` keeps the recipe's `damageType` field. New `DamageBreakdownView` renders "5 slashing + 4 radiant" lines under the tray total and in history rows. Formula bar stays untyped for parser round-trip. **Known wart**: opening the formula bar editor on a typed roll and tapping Done re-parses the untyped text, losing the type — acceptable since typed rolls come from recipe dispatch, not bar edits. |
| O — Triggered effects & active statuses | **Slices A + B shipped.** *Slice A:* Hex + Hunter's Mark end-to-end via automatic damage riders folded into weapon damage formulas. *Slice B:* Rogue class + Sneak Attack as the canonical `.optIn` chip. Schema extensions: `TriggerActivation` (`.automatic`/`.optIn`), `TriggerCost` (`.oncePerTurn(flagID:)`), `AttackFilter` (composable predicate — `.weaponHasProperty`, `.anyOf`, `.allOf`), `TriggerCondition.onAttackHit(filter:)`, `TriggerLifecycle.oneShot`, `TriggerEffect.addScaledDamageDice(count:die:damageType:)` for class-level scaling. `Character.turnFlags: Set<String>` + `setTurnFlag`/`hasTurnFlag`/`startNewTurn` mutators with backwards-compat Codable. `FeatureDefinition.triggeredEffect: TriggeredEffect?` so class features can declare riders. `PendingRollStore.followUp` generalized to `followUps: [PendingFollowUp]` (each chip carries an optional `TriggerCost`); `pendingCostsToApply` side channel lets the dice tab fire chip taps without holding a character binding (the sheet observes and applies). `TriggeredEffectResolver.optInRiders(weapon:character:content:)` walks class features, applies the attack filter, resolves scaled dice via `LevelScaledValue`, and filters out once-per-turn flags already set. Dice tab renders a scrollable chip rail post-roll; sheet renders a `turnFlagsRow` with Start New Turn button only when flags are present. **Slice C (next):** `.toggleBeforeRoll` activation + Rage's rounds-remaining metadata + GWM's paired attack penalty / damage flat. Needs Barbarian content. **Deferred from Slice B:** Paladin + Divine Smite (needs `TriggerCost.spellSlot(minLevel:maxLevel:)` + Paladin spell slots). |

## Open Decisions (to resolve during implementation)

1. **Tab layout:** Does the 3D playground tab stay, or move to a Settings/dev panel? (3D playground tab has been removed; legacy file kept for reference.)
2. **Character portrait:** Placeholder in v1, or camera/photo picker? (Placeholder shipped; picker deferred.)
3. **Death saves:** Track in Phase L alongside conditions.
4. **Multi-classing:** Out of scope for v1, but character JSON already stores `classEntries: [ClassEntry]` — multi-class UI and proficiency reconciliation land alongside Phase M's level-up flow.
5. **Resource ID collisions across content packs:** Since resource IDs are flat strings and homebrew packs can override bundled IDs, define a namespacing convention (`<pack>.<resourceID>`) before Phase H ships.
6. **Per-stack item charges:** Two of the same wand currently share one pool. Revisit if a real case appears in play.
7. **`dawn` refresh trigger:** Folded into long rest for now (see K.5). Add a separate "advance time" button only if a use case demands it.
8. **Roll-prompt label matching:** When `RollResolutionMode == .tray`, the prompt waits for a result with a matching label. Need a clear contract for what counts as "matching" — exact string vs. ID-based — before Phase J's spell-cast flow lands.

---

*Last updated: 2026-05-17*
*Next step: Phase O Slice C — pre-roll toggles + persistent rounds-tracker. Add `TriggerActivation.toggleBeforeRoll`, extend `TriggerLifecycle.persistent` with `.rounds(Int)` end conditions, attach round counters via `ActiveEffect.metadata["roundsRemaining"]`, render toggle chips on action buttons. Author Barbarian L1 (Rage as automatic persistent rider with rounds tracker) and Great Weapon Master feat (paired `-5` attack / `+10` damage toggle). Or, divert to Paladin + Divine Smite as a follow-up to Slice B (needs `TriggerCost.spellSlot(minLevel:maxLevel:)` and Paladin spellcasting; simpler than Slice C overall).*

> This document is mutable. As phases L–O evolve and new SRD / expansion
> content surfaces edge cases the schema doesn't cover, update the relevant
> phase section in place rather than spawning a parallel document.

---

## Appendix A — Exact Integration Points (Validated against codebase)

### A.1 RootView changes

Current `RootView` has no `selection:` binding on `TabView`. We add one:

```swift
enum Tab: String, Hashable {
    case dice, characters
}

struct RootView: View {
    @State private var history = HistoryStore()
    @State private var presets = PresetStore()
    @State private var contentStore = ContentStore()
    @State private var characterStore = CharacterStore()
    @State private var pendingRollStore = PendingRollStore()
    @State private var selectedTab: Tab = .dice

    var body: some View {
        TabView(selection: $selectedTab) {
            DiceRollerView()
                .tabItem { Label("Dice", systemImage: "dice") }
                .tag(Tab.dice)

            CharacterListView()
                .tabItem { Label("Characters", systemImage: "person.2") }
                .tag(Tab.characters)
        }
        .environment(history)
        .environment(presets)
        .environment(contentStore)
        .environment(characterStore)
        .environment(pendingRollStore)
    }
}
```

### A.2 DiceRollerView integration

`DiceRollerView` currently owns `@State var formula = DiceFormula()` and `@State var mode: RollMode = .normal`. It already observes `formula` changes and reseeds the tray:

```swift
.onChange(of: formula) { _, new in
    guard !isRolling else { return }
    controller.setDice(formula: new)
    lastResult = nil
    magnifyingDieIndices = []
}
```

We add one observer for `PendingRollStore`:

```swift
@Environment(PendingRollStore.self) private var pendingRoll

// inside body, after existing .onChange modifiers:
.onChange(of: pendingRoll.pending) { _, new in
    guard let resolved = new else { return }
    formula = resolved.formula ?? DiceFormula()
    mode = resolved.mode ?? .normal
    pendingRoll.pending = nil
}
```

The existing `.onChange(of: formula)` will automatically seed the tray. No changes to `DiceSceneController`, `DiceRoller`, or `HistoryStore`.

### A.3 Auto-roll setting

Add to `DiceRollerView`:

```swift
@AppStorage("character.autoRoll.enabled") private var autoRollEnabled = false

// inside the .onChange(of: pendingRoll.pending) block:
if autoRollEnabled, resolved.formula != nil {
    Task { await roll() }
}
```

### A.4 Tab layout note

The 3D playground tab has been removed from `RootView` but the `Dice3DPlaygroundView.swift` file is preserved for legacy reference.

### A.5 Test target

No test target currently exists in the project. Since `.xcodeproj` should not be modified by hand, the user will need to add a **Unit Testing Bundle** target via Xcode (`File > New > Target > Unit Testing Bundle`) once before Phase A tests can run. After the target is created, new test files in the synchronized group may need a quit-and-relaunch of Xcode to be detected.

Alternatively, if the user prefers, we can write all test code into files and the user adds them to the test target in Xcode.

---

## Appendix B — ActionRecipe → DiceFormula Examples

These examples show what `ActionInterpreter.resolve()` produces for common cases.

### Fighter with longsword (STR 16, +3 mod, proficient)
- **weaponAttack**: `DiceFormula(groups: [DiceGroup(kind: .d20, count: 1)], modifier: 5)` → display "1d20 + 5"
- **weaponDamage**: `DiceFormula(groups: [DiceGroup(kind: .d8, count: 1)], modifier: 3)` → display "1d8 + 3"
- **versatile damage**: `DiceFormula(groups: [DiceGroup(kind: .d10, count: 1)], modifier: 3)` → display "1d10 + 3"

### Rogue with rapier (DEX 16, STR 10, proficient)
- **weaponAttack** (finesse): Uses DEX mod (+3) because DEX > STR. Same formula structure, modifier = 5 (3 + 2 prof).

### Wizard casting fire bolt (spell attack, not in v1)
- Out of scope until spells phase.

### Skill check (Athletics, STR 16, proficient)
- **skillCheck**: `DiceFormula(groups: [DiceGroup(kind: .d20, count: 1)], modifier: 5)` → display "1d20 + 5"

### Saving throw (Constitution, CON 14, proficient)
- **savingThrow**: `DiceFormula(groups: [DiceGroup(kind: .d20, count: 1)], modifier: 4)` → display "1d20 + 4" (2 mod + 2 prof)

### Save DC display (Wizard, INT 16)
- **saveDC**: `formula = nil`, label = "Spell Save DC 13" (8 + 3 mod + 2 prof)

---

## Appendix C — Character JSON Future-Proofing

To avoid a breaking migration when multi-classing arrives, store class as an array even in v1:

```json
{
  "classEntries": [
    { "classID": "fighter", "level": 1 }
  ]
}
```

`Character` Swift model:
```swift
struct ClassEntry: Codable, Equatable {
    let classID: String
    let level: Int
}

struct Character: Codable, Identifiable, Equatable {
    // ... other fields ...
    var classEntries: [ClassEntry]  // v1 always has exactly 1 element
}
```

This means `classID` is never a top-level string in the JSON. Same approach for species traits that grant choices — use arrays with single elements in v1.

---

*End of plan.*
