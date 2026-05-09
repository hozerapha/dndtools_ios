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

## Open Decisions (to resolve during implementation)

1. **Tab layout:** Does the 3D playground tab stay, or move to a Settings/dev panel? (User's call.)
2. **Character portrait:** Placeholder in v1, or camera/photo picker? (Placeholder recommended.)
3. **Death saves / conditions:** In v1 or deferred? (Defer to v1.1.)
4. **Spellcasting tab:** Caster classes have spell slots but no spell list in v1. Show slot counter on sheet? (Yes, simple counter.)
5. **Multi-classing:** Out of scope for v1, but character JSON should not prevent it later. (Store `classEntries: [ClassEntry]` instead of single `classID` to future-proof.)

---

*Last updated: 2026-05-09*
*Next step: Implement Phase A (domain models & content schema).*

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
