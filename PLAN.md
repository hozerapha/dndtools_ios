# dndtools_ios — Implementation Plan

A TTRPG toolset for iOS. **First feature: Dice Roller** (shipped). Active work
has moved to the character manager — see **[PLAN_CharacterSheet.md](PLAN_CharacterSheet.md)**.
This file is now a historical trace of the dice-roller build + the early
character-sheet planning that PLAN_CharacterSheet.md superseded.

---

## Status

**Dice-roller phases 0–11 are all shipped.** Phase 11 (3D dice) uses
**SceneKit + default physics + `physicsWorld.speed = 3`** rather than RealityKit
(RealityKit physics was hard to tune; rationale in `CLAUDE.md` → "Tech stack").
All other phase tech choices stuck.

Bonus capabilities shipped on top of the original phases (driven mostly by the
character-sheet plan's Phase N and the action engine):

- **Per-type damage breakdown** chip under the tray total + in history rows (`DamageBreakdownView`).
- **Die-by-type colored glow** (inverted-hull shell tinted per `DamageType`).
- **Parser support for typed groups + typed flat modifiers** — `[fire]2d6 + [necrotic]3 + 2` round-trips.
- **Follow-up chip rail** in the dice tab — chained damage (attack → damage) + opt-in/toggle rider chips (Sneak Attack, Rage, …); tapping one clears the rail.
- **Compact dice-formula display** (`DiceFormula.compactDisplayString`) for chip subtitles.
- **`PendingRollStore`** cross-tab handoff with `followUps` + `pendingCostsToApply` side channels.
- **Per-die minimum values** — `DiceGroup.minimumValue` (Reliable Talent's floor); parser round-trips `1d20min10`.
- **Stroke of Luck prompt** — post-roll chip flips a rolling Rogue's d20 to 20, consuming the resource.

**Known dead code (deletion candidates — confirmed zero references; remove via Xcode when convenient, per the never-delete rule):**
`DiceRoller/Views/DiceTrayView.swift` (2D fallback tray, superseded by 3D),
`DiceRoller/Views/DieTokenView.swift` (only used by DiceTrayView),
`DiceRoller/Views/Dice3DPlaygroundView.swift` (unreachable sandbox; prod controller lives in `DiceSceneController.swift`),
`Resources/Content/spells.json` (superseded by per-level split at `Resources/Content/Spells/SRD/L0.json`…`L9.json`; `ContentStore` no longer reads it, but it still ships in the bundle until removed via Xcode).

---

## Tech choices

| Concern | Choice | Why |
|---|---|---|
| UI framework | **SwiftUI** | Modern declarative UI. |
| Min iOS target | **iOS 18+** | `@Observable`, `.sensoryFeedback`, modern `NavigationStack`, `.presentationDetents`. |
| State | `@State` local, `@Observable` for shared (history, presets) | Replaces `ObservableObject`/`@Published`. |
| Persistence | `UserDefaults` + `Codable` for dice state; JSON files for content/characters | Migrate to SwiftData only if the model gets richer. |
| Tests | **Swift Testing** (`@Test`, `#expect`) | Lighter than XCTest. |
| 3D dice | **SceneKit** (not RealityKit) | Physics easier to tune for natural dice. |

---

## Dice Roller — phase changelog (all shipped)

- **0** Project setup — buildable SwiftUI app, iOS deployment target.
- **1** App shell — `TabView` with room to grow.
- **2** Domain models — `DieKind`, `DiceFormula`, `RollResult`, `DiceRoller`.
- **3** Static dice-roller UI.
- **4** Wire up state (`@Observable` stores, environment injection).
- **5** Rolling logic.
- **6** Dice tray (originally 2D — later replaced by the 3D SceneKit tray).
- **7** Roll history bottom sheet.
- **8** Persistence — history + presets via `UserDefaults` + `Codable`.
- **9** Advantage / disadvantage (`2d20kh1` / `2d20kl1`).
- **10** Polish — haptics & sound.
- **11** 3D dice — SceneKit physics tray with rest detection + magnifier.

---

## Character Sheet (early plan — superseded)

The character manager for **D&D 5.2.1 (5.5e SRD)** was originally sketched here
as Phases A–I. **That work is live and tracked in
[PLAN_CharacterSheet.md](PLAN_CharacterSheet.md)** (architecture decisions,
schemas, shipped changelog, the QA remediation plan, and remaining work). The
A–I sketch is intentionally dropped from this file to avoid two sources of
truth; the locked-in decisions (data-driven `ActionRecipe`s, content/character
storage split, `PendingRollStore` handoff, JSON-over-SwiftData) carried forward
verbatim into that doc.

---

## Out-of-scope for v1

- Multi-user / sync / accounts (online group-play is a planned later feature)
- iPad-specific layouts, localization
- Initiative tracker / encounter management — separate future features
- Bestiary / monsters

---

## Working agreement

- Speed-to-stable-app over step-by-step pedagogy (see `CLAUDE.md`).
- Commits only when the user explicitly asks; one feature/batch per commit.
