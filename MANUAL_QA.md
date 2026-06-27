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

> **Recently changed — needs verification:** the **Settings page + Natural 20
> crit styles** (2026-06-27, new — see "Settings & critical-hit styles"); the
> **QA P0 quick batch**
> (2026-06-27, mostly covered by unit tests — see "QA fixes" below); the
> **Sorcerer** class + mechanics pass (Unarmored Defense, feature HP, granted
> subclass spells, Innate Sorcery), which also fixed **Barbarian Unarmored
> Defense** and **Dwarven Toughness**; the **Bard** class (2026-06-17); and the
> Species epoch.

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

## Settings & critical-hit styles (new 2026-06-27)

- [ ] **Settings → Combat shows a "Natural 20 style" picker** with: Off, Double
  the dice (RAW, default), Double the rolled value, Max die + roll, Maximize
  dice, Double the total. The footer explains the selected style.
- [ ] **Choice persists across relaunch.** Pick a non-default style, force-quit,
  relaunch → it's still selected.
- [ ] **Crit applies on the damage follow-up.** Roll a weapon (or spell) attack
  that lands a **natural 20**; the damage chip reads **"Roll critical damage"**
  and its subtitle shows the transformed dice. Each style:
  - Double the dice → e.g. a greatsword's `2d6+3` becomes `4d6+3`.
  - Double the rolled value → rolls `2d6`, the total doubles the dice you rolled, +3.
  - Max die + roll → `12 + 2d6 + 3`.
  - Maximize → every damage die shows its max (e.g. all 6s).
  - Double the total → dice doubled and the +3 becomes +6.
  - Off → damage rolls normally (no crit change).
- [ ] **No crit on a dropped 20.** With disadvantage, a 20 that gets dropped
  (keep-lowest) is NOT a crit — damage rolls normally.
- [ ] **Non-crit attacks unaffected.** A normal hit's damage chip is unchanged.
- [ ] _Note:_ crit applies to the attack→damage follow-up (weapon + spell
  attack rolls), not to manual dice-tab rolls with no attack context.

## Stackable damage riders (changed 2026-06-27)

Riders (Sneak Attack, Divine Smite, Fire's Burn, …) are no longer mutually-
exclusive chips — they're independent **toggles** stacked onto one damage roll.

- [ ] **Riders are toggles, not one-shot chips.** After an attack, the rail
  shows a "Roll damage" chip plus a toggle per available rider. Tapping a rider
  highlights it (and updates the "Roll damage" subtitle to the combined dice);
  tapping again turns it off. Tapping "Roll damage" rolls base + all active
  riders as one roll.
- [ ] **Stacking works.** A Paladin/Rogue multiclass can turn on **both** Sneak
  Attack and Divine Smite and roll them together (previously impossible).
- [ ] **Cost paid only at roll time.** Toggling a rider on/off spends nothing;
  switching tabs without rolling spends nothing. Only tapping "Roll damage"
  spends each active rider's resource (Sneak Attack once-per-turn flag, Divine
  Smite spell slot). [Fixes the rider half of QA audit #2.]
- [ ] **Crit doubles every active rider.** On a nat-20, "Roll critical damage"
  applies the crit style to the whole combined formula — weapon + Sneak Attack +
  Smite dice all transform.
- [ ] **Divine Smite slot level** still shows in the toggle label ("Divine
  Smite (L1 slot)") and consumes the slot it names.
- [ ] **Once-per-turn riders disappear after use.** After firing Sneak Attack,
  it's gone from the rail until Start New Turn clears the flag.

## Selection pickers — no double-grants (fixed 2026-06-27)

- [ ] **Second Expertise doesn't re-offer existing expertise.** A Rogue picks
  Expertise at L1; at L6 the second Expertise picker shows the L1-chosen skills
  as **disabled** with "Already expertise" (can't pick them twice). Same for a
  **Bard** (L2 + L9 Expertise). The current picker's own picks stay toggleable.
- [ ] **Class-skill pickers still exclude already-proficient skills** (existing
  behavior unchanged — "Already proficient").

## QA fixes (P0 quick batch, 2026-06-27)

Mostly unit-tested; two have an in-app surface worth a quick check:

- [ ] **Formula bar accepts `min` + keep/drop.** Type `1d20kh1min10` (and
  `1d20min10kh2`) into the dice formula bar — both parse and roll (previously
  rejected). `1d20min` (no number) still errors.
- [ ] **Reliable Talent floor applies to a class-skill proficiency.** A Rogue 7+
  whose proficiency in a skill came from the class skill-choice (not a
  background) rolls that skill **with the floor** — roll it with advantage and
  the dice tab shows `2d20kh1min10`, not `1d20`.

## Classes

### Bard (new 2026-06-17)
- [OK] **Bard core verified** — creation (any-3 skills, Charisma caster),
  Bardic Inspiration pool = CHA mod (Bonus Action, refills on Long Rest),
  Expertise L2/L9 editable, College of Lore at L3 (Bonus Proficiencies +
  Cutting Words), full-caster slots, and reaction features (Countercharm,
  Cutting Words, Peerless Skill) all confirmed.
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

### Sorcerer (new 2026-06-27)
- [ ] **Create a Sorcerer.** Class skills step offers exactly 6 options
  (Arcana, Deception, Insight, Intimidation, Persuasion, Religion), choose 2.
  Sheet opens with a Spells tab (Charisma caster, no armor).
- [ ] **Innate Sorcery (L1)** is a **toggle** Bonus Action (2 / Long Rest):
  activating it shows an active effect; **while active**, the cast sheet shows
  your **Spell Save DC +1** and **Advantage** on spell-attack rolls (the spell
  attack rolls 2d20-keep-highest), and "End Innate Sorcery" appears. Ending it
  (or a Long Rest) clears the buff.
- [ ] **Sorcery Points (L2 Font of Magic)** appear as a **counter** (in the
  resources card), value equal to your Sorcerer level (2 at L2, 5 at L5, …),
  and are NOT a tappable action row. A Long Rest refills them. None at L1.
- [ ] **Metamagic (L2)** shows on the Features tab as a picker with **2**
  choices at L2, growing to **4** at L10 and **6** at L17, from the 10 options.
- [ ] **Subclass at L3** prompts "Choose a Sorcerous origin" with **Draconic
  Sorcery**; its features appear as you level (Draconic Resilience + Draconic
  Spells at L3, Elemental Affinity at L6, Dragon Wings at L14).
- [ ] **Elemental Affinity (L6)** offers a damage-type picker (Acid/Cold/Fire/
  Lightning/Poison) on the Features tab.
- [ ] **Dragon Wings (L14)** is a Bonus Action with a 1 / Long Rest counter.
- [ ] **Draconic Resilience (L3)** — once Draconic Sorcery is chosen, the
  character's **AC while unarmored is 10 + DEX + CHA**, and **max HP increases
  by your sorcerer level** (e.g. +3 at L3, +5 at L5). Leveling up adds 1 more.
- [ ] **Draconic Spells** become always-prepared on the Spells tab by tier:
  L3 (Alter Self, Chromatic Orb, Command, Dragon's Breath), L5 (Fear, Fly),
  L7 (Arcane Eye, Charm Monster), L9 (Legend Lore, Summon Dragon).
- [ ] **Full-caster slots** — a high-level Sorcerer reaches a 9th-level slot.
- [ ] _Known simplifications:_ Sorcery-point spending (Metamagic, creating/
  converting slots) and Sorcerous Restoration's short-rest recovery remain
  **manual** (the points counter is adjusted by hand). Summon Dragon's stat
  block is text-only. "Sorcerer spells" advantage/DC applies to all the
  character's spells (single-class assumption).

### Cross-class fixes from the Sorcerer pass (verify these too)
- [ ] **Barbarian Unarmored Defense** now actually computes: a no-armor
  Barbarian's AC is **10 + DEX + CON** (previously the feature did nothing).
- [ ] **Dwarven Toughness** now actually adds HP: a Dwarf's max HP is **+1 per
  character level** (previously descriptive only).

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
