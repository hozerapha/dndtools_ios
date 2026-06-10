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

#### Shipped reality (Slices A + B + C, 2026-05-17)

The sketch above was the design target. What actually shipped diverges in
naming and scope in a few places — capture that here so the next session can
pick up cold without re-deriving everything from the code.

**Actual schema in `Features/CharacterSheet/Content/TriggeredEffect.swift`:**

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
    case addDamageDice(dice: String, damageType: TypedOrMatch)                          // Hex 1d6 necrotic; Hunter's Mark 1d6 $weapon
    case addScaledDamageDice(count: LevelScaledValue, die: String, damageType: TypedOrMatch)  // Sneak Attack Nd6
    case addFlatDamage(amount: LevelScaledValue, damageType: TypedOrMatch?)             // Rage +2/+3/+4 (untyped → bare modifier; typed → typedModifiers bucket)
}

enum TypedOrMatch: Equatable { case fixed(DamageType); case matchWeapon }  // JSON: "necrotic" or "$weapon"

enum TriggerLifecycle: Equatable {
    case persistent(until: PersistenceEnd)
    case oneShot                       // per-attack (Sneak Attack chips)
}

enum PersistenceEnd: Equatable {
    case concentrationEnds             // Hex / Hunter's Mark
    case rounds(_ count: Int)          // Rage 10
    case manual                        // until the player dismisses from EffectsRow
}
```

**Character state additions** (all backwards-compat — `decodeIfPresent` for
each new field, encode-when-non-default for each new field):

- `Character.activeEffects: [ActiveEffect]` — persistent rider list.
- `Character.turnFlags: Set<String>` + `setTurnFlag(_:)` / `hasTurnFlag(_:)`.
- `Character.startNewTurn()` clears all turn flags AND decrements
  `roundsRemaining` on every active effect, dropping any whose counter hits 0.
- `Character.toggleFeatureEffect(effectID:featureID:roundsRemaining:)` —
  idempotent add/remove for `.toggle` effects.
- `Character.startConcentrating(on:grantsEffect:)` /
  `stopConcentrating()` / `dismissActiveEffect(_:)` — Phase L concentration
  wiring, drops spell-sourced effects automatically.
- `ActiveEffect { effectID, source: EffectSource, roundsRemaining: Int?, metadata: [String:Int] }`.
  `EffectSource` is `.spell(spellID:)` / `.feature(featureID:)` /
  `.item(itemID:)` (item branch is stubbed for later).

**Resolver — `TriggeredEffectResolver` (MainActor):**

- `applyAutomaticDamageRiders(to:weapon:character:content:) -> ResolvedAction`
  — folds every `.automatic` AND `.toggle` rider whose trigger matches into
  the in-flight damage formula. Used by `CharacterActionDeriver` to enrich
  weapon damage rows before they ever hit the dice tab.
- `optInRiders(weapon:baseDamage:character:content:) -> [PendingFollowUp]`
  — produces one `PendingFollowUp` per qualifying `.optIn` rider; each
  chip's formula is the **merged** weapon-damage + rider formula so the
  player rolls a single combined damage roll (mutually exclusive with the
  default "Roll damage" chip — that was a Slice B UX refinement).
- `turnFlagDisplayName(_:character:content:)` — resolves `"sneak_attack"` →
  `"Sneak Attack"` by scanning class features + spell-sourced effects;
  falls back to title-cased flag id when no match.
- Private `effectContext(for:character:in:)` returns the effect AND the
  owning class level so `LevelScaledValue.byClassLevel` resolves correctly
  for multiclass characters (a future L5 Rogue / L3 Barbarian gets Rage at
  Barbarian-3 = +2, not Rogue-5).

**UI surfaces shipped:**

- `EffectsRow` (sheet header, below conditions). Two stripes: orange
  "available toggles" (pill with uses-left badge; tap activates and spends
  one resource; disabled at 0 uses) and purple "active" pills with an `Nr`
  rounds-remaining mini-badge. Pills carry a menu with description + Dismiss.
- `CharacterActionDeriver.featureRows` emits a bespoke **toggle row** for any
  feature with a `.toggle` triggered effect. The row carries a
  `ToggleEffectContext` divert (mirror of `castFromItem`). Label flips
  between `Rage` / `End Rage` based on active state. Stays tappable when
  active even with 0 uses left (so you can end Rage early).
- `CharacterSheetView.handleActionTap` diverts to the toggle path before the
  default resource-cost block, so activating spends a use, deactivating is
  free (Rage doesn't refund).
- `ActionTile.isInteractive` includes `toggleEffect != nil` (Slice C bug
  fix — without this, the toggle row rendered as a non-tappable info-chip).
- `turnFlagsRow` is now a **turn tracker**: shows whenever turn flags AND/OR
  round-timed effects are present, listing both sorted ("Sneak Attack ·
  Rage 9r"). Start New Turn button clears flags and decrements rounds in
  one tap.
- Dice tab's `followUpRail` renders one chip per `PendingFollowUp`. Tapping
  any chip clears the whole rail (one damage roll per attack). Chip
  subtitle uses `DiceFormula.compactDisplayString` so a merged formula reads
  `1d8 + 1d6 + 3 piercing` instead of `[piercing]1d8 + [piercing]1d6 + 3`.
  Rider chips use `bolt.fill` icon vs `arrow.right.circle.fill` for chained.

**Content authored:**

- `spells.json` — Hex (necrotic rider, `.concentrationEnds`), Hunter's Mark
  (`$weapon` matching rider, `.concentrationEnds`).
- `classes.json` — Rogue L1 with Sneak Attack (`.optIn`, `.onAttackHit`
  with `[.finesse, .ammunition]` filter, `addScaledDamageDice` scaling
  1→10 d6 by class level, `.oneShot` lifecycle, `oncePerTurn("sneak_attack")` cost).
- `classes.json` — Barbarian L1 with Rage (`.toggle`, `.onDamageRoll` with
  `weaponLacksProperty([.ammunition])` filter, `addFlatDamage` 2/3/4 by
  class level, `.persistent(.rounds(10))` lifecycle, `barbarian_rage_uses`
  resource: 2 at L1 scaling up, refreshes on long rest). Also bundled
  Unarmored Defense as a descriptive (mechanically-inert) feature.

**Tests (in `ROLLodexTests/`):**

- `TriggeredEffectTests.swift` — schema round-trips, bundled Hex /
  Hunter's Mark loads, concentration helpers, automatic damage rider folds
  Hex into a longsword damage roll.
- `SneakAttackOptInTests.swift` — Slice B end-to-end (14 tests).
- `RageToggleTests.swift` — Slice C (13 tests): schema additions, filter
  matches, `ActiveEffect` round-trips with/without `roundsRemaining`,
  bundled Barbarian, toggle activation + deactivation, round decay,
  resolver folds on melee + skips on ranged + skips when not toggled.
- `DamageTypingTests.swift` — Phase N (now includes the Slice C polish-pass
  tests for `DiceFormula.compactDisplayString`).

**Divergences from the original sketch (still potential work):**

| Sketch | Shipped | Notes |
|---|---|---|
| `TriggerActivation.toggleBeforeRoll` | `.toggle` (sticky on/off) | We did sticky-toggle, not per-attack pre-roll. GWM's `-5/+10` pre-roll trade-off would need a separate `.toggleBeforeRoll` activation that resets each turn. |
| `TriggerCondition.onAttackRoll(filter:)` | not shipped | Needed for GWM-style penalties to the attack roll itself. |
| `TriggerCondition.onSpellAttackHit(filter:)` | folded into `.onDamageRoll` for now | Real spell-attack-hit triggers would need a distinct condition. |
| `TriggerCondition.onTurnStart` | not shipped | Reserved for Rage's "do nothing for a turn → end" semantics; we use the honor-system Start New Turn button instead. |
| `AttackFilter.weaponCategory` / `.weaponDamageType` / `.hadAdvantage` / `.allyWithin5ft` | not shipped | Sneak Attack's "advantage OR ally within 5 ft" is approximated as the property filter alone — the trust/checkbox prompt isn't surfaced. |
| `TriggerEffect.advantage` / `.disadvantage` / `.rerollOne` / `.attackPenalty` | not shipped | Reckless Attack, Halfling Lucky, GWM penalty all need these. The resolver currently only folds into damage formulas, not attack-mode or reroll mechanics. |
| `TriggerCost.spellSlot(minLevel:maxLevel:)` | not shipped | Blocks Divine Smite. |
| `TriggerCost.resource(id:amount:)` | not shipped | Blocks Battle Master maneuvers and any other once-per-something-else costs. |
| `TypedOrMatch.matchSpell` | not shipped | Only matters for spell-sourced opt-in damage riders (Divine Smite's "+1d8 radiant vs undead/fiend"). |
| `PersistenceEnd.endOfTurn` / `.shortRest` / `.longRest` | not shipped | All current persistent effects use `.concentrationEnds`, `.rounds(_)`, or `.manual`. |

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

## Status (as of 2026-06-09)

| Phase | Status |
|---|---|
| A — Domain models & content schema | shipped |
| B — Content loader | shipped |
| C — CharacterStore & file I/O | shipped (atomic write fixed via `Data.write(.atomic)`) |
| D — Characters tab & creation flow | shipped |
| E — Read-only character sheet | shipped |
| F — Action engine, buttons, dice handoff | shipped |
| G — Editing characters | shipped (death saves shipped 2026-06-09 — see roadmap item 4) |
| H — Custom content import / export | **deferred** until I–O stabilize the schema |
| I — Resources & rest cycle | shipped |
| J — Spells | shipped (incl. `spellAttack` recipe + attack→damage follow-up chip) |
| K — Items with charges & spell access | shipped (Wand of Magic Missiles end-to-end) |
| Post-J UX polish | shipped — see "Out-of-Scope Additions" below |
| L — Conditions, concentration, action economy | shipped (14 SRD conditions + concentration tracking + damage-triggered Con save + action-cost chips) |
| M — Choices & multi-step prompts | **shipped (architecture complete)** — Slices A + B + C all landed. Substrate: `FeatureSelection` + 4 `SelectionSource` cases (weapons / fixedOptions / subclasses / abilityScoreIncrease), `SubclassDefinition` schema, `ClassDefinition.resolvedFeatures` aggregator threaded through every feature-walking site, `LevelUpSheet` with HP roll/average, and ASI mutators with score-cap + per-ability-cap enforcement. **Incremental content still to author** (not blocking): more subclasses (Battle Master / Eldritch Knight / wizard arcane traditions / cleric domains), sorcerer metamagic via existing `.fixedOptions`, ASI prompts on every class at L4/L8/L12/L16/L19, and a feat catalog + Origin/General feat picker. **Deferred architecture**: the heavier `ChoicePromptDefinition` / `ChoiceOutcome` recursive model the plan describes — pushed until a real use case needs nested choices (Feat → "+1 ability" sub-prompt, etc.). |
| N — Damage typing in the dice tray | **shipped** — `DiceGroup` gained `damageType: DamageType?` (Codable optional, backwards-compat for legacy JSON), `DiceFormula.applyDamageType(_:)` + `displayStringWithTypes`, `RollResult.subtotalsByType` bucketing kept dice + flat modifier (modifier attaches to a sole damage type when groups share one; falls under `nil` for mixed/untyped). `ActionInterpreter.resolveWeaponDamage` stamps `weapon.damageType` onto produced groups; `resolveRawDamage` stamps the recipe's `damageType`. Spell upcast preserves the type implicitly because `SpellDefinition.scaledRecipe` keeps the recipe's `damageType` field. New `DamageBreakdownView` renders "5 slashing + 4 radiant" lines under the tray total and in history rows. Formula bar stays untyped for parser round-trip. **Known wart**: opening the formula bar editor on a typed roll and tapping Done re-parses the untyped text, losing the type — acceptable since typed rolls come from recipe dispatch, not bar edits. |
| O — Triggered effects & active statuses | **Slices A + B + C all shipped.** *Slice A:* Hex + Hunter's Mark end-to-end via automatic damage riders folded into weapon damage formulas. *Slice B:* Rogue class + Sneak Attack as the canonical `.optIn` chip. *Slice C:* Barbarian L1 + Rage as the canonical `.toggle` rider with 10-round timer + per-LR resource. See the **Shipped reality** callout at the end of the Phase O section for the actual schema, divergences from the original sketch, and what's still open in this phase (Divine Smite / spell-slot cost, Battle Master / superiority dice, GWM 2024-shape on-hit, attack-roll triggers, etc.). |
| Post-O — Rogue & Barbarian full progression | **shipped 2026-05-17** (`65213dd`). Rogue L1–20: Expertise (selection UI + skill picks), Sneak Attack scaling, Cunning Action, Uncanny Dodge, Evasion, Reliable Talent (d20 floor via new `DiceGroup.minimumValue` + `1d20min10` parser support), Slippery Mind (save-proficiency grants via `grantsProficiencies`), Stroke of Luck (reactive post-roll d20→20 prompt in the dice tab, consumes the L20 resource). Thief subclass (L3/9/13/17 features, incl. Use Magic Device's 4 attunement slots). Barbarian progression entries through L20. Tool proficiencies + auto-granted feature proficiencies; level-up applies pending proficiency picks. ~40 new tests. |
| HP retroactive recalc + character-deletion UI | **HP half re-landed 2026-06-09** (v2 of the reverted `131da6d`). Why the original was reverted, found by inspection: (a) the init fallback derived `rolledHP = maxHP − conMod` **without the level multiplier**, inflating HP for any level > 1 character on the next recalc — the commit's own `HPRecalculationTests` couldn't pass; (b) it changed `averageLevelUpHPGain`'s signature without updating `LevelUpTests`, so the test target didn't compile; (c) the HP editor's manual max-HP stepper wrote `maxHP` directly, which the next recalc would have stomped. v2 fixes all three: level-aware derivation + decode migration, `averageLevelUpHPGain(hitDie:conMod:)` kept as the display helper, and `setMaxHP(_:)` writes manual edits through `rolledHP`. Bonus fix: creation finalization now seeds HP from the real class hit die + post-background-ASI CON (previously every class started on a d10 and a background CON bump never reached HP). The **deletion-UI half** of the old commit is still pending — roadmap item 8. |

## Open Decisions (to resolve during implementation)

1. **Tab layout:** Does the 3D playground tab stay, or move to a Settings/dev panel? (3D playground tab has been removed; legacy file kept for reference.)
2. **Character portrait:** Placeholder in v1, or camera/photo picker? (Placeholder shipped; picker deferred.)
3. **Death saves:** Track in Phase L alongside conditions. (Shipped 2026-06-09 as a header tracker row — see roadmap item 4.)
4. **Multi-classing:** Out of scope for v1, but character JSON already stores `classEntries: [ClassEntry]` — multi-class UI and proficiency reconciliation land alongside Phase M's level-up flow.
5. **Resource ID collisions across content packs:** Since resource IDs are flat strings and homebrew packs can override bundled IDs, define a namespacing convention (`<pack>.<resourceID>`) before Phase H ships.
6. **Per-stack item charges:** Two of the same wand currently share one pool. Revisit if a real case appears in play.
7. **`dawn` refresh trigger:** Folded into long rest for now (see K.5). Add a separate "advance time" button only if a use case demands it.
8. **Roll-prompt label matching:** When `RollResolutionMode == .tray`, the prompt waits for a result with a matching label. Need a clear contract for what counts as "matching" — exact string vs. ID-based — before Phase J's spell-cast flow lands.

---

*Last updated: 2026-06-09 — full codebase review + doc sync. See "Code health review" below.*

### Code health review (2026-06-09)

A full review pass (four parallel read-throughs: dice feature, rules engine,
view layer, tests + bundled content) produced the findings below. Fixes
already applied are marked ✅; everything else is tracked as roadmap items
in "What's left".

**Fixes applied in this pass (need one ⌘R + test run to confirm — no new files, no Xcode restart needed):**

- ✅ `CharacterStore.save(_:)` no longer re-reads + re-decodes the character
  file after every write. The sheet writes through `binding(for:)` on every
  keystroke / HP tap, so the disk round-trip was pure overhead; the in-memory
  array is now updated directly with the value that was just encoded.
- ✅ `CharacterStore.load()`'s manifest-cleanup check compared against
  `characters.count`, which is always 0 during init — so the manifest was
  rewritten on **every launch**. It now compares the entry count before/after
  cleanup, and the rewrite goes through the atomic `writeManifest` path
  (the old inline write wasn't atomic).
- ✅ `DiceSceneController.tickRestDetection()`'s force-unwrap
  (`allStillSince!`) replaced with an unwrap-free equivalent.
- ✅ (2026-06-09, HP pass) `CharacterCalculator.abilityModifier` used Swift's
  truncating division, so every odd score below 10 was one modifier too high
  (9 → 0 instead of −1; 1 → −4 instead of −5 — the existing test for score 1
  expected −5 and was **failing**). Now `score / 2 - 5`, the exact 5e floor.
  Affects mods/saves/AC/attack math for low odd scores everywhere.

**Verified-correct during review (false alarms — no action needed):**

- Stroke of Luck's value-override loop already bounds-checks
  (`min(cursor + group.count, overriddenValues.count)`).
- `RefreshResolutionSheet`'s `rolls` cache is `@State` inside sheet content —
  it resets per presentation; no stale-roll bug.
- 5e math audit came back clean: proficiency bonus `⌊(L−1)/4⌋+2`, spell save
  DC `8+mod+prof`, spell attack bonus, AC (armor base / dex cap / shield),
  concentration DC `max(10, dmg/2)` after temp-HP absorption, level-up HP
  average with ≥1 clamp, Archery (+2 ranged) / Dueling (+2 single-wield melee)
  gating, keep/drop/reroll/advantage dice logic, crit detection on kept dice
  only, multiclass-aware `LevelScaledValue` resolution.

**Known debt (each row maps to a roadmap item below):**

| Finding | Where | Item |
|---|---|---|
| Reliable Talent hardcodes `classID == "rogue" && level >= 7` in Swift | `ActionInterpreter.swift` | 9a |
| `stroke_of_luck` excluded from the action grid by raw string id | `CharacterActionDeriver.swift` | 9b |
| Fighting-style mechanics keyed on raw option strings (`"archery"`, `"dueling"`) | `ActionInterpreter.swift` | 9c |
| `CharacterStore.save` failures only `print` — the user never learns a save failed | `CharacterStore.swift` | 9d |
| ~~No content lint~~ — ✅ closed 2026-06-09 (`ContentLintTests.swift`) | tests | 9e |
| Backgrounds reference feats (`savage_attacker`, `magic_initiate_*`) that exist nowhere as content definitions | `backgrounds.json` | 11 |
| `ContentStore` `fatalError`s on bad JSON — right for bundled content, fatal for Phase H user imports | `ContentStore.swift` | 12 |
| `ForEach(… id: \.offset)` on the level-up new-features list (fragile identity) | `FeaturesView.swift` | 13 |
| ~~Character swipe-to-delete~~ ✅ confirmed-delete shipped 2026-06-09; spell long-press "forget" still unconfirmed | `SpellListView` | 13 |
| No spell search in the add-spell picker; no spell-description preview short of opening the cast sheet | `SpellListView` | 13 |
| DiceRoller core (adv/dis, keep/drop, reroll, d100 pairing, physics-values path) has no direct unit tests | tests | 10 |

**Deletion candidates (zero references, confirmed by project-wide grep — flag only; deletions happen in Xcode, by hand):**

- `Features/DiceRoller/Views/DiceTrayView.swift` — 2D fallback tray,
  superseded by the 3D SceneKit tray. Self-contained (all helpers `private`).
- `Features/DiceRoller/Views/DieTokenView.swift` — only ever used by
  `DiceTrayView`.
- The `Dice3DPlaygroundView` *view struct* (the sandbox screen) is
  unreachable from the app — but its file hosts the **production**
  `DiceSceneController`. Split the controller into its own file first
  (item 13), then the view struct can go.
- `ClassDefinition.masteryCount` / `masteryRestrictions` — still parsed,
  no longer consulted (superseded by the `weapon_mastery` feature selection).
- `Character`'s legacy `chosenWeaponMasteries` CodingKey — **keep** until a
  save-format version bump; it's the migration path for old saves.

### What's left — cold-start hand-off

Picking up in a fresh session? These are the live threads, ordered by how
self-contained each one is. Pick whichever matches the appetite for the
session.

**1. Paladin + Divine Smite (finishes Phase O's opt-in story)**
- New: `TriggerCost.spellSlot(minLevel: Int, maxLevel: Int)` case
  alongside the existing `oncePerTurn`. JSON shape:
  `{"type":"spellSlot","minLevel":1,"maxLevel":5}`.
- New: `TypedOrMatch.matchSpell` (only needed for Divine Smite's `+1d8`
  vs undead/fiend variant — defer if you skip the toggle-by-target flow).
- Resolver: `optInRiders` already iterates `.optIn` triggers from class
  features. Add a `spellSlot` cost path that, on chip tap, prompts the
  player for a slot level (reuse `SpellCastSheet` UX) before applying
  `addScaledDamageDice` with `count = slotLevel + 1`.
- Character work: bundle Paladin L1 in `classes.json` with Lay on Hands
  (already works under existing schema) + Divine Smite triggered effect.
  Needs Paladin spell slot table on `ClassDefinition.spellcasting`.
- Wiring: `PendingFollowUp` already carries an optional `cost`; extend
  the dice-tab consume path to route `spellSlot` costs to a slot picker
  before firing. Or — simpler — gate Divine Smite chip rendering by
  "have any slot available" and consume the lowest slot silently for
  v1 (a "pick slot level" UI is its own polish).
- Test: `DivineSmiteTests.swift` — bundled Paladin loads with smite,
  resolver lists it only after a melee hit, consuming the chip
  decrements a slot, applies `2d8 + 1d8/level above 1` radiant.

**2. ~~Bundle a real Rogue subclass at L3~~ — DONE (`65213dd`)**
- Thief shipped with L3/9/13/17 features (incl. Use Magic Device granting
  4 attunement slots), covered by `RogueFeatureTests`. Champion (Fighter)
  was already bundled. Remaining subclass authoring is folded into item 11.
- Still worth one manual end-to-end pass on the simulator: create a Rogue,
  level to 3, pick Thief, confirm L3+ features appear in the grid.

**3. Phase O polish — visuals + content authoring (small, parallelizable)**
- `EffectsRow` two-stripe layout: separate the orange "available
  toggles" from the purple "active" pills with a visual gap or
  divider — they currently jam together when both are present.
- Chip rail wording sweep: "Roll damage" vs "Sneak Attack" vs "End Rage"
  are inconsistent — chip prompts and tile labels could converge on one
  verb pattern.
- Author two more `.toggle` features to prove the substrate generalises:
  - **Bless** (already a Phase J spell, currently lacks a triggered
    effect) — concentration buff that adds `+1d4` to attack rolls. Needs
    `TriggerCondition.onAttackRoll(filter:)` (NOT shipped) and
    `TriggerEffect.addAttackBonus(dice:)` (NOT shipped). Bigger lift.
  - **Reckless Attack** (Barbarian L2) — `.toggle`, grants advantage on
    STR melee attacks and to attacks against you. Needs
    `TriggerEffect.advantage(target:)` (NOT shipped).

**4. ~~Phase G follow-ups: death saves~~ — DONE 2026-06-09**
- `DeathSaveState` (successes/failures, clamped 0–3, `isStable`/`isDead`)
  lives on `Character.deathSaves`; decode-safe default, encoded only when
  non-empty. Counters reset automatically when `currentHP` goes 0 → positive
  (a `didSet` on `currentHP`, so every heal path — header +1, HP editor,
  long rest — gets it for free). `applyDamage` while already at 0 HP
  auto-records one failure (the crit's second failure is a manual tap —
  the app can't see the attacker's die).
- UI: `DeathSavesRow` appears in the sheet's sticky header only at 0 HP —
  Dying/Stable/Dead badge, two rows of three tappable circles (re-tap to
  undo), a Roll chip that hands a labeled d20 to the dice tab, and the
  rules reminder line ("10+ succeeds · nat 1 = 2 fails · nat 20 = regain
  1 HP"). Honor-system: the player reads the die and taps the circle.
- Tests: `DeathSaveTests.swift` (10 tests) — legacy decode, round-trip,
  encode-omission, damage-while-dying, drop-to-zero non-failure, temp-HP
  absorption, cap-at-three, heal reset, thresholds.

**5. Phase H — Custom content import / export (deferred until Phase O
schema stabilised; now that it has, this is unblocked)**
- See Phase H section above. `UIDocumentPicker` for import,
  `ShareLink` for per-character JSON export. Validate against the
  bundled JSON schemas before writing into `Documents/Content/`.

**6. Phase M open content debt (the architecture is done, the catalog isn't)**
- Subclasses at the right level for every bundled class.
- ASI prompts at L4/L8/L12/L16/L19 for every class (currently only the
  shape exists; per-class wiring lands when each class is authored).
- Sorcerer metamagic (uses existing `.fixedOptions`).
- Feat catalog (Origin feats from backgrounds, General feats from ASI
  trade-ins). May force the deferred `ChoicePromptDefinition` /
  `ChoiceOutcome` recursive model if any feat sub-prompts.

**7. Bigger architectural threads that haven't started**
- **Initiative / combat tracker** (separate top-level feature; currently
  out of scope per PLAN.md).
- **Replace the "Start New Turn" honor-system button** with
  initiative-aware turn advancement once a tracker exists.
- **In-app content editor** (Phase I) — substantial UI surface; only
  worth picking up if hand-editing JSON has started to hurt.

**8. ~~Re-land the reverted HP/CON work~~ — DONE 2026-06-09 (both halves)**
- Shipped (see the Status-table entry for the revert post-mortem):
  `Character.rolledHP` stores die-only HP; `recalculateHP()` derives
  `maxHP = max(level, rolledHP + level × CON mod)` and shifts `currentHP`
  by the delta (floors at 1 for the living, leaves the dying at 0); decode
  migration back-derives `rolledHP` for old saves; the ASI mutators recalc
  automatically when CON changes (so every picker path is covered);
  `setMaxHP(_:)` writes manual max-HP edits through `rolledHP` so recalcs
  preserve them; `applyLevelUp` banks the die-only gain; creation
  finalization seeds HP from the real class hit die + post-ASI CON.
  Tests: new `HPRecalculationTests.swift` (⚠️ new file — Xcode ⌘Q +
  relaunch before building) + `LevelUpTests` updated to die-only semantics.
- Known model edge (accepted): with severe CON penalties, 5e's
  ≥1-HP-per-level rule is enforced as a total floor (`max(level, …)`)
  rather than per-level clamping, since per-level die values aren't stored.
- **Deletion UI also shipped 2026-06-09:** context-menu delete on
  `CharacterListView` rows, swipe-to-delete now stages a confirmation
  dialog instead of firing immediately, and the sheet's toolbar gained an
  overflow menu with a confirmed delete that pops back to the list before
  removing the file (the store mutation waits out the pop animation so the
  screen doesn't flash "Character not found"). Note: the reverted version's
  delete button only switched tabs — it never actually called
  `characterStore.delete`; this one does.

**9. Engine hardening (from the 2026-06-09 code health review)**
- **9a. De-hardcode Reliable Talent.** `ActionInterpreter` checks
  `classID == "rogue" && level >= 7` in Swift. Replace with data: add an
  optional `skillCheckMinimum: LevelScaledValue` (or a
  `TriggerEffect.minimumOnSkillChecks`) to `FeatureDefinition`, author it on
  the Rogue L7 feature in `classes.json`, and have the interpreter walk
  features instead of class ids. `MinimumValueTests` already pin the
  behavior — they must pass unchanged.
- **9b. De-hardcode the `stroke_of_luck` action-grid skip.** Add a
  presentation flag (`FeatureKind.reactive` or `surfaceAsAction: false`) to
  `FeatureDefinition`, set it in JSON, drop the string match in
  `CharacterActionDeriver`.
- **9c. Centralize magic strings.** `"archery"`, `"dueling"`,
  `"weapon_mastery"`, `"fighting_style"`, the `"expertise"` prefix — collect
  into one `FeatureIDs` namespace as a first step (grep-able, single point of
  truth). Full data-driven fighting-style *mechanics* (so a homebrew style
  can add bonuses without Swift) is a separate, bigger lift — defer until a
  real homebrew case shows up.
- **9d. Surface save failures.** `CharacterStore.save` currently `print`s
  and moves on. Add `private(set) var lastSaveError: String?` on the store,
  set/clear it in `save`, render a dismissible warning banner on
  `CharacterSheetView` when non-nil. (Disk-full is the realistic trigger.)
- **9e. ~~Content lint test~~ — DONE 2026-06-09.** `ContentLintTests.swift`
  walks ALL bundled JSON: id uniqueness per file, across the
  gear/weapons/armor item namespace, and globally for resource/effect ids;
  background feat/equipment references (with an explicit
  `knownUnauthoredIDs` allow-list covering the 3 feats + 8 flavor items
  awaiting items 11d/11g, plus a staleness check that fails when an
  allow-listed id becomes real content); every dice string parses (recipes,
  weapon damage/versatile, refresh rolls, rider dice, composed max-upcast
  formulas); upcast `recipeIndex` bounds + scalability; `byClassLevel`
  tables reach their grant level; item-use costs and cast spells resolve;
  subclass picker wiring matches the aggregator's convention key. Phase H
  should reuse these invariants as its import validator.

**10. Test gaps (beyond the content lint)**
- `DiceRoller` core: `roll` ranges + die counts, advantage/disadvantage
  keeps the right die, `keepHighest/keepLowest/dropHighest/dropLowest`
  permutations, `rerollOnceIfAtMost` (incl. reroll-then-floor interaction),
  `rerollIndices` + `resultFrom(values:)` physics path, d100 tens/ones
  composition.
- `CharacterStore.load()` manifest-cleanup regression test (the every-launch
  rewrite bug fixed in this pass).
- Spell-preparation rule enforcement (`PreparedRule` — wizard can't prepare
  outside spellbook, etc.) once item 11's casters land.

**11. Content authoring catalog (JSON-only work, no Swift)**
Current bundle: 4/12 classes (Fighter, Wizard, Rogue, Barbarian), 3/9
species, 3/16 backgrounds, ~18/40 weapons, 8/8 armor ✅, 14/14 conditions ✅,
~11 spells (cantrips + L1). Suggested authoring order, each batch
shippable alone:
- **11a. Cleric** — first `preparedFromAll` caster; Channel Divinity as a
  resource; Life Domain at the subclass level; needs a half-dozen L1 cleric
  spells + healing word/cure wounds (heal recipes already exist).
- **11b. Paladin** — pairs with item 1 (Divine Smite). Half-caster slot
  table (the `SlotTable` shape already supports arbitrary progressions —
  author the half-caster table, no schema change). Lay on Hands as a
  `5 × level` pool resource (v1: spend via the resources card's manual
  adjustment; a "spend N" prompt is polish).
- **11c. Species + backgrounds sweep** — the 6 missing species and 13
  missing backgrounds are descriptive-trait work; Dwarven Toughness-style
  HP traits should wait for item 8's `rolledHP` model.
- **11d. Weapons + gear sweep** — remaining ~22 SRD weapons (all have
  existing property/mastery vocabulary), standard adventuring gear.
- **11e. Spell batches** — all SRD cantrips, then L1, then L2–L3, gated per
  bundled caster class. **Prereq:** decide how class spell lists are
  encoded (per-spell `classes: [...]` array vs. per-class list) — the
  add-spell picker needs it to filter once the catalog grows.
- **11f. ASI prompts audit** — Fighter currently has ASI at 4/13/19; SRD
  5.2.1 Fighter gets 4/6/8/12/14/16/19. Audit every bundled class's ASI
  levels against the SRD while authoring.
- **11g. Feat catalog** — Origin feats first (backgrounds already
  reference `savage_attacker`, `magic_initiate_*` as dangling ids — item
  9e will flag them). General feats need the ASI-vs-feat fork in
  `LevelUpSheet`; that may finally force the deferred
  `ChoicePromptDefinition` recursive model (a feat granting a +1 ability
  sub-choice).
- **11h. More subclasses** — Battle Master (needs
  `TriggerCost.resource(id:amount:)` — small schema addition), Eldritch
  Knight + Arcane Trickster (spell-list subclasses), Wizard Evoker.

**12. Phase H — homebrew import/export (unblocked, schema is stable)**
- Prereq: `ContentStore` decode path must become throwing/recoverable for
  *imported* packs (bundled content keeps `fatalError` semantics). Reuse
  item 9e's lint as the import validator — same invariants, surfaced as an
  error sheet instead of a failing test.
- Then as originally specced: `UIDocumentPicker` for `.json`/`.zip` import
  into `Documents/Content/`, `ContentStore.reload()` with imported-shadows-
  bundled id resolution, `ShareLink` export of characters and packs.
- Resolve open decision #5 (resource-id namespacing, `<pack>.<id>`) before
  the first external pack exists, not after.

**13. UX + structure polish backlog (small, parallelizable)**
- ~~Confirmation dialog: character delete~~ (done with item 8). Spell
  "forget" confirmation still open.
- Empty-name guard on character rename.
- `.searchable` on the add-spell picker; spell-description preview without
  opening the cast sheet (long-press or info button).
- Attunement-cap feedback: tapping attune at 3/3 currently no-ops silently —
  show a brief explanation instead.
- Stable identity for the level-up new-features `ForEach` (use feature id,
  not `\.offset`).
- Split `DiceSceneController` out of `Dice3DPlaygroundView.swift` into its
  own file (⚠️ new file → Xcode ⌘Q + relaunch). Unblocks deleting the dead
  playground view struct; also the right moment to extract
  `FaceGeometryBuilder` / rest-detection if the file is being touched anyway.
- EffectsRow two-stripe divider + chip-rail wording sweep (carried over from
  item 3).

### Suggested order

1. **Verify this pass:** ⌘R + run the test suite (CharacterStore changed —
   `CharacterStoreTests` must stay green).
2. ~~Item 9e (content lint)~~ — done 2026-06-09.
3. ~~Item 8~~ — done 2026-06-09 (HP re-land + deletion UI, both surfaces
   confirmed).
4. ~~Item 4 (death saves)~~ — done 2026-06-09.
5. **Items 1 + 11b together (Paladin + Divine Smite)** — finishes Phase O's
   opt-in story and proves the spell-slot cost path.
6. **Item 11a (Cleric)** — first prepared caster, exercises `preparedFromAll`.
7. **Item 12 (Phase H)** once 9e exists to power import validation.
8. Items 9a–9d, 10, 13 interleave as palate cleansers between the above.

### How to resume

In a new session, opening with "let's continue from PLAN_CharacterSheet's
'What's left' section, pick #N" is enough — every entry above lists the
files / schema cases / tests that would change, so the next session can
start without re-reading the codebase first. `git log --oneline -10` shows
the recent shipping cadence; note that `131da6d` (HP recalc) was reverted
and is item 8's subject, not shipped work.

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
