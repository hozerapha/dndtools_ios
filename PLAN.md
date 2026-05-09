# dndtools_ios — Implementation Plan

A TTRPG toolset for iOS. **First feature: Dice Roller.** Future features (character sheet, initiative tracker, spell lookup, etc.) will be added later, so the app shell should be designed with a tab/navigation structure that has room to grow.

The plan is intentionally split into small phases so each step introduces one or two new Swift / SwiftUI concepts at a time. We pause between phases.

---

## Tech choices (proposed)

| Concern | Choice | Why |
|---|---|---|
| UI framework | **SwiftUI** | Modern declarative UI; less boilerplate than UIKit; good for a learner. |
| Min iOS target | **iOS 17+** | Lets us use the `@Observable` macro, `.sensoryFeedback`, modern `NavigationStack`, etc. |
| State | `@State` locally, `@Observable` classes for shared state (history, presets) | Replaces older `ObservableObject` + `@Published`. |
| Persistence | `UserDefaults` + `Codable` at first, migrate to **SwiftData** when history/presets get richer | Start simple; SwiftData is overkill for a v1. |
| Tests | **Swift Testing** (`@Test`, `#expect`) | Newer, lighter than XCTest. |
| 3D dice (later) | **RealityKit** | As planned. |

We'll confirm each choice before adopting it, but these are the defaults.

---

## Phase 0 — Project setup

**Goal:** A buildable, runnable empty SwiftUI app on the simulator.

1. Create the Xcode project in Xcode (`File > New > Project > iOS > App`).
   - Product Name: `ROLLodex`
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None (we'll add SwiftData later)
   - Save it inside this repo at `./ROLLodex/`.
2. Set min deployment target to iOS 17.0.
3. Run on the simulator — verify the default "Hello, world!" screen launches.
4. Commit.

**Concepts introduced:** Xcode project anatomy, the App entry point (`@main`, `App`, `Scene`, `WindowGroup`), what a `View` is, what `body: some View` means.

---

## Phase 1 — App shell (room to grow)

**Goal:** A `TabView` (or root navigation) so the dice roller has a home and other tools can be added later.

1. Replace `ContentView` with a `RootView` containing a `TabView`.
2. One tab for now: **Dice Roller** (placeholder view).
3. Stub future tabs as a single "More" tab or just leave them out for now.

**Concepts introduced:** `TabView`, `.tabItem`, splitting views into separate files.

---

## Phase 2 — Domain models

**Goal:** Pure-Swift types for dice, formulas, and roll results. No UI yet.

Files (in `Models/`):

1. `DieKind.swift` — an enum of the seven dice with their face counts.
   ```swift
   enum DieKind: Int, CaseIterable, Identifiable, Codable {
       case d4 = 4, d6 = 6, d8 = 8, d10 = 10, d12 = 12, d20 = 20, d100 = 100
       var id: Int { rawValue }
       var label: String { "d\(rawValue)" }
   }
   ```
2. `DiceFormula.swift` — counts per die kind + integer modifier. Methods to add/remove a die, clear, and produce a display string like `2d4 + 3d12 + 4`.
3. `RollResult.swift` — input formula, per-die outcomes (which die, what it rolled), modifier, total, timestamp, optional advantage/disadvantage flag.
4. `DiceRoller.swift` — pure function `func roll(_ formula: DiceFormula) -> RollResult` using `Int.random(in: 1...kind.rawValue)`. Keeping the RNG behind a small abstraction will let us swap in a seeded RNG for tests later.

**Concepts introduced:** `enum` with raw values, `struct` value semantics, `Codable`, `Identifiable`, computed properties, basic Swift collections (`Dictionary`, `Array`).

**Tests:** A few Swift Testing cases — formula display string, count add/remove, `roll` returns values in the right ranges and the right number of dice.

---

## Phase 3 — Static dice roller UI (no logic yet)

**Goal:** Lay out the screen exactly like the design, but with hardcoded text. Get comfortable with SwiftUI layout.

Layout (top → bottom):
- **Formula bar** — single-line text showing the current formula.
- **Dice tray** — center area that will eventually show the 2D tokens / 3D dice. Empty placeholder for now.
- **Modifier stepper** — `Stepper` bound to an `Int`.
- **Dice picker row** — seven buttons, one per `DieKind`.
- **Action row** — Clear button, Roll button, History button.

**Concepts introduced:** `VStack`/`HStack`/`ZStack`, `Spacer`, `.padding`, `.background`, `.frame`, `Button` action, `ForEach` over an enum's `allCases`.

---

## Phase 4 — Wire up state

**Goal:** The formula bar updates as you tap the dice.

1. `@State private var formula = DiceFormula()` in the dice roller view.
2. Tap on a die button → `formula.add(.d6)` etc. Watch the bar update.
3. **Long press to subtract.** Use `.onLongPressGesture` (or a combined `TapGesture` + `LongPressGesture`) to call `formula.remove(.d6)`.
4. Modifier `Stepper` bound to `formula.modifier`.
5. Clear button resets `formula` to `.init()`.

**Concepts introduced:** `@State`, value-vs-reference semantics (why `@State var formula = DiceFormula()` works even though structs are copied), gestures, two-way bindings (`$formula.modifier`).

---

## Phase 5 — Rolling

**Goal:** Tapping Roll produces a result and shows the total.

1. `@State private var lastResult: RollResult?`.
2. Roll button calls `DiceRoller().roll(formula)` and stores the result.
3. Show the total prominently after a roll (above the formula bar or in the dice tray).
4. Show the per-die breakdown in a small list under the total ("d20: 17, d6: 3, d6: 5, +2 → 27").

**Concepts introduced:** Optional state, conditional views (`if let result = lastResult`), formatting numbers in SwiftUI.

---

## Phase 6 — Dice tray (2D version)

**Goal:** Replace the empty placeholder with numbered tokens shaped like each die.

1. Build a `DieTokenView` — a small shape (circle / triangle / square / etc., one per kind) with the rolled number centered.
2. After a roll, the tray shows one token per rolled die, colored by kind, with the result number on it.
3. Highlight nat-20 (gold) and nat-1 (red) on d20s — first taste of "extras".

**Concepts introduced:** Custom `Shape`, `GeometryReader` if needed, conditional styling.

> The 3D RealityKit version will replace this view in a much later phase.

---

## Phase 7 — Roll history (bottom sheet)

**Goal:** A button opens a sheet that slides up showing past rolls, newest first.

1. New `@Observable` class `HistoryStore` holding `[RollResult]`. Inject it as an `@Environment` value or `@State` at the root.
2. After every roll, prepend the result.
3. History button toggles a `@State var showHistory = false`. Use `.sheet(isPresented:)` with `.presentationDetents([.medium, .large])` to get the bottom-sheet behavior.
4. Each row shows formula, total, timestamp; tap a row → option to "re-roll this formula".

**Concepts introduced:** `@Observable`, environment injection, `.sheet`, `presentationDetents`, `List` + `ForEach`, relative date formatting.

---

## Phase 8 — Persistence (history + presets)

**Goal:** History survives app restarts. Add the "save formula as preset" feature.

1. Persist `HistoryStore` and a new `PresetStore` to `UserDefaults` via `Codable` (JSON-encoded).
2. "Save as preset" button on the dice roller stores the current formula with a user-supplied name.
3. Presets row above the dice picker — tap a preset to load it into the formula.

**Concepts introduced:** `JSONEncoder` / `JSONDecoder`, `UserDefaults`, debouncing writes, simple input via `TextField` + `.alert`.

---

## Phase 9 — Advantage / disadvantage

**Goal:** A toggle that, when enabled, rolls the d20 portion of the formula twice and keeps the higher (advantage) or lower (disadvantage).

1. Tri-state control: Normal / Advantage / Disadvantage (a `Picker` with `.segmented` style).
2. `DiceRoller.roll` takes an optional mode and applies it only to d20s.
3. The result breakdown shows both d20 rolls, with the kept one bolded.

**Concepts introduced:** Enums as inputs, segmented pickers, slightly more interesting result modeling.

---

## Phase 10 — Polish: haptics & sound

**Goal:** A satisfying tactile/audio cue when rolling.

1. `.sensoryFeedback(.impact, trigger: lastResult?.id)` for haptics.
2. `AVAudioPlayer` (or `AVFoundation`'s simpler APIs) for a short dice-clatter sound. Add a setting to mute it.
3. A small "Settings" sheet for the mute toggle and any future preferences.

**Concepts introduced:** `.sensoryFeedback`, working with bundled audio assets, settings storage via `@AppStorage`.

---

## Phase 11 — RealityKit 3D dice (stretch, later)

**Goal:** Replace the 2D tray with physics-rolled 3D dice. This is a significant phase — we'll plan it in detail when we get there. Likely sub-phases:

- Set up a `RealityView` and a basic scene with a "table" plane.
- Load / generate a die mesh per kind (or use simple primitives first).
- Apply physics, drop dice in, read which face landed up.
- Sync the physical result with the deterministic RNG (i.e., the math result is canonical; the animation is theater).

---

---

# Character Sheet

A multi-character manager for **D&D 5.2.1 (5.5e SRD)**. Each character is a JSON document; ruleset content (classes, species, items, weapons) is bundled as JSON and extensible via user-imported homebrew. Tapping an action on a character sheet pre-fills the Dice Roller tab.

## Locked-in architecture decisions

- **Data-driven action recipes.** Each weapon, class feature, and (later) spell declares an `ActionRecipe` in its content JSON. A small interpreter combines the recipe with character state to produce a `DiceFormula`. v1 ships a fixed primitive set: weapon attack, weapon damage, ability check, skill check, saving throw, save DC. Homebrew works automatically if it conforms to the schema. (We ruled out the alternative — hardcoded action types in Swift — because adding a new kind of action would have required code changes.)
- **Storage split.** Bundled SRD + user-imported content live in `Documents/Content/` (read-mostly, with a single shared layout). Each character is one JSON file in `Documents/Characters/<uuid>.json` with atomic writes. `HistoryStore` and `PresetStore` stay on UserDefaults — they're dice-roller state, not documents.
- **Cross-tab handoff.** A new `@Observable PendingRollStore` injected at the root holds an optional `(formula, mode, label)`. The Dice tab observes it; the Characters tab writes to it and bumps the `TabView` selection. The same plumbing later carries one-shot mode overrides ("advantage from Faerie Fire").
- **JSON over SwiftData.** Picked deliberately so future tools (D&D Beyond importer, hypothetical Android port) can speak the same format.

## v1 scope cuts

- **No spells.** Caster classes still get attacks/checks/saves; just no cast buttons. Spells get their own phase later — they roughly double the action engine's surface area.
- **No leveling beyond level 1.** Class JSON has a per-level features field, but only level 1 is populated in v1.
- **No bestiary / monsters.** Out of scope entirely; revisit later if needed.
- **Weapon Mastery (5.5e)** shows as a label on action buttons but doesn't apply mechanical effects yet — wire it up in a polish pass.
- **Initiative tracker** remains a separate future feature, not part of this plan.

## Phase A — Domain models & content schema

**Goal:** Pure Swift types and JSON schemas. No UI, no I/O.

Files (in `Features/Characters/Models/` plus a shared `Content/` area):

1. `Character.swift` — name, level, species, background, class choice, ability scores, hp, ac, speed, equipped items, currency, notes, manifest version field.
2. `Ability.swift` / `Skill.swift` / `ProficiencyLevel.swift` (none / proficient / expertise).
3. `ClassDefinition.swift` — name, hit die, primary ability, saves, level-1 features, weapon/armor proficiencies, per-level features (empty above level 1 for now).
4. `SpeciesDefinition.swift` — name, size, speed, traits.
5. `BackgroundDefinition.swift` — name, ability score increases, skill proficiencies, feat.
6. `ItemDefinition.swift` (base) + `WeaponDefinition.swift` / `ArmorDefinition.swift`. Weapons carry one or more `ActionRecipe`s.
7. `ActionRecipe.swift` — tagged enum: `.weaponAttack`, `.weaponDamage`, `.abilityCheck`, `.skillCheck`, `.savingThrow`, `.saveDC`. Each variant carries its parameters (ability choice, finesse rule, prof requirement, etc.).
8. JSON schemas documented inline + sample longsword + sample fighter hand-written as test fixtures.

**Tests:** Codable round-trips for every model. Decode the sample longsword and fighter from JSON. Verify `ActionRecipe` decodes correctly across variants.

**Concepts introduced:** Tagged enums with associated values + `Codable`, custom decoder for tagged-union JSON, keeping data and behaviour separate.

## Phase B — Content loader

**Goal:** Load bundled SRD content into memory at app startup.

1. Bundle a starter SRD slice in `Resources/Content/` — 2 classes (Fighter, Wizard), 3 species (Human, Elf, Dwarf), 3 backgrounds, ~10 weapons, basic armor and gear. Enough to exercise the pipeline; the rest of the SRD lands in batches as Phase D/E/F mature.
2. `@Observable ContentStore` exposes `[ClassDefinition]`, `[SpeciesDefinition]`, etc. Loaded in `init` via the bundle. Bundled content failing to load throws — that's a build-time bug, not a runtime concern.
3. Inject as an environment value at `RootView`. No UI yet.

**Concepts introduced:** Reading from `Bundle.main`, decoding a directory of JSON files, environment injection patterns.

## Phase C — CharacterStore

**Goal:** Read/write character JSON files.

1. `@Observable CharacterStore` exposes `[Character]`. Reads all files in `Documents/Characters/` on init.
2. Save: encode → write to `<uuid>.json.tmp` → rename to `<uuid>.json`. Atomic, so a crash mid-save can't corrupt the file.
3. Manifest file (`Documents/Characters/manifest.json`) tracks character order and last-edited timestamps. Tolerates single-character-file deletes gracefully.
4. `delete(id:)` removes the file and the manifest entry.

**Tests:** save → load → equal. Save mid-rename simulation → file integrity preserved.

**Concepts introduced:** `FileManager`, atomic file writes, `Documents` vs `Bundle`, manifest patterns.

## Phase D — Characters tab + creation flow

**Goal:** New "Characters" tab. List of characters. "+" opens a guided creation flow.

1. `RootView` gains a third tab. The 3D playground tab can either stay or move under a Settings/dev panel — open question.
2. `CharacterListView` — scrollable list with name, class summary, level, portrait placeholder.
3. `CharacterCreationView` — multi-step `NavigationStack`: name → species → background → class → ability score assignment (**point-buy only** in v1, standard 27-point spread). Submit → `CharacterStore.create(...)`.
4. Guards: can't submit incomplete characters; point-buy must be valid.

**Concepts introduced:** Multi-step `NavigationStack` flows, form validation, `@Bindable` for sub-views editing a draft model.

## Phase E — Character sheet (read-only)

**Goal:** Tap a character, see the full sheet. No editing, no actions yet.

1. `CharacterSheetView` — header (name + class + level), stats block (six abilities + modifiers + saves), AC/HP/speed/initiative, proficiencies (skills with prof / expertise marked), equipped items, class features (level-1).
2. Primary visual-design phase — this is where your design work lands.

**Concepts introduced:** Composable sheet sub-views, `Grid` for the stats block, derived values.

## Phase F — Action engine + buttons + Dice handoff

**Goal:** The headline feature. Actions appear as buttons; tapping one pre-fills the Dice tab.

1. `ActionInterpreter` — pure function `(ActionRecipe, Character, ContentStore) -> ResolvedAction` where `ResolvedAction = (label, formula, mode)`. Covers the v1 primitives.
2. `CharacterSheetView` derives `[ResolvedAction]` from equipped weapons + class features + skill list + saves + ability checks. One button per action, grouped by category.
3. `@Observable PendingRollStore` injected at root; tapping an action sets its value.
4. `DiceRollerView` consumes pending rolls on appear / onChange, replaces the formula, clears the pending state.
5. `RootView` lifts `selectedTab` to `@State` so the Characters tab can switch focus.

**Tests:** ActionInterpreter against a fighter holding a longsword + shield → expected attack and damage formulas.

**Concepts introduced:** Pure-function interpreter design, cross-tab state, deep-linking via observable state.

## Phase G — Editing characters

**Goal:** Round-trip edits, including level-up.

1. Edit existing character: rename, hp, ac, equipped items, manual ability score overrides, notes.
2. Level-up flow — class feature choices per new level. Requires populating per-level features in the class JSON.
3. Inventory UI: pick from `ContentStore`, equip/unequip, attune.

**Concepts introduced:** Forms backed by drafts, optimistic updates, level-progression modeling.

## Phase H — Custom content import / export

**Goal:** User-supplied homebrew JSON.

1. Settings screen with an "Import content" button → `UIDocumentPicker`. Validates the JSON against the schema. On success copies into `Documents/Content/<filename>.json` and reloads `ContentStore`.
2. Per-character "Share" action exports the character's JSON via `ShareLink`.
3. Per-content-pack "Share" exports homebrew packs the same way.
4. Validation surfaces errors clearly — bad JSON shouldn't crash the app or fail silently.

**Concepts introduced:** `UIDocumentPicker` / `ShareLink`, schema validation, file-system layout discipline.

## Phase I — In-app content editor (deferred / stretch)

**Goal:** Create homebrew weapons / items / class features without leaving the app.

Substantial UI surface on its own — forms per content type plus an action-recipe builder. Schedule once A–H are stable and we've felt the pain of editing JSON by hand.

---

## Out-of-scope for v1

- Multi-user / sync / accounts
- iPad-specific layouts (we'll let SwiftUI's defaults adapt for now)
- Localization
- Initiative tracker, encounter management — separate future features in the same app
- Spells, leveling past 1, monsters/bestiary — see Character Sheet scope cuts above

---

## Working agreement

- One phase at a time. We'll confirm each phase is done (builds, runs, behaves as expected) before starting the next.
- When a phase introduces a new Swift/SwiftUI concept, we pause to make sure it's understood, not just typed.
- Commits at the end of each phase, with a message like `Phase N: <what>`.
