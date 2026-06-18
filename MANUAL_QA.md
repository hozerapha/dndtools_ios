# Manual QA Checklist

In-app test cases to run on the Simulator. The automated suite (`⌘U`) covers
pure logic; this doc covers the things only a running build reveals — tab
gating, navigation, picker wiring, sheet behavior, persistence across
relaunch. Several bugs we've shipped were invisible to unit tests and only
showed up here (the Spells tab being hidden for non-casters, species choices
not surfacing at creation), which is why this list exists.

## How to use
- Each feature area has a list of concrete, step-by-step cases with a checkbox.
- Status: `[ ]` not yet verified · `[x]` verified · `[~]` partial / known issue
  (leave a `— note:` after the case explaining what's off).
- Check boxes off as you test. It's fine to defer testing — the unchecked
  boxes are your worklist when you next sit down.
- **Claude updates this file whenever a user-facing feature is added or
  changed** (see CLAUDE.md), adding new cases as `[ ]` and re-opening boxes
  for cases whose behavior changed. Claude does not check boxes — verification
  is yours.

> **Recently changed — needs verification (2026-06-17):** the **Bard** class
> (see Classes below) is freshly authored. The Species epoch (creation pickers,
> breath weapon, granted spells, Giant Ancestry) is also still unverified.

---

## Character creation

- [ ] **Full happy path.** Create a character end to end (name → species →
  background → class → skills → abilities → review → save). It appears in the
  character list and opens to a populated sheet.
- [ ] **Debug autofill (DEBUG builds).** On the Ability Scores step, tap
  "Autofill (debug)". All six scores fill and the origin (background) bonus is
  assigned; "Next" becomes enabled immediately. Works on Point Buy, Array, and
  Roll methods.
- [ ] **Species with no choices skip the choices step.** Creating a Human /
  Dwarf / Halfling / Orc goes straight from Species to Background (no extra
  step).
- [ ] **Species with choices stop for them.** Creating a Dragonborn / Elf /
  Gnome / Goliath / Tiefling shows a "<Species> Traits" step after Species.
- [ ] **Picks persist onto the new character.** Pick Red Dragon (Dragonborn)
  at creation → open the sheet → the Breath Weapon is already fire-typed
  without visiting the Features tab.
- [ ] **Switching species clears stale picks.** Choose Tiefling, pick a
  legacy, go back, switch to Dragonborn → the Tiefling legacy pick is gone
  (no leftover selection).
- [ ] **Choices are optional.** Skip a species choice at creation, finish, then
  set it later on the Features tab — it takes effect.

## Species traits & choices (Features tab)

- [ ] **Lineage/ancestry/legacy pickers are editable post-creation.** On an
  existing Dragonborn/Elf/Gnome/Goliath/Tiefling, the Features tab shows the
  ancestry/lineage/legacy picker and the "Innate Spellcasting" ability picker;
  changing them updates the sheet.
- [ ] **Breath Weapon (Dragonborn).** Actions tab shows "Breath Weapon" as an
  Action that rolls 1d10 at L1–4, **scaling** to 2d10 (L5), 3d10 (L11), 4d10
  (L17). The damage type matches the chosen ancestry (Red→fire, White→cold,
  Green→poison, …); untyped only if no ancestry is chosen. Has a Proficiency-
  Bonus use counter.
- [ ] **Stonecunning (Dwarf).** Surfaces as a usable **Bonus Action** with a
  PB-uses counter (5.2.1 tremorsense wording), not a passive line.
- [ ] **Adrenaline Rush (Orc) / Large Form (Goliath L5).** Each surfaces as a
  Bonus Action with its own use counter.
- [ ] **Passive traits stay text-only.** Relentless Endurance, Powerful Build,
  Brave, Luck, etc. show on the Features tab with no action row.

## Spells & granted spells

- [ ] **Non-caster sees granted spells.** An Infernal Tiefling **Fighter** has
  a **Spells** tab (it should NOT be hidden) with a "Granted" section showing
  **Fire Bolt** + **Thaumaturgy**.
- [ ] **Level-gated grants.** That Tiefling shows only the cantrips at L1–2;
  **Hellish Rebuke** appears at L3 and **Darkness** at L5 (level the character
  up or create at those levels to check).
- [ ] **Legacy/lineage swap updates spells.** Switch the legacy from Infernal
  to Abyssal → Fire Bolt is replaced by Poison Spray.
- [ ] **Innate casting ability.** Cast Fire Bolt on a non-caster → the attack
  roll uses your highest of INT/WIS/CHA by default; setting the "Innate
  Spellcasting" pick to a specific ability overrides that.
- [ ] **Free cast (leveled grants).** For a granted leveled spell (e.g.
  Hellish Rebuke at L3+), the cast sheet shows a **"Cast free (Innate)"** path
  with a 1/Long-Rest counter; using it spends the counter, not a slot. A Long
  Rest refills it.
- [ ] **Caster + grants coexist.** A Tiefling Wizard shows both their prepared
  list and the Granted section without duplication.

## Actions & combat — Giant Ancestry (Goliath)

- [ ] **Granted actions are choice-gated.** Pick **Stone's Giant** → Actions
  tab shows "Stone's Endurance" as a **Reaction** that rolls **1d12 + CON**.
  Pick **Cloud's Giant** → "Cloud's Jaunt" Bonus Action. Pick **Storm's Giant**
  → "Storm's Thunder" Reaction rolling 1d8 thunder. Only the chosen one shows.
- [ ] **On-hit riders are choice-gated.** Pick **Fire's Giant** → a "Fire's
  Burn" chip appears on weapon attacks adding **+1d10 fire** to the damage roll.
  Pick **Frost's Giant** → "Frost's Chill" (+1d6 cold). Switching the pick
  swaps which chip appears; other giants show no rider.
- [ ] **Hill's Tumble** is descriptive only (no action row / chip).
- [ ] _Known gap:_ the "PB uses per Long Rest" limit on giant benefits is **not
  metered** — actions/riders are always available; track uses yourself.

---

## Classes

### Bard (new 2026-06-17)
- [OK] **Create a Bard.** Class skills step lets you pick **any 3** skills.
  Sheet opens with a Spells tab (Charisma caster) and slots.
- [OK] **Bardic Inspiration pool = CHA modifier.** A CHA 16 Bard shows
  **3 / 3** Bardic Inspiration uses; a CHA 10 Bard shows 1; it's a **Bonus
  Action** row on the Actions tab and decrements when tapped. A Long Rest
  refills it.
- [OK] **Expertise (L2) is editable.** The Features tab shows an Expertise
  picker offering only skills you're already proficient in; a 2nd Expertise
  pick appears at L9.
- [OK] **Subclass at L3.** Leveling to 3 prompts a "Choose a Bard College"
  picker with **College of Lore**; its L3 features (Bonus Proficiencies +
  Cutting Words) then appear on the Features tab.
- [OK] **College of Lore Bonus Proficiencies (L3)** grants 3 more skills via a
  picker; already-proficient skills are disabled in the list.
- [ ] **Spell slots scale as a full caster** — a high-level Bard has the right
  slots (e.g. a 9th-level slot at character level 17+).
- [ ] **Reaction features show as reactions.** Countercharm (L7), Cutting Words
  (L3) and Peerless Skill (L14) appear with a Reaction cost / on the Actions
  tab where applicable.
- [ ] **Jack of All Trades (L2) does the math.** On a level-2+ Bard, every
  skill you're NOT proficient in shows a **diagonal half-filled dot** (blue) in
  place of the empty circle, and that skill's modifier includes half your
  Proficiency Bonus (round down) — e.g. a level-5 Bard (PB 4) with DEX 14 shows
  Stealth at **+4** (+2 DEX +2 half-PB). Proficient (green check) / Expertise
  (yellow star) dots are unchanged and get no extra bonus. Rolling such a skill
  from the table carries the bonus into the dice tab, and passive Perception
  reflects it when Perception isn't proficient.
- [ ] _Known simplifications:_ Font of Inspiration's short-rest recovery is
  **not** auto-applied (pool refreshes on Long Rest — track short-rest manually);
  Magical Secrets / Magical Discoveries cross-list spell choices are
  descriptive, not auto-applied.

---

## Backlog to backfill (older features, not yet itemized here)

These shipped before this doc existed; add cases on demand when we next touch
them or when you want a full regression pass:

- [ ] Dice roller (3D tray, formulas, history, presets, advantage/disadvantage)
- [ ] Character sheet core (HP/CON, AC, initiative, rest, conditions,
  concentration, inventory/attunement)
- [ ] Class progression (leveling, subclasses, Expertise, Sneak Attack, Rage,
  Divine Smite, spell slots)
- [ ] Content import/export & SRD attribution
