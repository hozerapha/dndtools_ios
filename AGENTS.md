# AGENTS.md — ROLLodex

> This file is written for AI coding agents. It describes the actual state of the codebase, not a target architecture. Read this before making changes.

---

## Project Overview

**ROLLodex** (repo `dndtools_ios`) is a SwiftUI iOS app that provides a toolset for tabletop RPG players (D&D 5e/5.5e SRD flavor). The first and currently active feature is a **physics-based 3D dice roller** with formula parsing, roll history, presets, advantage/disadvantage, and group modifiers (keep/drop/reroll). A **character sheet** feature is planned but not yet implemented — the full phased plan lives in `PLAN.md`.

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
| Tests | None currently exist. Swift Testing (`@Test`, `#expect`) is the intended framework. |
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
          Dice3DPlaygroundView.swift  # Legacy SceneKit playground; not shown in TabView
          DiceTrayView.swift   # 2D fallback tray (wood/felt background, token grid)
          DieTokenView.swift   # 2D die token with colored shape + number
          DiePickerView.swift  # Tap to add, long-press to remove
          FormulaBarView.swift # Displays formula; tap to edit via text parser
          HistorySheet.swift   # Bottom sheet of past rolls
          PresetRowView.swift  # Horizontal scroll of saved presets
          SavePresetSheet.swift
    Assets.xcassets/           # Dice face textures (d4–d20, d10 for d100), tray wood/felt images
```

There is no test target or test files in the repository yet.

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

| Store | Type | Scope | Key | Notes |
|---|---|---|---|---|
| `HistoryStore` | `@Observable` | Environment | `history.rolls.v2` | Max 200 entries; JSON-encoded `[RollResult]` |
| `PresetStore` | `@Observable` | Environment | `presets.v2` | JSON-encoded `[Preset]` |

Both stores read from `UserDefaults` on `init` and write on every mutation. There is no debouncing currently.

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

**There are no tests in the repository right now.** When you add tests, use **Swift Testing** (`import Testing`, `@Test`, `#expect`). The pure model types (`DiceFormula`, `DiceRoller`, `DiceFormulaParser`) are designed to be fully testable with no UI or framework dependencies.

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
- User data (history, presets) is stored in `UserDefaults` (unencrypted). Character data (when implemented) is planned for `Documents/Characters/` as JSON.
- No analytics or tracking code.

---

## Useful References

- `PLAN.md` — Full phased implementation plan (dice roller + character sheet).
- `CLAUDE.md` — Original collaboration guidelines for this repo.
