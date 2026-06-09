# AGENTS.md — ROLLodex

> This file is written for AI coding agents. It describes the actual state of the codebase, not a target architecture. Read this before making changes.

---

## Project Overview

**ROLLodex** (repo `dndtools_ios`) is a SwiftUI iOS app that provides a toolset for tabletop RPG players (D&D 5e/5.5e SRD flavor). The active features are:
- A **physics-based 3D dice roller** with formula parsing, roll history, presets, advantage/disadvantage, and group modifiers (keep/drop/reroll).
- A **character sheet** with class progression (Fighter, Wizard, Rogue, Barbarian), subclass support, features, resources, inventory, spellcasting, and action rolling.

The full phased plan lives in `PLAN.md`.

The app name puns on Rolodex (rotating index of cards) + ROLL (dice).

---

## Technology Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.0+ |
| UI Framework | SwiftUI |
| Min iOS Target | 18.0 (`IPHONEOS_DEPLOYMENT_TARGET = 18.0`) |
| 3D Graphics | SceneKit (`SCNView`, `SCNScene`, `SCNPhysicsBody`) |
| State (local) | `@State` |
| State (shared) | `@Observable` classes injected via `.environment()` |
| Persistence | `UserDefaults` + `Codable` (JSON) |
| Tests | Swift Testing (`@Test`, `#expect`). 21 test files / ~285 tests covering models, content decoding, calculators, actions, resources, spells, conditions, and triggered effects. |
| Dependencies | None — no SwiftPM packages or CocoaPods. |

The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 26.4). **New Swift files added from outside Xcode are NOT live-detected**; the user must quit and relaunch Xcode for the navigator/build to see them. Editing existing files is live.

---

## Project Structure

```
ROLLodex/
  ROLLodex.xcodeproj/          # Xcode project — managed via Xcode, not by hand
  ROLLodex/
    App/
      RootView.swift           # TabView shell; injects HistoryStore, PresetStore, ContentStore, CharacterStore, PendingRollStore
    ROLLodexApp.swift          # @main entry point
    Features/
      DiceRoller/
        Models/                # Pure Swift types, no UI imports
          DieKind.swift
          DiceFormula.swift
          DiceGroup.swift
          GroupModifier.swift
          RollResult.swift
          DieRoll.swift
          RollMode.swift
          Preset.swift
          DiceRoller.swift     # Pure rolling logic + physics-result helpers
          DiceFormulaParser.swift
        State/                 # @Observable shared stores
          HistoryStore.swift   # UserDefaults-backed roll history (max 200 entries)
          PresetStore.swift    # UserDefaults-backed saved formulas
        Views/                 # SwiftUI views
          DiceRollerView.swift # Main dice tab; hosts the 3D tray + controls
          Dice3DPlaygroundView.swift  # Legacy SceneKit playground view (unreachable) + PRODUCTION DiceSceneController
          DiceTrayView.swift   # DEAD CODE — 2D fallback tray, zero references (deletion candidate)
          DieTokenView.swift   # DEAD CODE — only used by DiceTrayView (deletion candidate)
          DiePickerView.swift  # Tap to add, long-press to remove
          FormulaBarView.swift # Displays formula; tap to edit via text parser
          HistorySheet.swift   # Bottom sheet of past rolls
          PresetRowView.swift  # Horizontal scroll of saved presets
          SavePresetSheet.swift
      CharacterSheet/
        Content/               # JSON schema definitions & interpreters
          ClassDefinition.swift
          FeatureDefinition.swift
          FeatureSelection.swift
          ActionRecipe.swift
          ActionInterpreter.swift
          CharacterActionDeriver.swift
          TriggeredEffect.swift
          TriggeredEffectResolver.swift
          ResourceDefinition.swift
          SpellDefinition.swift
          WeaponDefinition.swift
          ArmorDefinition.swift
          ItemDefinition.swift
          ConditionDefinition.swift
          (and more)
        Models/                # Character data models
          Character.swift
          CharacterCalculator.swift
          CharacterDraft.swift
          ProficiencyKey.swift
          ProficiencyLevel.swift
          Skill.swift
          Ability.swift
          (and more)
        State/                 # @Observable stores
          CharacterStore.swift # File-system persisted characters
          ContentStore.swift   # Bundled JSON loader
          PendingRollStore.swift # Cross-tab action handoff
        Views/                 # SwiftUI views
          CharacterSheetView.swift
          CharacterListView.swift
          CharacterCreationView.swift
          FeaturesView.swift
          LevelUpSheet.swift
          ActionButtonGrid.swift
          (and more)
    Assets.xcassets/           # Dice face textures (d4–d20, d10 for d100), tray wood/felt images
    Resources/
      Content/                 # Bundled SRD JSON: classes, species, backgrounds, weapons, armor, gear, spells, conditions
```

Tests live in `ROLLodexTests/` and use Swift Testing.

---

## Build & Run

The user builds and runs through **Xcode** (⌘R) on the iOS Simulator. There is no CLI build step. Do not invoke `xcodebuild` yourself.

- **Bundle ID**: `com.jcol.ROLLodex`
- **Development Team**: `Y282A8VYJU`
- **Product**: `ROLLodex.app`

---

## Code Organization Rules

Follow the conventions already used in the codebase:

1. **One type per file**; filename matches the type name.
2. **Pure model logic** (formulas, rolling, parsing) goes in plain `struct`s with no UI imports (`SwiftUI`, `SceneKit`, etc.). Keep them testable.
3. **Views stay small**. If a `body` gets long, extract subviews into private `struct`s within the same file or new files.
4. **Value types by default** (`struct`). Use `class` only when identity / shared mutable state is required (`@Observable`).
5. **No comments that restate the code**. Comments are for hidden constraints, non-obvious *why*, or math derivations (see `Dice3DPlaygroundView.swift` for extensive examples).
6. **Prefer modern SwiftUI APIs**: `.sensoryFeedback`, `.presentationDetents`, `NavigationStack`, `@Observable`, `contentTransition(.numericText())`.

---

## 3D Dice Architecture

The 3D dice system lives almost entirely in `Dice3DPlaygroundView.swift`. It is a single `@MainActor` `DiceSceneController` that manages:

- **Procedural geometry** for d4, d6, d8, d10, d12, d20 (vertices, face normals, UV mapping).
- **Physics simulation** via SceneKit (`SCNPhysicsBody`, `physicsWorld.speed = 3.0`).
- **Tray construction** — wood-walled box with felt floor, invisible ceiling to prevent escape.
- **Rest detection** — polls at ~60 Hz; requires all dice to be still (velocity + angular thresholds + frame-to-frame position/orientation stability) continuously for 0.5 s before snapshotting face values.
- **Face reading** — compares each face's outward normal against world +Y (or -Y for d4) to determine the rolled value.
- **d100 handling** — compound kind rendered as two d10 nodes (tens + ones) with an arched connector line after settling.
- **Magnifier** — press-and-hold on the tray hit-tests a die, positions a top-down camera, and renders a zoomed overlay via a second `SCNView`.
- **Dimming** — dropped dice (from `kh`/`kl`/`dh`/`dl` modifiers) are visually dimmed after settling.

The `DiceRollerView` drives the controller through an async flow:
1. `controller.rollAllAsync()` — physics-roll every die.
2. `DiceRoller.rerollIndices(formula:values:)` — determine which dice need physical rethrows.
3. `controller.rethrowDiceAsync(at:)` — rethrow those dice.
4. `DiceRoller.resultFrom(formula:values:mode:)` — build a canonical `RollResult` (applies keep/drop logic).
5. `controller.setDimmed(formulaIndices:)` — fade dropped dice.

---

## State & Persistence

| Store | Type | Scope | Persistence | Key / Location |
|---|---|---|---|---|
| `HistoryStore` | `@Observable class` | Environment | `UserDefaults` | `history.rolls.v2` — JSON-encoded `[RollResult]`, max 200 entries. |
| `PresetStore` | `@Observable class` | Environment | `UserDefaults` | `presets.v2` — JSON-encoded `[Preset]`. |
| `CharacterStore` | `@Observable class` | Environment | File System | `Documents/Characters/<uuid>.json` + `manifest.json`. Atomic writes. |
| `ContentStore` | `@Observable class` | Environment | Bundled JSON | Loaded from app bundle at init (not persisted). |
| `PendingRollStore` | `@Observable class` | Environment | In-memory only | Cross-tab handoff queue. |

All stores read from their source on `init` and write on every mutation. No debouncing currently.

---

## Formula & Parsing

`DiceFormula` is a value type containing `[DiceGroup]` + an integer modifier. A group is a count of a `DieKind` with an optional `GroupModifier`:

- `.keepHighest(Int)` / `.keepLowest(Int)`
- `.dropHighest(Int)` / `.dropLowest(Int)`
- `.rerollOnceIfAtMost(Int)`

`DiceFormulaParser` accepts strings like `2d6+1d20+3`, `3d6kh2`, `4d6dl1`, `2d6r1`. It validates die sizes against `DieKind` and enforces modifier sanity (e.g. can't keep more dice than rolled).

Advantage/disadvantage (`RollMode`) is only enabled when the formula is exactly one plain d20.

---

## Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). The test target covers:
- Pure model types (`DiceFormula`, `DiceRoller`, `DiceFormulaParser`)
- Content decoding and bundled JSON invariants
- `CharacterCalculator` (modifiers, AC, spell DC, weapon mastery)
- `ActionInterpreter` and `CharacterActionDeriver`
- `TriggeredEffectResolver` (automatic riders, opt-in chips)
- Character Codable round-trips and migrations
- Feature selections, subclasses, ASI mechanics, level-up flow

Do not add XCTest unless explicitly asked.

---

## What Not to Do

- Do not pre-implement future phases of `PLAN.md`.
- Do not introduce architectural patterns (MVVM, Coordinators, Redux, etc.) before actual complexity justifies them. SwiftUI + `@Observable` is sufficient for the current scope.
- Do not add SwiftPM packages or third-party dependencies without proposing them first.
- Do not modify `.xcodeproj` by hand.
- Do not write code requiring a paid Apple Developer account without flagging it.

---

## Security & Privacy Considerations

- No network code exists.
- No keychain usage.
- User data (history, presets) is stored in `UserDefaults` (unencrypted). Character data lives in `Documents/Characters/` as one JSON file per character plus a `manifest.json`, written atomically.
- No analytics or tracking code.

---

## Useful References

- `PLAN.md` — Phased implementation plan for the dice roller (all shipped) + original character-sheet outline.
- `PLAN_CharacterSheet.md` — The live character-sheet plan: phase status table, shipped-reality notes, and the **"What's next" roadmap** (start here when picking up work).
- `CLAUDE.md` — Original collaboration guidelines for this repo. (Note: its "min iOS 17.0" line is stale — the project's actual `IPHONEOS_DEPLOYMENT_TARGET` is 18.0, as recorded above.)
