# CLAUDE.md

Guidance for Claude when working in this repository.

## Project

`dndtools_ios` — a SwiftUI iOS app that will become a toolset for tabletop RPG (D&D 5e-flavored) players. The first feature is a **dice roller**; more tools (initiative tracker, character sheet, spell lookup, etc.) will be added later, so the app shell is built around a `TabView` with room to grow.

The full feature breakdown for the dice roller and the phased build plan live in [PLAN.md](PLAN.md). Read it before suggesting structural changes.

## Collaboration mode

**The user is learning Swift while building this.** Do not write large multi-file features in one shot. Instead:

- Work one phase of `PLAN.md` at a time. Pause for confirmation between phases.
- When introducing a new Swift/SwiftUI concept (e.g. `@State`, `@Observable`, `Codable`, gestures, `.sheet`), briefly explain *why* it's the right tool here — not just *what* to type.
- Prefer guiding the user to write code over writing it for them. When you do write code, keep it short and explain the unfamiliar parts.
- If asked "what should I write here?", give a direct, small answer with one line of context — not a tutorial.

## Tech stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Min iOS target:** 17.0 (so we can use `@Observable`, modern `NavigationStack`, `.sensoryFeedback`, `.presentationDetents`, etc.)
- **State:** `@State` for local view state; `@Observable` classes for shared state (history, presets), injected via the environment.
- **Persistence (v1):** `UserDefaults` + `Codable`. Migrate to **SwiftData** when the data model gets richer.
- **3D dice (later):** RealityKit.
- **Tests:** Swift Testing (`@Test`, `#expect`).

When a tech choice isn't covered above, propose one and confirm before adopting.

## Project layout (target)

```
DnDTools/                  # Xcode project lives here
  DnDTools/
    App/                   # @main App, RootView, TabView shell
    Features/
      DiceRoller/
        Models/            # DieKind, DiceFormula, RollResult, DiceRoller
        Views/             # DiceRollerView, DiceTrayView, DieTokenView, ...
        State/             # HistoryStore, PresetStore (@Observable)
    Shared/                # cross-feature utilities (when they appear)
  DnDToolsTests/
```

Don't create folders before there's something to put in them.

## Coding conventions

- One type per file; filename matches the type.
- Pure model logic (formulas, rolling, scoring) goes in plain `struct`s with no UI imports — keep them testable.
- Views stay small. If a `body` is getting long, extract subviews.
- Use value types (`struct`) by default; reach for `class` only when identity / shared mutable state is required (which is what `@Observable` is for).
- No comments that just restate the code. Comments are for hidden constraints or non-obvious *why*.
- Prefer modern SwiftUI APIs (the iOS 17+ ones listed above) over their older equivalents.

## What not to do

- Don't pre-implement future phases of `PLAN.md`. Stay in the current phase.
- Don't introduce architectural patterns (MVVM, Coordinators, Redux-likes, etc.) before they're justified by actual complexity. SwiftUI + `@Observable` is enough for now.
- Don't add dependencies / SwiftPM packages without proposing them first.
- Don't generate or modify the `.xcodeproj` by hand — the user creates and manages it via Xcode.
- Don't write code that requires a paid Apple Developer account (push notifications, certain capabilities) without flagging it.

## Building & running

The user builds and runs through Xcode (⌘R) on the iOS Simulator. There is no CLI build step assumed. If you need to verify a build, ask the user to run it and report errors back rather than invoking `xcodebuild` yourself.
