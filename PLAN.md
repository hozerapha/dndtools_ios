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

## Out-of-scope for v1

- Multi-user / sync / accounts
- iPad-specific layouts (we'll let SwiftUI's defaults adapt for now)
- Localization
- Other TTRPG features (initiative tracker, character sheet, etc.) — those are separate later projects in the same app

---

## Working agreement

- One phase at a time. We'll confirm each phase is done (builds, runs, behaves as expected) before starting the next.
- When a phase introduces a new Swift/SwiftUI concept, we pause to make sure it's understood, not just typed.
- Commits at the end of each phase, with a message like `Phase N: <what>`.
