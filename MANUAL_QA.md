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

> **Recently changed — needs verification:** the **Ranger** class + Hunter
> (2026-07-06, new — see "Ranger" under Classes) — **the class catalog is
> now complete (12/12 classes, 12/12 subclasses)** and this pass also shipped
> a prep-cap fix so Bard/Sorcerer/Ranger are gated by their `spellsKnown`
> table instead of ability mod; the **Monk** class + Warrior of the Open Hand
> (2026-07-06, new — see "Monk" under Classes; shared Focus pool, scaling
> Martial Arts die, unarmored speed bonus, and an unarmed-strike proficiency
> fix that affects every class); the **Warlock** class + Fiend Patron
> (2026-07-02, new — see "Warlock" under Classes; first pact-magic caster +
> Eldritch Blast) and the **subclass backfill** — Path of the Berserker, Oath
> of Devotion, Evoker (2026-07-02, new — see "Subclass backfill" under
> Classes); the **Settings page + Natural 20
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
- [ ] **Split-catalog spell load (2026-07-10 refactor).** Cold-launch the app
  (kill from app switcher first). Create a Wizard. Open **Add Spell**. The
  picker shows spells for **every** level 0–9 (spot-check: Fire Bolt at L0,
  Magic Missile at L1, Fireball at L3, Wall of Fire at L4, Meteor Swarm at
  L9). Settings → Content shows no "Missing bundled content" or "Duplicate id"
  errors. Bundle now loads spells from `Content/Spells/SRD/L*.json` (10 files)
  instead of a single `spells.json`.
- [ ] **SRD 5.2.1 compliance audit — cantrip picker (2026-07-11).** Create a
  Druid. Open **Add Spell** at cantrip level. Confirm **Thorn Whip** and
  **Thunderclap** are NO LONGER in the picker (they were 2014-PHB, not SRD).
  Confirm **Message** now appears in the Druid list. Confirm **Elementalism**
  appears at L0 for druid/sorcerer/wizard. For a Sorcerer specifically,
  confirm **Sorcerous Burst** appears at L0.
- [ ] **SRD 5.2.1 compliance — smites (2026-07-11).** Create a Paladin. Open
  Add Spell. Confirm Thunderous / Wrathful / Branding / Blinding Smite are
  NO LONGER available (5.2.1 folded them into a single Divine Smite spell +
  Divine Smite class feature). Confirm **Divine Smite** (the spell) is now
  available for the Paladin at L1 with `+1d8 radiant per slot level` scaling.
- [ ] **SRD 5.2.1 compliance — L6 renames (2026-07-11).** Confirm **Otto's
  Irresistible Dance** is no longer available; **Irresistible Dance** (the
  5.2.1 canonical name) is available at L6 for bard/wizard.
- [ ] **SRD 5.2.1 compliance — Feeblemind replaced (2026-07-11).** At L8,
  confirm **Feeblemind** is gone; **Befuddlement** (its SRD 5.2.1 successor)
  is available for bard/druid/warlock/wizard.
- [ ] **SRD 5.2.1 compliance — new adds (2026-07-11).** Spot-check the spell
  picker for at least three of the newly authored spells: **Hideous Laughter**
  (L1, bard/warlock/wizard), **Blink** (L3, sorcerer/wizard), **Vitriolic
  Sphere** (L4, sorcerer/wizard), **Power Word Heal** (L9, bard/cleric).
- [ ] **SRD 5.2.1 conditions — Exhaustion added (2026-07-11).** Open Conditions
  from a character sheet. The list now has 15 conditions (was 14) — verify
  **Exhaustion** appears in the picker with the "cumulative levels; 6 kills you"
  description. Applying it should show up on the sheet like other conditions
  (the specific mechanical scaling — Speed/roll penalties per level — is
  honor-system for now, not automatically applied).
- [ ] **SRD 5.2.1 gear renames (2026-07-11).** In the inventory/equipment
  picker, confirm the entries formerly labelled "Rations (1 day)" and
  "Rope, Hempen (50 feet)" now display as **Rations** and **Rope**
  respectively (the SRD 5.2.1 canonical names).
- [ ] **SRD 5.2.1 class feature backfill (2026-07-11).** For each class,
  level up (or create at a specific level) and confirm the newly authored
  features appear in the Features tab and on level-up preview:
  - **Barbarian**: Danger Sense + Reckless Attack at L2; Primal Knowledge
    at L3; Fast Movement at L5; Feral Instinct + Instinctive Pounce at L7;
    Brutal Strike at L9; Relentless Rage at L11; Persistent Rage at L15;
    Indomitable Might at L18; Primal Champion at L20.
  - **Fighter**: Tactical Mind at L2; Tactical Shift at L5; Indomitable
    at L9/13/17; Tactical Master at L9; Two Extra Attacks at L11;
    Studied Attacks at L13; Three Extra Attacks at L20.
  - **Wizard**: Ritual Adept at L1; Scholar at L2; Memorize Spell at L5;
    Spell Mastery at L18; Signature Spells at L20.
  - **Druid**: Wild Resurgence at L5; Elemental Fury at L7; Improved
    Elemental Fury at L15.
  - **Warlock**: L11/13/15/17 Mystic Arcanum entries now display as
    plain **Mystic Arcanum** (not "Mystic Arcanum (6th)/(7th)/…").
  - **Ranger**: L1 Spellcasting now surfaced as a feature; L6 Roving
    replaces the old L5 placement; L3 no longer shows Primal Awareness
    (2014 leftover, removed).
  - **Paladin**: Abjure Foes at L9.
  - **Monk**: Uncanny Metabolism at L2 (alongside Monk's Focus + Flurry
    of Blows / Patient Defense / Step of the Wind).
  - **All classes**: **Ability Score Improvement** entries at L4/8/12/16
    (Fighter also 6/14; Rogue also 10) and **Epic Boon** at L19 now show
    up as their own features.
- [ ] **SRD 5.2.1 compliance — spell schools shifted (2026-07-11).** In the
  spell picker or a spell's detail view, verify: **Cure Wounds** → Abjuration,
  **Poison Spray** → Necromancy, **Acid Splash** → Evocation, **Mass Heal** →
  Abjuration. Older lists had these under different schools.

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

## Spell effects on the sheet (new 2026-06-27)

Spells can now change the caster's sheet on cast, and impose-condition spells
offer an apply button (one-PC app — no enemy sheet).

- [ ] **False Life grants temp HP.** Cast False Life (a leveled spell — tap a
  slot) → the character gains 2d4+4 temp HP (rolled). Re-casting takes the
  higher value, doesn't stack.
- [ ] **Control spells offer "Apply to this character".** Open Hold Person /
  Fear / Ray of Sickness / Charm Monster in the cast sheet → an "Imposes"
  section shows an **Apply Paralyzed/Frightened/Poisoned/Charmed** button.
  Tapping it adds the condition to the character; the button then reads
  "applied" and disables.
- [ ] **Applied debuff actually bites.** Apply Poisoned via Ray of Sickness →
  go roll a skill/attack → it's at disadvantage (condition enforcement). Apply
  Paralyzed → the character shows the condition badge.
- [ ] **Plain damage spells have no effect section.** Fire Bolt / Magic Missile
  show no "Imposes" section.
- [ ] _Note:_ debuffs land on **your** character (honor-system, for when you're
  the target) — there's no enemy sheet to target.

## Condition enforcement (new 2026-06-27)

Tracked conditions now actually change d20 rolls (attacks, ability/skill checks,
saves) — for the rolling character. (`attacksAgainst…` effects act on the
attacker, so they're not applied to the afflicted character's own dice.)

- [ ] **Poisoned → disadvantage.** Add Poisoned to a character; a weapon attack
  rolls **2d20 keep-lowest**, and any skill/ability check does too (label notes
  "Disadvantage"). Saves are unaffected by Poisoned.
- [ ] **Invisible → attack advantage.** An Invisible character's attacks roll
  2d20 keep-highest.
- [ ] **Restrained → DEX saves only.** A Restrained character's **Dexterity**
  save rolls disadvantage; a Wisdom save rolls normally. (Restrained also gives
  attack disadvantage.)
- [ ] **Advantage + disadvantage cancel.** Poisoned, then tap the skill's
  **Advantage** chip → it rolls a normal single d20 (the two cancel per 5e).
- [ ] **Weapon attacks honor conditions** even though they have no adv/dis
  chips (applied automatically in the handoff).
- [ ] **Spell attacks combine sources.** A Poisoned Sorcerer with Innate Sorcery
  active (advantage) casting a spell attack → the advantage and disadvantage
  cancel to a normal roll.
- [ ] **Damage unaffected.** Conditions change only the d20 (attack/check/save),
  never damage dice.
- [ ] **STR/DEX saves auto-fail (new 2026-06-27).** Add Paralyzed (or Stunned)
  to a character, then tap a **Strength** or **Dexterity** save → an alert
  "Save auto-fails" appears and **no roll happens**. A Wisdom save still rolls
  normally. Remove the condition → STR/DEX saves roll again.
- [ ] **Armor Stealth disadvantage (new 2026-06-27).** Equip Chain Mail (or any
  medium/heavy armor flagged `stealthDisadvantage`), then roll a **Stealth**
  check → it rolls 2d20 keep-lowest and the label notes "Disadvantage". Other
  Dexterity skills are unaffected. Unequip → Stealth rolls normally.

## Structural P0 fixes (2026-06-27)

- [ ] **Stroke of Luck replaces the right roll.** As a Rogue 20 with Stroke of
  Luck available, roll an attack that offers the prompt; roll something else in
  the dice tab without tapping it; then tap Stroke of Luck → history shows the
  forced-20 result and the *unrelated* roll is untouched (previously it deleted
  the wrong entry). With a multi-d20 formula, every d20 is forced to 20.
- [ ] **Stroke of Luck doesn't leak.** Do a character info-only action (e.g. a
  save DC), then a manual dice-tab roll → no Stroke of Luck prompt appears for
  the manual roll.
- [ ] **Bad content degrades, doesn't crash.** (Dev) Corrupt a bundled
  `Content/*.json` and launch → app still opens; Settings shows a "Content
  Problems" warning instead of a crash.
- [ ] **Colliding pack names don't overwrite.** Import two packs named "Pack 1"
  and "Pack!1" → both appear in Settings (distinct files). Re-importing "Pack 1"
  replaces only itself.
- [ ] **Rollable resource cost spent only on the roll.** Tap a feature that
  rolls *and* costs a use (e.g. Second Wind), switch tabs **without** rolling →
  the use is NOT spent. Actually roll it → the use is spent once. (Action Surge,
  no roll, still spends on tap; Rage still spends when toggled on.)

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

### Druid + spell preparation (new 2026-07-01)
- [ ] **Create a Druid** — Wisdom caster, d8 HP, Light armor + Shields + Simple
  weapons, INT & WIS saves. Creation offers 2 skills from the Druid list and a
  Primal Order pick (Magician / Warden).
- [ ] **Full-caster slots** — a level-3 Druid has 4× L1 and 2× L2 slots in the
  Spells card.
- [ ] **Wild Shape** appears as a **Bonus Action** on the Actions tab with a
  **2-use** pool (3 at L6, 4 at L17); tapping consumes a use; Short Rest gives
  one back, Long Rest refills.
- [ ] **Circle of the Land at L3** — subclass picker offers it; choosing it
  prompts a land type (Arid/Polar/Temperate/Tropical) and lists Land's Aid,
  Natural Recovery (L6), Nature's Ward (L10), Nature's Sanctuary (L14).
- [ ] **Prepare Spells button** — the Spells card shows **"Prepared: X / N"**
  (N = WIS mod + Druid level) and a **"Prepare Spells"** button (not "Add
  Spell").
- [ ] **Prep picker is class-filtered** — tapping Prepare Spells lists **only
  Druid spells** (Druidcraft, Cure Wounds, Faerie Fire, Hold Person, …); Fire
  Bolt / Magic Missile do **not** appear.
- [ ] **Prepare / unprepare toggles** — tap a leveled spell to prepare it
  (green check); tap again to unprepare. The "Leveled prepared: X / N" counter
  updates live.
- [ ] **Cap enforced** — once leveled prepared hits N, un-prepared leveled
  spells show a slashed circle and can't be added until you unprepare one.
  Cantrips have their own "x / y" budget.
- [ ] **Daily re-prep** — you can freely unprepare and prepare different spells
  (models "change your prepared list after a long rest").
- [ ] **Fresh Druid isn't over-prepared** — a newly created Druid starts with a
  prepared list capped at N leveled spells (all Druid-list), not every L1 spell.
- [ ] _Known simplifications:_ Wild Shape beast forms aren't modeled (track your
  form + stats manually); per-land circle spell lists are text-only; Natural
  Recovery slot recovery is manual; the "must long-rest to re-prepare" gate is
  honor-system (editing is always allowed).

### Multiclassing (new 2026-07-01)
- [ ] **Class picker at level-up.** On a Druid 2, tap Level Up → a **Class**
  card shows a "Druid L2 → 3" button (selected) and a **"Multiclass into…"**
  menu listing the other classes.
- [ ] **RAW prerequisites hard-block.** A character with WIS 10 opens the
  multiclass menu → **Druid** shows a lock with "Druid needs WIS 13 (you have
  10)" and can't be tapped. A STR 10 Fighter is blocked from adding ANY class
  (fighter's own primary must also be 13+).
- [ ] **Adding a class.** An eligible Druid 2 (WIS 16, STR 13) picks Fighter →
  header reads "Fighter · NEW class → Level 1", the HP card uses **1d10** (not
  1d8), and the card notes what multiclassing grants (Light/Medium armor,
  Shield, Simple/Martial weapons). Finish → sheet header shows
  **"Druid 2 / Fighter 1"**, and the granted proficiencies appear.
- [ ] **No L1 skill picks for the second class.** After adding Fighter, the
  Features tab does **not** offer Fighter's "choose 2 skills" picker (5e
  multiclass rule). The first class's picker is unaffected.
- [ ] **Slot merging.** Level a Druid 2 / Cleric 2 → the Spells card shows ONE
  set of slots: **4× L1 and 3× L2** (combined caster level 4 on the shared
  table), not two separate 3× L1 pools. A Druid 3 / Fighter 2 keeps normal
  Druid slots (one casting class → no merge).
- [ ] **Half-caster counts half.** Druid 3 / Paladin 3 → combined caster level
  4 (3 + 3÷2).
- [ ] **Per-class preparation.** As Druid 3 / Cleric 2 (WIS 16), open Prepare
  Spells → a **class segment picker** appears; Druid shows "Leveled prepared:
  X / 6", Cleric "X / 5", each with its own class-filtered list and bucket.
  The Spells card lists both "Druid prepared: X/6" and "Cleric prepared: X/5".
- [ ] **Casting ability follows the class.** A spell prepared under the Druid
  bucket casts with WIS even when another casting class (different ability)
  is present — check the spell attack/DC math in the cast sheet.
- [ ] **Old saves migrate.** A pre-existing single-class prepared caster loads
  with its prepared list intact (moved into the class bucket invisibly).
- [ ] _Known simplifications:_ known-caster (Bard/Sorcerer) per-level spell
  picks aren't budget-gated; Bard/Rogue multiclass skill/tool CHOICE grants are
  manual; the level-up Spellcasting card diffs the leveled class's own slot
  table, not the merged pools; on the level-up that first merges slots, the
  pools reset to full (old per-class ids are retired).

### Spell class lists, learning budgets & starting spells (new 2026-07-01)
- [ ] **Class-restricted lists.** A Wizard's spell picker no longer shows
  Bless (cleric/paladin only); a Cleric's does. Every picker (Prepare/Learn/
  Add) shows only the class's own list.
- [ ] **Mode titles per class.** Druid/Cleric → "Prepare Spells"; Bard/
  Sorcerer → "Learn Spells" with a "Spells known: X / N" counter; Wizard →
  "Add Spell". A Druid/Sorcerer multiclass shows a class segment picker and
  "Manage Spells" on the button.
- [ ] **Learn budget enforced.** A level-1 Sorcerer can learn at most 2
  leveled spells (bard: 4); at the cap un-learned spells show a slashed
  circle until one is toggled off. Cantrips have their own budget.
- [ ] **Creation Spells step (casters only).** Creating a Druid: after
  Abilities a "Spells" step appears with Cantrips and Level 1 sections, live
  "X / N" counters (druid: 2 cantrips; leveled = WIS mod + 1); creating a
  Fighter skips straight to Review.
- [ ] **Cap + auto-pick in creation.** Over-budget picks are blocked (slashed
  circle); "Auto-pick the rest" fills remaining budget alphabetically; Next
  requires at least one pick.
- [ ] **Created character matches picks.** The finished character's Spells
  card lists exactly the chosen spells (not the whole catalog, which was the
  old behavior).
- [ ] **Level-up prompts spell learning.** Level a Sorcerer 1 → 2 (spells
  known 2 → 4): after Finish, the spell picker opens automatically in Learn
  mode. A Fighter level-up opens no picker.
- [ ] _Known simplifications:_ wizard remains Add mode until spellbook
  management lands; Learn-mode edits aren't time-gated (RAW "swap one spell
  per level-up" is honor-system); auto-seed still applies to drafts that skip
  the step (DEBUG autofill).

### Level-up sheet sync (new 2026-07-01)
- [ ] **HP preview includes feature bonuses.** Level up a **Dwarf** (Dwarven
  Toughness) → the staged HP line shows **+1 more** than die + CON, with an
  "incl. +1 from features" caption, and the committed max matches the preview
  exactly. A Draconic Sorcerer shows the same (+1/level).
- [ ] **Subclass unlock callout.** Level a Druid (or any class) from 2 → 3 with
  no subclass chosen → a purple banner names the unlock ("Level 3 unlocks your
  Druid subclass — choose it in the Features tab"). After picking a subclass,
  leveling further shows no banner.
- [ ] **Spellcasting card on caster level-ups.** Druid 1 → 2 shows "More slots
  at: L1 (2 → 3)" and "Prepared spells: N → N+1"; Druid 2 → 3 shows "New spell
  slot level: L2"; Druid 3 → 4 shows "Cantrips known: 2 → 3". A Fighter
  level-up shows no Spellcasting card.
- [ ] **New resources appear without any sync step.** Level a Druid 1 → 2 →
  Wild Shape shows up on the Actions tab with a full 2-use pool; the new L1
  slot and (at 3) L2 slots appear in the Spells card already full.

### Warlock (new 2026-07-02)
- [ ] **Create a Warlock.** Charisma caster, d8 HP, Light armor + Simple
  weapons, WIS & CHA saves; class skills step offers 2 of 7 (Arcana,
  Deception, History, Intimidation, Investigation, Nature, Religion). The
  creation Spells step shows only warlock-list spells (Eldritch Blast present;
  Fire Bolt absent) with budgets of 2 cantrips / 2 known spells.
- [ ] **Pact Magic slots.** A level-1 Warlock's Spells card shows ONE slot
  pool (1× L1); at L5 it's **2 slots, both level 3** (no separate L1/L2
  pools). A **Short Rest** refills them (unlike every other caster's slots).
- [ ] **Learn Spells.** The Spells card button reads **"Learn Spells"** with a
  "Spells known: X / N" counter following the Warlock table (2 at L1, 6 at
  L5); at the cap, un-learned spells show a slashed circle until one is
  toggled off.
- [ ] **Eldritch Invocations.** The Features tab shows an invocations picker
  offering **13** options — **1** pick at L1, growing to **3** at L2 (re-open
  the picker after leveling); the feature text notes mechanics are manual.
- [ ] **Level-up prompts spell learning.** Warlock 1 → 2 (spells known 2 → 3,
  second pact slot): after Finish, the spell picker opens automatically.
- [ ] **Fiend Patron at L3.** Subclass picker offers it; choosing it puts
  **Command** in the Granted section of the Spells tab; at L6 **Dark One's Own
  Luck** shows a use pool equal to your CHA modifier; at L14 **Hurl Through
  Hell** is a tappable action rolling **8d10 psychic** with a 1 / Long Rest
  counter.
- [ ] **Multiclass keeps pact separate.** A Druid 3 / Warlock 3 shows the
  normal Druid slots AND the pact slots as separate pools (pact magic is
  excluded from the shared multiclass slot table — no merged pool).
- [ ] _Known simplifications:_ invocation effects are text-only (Agonizing
  Blast's +CHA damage is manual); Eldritch Blast's multi-beam scaling means
  rolling the attack once per beam manually; Dark One's Blessing temp HP is
  applied by hand via the HP editor; Mystic Arcanum spells (L6+) aren't
  bundled; Magical Cunning's slot regain is manual (the 1/LR counter just
  tracks the rite).

### Subclass backfill — Berserker, Devotion, Evoker (new 2026-07-02)
- [ ] **Every class now has a subclass picker.** A Barbarian / Paladin /
  Wizard at L3 offers a subclass picker on the Features tab ("Choose your
  Primal Path" / "Choose your Sacred Oath" / "Choose your Arcane Tradition"),
  and leveling 2 → 3 without one shows the purple subclass-unlock banner.
- [ ] **Frenzy rider (Berserker).** With Path of the Berserker picked and a
  melee weapon equipped, a weapon attack shows a **"Frenzy"** toggle chip that
  adds **2d6** (weapon-typed) to the damage roll; at L9 it's **3d6**; after
  using it, the chip greys out until **Start New Turn**. The Rage-active +
  Reckless-Attack requirement is a note in the feature text, not enforced.
- [ ] **Intimidating Presence (Berserker L14).** Appears as a **Bonus Action**
  row showing a **Strength-based save DC** with a **1 / Long Rest** counter.
- [ ] **Devotion oath spells.** Picking Oath of Devotion at L3 puts **Shield
  of Faith** in the Granted section of the Spells tab (castable — its +2 AC
  buff applies); the other oath spells are listed as text.
- [ ] **Holy Nimbus (Devotion L20).** A **Bonus Action** with a **1 / Long
  Rest** counter; its damage/advantage effects are manual.
- [ ] **Evoker.** All five features (Evocation Savant + Potent Cantrip at L3,
  Sculpt Spells L6, Empowered Evocation L10, Overchannel L14) appear at their
  levels as text; no action rows expected.
- [ ] _Known simplifications:_ Frenzy's Rage/Reckless gate, Sacred Weapon's
  +CHA attack bonus, Mindless Rage's condition immunity, and the Sculpt
  Spells / Potent Cantrip / Overchannel math are all manual.

### Monk (new 2026-07-06)
- [ ] **Create a Monk.** DEX/WIS class, d8 HP, **no** armor proficiencies,
  STR & DEX saves; class skills step offers 2 of 6 (Acrobatics, Athletics,
  History, Insight, Religion, Stealth); no Spells step appears (non-caster).
  The sheet's unarmored AC is **10 + DEX + WIS**.
- [ ] **Unarmed Strike.** The Actions tab shows a Martial Arts / Unarmed
  Strike row: the attack rolls **d20 + DEX + PB**, and the damage rolls
  **1d6 + DEX** at L1 — level up and re-check: **1d8** at L5, **1d10** at
  L11, **1d12** at L17.
- [ ] **Focus points (L2).** A **"Focus Points"** pool (2/2) appears in the
  resources card and refills on a **Short Rest**. Flurry of Blows / Patient
  Defense / Step of the Wind rows all show the **same shared pool badge**,
  and tapping each debits that one pool by 1.
- [ ] **Unarmored Movement.** At L2 the Speed chip gains **+10 ft** (30 → 40
  for a human); equipping any armor or a shield removes the bonus; at L6
  it's +15.
- [ ] **Deflect Attacks (L3).** A **Reaction** row that rolls
  **1d10 + DEX + monk level**.
- [ ] **Stunning Strike (L5).** Tapping it shows a **Wisdom-based save DC**
  and spends **1 Focus point**.
- [ ] **Superior Defense (L18).** The row greys out when fewer than **3**
  Focus points remain.
- [ ] **Warrior of the Open Hand at L3.** The subclass picker offers it;
  **Wholeness of Body** (L6) rolls the Martial Arts die + WIS with a
  WIS-mod / Long Rest pool; **Quivering Palm** (L17) rolls **10d12 force**
  and costs **4 Focus** (deferred to the roll).
- [ ] _Known simplifications:_ Flurry's second/third strike = tap Unarmed
  Strike again; Extra Attack, Open Hand Technique's rider saves, Heightened
  Focus upgrades, Deflect Attacks' redirect, and Disciplined Survivor's
  reroll are all manual.

### Ranger (new 2026-07-06 — class catalog complete)
- [ ] **Create a Ranger.** Wisdom caster, d10 HP, Light + Medium armor +
  Shield + Simple/Martial weapons, STR & DEX saves; class skills step offers
  **3 of 8** (Animal Handling, Athletics, Insight, Investigation, Nature,
  Perception, Stealth, Survival); no cantrips (the creation Spells step
  shows only a Level 1 section). Even a WIS 8 Ranger shows the prep budget
  as **2 / 2** at L1 (the `spellsKnown` table caps prep, not ability mod).
- [ ] **Half-caster slots.** L1 shows **NO** spell slots (SRD half-caster
  starts at L2). L2 = **2 × L1** slots. L5 = **4 × L1 + 2 × L2** (identical
  to a Paladin at the same level).
- [ ] **Hunter's Mark always prepared.** From L1, **Hunter's Mark** appears
  in the Granted section of the Spells tab; casting it applies the on-damage
  rider chip to weapon attacks (existing Hunter's Mark plumbing). The
  Resources card shows a **"Hunter's Mark (free)"** pool = **2** at L1,
  growing to **3 / 4 / 5** at levels 5 / 13 / 17; casting from that pool
  doesn't spend a slot.
- [ ] **Fighting Style at L2.** The Features picker offers **Archery,
  Defense, Dueling, Two-Weapon Fighting** — **no** Great Weapon Fighting.
  Archery adds +2 to ranged attack rolls; the others behave as before.
- [ ] **Weapon Mastery at L1.** Picker for **2** weapons; at **L9** the same
  picker reopens for a **3rd** choice.
- [ ] **Expertise at L2 and L9.** Two independent skill pickers (Deft
  Explorer at L2, Expertise at L9); a chosen skill's dot upgrades to the
  yellow expertise star.
- [ ] **Roving at L5.** Speed chip **+10 ft** while unarmored (30 → 40 for a
  human); equipping any heavy armor removes it. (Known simplification: the
  SRD's "not wearing Heavy armor" is honored as app-level "unarmored" —
  swap heavy armor manually if you're testing light/medium.)
- [ ] **Multiclass caster level.** A Druid 3 / Ranger 4 shows merged
  multiclass slot pools at combined caster level **5** (druid 3 + ranger
  4 ÷ 2), not the ranger's own pools.
- [ ] **Hunter at L3.** Subclass picker offers Hunter; picking it exposes
  **Colossus Slayer** as an opt-in toggle chip on weapon attacks adding
  **1d8 weapon-typed damage**, greying out after use until **Start New
  Turn**.
- [ ] **Hunter L7 / L11 / L15 features.** Escape the Horde (L7), Evasion
  (L11), and Superior Hunter's Prey (L15) appear as text-only features on
  the Features tab.
- [ ] _Known simplifications:_ Hunter's Prey / Defensive Tactics / Superior
  Hunter's Defense each have 3 SRD options — only one authored per tier
  (swap manually); Foe Slayer +1d10, Precise Hunter advantage, Relentless
  Hunter concentration protection, Feral Senses blindsight, and Superior
  Prey's d10 bump are all text — apply manually.

---

## P1 rules-fidelity batch (new 2026-06-27)

### Natural 1 suppresses the damage chip
- [ ] Tap a weapon **Attack**; on the dice tab, roll a **natural 1** on the
  attack d20 → the follow-up rail shows **"Natural 1 — miss. No damage."** and
  the "Roll damage" chip + any rider toggles are hidden.
- [ ] Roll a non-1 attack → the damage chip + riders appear as before.

### Choose-damage spells
- [ ] Cast **Chromatic Orb** → a **Damage type** picker shows 6 options (acid,
  cold, fire, lightning, poison, thunder). Pick **cold**, roll damage → the
  result breakdown reads **cold** (not fire).
- [ ] Cast **Dragon's Breath** → picker shows 5 options; the chosen type carries
  into the damage roll.
- [ ] A fixed-type damage spell (e.g. Fire Bolt) shows **no** type picker.

### Fighting Styles — Great Weapon Fighting & Two-Weapon Fighting
- [ ] A Fighter with **Great Weapon Fighting** wielding a **Greatsword** (or a
  longsword's **2H** damage) → the damage roll **rerolls 1s and 2s** once
  (description shows "(reroll 1-2)"); a one-handed longsword swing does **not**.
- [ ] A Fighter with **Two-Weapon Fighting** — verify the engine restores the
  ability mod to an off-hand (mod-less) attack. _Note: a separate off-hand
  attack row isn't generated yet, so this is mostly engine-level for now._
- [ ] Archery / Dueling / Defense still behave as before (no regression).

### Weapon Mastery — resolved mechanics
- [ ] Equip a **Quarterstaff** (Topple) with the Weapon Mastery feature + it
  selected → tap the **Topple** badge → the sheet shows **"…DC N Constitution
  save or falls Prone"** with N computed (8 + attack mod + PB).
- [ ] Equip a **Greatsword** (Graze) similarly → the badge detail shows
  **"On a miss: deal N <type> damage"** with N = your attack ability mod.
- [ ] Sap/Slow/Nick/Vex masteries still show their rule text (narrative — no
  enemy sheet).

### Buff spells touch the sheet
- [ ] Cast **Shield of Faith** (concentration) → **AC goes up by 2**; an
  effect pill appears. Drop concentration → AC returns and the pill clears.
- [ ] Cast **Shield** (reaction, 1 round) → **AC +5**; tap **Start New Turn** →
  the buff expires and AC returns.
- [ ] Cast **Mage Armor** while **unarmored** → AC becomes **13 + DEX** (pill
  shows "Unarmored AC base 13"). With body armor equipped it has no effect.
- [ ] Cast **Bless** → tap a weapon **Attack**, a **spell attack**, and a
  **saving throw** → each rolls an extra **1d4** (label notes "+Bless"). Ability
  and skill checks do **not** get the d4. Drop concentration → the d4 stops.
- [ ] Cast **Longstrider** → **Speed increases by 10 ft**. Dismiss the pill →
  speed returns.
- [ ] Shield + Shield of Faith together → **AC +7** (they stack).

## Backlog to backfill (older features, not yet itemized here)

These shipped before this doc existed; add cases on demand when we next touch
them or when you want a full regression pass:

- [ ] Dice roller (3D tray, formulas, history, presets, advantage/disadvantage)
- [ ] Character sheet core (HP/CON, AC, initiative, rest, conditions,
  concentration, inventory/attunement)
- [ ] Class progression (leveling, subclasses, Expertise, Sneak Attack, Rage,
  Divine Smite, spell slots)
- [ ] Content import/export & SRD attribution
