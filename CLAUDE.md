# CLAUDE.md

Guidance for Claude when working in this repository.

## Project

**ROLLodex** (repo: `dndtools_ios`) — a SwiftUI iOS app that will become a toolset for tabletop RPG (D&D 5e-flavored) players. The name puns on Rolodex (a rotating index of cards) + ROLL (dice). The first feature is a **dice roller**; more tools (initiative tracker, character sheet, spell lookup, etc.) will be added later, so the app shell is built around a `TabView` with room to grow.

The full feature breakdown for the dice roller and the phased build plan live in [PLAN.md](PLAN.md); the character sheet (the second major feature, now substantially shipped: classes, leveling, spells, resources, conditions, triggered effects) has its own live plan in [PLAN_CharacterSheet.md](PLAN_CharacterSheet.md). Read those before suggesting structural changes.

## Collaboration mode

**Speed-to-stable-app over step-by-step pedagogy.** The user is learning Swift but prefers to read/run working code rather than be walked through every concept. So:

- Write the code. Keep responses tight — explain only the unfamiliar or non-obvious parts.
- It's fine to ship multi-file changes when a feature genuinely needs them.
- `PLAN.md` is a reference for scope, not a rigid phase gate — work to whatever the user is asking for now.
- If asked "what should I write here?", give a direct, small answer — not a tutorial.

## Tech stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Min iOS target:** 18.0 (`IPHONEOS_DEPLOYMENT_TARGET = 18.0` in the project; gives us `@Observable`, modern `NavigationStack`, `.sensoryFeedback`, `.presentationDetents`, etc.)
- **State:** `@State` for local view state; `@Observable` classes for shared state (history, presets), injected via the environment.
- **Persistence (v1):** `UserDefaults` + `Codable`. Migrate to **SwiftData** when the data model gets richer.
- **3D dice:** SceneKit (`SCNView` / `SCNScene` / `SCNPhysicsBody`). RealityKit was tried first but its physics was hard to tune for natural dice behavior; SceneKit + default physics + `physicsWorld.speed = 3` matches D&D-Beyond-style feel. Reference implementation lived at `/Users/josecolina/gitpersonal/DiceRollDemo`.
- **Tests:** Swift Testing (`@Test`, `#expect`).

When a tech choice isn't covered above, propose one and confirm before adopting.

## Project layout (target)

```
ROLLodex/                  # Xcode project lives here
  ROLLodex/
    App/                   # @main App, RootView, TabView shell
    Features/
      DiceRoller/
        Models/            # DieKind, DiceFormula, RollResult, DiceRoller
        Views/             # DiceRollerView, DiceTrayView, DieTokenView, ...
        State/             # HistoryStore, PresetStore (@Observable)
    Shared/                # cross-feature utilities (when they appear)
  ROLLodexTests/
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

## Manual QA checklist

[MANUAL_QA.md](MANUAL_QA.md) is a living checklist of in-app, manual test cases (the things `⌘U` can't catch — tab gating, navigation, picker wiring, sheet behavior, persistence). **Whenever you implement or change a user-facing feature, add or update its cases there**, written as concrete step-by-step actions with a `[ ]` checkbox and an expected result. Re-open (`[ ]`) any existing case whose behavior changed. Do **not** check boxes off yourself — verification is the user's; you only author the cases. Mention in your summary which MANUAL_QA.md cases are new/affected so the user knows what to test.

## New files & Xcode

Xcode 26.4's `PBXFileSystemSynchronizedRootGroup` does **not** live-detect Swift files added from outside Xcode. After any new file is created, the user has to ⌘Q and relaunch Xcode for the navigator/build to see it. This is a known annoyance, not a blocker — don't avoid creating new files when they're the right call. Just:

- Flag at the top of the message that new files were added, so the user knows to restart Xcode.
- Batch new files together when convenient (one restart instead of three), but don't contort the design to avoid them.
- Editing existing files is live — no restart needed.
